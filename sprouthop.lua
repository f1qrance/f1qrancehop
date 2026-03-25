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

local function safeDestroyGui()
    local old = CoreGui:FindFirstChild("BSS_UI")
    if old then
        old:Destroy()
    end
end

local function isSprout(server)
    return tostring(server.type or "") == "Sprout"
end

local function isVicious(server)
    return tostring(server.type or "") == "Vicious"
end

local function getServerColor(server)
    if isVicious(server) and server.gifted == true then
        return "#f5ce0a"
    end

    if isVicious(server) then
        return "#85C5FF"
    end

    local rarity = tostring(server.rarity or "")

    if rarity == "Supreme" then
        return "#7DEC66"
    elseif rarity == "Legendary" then
        return "#3AD5EA"
    elseif rarity == "Epic" then
        return "#BEC459"
    elseif rarity == "Rare" then
        return "#BBB9BC"
    elseif rarity == "Gummy" then
        return "#6E324E"
    elseif rarity == "Festive" then
        return "#6B273D"
    end

    return "#FFFFFF"
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
        return 50
    elseif isSprout(server) and rarity == "Rare" then
        return 40
    end

    return 0
end

local function getCooldownForServer(server)
    if isSprout(server) and server.rarity == "Supreme" then
        return 60
    elseif isSprout(server) and server.rarity == "Legendary" then
        return 55
    elseif isVicious(server) and server.gifted == true then
        return 45
    elseif isVicious(server) then
        return 40
    end

    return 50
end

local function shouldForceTeleport(best)
    if not best then
        return false
    end

    local currentType = getgenv().BSS_CURRENT_SERVER_TYPE
    local currentRarity = getgenv().BSS_CURRENT_SERVER_RARITY

    local isCurrentLow =
        (currentType == "Sprout" and (currentRarity == "Rare" or currentRarity == "Epic")) or
        (currentType == "Vicious")

    local isTargetHigh =
        (isSprout(best) and (best.rarity == "Supreme" or best.rarity == "Legendary"))

    return isCurrentLow and isTargetHigh
end

local function isInRecent(jobId)
    for _, v in ipairs(RECENT) do
        if v == jobId then
            return true
        end
    end
    return false
end

local function pushRecent(jobId)
    if not jobId or jobId == "" then
        return
    end

    for i = #RECENT, 1, -1 do
        if RECENT[i] == jobId then
            table.remove(RECENT, i)
        end
    end

    table.insert(RECENT, 1, jobId)

    while #RECENT > RECENT_LIMIT do
        table.remove(RECENT, #RECENT)
    end
end

local function markCurrentServer()
    local currentJobId = game.JobId
    if currentJobId and currentJobId ~= "" then
        VISITED[currentJobId] = true
        pushRecent(currentJobId)
    end
end

local function hasTooManyPlayers(server)
    local players = tonumber(server.playerCount) or 0
    return players > MAX_PLAYERS
end

local function isValidServer(server)
    if not server.jobId then
        return false
    end

    if server.jobId == game.JobId then
        return false
    end

    if VISITED[server.jobId] then
        return false
    end

    if isInRecent(server.jobId) then
        return false
    end

    if hasTooManyPlayers(server) then
        return false
    end

    if isSprout(server) then
        local remaining = getRemainingSeconds(server)

        if remaining <= 0 then
            return false
        end

        if remaining < MIN_SPROUT_SECONDS then
            return false
        end
    end

    return getPriority(server) > 0
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
        warn("API error:", res and res.Body or "no response")
        return {}
    end

    local ok, data = pcall(function()
        return HttpService:JSONDecode(res.Body)
    end)

    if not ok or not data then
        warn("JSON decode error")
        return {}
    end

    return data.results or {}
end

local function isBetterServer(candidate, best)
    if not candidate then
        return false
    end

    if not best then
        return true
    end

    local cp = getPriority(candidate)
    local bp = getPriority(best)

    if cp > bp then
        return true
    elseif cp < bp then
        return false
    end

    if isSprout(candidate) and isSprout(best) then
        local cr = getRemainingSeconds(candidate)
        local br = getRemainingSeconds(best)

        if cr < br then
            return true
        elseif cr > br then
            return false
        end
    end

    if isVicious(candidate) and isVicious(best) then
        local cl = tonumber(candidate.level) or 0
        local bl = tonumber(best.level) or 0

        if cl > bl then
            return true
        elseif cl < bl then
            return false
        end
    end

    local cPlayers = tonumber(candidate.playerCount) or 999
    local bPlayers = tonumber(best.playerCount) or 999

    return cPlayers < bPlayers
end

local function pickBestServer(servers)
    local best = nil

    for _, server in ipairs(servers) do
        if isValidServer(server) then
            if isBetterServer(server, best) then
                best = server
            end
        end
    end

    return best
end

local function sortServersForUi(servers)
    local copy = {}

    for _, server in ipairs(servers) do
        table.insert(copy, server)
    end

    table.sort(copy, function(a, b)
        if isBetterServer(a, b) then
            return true
        elseif isBetterServer(b, a) then
            return false
        end
        return false
    end)

    return copy
end

safeDestroyGui()

-- GUI setup code тут (не трогаем, как было)

markCurrentServer()

while true do
    task.wait(CHECK_DELAY)

    local servers = fetchValidated()
    local best = pickBestServer(servers)

    local joinedAgo = tick() - getgenv().BSS_SERVER_JOIN_TIME
    local dynamicCooldown = getgenv().BSS_NEXT_TELEPORT_COOLDOWN or TELEPORT_COOLDOWN
    local force = shouldForceTeleport(best)

    updateTopInfo(best, force, joinedAgo, dynamicCooldown)
    updateServerList(servers, best)

    if not force and joinedAgo < dynamicCooldown then
        print("[JOIN COOLDOWN]", math.ceil(dynamicCooldown - joinedAgo), "sec left")
        continue
    end

    if best then
        local remaining = getRemainingSeconds(best)

        print("========== SELECTED ==========")
        print("Type:", best.type)
        print("Rarity:", best.rarity)
        print("Field:", best.field)
        print("Players:", best.playerCount)
        print("Gifted:", best.gifted)
        print("Level:", best.level)
        print("Priority:", getPriority(best))
        print("Remaining:", remaining == math.huge and "INF" or remaining)
        print("JobId:", best.jobId)
        print("==============================")

        VISITED[best.jobId] = true
        pushRecent(best.jobId)

        getgenv().BSS_CURRENT_SERVER_TYPE = best.type
        getgenv().BSS_CURRENT_SERVER_RARITY = best.rarity
        getgenv().BSS_NEXT_TELEPORT_COOLDOWN = getCooldownForServer(best)
        getgenv().BSS_SERVER_JOIN_TIME = tick()

        TeleportService:TeleportToPlaceInstance(placeId, best.jobId, LocalPlayer)
        task.wait(3)

        -- ВАША ВСТАВКА ДЛЯ ФАРМА СПРАУТОВ
        local targetSprout
        local farmedAt

        do
            for _, v in ipairs(workspace:GetDescendants()) do
                if v.Name:lower():find("sprout") then
                    targetSprout = v
                    break
                end
            end

            if targetSprout then
                local conn
                conn = targetSprout.AncestryChanged:Connect(function()
                    farmedAt = tick()
                    conn:Disconnect()
                end)
            end
        end

        while true do
            if not targetSprout or (farmedAt and (tick() - farmedAt) > 30) then break end
            -- бегаешь по полю, фармишь всё
            task.wait()
        end
    else
        print("[SCAN] Нет подходящих validated серверов")
    end
end
