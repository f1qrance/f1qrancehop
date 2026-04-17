-- ============================================
--  AUTO HOP SCRIPT - ЗАЩИЩЁННАЯ ВЕРСИЯ
-- ============================================

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- ========== ЗАЩИТА ОТ КОНКУРЕНТА ==========
local _GAME = game
local _SERVICE = _GAME:GetService

-- Проверка на хуки
local function isHooked(func)
    if not debug or not debug.getinfo then return false end
    local info = debug.getinfo(func)
    return info and info.what == "Lua"
end

-- Обход перехваченного request
local safeRequest = syn and syn.request or (http_request or request)
if isHooked(safeRequest) then
    safeRequest = function(t)
        return (syn and syn.request or http_request or request)(t)
    end
end

-- Локальное хранилище (не в getgenv!)
local STORAGE = {
    visited = {},
    recent = {},
    joinTime = tick(),
    currentType = nil,
    currentRarity = nil,
    currentField = nil,
    currentJobId = game.JobId,
    nextCooldown = 55,
    uiCollapsed = false,
    ignoreJobId = nil,
    activeTab = "S",
    priorityOrder = {
        "Supreme Sprout",
        "Legendary Sprout", 
        "Gifted Vicious",
        "Festive Sprout",
        "Epic Sprout",
        "Gummy Sprout",
        "Rare Sprout",
        "Vicious"
    }
}

-- Геттеры/сеттеры для удобства
local function get(k) return STORAGE[k] end
local function set(k, v) STORAGE[k] = v end

-- Конфиг
local CONFIG = {
    TELEPORT_COOLDOWN = 55,
    CHECK_DELAY = 1,
    MIN_SPROUT_SECONDS = 40,
    MAX_PLAYERS = 4,
    RECENT_LIMIT = 5,
    VISITED_LIMIT = 100,
    WAIT_AFTER_DESPAWN = 30,
    WORLD_LOAD_DELAY = 5,
    MAX_TRACK_TIME = 60,
    MAX_HP_STUCK_TIME = 30
}

local userId = getgenv().BSS_USER_ID
local secretKey = getgenv().BSS_SECRET_KEY

if not userId or not secretKey then
    warn("[AH] Missing USER_ID or SECRET_KEY")
    return
end

local placeId = game.PlaceId

-- ========== ОСНОВНЫЕ ФУНКЦИИ ==========
local function log(...) print("[AH]", ...) end
local function warnf(...) warn("[AH]", ...) end

local function isSprout(server) return tostring(server.type or "") == "Sprout" end
local function isVicious(server) return tostring(server.type or "") == "Vicious" end

local function getServerColor(server)
    if isVicious(server) and server.gifted == true then return "#f5ce0a" end
    if isVicious(server) then return "#85C5FF" end
    local rarity = tostring(server.rarity or "")
    if rarity == "Supreme" then return "#7DEC66"
    elseif rarity == "Legendary" then return "#3AD5EA"
    elseif rarity == "Epic" then return "#BEC459"
    elseif rarity == "Rare" then return "#BBB9BC"
    elseif rarity == "Gummy" then return "#6E324E"
    elseif rarity == "Festive" then return "#6B273D"
    end
    return "#FFFFFF"
end

local function getRemainingSeconds(server)
    if not server.expiryAt then return math.huge end
    local expiry = tonumber(server.expiryAt)
    if not expiry then return math.huge end
    return expiry - os.time()
end

local function getServerLabel(server)
    local rarity = tostring(server.rarity or "")
    if isSprout(server) and rarity == "Supreme" then return "Supreme Sprout"
    elseif isSprout(server) and rarity == "Legendary" then return "Legendary Sprout"
    elseif isVicious(server) and server.gifted == true then return "Gifted Vicious"
    elseif isSprout(server) and rarity == "Festive" then return "Festive Sprout"
    elseif isSprout(server) and rarity == "Epic" then return "Epic Sprout"
    elseif isSprout(server) and rarity == "Gummy" then return "Gummy Sprout"
    elseif isSprout(server) and rarity == "Rare" then return "Rare Sprout"
    elseif isVicious(server) then return "Vicious"
    end
    return nil
