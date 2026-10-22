local Comm = {}

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local PREFIX = "AllyComm_"
local lastSeen = {}
local counter = 0

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
        return CFrame.new(unpack(value.components))
    end

    local result = {}

    for key, item in pairs(value) do
        result[key] = decodeValue(item)
    end

    return result
end

function Comm.Send(targetTeam, command)
    if type(command) ~= "table" then
        return false
    end

    counter += 1

    local packet = {
        id = counter,
        senderId = LocalPlayer.UserId,
        senderTeam = LocalPlayer.TeamColor.Name,
        targetTeam = targetTeam,
        command = encodeValue(command)
    }

    local success, err = pcall(function()
        writefile(
            getFile(LocalPlayer.UserId),
            HttpService:JSONEncode(packet)
        )
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

        if not isfile(file) then
            continue
        end

        local success, packet = pcall(function()
            return HttpService:JSONDecode(readfile(file))
        end)

        if not success or type(packet) ~= "table" then
            continue
        end

        if packet.senderId ~= player.UserId then
            continue
        end

        if packet.targetTeam ~= LocalPlayer.TeamColor.Name then
            continue
        end

        if packet.id == lastSeen[player.UserId] then
            continue
        end

        lastSeen[player.UserId] = packet.id

        table.insert(messages, {
            sender = player,
            command = decodeValue(packet.command)
        })
    end

    return messages
end

return Comm
