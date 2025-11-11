-- tpbring.lua
return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")

    local lp  = Players.LocalPlayer
    local tab = UI and UI.Tabs and (UI.Tabs.TPBring or UI.Tabs.Bring or UI.Tabs.Auto or UI.Tabs.Main)
    if not tab then return end

    -- ========== small helpers ==========
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
    local function setAnchored(m, on)
        for _,p in ipairs(allParts(m)) do p.Anchored = on end
    end
    local function setNoCollide(m)
        local s = {}
        for _,p in ipairs(allParts(m)) do s[p]=p.CanCollide; p.CanCollide=false end
        return s
    end
    local function itemsRootOrNil() return WS:FindFirstChild("Items") end

    -- remotes
    local startDrag, stopDrag = nil, nil
    do
        local re = RS:FindFirstChild("RemoteEvents")
        if re then
            startDrag = re:FindFirstChild("RequestStartDraggingItem")
            stopDrag  = re:FindFirstChild("StopDraggingItem")
        end
    end

    -- edge buttons
    local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
    local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
    if not edgeGui then
        edgeGui = Instance.new("ScreenGui"); edgeGui.Name="EdgeButtons"; edgeGui.ResetOnSpawn=false; edgeGui.Parent=playerGui
    end
    local stack = edgeGui:FindFirstChild("EdgeStack")
    if not stack then
        stack = Instance.new("Frame"); stack.Name="EdgeStack"; stack.AnchorPoint=Vector2.new(1,0)
        stack.Position = UDim2.new(1,-6,0,6); stack.Size = UDim2.new(0,130,1,-12); stack.BackgroundTransparency=1; stack.Parent=edgeGui
        local list = Instance.new("UIListLayout")
        list.FillDirection = Enum.FillDirection.Vertical; list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Padding = UDim.new(0,6); list.HorizontalAlignment = Enum.HorizontalAlignment.Right; list.Parent = stack
    end
    local function makeEdgeBtn(name, label, order)
        local b = stack:FindFirstChild(name)
        if not b then
            b = Instance.new("TextButton")
            b.Name = name; b.Size = UDim2.new(1,0,0,30); b.Text = label; b.TextSize = 12; b.Font = Enum.Font.GothamBold
            b.BackgroundColor3 = Color3.fromRGB(30,30,35); b.TextColor3 = Color3.new(1,1,1); b.BorderSizePixel = 0
            b.Visible=false; b.LayoutOrder = order or 1; b.Parent = stack
            local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,8); corner.Parent = b
        else
            b.Text = label; b.LayoutOrder = order or b.LayoutOrder; b.Visible=false
        end
        return b
    end
    local STOP_BTN = makeEdgeBtn("TPBringStop", "STOP", 50)

    -- ========== tuning ==========
    local PICK_RADIUS          = 400
    local ORB_HEIGHT           = 20
    local LAND_MIN             = 0.15   -- tighter cluster
    local LAND_MAX             = 0.35
    local HOVER_ABOVE_ORB      = 0.9
    local ARRIVE_EPS_H         = 0.7
    local STAGE_TIMEOUT_S      = 1.25

    -- release exactly one at a time, very fast
    local RELEASE_INTERVAL     = 0.035  -- ~28 items/sec
    local MAX_STAGED           = 1      -- strictly one pending in queue

    -- repick/flight guards
    local STUCK_TTL            = 6.0
    local INFLT_ATTR           = "OrbInFlightAt"
    local JOB_ATTR             = "OrbJob"
    local DONE_ATTR            = "OrbDelivered"

    -- state
    local CURRENT_RUN_ID = nil
    local running   = false
    local hb        = nil
    local orb       = nil
    local orbPosVec = nil

    local inflight     = {}   -- model -> {snap=..., staged=bool, stagedAt=number}
    local releaseQueue = {}   -- { {model=m, pos=vec3}, ... }
    local releaseTick  = 0

    -- item sets
    local junkItems = {
        "Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine",
        "UFO Junk","UFO Component"
    }
    local fuelItems = {"Log","Coal","Fuel Canister","Oil Barrel"}
    local scrapAlso = { Log=true }

    local fuelSet = {}; for _,n in ipairs(fuelItems) do fuelSet[n]=true end
    local scrapSet = {}; for _,n in ipairs(junkItems) do scrapSet[n]=true end; for k,_ in pairs(scrapAlso) do scrapSet[k]=true end

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
    local function wantedBySet(m, set)
        if not (m and m:IsA("Model") and m.Parent) then return false end
        local itemsFolder = itemsRootOrNil()
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then return false end
        if isWallVariant(m) or isUnderLogWall(m) then return false end
        local nm = m.Name or ""
        if nm == "Chair" then return false end
        return set[nm] == true
    end

    -- orb
    local function spawnOrbAt(pos, color)
        if orb then pcall(function() orb:Destroy() end) end
        local o = Instance.new("Part")
        o.Name="tp_orb_fixed"; o.Shape=Enum.PartType.Ball; o.Size=Vector3.new(1.5,1.5,1.5)
        o.Material=Enum.Material.Neon; o.Color = color or Color3.fromRGB(80,180,255)
        o.Anchored=true; o.CanCollide=false; o.CanTouch=false; o.CanQuery=false
        o.CFrame = CFrame.new(pos + Vector3.new(0, ORB_HEIGHT, 0)); o.Parent = WS
        local l = Instance.new("PointLight"); l.Range=16; l.Brightness=2.5; l.Parent=o
        orb=o; orbPosVec=o.Position
    end
    local function destroyOrb()
        if orb then pcall(function() orb:Destroy() end) orb=nil end
        orbPosVec=nil
    end

    -- positions
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

    -- spread around orb
    local function hash01(s)
        local h = 131071
        for i=1,#s do h=(h*131 + string.byte(s,i))%1000003 end
        return (h%100000)/100000
    end
    local function landingOffset(m, jobId)
        local key = (typeof(m.GetDebugId)=="function" and m:GetDebugId() or (m.Name or "")) .. tostring(jobId)
        local r1 = hash01(key.."a"); local r2 = hash01(key.."b")
        local ang = r1 * math.pi * 2
        local rad = LAND_MIN + (LAND_MAX - LAND_MIN) * r2
        return Vector3.new(math.cos(ang)*rad, 0, math.sin(ang)*rad)
    end

    -- candidate search
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
                    if tIn and jIn and tostring(jIn) ~= jobId and os.clock() - tIn < STUCK_TTL then
                    else
                        uniq[m]=true; out[#out+1]=m
                    end
                end
            end
        end
        return out
    end

    -- stage at orb (teleport), release later
    local function stageAtOrb(m, snap, tgt)
        setAnchored(m, true)
        for _,p in ipairs(allParts(m)) do
            p.CanCollide = false
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
        setPivot(m, CFrame.new(tgt))
        local rec = inflight[m] or {}
        rec.snap = snap; rec.staged = true; rec.stagedAt = os.clock()
        inflight[m] = rec
        table.insert(releaseQueue, {model=m, pos=tgt})
    end

    local function releaseOne()
        local rec = table.remove(releaseQueue, 1)
        if not rec then return end
        local m = rec.model
        if not (m and m.Parent) then return end
        local info = inflight[m]
        local snap = info and info.snap or snapshotCollide(m)

        -- restore natural physics
        setAnchored(m, false)
        zeroAssembly(m)
        setCollideFromSnapshot(snap)
        for _,p in ipairs(allParts(m)) do
            p.AssemblyAngularVelocity = Vector3.new()
            p.AssemblyLinearVelocity  = Vector3.new()
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
        end

        pcall(function()
            m:SetAttribute(INFLT_ATTR, nil)
            m:SetAttribute(JOB_ATTR, nil)
            m:SetAttribute(DONE_ATTR, CURRENT_RUN_ID)
        end)
        inflight[m] = nil
    end

    -- one-item pipeline: teleport to orb then queue single release
    local function startConveyor(m, jobId)
        if not (running and m and m.Parent and orbPosVec) then return end
        local mp = mainPart(m); if not mp then return end

        local off = landingOffset(m, jobId)
        local tgt = Vector3.new(orbPosVec.X + off.X, orbPosVec.Y + HOVER_ABOVE_ORB, orbPosVec.Z + off.Z)

        pcall(function() m:SetAttribute(INFLT_ATTR, os.clock()) end)
        pcall(function() m:SetAttribute(JOB_ATTR, jobId) end)

        local snap = setNoCollide(m)
        zeroAssembly(m)
        setAnchored(m, true)
        if startDrag then pcall(function() startDrag:FireServer(m) end) end

        stageAtOrb(m, snap, tgt)
        if stopDrag then pcall(function() stopDrag:FireServer(m) end) end
    end

    local activeCount = 0
    local CURRENT_TARGET_SET = nil

    local function wave(center)
        local jobId = tostring(os.clock())
        local list = nearbyCandidates(center, PICK_RADIUS, jobId, CURRENT_TARGET_SET or {})
        for i=1,#list do
            if not running then break end
            -- strictly one staged at a time
            while running and (#releaseQueue >= MAX_STAGED) do Run.Heartbeat:Wait() end
            while running and activeCount >= 1 do Run.Heartbeat:Wait() end -- one in-flight op at a time
            local m = list[i]
            if m and m.Parent and not inflight[m] then
                activeCount += 1
                task.spawn(function()
                    startConveyor(m, jobId)
                    activeCount = math.max(0, activeCount-1)
                end)
            end
        end
    end

    local function flushStaleStaged()
        local now = os.clock()
        for m,info in pairs(inflight) do
            if info and info.staged and (now - (info.stagedAt or now)) >= STAGE_TIMEOUT_S then
                local queued=false
                for _,q in ipairs(releaseQueue) do if q.model==m then queued=true; break end end
                if not queued then table.insert(releaseQueue, {model=m, pos=mainPart(m) and mainPart(m).Position or orbPosVec}) end
            end
        end
    end

    local function stopAll()
        running = false
        if hb then hb:Disconnect(); hb=nil end
        STOP_BTN.Visible = false

        -- release anything staged so they are not left frozen
        for i=#releaseQueue,1,-1 do releaseOne() end

        for m,rec in pairs(inflight) do
            if stopDrag then pcall(function() stopDrag:FireServer(m) end) end
            setAnchored(m, false)
            setCollideFromSnapshot(rec and rec.snap or snapshotCollide(m))
            zeroAssembly(m)
            inflight[m] = nil
        end
        activeCount = 0
        destroyOrb()
    end
    STOP_BTN.MouseButton1Click:Connect(stopAll)

    -- start
    local function startAll(mode)
        if running then return end
        if not hrp then return end

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
        releaseQueue = {}
        releaseTick  = os.clock()
        CURRENT_TARGET_SET = set

        if hb then hb:Disconnect() end
        hb = Run.Heartbeat:Connect(function()
            if not running then return end
            local root = hrp(); if root then wave(root.Position) end

            -- release exactly one at fixed cadence
            if #releaseQueue > 0 and (os.clock() - releaseTick) >= RELEASE_INTERVAL then
                releaseTick = os.clock()
                releaseOne()
            end

            flushStaleStaged()
        end)
    end

    -- UI
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
end