end

local function getPriority(server)
    local label = getServerLabel(server)
    if not label then return 0 end
    for index, value in ipairs(get("priorityOrder")) do
        if value == label then return 100 - index end
    end
    return 0
end

local function getCooldownForServer(server)
    if isSprout(server) and server.rarity == "Supreme" then return 60
    elseif isSprout(server) and server.rarity == "Legendary" then return 55
    elseif isVicious(server) and server.gifted == true then return 55
    elseif isVicious(server) then return 40
    end
    return 50
end

local function hasKnownCurrentServer()
    local currentType = get("currentType")
    if currentType == nil then return false end
    local normalized = tostring(currentType):lower():gsub("^%s+", ""):gsub("%s+$", "")
    return normalized ~= "" and normalized ~= "none" and normalized ~= "unknown"
end

local function hydrateCurrentServerFromList(servers)
    local ignoredJobId = get("ignoreJobId")
    if ignoredJobId and ignoredJobId == game.JobId then return false end
    if hasKnownCurrentServer() then return true end
    for _, server in ipairs(servers) do
        if server.jobId == game.JobId then
            if isVicious(server) and server.gifted == true then
                set("currentRarity", "Gifted")
            else
                set("currentRarity", server.rarity)
            end
            set("currentType", server.type)
            set("currentField", server.field)
            set("currentJobId", server.jobId)
            return true
        end
    end
    return false
end

local function shouldForceTeleport(best)
    if not best then return false end
    local currentType = get("currentType")
    local currentRarity = get("currentRarity")
    local isCurrentLow = (currentType == "Sprout" and (currentRarity == "Rare" or currentRarity == "Epic")) or (currentType == "Vicious")
    local isTargetHigh = (isSprout(best) and (best.rarity == "Supreme" or best.rarity == "Legendary"))
    return isCurrentLow and isTargetHigh
end

local function isInRecent(jobId)
    for _, v in ipairs(get("recent")) do
        if v == jobId then return true end
    end
    return false
end

local function pushRecent(jobId)
    if not jobId or jobId == "" then return end
    local recent = get("recent")
    for i = #recent, 1, -1 do
        if recent[i] == jobId then table.remove(recent, i) end
    end
    table.insert(recent, 1, jobId)
    while #recent > CONFIG.RECENT_LIMIT do table.remove(recent, #recent) end
end

local function countVisited()
    local total = 0
    for _ in pairs(get("visited")) do total += 1 end
    return total
end

local function trimVisited()
    if countVisited() <= CONFIG.VISITED_LIMIT then return end
    local keep = {}
    for _, jobId in ipairs(get("recent")) do keep[jobId] = true end
    keep[game.JobId] = true
    local visited = get("visited")
    for jobId in pairs(visited) do
        if not keep[jobId] then
            visited[jobId] = nil
            if countVisited() <= CONFIG.VISITED_LIMIT then break end
        end
    end
end

local function addVisited(jobId)
    if not jobId or jobId == "" then return end
    get("visited")[jobId] = true
    trimVisited()
end

local function removeRecent(jobId)
    if not jobId or jobId == "" then return end
    local recent = get("recent")
    for i = #recent, 1, -1 do
        if recent[i] == jobId then table.remove(recent, i) end
    end
end

local function markCurrentServer()
    local currentJobId = game.JobId
    if currentJobId and currentJobId ~= "" then
        addVisited(currentJobId)
        pushRecent(currentJobId)
        set("currentJobId", currentJobId)
    end
end

local function hasTooManyPlayers(server)
    local players = tonumber(server.playerCount) or 0
    return players > CONFIG.MAX_PLAYERS
end

local function isValidServer(server)
    if not server.jobId then return false end
    if server.jobId == game.JobId then return false end
    if get("visited")[server.jobId] then return false end
    if isInRecent(server.jobId) then return false end
    if hasTooManyPlayers(server) then return false end
    if isSprout(server) then
        local remaining = getRemainingSeconds(server)
        if remaining <= 0 then return false end
        if remaining < CONFIG.MIN_SPROUT_SECONDS then return false end
    end
    return getPriority(server) > 0
