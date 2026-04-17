local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G

local userId = ENV.BSS_USER_ID
local secretKey = ENV.BSS_SECRET_KEY

if not userId or not secretKey then
    warn("[AUTOHOP] Missing BSS_USER_ID or BSS_SECRET_KEY")
    return
end

if typeof(request) ~= "function" then
    warn("[AUTOHOP] request(...) is not available in this executor")
    return
end

local placeId = game.PlaceId

local TELEPORT_COOLDOWN = 55
local CHECK_DELAY = 1
local MIN_SPROUT_SECONDS = 40
local MAX_PLAYERS = 4
local RECENT_LIMIT = 5
local VISITED_LIMIT = 100
local WAIT_AFTER_SPROUT_DESPAWN = 30
local WORLD_LOAD_DELAY = 5
local MAX_TRACK_TIME = 60
local MAX_HP_STUCK_TIME = 30

ENV.BSS_VISITED_JOB_IDS = ENV.BSS_VISITED_JOB_IDS or {}
ENV.BSS_RECENT_JOB_IDS = ENV.BSS_RECENT_JOB_IDS or {}
ENV.BSS_SERVER_JOIN_TIME = ENV.BSS_SERVER_JOIN_TIME or tick()
ENV.BSS_CURRENT_SERVER_TYPE = ENV.BSS_CURRENT_SERVER_TYPE or nil
ENV.BSS_CURRENT_SERVER_RARITY = ENV.BSS_CURRENT_SERVER_RARITY or nil
ENV.BSS_CURRENT_SERVER_FIELD = ENV.BSS_CURRENT_SERVER_FIELD or nil
ENV.BSS_CURRENT_SERVER_JOB_ID = ENV.BSS_CURRENT_SERVER_JOB_ID or game.JobId
ENV.BSS_NEXT_TELEPORT_COOLDOWN = ENV.BSS_NEXT_TELEPORT_COOLDOWN or TELEPORT_COOLDOWN
ENV.BSS_UI_COLLAPSED = ENV.BSS_UI_COLLAPSED or false
ENV.BSS_IGNORE_CURRENT_JOB_ID = ENV.BSS_IGNORE_CURRENT_JOB_ID or nil
ENV.BSS_ACTIVE_TAB = ENV.BSS_ACTIVE_TAB or "Servers"
ENV.BSS_PRIORITY_ORDER = ENV.BSS_PRIORITY_ORDER or {
    "Supreme Sprout",
    "Legendary Sprout",
    "Gifted Vicious",
    "Festive Sprout",
    "Epic Sprout",
    "Gummy Sprout",
    "Rare Sprout",
    "Vicious",
}

local VISITED = ENV.BSS_VISITED_JOB_IDS
local RECENT = ENV.BSS_RECENT_JOB_IDS

local pendingTeleport = nil
local isProcessingSpecial = false
local worldReadyAt = tick() + WORLD_LOAD_DELAY

local targetSprout = nil
local farmedAt = nil
local sproutConn = nil

local targetVicious = nil
local viciousGoneAt = nil
local viciousConn = nil
local viciousHumanoidConn = nil

local currentSproutHP = nil
local currentViciousHP = nil

local function log(...)
    print("[AUTOHOP]", ...)
end

local function warnf(...)
    warn("[AUTOHOP]", ...)
end

local function safeDestroyGui()
    local old = CoreGui:FindFirstChild("HopUI_Main")
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

local function getServerLabel(server)
    local rarity = tostring(server.rarity or "")

    if isSprout(server) and rarity == "Supreme" then
        return "Supreme Sprout"
    elseif isSprout(server) and rarity == "Legendary" then
        return "Legendary Sprout"
    elseif isVicious(server) and server.gifted == true then
        return "Gifted Vicious"
    elseif isSprout(server) and rarity == "Festive" then
        return "Festive Sprout"
    elseif isSprout(server) and rarity == "Epic" then
        return "Epic Sprout"
    elseif isSprout(server) and rarity == "Gummy" then
        return "Gummy Sprout"
    elseif isSprout(server) and rarity == "Rare" then
        return "Rare Sprout"
    elseif isVicious(server) then
        return "Vicious"
    end

    return nil
end

local function getPriority(server)
    local label = getServerLabel(server)
    if not label then
        return 0
    end

    for index, value in ipairs(ENV.BSS_PRIORITY_ORDER) do
        if value == label then
            return 100 - index
        end
    end

    return 0
end

local function getCooldownForServer(server)
    if isSprout(server) and server.rarity == "Supreme" then
        return 60
    elseif isSprout(server) and server.rarity == "Legendary" then
        return 55
    elseif isVicious(server) and server.gifted == true then
        return 55
    elseif isVicious(server) then
        return 40
    end

    return 50
end

local function hasKnownCurrentServer()
    local currentType = ENV.BSS_CURRENT_SERVER_TYPE
    if currentType == nil then
        return false
    end

    local normalized = tostring(currentType):lower():gsub("^%s+", ""):gsub("%s+$", "")
    return normalized ~= "" and normalized ~= "none" and normalized ~= "unknown"
end

local function hydrateCurrentServerFromList(servers)
    local ignoredJobId = ENV.BSS_IGNORE_CURRENT_JOB_ID
    if ignoredJobId and ignoredJobId == game.JobId then
        return false
    end

    if hasKnownCurrentServer() then
        return true
    end

    for _, server in ipairs(servers) do
        if server.jobId == game.JobId then
            if isVicious(server) and server.gifted == true then
                ENV.BSS_CURRENT_SERVER_RARITY = "Gifted"
            else
                ENV.BSS_CURRENT_SERVER_RARITY = server.rarity
            end

            ENV.BSS_CURRENT_SERVER_TYPE = server.type
            ENV.BSS_CURRENT_SERVER_FIELD = server.field
            ENV.BSS_CURRENT_SERVER_JOB_ID = server.jobId
            return true
        end
    end

    return false
