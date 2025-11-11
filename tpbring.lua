-- tpbring.lua
return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")

    local lp  = Players.LocalPlayer
    local tab = UI and UI.Tabs and (UI.Tabs.TPBring or UI.Tabs.Bring or UI.Tabs.Auto or UI.Tabs.Main)
    if not tab then return end

    -- utils
    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end
    local function mainPart(m)
        if not (m and m:IsA("Model")) then return nil end
        return m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
    end
    local function allParts(m)
        local t = {}
        if not m then return t end
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then t[#t+1] = d end
        end
        return t
    end
    local function setPivot(m, cf)
        if m:IsA("Model") then m:PivotTo(cf) else local p=mainPart(m); if p then p.CFrame = cf end end
    end
    local function zeroAssembly(m)
        for _,p in ipairs(allParts(m)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            p.RotVelocity             = Vector3.new()
            p.Velocity                = Vector3.new()
        end
    end
    local function snapshotCollide(m)
        local s = {}
        for _,p in ipairs(allParts(m)) do s[p] = p.CanCollide end
        return s
    end
    local function setCollideFromSnapshot(snap)
        for part,can in pairs(snap or {}) do
            if part and part.Parent then part.CanCollide = can end
        end
    end

    -- remotes (not used in teleport mode but kept for compatibility)
    local startDrag, stopDrag = nil, nil
    do
        local re = RS:FindFirstChild("RemoteEvents")
        if re then
            startDrag = re:FindFirstChild("RequestStartDraggingItem")
            stopDrag  = re:FindFirstChild("StopDraggingItem")
        end
    end

    -- edge UI
    local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
    local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
    if not edgeGui then
        edgeGui = Instance.new("ScreenGui")
        edgeGui.Name = "EdgeButtons"
        edgeGui.ResetOnSpawn = false
        edgeGui.Parent = playerGui
    end
    local stack = edgeGui:FindFirstChild("EdgeStack")
    if not stack then
        stack = Instance.new("Frame")
        stack.Name = "EdgeStack"
        stack.AnchorPoint = Vector2.new(1,0)
        stack.Position = UDim2.new(1,-6,0,6)
        stack.Size = UDim2.new(0,130,1,-12)
        stack.BackgroundTransparency = 1
        stack.Parent = edgeGui
        local list = Instance.new("UIListLayout")
        list.FillDirection = Enum.FillDirection.Vertical
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Padding = UDim.new(0,6)
        list.HorizontalAlignment = Enum.HorizontalAlignment.Right
        list.Parent = stack
    end
    local function makeEdgeBtn(name, label, order)
        local b = stack:FindFirstChild(name)
        if not b then
            b = Instance.new("TextButton")
            b.Name = name
            b.Size = UDim2.new(1,0,0,30)
            b.Text = label
            b.TextSize = 12
            b.Font = Enum.Font.GothamBold
            b.BackgroundColor3 = Color3.fromRGB(30,30,35)
            b.TextColor3 = Color3.new(1,1,1)
            b.BorderSizePixel = 0
            b.Visible = false
            b.LayoutOrder = order or 1
            b.Parent = stack
            local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,8); corner.Parent = b
        else
            b.Text = label; b.LayoutOrder = order or b.LayoutOrder; b.Visible = false
        end
        return b
    end

    local STOP_BTN = makeEdgeBtn("TPBringStop", "STOP", 50)

    -- config
    local PICK_RADIUS           = 220
    local ORB_HEIGHT            = 28
    local DROP_JITTER_MIN       = 0.18
    local DROP_JITTER_MAX       = 0.42
    local ONE_AT_A_TIME         = true
    local START_STAGGER         = 0.02   -- fast cadence, one-at-a-time
    local WATCHDOG_HZ           = 2

    local INFLT_ATTR = "OrbInFlightAt"
    local DONE_ATTR  = "OrbDelivered"

    local CURRENT_RUN_ID = nil
    local running        = false

    -- single hover orb at destination
    local hoverOrb   = nil
    local hoverPos   = nil
    local hoverColor = nil

    local function destroyOrb()
        if hoverOrb then pcall(function() hoverOrb:Destroy() end) end
        hoverOrb, hoverPos = nil, nil
    end
    local function spawnHoverOrb(pos, color)
        destroyOrb()
        local o = Instance.new("Part")
        o.Name = "tp_hover_orb"
        o.Shape = Enum.PartType.Ball
        o.Size = Vector3.new(1.5,1.5,1.5)
        o.Material = Enum.Material.Neon
        o.Color = color or Color3.fromRGB(180,240,255)
        o.Anchored, o.CanCollide, o.CanTouch, o.CanQuery = true,false,false,false
        o.CFrame = CFrame.new(pos + Vector3.new(0, ORB_HEIGHT, 0))
        o.Parent = WS
        local l = Instance.new("PointLight"); l.Range = 16; l.Brightness = 2.2; l.Parent = o
        hoverOrb = o
        hoverPos = o.Position
        hoverColor = o.Color
    end

    -- filters
    local junkItems = {
        "Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine",
        "UFO Junk","UFO Component"
    }
    local fuelItems = {"Log","Coal","Fuel Canister","Oil Barrel"}
    local scrapAlso = { Log=true }

    local fuelSet, scrapSet = {}, {}
    for _,n in ipairs(fuelItems) do fuelSet[n] = true end
    for _,n in ipairs(junkItems) do scrapSet[n] = true end
    for k,_ in pairs(scrapAlso) do scrapSet[k] = true end

    local function isWallVariant(m)
        if not (m and m:IsA("Model")) then return false end
        local n = (m.Name or ""):lower()
        return n == "logwall" or n == "log wall" or (n:find("log",1,true) and n:find("wall",1,true))
    end
    local function isUnderLogWall(inst)
        local cur = inst
        while cur and cur ~= WS then
            local nm = (cur.Name or ""):lower()
            if nm == "logwall" or nm == "log wall" or (nm:find("log",1,true) and nm:find("wall",1,true)) then
                return true
            end
            cur = cur.Parent
        end
        return false
    end
    local function itemsRootOrNil() return WS:FindFirstChild("Items") end
    local function wantedBySet(m, set)
        if not (m and m:IsA("Model") and m.Parent) then return false end
        local itemsFolder = itemsRootOrNil()
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then return false end
        if isWallVariant(m) or isUnderLogWall(m) then return false end
        local nm = m.Name or ""
        if nm == "Chair" then return false end
        return set[nm] == true
    end

    local function nearbyCandidates(center, radius, set)
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(center, radius, params) or {}
        local uniq, out = {}, {}
        for _,p in ipairs(parts) do
            local m = p:FindFirstAncestorOfClass("Model")
            if m and not uniq[m] and wantedBySet(m, set) and m.Parent then
                local done = m:GetAttribute(DONE_ATTR)
                if done ~= CURRENT_RUN_ID then
                    uniq[m]=true; out[#out+1]=m
                end
            end
        end
        return out
    end

    local function hash01(s)
        local h = 131071
        for i = 1, #s do h = (h*131 + string.byte(s, i)) % 1000003 end
        return (h % 100000) / 100000
    end
    local function landingOffset(m)
        local key = (typeof(m.GetDebugId)=="function" and m:GetDebugId() or (m.Name or "")) .. tostring(CURRENT_RUN_ID or "")
        local r1 = hash01(key .. "a")
        local r2 = hash01(key .. "b")
        local ang = r1 * math.pi * 2
        local rad = DROP_JITTER_MIN + (DROP_JITTER_MAX - DROP_JITTER_MIN) * r2
        return Vector3.new(math.cos(ang)*rad, 0, math.sin(ang)*rad)
    end

    -- destination finders
    local function cfFromInstance(inst)
        if not inst then return nil end
        if inst:IsA("Model") then
            local mp = mainPart(inst)
            if mp then return mp.CFrame end
            return inst:GetPivot()
        elseif inst:IsA("BasePart") then
            return inst.CFrame
        end
        return nil
    end
    local function findDescendantByKeywords(root, kws)
        if not root then return nil end
        local function match(name)
            name = (name or ""):lower()
            for _,kw in ipairs(kws) do
                if string.find(name, kw, 1, true) then return true end
            end
            return false
        end
        for _,inst in ipairs(root:GetDescendants()) do
            if match(inst.Name) then
                if inst:IsA("BasePart") then return inst end
                if inst:IsA("Model") and mainPart(inst) then return inst end
            end
        end
        return nil
    end
    local function campfirePos()
        local fire = WS:FindFirstChild("Map") and WS.Map:FindFirstChild("Campground") and WS.Map.Campground:FindFirstChild("MainFire")
        if not (fire and (fire:IsA("Model") or fire:IsA("BasePart"))) then
            local root = (WS:FindFirstChild("Map") or WS)
            local cand = findDescendantByKeywords(root, { "mainfire", "campfire", "camp fire", "firepit", "fire" })
            if not cand then return nil end
            local cf = cfFromInstance(cand)
            return cf and cf.Position or nil
        end
        local cf = (mainPart(fire) and fire.PrimaryPart and fire.PrimaryPart.CFrame) or (mainPart(fire) and mainPart(fire).CFrame) or fire:GetPivot()
        return cf and cf.Position or nil
    end
    local function scrapperPos()
        local scr = WS:FindFirstChild("Map")
                    and WS.Map:FindFirstChild("Campground")
                    and WS.Map.Campground:FindFirstChild("Scrapper")
        if not (scr and (scr:IsA("Model") or scr:IsA("BasePart"))) then
            local root = (WS:FindFirstChild("Map") or WS)
            local cand = findDescendantByKeywords(root, { "scrapper", "scrap dealer", "scrap", "scrappernpc", "scrapshop" })
            if not cand then return nil end
            local cf = cfFromInstance(cand)
            return cf and cf.Position or nil
        end
        local cf = (mainPart(scr) and scr.PrimaryPart and scr.PrimaryPart.CFrame) or (mainPart(scr) and mainPart(scr).CFrame) or scr:GetPivot()
        return cf and cf.Position or nil
    end

    -- teleport-and-drop
    local function teleportDrop(m)
        if not (running and m and m.Parent and hoverPos) then return end
        local mp = mainPart(m); if not mp then return end

        -- snapshot and prep
        local snap = snapshotCollide(m)
        for _,p in ipairs(allParts(m)) do
            p.CanCollide = false
            p.Anchored   = true
        end
        zeroAssembly(m)

        -- place above orb with slight horizontal jitter to avoid clumps
        local off = landingOffset(m)
        local target = Vector3.new(hoverPos.X + off.X, hoverPos.Y, hoverPos.Z + off.Z)

        setPivot(m, CFrame.new(target))

        -- release: physics takes over, smooth fall
        zeroAssembly(m)
        for _,p in ipairs(allParts(m)) do
            p.Anchored = false
            p.CanCollide = true
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end

        -- mark delivered for this run
        pcall(function() m:SetAttribute(INFLT_ATTR, os.clock()) end)
        pcall(function() m:SetAttribute(DONE_ATTR, CURRENT_RUN_ID) end)
    end

    -- run loop
    local CURRENT_TARGET_SET = nil
    local hb = nil
    local function stopAll()
        running = false
        if hb then hb:Disconnect() end
        STOP_BTN.Visible = false
        destroyOrb()
    end
    STOP_BTN.MouseButton1Click:Connect(stopAll)

    -- orb watchdog
    do
        local acc = 0
        Run.Heartbeat:Connect(function(dt)
            if not running then return end
            acc += dt
            if acc >= (1/WATCHDOG_HZ) then
                acc = 0
                if hoverPos and (not hoverOrb or not hoverOrb.Parent) then
                    spawnHoverOrb(hoverPos, hoverColor)
                else
                    hoverPos = hoverOrb and hoverOrb.Position or hoverPos
                end
            end
        end)
    end

    local function startAll(kind)
        if running then return end
        if not hrp() then return end

        local pos, set, color
        if kind == "fuel" then
            pos   = campfirePos()
            set   = fuelSet
            color = Color3.fromRGB(255,200,50)
        elseif kind == "scrap" then
            pos   = scrapperPos()
            set   = scrapSet
            color = Color3.fromRGB(120,255,160)
        else
            return
        end
        if not pos then return end

        CURRENT_RUN_ID = tostring(os.clock())
        spawnHoverOrb(pos, color)

        running = true
        STOP_BTN.Visible = true
        CURRENT_TARGET_SET = set

        if hb then hb:Disconnect() end
        hb = Run.Heartbeat:Connect(function()
            if not running then return end
            local root = hrp(); if not root then return end

            -- pick near player
            local list = nearbyCandidates(root.Position, PICK_RADIUS, CURRENT_TARGET_SET)
            if #list == 0 then return end

            -- one at a time, fast
            if ONE_AT_A_TIME then
                teleportDrop(list[1])
                task.wait(START_STAGGER)
            else
                for i=1,#list do
                    teleportDrop(list[i])
                    task.wait(START_STAGGER)
                    if not running then break end
                end
            end
        end)
    end

    -- keep existing button labels; both use teleport mode now
    tab:Button({ Title = "Send Fuel",               Callback = function() if running then return end startAll("fuel")  end })
    tab:Button({ Title = "Send Scrap",              Callback = function() if running then return end startAll("scrap") end })
    tab:Button({ Title = "Send Fuel (Teleport)",    Callback = function() if running then return end startAll("fuel")  end })
    tab:Button({ Title = "Send Scrap (Teleport)",   Callback = function() if running then return end startAll("scrap") end })

    Players.LocalPlayer.CharacterAdded:Connect(function()
        if running and hoverPos then
            spawnHoverOrb(hoverPos, hoverColor)
        end
    end)
end