end

local function fetchValidated()
    local url = ("https://bss-tools.com/api/workspaces/%s/validated"):format(userId)
    local okRequest, res = pcall(function()
        return safeRequest({ Url = url, Method = "GET", Headers = {["secret-key"] = secretKey} })
    end)
    if not okRequest then warnf("API request failed") return {} end
    if not res or res.StatusCode ~= 200 then warnf("API error:", res and res.Body or "no response") return {} end
    local ok, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
    if not ok or not data then warnf("JSON decode error") return {} end
    return data.results or {}
end

local function isBetterServer(candidate, best)
    if not candidate then return false end
    if not best then return true end
    local cp = getPriority(candidate)
    local bp = getPriority(best)
    if cp > bp then return true
    elseif cp < bp then return false end
    if isSprout(candidate) and isSprout(best) then
        local cr = getRemainingSeconds(candidate)
        local br = getRemainingSeconds(best)
        if cr < br then return true
        elseif cr > br then return false end
    end
    if isVicious(candidate) and isVicious(best) then
        local cl = tonumber(candidate.level) or 0
        local bl = tonumber(best.level) or 0
        if cl > bl then return true
        elseif cl < bl then return false end
    end
    local cPlayers = tonumber(candidate.playerCount) or 999
    local bPlayers = tonumber(best.playerCount) or 999
    return cPlayers < bPlayers
end

local function pickBestServer(servers)
    local best = nil
    for _, server in ipairs(servers) do
        if isValidServer(server) and isBetterServer(server, best) then
            best = server
        end
    end
    return best
end

-- ========== GUI (скрытый) ==========
local function getGuiParent()
    local success, result = pcall(function()
        return gethui and gethui() or LocalPlayer:WaitForChild("PlayerGui")
    end)
    if success and result then
        return result
    end
    return game:GetService("CoreGui")
end

local function safeDestroyGui()
    local parent = getGuiParent()
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == "AH_Main" then
            child:Destroy()
        end
    end
end

safeDestroyGui()

local gui = Instance.new("ScreenGui")
gui.Name = "AH_Main"
gui.ResetOnSpawn = false
gui.Parent = getGuiParent()

local frame = Instance.new("Frame")
frame.Parent = gui
frame.Size = UDim2.new(0, 350, 0, get("uiCollapsed") and 40 or 480)
frame.Position = UDim2.new(1, -365, 0.5, get("uiCollapsed") and -20 or -240)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
frame.BackgroundTransparency = 0.95
frame.BorderSizePixel = 0

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local header = Instance.new("Frame")
header.Parent = frame
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
header.BackgroundTransparency = 0.95
header.BorderSizePixel = 0

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 8)
headerCorner.Parent = header

local title = Instance.new("TextLabel")
title.Parent = header
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 12, 0, 0)
title.Size = UDim2.new(1, -60, 1, 0)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "H"

local collapseBtn = Instance.new("TextButton")
collapseBtn.Parent = header
collapseBtn.Size = UDim2.new(0, 28, 0, 22)
collapseBtn.Position = UDim2.new(1, -36, 0.5, -11)
collapseBtn.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
collapseBtn.BorderSizePixel = 0
collapseBtn.Font = Enum.Font.GothamBold
collapseBtn.TextSize = 14
collapseBtn.TextColor3 = Color3.fromRGB(230, 230, 235)
collapseBtn.Text = get("uiCollapsed") and "+" or "-"

local collapseCorner = Instance.new("UICorner")
collapseCorner.CornerRadius = UDim.new(0, 5)
collapseCorner.Parent = collapseBtn

local statusTxt = Instance.new("TextLabel")
statusTxt.Parent = frame
statusTxt.BackgroundTransparency = 1
statusTxt.Position = UDim2.new(0, 12, 0, 48)
statusTxt.Size = UDim2.new(1, -24, 0, 18)
statusTxt.Font = Enum.Font.Gotham
statusTxt.TextSize = 12
statusTxt.TextColor3 = Color3.fromRGB(190, 190, 200)
statusTxt.TextXAlignment = Enum.TextXAlignment.Left
statusTxt.Text = "St: init"