end

local function shouldForceTeleport(best)
    if not best then
        return false
    end

    local currentType = ENV.BSS_CURRENT_SERVER_TYPE
    local currentRarity = ENV.BSS_CURRENT_SERVER_RARITY

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

local function countVisited()
    local total = 0
    for _ in pairs(VISITED) do
        total += 1
    end
    return total
end

local function trimVisited()
    if countVisited() <= VISITED_LIMIT then
        return
    end

    local keep = {}
    for _, jobId in ipairs(RECENT) do
        keep[jobId] = true
    end
    keep[game.JobId] = true

    for jobId in pairs(VISITED) do
        if not keep[jobId] then
            VISITED[jobId] = nil
            if countVisited() <= VISITED_LIMIT then
                break
            end
        end
    end
end

local function addVisited(jobId)
    if not jobId or jobId == "" then
        return
    end

    VISITED[jobId] = true
    trimVisited()
end

local function removeRecent(jobId)
    if not jobId or jobId == "" then
        return
    end

    for i = #RECENT, 1, -1 do
        if RECENT[i] == jobId then
            table.remove(RECENT, i)
        end
    end
end

local function markCurrentServer()
    local currentJobId = game.JobId
    if currentJobId and currentJobId ~= "" then
        addVisited(currentJobId)
        pushRecent(currentJobId)
        ENV.BSS_CURRENT_SERVER_JOB_ID = currentJobId
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

    local okRequest, res = pcall(function()
        return request({
            Url = url,
            Method = "GET",
            Headers = {["secret-key"] = secretKey}
        })
    end)

    if not okRequest then
        warnf("API request failed")
        return {}
    end

    if not res or res.StatusCode ~= 200 then
        warnf("API error:", res and res.Body or "no response")
        return {}
    end

    local ok, data = pcall(function()
        return HttpService:JSONDecode(res.Body)
    end)

    if not ok or not data then
        warnf("JSON decode error")
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
        if isValidServer(server) and isBetterServer(server, best) then
            best = server
        end
    end
    return best
end

local function sortServersForUi(servers)
    local copy = {}
    for _, server in ipairs(servers) do
        if isValidServer(server) then
            table.insert(copy, server)
        end
    end

    table.sort(copy, function(a, b)
        return isBetterServer(a, b)
    end)

    return copy
end

-- ========== НОВЫЙ UI (изменён только он) ==========

safeDestroyGui()

local gui = Instance.new("ScreenGui")
gui.Name = "HopUI_Main"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = CoreGui

local mainFrame = Instance.new("Frame")
mainFrame.Parent = gui
mainFrame.Size = UDim2.new(0, 360, 0, ENV.BSS_UI_COLLAPSED and 42 or 500)
mainFrame.Position = UDim2.new(1, -375, 0.5, ENV.BSS_UI_COLLAPSED and -21 or -250)
mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
mainFrame.BorderSizePixel = 0

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 8)
mainCorner.Parent = mainFrame

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(50, 50, 65)
mainStroke.Thickness = 1
mainStroke.Parent = mainFrame

local topBar = Instance.new("Frame")
topBar.Parent = mainFrame
topBar.Size = UDim2.new(1, 0, 0, 40)
topBar.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
topBar.BorderSizePixel = 0

local topCorner = Instance.new("UICorner")
topCorner.CornerRadius = UDim.new(0, 8)
topCorner.Parent = topBar

local topFill = Instance.new("Frame")
topFill.Parent = topBar
topFill.Position = UDim2.new(0, 0, 1, -8)
topFill.Size = UDim2.new(1, 0, 0, 8)
topFill.BackgroundColor3 = topBar.BackgroundColor3
topFill.BorderSizePixel = 0

local titleLabel = Instance.new("TextLabel")
titleLabel.Parent = topBar
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.Size = UDim2.new(1, -70, 1, 0)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 15
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "Hop"

local toggleBtn = Instance.new("TextButton")
toggleBtn.Parent = topBar
toggleBtn.Size = UDim2.new(0, 30, 0, 22)
toggleBtn.Position = UDim2.new(1, -38, 0.5, -11)
toggleBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
toggleBtn.BorderSizePixel = 0
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 16
toggleBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
toggleBtn.Text = ENV.BSS_UI_COLLAPSED and "▸" or "▾"

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 5)
toggleCorner.Parent = toggleBtn

local statusLine = Instance.new("TextLabel")
statusLine.Parent = mainFrame
statusLine.BackgroundTransparency = 1
statusLine.Position = UDim2.new(0, 12, 0, 50)
statusLine.Size = UDim2.new(1, -24, 0, 18)
statusLine.Font = Enum.Font.Gotham
statusLine.TextSize = 12
statusLine.TextColor3 = Color3.fromRGB(190, 190, 200)
statusLine.TextXAlignment = Enum.TextXAlignment.Left
statusLine.Text = "● Init..."

local cdLine = Instance.new("TextLabel")
cdLine.Parent = mainFrame
cdLine.BackgroundTransparency = 1
cdLine.Position = UDim2.new(0, 12, 0, 70)
cdLine.Size = UDim2.new(1, -24, 0, 18)
cdLine.Font = Enum.Font.Gotham
cdLine.TextSize = 12
cdLine.TextColor3 = Color3.fromRGB(190, 190, 200)
cdLine.TextXAlignment = Enum.TextXAlignment.Left
cdLine.Text = "⏱ 0s"

