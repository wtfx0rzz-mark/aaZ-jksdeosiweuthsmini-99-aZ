--=====================================================
-- 1337 Nights | Auto Tab • Edge Buttons + Lost Child Toggle + Instant Interact
--  • Hard-stick teleports to ensure server-side position commit
--  • Teleport + Campfire use noclip dive-under workaround before TP
--  • Load Defense: force any "DataHasLoaded" flag TRUE continuously
--=====================================================
return function(C, R, UI)
    local Players = (C and C.Services and C.Services.Players) or game:GetService("Players")
    local RS      = (C and C.Services and C.Services.RS)      or game:GetService("ReplicatedStorage")
    local WS      = (C and C.Services and C.Services.WS)      or game:GetService("Workspace")
    local PPS     = game:GetService("ProximityPromptService")
    local Run     = (C and C.Services and C.Services.Run)     or game:GetService("RunService")

    local lp = Players.LocalPlayer
    local Tabs = (UI and UI.Tabs) or {}
    local tab  = Tabs.Auto
    if not tab then
        warn("[Auto] Auto tab not found in UI")
        return
    end

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local function getHumanoid()
        local ch = lp.Character
        return ch and ch:FindFirstChildOfClass("Humanoid")
    end
    local function mainPart(model)
        if not (model and model:IsA("Model")) then return nil end
        if model.PrimaryPart then return model.PrimaryPart end
        return model:FindFirstChildWhichIsA("BasePart")
    end
    local function getRemote(name)
        local f = RS:FindFirstChild("RemoteEvents")
        return f and f:FindFirstChild(name) or nil
    end
    local function zeroAssembly(root)
        if not root then return end
        root.AssemblyLinearVelocity  = Vector3.new(0,0,0)
        root.AssemblyAngularVelocity = Vector3.new(0,0,0)
    end

    local STICK_DURATION    = 0.35
    local STICK_EXTRA_FR    = 2
    local STICK_CLEAR_VEL   = true
    local TELEPORT_UP_NUDGE = 0.05

    local function snapshotCollide()
        local ch = lp.Character
        if not ch then return {} end
        local t = {}
        for _,d in ipairs(ch:GetDescendants()) do
            if d:IsA("BasePart") then t[d] = d.CanCollide end
        end
        return t
    end
    local function setCollideAll(on, snapshot)
        local ch = lp.Character
        if not ch then return end
        if on and snapshot then
            for part,can in pairs(snapshot) do
                if part and part.Parent then part.CanCollide = can end
            end
        else
            for _,d in ipairs(ch:GetDescendants()) do
                if d:IsA("BasePart") then d.CanCollide = false end
            end
        end
    end
    local function isNoclipNow()
        local ch = lp.Character
        if not ch then return false end
        local total, off = 0, 0
        for _,d in ipairs(ch:GetDescendants()) do
            if d:IsA("BasePart") then
                total += 1
                if d.CanCollide == false then off += 1 end
            end
        end
        return (total > 0) and ((off / total) >= 0.9) or false
    end

    local function teleportSticky(cf)
        local root = hrp(); if not root then return end
        local ch   = lp.Character
        local targetCF = cf + Vector3.new(0, TELEPORT_UP_NUDGE, 0)

        local hadNoclip = isNoclipNow()
        local snap
        if not hadNoclip then
            snap = snapshotCollide()
            setCollideAll(false)
        end

        if ch then pcall(function() ch:PivotTo(targetCF) end) end
        pcall(function() root.CFrame = targetCF end)
        if STICK_CLEAR_VEL then zeroAssembly(root) end

        local t0 = os.clock()
        while (os.clock() - t0) < STICK_DURATION do
            if ch then pcall(function() ch:PivotTo(targetCF) end) end
            pcall(function() root.CFrame = targetCF end)
            if STICK_CLEAR_VEL then zeroAssembly(root) end
            Run.Heartbeat:Wait()
        end
        for _=1,STICK_EXTRA_FR do
            if ch then pcall(function() ch:PivotTo(targetCF) end) end
            pcall(function() root.CFrame = targetCF end)
            if STICK_CLEAR_VEL then zeroAssembly(root) end
            Run.Heartbeat:Wait()
        end

        if not hadNoclip then
            setCollideAll(true, snap)
        end
        if STICK_CLEAR_VEL then zeroAssembly(root) end
    end

    local function diveBelowGround(depth, frames)
        local root = hrp(); if not root then return end
        local ch = lp.Character
        local look = root.CFrame.LookVector
        local dest = root.Position + Vector3.new(0, -math.abs(depth), 0)
        for _=1,(frames or 4) do
            local cf = CFrame.new(dest, dest + look)
            if ch then pcall(function() ch:PivotTo(cf) end) end
            pcall(function() root.CFrame = cf end)
            zeroAssembly(root)
            Run.Heartbeat:Wait()
        end
    end
    local function waitUntilGroundedOrMoving(timeout)
        local h = getHumanoid()
        local t0 = os.clock()
        local groundedFrames = 0
        while os.clock() - t0 < (timeout or 3) do
            if h then
                local grounded = (h.FloorMaterial ~= Enum.Material.Air)
                if grounded then groundedFrames += 1 else groundedFrames = 0 end
                if groundedFrames >= 5 then
                    local t1 = os.clock()
                    while os.clock() - t1 < 0.35 do
                        if h.MoveDirection.Magnitude > 0.05 then return true end
                        Run.Heartbeat:Wait()
                    end
                    return true
                end
            end
            Run.Heartbeat:Wait()
        end
        return false
    end
    local DIVE_DEPTH = 200
    local function teleportWithDive(targetCF)
        local root = hrp(); if not root then return end
        local snap = snapshotCollide()
        setCollideAll(false)
        diveBelowGround(DIVE_DEPTH, 4)
        teleportSticky(targetCF)
        waitUntilGroundedOrMoving(3)
        setCollideAll(true, snap)
    end

    local function fireCenterPart(fire)
        return fire:FindFirstChild("Center")
            or fire:FindFirstChild("InnerTouchZone")
            or mainPart(fire)
            or fire.PrimaryPart
    end
    local function resolveCampfireModel()
        local map = WS:FindFirstChild("Map")
        local cg  = map and map:FindFirstChild("Campground")
        local mf  = cg and cg:FindFirstChild("MainFire")
        if mf then return mf end
        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") then
                local n = (d.Name or ""):lower()
                if n == "mainfire" or n == "campfire" or n == "camp fire" then
                    return d
                end
            end
        end
        return nil
    end
    local function groundBelow(pos)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {lp.Character}
        local rc = WS:Raycast(pos + Vector3.new(0, 200, 0), Vector3.new(0, -1000, 0), params)
        return rc and rc.Position or pos
    end
    local function campfireTeleportCF()
        local fire = resolveCampfireModel(); if not fire then return nil end
        local center = fireCenterPart(fire); if not center then return fire:GetPivot() end
        local look   = center.CFrame.LookVector
        local zone   = fire:FindFirstChild("InnerTouchZone")
        local offset = 6
        if zone and zone:IsA("BasePart") then
            offset = math.max(zone.Size.X, zone.Size.Z) * 0.5 + 4
        end
        local targetPos = center.Position + look * offset + Vector3.new(0, 3, 0)
        local g = groundBelow(targetPos)
        local finalPos = Vector3.new(targetPos.X, g.Y + 2.5, targetPos.Z)
        return CFrame.new(finalPos, center.Position)
    end

    local PHASE_DIST = 10

    local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
    local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
    if not edgeGui then
        edgeGui = Instance.new("ScreenGui")
        edgeGui.Name = "EdgeButtons"
        edgeGui.ResetOnSpawn = false
        edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        edgeGui.Parent = playerGui
    end

    local function makeEdgeBtn(name, row, label)
        local b = edgeGui:FindFirstChild(name)
        if not b then
            b = Instance.new("TextButton")
            b.Name = name
            b.AnchorPoint = Vector2.new(1, 0)
            b.Position    = UDim2.new(1, -6, 0, 6 + (row-1)*36)
            b.Size        = UDim2.new(0, 120, 0, 30)
            b.Text        = label
            b.TextSize    = 12
            b.Font        = Enum.Font.GothamBold
            b.BackgroundColor3 = Color3.fromRGB(30,30,35)
            b.TextColor3  = Color3.new(1,1,1)
            b.BorderSizePixel = 0
            b.Visible     = false
            b.Parent      = edgeGui
            local corner  = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 8)
            corner.Parent = b
        else
            b.Text = label
            b.Visible = false
        end
        return b
    end

    local phaseBtn = makeEdgeBtn("Phase10Edge", 1, "Phase 10")
    local tpBtn    = makeEdgeBtn("TpEdge",      2, "Teleport")
    local plantBtn = makeEdgeBtn("PlantEdge",   3, "Plant")
    local lostBtn  = makeEdgeBtn("LostEdge",    4, "Lost Child")
    local campBtn  = makeEdgeBtn("CampEdge",    5, "Campfire")
    campBtn.Visible = true

    phaseBtn.MouseButton1Click:Connect(function()
        local root = hrp()
        if not root then return end
        local dest = root.Position + root.CFrame.LookVector * PHASE_DIST
        teleportSticky(CFrame.new(dest, dest + root.CFrame.LookVector))
    end)

    local markedCF = nil
    local HOLD_THRESHOLD = 0.5
    local downAt, suppressClick = 0, false

    tpBtn.MouseButton1Down:Connect(function()
        downAt = os.clock()
        suppressClick = false
    end)
    tpBtn.MouseButton1Up:Connect(function()
        local held = os.clock() - (downAt or 0)
        if held >= HOLD_THRESHOLD then
            local root = hrp()
            if root then
                markedCF = root.CFrame
                suppressClick = true
                local old = tpBtn.Text
                tpBtn.Text = "Marked!"
                task.delay(0.6, function()
                    if tpBtn then tpBtn.Text = old end
                end)
            end
        end
    end)
    tpBtn.MouseButton1Click:Connect(function()
        if suppressClick then suppressClick = false return end
        if not markedCF then return end
        teleportWithDive(markedCF)
    end)

    campBtn.MouseButton1Click:Connect(function()
        local cf = campfireTeleportCF()
        if cf then teleportWithDive(cf) end
    end)

    local AHEAD_DIST  = 3
    local RAY_HEIGHT  = 500
    local RAY_DEPTH   = 2000
    local function groundAhead(root)
        local base   = root.Position + root.CFrame.LookVector * AHEAD_DIST
        local start  = base + Vector3.new(0, RAY_HEIGHT, 0)
        local result = WS:Raycast(start, Vector3.new(0, -RAY_DEPTH, 0))
        return result and result.Position or base
    end
    local function findClosestSapling()
        local items = WS:FindFirstChild("Items")
        local root  = hrp()
        if not (items and root) then return nil end
        local closest, bestDist = nil, math.huge
        for _,m in ipairs(items:GetChildren()) do
            if m:IsA("Model") and m.Name == "Sapling" then
                local mp = mainPart(m)
                if mp then
                    local d = (mp.Position - root.Position).Magnitude
                    if d < bestDist then bestDist, closest = d, m end
                end
            end
        end
        return closest
    end
    local function plantNearestSaplingInFront()
        local sapling = findClosestSapling()
        if not sapling then return end
        local startDrag = getRemote("RequestStartDraggingItem")
        local stopDrag  = getRemote("StopDraggingItem")
        local plantRF   = getRemote("RequestPlantItem")
        if not plantRF then return end

        local root = hrp(); if not root then return end
        local plantPos = groundAhead(root)

        if startDrag then
            pcall(function() startDrag:FireServer(sapling) end)
            pcall(function() startDrag:FireServer(Instance.new("Model")) end)
        end
        task.wait(0.05)

        local ok = pcall(function()
            return plantRF:InvokeServer(sapling, Vector3.new(plantPos.X, plantPos.Y, plantPos.Z))
        end)
        if not ok then
            local dummy = Instance.new("Model")
            ok = pcall(function()
                return plantRF:InvokeServer(dummy, Vector3.new(plantPos.X, plantPos.Y, plantPos.Z))
            end)
        end
        if not ok then
            pcall(function() plantRF:FireServer(sapling, Vector3.new(plantPos.X, plantPos.Y, plantPos.Z)) end)
            pcall(function() plantRF:FireServer(Instance.new("Model"), Vector3.new(plantPos.X, plantPos.Y, plantPos.Z)) end)
        end
        task.wait(0.05)
        if stopDrag then
            pcall(function() stopDrag:FireServer(sapling) end)
            pcall(function() stopDrag:FireServer(Instance.new("Model")) end)
        end
    end
    plantBtn.MouseButton1Click:Connect(function() plantNearestSaplingInFront() end)

    local MAX_TO_SAVE   = 4
    local savedCount    = 0
    local autoLostEnabled = true
    local lostEligible  = setmetatable({}, {__mode="k"})

    local function isLostChildModel(m)
        return m and m:IsA("Model") and m.Name:match("^Lost Child")
    end

    local function refreshLostBtn()
        local anyEligible = next(lostEligible) ~= nil
        lostBtn.Visible = autoLostEnabled and (savedCount < MAX_TO_SAVE) and anyEligible
    end

    local function onLostAttrChange(m)
        local v = m:GetAttribute("Lost") == true
        local was = lostEligible[m] == true
        if v then
            lostEligible[m] = true
        else
            if was and savedCount < MAX_TO_SAVE then
                savedCount += 1
            end
            lostEligible[m] = nil
        end
        refreshLostBtn()
    end

    local function trackLostModel(m)
        if not isLostChildModel(m) then return end
        onLostAttrChange(m)
        m:GetAttributeChangedSignal("Lost"):Connect(function() onLostAttrChange(m) end)
        m.AncestryChanged:Connect(function(_, parent)
            if not parent then
                lostEligible[m] = nil
                refreshLostBtn()
            end
        end)
    end

    for _,d in ipairs(WS:GetDescendants()) do trackLostModel(d) end
    WS.DescendantAdded:Connect(trackLostModel)

    local function findNearestEligibleLost()
        local root = hrp(); if not root then return nil end
        local best, bestD = nil, math.huge
        for m,_ in pairs(lostEligible) do
            local mp = mainPart(m)
            if mp then
                local dist = (mp.Position - root.Position).Magnitude
                if dist < bestD then bestD, best = dist, m end
            end
        end
        return best
    end

    local function teleportToNearestLost()
        if savedCount >= MAX_TO_SAVE then return end
        local target = findNearestEligibleLost()
        if not target then return end
        local mp = mainPart(target)
        if mp then
            teleportWithDive(CFrame.new(mp.Position + Vector3.new(0, 3, 0), mp.Position))
        end
    end
    lostBtn.MouseButton1Click:Connect(function() teleportToNearestLost() end)

    local loadDefenseOn = false
    local ldHB, ldConnWS, ldConnRS, ldConnPLR
    local logLoadDefense = false

    local function forceOn(inst)
        local ok, val = pcall(function() return inst:GetAttribute("DataHasLoaded") end)
        if ok and val == false then
            pcall(function() inst:SetAttribute("DataHasLoaded", true) end)
            if logLoadDefense then print("[LD] Attr->true on", inst:GetFullName()) end
        end
        if inst:IsA("BoolValue") and inst.Name == "DataHasLoaded" and inst.Value == false then
            pcall(function() inst.Value = true end)
            if logLoadDefense then print("[LD] Bool->true on", inst:GetFullName()) end
        end
    end
    local function hookOne(inst)
        pcall(function()
            if inst:GetAttribute("DataHasLoaded") ~= nil then
                inst:GetAttributeChangedSignal("DataHasLoaded"):Connect(function()
                    if loadDefenseOn then forceOn(inst) end
                end)
            end
        end)
        if inst:IsA("BoolValue") and inst.Name == "DataHasLoaded" then
            inst.Changed:Connect(function(prop)
                if loadDefenseOn and prop == "Value" then forceOn(inst) end
            end)
        end
        forceOn(inst)
    end
    local function scanAll()
        for _,container in ipairs({workspace, ReplicatedStorage, Players.LocalPlayer}) do
            for _,d in ipairs(container:GetDescendants()) do hookOne(d) end
        end
    end
    local function enableLoadDefense()
        if loadDefenseOn then return end
        loadDefenseOn = true
        scanAll()
        local acc = 0
        ldHB = Run.Heartbeat:Connect(function(dt)
            acc += dt
            if acc < 0.05 then return end
            acc = 0
            for _,container in ipairs({workspace, ReplicatedStorage, Players.LocalPlayer}) do
                for _,d in ipairs(container:GetDescendants()) do forceOn(d) end
            end
        end)
        ldConnWS = workspace.DescendantAdded:Connect(hookOne)
        ldConnRS = ReplicatedStorage.DescendantAdded:Connect(hookOne)
        ldConnPLR = Players.LocalPlayer.DescendantAdded:Connect(hookOne)
    end
    local function disableLoadDefense()
        loadDefenseOn = false
        if ldHB then ldHB:Disconnect() ldHB = nil end
        if ldConnWS then ldConnWS:Disconnect() ldConnWS = nil end
        if ldConnRS then ldConnRS:Disconnect() ldConnRS = nil end
        if ldConnPLR then ldConnPLR:Disconnect() ldConnPLR = nil end
    end

    tab:Section({ Title = "Quick Moves", Icon = "zap" })

    tab:Toggle({
        Title = "Show Phase 10 button",
        Value = false,
        Callback = function(state) phaseBtn.Visible = state end
    })
    tab:Toggle({
        Title = "Show Teleport button",
        Value = false,
        Callback = function(state) tpBtn.Visible = state end
    })
    tab:Toggle({
        Title = "Plant Saplings",
        Value = false,
        Callback = function(state) plantBtn.Visible = state end
    })
    tab:Toggle({
        Title = "Auto Teleport to Lost Child",
        Value = true,
        Callback = function(state)
            autoLostEnabled = state
            refreshLostBtn()
        end
    })
    tab:Toggle({
        Title = "Show Campfire button",
        Value = true,
        Callback = function(state) campBtn.Visible = state end
    })
    tab:Toggle({
        Title = "Load Defense",
        Value = false,
        Callback = function(state)
            if state then enableLoadDefense() else disableLoadDefense() end
        end
    })

    local INSTANT_HOLD     = 0.2
    local TRIGGER_COOLDOWN = 0.4
    local EXCLUDE_NAME_SUBSTR = { "door", "closet", "gate", "hatch" }
    local EXCLUDE_ANCESTOR_SUBSTR = { "closetdoors", "closet", "door", "landmarks" }

    local function strfindAny(s, list)
        s = string.lower(s or "")
        for _, w in ipairs(list) do
            if string.find(s, w, 1, true) then return true end
        end
        return false
    end
    local function shouldSkipPrompt(p)
        if not p or not p.Parent then return true end
        if strfindAny(p.Name, EXCLUDE_NAME_SUBSTR) then return true end
        pcall(function()
            if strfindAny(p.ObjectText, EXCLUDE_NAME_SUBSTR) then error(true) end
            if strfindAny(p.ActionText, EXCLUDE_NAME_SUBSTR) then error(true) end
        end)
        local a = p.Parent
        while a and a ~= workspace do
            if strfindAny(a.Name, EXCLUDE_ANCESTOR_SUBSTR) then return true end
            a = a.Parent
        end
        return false
    end

    local promptDurations = setmetatable({}, { __mode = "k" })
    local shownConn, trigConn, hiddenConn

    local function restorePrompt(prompt)
        local orig = promptDurations[prompt]
        if orig ~= nil and prompt and prompt.Parent then
            pcall(function() prompt.HoldDuration = orig end)
        end
        promptDurations[prompt] = nil
    end
    local function onPromptShown(prompt)
        if not prompt or not prompt:IsA("ProximityPrompt") then return end
        if shouldSkipPrompt(prompt) then return end
        if promptDurations[prompt] == nil then
            promptDurations[prompt] = prompt.HoldDuration
        end
        task.defer(function()
            if prompt and prompt.Parent and not shouldSkipPrompt(prompt) then
                pcall(function() prompt.HoldDuration = INSTANT_HOLD end)
            end
        end)
    end
    local function enableInstantInteract()
        if shownConn then return end
        shownConn  = PPS.PromptShown:Connect(onPromptShown)
        trigConn   = PPS.PromptTriggered:Connect(function(prompt, player)
            if player ~= lp or shouldSkipPrompt(prompt) then return end
            pcall(function() prompt.Enabled = false end)
            task.delay(TRIGGER_COOLDOWN, function()
                if prompt and prompt.Parent then pcall(function() prompt.Enabled = true end) end
            end)
            restorePrompt(prompt)
        end)
        hiddenConn = PPS.PromptHidden:Connect(function(prompt)
            if shouldSkipPrompt(prompt) then return end
            restorePrompt(prompt)
        end)
    end
    local function disableInstantInteract()
        if shownConn  then shownConn:Disconnect();  shownConn  = nil end
        if trigConn   then trigConn:Disconnect();   trigConn   = nil end
        if hiddenConn then hiddenConn:Disconnect(); hiddenConn = nil end
        for p,_ in pairs(promptDurations) do
            restorePrompt(p)
        end
    end
    enableInstantInteract()
    tab:Toggle({
        Title = "Instant Interact",
        Value = true,
        Callback = function(state)
            if state then enableInstantInteract() else disableInstantInteract() end
        end
    })

    Players.LocalPlayer.CharacterAdded:Connect(function()
        if edgeGui.Parent ~= playerGui then
            edgeGui.Parent = playerGui
        end
    end)
end