local cdTxt = Instance.new("TextLabel")
cdTxt.Parent = frame
cdTxt.BackgroundTransparency = 1
cdTxt.Position = UDim2.new(0, 12, 0, 68)
cdTxt.Size = UDim2.new(1, -24, 0, 18)
cdTxt.Font = Enum.Font.Gotham
cdTxt.TextSize = 12
cdTxt.TextColor3 = Color3.fromRGB(190, 190, 200)
cdTxt.TextXAlignment = Enum.TextXAlignment.Left
cdTxt.Text = "CD: 0s"

local trackerTxt = Instance.new("TextLabel")
trackerTxt.Parent = frame
trackerTxt.BackgroundTransparency = 1
trackerTxt.Position = UDim2.new(0, 12, 0, 88)
trackerTxt.Size = UDim2.new(1, -24, 0, 36)
trackerTxt.Font = Enum.Font.Gotham
trackerTxt.TextSize = 12
trackerTxt.TextColor3 = Color3.fromRGB(150, 150, 160)
trackerTxt.TextXAlignment = Enum.TextXAlignment.Left
trackerTxt.TextWrapped = true
trackerTxt.Text = "Tr: idle"

local hpTxt = Instance.new("TextLabel")
hpTxt.Parent = frame
hpTxt.BackgroundTransparency = 1
hpTxt.Position = UDim2.new(0, 12, 0, 126)
hpTxt.Size = UDim2.new(1, -24, 0, 18)
hpTxt.Font = Enum.Font.Gotham
hpTxt.TextSize = 12
hpTxt.TextColor3 = Color3.fromRGB(205, 205, 215)
hpTxt.TextXAlignment = Enum.TextXAlignment.Left
hpTxt.Text = "HP: - | -"

local targetTxt = Instance.new("TextLabel")
targetTxt.Parent = frame
targetTxt.BackgroundTransparency = 1
targetTxt.Position = UDim2.new(0, 12, 0, 148)
targetTxt.Size = UDim2.new(1, -24, 0, 50)
targetTxt.Font = Enum.Font.Gotham
targetTxt.TextSize = 11
targetTxt.TextColor3 = Color3.fromRGB(220, 220, 230)
targetTxt.TextXAlignment = Enum.TextXAlignment.Left
targetTxt.TextYAlignment = Enum.TextYAlignment.Top
targetTxt.TextWrapped = true
targetTxt.RichText = true
targetTxt.Text = "Curr: none"

local listScroll = Instance.new("ScrollingFrame")
listScroll.Parent = frame
listScroll.BackgroundTransparency = 1
listScroll.BorderSizePixel = 0
listScroll.Position = UDim2.new(0, 8, 0, 210)
listScroll.Size = UDim2.new(1, -16, 1, -218)
listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
listScroll.ScrollBarThickness = 3

local listLayout = Instance.new("UIListLayout")
listLayout.Parent = listScroll
listLayout.Padding = UDim.new(0, 4)

-- Drag
local dragging = false
local dragStart, startPos

header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

collapseBtn.MouseButton1Click:Connect(function()
    local newState = not get("uiCollapsed")
    set("uiCollapsed", newState)
    collapseBtn.Text = newState and "+" or "-"
    statusTxt.Visible = not newState
    cdTxt.Visible = not newState
    trackerTxt.Visible = not newState
    hpTxt.Visible = not newState
    targetTxt.Visible = not newState
    listScroll.Visible = not newState
    frame.Size = UDim2.new(0, 350, 0, newState and 40 or 480)
end)

-- ========== ТРЕКИНГ СПРАУТОВ ==========
local pendingTeleport = nil
local isProcessingSpecial = false
local worldReadyAt = tick() + CONFIG.WORLD_LOAD_DELAY
local targetSprout = nil
local farmedAt = nil
local sproutConn = nil
local targetVicious = nil
local viciousGoneAt = nil
local viciousConn = nil
local viciousHumanoidConn = nil
local currentSproutHP = nil
local currentViciousHP = nil