local trackLine = Instance.new("TextLabel")
trackLine.Parent = mainFrame
trackLine.BackgroundTransparency = 1
trackLine.Position = UDim2.new(0, 12, 0, 90)
trackLine.Size = UDim2.new(1, -24, 0, 38)
trackLine.Font = Enum.Font.Gotham
trackLine.TextSize = 12
trackLine.TextColor3 = Color3.fromRGB(150, 150, 165)
trackLine.TextXAlignment = Enum.TextXAlignment.Left
trackLine.TextWrapped = true
trackLine.Text = "◆ idle"

local hpLine = Instance.new("TextLabel")
hpLine.Parent = mainFrame
hpLine.BackgroundTransparency = 1
hpLine.Position = UDim2.new(0, 12, 0, 130)
hpLine.Size = UDim2.new(1, -24, 0, 20)
hpLine.Font = Enum.Font.Gotham
hpLine.TextSize = 12
hpLine.TextColor3 = Color3.fromRGB(205, 205, 215)
hpLine.TextXAlignment = Enum.TextXAlignment.Left
hpLine.Text = "❤ S:- | V:-"

local targetLine = Instance.new("TextLabel")
targetLine.Parent = mainFrame
targetLine.BackgroundTransparency = 1
targetLine.Position = UDim2.new(0, 12, 0, 154)
targetLine.Size = UDim2.new(1, -24, 0, 52)
targetLine.Font = Enum.Font.Gotham
targetLine.TextSize = 12
targetLine.TextColor3 = Color3.fromRGB(220, 220, 235)
targetLine.TextXAlignment = Enum.TextXAlignment.Left
targetLine.TextYAlignment = Enum.TextYAlignment.Top
targetLine.TextWrapped = true
targetLine.RichText = true
targetLine.Text = "🎯 none"

local tabRow = Instance.new("Frame")
tabRow.Parent = mainFrame
tabRow.Position = UDim2.new(0, 12, 0, 212)
tabRow.Size = UDim2.new(1, -24, 0, 32)
tabRow.BackgroundTransparency = 1

local serversTab = Instance.new("TextButton")
serversTab.Parent = tabRow
serversTab.Size = UDim2.new(0.5, -4, 1, 0)
serversTab.Position = UDim2.new(0, 0, 0, 0)
serversTab.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
serversTab.BorderSizePixel = 0
serversTab.Font = Enum.Font.GothamBold
serversTab.TextSize = 12
serversTab.TextColor3 = Color3.fromRGB(235, 235, 245)
serversTab.Text = "List"

local settingsTab = Instance.new("TextButton")
settingsTab.Parent = tabRow
settingsTab.Size = UDim2.new(0.5, -4, 1, 0)
settingsTab.Position = UDim2.new(0.5, 4, 0, 0)
settingsTab.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
settingsTab.BorderSizePixel = 0
settingsTab.Font = Enum.Font.GothamBold
settingsTab.TextSize = 12
settingsTab.TextColor3 = Color3.fromRGB(235, 235, 245)
settingsTab.Text = "Order"

for _, btn in ipairs({serversTab, settingsTab}) do
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = btn
end

local contentArea = Instance.new("Frame")
contentArea.Parent = mainFrame
contentArea.Position = UDim2.new(0, 12, 0, 250)
contentArea.Size = UDim2.new(1, -24, 1, -262)
contentArea.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
contentArea.BorderSizePixel = 0

local areaCorner = Instance.new("UICorner")
areaCorner.CornerRadius = UDim.new(0, 6)
areaCorner.Parent = contentArea

local areaStroke = Instance.new("UIStroke")
areaStroke.Color = Color3.fromRGB(45, 45, 55)
areaStroke.Thickness = 1
areaStroke.Parent = contentArea

local serversPanel = Instance.new("Frame")
serversPanel.Parent = contentArea
serversPanel.BackgroundTransparency = 1
serversPanel.Size = UDim2.new(1, 0, 1, 0)

local settingsPanel = Instance.new("Frame")
settingsPanel.Parent = contentArea
settingsPanel.BackgroundTransparency = 1
settingsPanel.Size = UDim2.new(1, 0, 1, 0)

local serverScroller = Instance.new("ScrollingFrame")
serverScroller.Parent = serversPanel
serverScroller.BackgroundTransparency = 1
serverScroller.BorderSizePixel = 0
serverScroller.Position = UDim2.new(0, 6, 0, 6)
serverScroller.Size = UDim2.new(1, -12, 1, -12)
serverScroller.CanvasSize = UDim2.new(0, 0, 0, 0)
serverScroller.ScrollBarThickness = 3
serverScroller.AutomaticCanvasSize = Enum.AutomaticSize.None

local serverLayout = Instance.new("UIListLayout")
serverLayout.Parent = serverScroller
serverLayout.Padding = UDim.new(0, 5)
serverLayout.SortOrder = Enum.SortOrder.LayoutOrder

local settingsHint = Instance.new("TextLabel")
settingsHint.Parent = settingsPanel
settingsHint.BackgroundTransparency = 1
settingsHint.Position = UDim2.new(0, 8, 0, 8)
settingsHint.Size = UDim2.new(1, -16, 0, 36)
settingsHint.Font = Enum.Font.Gotham
settingsHint.TextSize = 11
settingsHint.TextColor3 = Color3.fromRGB(180, 180, 195)
settingsHint.TextXAlignment = Enum.TextXAlignment.Left
settingsHint.TextWrapped = true
settingsHint.Text = "▲▼ = priority (top = highest)"

