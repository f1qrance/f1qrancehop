-- ============================================
--  SPROUT HOP v3 - ЗАЩИЩЁННАЯ ВЕРСИЯ
-- ============================================

pcall(function()
    local atl = game:GetService("CoreGui"):FindFirstChild("Atlas")
    if atl then atl:Destroy() end
    local atl2 = game:GetService("PlayerGui"):FindFirstChild("Atlas")
    if atl2 then atl2:Destroy() end
end)

local _startDelay = math.random(10, 18)
task.wait(_startDelay)

local _origRequest = request
local _safeReq = syn and syn.request or (http_request or request)
request = function(t)
    if debug and debug.getinfo and debug.getinfo(_origRequest, "s") then
        return _safeReq(t)
    end
    return _origRequest(t)
end

local _origTp = TeleportService.TeleportToPlaceInstance
TeleportService.TeleportToPlaceInstance = function(self, pid, jid, plr)
    task.wait(math.random(400, 900) / 1000)
    return _origTp(self, pid, jid, plr)
end

pcall(function()
    for _, v in pairs(getgc and getgc() or {}) do
        if type(v) == "function" and debug.getinfo then
            debug.setinfo and debug.setinfo(v, "n", "")
        end
    end
end)

-- ============================================
--  ОСНОВНОЙ СКРИПТ
-- ============================================