local function updateTrackerUI(text, color)
    trackerTxt.Text = text
    if color then trackerTxt.TextColor3 = color end
end

local function updateHPUI()
    local sproutText = currentSproutHP and tostring(currentSproutHP) or "-"
    local viciousText = currentViciousHP and tostring(currentViciousHP) or "-"
    hpTxt.Text = "HP: S " .. sproutText .. " | V " .. viciousText
end

local function clearServerList()
    for _, child in ipairs(listScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
end

local function formatServerLine(server)
    local serverType = tostring(server.type or "?")
    local rarity = tostring(server.rarity or "")
    local players = tonumber(server.playerCount) or 0
    local remaining = getRemainingSeconds(server)
    local color = getServerColor(server)
    local nameText
    if isVicious(server) then
        if server.gifted == true then
            nameText = string.format('<font color="%s">G %s</font>', color, serverType)
        else
            nameText = string.format('<font color="%s">%s</font>', color, serverType)
        end
    else
        nameText = string.format('<font color="%s">%s %s</font>', color, rarity:sub(1,3), serverType:sub(1,3))
    end
    local extra = ""
    if isSprout(server) then
        extra = " | " .. (remaining == math.huge and "INF" or tostring(math.max(0, remaining)) .. "s")
    elseif isVicious(server) then
        extra = " | L" .. tostring(server.level or "?")
        if server.gifted then extra = extra .. "|G" end
    end
    return string.format("%s | %dP%s", nameText, players, extra)
end

local function sortServersForUi(servers)
    local copy = {}
    for _, server in ipairs(servers) do
        if isValidServer(server) then table.insert(copy, server) end
    end
    table.sort(copy, function(a, b) return isBetterServer(a, b) end)
    return copy
end

local function updateServerList(servers, best)
    clearServerList()
    local sorted = sortServersForUi(servers)
    local shown = 0
    for _, server in ipairs(sorted) do
        shown += 1
        if shown > 12 then break end
        local item = Instance.new("Frame")
        item.Parent = listScroll
        item.Size = UDim2.new(1, 0, 0, 30)
        item.BackgroundColor3 = (best and server.jobId == best.jobId) and Color3.fromRGB(36, 58, 44) or Color3.fromRGB(28, 28, 34)
        item.BackgroundTransparency = 0.9
        item.BorderSizePixel = 0
        local itemCorner = Instance.new("UICorner")
        itemCorner.CornerRadius = UDim.new(0, 4)
        itemCorner.Parent = item
        local itemText = Instance.new("TextLabel")
        itemText.Parent = item
        itemText.BackgroundTransparency = 1
        itemText.Position = UDim2.new(0, 8, 0, 0)
        itemText.Size = UDim2.new(1, -16, 1, 0)
        itemText.Font = Enum.Font.Gotham
        itemText.TextSize = 11
        itemText.TextColor3 = Color3.fromRGB(235, 235, 240)
        itemText.TextXAlignment = Enum.TextXAlignment.Left
        itemText.RichText = true
        itemText.Text = formatServerLine(server)
    end
    task.wait()
    listScroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y)
end

local function updateTopInfo(best, force, joinedAgo, cooldown)
    local remainingCooldown = math.max(0, math.ceil(cooldown - joinedAgo))
    if force and best then
        statusTxt.Text = "St: force"
        cdTxt.Text = "CD: bypass"
    else
        if remainingCooldown > 0 then
            statusTxt.Text = "St: wait"
            cdTxt.Text = "CD: " .. tostring(remainingCooldown) .. "s"
        else
            statusTxt.Text = "St: ready"
            cdTxt.Text = "CD: 0s"
        end
    end
    
    if best then
        local color = getServerColor(best)
        local remaining = getRemainingSeconds(best)
        local nameText
        if isVicious(best) then
            if best.gifted == true then
                nameText = string.format('<font color="%s">G %s</font>', color, tostring(best.type or "?"))
            else
                nameText = string.format('<font color="%s">%s</font>', color, tostring(best.type or "?"))
            end
        else
            nameText = string.format('<font color="%s">%s %s</font>', color, tostring(best.rarity or "?"), tostring(best.type or "?"))
        end
        local extra = ""
        if isSprout(best) then
            extra = " | " .. (remaining == math.huge and "INF" or tostring(math.max(0, remaining)) .. "s")
        elseif isVicious(best) then
            extra = " | L" .. tostring(best.level or "?")
            if best.gifted then extra = extra .. "|G" end
        end
        targetTxt.Text = string.format("Next: %s | %dP%s", nameText, tostring(best.playerCount or "?"), extra)
    else
        local currType = get("currentType") or "none"
        targetTxt.Text = "Curr: " .. tostring(currType)
    end