local settingsScroller = Instance.new("ScrollingFrame")
settingsScroller.Parent = settingsPanel
settingsScroller.BackgroundTransparency = 1
settingsScroller.BorderSizePixel = 0
settingsScroller.Position = UDim2.new(0, 8, 0, 48)
settingsScroller.Size = UDim2.new(1, -16, 1, -56)
settingsScroller.CanvasSize = UDim2.new(0, 0, 0, 0)
settingsScroller.ScrollBarThickness = 3
settingsScroller.AutomaticCanvasSize = Enum.AutomaticSize.None

local settingsLayout = Instance.new("UIListLayout")
settingsLayout.Parent = settingsScroller
settingsLayout.Padding = UDim.new(0, 5)
settingsLayout.SortOrder = Enum.SortOrder.LayoutOrder

local function setCollapsed(state)
    ENV.BSS_UI_COLLAPSED = state
    toggleBtn.Text = state and "▸" or "▾"
    statusLine.Visible = not state
    cdLine.Visible = not state
    trackLine.Visible = not state
    hpLine.Visible = not state
    targetLine.Visible = not state
    tabRow.Visible = not state
    contentArea.Visible = not state
    mainFrame.Size = UDim2.new(0, 360, 0, state and 42 or 500)
end

local function setActiveTab(tab)
    ENV.BSS_ACTIVE_TAB = tab
    local isServers = tab == "Servers"
    serversPanel.Visible = isServers
    settingsPanel.Visible = not isServers
    serversTab.BackgroundColor3 = isServers and Color3.fromRGB(55, 85, 65) or Color3.fromRGB(35, 35, 45)
    settingsTab.BackgroundColor3 = not isServers and Color3.fromRGB(55, 85, 65) or Color3.fromRGB(35, 35, 45)
end

toggleBtn.MouseButton1Click:Connect(function()
    setCollapsed(not ENV.BSS_UI_COLLAPSED)
end)

serversTab.MouseButton1Click:Connect(function()
    setActiveTab("Servers")
end)

settingsTab.MouseButton1Click:Connect(function()
    setActiveTab("Settings")
end)

setCollapsed(ENV.BSS_UI_COLLAPSED)
setActiveTab(ENV.BSS_ACTIVE_TAB)

local dragActive = false
local dragOrigin, frameOrigin

topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragActive = true
        dragOrigin = input.Position
        frameOrigin = mainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragActive = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragActive and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragOrigin
        mainFrame.Position = UDim2.new(
            frameOrigin.X.Scale,
            frameOrigin.X.Offset + delta.X,
            frameOrigin.Y.Scale,
            frameOrigin.Y.Offset + delta.Y
        )
    end
end)

local function updateTrackerUI(text, color)
    trackLine.Text = text
    if color then
        trackLine.TextColor3 = color
    end
end

local function updateHPUI()
    local sproutText = currentSproutHP and tostring(currentSproutHP) or "-"
    local viciousText = currentViciousHP and tostring(currentViciousHP) or "-"
    hpLine.Text = "❤ S:" .. sproutText .. " | V:" .. viciousText
end

