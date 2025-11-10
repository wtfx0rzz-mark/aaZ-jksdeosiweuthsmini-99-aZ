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
    local function setAnchored(m, on)
        for _,p in ipairs(allParts(m)) do p.Anchored = on end
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

    local DRAG_SPEED            = 420
    local PICK_RADIUS           = 220
    local ORB_HEIGHT            = 30
    local UPPER_ORB_OFFSET      = 10
    local MAX_CONCURRENT        = 48
    local START_STAGGER         = 0.004
    local STEP_WAIT             = 0.008

    local LAND_MIN              = 0.18
    local LAND_MAX              = 0.42
    local ARRIVE_EPS_H          = 0.7
    local STALL_SEC             = 0.45

    local HOVER_ABOVE_ORB       = 0.9

    local RELEASE_RATE_HZ       = 45
    local STAGE_TIMEOUT_S       = 2.0
    local ORB_UNSTICK_RAD       = 2.0
    local ORB_UNSTICK_HZ        = 10
    local ORB_WATCHDOG_HZ       = 2

    local DOWNCAST_ALIGN_SPEED  = 240
    local DOWNCAST_EPS_H        = 0.25
    local DOWNCAST_EPS_V        = 0.5
    local G                     = tonumber(WS.Gravity) or 196.2

    local INFLT_ATTR = "OrbInFlightAt"
    local JOB_ATTR   = "OrbJob"
    local DONE_ATTR  = "OrbDelivered"

    local CURRENT_RUN_ID = nil
    local running      = false
    local hb           = nil

    local orbLower     = nil
    local orbLowerPos  = nil
    local orbUpper     = nil
    local orbUpperPos  = nil

    local inflight     = {}
    local releaseQueue = {}
    local releaseAcc   = 0.0
    local CURRENT_DOWNCAST = nil

    local TRANSPORT_MODE = "drag"
    local DEST_BASEPOS, DEST_COLOR = nil, nil

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

    local function spawnLowerOrbAt(pos, color)
        if orbLower then pcall(function() orbLower:Destroy() end) end
        local o = Instance.new("Part")
        o.Name = "tp_orb_fixed_lower"
        o.Shape = Enum.PartType.Ball
        o.Size = Vector3.new(1.5,1.5,1.5)
        o.Material = Enum.Material.Neon
        o.Color = color or Color3.fromRGB(80,180,255)
        o.Anchored, o.CanCollide, o.CanTouch, o.CanQuery = true,false,false,false
        o.CFrame = CFrame.new(pos + Vector3.new(0, ORB_HEIGHT, 0))
        o.Parent = WS
        local l = Instance.new("PointLight"); l.Range = 16; l.Brightness = 2.5; l.Parent = o
        orbLower = o
        orbLowerPos = o.Position
    end
    local function spawnUpperOrbAt(pos, color)
        if orbUpper then pcall(function() orbUpper:Destroy() end) end
        local o = Instance.new("Part")
        o.Name = "tp_orb_fixed_upper"
        o.Shape = Enum.PartType.Ball
        o.Size = Vector3.new(1.25,1.25,1.25)
        o.Material = Enum.Material.Neon
        o.Color = color or Color3.fromRGB(180,240,255)
        o.Anchored, o.CanCollide, o.CanTouch, o.CanQuery = true,false,false,false
        o.CFrame = CFrame.new(pos + Vector3.new(0, ORB_HEIGHT + UPPER_ORB_OFFSET, 0))
        o.Parent = WS
        local l = Instance.new("PointLight"); l.Range = 12; l.Brightness = 1.8; l.Parent = o
        orbUpper = o
        orbUpperPos = o.Position
    end
    local function destroyOrbs()
        if orbLower then pcall(function() orbLower:Destroy() end) orbLower=nil end
        if orbUpper then pcall(function() orbUpper:Destroy() end) orbUpper=nil end
        orbLowerPos, orbUpperPos = nil, nil
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

    local function hash01(s)
        local h = 131071
        for i = 1, #s do h = (h*131 + string.byte(s, i)) % 1000003 end
        return (h % 100000) / 100000
    end
    local function landingOffset(m, jobId)
        local key = (typeof(m.GetDebugId)=="function" and m:GetDebugId() or (m.Name or "")) .. tostring(jobId)
        local r1 = hash01(key .. "a")
        local r2 = hash01(key .. "b")
        local ang = r1 * math.pi * 2
        local rad = LAND_MIN + (LAND_MAX - LAND_MIN) * r2
        return Vector3.new(math.cos(ang)*rad, 0, math.sin(ang)*rad)
    end

    local function stageAtUpper(m, snap, tgt)
        local info = inflight[m]
        if not info then
            info = { snap = snap, staged = false, queued = false, stagedAt = 0, conn = nil }
            inflight[m] = info
        else
            info.snap = info.snap or snap
        end
        setAnchored(m, true)
        for _,p in ipairs(allParts(m)) do
            p.CanCollide = false
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
        setPivot(m, CFrame.new(tgt))
        info.staged   = true
        info.stagedAt = os.clock()
        if not info.queued then
            table.insert(releaseQueue, {model=m})
            info.queued = true
        end
    end
    local function finalizeDelivered(m, info)
        local snap = info and info.snap or snapshotCollide(m)
        setCollideFromSnapshot(snap)
        zeroAssembly(m)
        setAnchored(m, false)
        pcall(function() m:SetAttribute(INFLT_ATTR, nil) end)
        pcall(function() m:SetAttribute(JOB_ATTR, nil) end)
        pcall(function() m:SetAttribute(DONE_ATTR, CURRENT_RUN_ID) end)
        for _,p in ipairs(allParts(m)) do
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
        end
        inflight[m] = nil
    end

    local function dragDownToLower(m)
        if CURRENT_DOWNCAST then return end
        CURRENT_DOWNCAST = m
        local info = inflight[m]; if not info then CURRENT_DOWNCAST=nil return end
        local part = mainPart(m); if not part then CURRENT_DOWNCAST=nil return end

        setAnchored(m, true)
        for _,p in ipairs(allParts(m)) do p.CanCollide = false end
        zeroAssembly(m)

        local vy = 0
        local conn
        conn = Run.Heartbeat:Connect(function(dt)
            if not running or not m or not m.Parent then
                if conn then conn:Disconnect() end
                CURRENT_DOWNCAST = nil
                inflight[m] = nil
                return
            end
            if orbLower then orbLowerPos = orbLower.Position end
            if orbUpper then orbUpperPos = orbUpper.Position end

            local targetPos = orbLowerPos or (DEST_BASEPOS and (DEST_BASEPOS + Vector3.new(0, ORB_HEIGHT, 0))) or part.Position
            local cur = mainPart(m)
            if not cur then
                if conn then conn:Disconnect() end
                CURRENT_DOWNCAST = nil
                inflight[m] = nil
                return
            end

            local pos = cur.Position
            local flat = Vector3.new(targetPos.X - pos.X, 0, targetPos.Z - pos.Z)
            local distH = flat.Magnitude
            local dv = targetPos.Y - pos.Y

            vy = vy + G * dt
            local stepH = math.min(DOWNCAST_ALIGN_SPEED * dt, distH)
            local dirH  = distH > 1e-3 and (flat / math.max(distH,1e-3)) or Vector3.new()

            local newPos = Vector3.new(
                pos.X + dirH.X * stepH,
                pos.Y + vy * dt,
                pos.Z + dirH.Z * stepH
            )

            if (Vector3.new(newPos.X, 0, newPos.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude <= DOWNCAST_EPS_H
               and math.abs(targetPos.Y - newPos.Y) <= DOWNCAST_EPS_V then
                setPivot(m, CFrame.new(Vector3.new(targetPos.X, targetPos.Y, targetPos.Z)))
                if conn then conn:Disconnect() end
                finalizeDelivered(m, info)
                CURRENT_DOWNCAST = nil
                return
            end

            setPivot(m, CFrame.new(newPos, newPos + (dirH.Magnitude>0 and dirH or Vector3.new(0,0,1))))
        end)
    end

    local function startConveyor(m, jobId)
        if not (running and m and m.Parent and orbUpperPos) then return end
        local mp = mainPart(m); if not mp then return end
        local off = landingOffset(m, jobId)
        local function targetUpper()
            local base = orbUpperPos or mp.Position
            return Vector3.new(base.X + off.X, base.Y + HOVER_ABOVE_ORB, base.Z + off.Z)
        end
        pcall(function() m:SetAttribute(INFLT_ATTR, os.clock()) end)
        pcall(function() m:SetAttribute(JOB_ATTR, jobId) end)
        local snap = setNoCollide(m)
        setAnchored(m, true)
        zeroAssembly(m)
        if startDrag then pcall(function() startDrag:FireServer(m) end) end
        if not inflight[m] then inflight[m] = { snap = snap, conn = nil, lastD = math.huge, lastT = os.clock(), staged = false, queued=false } end

        if TRANSPORT_MODE == "teleport" then
            stageAtUpper(m, snap, targetUpper())
            return
        end

        local rec = inflight[m]
        rec.conn = Run.Heartbeat:Connect(function(dt)
            if not (running and m and m.Parent and orbUpperPos) then
                if rec.conn then rec.conn:Disconnect() end
                inflight[m] = nil
                return
            end
            if rec.staged then return end
            local pivot = m:IsA("Model") and m:GetPivot() or (mp and mp.CFrame)
            if not pivot then
                if rec.conn then rec.conn:Disconnect() end
                inflight[m] = nil
                return
            end
            local pos = pivot.Position
            local tgt = targetUpper()
            local flatDelta = Vector3.new(tgt.X - pos.X, 0, tgt.Z - pos.Z)
            local distH = flatDelta.Magnitude
            if distH <= ARRIVE_EPS_H and math.abs(tgt.Y - pos.Y) <= 1.0 then
                if stopDrag then pcall(function() stopDrag:FireServer(m) end) end
                stageAtUpper(m, snap, tgt)
                if rec.conn then rec.conn:Disconnect() end
                return
            end
            if distH >= rec.lastD - 0.02 then
                if os.clock() - rec.lastT >= STALL_SEC then
                    off = landingOffset(m, tostring(jobId) .. tostring(os.clock()))
                    rec.lastT = os.clock()
                end
            else
                rec.lastT = os.clock()
            end
            rec.lastD = distH

            local step = math.min(DRAG_SPEED * dt, math.max(0, distH))
            local dir  = distH > 1e-3 and (flatDelta / math.max(distH,1e-3)) or Vector3.new()
            local vy   = math.clamp((tgt.Y - pos.Y), -7, 7)
            local newPos = Vector3.new(pos.X, pos.Y + vy * dt * 10, pos.Z) + dir * step
            setPivot(m, CFrame.new(newPos, newPos + (dir.Magnitude>0 and dir or Vector3.new(0,0,1))))
        end)
    end

    local activeCount = 0
    local CURRENT_TARGET_SET = nil

    local function wave(center)
        local jobId = tostring(os.clock())
        local list = nearbyCandidates(center, PICK_RADIUS, jobId, CURRENT_TARGET_SET or {})
        for i=1,#list do
            if not running then break end
            while running and activeCount >= MAX_CONCURRENT do Run.Heartbeat:Wait() end
            local m = list[i]
            if m and m.Parent and not inflight[m] then
                activeCount += 1
                task.spawn(function()
                    startConveyor(m, jobId)
                    task.delay(8, function() activeCount = math.max(0, activeCount-1) end)
                end)
                task.wait(START_STAGGER)
            end
        end
    end

    local function flushStaleStaged()
        local now = os.clock()
        for m,info in pairs(inflight) do
            if info and info.staged and (now - (info.stagedAt or now)) >= STAGE_TIMEOUT_S then
                local queued = false
                for _,rec in ipairs(releaseQueue) do if rec.model == m then queued = true; break end end
                if not queued then
                    table.insert(releaseQueue, {model=m})
                    info.queued = true
                end
            end
        end
    end

    do
        local acc = 0
        Run.Heartbeat:Connect(function(dt)
            if not running then return end
            if orbLower then orbLowerPos = orbLower.Position end
            if orbUpper then orbUpperPos = orbUpper.Position end

            acc = acc + dt
            if acc < (1/ORB_UNSTICK_HZ) then return end
            acc = 0
            local items = itemsRootOrNil(); if not items or not orbLowerPos then return end
            for _,m in ipairs(items:GetChildren()) do
                if not m:IsA("Model") then continue end
                local mp = mainPart(m); if not mp then continue end
                if (mp.Position - orbLowerPos).Magnitude <= ORB_UNSTICK_RAD then
                    for _,p in ipairs(allParts(m)) do
                        p.Anchored = false
                        p.AssemblyAngularVelocity = Vector3.new()
                        p.AssemblyLinearVelocity  = Vector3.new()
                        p.CanCollide = true
                    end
                end
            end
        end)
    end

    do
        local orbWatchAcc = 0
        Run.Heartbeat:Connect(function(dt)
            if not running then return end
            orbWatchAcc += dt
            if orbWatchAcc >= (1/ORB_WATCHDOG_HZ) then
                orbWatchAcc = 0
                if DEST_BASEPOS and (not orbLower or not orbLower.Parent) then
                    spawnLowerOrbAt(DEST_BASEPOS, DEST_COLOR)
                end
                if DEST_BASEPOS and (not orbUpper or not orbUpper.Parent) then
                    spawnUpperOrbAt(DEST_BASEPOS, DEST_COLOR)
                end
            end
        end)
    end

    local function stopAll()
        running = false
        if hb then hb:Disconnect() end
        STOP_BTN.Visible = false

        for i=#releaseQueue,1,-1 do
            local rec = releaseQueue[i]
            if rec and rec.model and rec.model.Parent then
                finalizeDelivered(rec.model, inflight[rec.model])
            end
            table.remove(releaseQueue, i)
        end
        for m,rec in pairs(inflight) do
            if rec and rec.conn then rec.conn:Disconnect() end
            if stopDrag then pcall(function() stopDrag:FireServer(m) end) end
            setAnchored(m, false)
            setCollideFromSnapshot(rec and rec.snap or snapshotCollide(m))
            inflight[m] = nil
        end
        activeCount = 0
        CURRENT_DOWNCAST = nil
        DEST_BASEPOS, DEST_COLOR = nil, nil
        destroyOrbs()
    end

    STOP_BTN.MouseButton1Click:Connect(stopAll)

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

    local function startAll(kind, transport)
        if running then return end
        if not hrp() then return end
        TRANSPORT_MODE = transport or "drag"
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
        DEST_BASEPOS, DEST_COLOR = pos, color
        spawnLowerOrbAt(pos, color)
        spawnUpperOrbAt(pos, color)

        running = true
        STOP_BTN.Visible = true
        releaseQueue = {}
        releaseAcc   = 0
        CURRENT_DOWNCAST = nil
        local TARGET = set
        if hb then hb:Disconnect() end

        hb = Run.Heartbeat:Connect(function(dt)
            if not running then return end
            local root = hrp(); if root then wave(root.Position) end

            releaseAcc = releaseAcc + dt
            local interval = 1 / RELEASE_RATE_HZ
            if releaseAcc >= interval then
                releaseAcc = releaseAcc - interval
                if CURRENT_DOWNCAST == nil then
                    local rec = table.remove(releaseQueue, 1)
                    if rec and rec.model and rec.model.Parent then
                        dragDownToLower(rec.model)
                    end
                end
            end

            flushStaleStaged()
            task.wait(STEP_WAIT)
        end)

        CURRENT_TARGET_SET = TARGET
    end

    tab:Button({ Title = "Send Fuel",  Callback = function() if running then return end startAll("fuel",  "drag")     end })
    tab:Button({ Title = "Send Scrap", Callback = function() if running then return end startAll("scrap", "drag")     end })
    tab:Button({ Title = "Send Fuel (Teleport)",  Callback = function() if running then return end startAll("fuel",  "teleport") end })
    tab:Button({ Title = "Send Scrap (Teleport)", Callback = function() if running then return end startAll("scrap", "teleport") end })

    Players.LocalPlayer.CharacterAdded:Connect(function()
        if running and DEST_BASEPOS then
            spawnLowerOrbAt(DEST_BASEPOS, DEST_COLOR)
            spawnUpperOrbAt(DEST_BASEPOS, DEST_COLOR)
        end
    end)
end