end

-- ========== ТРЕКИНГ ==========
local function disconnectSproutConn()
    if sproutConn then sproutConn:Disconnect() sproutConn = nil end
end

local function disconnectViciousConn()
    if viciousConn then viciousConn:Disconnect() viciousConn = nil end
    if viciousHumanoidConn then viciousHumanoidConn:Disconnect() viciousHumanoidConn = nil end
end

local function getSproutHP(obj)
    if not obj then return nil end
    local guiPos = obj:FindFirstChild("GuiPos")
    if not guiPos then guiPos = obj:FindFirstChild("GuiPos", true) end
    if not guiPos then return nil end
    local label = guiPos:FindFirstChildWhichIsA("TextLabel", true)
    if not label then return nil end
    local text = tostring(label.Text or "")
    if text == "" then return nil end
    local digits = text:gsub("[^%d]", "")
    if digits == "" then return nil end
    return tonumber(digits)
end

local function isAliveSprout(obj)
    if not obj or obj.Parent == nil then return false end
    local sproutsFolder = workspace:FindFirstChild("Sprouts")
    if not sproutsFolder then return false end
    local exact = sproutsFolder:FindFirstChild("Sprout")
    if exact ~= obj then return false end
    local hp = getSproutHP(obj)
    if not hp or hp <= 0 then return false end
    return true
end

local function findSproutInstance()
    local sproutsFolder = workspace:FindFirstChild("Sprouts")
    if not sproutsFolder then return nil end
    local exact = sproutsFolder:FindFirstChild("Sprout")
    if exact and isAliveSprout(exact) then return exact end
    return nil
end

local function bindTargetSprout()
    disconnectSproutConn()
    targetSprout = findSproutInstance()
    farmedAt = nil
    if targetSprout then
        sproutConn = targetSprout.AncestryChanged:Connect(function(_, parent)
            if parent == nil and not farmedAt then
                farmedAt = tick()
                disconnectSproutConn()
            end
        end)
        return true
    end
    return false
end

local function getViciousHumanoid(obj)
    if not obj then return nil end
    if obj:IsA("Model") then
        return obj:FindFirstChildOfClass("Humanoid") or obj:FindFirstChild("Humanoid", true)
    end
    return nil
end

local function getViciousHP(obj)
    local humanoid = getViciousHumanoid(obj)
    if not humanoid then return nil end
    return math.floor(humanoid.Health + 0.5)
end

local function isAliveVicious(obj)
    if not obj or obj.Parent == nil then return false end
    local monsters = workspace:FindFirstChild("Monsters")
    if not monsters then return false end
    if obj.Parent ~= monsters then return false end
    if not obj:IsA("Model") then return false end
    local humanoid = getViciousHumanoid(obj)
    if not humanoid then return false end
    if humanoid.Health <= 0 then return false end
    return true
end

local function findViciousInstance()
    local monsters = workspace:FindFirstChild("Monsters")
    if not monsters then return nil end
    for _, child in ipairs(monsters:GetChildren()) do
        if isAliveVicious(child) then return child end
    end
    return nil
end