local function clearServerList()
    for _, child in ipairs(serverScroller:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
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
        nameText = string.format('<font color="%s">%s %s</font>', color, rarity, serverType)
    end

    local extra = ""
    if isSprout(server) then
        extra = " | " .. (remaining == math.huge and "∞" or tostring(math.max(0, remaining)) .. "s")
        if server.field then
            extra = extra .. " | " .. tostring(server.field)
        end
    elseif isVicious(server) then
        extra = " | L" .. tostring(server.level or "?")
        if server.gifted then
            extra = extra .. " G"
        end
    end

    return string.format("%s | %dP%s", nameText, players, extra)
end

local function updateServerList(servers, best)
    clearServerList()

    local sorted = sortServersForUi(servers)
    local shown = 0

    for _, server in ipairs(sorted) do
        shown += 1
        if shown > 14 then
            break
        end

        local item = Instance.new("Frame")
        item.Parent = serverScroller
        item.Size = UDim2.new(1, 0, 0, 32)
        item.BackgroundColor3 = (best and server.jobId == best.jobId)
            and Color3.fromRGB(40, 62, 48)
            or Color3.fromRGB(26, 26, 32)
        item.BorderSizePixel = 0
        item.LayoutOrder = shown

        local itemCorner = Instance.new("UICorner")
        itemCorner.CornerRadius = UDim.new(0, 5)
        itemCorner.Parent = item

        local itemText = Instance.new("TextLabel")
        itemText.Parent = item
        itemText.BackgroundTransparency = 1
        itemText.Position = UDim2.new(0, 8, 0, 0)
        itemText.Size = UDim2.new(1, -16, 1, 0)
        itemText.Font = Enum.Font.Gotham
        itemText.TextSize = 11
        itemText.TextColor3 = Color3.fromRGB(240, 240, 245)
        itemText.TextXAlignment = Enum.TextXAlignment.Left
        itemText.RichText = true
        itemText.Text = formatServerLine(server)
    end

    if shown == 0 then
        local item = Instance.new("Frame")
        item.Parent = serverScroller
        item.Size = UDim2.new(1, 0, 0, 32)
        item.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
        item.BorderSizePixel = 0

        local itemCorner = Instance.new("UICorner")
        itemCorner.CornerRadius = UDim.new(0, 5)
        itemCorner.Parent = item

        local itemText = Instance.new("TextLabel")
        itemText.Parent = item
        itemText.BackgroundTransparency = 1
        itemText.Position = UDim2.new(0, 8, 0, 0)
        itemText.Size = UDim2.new(1, -16, 1, 0)
        itemText.Font = Enum.Font.Gotham
        itemText.TextSize = 11
        itemText.TextColor3 = Color3.fromRGB(160, 160, 175)
        itemText.TextXAlignment = Enum.TextXAlignment.Left
        itemText.Text = "∅ no suitable servers"
    end

    task.wait()
    serverScroller.CanvasSize = UDim2.new(0, 0, 0, serverLayout.AbsoluteContentSize.Y)
end

local function movePriority(index, direction)
    local newIndex = index + direction
    if newIndex < 1 or newIndex > #ENV.BSS_PRIORITY_ORDER then
        return
    end

    local tmp = ENV.BSS_PRIORITY_ORDER[index]
    ENV.BSS_PRIORITY_ORDER[index] = ENV.BSS_PRIORITY_ORDER[newIndex]
    ENV.BSS_PRIORITY_ORDER[newIndex] = tmp
end

local refreshSettingsList

refreshSettingsList = function()
    for _, child in ipairs(settingsScroller:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    for index, itemName in ipairs(ENV.BSS_PRIORITY_ORDER) do
        local row = Instance.new("Frame")
        row.Parent = settingsScroller
        row.Size = UDim2.new(1, 0, 0, 36)
        row.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
        row.BorderSizePixel = 0
        row.LayoutOrder = index

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 5)
        rowCorner.Parent = row

        local rankLabel = Instance.new("TextLabel")
        rankLabel.Parent = row
        rankLabel.BackgroundTransparency = 1
        rankLabel.Position = UDim2.new(0, 8, 0, 0)
        rankLabel.Size = UDim2.new(0, 26, 1, 0)
        rankLabel.Font = Enum.Font.GothamBold
        rankLabel.TextSize = 11
        rankLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        rankLabel.Text = tostring(index)

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Parent = row
        nameLabel.BackgroundTransparency = 1
        nameLabel.Position = UDim2.new(0, 38, 0, 0)
        nameLabel.Size = UDim2.new(1, -110, 1, 0)
        nameLabel.Font = Enum.Font.Gotham
        nameLabel.TextSize = 11
        nameLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Text = itemName

        local upBtn = Instance.new("TextButton")
        upBtn.Parent = row
        upBtn.Size = UDim2.new(0, 26, 0, 22)
        upBtn.Position = UDim2.new(1, -62, 0.5, -11)
        upBtn.BackgroundColor3 = Color3.fromRGB(44, 65, 51)
        upBtn.BorderSizePixel = 0
        upBtn.Font = Enum.Font.GothamBold
        upBtn.TextSize = 13
        upBtn.TextColor3 = Color3.fromRGB(240, 240, 245)
        upBtn.Text = "▲"

        local downBtn = Instance.new("TextButton")
        downBtn.Parent = row
        downBtn.Size = UDim2.new(0, 26, 0, 22)
        downBtn.Position = UDim2.new(1, -32, 0.5, -11)
        downBtn.BackgroundColor3 = Color3.fromRGB(65, 44, 44)
        downBtn.BorderSizePixel = 0
        downBtn.Font = Enum.Font.GothamBold
        downBtn.TextSize = 13
        downBtn.TextColor3 = Color3.fromRGB(240, 240, 245)
        downBtn.Text = "▼"

        for _, btn in ipairs({upBtn, downBtn}) do
            local btnCorner = Instance.new("UICorner")
            btnCorner.CornerRadius = UDim.new(0, 5)
            btnCorner.Parent = btn
        end

        upBtn.MouseButton1Click:Connect(function()
            movePriority(index, -1)
            refreshSettingsList()
        end)

        downBtn.MouseButton1Click:Connect(function()
            movePriority(index, 1)
            refreshSettingsList()
        end)
    end

    task.wait()
    settingsScroller.CanvasSize = UDim2.new(0, 0, 0, settingsLayout.AbsoluteContentSize.Y)
end

local function getCurrentServerText()
    local currentType = ENV.BSS_CURRENT_SERVER_TYPE
    local currentRarity = ENV.BSS_CURRENT_SERVER_RARITY
    local currentField = ENV.BSS_CURRENT_SERVER_FIELD

    if not currentType or currentType == "" then
        return "🎯 none"
    end

    local currentName = currentType
    if currentType == "Sprout" and currentRarity then
        currentName = string.format("%s %s", currentRarity, currentType)
    elseif currentType == "Vicious" and currentRarity == "Gifted" then
        currentName = "Gifted Vicious"
    end

    if currentField and currentField ~= "" then
        return string.format("🎯 %s | %s", currentName, tostring(currentField))
    end

    return string.format("🎯 %s", currentName)
end

local function updateTopInfo(best, force, joinedAgo, cooldown)
    local remainingCooldown = math.max(0, math.ceil(cooldown - joinedAgo))

    if force and best then
        statusLine.Text = "⚡ Force teleport"
        cdLine.Text = "⏱ bypass"
    else
        if remainingCooldown > 0 then
            statusLine.Text = "◔ Waiting"
            cdLine.Text = "⏱ " .. tostring(remainingCooldown) .. "s"
        else
            statusLine.Text = "● Ready"
            cdLine.Text = "⏱ 0s"
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
            extra = " | " .. (remaining == math.huge and "∞" or tostring(math.max(0, remaining)) .. "s")
            if best.field then
                extra = extra .. " | " .. tostring(best.field)
            end
        elseif isVicious(best) then
            extra = " | L" .. tostring(best.level or "?")
            if best.gifted then
                extra = extra .. " G"
            end
        end

        targetLine.Text = string.format(
            "%s\n➜ %s | %dP%s",
            getCurrentServerText(),
            nameText,
            tonumber(best.playerCount) or 0,
            extra
        )
    else
        targetLine.Text = getCurrentServerText()
    end
end

local function disconnectSproutConn()
    if sproutConn then
        sproutConn:Disconnect()
        sproutConn = nil
    end
end

local function disconnectViciousConn()
    if viciousConn then
        viciousConn:Disconnect()
        viciousConn = nil
    end
    if viciousHumanoidConn then
        viciousHumanoidConn:Disconnect()
        viciousHumanoidConn = nil
    end
end

local function getSproutHP(obj)
    if not obj then
        return nil
    end

    local guiPos = obj:FindFirstChild("GuiPos")
    if not guiPos then
        guiPos = obj:FindFirstChild("GuiPos", true)
    end
    if not guiPos then
        return nil
    end

    local label = guiPos:FindFirstChildWhichIsA("TextLabel", true)
    if not label then
        return nil
    end

    local text = tostring(label.Text or "")
    if text == "" then
        return nil
    end

    local digits = text:gsub("[^%d]", "")
    if digits == "" then
        return nil
    end

    return tonumber(digits)
end

local function isAliveSprout(obj)
    if not obj or obj.Parent == nil then
        return false
    end

    local sproutsFolder = workspace:FindFirstChild("Sprouts")
    if not sproutsFolder then
        return false
    end

    local exact = sproutsFolder:FindFirstChild("Sprout")
    if exact ~= obj then
        return false
    end

    local lowerName = tostring(obj.Name or ""):lower()
    if lowerName ~= "sprout" then
        return false
    end

    local hp = getSproutHP(obj)
    if not hp or hp <= 0 then
        return false
    end

    return true
end

local function findSproutInstance()
    local sproutsFolder = workspace:FindFirstChild("Sprouts")
    if not sproutsFolder then
        return nil
    end

    local exact = sproutsFolder:FindFirstChild("Sprout")
    if exact and isAliveSprout(exact) then
        return exact
    end

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
    if not obj then
        return nil
    end

    if obj:IsA("Model") then
        return obj:FindFirstChildOfClass("Humanoid") or obj:FindFirstChild("Humanoid", true)
    end

    return nil
end

local function getViciousHP(obj)
    local humanoid = getViciousHumanoid(obj)
    if not humanoid then
        return nil
    end

    return math.floor(humanoid.Health + 0.5)
end

local function isAliveVicious(obj)
    if not obj or obj.Parent == nil then
        return false
    end

    local monsters = workspace:FindFirstChild("Monsters")
    if not monsters then
        return false
    end

    if obj.Parent ~= monsters then
        return false
    end

    local lowerName = tostring(obj.Name or ""):lower()
    if not lowerName:find("vicious bee") then
        return false
    end

    if not obj:IsA("Model") then
        return false
    end

    local humanoid = getViciousHumanoid(obj)
    if not humanoid then
        return false
    end

    if humanoid.Health <= 0 then
        return false
    end

    local root = obj.PrimaryPart or obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildWhichIsA("BasePart", true)
    if not root then
        return false
    end

    return true
end

local function findViciousInstance()
    local monsters = workspace:FindFirstChild("Monsters")
    if not monsters then
        return nil
    end

    for _, child in ipairs(monsters:GetChildren()) do
        if isAliveVicious(child) then
            return child
        end
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
    log("SPROUT found, tracking alive state...")
    updateTrackerUI("🌱 Sprout found...", Color3.fromRGB(120, 255, 120))

    local startedAt = tick()
    local lastHP = getSproutHP(targetSprout)
    currentSproutHP = lastHP
    updateHPUI()
    local lastHPChangeAt = tick()

    while true do
        if (tick() - startedAt) >= MAX_TRACK_TIME then
            log("SPROUT timeout reached, hopping next")
            updateTrackerUI("⚠️ Sprout timeout", Color3.fromRGB(255, 170, 90))
            currentSproutHP = nil
            updateHPUI()
            targetSprout = nil
            farmedAt = nil
            disconnectSproutConn()
            return "timeout"
        end

        if not isAliveSprout(targetSprout) then
            if not farmedAt then
                farmedAt = tick()
            end
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

            if (tick() - lastHPChangeAt) >= MAX_HP_STUCK_TIME then
                log("SPROUT hp stuck reached, hopping next")
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
            local left = math.max(0, math.ceil(WAIT_AFTER_SPROUT_DESPAWN - elapsed))
            updateTrackerUI("⏳ After Sprout: " .. tostring(left) .. "s", Color3.fromRGB(255, 210, 120))

            if elapsed > WAIT_AFTER_SPROUT_DESPAWN then
                break
            end
        elseif lastHP then
            local liveLeft = math.max(0, math.ceil(MAX_HP_STUCK_TIME - (tick() - lastHPChangeAt)))
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
    log("VICIOUS found, tracking alive state...")
    updateTrackerUI("🐝 Vicious found...", Color3.fromRGB(255, 160, 120))

    local startedAt = tick()
    local lastHP = getViciousHP(targetVicious)
    currentViciousHP = lastHP
    updateHPUI()
    local lastHPChangeAt = tick()

    while true do
        if (tick() - startedAt) >= MAX_TRACK_TIME then
            log("VICIOUS timeout reached, hopping next")
            updateTrackerUI("⚠️ Vicious timeout", Color3.fromRGB(255, 170, 90))
            currentViciousHP = nil
            updateHPUI()
            targetVicious = nil
            viciousGoneAt = nil
            disconnectViciousConn()
            return "timeout"
        end

        if not isAliveVicious(targetVicious) then
            if not viciousGoneAt then
                viciousGoneAt = tick()
            end
            currentViciousHP = nil
            updateHPUI()
            break
        else
            local hp = getViciousHP(targetVicious)
            currentViciousHP = hp
            updateHPUI()

            if hp and hp ~= lastHP then
                lastHP = hp
                lastHPChangeAt = tick()
            end

            if (tick() - lastHPChangeAt) >= MAX_HP_STUCK_TIME then
                log("VICIOUS hp stuck reached, hopping next")
                updateTrackerUI("⚠️ Vicious HP stuck", Color3.fromRGB(255, 170, 90))
                currentViciousHP = nil
                updateHPUI()
                targetVicious = nil
                viciousGoneAt = nil
                disconnectViciousConn()
                return "hp_stuck"
            end

            local liveLeft = math.max(0, math.ceil(MAX_HP_STUCK_TIME - (tick() - lastHPChangeAt)))
            updateTrackerUI("🐝 HP: " .. tostring(hp or "-") .. " | stuck: " .. tostring(liveLeft) .. "s", Color3.fromRGB(255, 160, 120))
        end

        task.wait(0.2)
    end

    currentViciousHP = nil
    updateHPUI()
    targetVicious = nil
    viciousGoneAt = nil
    disconnectViciousConn()
    return "done"
end

local function invalidateCurrentServer()
    local currentJobId = game.JobId
    if currentJobId and currentJobId ~= "" then
        addVisited(currentJobId)
        pushRecent(currentJobId)
        ENV.BSS_IGNORE_CURRENT_JOB_ID = currentJobId
    end

    targetSprout = nil
    farmedAt = nil
    disconnectSproutConn()

    targetVicious = nil
    viciousGoneAt = nil
    disconnectViciousConn()

    currentSproutHP = nil
    currentViciousHP = nil
    updateHPUI()

    ENV.BSS_CURRENT_SERVER_TYPE = nil
    ENV.BSS_CURRENT_SERVER_RARITY = nil
    ENV.BSS_CURRENT_SERVER_FIELD = nil
    ENV.BSS_CURRENT_SERVER_JOB_ID = nil
    ENV.BSS_NEXT_TELEPORT_COOLDOWN = 0
    ENV.BSS_SERVER_JOIN_TIME = tick() - 60
end

local function applyServerIdentity(server)
    if isVicious(server) and server.gifted == true then
        ENV.BSS_CURRENT_SERVER_RARITY = "Gifted"
    else
        ENV.BSS_CURRENT_SERVER_RARITY = server.rarity
    end

    ENV.BSS_CURRENT_SERVER_TYPE = server.type
    ENV.BSS_CURRENT_SERVER_FIELD = server.field
    ENV.BSS_CURRENT_SERVER_JOB_ID = server.jobId
end

local function rollbackPendingTeleport(failedJobId)
    if failedJobId and failedJobId ~= "" then
        VISITED[failedJobId] = nil
        removeRecent(failedJobId)
    end

    if pendingTeleport then
        ENV.BSS_CURRENT_SERVER_TYPE = pendingTeleport.previousType
        ENV.BSS_CURRENT_SERVER_RARITY = pendingTeleport.previousRarity
        ENV.BSS_CURRENT_SERVER_FIELD = pendingTeleport.previousField
        ENV.BSS_CURRENT_SERVER_JOB_ID = pendingTeleport.previousJobId
        ENV.BSS_NEXT_TELEPORT_COOLDOWN = pendingTeleport.previousCooldown
        ENV.BSS_SERVER_JOIN_TIME = pendingTeleport.previousJoinTime
        ENV.BSS_IGNORE_CURRENT_JOB_ID = pendingTeleport.previousIgnoreJobId
        pendingTeleport = nil
    end
end

local function teleportToServer(best)
    local remaining = getRemainingSeconds(best)

    log("========== SELECTED ==========")
    log("Type:", best.type)
    log("Rarity:", best.rarity)
    log("Field:", best.field)
    log("Players:", best.playerCount)
    log("Gifted:", best.gifted)
    log("Level:", best.level)
    log("Priority:", getPriority(best))
    log("Remaining:", remaining == math.huge and "INF" or remaining)
    log("JobId:", best.jobId)
    log("==============================")

    pendingTeleport = {
        jobId = best.jobId,
        previousType = ENV.BSS_CURRENT_SERVER_TYPE,
        previousRarity = ENV.BSS_CURRENT_SERVER_RARITY,
        previousJobId = ENV.BSS_CURRENT_SERVER_JOB_ID,
        previousField = ENV.BSS_CURRENT_SERVER_FIELD,
        previousCooldown = ENV.BSS_NEXT_TELEPORT_COOLDOWN,
        previousJoinTime = ENV.BSS_SERVER_JOIN_TIME,
        previousIgnoreJobId = ENV.BSS_IGNORE_CURRENT_JOB_ID,
    }

    addVisited(best.jobId)
    pushRecent(best.jobId)
    applyServerIdentity(best)
    ENV.BSS_NEXT_TELEPORT_COOLDOWN = getCooldownForServer(best)
    ENV.BSS_SERVER_JOIN_TIME = tick()
    ENV.BSS_IGNORE_CURRENT_JOB_ID = nil

    targetSprout = nil
    farmedAt = nil
    disconnectSproutConn()

    targetVicious = nil
    viciousGoneAt = nil
    disconnectViciousConn()

    currentSproutHP = nil
    currentViciousHP = nil
    updateHPUI()

    local okTeleport, teleportError = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, best.jobId, LocalPlayer)
    end)

    if not okTeleport then
        warnf("Teleport call failed:", tostring(teleportError))
        rollbackPendingTeleport(best.jobId)
        return false
    end

    worldReadyAt = tick() + WORLD_LOAD_DELAY
    task.wait(3)
    return true
