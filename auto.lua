return function(C, R, UI)
    local function run()
        local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
        local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
        local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
        local PPS      = game:GetService("ProximityPromptService")
        local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")
        local UIS      = game:GetService("UserInputService")
        local Lighting = (C and C.Services and C.Services.Lighting) or game:GetService("Lighting")
        local VIM      = game:GetService("VirtualInputManager")

        local lp = Players.LocalPlayer
        local Tabs = (UI and UI.Tabs) or {}
        local tab  = Tabs.Auto
        if not tab then return end

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
        local SAFE_DROP_UP      = 4.0
        local STREAM_TIMEOUT    = 6.0

        local function requestStreamAt(pos, timeout)
            local p = typeof(pos) == "CFrame" and pos.Position or pos
            local ok, res = pcall(function() return WS:RequestStreamAroundAsync(p, timeout or STREAM_TIMEOUT) end)
            return ok and res or false
        end
        local function prefetchRing(cf, r)
            local base = typeof(cf)=="CFrame" and cf.Position or cf
            r = r or 80
            local o = {
                Vector3.new( 0,0, 0),
                Vector3.new( r,0, 0), Vector3.new(-r,0, 0),
                Vector3.new( 0,0, r), Vector3.new( 0,0,-r),
                Vector3.new( r,0, r), Vector3.new( r,0,-r),
                Vector3.new(-r,0, r), Vector3.new(-r,0,-r),
            }
            for i=1,#o do requestStreamAt(base + o[i]) end
        end
        local function waitGameplayResumed(timeout)
            local t0 = os.clock()
            while lp and lp.GameplayPaused do
                if os.clock() - t0 > (timeout or STREAM_TIMEOUT) then break end
                Run.Heartbeat:Wait()
            end
        end

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

        local function teleportSticky(cf, dropMode)
            local root = hrp(); if not root then return end
            local ch   = lp.Character
            local targetCF = cf + Vector3.new(0, TELEPORT_UP_NUDGE, 0)

            prefetchRing(targetCF)
            requestStreamAt(targetCF)
            waitGameplayResumed(1.0)

            local hadNoclip = isNoclipNow()
            local snap
            if not hadNoclip then
                snap = snapshotCollide()
                setCollideAll(false)
            end

            if ch then pcall(function() ch:PivotTo(targetCF) end) end
            pcall(function() root.CFrame = targetCF end)
            if STICK_CLEAR_VEL then zeroAssembly(root) end

            if dropMode then
                if not hadNoclip then setCollideAll(true, snap) end
                waitGameplayResumed(1.0)
                return
            end

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
            waitGameplayResumed(1.0)
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
            local upCF = targetCF + Vector3.new(0, SAFE_DROP_UP, 0)
            prefetchRing(upCF)
            requestStreamAt(upCF)
            waitGameplayResumed(1.0)

            local root = hrp(); if not root then return end
            local snap = snapshotCollide()
            setCollideAll(false)
            diveBelowGround(DIVE_DEPTH, 4)
            teleportSticky(upCF, true)
            waitUntilGroundedOrMoving(3)
            setCollideAll(true, snap)
            waitGameplayResumed(1.0)
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
            local ex = { lp.Character }
            local map = WS:FindFirstChild("Map")
            if map then
                local fol = map:FindFirstChild("Foliage")
                if fol then table.insert(ex, fol) end
            end
            local items = WS:FindFirstChild("Items");      if items then table.insert(ex, items) end
            local chars = WS:FindFirstChild("Characters"); if chars then table.insert(ex, chars) end
            params.FilterDescendantsInstances = ex

            local start = pos + Vector3.new(0, 5, 0)
            local hit = WS:Raycast(start, Vector3.new(0, -1000, 0), params)
            if hit then return hit.Position end

            hit = WS:Raycast(pos + Vector3.new(0, 200, 0), Vector3.new(0, -1000, 0), params)
            return (hit and hit.Position) or pos
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
            pcall(function() edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
            edgeGui.Parent = playerGui
        end

        local stack = edgeGui:FindFirstChild("EdgeStack")
        if not stack then
            stack = Instance.new("Frame")
            stack.Name = "EdgeStack"
            stack.AnchorPoint = Vector2.new(1, 0)
            stack.Position = UDim2.new(1, -6, 0, 6)
            stack.Size = UDim2.new(0, 130, 1, -12)
            stack.BackgroundTransparency = 1
            stack.BorderSizePixel = 0
            stack.Parent = edgeGui
            local list = Instance.new("UIListLayout")
            list.Name = "VList"
            list.FillDirection = Enum.FillDirection.Vertical
            list.SortOrder = Enum.SortOrder.LayoutOrder
            list.Padding = UDim.new(0, 6)
            list.HorizontalAlignment = Enum.HorizontalAlignment.Right
            list.Parent = stack
        end

        local function ensureBtn(name, label, order, visible)
            local b = stack:FindFirstChild(name)
            if not b then
                b = Instance.new("TextButton")
                b.Name = name
                b.Size = UDim2.new(1, 0, 0, 30)
                b.Text = label
                b.TextSize = 12
                b.Font = Enum.Font.GothamBold
                b.BackgroundColor3 = Color3.fromRGB(30,30,35)
                b.TextColor3 = Color3.new(1,1,1)
                b.BorderSizePixel = 0
                b.Visible = visible or false
                b.LayoutOrder = order or 1
                b.Parent = stack
                local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = b
            else
                b.Text = label
                b.LayoutOrder = order or b.LayoutOrder
                if visible ~= nil then b.Visible = visible end
            end
            return b
        end

        local phaseBtn = ensureBtn("Phase10Edge", "Phase 10", 1, false)
        local tpBtn    = ensureBtn("TpEdge",      "Teleport", 2, false)
        local plantBtn = ensureBtn("PlantEdge",   "Plant",     3, false)
        local lostBtn  = ensureBtn("LostEdge",    "Lost Child",4, false)
        local campBtn  = ensureBtn("CampEdge",    "Campfire",  5, true)

        phaseBtn.MouseButton1Click:Connect(function()
            local root = hrp(); if not root then return end
            local dest = root.Position + root.CFrame.LookVector * PHASE_DIST
            teleportSticky(CFrame.new(dest, dest + root.CFrame.LookVector))
        end)

        local markedCF, HOLD_THRESHOLD, downAt, suppressClick = nil, 0.5, 0, false
        tpBtn.MouseButton1Down:Connect(function() downAt = os.clock(); suppressClick = false end)
        tpBtn.MouseButton1Up:Connect(function()
            local held = os.clock() - (downAt or 0)
            if held >= HOLD_THRESHOLD then
                local root = hrp()
                if root then
                    markedCF = root.CFrame
                    suppressClick = true
                    local old = tpBtn.Text; tpBtn.Text = "Marked!"; task.delay(0.6, function() if tpBtn then tpBtn.Text = old end end)
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

        local AHEAD_DIST, RAY_DEPTH = 3, 2000
        local function groundAhead(root)
            if not root then return nil end
            local ch   = lp.Character
            local head = ch and ch:FindFirstChild("Head")
            if not head then return root.Position end

            local castFrom = head.Position + root.CFrame.LookVector * AHEAD_DIST
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            local itemsFolder = WS:FindFirstChild("Items")
            if itemsFolder then
                params.FilterDescendantsInstances = { lp.Character, itemsFolder }
            else
                params.FilterDescendantsInstances = { lp.Character }
            end

            local hit = WS:Raycast(castFrom, Vector3.new(0, -RAY_DEPTH, 0), params)
            return hit and hit.Position or (castFrom - Vector3.new(0, 3, 0))
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
            local sapling = findClosestSapling(); if not sapling then return end
            local startDrag = getRemote("RequestStartDraggingItem")
            local stopDrag  = getRemote("StopDraggingItem")
            local plantRF   = getRemote("RequestPlantItem"); if not plantRF then return end
            local root = hrp(); if not root then return end
            local plantPos = groundAhead(root)
            if startDrag then pcall(function() startDrag:FireServer(sapling) end); pcall(function() startDrag:FireServer(Instance.new("Model")) end) end
            task.wait(0.05)
            local ok = pcall(function() return plantRF:InvokeServer(sapling, Vector3.new(plantPos.X, plantPos.Y, plantPos.Z)) end)
            if not ok then local dummy = Instance.new("Model"); ok = pcall(function() return plantRF:InvokeServer(dummy, Vector3.new(plantPos.X, plantPos.Y, plantPos.Z)) end) end
            if not ok then pcall(function() plantRF:FireServer(sapling, Vector3.new(plantPos.X, plantPos.Y, plantPos.Z)) end); pcall(function() plantRF:FireServer(Instance.new("Model"), Vector3.new(plantPos.X, plantPos.Y, plantPos.Z)) end) end
            task.wait(0.05)
            if stopDrag then pcall(function() stopDrag:FireServer(sapling) end); pcall(function() stopDrag:FireServer(Instance.new("Model")) end) end
        end
        plantBtn.MouseButton1Click:Connect(function() plantNearestSaplingInFront() end)

        local MAX_TO_SAVE, savedCount = 4, 0
        local autoLostEnabled = true
        local lostEligible  = setmetatable({}, {__mode="k"})
        local function isLostChildModel(m) return m and m:IsA("Model") and m.Name:match("^Lost Child") end
        local function refreshLostBtn()
            local anyEligible = next(lostEligible) ~= nil
            lostBtn.Visible = autoLostEnabled and (savedCount < MAX_TO_SAVE) and anyEligible
        end
        local function onLostAttrChange(m)
            local v = m:GetAttribute("Lost") == true
            local was = lostEligible[m] == true
            if v then lostEligible[m] = true else if was and savedCount < MAX_TO_SAVE then savedCount += 1 end; lostEligible[m] = nil end
            refreshLostBtn()
        end
        local function trackLostModel(m)
            if not isLostChildModel(m) then return end
            onLostAttrChange(m)
            m:GetAttributeChangedSignal("Lost"):Connect(function() onLostAttrChange(m) end)
            m.AncestryChanged:Connect(function(_, parent) if not parent then lostEligible[m] = nil; refreshLostBtn() end end)
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
            local target = findNearestEligibleLost(); if not target then return end
            local mp = mainPart(target)
            if mp then teleportWithDive(CFrame.new(mp.Position + Vector3.new(0, 3, 0), mp.Position)) end
        end
        lostBtn.MouseButton1Click:Connect(function() teleportToNearestLost() end)

        local loadDefenseOn = false
        local ldHB, ldConnWS, ldConnRS, ldConnPLR
        local function forceOn(inst)
            local ok, val = pcall(function() return inst:GetAttribute("DataHasLoaded") end)
            if ok and val == false then pcall(function() inst:SetAttribute("DataHasLoaded", true) end) end
            if inst:IsA("BoolValue") and inst.Name == "DataHasLoaded" and inst.Value == false then pcall(function() inst.Value = true end) end
        end
        local function hookOne(inst)
            pcall(function()
                if inst:GetAttribute("DataHasLoaded") ~= nil then
                    inst:GetAttributeChangedSignal("DataHasLoaded"):Connect(function() if loadDefenseOn then forceOn(inst) end end)
                end
            end)
            if inst:IsA("BoolValue") and inst.Name == "DataHasLoaded" then
                inst.Changed:Connect(function(prop) if loadDefenseOn and prop == "Value" then forceOn(inst) end end)
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
        tab:Toggle({ Title = "Show Phase 10 button", Value = false, Callback = function(state) phaseBtn.Visible = state end })
        tab:Toggle({ Title = "Show Teleport button",   Value = false, Callback = function(state) tpBtn.Visible   = state end })
        tab:Toggle({ Title = "Plant Saplings",         Value = false, Callback = function(state) plantBtn.Visible= state end })
        tab:Toggle({ Title = "Auto Teleport to Lost Child", Value = true, Callback = function(state) autoLostEnabled = state; refreshLostBtn() end })
        tab:Toggle({ Title = "Show Campfire button",   Value = true,  Callback = function(state) campBtn.Visible  = state end })

        local godOn, godHB, godAcc = false, nil, 0
        local GOD_INTERVAL = 0.5
        local function fireGod()
            local f = RS:FindFirstChild("RemoteEvents")
            local ev = f and f:FindFirstChild("DamagePlayer")
            if ev and ev:IsA("RemoteEvent") then pcall(function() ev:FireServer(-math.huge) end) end
        end
        local function enableGod()
            if godOn then return end
            godOn = true; fireGod()
            if godHB then godHB:Disconnect() end
            godAcc = 0
            godHB = Run.Heartbeat:Connect(function(dt)
                godAcc += dt
                if godAcc >= GOD_INTERVAL then godAcc = 0; fireGod() end
            end)
        end
        local function disableGod() godOn = false; if godHB then godHB:Disconnect() godHB = nil end end
        tab:Toggle({ Title = "Godmode", Value = true, Callback = function(state) if state then enableGod() else disableGod() end end })
        task.defer(enableGod)

        local infJumpOn, infConn = true, nil
        local function enableInfJump()
            infJumpOn = true
            if infConn then infConn:Disconnect() end
            infConn = UIS.JumpRequest:Connect(function()
                local h = getHumanoid()
                if h then pcall(function() h:ChangeState(Enum.HumanoidStateType.Jumping) end) end
            end)
        end
        local function disableInfJump() infJumpOn = false; if infConn then infConn:Disconnect(); infConn = nil end end
        tab:Toggle({ Title = "Infinite Jump", Value = true, Callback = function(state) if state then enableInfJump() else disableInfJump() end end })
        enableInfJump()

        local INSTANT_HOLD, TRIGGER_COOLDOWN = 0.2, 0.4
        local EXCLUDE_NAME_SUBSTR = { "door", "closet", "gate", "hatch" }
        local EXCLUDE_ANCESTOR_SUBSTR = { "closetdoors", "closet", "door", "landmarks" }
        local function strfindAny(s, list)
            s = string.lower(s or "")
            for _, w in ipairs(list) do if string.find(s, w, 1, true) then return true end end
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
            if orig ~= nil and prompt and prompt.Parent then pcall(function() prompt.HoldDuration = orig end) end
            promptDurations[prompt] = nil
        end
        local function onPromptShown(prompt)
            if not prompt or not prompt:IsA("ProximityPrompt") then return end
            if shouldSkipPrompt(prompt) then return end
            if promptDurations[prompt] == nil then promptDurations[prompt] = prompt.HoldDuration end
            task.defer(function() if prompt and prompt.Parent and not shouldSkipPrompt(prompt) then pcall(function() prompt.HoldDuration = INSTANT_HOLD end) end end)
        end
        local function enableInstantInteract()
            if shownConn then return end
            shownConn  = PPS.PromptShown:Connect(onPromptShown)
            trigConn   = PPS.PromptTriggered:Connect(function(prompt, player)
                if player ~= lp or shouldSkipPrompt(prompt) then return end
                pcall(function() prompt.Enabled = false end)
                task.delay(TRIGGER_COOLDOWN, function() if prompt and prompt.Parent then pcall(function() prompt.Enabled = true end) end end)
                restorePrompt(prompt)
            end)
            hiddenConn = PPS.PromptHidden:Connect(function(prompt) if shouldSkipPrompt(prompt) then return end; restorePrompt(prompt) end)
        end
        local function disableInstantInteract()
            if shownConn  then shownConn:Disconnect();  shownConn  = nil end
            if trigConn   then trigConn:Disconnect();   trigConn   = nil end
            if hiddenConn then hiddenConn:Disconnect(); hiddenConn = nil end
            for p,_ in pairs(promptDurations) do restorePrompt(p) end
        end
        enableInstantInteract()
        tab:Toggle({ Title = "Instant Interact", Value = true, Callback = function(state) if state then enableInstantInteract() else disableInstantInteract() end end })

        local FLASHLIGHT_PREF = { "Strong Flashlight", "Old Flashlight" }
        local MONSTER_NAMES   = { "Deer", "Ram", "Owl" }
        local STUN_RADIUS     = 24
        local HIT_BURST       = 2
        local OFF_PULSE_EVERY = 1.5
        local OFF_PULSE_LEN   = 1/90

        local autoStunOn, autoStunThread = false, nil
        local lastFlashState, lastFlashName = nil, nil

        local function resolveFlashlightName()
            local inv = lp and lp:FindFirstChild("Inventory")
            if not inv then return nil end
            for _,n in ipairs(FLASHLIGHT_PREF) do
                if inv:FindFirstChild(n) then return n end
            end
            return nil
        end
        local function equipFlashlight(name)
            local inv = lp and lp:FindFirstChild("Inventory"); if not (inv and name) then return false end
            local item = inv:FindFirstChild(name); if not item then return false end
            local equip = getRemote("EquipItemHandle")
            local eqf   = getRemote("EquippedFlashlight")
            if equip and equip:IsA("RemoteEvent") then pcall(function() equip:FireServer("FireAllClients", item) end) end
            if eqf   and eqf:IsA("RemoteEvent")   then pcall(function() eqf:FireServer() end) end
            return true
        end
        local function setFlashlight(state, name)
            local ev = getRemote("FlashlightToggle")
            if not ev or not name then return end
            if state and lastFlashName ~= name then equipFlashlight(name) end
            if lastFlashState == state and lastFlashName == name then return end
            pcall(function() ev:FireServer(state, name) end)
            lastFlashState, lastFlashName = state, name
        end
        local function forceFlashlightOffAll()
            local ev = getRemote("FlashlightToggle"); if not ev then return end
            pcall(function() ev:FireServer(false, "Strong Flashlight") end)
            pcall(function() ev:FireServer(false, "Old Flashlight") end)
            lastFlashState, lastFlashName = nil, nil
        end
        local function nearestMonsterWithin(radius)
            local chars = WS:FindFirstChild("Characters")
            local root  = hrp()
            if not (chars and root) then return nil end
            local best, bestD = nil, radius
            for _,m in ipairs(chars:GetChildren()) do
                if m:IsA("Model") then
                    local n = m.Name
                    for _,want in ipairs(MONSTER_NAMES) do
                        if n == want then
                            local mp = mainPart(m)
                            if mp then
                                local d = (mp.Position - root.Position).Magnitude
                                if d <= bestD then bestD, best = d, m end
                            end
                            break
                        end
                    end
                end
            end
            return best
        end
        local function torchHit(targetModel)
            local torch = getRemote("MonsterHitByTorch"); if not torch then return end
            local ok = pcall(function()
                if torch:IsA("RemoteFunction") then
                    return torch:InvokeServer(targetModel or Instance.new("Model"))
                else
                    return torch:FireServer(targetModel or Instance.new("Model"))
                end
            end)
            return ok
        end

        local function enableAutoStun()
            if autoStunOn then return end
            autoStunOn = true
            autoStunThread = task.spawn(function()
                forceFlashlightOffAll()
                local fname = resolveFlashlightName()
                local lastPulse = os.clock()
                while autoStunOn do
                    if not fname then fname = resolveFlashlightName() end
                    local target = nearestMonsterWithin(STUN_RADIUS)
                    if fname and target then
                        setFlashlight(true, fname)
                        for i=1,HIT_BURST do torchHit(target) end
                        if os.clock() - lastPulse >= OFF_PULSE_EVERY then
                            setFlashlight(false, fname)
                            Run.Heartbeat:Wait()
                            setFlashlight(true, fname)
                            lastPulse = os.clock()
                        end
                    else
                        if fname then setFlashlight(false, fname) end
                        lastPulse = os.clock()
                        task.wait(0.15)
                    end
                    Run.Heartbeat:Wait()
                end
                forceFlashlightOffAll()
            end)
        end
        local function disableAutoStun()
            autoStunOn = false
        end

        tab:Toggle({
            Title = "Auto Stun Monster",
            Value = true,
            Callback = function(state)
                if state then enableAutoStun() else disableAutoStun() end
            end
        })
        task.defer(enableAutoStun)

        local noShadowsOn, lightConn = false, nil
        local origGlobalShadows = nil
        local lightOrig = setmetatable({}, {__mode = "k"})
        local function applyLight(l)
            if l:IsA("PointLight") or l:IsA("SpotLight") or l:IsA("SurfaceLight") then
                if lightOrig[l] == nil then lightOrig[l] = l.Shadows end
                pcall(function() l.Shadows = false end)
            end
        end
        local function enableNoShadows()
            if noShadowsOn then return end
            noShadowsOn = true
            origGlobalShadows = Lighting.GlobalShadows
            pcall(function() Lighting.GlobalShadows = false end)
            for _,d in ipairs(Lighting:GetDescendants()) do applyLight(d) end
            lightConn = Lighting.DescendantAdded:Connect(applyLight)
        end
        local function disableNoShadows()
            noShadowsOn = false
            if lightConn then lightConn:Disconnect() lightConn = nil end
            if origGlobalShadows ~= nil then pcall(function() Lighting.GlobalShadows = origGlobalShadows end) end
            for l,orig in pairs(lightOrig) do
                if l and l.Parent then pcall(function() l.Shadows = orig end) end
            end
        end

        tab:Toggle({ Title = "Disable Shadows", Value = false, Callback = function(state) if state then enableNoShadows() else disableNoShadows() end end })

        local function isBigTreeName(n)
            if not n then return false end
            if n == "TreeBig1" or n == "TreeBig2" or n == "TreeBig3" then return true end
            return (type(n)=="string") and (n:match("^WebbedTreeBig%d*$") ~= nil)
        end
        local hideBigTreesOn, hideConn, hideAcc = false, nil, 0
        local function deleteBigTreesOnce()
            local count = 0
            for _,d in ipairs(WS:GetDescendants()) do
                if d:IsA("Model") and isBigTreeName(d.Name) then
                    pcall(function() d:Destroy() end)
                    count += 1
                end
            end
            return count
        end
        local function enableHideBigTrees()
            if hideBigTreesOn then return end
            hideBigTreesOn = true
            deleteBigTreesOnce()
            if hideConn then hideConn:Disconnect() end
            hideAcc = 0
            hideConn = Run.Heartbeat:Connect(function(dt)
                hideAcc += dt
                if hideAcc >= 60 then
                    hideAcc = 0
                    deleteBigTreesOnce()
                end
            end)
        end
        local function disableHideBigTrees()
            hideBigTreesOn = false
            if hideConn then hideConn:Disconnect() hideConn = nil end
        end
        tab:Toggle({ Title = "Hide Big Trees (Local)", Value = false, Callback = function(state) if state then enableHideBigTrees() else disableHideBigTrees() end end })

        ----------------------------------------------------------------
        -- Auto Collect Coins
        ----------------------------------------------------------------
        local cam = WS.CurrentCamera
        WS:GetPropertyChangedSignal("CurrentCamera"):Connect(function() cam = WS.CurrentCamera end)

        local COIN_RADIUS      = 10
        local COIN_INTERVAL    = 0.12
        local COIN_TTL         = 1.0
        local COIN_FORWARD     = 2.0
        local COIN_HEAD_UP     = 0.5

        local coinSeen = {}
        local coinConn, coinAcc = nil, 0
        local coinDirs = {}
        do
            local pitches = { -24, -12, 0, 12, 24 }
            for i = 0, 15 do
                local yaw = math.rad(i * 22.5)
                local cy, sy = math.cos(yaw), math.sin(yaw)
                for _,deg in ipairs(pitches) do
                    local p = math.rad(deg)
                    local cp, sp = math.cos(p), math.sin(p)
                    coinDirs[#coinDirs+1] = Vector3.new(cy*cp, sp, sy*cp).Unit
                end
            end
        end

        local coinParams = RaycastParams.new()
        coinParams.FilterType = Enum.RaycastFilterType.Exclude
        coinParams.IgnoreWater = true

        local function getNil(name, class)
            local ok, arr = pcall(getnilinstances)
            if not ok or type(arr) ~= "table" then return nil end
            for _, v in next, arr do
                if v and v.ClassName == class and v.Name == name then
                    return v
                end
            end
        end

        local function isMossyName(n)
            if n == "Mossy Coin" then return true end
            return n and n:match("^Mossy Coin%d+$") ~= nil
        end

        local function findCoinStack(inst)
            local cur = inst
            for _ = 1, 8 do
                if not cur then return nil end
                if cur:IsA("Model") and cur.Name == "Coin Stack" then return cur end
                if cur:IsA("Model") and isMossyName(cur.Name) and cur.Parent and cur.Parent:IsA("Model") and cur.Parent.Name == "Coin Stack" then
                    return cur.Parent
                end
                cur = cur.Parent
            end
            return nil
        end

        local function triggerPromptOn(model)
            local p = model:FindFirstChildWhichIsA("ProximityPrompt", true)
            if p and p.Enabled then PPS:TriggerPrompt(p); return true end
            return false
        end

        local function clickDetectorOn(model)
            local cd = model:FindFirstChildWhichIsA("ClickDetector", true)
            if not cd then return false end
            local pos = (model.PrimaryPart and model.PrimaryPart.Position) or model:GetPivot().Position
            if not cam then return false end
            local v2, onScreen = cam:WorldToViewportPoint(pos)
            if not onScreen then return false end
            VIM:SendMouseMoveEvent(v2.X, v2.Y, game)
            VIM:SendMouseButtonEvent(v2.X, v2.Y, 0, true, game, 0)
            VIM:SendMouseButtonEvent(v2.X, v2.Y, 0, false, game, 0)
            return true
        end

        local function tryRemote(stack)
            local remote = RS:WaitForChild("RemoteEvents"):WaitForChild("RequestCollectCoints")
            local ok = false
            do
                local s, r = pcall(function() return remote:InvokeServer(stack) end)
                ok = s and (r ~= nil or true)
                if ok then return true end
            end
            do
                local ghost = getNil("Coin Stack", "Model")
                if ghost then
                    local s, r = pcall(function() return remote:InvokeServer(ghost) end)
                    ok = s and (r ~= nil or true)
                    if ok then return true end
                end
            end
            do
                local s, r = pcall(function() return remote:InvokeServer() end)
                ok = s and (r ~= nil or true)
            end
            return ok
        end

        local coinOn = true
        local function enableCoin()
            if coinConn then return end
            coinOn = true
            coinAcc = 0
            coinConn = Run.Heartbeat:Connect(function(dt)
                coinAcc += dt
                if coinAcc < COIN_INTERVAL then return end
                coinAcc = 0

                local root = hrp(); if not root then return end
                local ch = lp.Character
                local head = ch and ch:FindFirstChild("Head")
                local origin = root.Position
                if head then
                    origin = head.Position + root.CFrame.LookVector * COIN_FORWARD + Vector3.new(0, COIN_HEAD_UP, 0)
                end
                coinParams.FilterDescendantsInstances = { lp.Character }

                local now = os.clock()
                for i=1,#coinDirs do
                    local res = WS:Raycast(origin, coinDirs[i] * COIN_RADIUS, coinParams)
                    if res and res.Instance then
                        local stack = findCoinStack(res.Instance)
                        if stack and stack.Parent then
                            local pos = (stack.PrimaryPart and stack.PrimaryPart.Position) or stack:GetPivot().Position
                            if (pos - origin).Magnitude <= COIN_RADIUS then
                                local t = coinSeen[stack]
                                if not t or now - t > COIN_TTL then
                                    local done = triggerPromptOn(stack)
                                    if not done then done = clickDetectorOn(stack) end
                                    if not done then tryRemote(stack) end
                                    coinSeen[stack] = now
                                end
                            end
                        end
                    end
                end
                for m, t in pairs(coinSeen) do
                    if (not m) or (not m.Parent) or now - t > 5 then coinSeen[m] = nil end
                end
            end)
        end
        local function disableCoin()
            coinOn = false
            if coinConn then coinConn:Disconnect(); coinConn = nil end
            coinSeen = {}
        end
        tab:Toggle({ Title = "Auto Collect Coins", Value = true, Callback = function(state) if state then enableCoin() else disableCoin() end end })
        if coinOn then enableCoin() end
        ----------------------------------------------------------------

        ----------------------------------------------------------------
        -- Chest Teleport + 10s Micro-Gather (Default OFF)   [below coins]
        ----------------------------------------------------------------
        local placeBtn = ensureBtn("PlaceEdge", "Place", 1000, false)
        _G._PlaceEdgeBtn = placeBtn

        local function itemsFolder()
            return WS:FindFirstChild("Items")
        end
        local function isUnderItems(m)
            local it = itemsFolder()
            return it and m and m:IsDescendantOf(it) or false
        end
        local function isChestName(n)
            if type(n)~="string" then return false end
            local s = n:lower()
            if s:find("snow",1,true) then return false
            end
            return s:find("chest",1,true) ~= nil
        end
        local function isChestModel(m) return m and m:IsA("Model") and isChestName(m.Name) end
        local function chestOpened(m)
            if not m then return false end
            if m:GetAttribute("LocalOpened") == true then return true end
            for k,v in pairs(m:GetAttributes()) do
                if tostring(k):match("Opened$") and v == true then return true end
            end
            return false
        end
        local function chestPos(m)
            local mp = mainPart(m)
            if mp then return mp.Position end
            local ok, cf = pcall(function() return m:GetPivot() end)
            return ok and cf.Position or nil
        end

        local Chest = {}
        Chest.Record   = {}
        Chest.Enabled  = false
        Chest.Btn      = ensureBtn("ChestEdge", "Nearest Unopened Chest", 6, false)

        local function markChest(m)
            if not isChestModel(m) then return end
            local pos = chestPos(m); if not pos then return end
            local r = Chest.Record[m] or {}
            r.pos = pos
            r.opened = chestOpened(m)
            Chest.Record[m] = r
            m:GetAttributeChangedSignal("LocalOpened"):Connect(function() local rec=Chest.Record[m]; if rec then rec.opened = chestOpened(m) end end)
            for k,_ in pairs(m:GetAttributes()) do
                if tostring(k):match("Opened$") then
                    m:GetAttributeChangedSignal(k):Connect(function() local rec=Chest.Record[m]; if rec then rec.opened = chestOpened(m) end end)
                end
            end
            m.AncestryChanged:Connect(function(_, parent) if not parent then Chest.Record[m]=nil end end)
        end
        local function initialScanChests()
            Chest.Record = {}
            local items = itemsFolder(); if not items then return end
            for _,m in ipairs(items:GetChildren()) do markChest(m) end
        end
        initialScanChests()
        do
            local it = itemsFolder()
            if it then
                it.ChildAdded:Connect(function(c) markChest(c) end)
                it.ChildRemoved:Connect(function(c) Chest.Record[c] = nil end)
            end
        end

        local function unopenedList()
            local root = hrp(); if not root then return {} end
            local out = {}
            for m,r in pairs(Chest.Record) do
                if m and m.Parent and not r.opened then
                    out[#out+1] = {m=m, pos=r.pos, d=(r.pos - root.Position).Magnitude}
                end
            end
            table.sort(out, function(a,b) return a.d < b.d end)
            return out
        end
        local function refreshChestBtn()
            if not Chest.Enabled then Chest.Btn.Visible=false return end
            local l = unopenedList()
            Chest.Btn.Visible = (#l > 0)
            Chest.Btn.Text = (#l>0) and ("Nearest Unopened Chest ("..#l..")") or "Nearest Unopened Chest"
        end

        local function chestFrontCF(m)
            local cf = (m.PrimaryPart and m.PrimaryPart.CFrame) or m:GetPivot()
            local front = cf.LookVector
            local pos   = cf.Position + front * 3.0 + Vector3.new(0,0.1,0)
            return CFrame.new(pos, cf.Position)
        end

        local function approachChest(m)
            local cf = chestFrontCF(m); if not cf then return end
            teleportSticky(cf)
            local camNow = WS.CurrentCamera
            if camNow then
                camNow.CameraType = Enum.CameraType.Scriptable
                local front = (m.PrimaryPart and m.PrimaryPart.CFrame.LookVector) or m:GetPivot().LookVector
                local cpos  = (m.PrimaryPart and m.PrimaryPart.Position or m:GetPivot().Position) + front * 5.0 + Vector3.new(0,1.8,0)
                camNow.CFrame = CFrame.new(cpos, (m.PrimaryPart and m.PrimaryPart.Position) or m:GetPivot().Position)
                task.delay(0.7, function() if camNow then camNow.CameraType = Enum.CameraType.Custom end end)
            end
        end

        local ChestAllow = {
            ["Log"]=true,["Chair"]=true,["Coal"]=true,["Fuel Canister"]=true,["Oil Barrel"]=true,["Biofuel"]=true,
            ["Cake"]=true,["Cooked Steak"]=true,["Cooked Morsel"]=true,["Steak"]=true,["Morsel"]=true,["Berry"]=true,
            ["Carrot"]=true,["Chilli"]=true,["Stew"]=true,["Ribs"]=true,["Pumpkin"]=true,["Hearty Stew"]=true,
            ["Cooked Ribs"]=true,["Corn"]=true,["BBQ ribs"]=true,["Apple"]=true,["Mackerel"]=true,
            ["Bandage"]=true,["MedKit"]=true,
            ["Revolver"]=true,["Rifle"]=true,["Leather Body"]=true,["Iron Body"]=true,["Good Axe"]=true,["Strong Axe"]=true,
            ["Chainsaw"]=true,["Crossbow"]=true,["Katana"]=true,["Kunai"]=true,["Laser cannon"]=true,["Laser sword"]=true,
            ["Morningstar"]=true,["Riot shield"]=true,["Spear"]=true,["Tactical Shotgun"]=true,["Wildfire"]=true,
            ["Revolver Ammo"]=true,["Rifle Ammo"]=true,["Giant Sack"]=true,["Good Sack"]=true,["Blueprint"]=true,
            ["Diamond"]=true,["Forest Gem"]=true,["Sapling"]=true,["Basketball"]=true
        }
        local function allowedByPattern(name)
            local n = (name or ""):lower()
            if n == "mossy coin" or n:match("^mossy coin%d+$") then return true end
            if n:find("forest gem fragment",1,true) then return true end
            if n:find(" key",1,true) and (n:find("blue",1,true) or n:find("yellow",1,true) or n:find("red",1,true)
                or n:find("gray",1,true) or n:find("grey",1,true) or n:find("frog",1,true)) then return true end
            if n:find("flashlight",1,true) and (n:find("old",1,true) or n:find("strong",1,true)) then return true end
            if n:find("taming flute",1,true) and (n:find("old",1,true) or n:find("good",1,true) or n:find("strong",1,true)) then return true end
            return false
        end
        local function isLootItem(m)
            if not (m and m:IsA("Model")) then return false end
            if not isUnderItems(m) then return false end
            local n = m.Name or ""
            if isChestName(n) then return false end
            if ChestAllow[n] then return true end
            return allowedByPattern(n)
        end

        local function startDrag(m)
            local ev = getRemote("RequestStartDraggingItem") or getRemote("StartDraggingItem")
            if not ev then return end
            pcall(function() ev:FireServer(m) end)
            pcall(function() ev:FireServer(Instance.new("Model")) end)
        end
        local function stopDrag(m)
            local ev = getRemote("RequestStopDraggingItem") or getRemote("StopDraggingItem")
            if not ev then return end
            pcall(function() ev:FireServer(m or Instance.new("Model")) end)
            pcall(function() ev:FireServer(Instance.new("Model")) end)
        end
        local function setNoCollideModel(m, on)
            for _,d in ipairs(m:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.CanCollide = not on
                    d.CanQuery   = not on
                    d.CanTouch   = not on
                    d.Massless   = on and true or false
                    d.AssemblyLinearVelocity  = Vector3.new()
                    d.AssemblyAngularVelocity = Vector3.new()
                end
            end
        end
        local function setAnchoredModel(m, on)
            for _,d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = on end end
        end
        local function pivotModel(m, cf)
            if m:IsA("Model") then m:PivotTo(cf) else local p=mainPart(m); if p then p.CFrame=cf end end
        end

        local ChestMICRO_RADIUS   = 2.0
        local ChestHOVER_HEIGHT   = 5
        local ChestPILE_RADIUS    = 1.25
        local ChestLAYER_SIZE     = 14
        local ChestLAYER_HEIGHT   = 0.35
        local ChestUNANCHOR_BATCH = 6
        local ChestUNANCHOR_STEP  = 0.03
        local ChestNUDGE_DOWN     = 4
        local ChestPLACE_BATCH    = 12
        local ChestDURATION       = 10.0

        local chestGatherOn, chestEndAt = false, 0
        local chestScanConn, chestHoverConn, chestChildConn = nil, nil, nil
        local chestGathered, chestList = {}, {}

        local function chestAdd(m)
            if chestGathered[m] then return end
            chestGathered[m] = true
            chestList[#chestList+1] = m
        end
        local function chestRemove(m)
            if not chestGathered[m] then return end
            chestGathered[m] = nil
            for i=#chestList,1,-1 do if chestList[i]==m then table.remove(chestList,i) break end end
        end

        local function tryCaptureLoot(m)
            repeat
                if not (m and m.Parent and m:IsA("Model")) then break end
                if not isLootItem(m) then break end
                local mp = mainPart(m); if not mp then break end
                local root = hrp(); if not root then break end
                if (mp.Position - root.Position).Magnitude > ChestMICRO_RADIUS then break end
                startDrag(m)
                task.wait(0.02)
                pcall(function() mp:SetNetworkOwner(lp) end)
                setNoCollideModel(m, true)
                setAnchoredModel(m, true)
                chestAdd(m)
                stopDrag(m)
            until true
        end

        local function hookItemsAdded()
            if chestChildConn then chestChildConn:Disconnect() chestChildConn=nil end
            local it = itemsFolder()
            if it then
                chestChildConn = it.ChildAdded:Connect(function(c)
                    if not chestGatherOn then return end
                    local m = c:IsA("Model") and c or c:FindFirstAncestorOfClass("Model")
                    if m then tryCaptureLoot(m) end
                end)
            end
        end
        hookItemsAdded()

        local function chestScan()
            if not chestGatherOn then return end
            local it = itemsFolder()
            if not it then return end
            for _,d in ipairs(it:GetDescendants()) do
                local m = d:IsA("Model") and d or d:FindFirstAncestorOfClass("Model")
                if m and not chestGathered[m] then tryCaptureLoot(m) end
            end
        end

        local function chestHover()
            if not chestGatherOn then return end
            local root = hrp(); if not root then return end
            local forward = root.CFrame.LookVector
            local above   = root.Position + Vector3.new(0, ChestHOVER_HEIGHT, 0)
            local baseCF  = CFrame.lookAt(above, above + forward)
            for _,m in ipairs(chestList) do
                if m and m.Parent then pivotModel(m, baseCF) else chestRemove(m) end
            end
        end

        local function chestEnableMicro()
            if chestGatherOn then return end
            chestGatherOn = true
            chestScanConn  = Run.Heartbeat:Connect(chestScan)
            chestHoverConn = Run.RenderStepped:Connect(chestHover)
            placeBtn.Visible = false
        end
        local function chestDisableMicro()
            chestGatherOn = false
            if chestScanConn  then pcall(function() chestScanConn:Disconnect()  end) end; chestScanConn=nil
            if chestHoverConn then pcall(function() chestHoverConn:Disconnect() end) end; chestHoverConn=nil
        end

        local function groundBelowLoose(pos, exclude)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            local ex = { lp.Character }
            if exclude then for i=1,#exclude do ex[#ex+1] = exclude[i] end end
            params.FilterDescendantsInstances = ex
            local from = pos + Vector3.new(0, 200, 0)
            local hit = WS:Raycast(from, Vector3.new(0, -1000, 0), params)
            return hit and hit.Position or (pos - Vector3.new(0, 3, 0))
        end
        local function groundAheadCF()
            local root = hrp(); if not root then return nil end
            local forward = root.CFrame.LookVector
            local ahead   = root.Position + forward * 10 + Vector3.new(0, 40, 0)
            local params  = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {lp.Character}
            local rc = WS:Raycast(ahead, Vector3.new(0, -200, 0), params)
            local hitPos = rc and rc.Position or (root.Position + forward * 10)
            local drop   = hitPos + Vector3.new(0, 5, 0)
            return CFrame.lookAt(drop, drop + forward)
        end
        local function pileCF(i, baseCF)
            local idx0   = i - 1
            local layer  = math.floor(idx0 / ChestLAYER_SIZE)
            local inLayer= idx0 % ChestLAYER_SIZE
            local angle  = (inLayer / ChestLAYER_SIZE) * math.pi * 2
            local r      = (0.25 + (inLayer % 7) * 0.07) * ChestPILE_RADIUS
            local x      = math.cos(angle) * r + (math.random() - 0.5) * 0.12
            local z      = math.sin(angle) * r + (math.random() - 0.5) * 0.12
            local y      = layer * ChestLAYER_HEIGHT
            return baseCF * CFrame.new(x, y, z)
        end
        local function setPhysicsFree(items)
            for _,m in ipairs(items) do
                if m and m.Parent then
                    setNoCollideModel(m, false)
                    local mp = mainPart(m)
                    if mp then
                        pcall(function() mp:SetNetworkOwner(nil) end)
                        pcall(function() if mp.SetNetworkOwnershipAuto then mp:SetNetworkOwnershipAuto() end end)
                        pcall(function() mp.CollisionGroupId = 0 end)
                    end
                    for _,p in ipairs(m:GetDescendants()) do
                        if p:IsA("BasePart") then
                            p.AssemblyLinearVelocity  = Vector3.new()
                            p.AssemblyAngularVelocity = Vector3.new()
                            p.CanCollide = true; p.CanTouch = true; p.CanQuery = true
                            p.Massless   = false
                        end
                    end
                end
            end
        end
        local function unanchorAndDrop(items)
            local n = #items
            local i = 1
            while i <= n do
                for j = i, math.min(i + ChestUNANCHOR_BATCH - 1, n) do
                    local m = items[j]
                    if m and m.Parent then
                        local mp = mainPart(m)
                        if mp then
                            local g = groundBelowLoose(mp.Position, {lp.Character})
                            local targetY = g.Y + 0.2
                            local cf = mp.CFrame
                            local rx,ry,rz = cf:ToOrientation()
                            local to = CFrame.new(cf.X, targetY, cf.Z) * CFrame.fromOrientation(rx,ry,rz)
                            if m:IsA("Model") then m:PivotTo(to) else mp.CFrame = to end
                        end
                        setAnchoredModel(m, false)
                        for _,p in ipairs(m:GetDescendants()) do
                            if p:IsA("BasePart") then
                                p.AssemblyLinearVelocity  = Vector3.new(0, -ChestNUDGE_DOWN, 0)
                                p.AssemblyAngularVelocity = Vector3.new()
                            end
                        end
                    end
                end
                Run.Heartbeat:Wait()
                i = i + ChestUNANCHOR_BATCH
            end
        end
        local function chestPlaceDown()
            local baseCF = groundAheadCF(); if not baseCF then return end
            chestDisableMicro()
            placeBtn.Visible = false
            local n = #chestList
            local cfs = table.create(n)
            for i = 1, n do cfs[i] = pileCF(i, baseCF) end
            local placed = 0
            for i = 1, n do
                local m = chestList[i]
                if m and m.Parent then
                    startDrag(m)
                    setAnchoredModel(m, true)
                    setNoCollideModel(m, true)
                    pivotModel(m, cfs[i])
                    stopDrag(m)
                    placed += 1
                    if placed % ChestPLACE_BATCH == 0 then Run.Heartbeat:Wait() end
                end
            end
            task.wait(0.03)
            setPhysicsFree(chestList)
            unanchorAndDrop(chestList)
            for k,_ in pairs(chestGathered) do chestGathered[k]=nil end
            table.clear(chestList)
        end
        placeBtn.MouseButton1Click:Connect(chestPlaceDown)

        Chest.Btn.MouseButton1Click:Connect(function()
            if not Chest.Enabled then return end
            local l = unopenedList()
            if #l == 0 then refreshChestBtn(); return end
            approachChest(l[1].m)
            chestEndAt = os.clock() + ChestDURATION
            if not chestGatherOn then chestEnableMicro() end
            placeBtn.Visible = false
        end)

        local chestOnToggle = false
        local function setChestEnabled(state)
            Chest.Enabled = state
            chestOnToggle = state
            Chest.Btn.Visible = state
            refreshChestBtn()
            if not state then
                chestDisableMicro()
                placeBtn.Visible = false
                for k,_ in pairs(chestGathered) do chestGathered[k]=nil end
                table.clear(chestList)
            end
        end

        tab:Toggle({
            Title = "Chest Teleport + 10s Gather",
            Value = false,
            Callback = function(state) setChestEnabled(state) end
        })

        Run.Heartbeat:Connect(function()
            if Chest.Enabled then
                if chestGatherOn and os.clock() >= chestEndAt then
                    chestDisableMicro()
                    placeBtn.Visible = (#chestList > 0)
                end
                for m,r in pairs(Chest.Record) do
                    if m and m.Parent then
                        r.pos = chestPos(m) or r.pos
                        r.opened = chestOpened(m)
                    end
                end
                refreshChestBtn()
            end
        end)
        ----------------------------------------------------------------

        local noPauseOn, prevPauseMode
        local function enableNoStreamingPause()
            if noPauseOn then return end
            noPauseOn = true
            pcall(function()
                prevPauseMode = WS.StreamingPauseMode
                WS.StreamingPauseMode = Enum.StreamingPauseMode.Disabled
            end)
        end

        enableNoStreamingPause()

        local function collectSaplingsSnapshot()
            local items = itemsFolder(); if not items then return {} end
            local list = {}
            for _,m in ipairs(items:GetChildren()) do
                if m:IsA("Model") and m.Name == "Sapling" then
                    local mp = mainPart(m)
                    if mp then list[#list+1] = m end
                end
            end
            return list
        end
        local function groundAtFeetCF()
            local root = hrp(); if not root then return nil end
            local g = groundBelow(root.Position)
            local look = root.CFrame.LookVector
            local pos = Vector3.new(g.X, g.Y + 0.6, g.Z)
            return CFrame.new(pos, pos + look)
        end
        local function dropModelAtFeet(m)
            local startDrag = getRemote("RequestStartDraggingItem")
            local stopDrag  = getRemote("StopDraggingItem")
            if startDrag then pcall(function() startDrag:FireServer(m) end); pcall(function() startDrag:FireServer(Instance.new("Model")) end) end
            Run.Heartbeat:Wait()
            local cf = groundAtFeetCF()
            if cf then
                pcall(function()
                    if m:IsA("Model") then m:PivotTo(cf) else local p = mainPart(m); if p then p.CFrame = cf end end
                end)
            end
            task.wait(0.05)
            if stopDrag then pcall(function() stopDrag:FireServer(m) end); pcall(function() stopDrag:FireServer(Instance.new("Model")) end) end
        end
        local SAPLING_DROP_PER_SEC = 25
        local function actionDropSaplings()
            local snap = collectSaplingsSnapshot()
            if #snap == 0 then return end
            local interval = 1 / math.max(0.1, SAPLING_DROP_PER_SEC)
            for i=1,#snap do
                local m = snap[i]
                if m and m.Parent then
                    dropModelAtFeet(m)
                    task.wait(interval)
                end
            end
        end

        local PLANT_START_DELAY = 1.0
        local PLANT_Y_EPSILON   = 0.15
        local function computePlantPosFromModel(m)
            local mp = mainPart(m); if not mp then return nil end
            local g  = groundBelow(mp.Position)
            local baseY = mp.Position.Y - (mp.Size.Y * 0.5)
            local y = math.min(g.Y, baseY) - PLANT_Y_EPSILON
            return Vector3.new(mp.Position.X, y, mp.Position.Z)
        end
        local function plantModelInPlace(m)
            local startDrag = getRemote("RequestStartDraggingItem")
            local stopDrag  = getRemote("StopDraggingItem")
            local plantRF   = getRemote("RequestPlantItem"); if not plantRF then return end
            local pos = computePlantPosFromModel(m); if not pos then return end
            if startDrag then pcall(function() startDrag:FireServer(m) end); pcall(function() startDrag:FireServer(Instance.new("Model")) end) end
            task.wait(0.05)
            local ok = pcall(function()
                if plantRF:IsA("RemoteFunction") then
                    return plantRF:InvokeServer(m, pos)
                else
                    plantRF:FireServer(m, pos); return true
                end
            end)
            if not ok then
                local dummy = Instance.new("Model")
                pcall(function()
                    if plantRF:IsA("RemoteFunction") then
                        return plantRF:InvokeServer(dummy, pos)
                    else
                        plantRF:FireServer(dummy, pos)
                    end
                end)
            end
            task.wait(0.05)
            if stopDrag then pcall(function() stopDrag:FireServer(m) end); pcall(function() stopDrag:FireServer(Instance.new("Model")) end) end
        end
        local function actionPlantAllSaplings()
            task.wait(PLANT_START_DELAY)
            local snap = collectSaplingsSnapshot()
            for i=1,#snap do
                local m = snap[i]
                if m and m.Parent then plantModelInPlace(m) end
                Run.Heartbeat:Wait()
            end
        end

        tab:Section({ Title = "Saplings" })
        tab:Button({ Title = "Drop Saplings", Callback = actionDropSaplings })
        tab:Button({ Title = "Plant All Saplings", Callback = actionPlantAllSaplings })

        local loadDefenseOnDefault = true
        if loadDefenseOnDefault then enableLoadDefense() end

        Players.LocalPlayer.CharacterAdded:Connect(function()
            if edgeGui.Parent ~= playerGui then edgeGui.Parent = playerGui end
            if godOn then if not godHB then enableGod() end task.delay(0.2, fireGod) end
            if infJumpOn and not infConn then enableInfJump() end
            if autoStunOn and not autoStunThread then enableAutoStun() end
            if noShadowsOn and not lightConn then enableNoShadows() end
            if hideBigTreesOn and not hideConn then enableHideBigTrees() end
            pcall(function() WS.StreamingPauseMode = Enum.StreamingPauseMode.Disabled end)
            if loadDefenseOnDefault then enableLoadDefense() end
            if coinOn and not coinConn then enableCoin() end
            if chestOnToggle then setChestEnabled(true) end
            hookItemsAdded()
        end)
    end
    local ok, err = pcall(run)
    if not ok then warn("[Auto] module error: " .. tostring(err)) end
end
