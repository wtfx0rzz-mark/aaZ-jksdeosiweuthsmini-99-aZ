-- tpbring.lua
return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")

    local lp  = Players.LocalPlayer
    local tab = UI and UI.Tabs and (UI.Tabs.TPBring or UI.Tabs.Bring or UI.Tabs.Auto or UI.Tabs.Main)
    if not tab then return end

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
    local function setNoCollide(m)
        local s = {}
        for _,p in ipairs(allParts(m)) do s[p]=p.CanCollide; p.CanCollide=false end
        return s
    end

    local startDrag, stopDrag = nil, nil
    do
        local re = RS:FindFirstChild("RemoteEvents")
        if re then
            startDrag = re:FindFirstChild("RequestStartDraggingItem")
            stopDrag  = re:FindFirstChild("StopDraggingItem")
        end
    end

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

    local PICK_RADIUS          = 400
    local ORB_HEIGHT           = 0
    local MAX_CONCURRENT       = 40
    local START_STAGGER        = 0.01
    local STEP_WAIT            = 0.016

    local INFLT_ATTR           = "OrbInFlightAt"
    local JOB_ATTR             = "OrbJob"
    local DONE_ATTR            = "OrbDelivered"

    local QUEUE_TIMEOUT_S      = 2.0
    local ORB_UNSTICK_RAD      = 2.5
    local ORB_UNSTICK_HZ       = 10
    local RELEASE_RATE_HZ      = 18
    local MAX_RELEASE_PER_TICK = 10

    local RIM_R      = 0.85
    local PHASE_STEP = 0.35
    local SWAY       = 0.18
    local SWAY_FREQ  = 3.0
    local _theta     = 0.0

    local CURRENT_RUN_ID = nil
    local running    = false
    local hb         = nil
    local orb        = nil
    local orbPosVec  = nil
    local inflight   = {}
    local queue      = {}
    local releaseAcc = 0.0
    local activeEnq  = 0
    local CURRENT_TARGET_SET = nil

    local junkItems = {
        "Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine",
        "UFO Junk","UFO Component"
    }
    local fuelItems = {"Log","Coal","Fuel Canister","Oil Barrel"}
    local scrapAlso = { Log=true }

    local fuelSet = {}
    for _,n in ipairs(fuelItems) do fuelSet[n] = true end
    local scrapSet = {}
    for _,n in ipairs(junkItems) do scrapSet[n] = true end
    for k,_ in pairs(scrapAlso) do scrapSet[k] = true end

    local function isWallVariant(m)
        if not (m and m:IsA("Model")) then return false end
        local n = (m.Name or ""):lower()
        return n == "logwall" or n == "log wall" or (n:find("log",1,true) and n:find("wall",1,true))
    end
    local function isUnderLogWall(inst)
        local cur = inst
        while cur and cur ~= WS do
            local nm = (cur.Name or ""):lower()
            if nm == "logwall" or nm == "log wall" or (nm:find("log",1,true) and nm:find("wall",1,true)) then
                return true
            end
            cur = cur.Parent
        end
        return false
    end
    local function itemsRootOrNil() return WS:FindFirstChild("Items") end

    local function spawnOrbAt(pos, color)
        if orb then pcall(function() orb:Destroy() end) end
        local o = Instance.new("Part")
        o.Name = "tp_orb_fixed"
        o.Shape = Enum.PartType.Ball
        o.Size = Vector3.new(1.5,1.5,1.5)
        o.Material = Enum.Material.Neon
        o.Color = color or Color3.fromRGB(80,180,255)
        o.Anchored, o.CanCollide, o.CanTouch, o.CanQuery = true,false,false,false
        o.CFrame = CFrame.new(pos + Vector3.new(0, ORB_HEIGHT, 0))
        o.Parent = WS
        local l = Instance.new("PointLight"); l.Range = 16; l.Brightness = 2.5; l.Parent = o
        orb = o
        orbPosVec = orb.Position
    end
    local function destroyOrb()
        if orb then pcall(function() orb:Destroy() end) orb=nil end
        orbPosVec = nil
    end

    local function wantedBySet(m, set)
        if not (m and m:IsA("Model") and m.Parent) then return false end
        local itemsFolder = itemsRootOrNil()
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then return false end
        if isWallVariant(m) or isUnderLogWall(m) then return false end
        local nm = m.Name or ""
        if nm == "Chair" then return false end
        return set[nm] == true
    end

    local function nearbyCandidates(center, radius, jobId, set)
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(center, radius, params) or {}
        local uniq, out = {}, {}
        for _,p in ipairs(parts) do
            local m = p:FindFirstAncestorOfClass("Model")
            if m and not uniq[m] and wantedBySet(m, set) and m.Parent and not inflight[m] then
                local done = m:GetAttribute(DONE_ATTR)
                if done ~= CURRENT_RUN_ID then
                    local tIn = m:GetAttribute(INFLT_ATTR)
                    local jIn = m:GetAttribute(JOB_ATTR)
                    if tIn and jIn and tostring(jIn) ~= jobId and os.clock() - tIn < 6.0 then
                    else
                        uniq[m]=true; out[#out+1]=m
                    end
                end
            end
        end
        return out
    end

    local function nextRimPoint()
        _theta = _theta + PHASE_STEP
        if _theta > math.pi*2 then _theta = _theta - math.pi*2 end
        local c, s = math.cos(_theta), math.sin(_theta)
        local rim  = Vector3.new(orbPosVec.X + c*RIM_R, orbPosVec.Y, orbPosVec.Z + s*RIM_R)
        local wob  = math.sin(_theta*SWAY_FREQ) * SWAY
        local tangent = Vector3.new(-s, 0, c)
        return rim + tangent * wob
    end

    local function queueModel(m, jobId)
        if not (m and m.Parent) then return end
        pcall(function() m:SetAttribute(INFLT_ATTR, os.clock()) end)
        pcall(function() m:SetAttribute(JOB_ATTR, jobId) end)
        local snap = setNoCollide(m)
        zeroAssembly(m)
        if startDrag then pcall(function() startDrag:FireServer(m) end) end
        local mp = mainPart(m)
        local t0 = os.clock()
        while mp and (os.clock() - t0) < 0.35 do
            local ownerOk = false
            pcall(function()
                local o = mp:GetNetworkOwner()
                ownerOk = (o == lp)
            end)
            if ownerOk then break end
            Run.Heartbeat:Wait()
        end
        inflight[m] = { snap = snap, queuedAt = os.clock() }
        queue[#queue+1] = m
        activeEnq += 1
    end

    local function releaseOne(m)
        if not (m and m.Parent and orbPosVec) then inflight[m]=nil; activeEnq = math.max(0, activeEnq-1); return end
        local info = inflight[m]
        local snap = info and info.snap or snapshotCollide(m)
        local rim = nextRimPoint()
        setPivot(m, CFrame.new(rim))
        setCollideFromSnapshot(snap)
        zeroAssembly(m)
        for _,p in ipairs(allParts(m)) do
            p.Anchored = false
            pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
        end
        if stopDrag then pcall(function() stopDrag:FireServer(m) end) end
        pcall(function()
            m:SetAttribute(INFLT_ATTR, nil)
            m:SetAttribute(JOB_ATTR, nil)
            m:SetAttribute(DONE_ATTR, CURRENT_RUN_ID)
        end)
        inflight[m] = nil
        activeEnq = math.max(0, activeEnq-1)
    end

    local function wave(center)
        local jobId = tostring(os.clock())
        local list = nearbyCandidates(center, PICK_RADIUS, jobId, CURRENT_TARGET_SET or {})
        for i=1,#list do
            if not running then break end
            while running and activeEnq >= MAX_CONCURRENT do Run.Heartbeat:Wait() end
            local m = list[i]
            if m and m.Parent and not inflight[m] then
                queueModel(m, jobId)
                task.wait(START_STAGGER)
            end
        end
    end

    local function stopAll()
        running = false
        if hb then hb:Disconnect(); hb=nil end
        STOP_BTN.Visible = false
        for i=#queue,1,-1 do
            local m = queue[i]
            if m and m.Parent then releaseOne(m) end
            table.remove(queue, i)
        end
        for m,info in pairs(inflight) do
            if stopDrag then pcall(function() stopDrag:FireServer(m) end) end
            setCollideFromSnapshot(info and info.snap or snapshotCollide(m))
            zeroAssembly(m)
            inflight[m] = nil
        end
        activeEnq = 0
        destroyOrb()
    end

    STOP_BTN.MouseButton1Click:Connect(stopAll)

    local function campfireOrbPos()
        local fire = WS:FindFirstChild("Map") and WS.Map:FindFirstChild("Campground") and WS.Map.Campground:FindFirstChild("MainFire")
        if not fire then return nil end
        local cf = (mainPart(fire) and mainPart(fire).CFrame) or fire:GetPivot()
        return (cf.Position + Vector3.new(0, ORB_HEIGHT + 10, 0))
    end
    local function scrapperOrbPos()
        local scr = WS:FindFirstChild("Map") and WS.Map:FindFirstChild("Campground") and WS.Map.Campground:FindFirstChild("Scrapper")
        if not scr then return nil end
        local cf = (mainPart(scr) and mainPart(scr).CFrame) or scr:GetPivot()
        return (cf.Position + Vector3.new(0, ORB_HEIGHT + 10, 0))
    end

    local function startAll(mode)
        if running then return end
        if not hrp() then return end
        local pos, set, color
        if mode == "fuel" then
            pos   = campfireOrbPos()
            set   = fuelSet
            color = Color3.fromRGB(255,200,50)
        elseif mode == "scrap" then
            pos   = scrapperOrbPos()
            set   = scrapSet
            color = Color3.fromRGB(120,255,160)
        else
            return
        end
        if not pos then return end
        CURRENT_RUN_ID = tostring(os.clock())
        spawnOrbAt(pos, color)
        running = true
        STOP_BTN.Visible = true
        queue = {}
        inflight = {}
        activeEnq = 0
        releaseAcc = 0
        CURRENT_TARGET_SET = set
        if hb then hb:Disconnect() end
        hb = Run.Heartbeat:Connect(function(dt)
            if not running then return end
            local root = hrp(); if root then wave(root.Position) end
            releaseAcc = releaseAcc + dt
            local interval = 1 / RELEASE_RATE_HZ
            local n = math.min(MAX_RELEASE_PER_TICK, math.floor(releaseAcc / interval))
            if n > 0 then
                releaseAcc = releaseAcc - n * interval
                for i=1,n do
                    local m = table.remove(queue, 1)
                    if not m then break end
                    releaseOne(m)
                end
            end
            local now = os.clock()
            for m,info in pairs(inflight) do
                if info and info.queuedAt and (now - info.queuedAt) > QUEUE_TIMEOUT_S then
                    local found = false
                    for i,v in ipairs(queue) do if v == m then table.remove(queue, i); found=true; break end end
                    if found then table.insert(queue, 1, m) else releaseOne(m) end
                    inflight[m].queuedAt = now
                end
            end
            task.wait(STEP_WAIT)
        end)
    end

    do
        local acc = 0
        Run.Heartbeat:Connect(function(dt)
            if not (running and orbPosVec) then return end
            acc = acc + dt
            if acc < (1/ORB_UNSTICK_HZ) then return end
            acc = 0
            local items = itemsRootOrNil(); if not items then return end
            for _,m in ipairs(items:GetChildren()) do
                if not m:IsA("Model") then continue end
                local mp = mainPart(m); if not mp then continue end
                if (mp.Position - orbPosVec).Magnitude <= ORB_UNSTICK_RAD then
                    for _,p in ipairs(allParts(m)) do p.Anchored = false end
                end
            end
        end)
    end

    tab:Button({
        Title = "Send Fuel",
        Callback = function()
            if running then return end
            startAll("fuel")
        end
    })
    tab:Button({
        Title = "Send Scrap",
        Callback = function()
            if running then return end
            startAll("scrap")
        end
    })

    Players.LocalPlayer.CharacterAdded:Connect(function()
        if running and not (orb and orb.Parent) then
            if CURRENT_TARGET_SET == fuelSet then
                local p = campfireOrbPos(); if p then spawnOrbAt(p, Color3.fromRGB(255,200,50)) end
            elseif CURRENT_TARGET_SET == scrapSet then
                local p = scrapperOrbPos(); if p then spawnOrbAt(p, Color3.fromRGB(120,255,160)) end
            end
        end
    end)
end