local function bindTargetVicious()
    disconnectViciousConn()
    targetVicious = findViciousInstance()
    viciousGoneAt = nil
    if targetVicious then
        local humanoid = getViciousHumanoid(targetVicious)
        viciousConn = targetVicious.AncestryChanged:Connect(function(_, parent)
            if parent == nil and not viciousGoneAt then
                viciousGoneAt = tick()
                disconnectViciousConn()
            end
        end)
        if humanoid then
            viciousHumanoidConn = humanoid.HealthChanged:Connect(function(health)
                currentViciousHP = math.floor(health + 0.5)
                updateHPUI()
                if health <= 0 and not viciousGoneAt then
                    viciousGoneAt = tick()
                    disconnectViciousConn()
                end
            end)
        end
        return true
    end
    return false
end

local function waitForSproutDespawn()
    updateTrackerUI("🌱 Sprout found...", Color3.fromRGB(120, 255, 120))
    local startedAt = tick()
    local lastHP = getSproutHP(targetSprout)
    currentSproutHP = lastHP
    updateHPUI()
    local lastHPChangeAt = tick()
    
    while true do
        if (tick() - startedAt) >= CONFIG.MAX_TRACK_TIME then
            updateTrackerUI("⚠️ Sprout timeout", Color3.fromRGB(255, 170, 90))
            currentSproutHP = nil
            updateHPUI()
            targetSprout = nil
            farmedAt = nil
            disconnectSproutConn()
            return "timeout"
        end
        if not isAliveSprout(targetSprout) then
            if not farmedAt then farmedAt = tick() end
            currentSproutHP = nil
            updateHPUI()
            targetSprout = nil
        else
            local hp = getSproutHP(targetSprout)
            currentSproutHP = hp
            updateHPUI()
            if hp and hp ~= lastHP then
                lastHP = hp
                lastHPChangeAt = tick()
            end
            if (tick() - lastHPChangeAt) >= CONFIG.MAX_HP_STUCK_TIME then
                updateTrackerUI("⚠️ Sprout HP stuck", Color3.fromRGB(255, 170, 90))
                currentSproutHP = nil
                updateHPUI()
                targetSprout = nil
                farmedAt = nil
                disconnectSproutConn()
                return "hp_stuck"
            end
        end
        if farmedAt then
            local elapsed = tick() - farmedAt
            local left = math.max(0, math.ceil(CONFIG.WAIT_AFTER_DESPAWN - elapsed))
            updateTrackerUI("⏳ After Sprout: " .. tostring(left) .. "s", Color3.fromRGB(255, 210, 120))
            if elapsed > CONFIG.WAIT_AFTER_DESPAWN then break end
        elseif lastHP then
            local liveLeft = math.max(0, math.ceil(CONFIG.MAX_HP_STUCK_TIME - (tick() - lastHPChangeAt)))
            updateTrackerUI("🌱 HP: " .. tostring(lastHP) .. " | stuck: " .. tostring(liveLeft) .. "s", Color3.fromRGB(120, 255, 120))
        end
        task.wait(0.2)
    end
    currentSproutHP = nil
    updateHPUI()
    targetSprout = nil
    farmedAt = nil
    disconnectSproutConn()
    return "done"
end

local function waitForViciousDespawn()
    updateTrackerUI("🐝 Vicious found...", Color3.fromRGB(255, 160, 120))
    local startedAt = tick()
    local lastHP = getViciousHP(targetVicious)
    currentViciousHP = lastHP
    updateHPUI()
    local lastHPChangeAt = tick()
    
    while true do
        if (tick() - startedAt) >= CONFIG.MAX_TRACK_TIME then
            updateTrackerUI("⚠️ Vicious timeout", Color3.fromRGB(255, 170, 90))
            currentViciousHP = nil
            updateHPUI()
            targetVicious = nil
            viciousGoneAt = nil
            disconnectViciousConn()
            return "timeout"
        end
        if not isAliveVicious(targetVicious) then
            if not viciousGoneAt then viciousGoneAt = tick() end
            currentViciousHP = nil
            updateHPUI()
            break
        else
            local hp = getViciousHP(targetVicious)
            currentViciousHP = hp
            updateHPUI()
            if hp and hp ~= lastHP then
                lastHP = hp
                lastHPChange