end

local function teleportToNextBestServer(servers)
    local best = pickBestServer(servers)
    if not best then
        return false
    end
    return teleportToServer(best)
end

local function processCurrentSproutServer(servers)
    if tick() < worldReadyAt then
        updateTrackerUI("🌱 Loading world...", Color3.fromRGB(180, 180, 200))
        return
    end

    isProcessingSpecial = true

    if bindTargetSprout() then
        updateTrackerUI("✅ Real Sprout on server", Color3.fromRGB(100, 255, 100))
        local result = waitForSproutDespawn()

        if result == "timeout" or result == "hp_stuck" then
            invalidateCurrentServer()
            task.wait(0.2)
            if servers and #servers > 0 then
                teleportToNextBestServer(servers)
            end
            isProcessingSpecial = false
            return
        end

        updateTrackerUI("➡️ Moving to next server...", Color3.fromRGB(100, 255, 100))
        invalidateCurrentServer()
    else
        updateTrackerUI("❌ No real Sprout on server", Color3.fromRGB(255, 100, 100))
        invalidateCurrentServer()
        task.wait(0.2)
        if servers and #servers > 0 then
            teleportToNextBestServer(servers)
        end
    end

    isProcessingSpecial = false
end

local function processCurrentViciousServer(servers)
    if tick() < worldReadyAt then
        updateTrackerUI("🐝 Loading world...", Color3.fromRGB(180, 180, 200))
        return
    end

    isProcessingSpecial = true

    if bindTargetVicious() then
        updateTrackerUI("✅ Vicious on server", Color3.fromRGB(255, 160, 120))
        local result = waitForViciousDespawn()

        if result == "timeout" or result == "hp_stuck" then
            invalidateCurrentServer()
            task.wait(0.2)
            if servers and #servers > 0 then
                teleportToNextBestServer(servers)
            end
            isProcessingSpecial = false
            return
        end

        updateTrackerUI("➡️ Vicious gone, hopping...", Color3.fromRGB(255, 160, 120))
        invalidateCurrentServer()
        if servers and #servers > 0 then
            teleportToNextBestServer(servers)
        end
    else
        updateTrackerUI("❌ No Vicious on server", Color3.fromRGB(255, 100, 100))
        invalidateCurrentServer()
        task.wait(0.2)
        if servers and #servers > 0 then
            teleportToNextBestServer(servers)
        end
    end

    isProcessingSpecial = false
