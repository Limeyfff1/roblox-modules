
local Comm = {}

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local PREFIX = "AllyComm_"
local MAX_MESSAGES = 500

local lastSeen = {}
local counter = 0
local sessionId = HttpService:GenerateGUID(false)

local function getFile(userId)
    return PREFIX .. tostring(userId) .. ".txt"
end

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

    -- Support the old single-message format.
    if data.senderId and data.command then
        return { data }
    end

    return {}
end

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

    counter += 1

    local packet = {
        id = counter,
        sessionId = sessionId,
        senderId = LocalPlayer.UserId,
        senderTeam = LocalPlayer.TeamColor.Name,
        targetTeam = targetTeam,
        command = encodeValue(command)
    }

    table.insert(queue, packet)

    -- Limit file growth.
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

            if packet.senderId ~= player.UserId then
                continue
            end

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

            if packetId <= previousId then
                continue
            end

            local success, decoded = pcall(function()
                return decodeValue(packet.command)
            end)

            if success and type(decoded) == "table" then
                lastSeen[seenKey] = packetId

                table.insert(messages, {
                    sender = player,
                    command = decoded
                })
            else
                warn("[Comm] Could not decode message:", packetId)
            end
        end
    end

    return messages
end

return Comm