(function()
    local HS  = game:GetService("HttpService")
    local TS  = game:GetService("TeleportService")
    local PL  = game:GetService("Players")
    local CG  = game:GetService("CoreGui")
    local UIS = game:GetService("UserInputService")
    local LP  = PL.LocalPlayer

    local S = {
        uid  = (getgenv and getgenv() or _G).BSS_USER_ID,
        key  = (getgenv and getgenv() or _G).BSS_SECRET_KEY,
        vis  = {},
        rec  = {},
        jt   = tick(),
        sty  = nil,
        rar  = nil,
        fld  = nil,
        jid  = game.JobId,
        cd   = 55,
        col  = false,
        ign  = nil,
        tab  = "S",
        pri  = {
            "Supreme Sprout","Legendary Sprout","Gifted Vicious",
            "Festive Sprout","Epic Sprout","Gummy Sprout",
            "Rare Sprout","Vicious",
        },
    }

    if not S.uid or not S.key then return end

    local TC  = 55
    local CD  = 1
    local MSS = 40
    local MP  = 4
    local RL  = 5
    local VL  = 100
    local WSD = 30
    local WLD = 5
    local MTT = 60
    local MHS = 30
    local PID = game.PlaceId

    local pt   = nil
    local ips  = false
    local wra  = tick() + WLD

    local tsp  = nil
    local fat  = nil
    local sc   = nil

    local tvic = nil
    local vga  = nil
    local vc   = nil
    local vhc  = nil

    local cshp = nil
    local cvhp = nil

    local function isSp(sv) return tostring(sv.type or "") == "Sprout" end
    local function isVc(sv) return tostring(sv.type or "") == "Vicious" end

    local function gCol(sv)
        if isVc(sv) and sv.gifted then return "#f5ce0a" end
        if isVc(sv) then return "#85C5FF" end
        local r = tostring(sv.rarity or "")
        if r == "Supreme" then return "#7DEC66" end
        if r == "Legendary" then return "#3AD5EA" end
        if r == "Epic" then return "#BEC459" end
        if r == "Rare" then return "#BBB9BC" end
        if r == "Gummy" then return "#6E324E" end
        if r == "Festive" then return "#6B273D" end
        return "#FFFFFF"
    end

    local function gRem(sv)
        local e = tonumber(sv.expiryAt)
        return e and (e - os.time()) or math.huge
    end

    local function gLbl(sv)
        local r = tostring(sv.rarity or "")
        if isSp(sv) then
            if r == "Supreme" then return "Supreme Sprout" end
            if r == "Legendary" then return "Legendary Sprout" end
            if r == "Festive" then return "Festive Sprout" end
            if r == "Epic" then return "Epic Sprout" end
            if r == "Gummy" then return "Gummy Sprout" end
            if r == "Rare" then return "Rare Sprout" end
        end
        if isVc(sv) then
            return sv.gifted and "Gifted Vicious" or "Vicious"
        end
        return nil
    end

    local function gPri(sv)
        local lbl = gLbl(sv)
        if not lbl then return 0 end
        for i, v in ipairs(S.pri) do
            if v == lbl then return 100 - i end
        end
        return 0
    end

    local function gCd(sv)
        if isSp(sv) and sv.rarity == "Supreme" then return 60 end
        if isSp(sv) and sv.rarity == "Legendary" then return 55 end
        if isVc(sv) and sv.gifted then return 55 end
        if isVc(sv) then return 40 end
        return 50
    end

    local function hasCS()
        local t = tostring(S.sty or ""):lower():match("^%s*(.-)%s*$")
        return t ~= "" and t ~= "none" and t ~= "unknown"
    end

    local function inRec(jid)
        for _, v in ipairs(S.rec) do if v == jid then return true end end
        return false
    end

    local function pushRec(jid)
        if not jid or jid == "" then return end
        for i = #S.rec, 1, -1 do
            if S.rec[i] == jid then table.remove(S.rec, i) end
        end
        table.insert(S.rec, 1, jid)
        while #S.rec > RL do table.remove(S.rec, #S.rec) end
    end

    local function cntVis()
        local n = 0
        for _ in pairs(S.vis) do n = n + 1 end
        return n
    end

    local function trimVis()
        if cntVis() <= VL then return end
        local keep = {}
        for _, j in ipairs(S.rec) do keep[j] = true end
        keep[game.JobId] = true
        for j in pairs(S.vis) do
            if not keep[j] then
                S.vis[j] = nil
                if cntVis() <= VL then break end
            end
        end
    end

    local function addVis(jid)
        if not jid or jid == "" then return end
        S.vis[jid] = true
        trimVis()
    end

    local function remRec(jid)
        if not jid or jid == "" then return end
        for i = #S.rec, 1, -1 do
            if S.rec[i] == jid then table.remove(S.rec, i) end
        end
    end

    local function markCS()
        local j = game.JobId
        if j and j ~= "" then
            addVis(j); pushRec(j); S.jid = j
        end
    end

    local function isVal(sv)
        if not sv.jobId then return false end
        if sv.jobId == game.JobId then return false end
        if S.vis[sv.jobId] then return false end
        if inRec(sv.jobId) then return false end
        if (tonumber(sv.playerCount) or 0) > MP then return false end
        if isSp(sv) then
            local r = gRem(sv)
            if r <= 0 or r < MSS then return false end
        end
        return gPri(sv) > 0
    end

    local function isBtr(a, b)
        if not a then return false end
        if not b then return true end
        local ap, bp = gPri(a), gPri(b)
        if ap > bp then return true end
        if ap < bp then return false end
        if isSp(a) and isSp(b) then
            local ar, br = gRem(a), gRem(b)
            if ar < br then return true end
            if ar > br then return false end
        end
        if isVc(a) and isVc(b) then
            local al = tonumber(a.level) or 0
            local bl = tonumber(b.level) or 0
            if al > bl then return true end
            if al < bl then return false end
        end
        return (tonumber(a.playerCount) or 999) < (tonumber(b.playerCount) or 999)
    end

    local function pickBest(svs)
        local best = nil
        for _, sv in ipairs(svs) do
            if isVal(sv) and isBtr(sv, best) then best = sv end
        end
        return best
    end

    local function sortUI(svs)
        local cp = {}
        for _, sv in ipairs(svs) do
            if isVal(sv) then cp[#cp+1] = sv end
        end
        table.sort(cp, function(a, b) return isBtr(a, b) end)
        return cp
    end

    local function frcTp(best)
        if not best then return false end
        local isLow = (S.sty == "Sprout" and (S.rar == "Rare" or S.rar == "Epic")) or (S.sty == "Vicious")
        local isHi = isSp(best) and (best.rarity == "Supreme" or best.rarity == "Legendary")
        return isLow and isHi
    end

    local function fetch()
        local url = ("https://bss-tools.com/api/workspaces/%s/validated"):format(S.uid)
        local ok, res = pcall(request, {
            Url = url, Method = "GET",
            Headers = {["secret-key"] = S.key}
        })
        if not ok or not res or res.StatusCode ~= 200 then return {} end
        local ok2, data = pcall(function() return HS:JSONDecode(res.Body) end)
        if not ok2 or not data then return {} end
        return data.results or {}
    end

    -- GUI
    local function dGui()
        local old = CG:FindFirstChild("_H")
        if old then old:Destroy() end
    end
    dGui()

    local gui = Instance.new("ScreenGui")
    gui.Name = "_H"; gui.ResetOnSpawn = false
    gui.Parent = CG

    local frm = Instance.new("Frame")
    frm.Parent = gui
    frm.Size = UDim2.new(0,340,0, S.col and 40 or 480)
    frm.Position = UDim2.new(1,-355,0.5, S.col and -20 or -240)
    frm.BackgroundColor3 = Color3.fromRGB(15,15,20)
    frm.BorderSizePixel = 0
    Instance.new("UICorner",frm).CornerRadius = UDim.new(0,8)

    local hdr = Instance.new("Frame",frm)
    hdr.Size = UDim2.new(1,0,0,38)
    hdr.BackgroundColor3 = Color3.fromRGB(22,22,28)
    hdr.BorderSizePixel = 0
    Instance.new("UICorner",hdr).CornerRadius = UDim.new(0,8)

    local ttl = Instance.new("TextLabel",hdr)
    ttl.BackgroundTransparency = 1
    ttl.Position = UDim2.new(0,12,0,0)
    ttl.Size = UDim2.new(1,-70,1,0)
    ttl.Font = Enum.Font.GothamBold
    ttl.TextSize = 14
    ttl.TextColor3 = Color3.fromRGB(255,255,255)
    ttl.TextXAlignment = Enum.TextXAlignment.Left
    ttl.Text = "H"

    local colBtn = Instance.new("TextButton",hdr)
    colBtn.Size = UDim2.new(0,28,0,22)
    colBtn.Position = UDim2.new(1,-36,0.5,-11)
    colBtn.BackgroundColor3 = Color3.fromRGB(35,35,45)
    colBtn.BorderSizePixel = 0
    colBtn.Font = Enum.Font.GothamBold
    colBtn.TextSize = 14
    colBtn.TextColor3 = Color3.fromRGB(230,230,240)
    colBtn.Text = S.col and "+" or "-"
    Instance.new("UICorner",colBtn).CornerRadius = UDim.new(0,5)

    local stLbl = Instance.new("TextLabel",frm)
    stLbl.BackgroundTransparency = 1
    stLbl.Position = UDim2.new(0,12,0,46)
    stLbl.Size = UDim2.new(1,-24,0,16)
    stLbl.Font = Enum.Font.Gotham
    stLbl.TextSize = 11
    stLbl.TextColor3 = Color3.fromRGB(190,190,200)
    stLbl.TextXAlignment = Enum.TextXAlignment.Left
    stLbl.Text = "●"

    local cdLbl = Instance.new("TextLabel",frm)
    cdLbl.BackgroundTransparency = 1
    cdLbl.Position = UDim2.new(0,12,0,64)
    cdLbl.Size = UDim2.new(1,-24,0,16)
    cdLbl.Font = Enum.Font.Gotham
    cdLbl.TextSize = 11
    cdLbl.TextColor3 = Color3.fromRGB(190,190,200)
    cdLbl.TextXAlignment = Enum.TextXAlignment.Left
    cdLbl.Text = "⏱"

    local trLbl = Instance.new("TextLabel",frm)
    trLbl.BackgroundTransparency = 1
    trLbl.Position = UDim2.new(0,12,0,82)
    trLbl.Size = UDim2.new(1,-24,0,36)
    trLbl.Font = Enum.Font.Gotham
    trLbl.TextSize = 11
    trLbl.TextColor3 = Color3.fromRGB(150,150,165)
    trLbl.TextXAlignment = Enum.TextXAlignment.Left
    trLbl.TextWrapped = true
    trLbl.Text = "..."

    local hpLbl = Instance.new("TextLabel",frm)
    hpLbl.BackgroundTransparency = 1
    hpLbl.Position = UDim2.new(0,12,0,120)
    hpLbl.Size = UDim2.new(1,-24,0,16)
    hpLbl.Font = Enum.Font.Gotham
    hpLbl.TextSize = 11
    hpLbl.TextColor3 = Color3.fromRGB(205,205,215)
    hpLbl.TextXAlignment = Enum.TextXAlignment.Left
    hpLbl.Text = "❤ - -"

    local tgLbl = Instance.new("TextLabel",frm)
    tgLbl.BackgroundTransparency = 1
    tgLbl.Position = UDim2.new(0,12,0,140)
    tgLbl.Size = UDim2.new(1,-24,0,52)
    tgLbl.Font = Enum.Font.Gotham
    tgLbl.TextSize = 11
    tgLbl.TextColor3 = Color3.fromRGB(220,220,235)
    tgLbl.TextXAlignment = Enum.TextXAlignment.Left
    tgLbl.TextYAlignment = Enum.TextYAlignment.Top
    tgLbl.TextWrapped = true
    tgLbl.RichText = true
    tgLbl.Text = "—"

    local tabBar = Instance.new("Frame",frm)
    tabBar.Position = UDim2.new(0,12,0,198)
    tabBar.Size = UDim2.new(1,-24,0,30)
    tabBar.BackgroundTransparency = 1

    local sBtn = Instance.new("TextButton",tabBar)
    sBtn.Size = UDim2.new(0.5,-4,1,0)
    sBtn.Position = UDim2.new(0,0,0,0)
    sBtn.BackgroundColor3 = Color3.fromRGB(35,35,45)
    sBtn.BorderSizePixel = 0
    sBtn.Font = Enum.Font.GothamBold
    sBtn.TextSize = 11
    sBtn.TextColor3 = Color3.fromRGB(235,235,245)
    sBtn.Text = "S"
    Instance.new("UICorner",sBtn).CornerRadius = UDim.new(0,5)

    local pBtn = Instance.new("TextButton",tabBar)
    pBtn.Size = UDim2.new(0.5,-4,1,0)
    pBtn.Position = UDim2.new(0.5,4,0,0)
    pBtn.BackgroundColor3 = Color3.fromRGB(35,35,45)
    pBtn.BorderSizePixel = 0
    pBtn.Font = Enum.Font.GothamBold
    pBtn.TextSize = 11
    pBtn.TextColor3 = Color3.fromRGB(235,235,245)
    pBtn.Text = "P"
    Instance.new("UICorner",pBtn).CornerRadius = UDim.new(0,5)

    local cHld = Instance.new("Frame",frm)
    cHld.Position = UDim2.new(0,12,0,234)
    cHld.Size = UDim2.new(1,-24,1,-246)
    cHld.BackgroundColor3 = Color3.fromRGB(20,20,26)
    cHld.BorderSizePixel = 0
    Instance.new("UICorner",cHld).CornerRadius = UDim.new(0,6)

    local sPg = Instance.new("Frame",cHld)
    sPg.BackgroundTransparency = 1
    sPg.Size = UDim2.new(1,0,1,0)

    local pPg = Instance.new("Frame",cHld)
    pPg.BackgroundTransparency = 1
    pPg.Size = UDim2.new(1,0,1,0)

    local sScr = Instance.new("ScrollingFrame",sPg)
    sScr.BackgroundTransparency = 1
    sScr.BorderSizePixel = 0
    sScr.Position = UDim2.new(0,5,0,5)
    sScr.Size = UDim2.new(1,-10,1,-10)
    sScr.CanvasSize = UDim2.new(0,0,0,0)
    sScr.ScrollBarThickness = 3

    local sLay = Instance.new("UIListLayout",sScr)
    sLay.Padding = UDim.new(0,4)

    local pScr = Instance.new("ScrollingFrame",pPg)
    pScr.BackgroundTransparency = 1
    pScr.BorderSizePixel = 0
    pScr.Position = UDim2.new(0,5,0,5)
    pScr.Size = UDim2.new(1,-10,1,-10)
    pScr.CanvasSize = UDim2.new(0,0,0,0)
    pScr.ScrollBarThickness = 3

    local pLay = Instance.new("UIListLayout",pScr)
    pLay.Padding = UDim.new(0,4)

    local function setCol(c)
        S.col = c
        colBtn.Text = c and "+" or "-"
        stLbl.Visible = not c
        cdLbl.Visible = not c
        trLbl.Visible = not c
        hpLbl.Visible = not c
        tgLbl.Visible = not c
        tabBar.Visible = not c
        cHld.Visible = not c
        frm.Size = UDim2.new(0,340,0, c and 40 or 480)
    end

    local function setTab(t)
        S.tab = t
        local isS = t == "S"
        sPg.Visible = isS
        pPg.Visible = not isS
        sBtn.BackgroundColor3 = isS and Color3.fromRGB(55,85,65) or Color3.fromRGB(35,35,45)
        pBtn.BackgroundColor3 = not isS and Color3.fromRGB(55,85,65) or Color3.fromRGB(35,35,45)
    end

    colBtn.MouseButton1Click:Connect(function() setCol(not S.col) end)
    sBtn.MouseButton1Click:Connect(function() setTab("S") end)
    pBtn.MouseButton1Click:Connect(function() setTab("P") end)
    setCol(S.col)
    setTab(S.tab)

    local drag, dStart, dPos = false
    hdr.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            drag = true
            dStart = inp.Position
            dPos = frm.Position
            inp.Changed:Connect(function()
                if inp.UserInputState == Enum.UserInputState.End then drag = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(inp)
        if drag and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local d = inp.Position - dStart
            frm.Position = UDim2.new(dPos.X.Scale, dPos.X.Offset + d.X, dPos.Y.Scale, dPos.Y.Offset + d.Y)
        end
    end)

    local function uTrk(txt, col)
        trLbl.Text = txt
        if col then trLbl.TextColor3 = col end
    end

    local function uHP()
        hpLbl.Text = "❤ S:" .. (cshp and tostring(cshp) or "-") .. " V:" .. (cvhp and tostring(cvhp) or "-")
    end

    local function clrList()
        for _, c in ipairs(sScr:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
    end

    local function fmtLine(sv)
        local col = gCol(sv)
        local pl = tonumber(sv.playerCount) or 0
        local nm
        if isVc(sv) then
            nm = sv.gifted and ('<font color="%s">★%s</font>'):format(col, sv.type) or ('<font color="%s">%s</font>'):format(col, sv.type)
        else
            nm = ('<font color="%s">%s %s</font>'):format(col, sv.rarity or "", sv.type or "")
        end
        local ex = ""
        if isSp(sv) then
            local r = gRem(sv)
            ex = " | " .. (r == math.huge and "∞" or math.max(0, r) .. "s")
        elseif isVc(sv) then
            ex = " | L" .. tostring(sv.level or "?")
            if sv.gifted then ex = ex .. " G" end
        end
        return string.format("%s | %dP%s", nm, pl, ex)
    end

    local function uList(svs, best)
        clrList()
        local sorted = sortUI(svs)
        local shown = 0
        for _, sv in ipairs(sorted) do
            shown = shown + 1
            if shown > 12 then break end
            local itm = Instance.new("Frame",sScr)
            itm.Size = UDim2.new(1,0,0,30)
            itm.BackgroundColor3 = (best and sv.jobId == best.jobId) and Color3.fromRGB(40,62,48) or Color3.fromRGB(26,26,32)
            itm.BorderSizePixel = 0
            Instance.new("UICorner",itm).CornerRadius = UDim.new(0,4)
            local lbl = Instance.new("TextLabel",itm)
            lbl.BackgroundTransparency = 1
            lbl.Position = UDim2.new(0,8,0,0)
            lbl.Size = UDim2.new(1,-16,1,0)
            lbl.Font = Enum.Font.Gotham
            lbl.TextSize = 10
            lbl.TextColor3 = Color3.fromRGB(240,240,245)
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.RichText = true
            lbl.Text = fmtLine(sv)
        end
        if shown == 0 then
            local itm = Instance.new("Frame",sScr)
            itm.Size = UDim2.new(1,0,0,30)
            itm.BackgroundColor3 = Color3.fromRGB(26,26,32)
            Instance.new("UICorner",itm).CornerRadius = UDim.new(0,4)
            local lbl = Instance.new("TextLabel",itm)
            lbl.BackgroundTransparency = 1
            lbl.Position = UDim2.new(0,8,0,0)
            lbl.Size = UDim2.new(1,-16,1,0)
            lbl.Font = Enum.Font.Gotham
            lbl.TextSize = 10
            lbl.TextColor3 = Color3.fromRGB(150,150,165)
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Text = "∅"
        end
        task.wait()
        sScr.CanvasSize = UDim2.new(0,0,0,sLay.AbsoluteContentSize.Y)
    end

    local refPri
    refPri = function()
        for _, c in ipairs(pScr:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        for i, nm in ipairs(S.pri) do
            local row = Instance.new("Frame",pScr)
            row.Size = UDim2.new(1,0,0,34)
            row.BackgroundColor3 = Color3.fromRGB(26,26,32)
            row.BorderSizePixel = 0
            Instance.new("UICorner",row).CornerRadius = UDim.new(0,4)
            local rk = Instance.new("TextLabel",row)
            rk.BackgroundTransparency = 1
            rk.Position = UDim2.new(0,8,0,0)
            rk.Size = UDim2.new(0,24,1,0)
            rk.Font = Enum.Font.GothamBold
            rk.TextSize = 10
            rk.TextColor3 = Color3.fromRGB(255,255,255)
            rk.Text = tostring(i)
            local nl = Instance.new("TextLabel",row)
            nl.BackgroundTransparency = 1
            nl.Position = UDim2.new(0,36,0,0)
            nl.Size = UDim2.new(1,-100,1,0)
            nl.Font = Enum.Font.Gotham
            nl.TextSize = 10
            nl.TextColor3 = Color3.fromRGB(235,235,245)
            nl.TextXAlignment = Enum.TextXAlignment.Left
            nl.Text = nm
            local function mkArrow(lbl2, xOff, bg, dir)
                local b = Instance.new("TextButton",row)
                b.Size = UDim2.new(0,24,0,20)
                b.Position = UDim2.new(1,xOff,0.5,-10)
                b.BackgroundColor3 = bg
                b.BorderSizePixel = 0
                b.Font = Enum.Font.GothamBold
                b.TextSize = 11
                b.TextColor3 = Color3.fromRGB(240,240,245)
                b.Text = lbl2
                Instance.new("UICorner",b).CornerRadius = UDim.new(0,4)
                b.MouseButton1Click:Connect(function()
                    local ni = i + dir
                    if ni >= 1 and ni <= #S.pri then
                        S.pri[i], S.pri[ni] = S.pri[ni], S.pri[i]
                        refPri()
                    end
                end)
            end
            mkArrow("▲",-56,Color3.fromRGB(44,65,51),-1)
            mkArrow("▼",-28,Color3.fromRGB(65,44,44),1)
        end
        task.wait()
        pScr.CanvasSize = UDim2.new(0,0,0,pLay.AbsoluteContentSize.Y)
    end

    local function csText()
        if not S.sty or S.sty == "" then return "—" end
        local nm = S.sty
        if S.sty == "Sprout" and S.rar then nm = S.rar .. " " .. S.sty end
        if S.sty == "Vicious" and S.rar == "Gifted" then nm = "★ Vicious" end
        return nm .. (S.fld and " | " .. S.fld or "")
    end

    local function uTop(best, force, ago, cd)
        local rem = math.max(0, math.ceil(cd - ago))
        if force and best then
            stLbl.Text = "⚡"
            cdLbl.Text = "⏱ 0"
        else
            stLbl.Text = rem > 0 and "◔ " .. rem .. "s" or "●"
            cdLbl.Text = "⏱ " .. (rem > 0 and rem .. "s" or "0")
        end
        if best then
            local col = gCol(best)
            local r = gRem(best)
            local nm
            if isVc(best) then
                nm = best.gifted and ('<font color="%s">★%s</font>'):format(col, best.type) or ('<font color="%s">%s</font>'):format(col, best.type)
            else
                nm = ('<font color="%s">%s %s</font>'):format(col, best.rarity or "?", best.type or "?")
            end
            local ex = ""
            if isSp(best) then
                ex = " | " .. (r == math.huge and "∞" or math.max(0, r) .. "s")
            elseif isVc(best) then
                ex = " | L" .. tostring(best.level or "?")
                if best.gifted then ex = ex .. " G" end
            end
            tgLbl.Text = csText() .. "\n→ " .. nm .. " | " .. tostring(best.playerCount or "?") .. "P" .. ex
        else
            tgLbl.Text = csText()
        end
    end

    -- TRACKERS
    local function dcSC()
        if sc then sc:Disconnect(); sc = nil end
    end
    local function dcVC()
        if vc then vc:Disconnect(); vc = nil end
        if vhc then vhc:Disconnect(); vhc = nil end
    end

    local function gSHP(obj)
        if not obj then return nil end
        local gp = obj:FindFirstChild("GuiPos") or obj:FindFirstChild("GuiPos", true)
        if not gp then return nil end
        local lbl = gp:FindFirstChildWhichIsA("TextLabel", true)
        if not lbl then return nil end
        local d = tostring(lbl.Text or ""):gsub("[^%d]", "")
        return d ~= "" and tonumber(d) or nil
    end

    local function alSp(obj)
        if not obj or obj.Parent == nil then return false end
        local f = workspace:FindFirstChild("Sprouts")
        if not f then return false end
        if f:FindFirstChild("Sprout") ~= obj then return false end
        local hp = gSHP(obj)
        return hp and hp > 0
    end

    local function fndSp()
        local f = workspace:FindFirstChild("Sprouts")
        if not f then return nil end
        local sp = f:FindFirstChild("Sprout")
        return sp and alSp(sp) and sp or nil
    end

    local function bindSp()
        dcSC()
        tsp = fndSp()
        fat = nil
        if tsp then
            sc = tsp.AncestryChanged:Connect(function(_, p)
                if p == nil and not fat then fat = tick(); dcSC() end
            end)
            return true
        end
        return false
    end

    local function gVHum(obj)
        if not obj then return nil end
        return obj:IsA("Model") and (obj:FindFirstChildOfClass("Humanoid") or obj:FindFirstChild("Humanoid", true)) or nil
    end

    local function gVHP(obj)
        local h = gVHum(obj)
        return h and math.floor(h.Health + 0.5) or nil
    end

    local function alVc(obj)
        if not obj or obj.Parent == nil then return false end
        local m = workspace:FindFirstChild("Monsters")
        if not m or obj.Parent ~= m then return false end
        if not obj:IsA("Model") then return false end
        local h = gVHum(obj)
        if not h or h.Health <= 0 then return false end
        return true
    end

    local function fndVc()
        local m = workspace:FindFirstChild("Monsters")
        if not m then return nil end
        for _, c in ipairs(m:GetChildren()) do
            if alVc(c) then return c end
        end
        return nil
    end

    local function bindVc()
        dcVC()
        tvic = fndVc()
        vga = nil
        if tvic then
            local hum = gVHum(tvic)
            vc = tvic.AncestryChanged:Connect(function(_, p)
                if p == nil and not vga then vga = tick(); dcVC() end
            end)
            if hum then
                vhc = hum.HealthChanged:Connect(function(hp)
                    cvhp = math.floor(hp + 0.5)
                    uHP()
                    if hp <= 0 and not vga then vga = tick(); dcVC() end
                end)
            end
            return true
        end
        return false
    end

    local G = Color3.fromRGB
    local GR = G(120,255,120)
    local OR = G(255,170,90)
    local YL = G(255,210,120)
    local BL = G(255,160,120)
    local RD = G(255,100,100)

    local function wSp()
        uTrk("🌱", GR)
        local t0 = tick()
        local lHP = gSHP(tsp)
        cshp = lHP
        uHP()
        local lHPt = tick()
        while true do
            if tick() - t0 >= MTT then
                uTrk("⚠️", OR)
                cshp = nil; uHP(); tsp = nil; fat = nil; dcSC()
                return "timeout"
            end
            if not alSp(tsp) then
                if not fat then fat = tick() end
                cshp = nil; uHP(); tsp = nil
            else
                local hp = gSHP(tsp)
                cshp = hp; uHP()
                if hp and hp ~= lHP then lHP = hp; lHPt = tick() end
                if tick() - lHPt >= MHS then
                    uTrk("⚠️ HP", OR)
                    cshp = nil; uHP(); tsp = nil; fat = nil; dcSC()
                    return "hp_stuck"
                end
            end
            if fat then
                local el = tick() - fat
                local lft = math.max(0, math.ceil(WSD - el))
                uTrk("⏳ " .. lft .. "s", YL)
                if el > WSD then break end
            elseif lHP then
                local lft = math.max(0, math.ceil(MHS - (tick() - lHPt)))
                uTrk("🌱 " .. tostring(lHP) .. " | " .. lft .. "s", GR)
            end
            task.wait(0.2)
        end
        cshp = nil; uHP(); tsp = nil; fat = nil; dcSC()
        return "done"
    end

    local function wVc()
        uTrk("🐝", BL)
        local t0 = tick()
        local lHP = gVHP(tvic)
        cvhp = lHP
        uHP()
        local lHPt = tick()
        while true do
            if tick() - t0 >= MTT then
                uTrk("⚠️", OR)
                cvhp = nil; uHP(); tvic = nil; vga = nil; dcVC()
                return "timeout"
            end
            if not alVc(tvic) then
                if not vga then vga = tick() end
                cvhp = nil; uHP()
                break
            else
                local hp = gVHP(tvic)
                cvhp = hp; uHP()
                if hp and hp ~= lHP then lHP = hp; lHPt = tick() end
                if tick() - lHPt >= MHS then
                    uTrk("⚠️ HP", OR)
                    cvhp = nil; uHP(); tvic = nil; vga = nil; dcVC()
                    return "hp_stuck"
                end
                local lft = math.max(0, math.ceil(MHS - (tick() - lHPt)))
                uTrk("🐝 " .. (hp or "-") .. " | " .. lft .. "s", BL)
            end
            task.wait(0.2)
        end
        cvhp = nil; uHP(); tvic = nil; vga = nil; dcVC()
        return "done"
    end

    local function hydrate(svs)
        if S.ign and S.ign == game.JobId then return false end
        if hasCS() then return true end
        for _, sv in ipairs(svs) do
            if sv.jobId == game.JobId then
                S.rar = (isVc(sv) and sv.gifted) and "Gifted" or sv.rarity
                S.sty = sv.type
                S.fld = sv.field
                S.jid = sv.jobId
                return true
            end
        end
        return false
    end

    local function inval()
        local j = game.JobId
        if j and j ~= "" then addVis(j); pushRec(j); S.ign = j end
        tsp = nil; fat = nil; dcSC()
        tvic = nil; vga = nil; dcVC()
        cshp = nil; cvhp = nil; uHP()
        S.sty = nil; S.rar = nil; S.fld = nil; S.jid = nil
        S.cd = 0; S.jt = tick() - 60
    end

    local function applyId(sv)
        S.rar = (isVc(sv) and sv.gifted) and "Gifted" or sv.rarity
        S.sty = sv.type
        S.fld = sv.field
        S.jid = sv.jobId
    end

    local function rollback(fid)
        if fid and fid ~= "" then S.vis[fid] = nil; remRec(fid) end
        if pt then
            S.sty = pt.pSty; S.rar = pt.pRar; S.fld = pt.pFld
            S.jid = pt.pJid; S.cd = pt.pCd; S.jt = pt.pJt; S.ign = pt.pIgn
            pt = nil
        end
    end

    local function doTp(sv)
        pt = {
            jobId = sv.jobId, pSty = S.sty, pRar = S.rar, pJid = S.jid,
            pFld = S.fld, pCd = S.cd, pJt = S.jt, pIgn = S.ign,
        }
        addVis(sv.jobId)
        pushRec(sv.jobId)
        applyId(sv)
        S.cd = gCd(sv)
        S.jt = tick()
        S.ign = nil
        tsp = nil; fat = nil; dcSC()
        tvic = nil; vga = nil; dcVC()
        cshp = nil; cvhp = nil; uHP()

        local ok, err = pcall(function()
            TS:TeleportToPlaceInstance(PID, sv.jobId, LP)
        end)
        if not ok then
            rollback(sv.jobId)
            return false
        end
        wra = tick() + WLD
        task.wait(3)
        return true
    end

    local function tpBest(svs)
        local b = pickBest(svs)
        return b and doTp(b) or false
    end

    local function procSp(svs)
        if tick() < wra then uTrk("🌱 ⌛", G(180,180,200)); return end
        ips = true
        if bindSp() then
            uTrk("✅", GR)
            local res = wSp()
            if res == "timeout" or res == "hp_stuck" then
                inval()
                task.wait(0.2)
                if svs and #svs > 0 then tpBest(svs) end
                ips = false
                return
            end
            uTrk("→", GR)
            inval()
        else
            uTrk("❌", RD)
            inval()
            task.wait(0.2)
            if svs and #svs > 0 then tpBest(svs) end
        end
        ips = false
    end

    local function procVc(svs)
        if tick() < wra then uTrk("🐝 ⌛", G(180,180,200)); return end
        ips = true
        if bindVc() then
            uTrk("✅", BL)
            local res = wVc()
            if res == "timeout" or res == "hp_stuck" then
                inval()
                task.wait(0.2)
                if svs and #svs > 0 then tpBest(svs) end
                ips = false
                return
            end
            uTrk("→", BL)
            inval()
            if svs and #svs > 0 then tpBest(svs) end
        else
            uTrk("❌", RD)
            inval()
            task.wait(0.2)
            if svs and #svs > 0 then tpBest(svs) end
        end
        ips = false
    end

    TS.TeleportInitFailed:Connect(function(player, _, _, _, jid)
        if player ~= LP then return end
        rollback(jid or (pt and pt.jobId))
    end)

    markCS()
    refPri()
    uHP()

    while true do
        task.wait(CD)
        if ips then continue end

        local svs = fetch()
        local has = hydrate(svs)
        local ago = tick() - S.jt
        local cd = S.cd or TC

        if has and S.sty == "Sprout" then
            uTop(nil, false, ago, cd)
            uList(svs, nil)
            procSp(svs)
            continue
        end
        if has and S.sty == "Vicious" then
            uTop(nil, false, ago, cd)
            uList(svs, nil)
            procVc(svs)
            continue
        end

        cshp = nil
        cvhp = nil
        uHP()
        uTrk("◌", G(150,150,160))

        local best = pickBest(svs)
        local force = frcTp(best)
        local byp = force or (not has and best ~= nil)

        uTop(best, force, ago, cd)
        uList(svs, best)

        if has and not byp and ago < cd then continue end
        if best then doTp(best) end
    end
end)()
