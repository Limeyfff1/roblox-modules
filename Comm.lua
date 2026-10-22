
local Comm = {}

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local PREFIX = "AllyComm_"
local MESSAGE_LIFETIME = 5
local MAX_MESSAGES = 500

local lastSeen = {}
local counter = 0
local sessionId = HttpService:GenerateGUID(false)

local function getFile(userId)
    return PREFIX .. tostring(userId) .. ".txt"
end

local function getTime()
    return DateTime.now().UnixTimestampMillis
end

-- Convert Roblox datatypes into JSON-compatible values
local function encodeValue(value)
    local kind = typeof(value)

    if kind == "Vector3" then
        return {
            __type = "Vector3",
            x = value.X,
            y = value.Y,
            z = value.Z
        }

    elseif kind == "CFrame" then
        return {
            __type = "CFrame",
            components = { value:GetComponents() }
        }

    elseif kind == "table" then
        local result = {}

        for key, item in pairs(value) do
            result[key] = encodeValue(item)
        end

        return result
    end

    return value
end

-- Restore Roblox datatypes after reading JSON
local function decodeValue(value)
    if type(value) ~= "table" then
        return value
    end

    if value.__type == "Vector3" then
        return Vector3.new(value.x, value.y, value.z)

    elseif value.__type == "CFrame" then
        return CFrame.new(table.unpack(value.components))
    end

    local result = {}

    for key, item in pairs(value) do
        result[key] = decodeValue(item)
    end

    return result
end

-- Read a sender's queue
local function readQueue(file)
    if not isfile(file) then
        return {}
    end

    local success, data = pcall(function()
        return HttpService:JSONDecode(readfile(file))
    end)

    if not success or type(data) ~= "table" then
        return nil
    end

    if type(data.messages) == "table" then
        return data.messages
    end

    -- Compatibility with the original single-message format
    if data.senderId and data.command then
        return { data }
    end

    return {}
end

-- Check whether a packet has expired
local function isExpired(packet)
    if type(packet) ~= "table" then
        return true
    end

    if type(packet.timestamp) ~= "number" then
        return true
    end

    local age = getTime() - packet.timestamp

    return age >= MESSAGE_LIFETIME * 1000
end

-- Remove expired packets from a queue
local function removeExpired(queue)
    for i = #queue, 1, -1 do
        if isExpired(queue[i]) then
            table.remove(queue, i)
        end
    end

    return queue
end

-- Send a command to an allied team
function Comm.Send(targetTeam, command)
    if type(targetTeam) ~= "string"
        or type(command) ~= "table" then
        return false
    end

    local file = getFile(LocalPlayer.UserId)

    local queue = readQueue(file)

    if not queue then
        warn("[Comm] Could not read queue:", file)
        return false
    end

    -- Clean up old messages before adding a new one
    removeExpired(queue)

    counter += 1

    local packet = {
        id = counter,
        sessionId = sessionId,
        timestamp = getTime(),
        senderId = LocalPlayer.UserId,
        senderTeam = LocalPlayer.TeamColor.Name,
        targetTeam = targetTeam,
        command = encodeValue(command)
    }

    table.insert(queue, packet)

    -- Prevent the file from growing too large
    while #queue > MAX_MESSAGES do
        table.remove(queue, 1)
    end

    local success, err = pcall(function()
        writefile(file, HttpService:JSONEncode({
            messages = queue
        }))
    end)

    if not success then
        warn("[Comm] Send failed:", err)
    end

    return success
end

-- Receive every new, unexpired command for your team
function Comm.Receive()
    local messages = {}

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then
            continue
        end

        local file = getFile(player.UserId)
        local queue = readQueue(file)

        if not queue then
            continue
        end

        for _, packet in ipairs(queue) do
            if type(packet) ~= "table" then
                continue
            end

            -- Ignore expired commands
            if isExpired(packet) then
                continue
            end

            -- Verify the sender matches the file owner
            if packet.senderId ~= player.UserId then
                continue
            end

            -- Only receive commands addressed to your team
            if packet.targetTeam ~= LocalPlayer.TeamColor.Name then
                continue
            end

            local packetSession = packet.sessionId or "legacy"
            local packetId = tonumber(packet.id)

            if not packetId then
                continue
            end

            local seenKey = tostring(player.UserId)
                .. ":" .. packetSession

            local previousId = lastSeen[seenKey] or 0

            -- Skip commands already received
            if packetId <= previousId then
                continue
            end

            local success, decoded = pcall(function()
                return decodeValue(packet.command)
            end)

            if not success or type(decoded) ~= "table" then
                warn("[Comm] Failed to decode packet:", packetId)
                continue
            end

            lastSeen[seenKey] = packetId

            table.insert(messages, {
                sender = player,
                command = decoded
            })
        end
    end

    return messages
end

-- Periodically clean up this client's own queue,
-- even when no new commands are being sent
function Comm.Cleanup()
    local file = getFile(LocalPlayer.UserId)

    if not isfile(file) then
        return
    end

    local queue = readQueue(file)

    if not queue then
        return
    end

    local previousCount = #queue

    removeExpired(queue)

    if #queue == previousCount then
        return
    end

    local success, err = pcall(function()
        writefile(file, HttpService:JSONEncode({
            messages = queue
        }))
    end)

    if not success then
        warn("[Comm] Cleanup failed:", err)
    end
end

-- Automatically clean up expired messages
task.spawn(function()
    while task.wait(1) do
        Comm.Cleanup()
    end
end)

return Comm