end

TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage, _, jobId)
    if player ~= LocalPlayer then
        return
    end

    local failedJobId = jobId or (pendingTeleport and pendingTeleport.jobId)
    rollbackPendingTeleport(failedJobId)
    warnf("Teleport failed:", tostring(result), tostring(errorMessage or ""))
end)

ENV.checkCurrentSprout = function()
    local exists = findSproutInstance() ~= nil
    print("[MANUAL] real sprout exists =", exists)
    return exists
end

ENV.checkCurrentVicious = function()
    local exists = findViciousInstance() ~= nil
    print("[MANUAL] real vicious exists =", exists)
    return exists
end

ENV.setWaitAfterDespawn = function(seconds)
    seconds = tonumber(seconds) or 30
    WAIT_AFTER_SPROUT_DESPAWN = math.max(1, math.min(120, seconds))
    print("[SETTINGS] Wait after Sprout despawn set to", WAIT_AFTER_SPROUT_DESPAWN, "seconds")
    return WAIT_AFTER_SPROUT_DESPAWN
end

markCurrentServer()
refreshSettingsList()
updateHPUI()

log("=== AutoHop HP Watch ===")
log("If Sprout/Vicious HP does not change for 30 sec -> hop next server")
log("HP values are shown in menu")

while true do
    task.wait(CHECK_DELAY)

    if isProcessingSpecial then
        continue
    end

    local servers = fetchValidated()
    local hasCurrentServer = hydrateCurrentServerFromList(servers)

    local joinedAgo = tick() - ENV.BSS_SERVER_JOIN_TIME
    local dynamicCooldown = ENV.BSS_NEXT_TELEPORT_COOLDOWN or TELEPORT_COOLDOWN

    if hasCurrentServer and ENV.BSS_CURRENT_SERVER_TYPE == "Sprout" then
        updateTopInfo(nil, false, joinedAgo, dynamicCooldown)
        updateServerList(servers, nil)
        processCurrentSproutServer(servers)
        continue
    end

    if hasCurrentServer and ENV.BSS_CURRENT_SERVER_TYPE == "Vicious" then
        updateTopInfo(nil, false, joinedAgo, dynamicCooldown)
        updateServerList(servers, nil)
        processCurrentViciousServer(servers)
        continue
    end

    currentSproutHP = nil
    currentViciousHP = nil
    updateHPUI()
    updateTrackerUI("◆ idle", Color3.fromRGB(150, 150, 160))

    local best = pickBestServer(servers)
    local force = shouldForceTeleport(best)
    local bypassCooldown = force or (not hasCurrentServer and best ~= nil)

    updateTopInfo(best, force, joinedAgo, dynamicCooldown)
    updateServerList(servers, best)

    if hasCurrentServer and not bypassCooldown and joinedAgo < dynamicCooldown then
        continue
    end

    if best then
        teleportToServer(best)
    end
end
