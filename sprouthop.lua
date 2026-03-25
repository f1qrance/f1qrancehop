local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local userId = getgenv().BSS_USER_ID
local secretKey = getgenv().BSS_SECRET_KEY

if not userId or not secretKey then
    warn("Missing USER_ID or SECRET_KEY")
    return
end

local placeId = game.PlaceId

local TELEPORT_COOLDOWN = 55
local CHECK_DELAY = 1
local MIN_SPROUT_SECONDS = 30
local MAX_PLAYERS = 4
local RECENT_LIMIT = 5

getgenv().BSS_VISITED_JOB_IDS = getgenv().BSS_VISITED_JOB_IDS or {}
getgenv().BSS_RECENT_JOB_IDS = getgenv().BSS_RECENT_JOB_IDS or {}
getgenv().BSS_SERVER_JOIN_TIME = getgenv().BSS_SERVER_JOIN_TIME or tick()

getgenv().BSS_CURRENT_SERVER_TYPE = getgenv().BSS_CURRENT_SERVER_TYPE or nil
getgenv().BSS_CURRENT_SERVER_RARITY = getgenv().BSS_CURRENT_SERVER_RARITY or nil
getgenv().BSS_NEXT_TELEPORT_COOLDOWN = getgenv().BSS_NEXT_TELEPORT_COOLDOWN or TELEPORT_COOLDOWN

local VISITED = getgenv().BSS_VISITED_JOB_IDS
local RECENT = getgenv().BSS_RECENT_JOB_IDS

-- 🌱 ФАРМ ПЕРЕМЕННЫЕ
local targetSprout = nil
local farmedAt = nil

local function isSprout(server)
    return tostring(server.type or "") == "Sprout"
end

local function isVicious(server)
    return tostring(server.type or "") == "Vicious"
end

local function getRemainingSeconds(server)
    if not server.expiryAt then
        return math.huge
    end

    local expiry = tonumber(server.expiryAt)
    if not expiry then
        return math.huge
    end

    return expiry - os.time()
end

local function getPriority(server)
    local rarity = tostring(server.rarity or "")

    if isSprout(server) and rarity == "Supreme" then
        return 100
    elseif isSprout(server) and rarity == "Legendary" then
        return 90
    elseif isSprout(server) and rarity == "Festive" then
        return 85
    elseif isVicious(server) and server.gifted == true then
        return 80
    elseif isSprout(server) and rarity == "Gummy" then
        return 70
    elseif isSprout(server) and rarity == "Epic" then
        return 60
    elseif isVicious(server) then
        return 10 -- самый низ
    elseif isSprout(server) and rarity == "Rare" then
        return 40
    end

    return 0
end

local function fetchValidated()
    local url = ("https://bss-tools.com/api/workspaces/%s/validated"):format(userId)

    local res = request({
        Url = url,
        Method = "GET",
        Headers = {
            ["secret-key"] = secretKey
        }
    })

    if not res or res.StatusCode ~= 200 then
        return {}
    end

    local ok, data = pcall(function()
        return HttpService:JSONDecode(res.Body)
    end)

    if not ok or not data then
        return {}
    end

    return data.results or {}
end

local function pickBestServer(servers)
    local best = nil

    for _, s in ipairs(servers) do
        if s.jobId and s.jobId ~= game.JobId then
            if not best or getPriority(s) > getPriority(best) then
                best = s
            end
        end
    end

    return best
end

while true do
    task.wait(CHECK_DELAY)

    local servers = fetchValidated()
    local best = pickBestServer(servers)

    if best then
        TeleportService:TeleportToPlaceInstance(placeId, best.jobId, LocalPlayer)

        -- ⏳ ждём загрузку
        task.wait(6)

        -- 🔍 ищем спроут
        targetSprout = nil
        farmedAt = nil

        for _, v in ipairs(workspace:GetDescendants()) do
            if v.Name:lower():find("sprout") then
                targetSprout = v
                break
            end
        end

        -- 🔗 отслеживание уничтожения
        if targetSprout then
            local conn
            conn = targetSprout.AncestryChanged:Connect(function()
                farmedAt = tick()
                conn:Disconnect()
            end)
        end

        -- 🌾 ФАРМ
        while true do
            if not targetSprout or (farmedAt and (tick() - farmedAt) > 30) then
                break
            end

            task.wait()
        end
    end
end
