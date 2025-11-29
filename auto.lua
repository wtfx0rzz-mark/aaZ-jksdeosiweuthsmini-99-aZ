-- auto.lua

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
        local function hum()
            local ch = lp.Character
            return ch and ch:FindFirstChildOfClass("Humanoid")
        end
        local function mainPart(m)
            if not m then return nil end
            if m:IsA("BasePart") then return m end
            if m:IsA("Model") then
                if m.PrimaryPart then return m.PrimaryPart end
                return m:FindFirstChildWhichIsA("BasePart")
            end
            return nil
        end
        local function getRemote(name)
            local f = RS:FindFirstChild("RemoteEvents")
            return f and f:FindFirstChild(name) or nil
        end
        local function zeroAssembly(root)
            if not root then return end
            root.AssemblyLinearVelocity  = Vector3.new()
            root.AssemblyAngularVelocity = Vector3.new()
        end

        local STICK_DURATION    = 0.35
        local STICK_EXTRA_FR    = 2
        local STICK_CLEAR_VEL   = true
        local TELEPORT_UP_NUDGE = 0.05
        local SAFE_DROP_UP      = 4.0

        -- per-user chest-open attribute key
        local UID_OPEN_KEY = tostring(lp.UserId) .. "Opened"

        local STREAM_TIMEOUT    = 6.0
        local function requestStreamAt(pos, timeout)
            local p = typeof(pos) == "CFrame" and pos.Position or pos
            local ok = pcall(function() WS:RequestStreamAroundAsync(p, timeout or STREAM_TIMEOUT) end)
            return ok
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

        local rollbackCF = nil
        local rollbackThread = nil
        local ROLLBACK_IDLE_S = 30
        local MIN_MOVE_DIST = 2.0

        local function startRollbackWatch(afterCF)
            if rollbackThread then task.cancel(rollbackThread) end
            rollbackCF = afterCF
            local startRoot = hrp()
            local startPos = startRoot and startRoot.Position or nil
            local startTime = os.clock()
            rollbackThread = task.spawn(function()
                local moved = false
                while os.clock() - startTime < ROLLBACK_IDLE_S do
                    local h = hum()
                    local r = hrp()
                    if r and startPos and (r.Position - startPos).Magnitude >= MIN_MOVE_DIST then
                        moved = true; break
                    end
                    if h and h.MoveDirection.Magnitude > 0.05 then
                        moved = true; break
                    end
                    if not lp or lp.GameplayPaused then
                        moved = true; break
                    end
                    Run.Heartbeat:Wait()
                end
                if (not moved) and rollbackCF then
                    local root = hrp(); if root then
                        local cf = rollbackCF
                        local snap = snapshotCollide()
                        setCollideAll(false)
                        prefetchRing(cf)
                        requestStreamAt(cf)
                        waitGameplayResumed(1.0)
                        pcall(function() (lp.Character or {}).PrimaryPart.CFrame = cf end)
                        pcall(function() root.CFrame = cf end)
                        zeroAssembly(root)
                        setCollideAll(true, snap)
                        waitGameplayResumed(1.0)
                    end
                end
            end)
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
                startRollbackWatch(targetCF)
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
            startRollbackWatch(targetCF)
        end

        local function waitUntilGroundedOrMoving(timeout)
            local h = hum()
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

        -- campfire teleport clamped so you are at/above campfire height
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
            local clampedY = math.max(g.Y + 2.5, center.Position.Y + 0.5)
            local finalPos = Vector3.new(targetPos.X, clampedY, targetPos.Z)
            return CFrame.new(finalPos, center.Position)
        end

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
        local function makeEdgeBtn(name, label, order)
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
                b.Visible = false
                b.LayoutOrder = order or 1
                b.Parent = stack
                local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = b
            else
                b.Text = label
                b.LayoutOrder = order or b.LayoutOrder
                b.Visible = false
            end
            return b
        end

        local PHASE_DIST = 10
        local phaseBtn = makeEdgeBtn("Phase10Edge", "Phase 10", 1)
        local tpBtn    = makeEdgeBtn("TpEdge",      "Teleport", 2)
        local plantBtn = makeEdgeBtn("PlantEdge",   "Plant",    3)
        local lostBtn  = makeEdgeBtn("LostEdge",    "Lost Child", 4)
        local campBtn  = makeEdgeBtn("CampEdge",    "Campfire", 5)

        local showPhaseEdge, showPlantEdge = false, false
        local showTeleportEdge, showCampEdge = false, true

        phaseBtn.Visible = showPhaseEdge
        plantBtn.Visible = showPlantEdge
        tpBtn.Visible    = showTeleportEdge
        campBtn.Visible  = showCampEdge

        phaseBtn.MouseButton1Click:Connect(function()
            local root = hrp(); if not root then return end
            local dest = root.Position + root.CFrame.LookVector * PHASE_DIST
            teleportSticky(CFrame.new(dest, dest + root.CFrame.LookVector))
        end)

        local markedCF, HOLD_THRESHOLD, downAt, suppressClick = nil, 0.2, 0, false
        tpBtn.MouseButton1Down:Connect(function() downAt = os.clock(); suppressClick = false end)
        tpBtn.MouseButton1Up:Connect(function()
            local held = os.clock() - (downAt or 0)
            if held >= HOLD_THRESHOLD then
                local root = hrp()
                if root then
                    markedCF = root.CFrame
                    suppressClick = true
                    local old = tpBtn.Text; tpBtn.Text = "Marked"; task.delay(0.5, function() if tpBtn then tpBtn.Text = old end end)
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

        tab:Toggle({
            Title = "Edge Button: Phase 10",
            Value = false,
            Callback = function(state)
                showPhaseEdge = state
                if phaseBtn then phaseBtn.Visible = state end
            end
        })
        tab:Toggle({
            Title = "Edge Button: Plant Sapling",
            Value = false,
            Callback = function(state)
                showPlantEdge = state
                if plantBtn then plantBtn.Visible = state end
            end
        })
        tab:Toggle({
            Title = "Edge Button: Teleport",
            Value = false,
            Callback = function(state)
                showTeleportEdge = state
                if tpBtn then tpBtn.Visible = state end
            end
        })
        tab:Toggle({
            Title = "Edge Button: Campfire",
            Value = true,
            Callback = function(state)
                showCampEdge = state
                if campBtn then campBtn.Visible = state end
            end
        })

        local MAX_TO_SAVE, savedCount = 4, 0
        local autoLostEnabled = true
        local lostEligible  = setmetatable({}, {__mode="k"})
        local visitedLost   = setmetatable({}, {__mode="k"})
        local function isLostChildModel(m) return m and m:IsA("Model") and m.Name:match("^Lost Child") end
        local function refreshLostBtn()
            local anyEligible = next(lostEligible) ~= nil
            lostBtn.Visible = autoLostEnabled and (savedCount < MAX_TO_SAVE) and anyEligible
        end
        local function onLostAttrChange(m)
            local v = m:GetAttribute("Lost") == true
            local was = lostEligible[m] == true
            if v then
                lostEligible[m] = true
                visitedLost[m] = nil
            else
                if was and savedCount < MAX_TO_SAVE then savedCount += 1 end
                lostEligible[m] = nil
                visitedLost[m] = nil
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
                    visitedLost[m] = nil
                    refreshLostBtn()
                end
            end)
        end
        for _,d in ipairs(WS:GetDescendants()) do trackLostModel(d) end
        WS.DescendantAdded:Connect(trackLostModel)
        local function findUnvisitedLost()
            local root = hrp(); if not root then return nil end
            local best, bestD = nil, math.huge
            for m,_ in pairs(lostEligible) do
                if not visitedLost[m] then
                    local mp = mainPart(m)
                    if mp then
                        local dist = (mp.Position - root.Position).Magnitude
                        if dist < bestD then bestD, best = dist, m end
                    end
                end
            end
            return best
        end
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
            local target = findUnvisitedLost()
            if not target then target = findNearestEligibleLost() end
            if not target then return end
            local mp = mainPart(target)
            if mp then
                visitedLost[target] = mp.Position
                teleportWithDive(CFrame.new(mp.Position + Vector3.new(0, 3, 0), mp.Position))
            end
        end
        lostBtn.MouseButton1Click:Connect(function() teleportToNearestLost() end)
        tab:Toggle({
            Title = "Teleport to Missing Kids",
            Value = autoLostEnabled,
            Callback = function(state)
                autoLostEnabled = state and true or false
                refreshLostBtn()
            end
        })

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
                local h = hum()
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

        -- tag chests opened by THIS player when a prompt fires
        local function tagChestFromPrompt(prompt)
            if not prompt then return end
            local node = prompt
            for _ = 1, 8 do
                if not node then break end
                if node:IsA("Model") then
                    local n = node.Name
                    if type(n) == "string" and (n:match("Chest%d*$") or n:match("Chest$")) then
                        pcall(function()
                            node:SetAttribute(UID_OPEN_KEY, true)
                        end)
                        break
                    end
                end
                node = node.Parent
            end
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

                -- mark chest as opened by this user
                tagChestFromPrompt(prompt)

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
        local OFF_PULSE_EVERY = 1.5
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
                        for _=1,2 do torchHit(target) end
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
        local cam = WS.CurrentCamera
        WS:GetPropertyChangedSignal("CurrentCamera"):Connect(function() cam = WS.CurrentCamera end)

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
        local COIN_RADIUS      = 20
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
        local function findCoinCarrier(inst)
            local cur = inst
            for _ = 1, 8 do
                if not cur then break end
                if cur:IsA("Model") and cur.Name == "Coin Stack" then return cur end
                if cur:IsA("Model") and isMossyName(cur.Name) and cur.Parent and cur.Parent:IsA("Model") and cur.Parent.Name == "Coin Stack" then
                    return cur.Parent
                end
                cur = cur.Parent
            end
            return nil
        end
        local function findMossyOrStack(inst)
            local stack = findCoinCarrier(inst)
            if stack then return stack end
            local cur = inst
            for _ = 1, 8 do
                if not cur then break end
                if cur:IsA("Model") and isMossyName(cur.Name) then return cur end
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
        local function tryRemote(targetModel)
            local remote = RS:WaitForChild("RemoteEvents"):WaitForChild("RequestCollectCoints")
            local ok = false
            do
                local s, r = pcall(function() return remote:InvokeServer(targetModel) end)
                ok = s and (r ~= nil or true)
                if ok then return true end
            end
            do
                local stack = findCoinCarrier(targetModel)
                if stack then
                    local s, r = pcall(function() return remote:InvokeServer(stack) end)
                    ok = s and (r ~= nil or true)
                    if ok then return true end
                end
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
                        local target = findMossyOrStack(res.Instance)
                        if target and target.Parent then
                            local pos = (target.PrimaryPart and target.PrimaryPart.Position) or target:GetPivot().Position
                            if (pos - origin).Magnitude <= COIN_RADIUS then
                                local t = coinSeen[target]
                                if not t or now - t > COIN_TTL then
                                    local done = triggerPromptOn(target)
                                    if not done then done = clickDetectorOn(target) end
                                    if not done then tryRemote(target) end
                                    coinSeen[target] = now
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

        local function itemsFolder() return WS:FindFirstChild("Items") end
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
        local function groundBelow2(pos)
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
        local function groundAtFeetCF()
            local root = hrp(); if not root then return nil end
            local g = groundBelow2(root.Position)
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
        local PLANT_START_DELAY       = 1.0
        local PLANT_Y_EPSILON         = 0.15
        local PLANT_INTERACTION_DELAY = 0
        local PLANT_CHAIN_DELAY       = nil
        local function yieldPlant(seconds)
            if seconds == nil then return end
            if seconds <= 0 then
                Run.Heartbeat:Wait()
            else
                task.wait(seconds)
            end
        end
        local function computePlantPosFromModel(m)
            local mp = mainPart(m); if not mp then return nil end
            local g  = groundBelow2(mp.Position)
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
            yieldPlant(PLANT_INTERACTION_DELAY)
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
            yieldPlant(PLANT_INTERACTION_DELAY)
            if stopDrag then pcall(function() stopDrag:FireServer(m) end); pcall(function() stopDrag:FireServer(Instance.new("Model")) end) end
        end
        local function actionPlantAllSaplings()
            task.wait(PLANT_START_DELAY)
            local snap = collectSaplingsSnapshot()
            for i=1,#snap do
                local m = snap[i]
                if m and m.Parent then plantModelInPlace(m) end
                yieldPlant(PLANT_CHAIN_DELAY)
            end
        end

        local chestFinderOn = false
        local enableChestFinder, disableChestFinder
        tab:Toggle({
            Title = "Find Unopened Chests",
            Value = false,
            Callback = function(state)
                if state then
                    if enableChestFinder then enableChestFinder() end
                else
                    if disableChestFinder then disableChestFinder() end
                end
            end
        })
        do
            local nextChestBtn = stack:FindFirstChild("NextChestEdge") or (function()
                local b = Instance.new("TextButton")
                b.Name = "NextChestEdge"
                b.Size = UDim2.new(1, 0, 0, 30)
                b.Text = "Nearest Unopened Chest"
                b.TextSize = 12
                b.Font = Enum.Font.GothamBold
                b.BackgroundColor3 = Color3.fromRGB(30,30,35)
                b.TextColor3 = Color3.new(1,1,1)
                b.BorderSizePixel = 0
                b.Visible = false
                b.LayoutOrder = 6
                b.Parent = stack
                local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = b
                return b
            end)()
            local function itemsFolder2() return WS:FindFirstChild("Items") end
            local function mainPart2(m)
                if not m then return nil end
                if m:IsA("BasePart") then return m end
                if m:IsA("Model") then
                    if m.PrimaryPart then return m.PrimaryPart end
                    return m:FindFirstChildWhichIsA("BasePart")
                end
                return nil
            end
            local function groundBelow3(pos)
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = { lp.Character, WS:FindFirstChild("Items") }
                local start = pos + Vector3.new(0, 5, 0)
                local hit = WS:Raycast(start, Vector3.new(0, -1000, 0), params)
                if hit then return hit.Position end
                hit = WS:Raycast(pos + Vector3.new(0, 200, 0), Vector3.new(0, -1000, 0), params)
                return (hit and hit.Position) or pos
            end
            local chests = {}
            local diamondModel = nil
            local DIAMOND_PAIR_DIST   = 9.8
            local DIAMOND_PAIR_TOL    = 2.0
            local EXCLUDE_NAMES = { ["Stronghold Diamond Chest"] = true }
            local function isChestName2(n)
                if type(n) ~= "string" then return false end
                return n:match("Chest%d*$") ~= nil or n:match("Chest$") ~= nil
            end
            local function isSnowChestName(n)
                if type(n) ~= "string" then return false end
                return (n == "Snow Chest") or (n:match("^Snow Chest%d+$") ~= nil)
            end
            local function isHalloweenChestName(n)
                if type(n) ~= "string" then return false end
                return (n == "Halloween Chest") or (n:match("^Halloween Chest%d+$") ~= nil)
            end
            -- chest opened for THIS user only
            local function chestOpened2(m)
                if not m then return false end
                return m:GetAttribute(UID_OPEN_KEY) == true
            end
            local function chestPos(m)
                local mp = mainPart2(m)
                if mp then return mp.Position end
                local ok, cf = pcall(function() return m:GetPivot() end)
                return ok and cf.Position or nil
            end
            local function markChest(m)
                if not (m and m:IsA("Model")) then return end
                if not isChestName2(m.Name) then return end
                local pos = chestPos(m); if not pos then return end
                local excluded = EXCLUDE_NAMES[m.Name] or isSnowChestName(m.Name) or isHalloweenChestName(m.Name) or false
                local rec = chests[m]
                if not rec then
                    chests[m] = { pos = pos, opened = chestOpened2(m), excluded = excluded }
                    m:GetAttributeChangedSignal(UID_OPEN_KEY):Connect(function()
                        local r = chests[m]; if r then r.opened = chestOpened2(m) end
                    end)
                    m:GetPropertyChangedSignal("PrimaryPart"):Connect(function() local r=chests[m]; if r then r.pos = chestPos(m) or r.pos end end)
                    m.AncestryChanged:Connect(function(_, parent) if not parent then chests[m] = nil end end)
                else
                    rec.pos = pos
                    rec.opened = chestOpened2(m)
                    rec.excluded = excluded
                end
                if m.Name == "Stronghold Diamond Chest" then diamondModel = m end
            end
            local function initialScan()
                chests = {}
                diamondModel = nil
                local items = itemsFolder2(); if not items then return end
                for _,m in ipairs(items:GetChildren()) do markChest(m) end
            end
            local function applyDiamondNeighborExclusion()
                if not diamondModel then return end
                local dpos = chestPos(diamondModel); if not dpos then return end
                for m,r in pairs(chests) do
                    if m ~= diamondModel and not r.excluded then
                        local dist = (r.pos - dpos).Magnitude
                        if math.abs(dist - DIAMOND_PAIR_DIST) <= DIAMOND_PAIR_TOL then
                            r.excluded = true
                        end
                    end
                end
            end
            local function excludeNearestToDiamond()
                if not diamondModel then return end
                local dpos = chestPos(diamondModel); if not dpos then return end
                local bestM, bestD = nil, math.huge
                for m,r in pairs(chests) do
                    if m ~= diamondModel and m and m.Parent then
                        local dist = (r.pos - dpos).Magnitude
                        if dist < bestD then bestD, bestM = dist, m end
                    end
                end
                if bestM then
                    local rec = chests[bestM]
                    if rec then rec.excluded = true end
                end
            end
            local function updateChestRecord(m)
                local r = chests[m]; if not r then return end
                r.pos = chestPos(m) or r.pos
                r.opened = chestOpened2(m)
                if m and m.Parent then
                    r.excluded = EXCLUDE_NAMES[m.Name] or isSnowChestName(m.Name) or isHalloweenChestName(m.Name) or r.excluded or false
                end
            end
            local function unopenedList()
                local list = {}
                for m,r in pairs(chests) do
                    if m and m.Parent and not r.opened and not r.excluded then
                        list[#list+1] = {m=m, pos=r.pos}
                    end
                end
                table.sort(list, function(a,b)
                    local rp = hrp()
                    if not rp then return false end
                    local da = (a.pos - rp.Position).Magnitude
                    local db = (b.pos - rp.Position).Magnitude
                    return da < db
                end)
                return list
            end
            local function hingeBackCenter(m)
                local pts = {}
                for _,d in ipairs(m:GetDescendants()) do
                    if d.Name == "Hinge" then
                        if d:IsA("BasePart") then
                            table.insert(pts, d.Position)
                        elseif d:IsA("Model") then
                            local mp = mainPart2(d)
                            if mp then table.insert(pts, mp.Position) end
                        end
                    end
                end
                if #pts == 0 then return nil end
                local sum = Vector3.new(0,0,0)
                for _,p in ipairs(pts) do sum += p end
                return sum / #pts
            end
            local FRONT_DIST = 4.0
            local function teleportNearChest(m)
                local mp = mainPart2(m); if not mp then return end
                local chestCenter = mp.Position
                local hingePos = hingeBackCenter(m)
                local dir
                if hingePos then
                    dir = (chestCenter - hingePos)
                    if dir.Magnitude < 1e-3 then dir = -mp.CFrame.LookVector end
                    dir = dir.Unit
                else
                    local root = hrp()
                    if root then
                        local vec = root.Position - chestCenter
                        if vec.Magnitude > 0.001 then
                            dir = (-vec).Unit
                        else
                            dir = (-mp.CFrame.LookVector).Unit
                        end
                    else
                        dir = (-mp.CFrame.LookVector).Unit
                    end
                end
                local desired = chestCenter + dir * FRONT_DIST
                local ground = groundBelow3(desired)
                local standPos = Vector3.new(desired.X, ground.Y + 2.5, desired.Z)
                teleportSticky(CFrame.new(standPos, chestCenter), true)
            end
            local cfHB, childAdd, childRem
            nextChestBtn.MouseButton1Click:Connect(function()
                local list = unopenedList()
                if #list == 0 then
                    nextChestBtn.Text = "Nearest Unopened Chest"
                    nextChestBtn.Visible = false
                    return
                end
                local target = list[1]
                teleportNearChest(target.m)
                task.delay(0.5, function()
                    local l2 = unopenedList()
                    nextChestBtn.Visible = chestFinderOn and (#l2 > 0)
                    if #l2 > 0 then
                        nextChestBtn.Text = ("Nearest Unopened Chest (%d)"):format(#l2)
                    else
                        nextChestBtn.Text = "Nearest Unopened Chest"
                    end
                end)
            end)
            local function refreshButton()
                local list = unopenedList()
                nextChestBtn.Visible = chestFinderOn and (#list > 0)
                if #list > 0 then
                    nextChestBtn.Text = ("Nearest Unopened Chest (%d)"):format(#list)
                else
                    nextChestBtn.Text = "Nearest Unopened Chest"
                end
            end
            enableChestFinder = function()
                if chestFinderOn then return end
                chestFinderOn = true
                nextChestBtn.Visible = false
                initialScan()
                applyDiamondNeighborExclusion()
                excludeNearestToDiamond()
                local items = itemsFolder2()
                if items then
                    childAdd = items.ChildAdded:Connect(function(c)
                        markChest(c)
                        applyDiamondNeighborExclusion()
                        excludeNearestToDiamond()
                    end)
                    childRem = items.ChildRemoved:Connect(function(c) chests[c] = nil end)
                end
                cfHB = Run.Heartbeat:Connect(function()
                    for m,_ in pairs(chests) do if m and m.Parent then updateChestRecord(m) end end
                    refreshButton()
                end)
                refreshButton()
            end
            disableChestFinder = function()
                chestFinderOn = false
                if cfHB then cfHB:Disconnect() cfHB = nil end
                if childAdd then childAdd:Disconnect() childAdd = nil end
                if childRem then childRem:Disconnect() childRem = nil end
                nextChestBtn.Visible = false
            end
        end

        do
            local deleteOn = false
            local addConn, remConn, sweepHB
            local tracked   = setmetatable({}, { __mode = "k" })
            local deleteExcl = setmetatable({}, { __mode = "k" })
            local DIAMOND_PAIR_DIST = 9.8
            local DIAMOND_PAIR_TOL  = 2.0
            local function isChestName3(n)
                if type(n) ~= "string" then return false end
                return n:match("Chest%d*$") ~= nil or n:match("Chest$") ~= nil
            end
            local function chestOpened3(m)
                if not m then return false end
                return m:GetAttribute(UID_OPEN_KEY) == true
            end
            local function safeHideThenDestroy(m)
                if not (m and m.Parent) then return end
                for _,d in ipairs(m:GetDescendants()) do
                    if d:IsA("ProximityPrompt") then
                        pcall(function() d.Enabled = false end)
                    elseif d:IsA("ClickDetector") then
                        pcall(function() d.MaxActivationDistance = 0 end)
                    elseif d:IsA("BasePart") then
                        pcall(function()
                            d.CanCollide = false
                            d.CanTouch   = false
                            d.CanQuery   = false
                            d.Anchored   = true
                            d.Transparency = 1
                        end)
                    end
                end
                task.delay((TRIGGER_COOLDOWN or 0.4) + 0.25, function()
                    if m and m.Parent then pcall(function() m:Destroy() end) end
                end)
            end
            local function locateDiamondAndNeighbor()
                deleteExcl = setmetatable({}, { __mode = "k" })
                local items = WS:FindFirstChild("Items"); if not items then return end
                local diamond, dpos = nil, nil
                local all = {}
                for _,m in ipairs(items:GetChildren()) do
                    if m:IsA("Model") and isChestName3(m.Name) then
                        all[#all+1] = m
                        if m.Name == "Stronghold Diamond Chest" then
                            diamond = m
                            local mp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
                            dpos = mp and mp.Position or (m:GetPivot().Position)
                        end
                    end
                end
                if not (diamond and dpos) then return end
                deleteExcl[diamond] = true
                local bestM, bestD = nil, math.huge
                for _,m in ipairs(all) do
                    if m ~= diamond then
                        local mp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
                        local p = mp and mp.Position or (m:GetPivot().Position)
                        if p then
                            local dist = (p - dpos).Magnitude
                            if math.abs(dist - DIAMOND_PAIR_DIST) <= DIAMOND_PAIR_TOL then
                                deleteExcl[m] = true
                            end
                            if dist < bestD then bestD, bestM = dist, m end
                        end
                    end
                end
                if not next(deleteExcl) and bestM then
                    deleteExcl[bestM] = true
                end
            end
            local function deleteIfOpenedNow(m)
                if not deleteOn then return end
                if not (m and m.Parent) then return end
                if not isChestName3(m.Name) then return end
                if deleteExcl[m] then return end
                if chestOpened3(m) then
                    safeHideThenDestroy(m)
                end
            end
            local function watchChest(m)
                if not (m and m:IsA("Model") and isChestName3(m.Name)) then return end
                if tracked[m] then return end
                tracked[m] = true
                m:GetAttributeChangedSignal(UID_OPEN_KEY):Connect(function()
                    deleteIfOpenedNow(m)
                end)
                m.AncestryChanged:Connect(function(_, parent)
                    if not parent then tracked[m] = nil end
                end)
                deleteIfOpenedNow(m)
            end
            local function scanAll()
                local items = WS:FindFirstChild("Items"); if not items then return end
                for _,child in ipairs(items:GetChildren()) do
                    watchChest(child)
                end
            end
            local function sweepDeleteOpened()
                if not deleteOn then return end
                local items = WS:FindFirstChild("Items"); if not items then return end
                for _,m in ipairs(items:GetChildren()) do
                    if m:IsA("Model") and isChestName3(m.Name) then
                        deleteIfOpenedNow(m)
                    end
                end
            end
            local function enableDelete()
                if deleteOn then return end
                deleteOn = true
                locateDiamondAndNeighbor()
                scanAll()
                sweepDeleteOpened()
                local items = WS:FindFirstChild("Items")
                if items then
                    addConn = items.ChildAdded:Connect(function(m)
                        if m and m:IsA("Model") then
                            if m.Name == "Stronghold Diamond Chest" or isChestName3(m.Name) then
                                locateDiamondAndNeighbor()
                            end
                            watchChest(m)
                        end
                    end)
                    remConn = items.ChildRemoved:Connect(function(m)
                        tracked[m] = nil
                        if m and (m.Name == "Stronghold Diamond Chest" or isChestName3(m.Name)) then
                            task.delay(0, locateDiamondAndNeighbor)
                        end
                    end)
                end
                if sweepHB then sweepHB:Disconnect() end
                sweepHB = Run.Heartbeat:Connect(function()
                    sweepDeleteOpened()
                end)
            end
            local function disableDelete()
                deleteOn = false
                if addConn   then addConn:Disconnect();   addConn = nil end
                if remConn   then remConn:Disconnect();   remConn = nil end
                if sweepHB   then sweepHB:Disconnect();   sweepHB = nil end
            end
            tab:Toggle({
                Title = "Delete Chests After Opening",
                Value = false,
                Callback = function(state)
                    if state then enableDelete() else disableDelete() end
                end
            })
        end

        ----------------------------------------------------------------
        -- Auto replant saplings (immediate on spawn)
        ----------------------------------------------------------------
        local autoReplantOn   = false
        local autoReplantConn = nil

        local function autoReplantCalcPos(m)
            local mp
            if mainPart2 then
                mp = mainPart2(m)
            end
            if not mp and mainPart then
                mp = mainPart(m)
            end
            if not mp then return nil end

            local center = mp.Position
            local ground = groundBelow3 and groundBelow3(center) or center
            local y = math.min(ground.Y, center.Y - (mp.Size.Y * 0.5)) - 0.15

            return Vector3.new(center.X, y, center.Z)
        end

        local function plantModelAtExactPosition(m, pos)
            local plantRF = getRemote and getRemote("RequestPlantItem")
            if not (plantRF and m and m.Parent and pos) then return end

            local startDrag = getRemote("RequestStartDraggingItem")
            local stopDrag  = getRemote("StopDraggingItem")

            if startDrag then
                pcall(function() startDrag:FireServer(m) end)
                pcall(function() startDrag:FireServer(Instance.new("Model")) end)
            end

            local INTERACTION_DELAY = 0
            if INTERACTION_DELAY > 0 then
                task.wait(INTERACTION_DELAY)
            else
                Run.Heartbeat:Wait()
            end

            local ok = pcall(function()
                if plantRF:IsA("RemoteFunction") then
                    return plantRF:InvokeServer(m, pos)
                else
                    plantRF:FireServer(m, pos)
                    return true
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

            if INTERACTION_DELAY > 0 then
                task.wait(INTERACTION_DELAY)
            else
                Run.Heartbeat:Wait()
            end

            if stopDrag then
                pcall(function() stopDrag:FireServer(m) end)
                pcall(function() stopDrag:FireServer(Instance.new("Model")) end)
            end
        end

        local function autoReplantPlantModel(m)
            local pos = autoReplantCalcPos(m)
            if not pos then return end
            plantModelAtExactPosition(m, pos)
        end

        local function handleNewSapling(child)
            if not (autoReplantOn and child and child:IsA("Model") and child.Name == "Sapling") then
                return
            end
            task.spawn(function()
                task.wait(0.1)
                if child and child.Parent then
                    autoReplantPlantModel(child)
                end
            end)
        end

        local function enableAutoReplant()
            if autoReplantOn then return end
            autoReplantOn = true
            local items = itemsFolder and itemsFolder() or WS:FindFirstChild("Items")
            if items and not autoReplantConn then
                autoReplantConn = items.ChildAdded:Connect(handleNewSapling)
            end
        end

        local function disableAutoReplant()
            autoReplantOn = false
            if autoReplantConn then
                autoReplantConn:Disconnect()
                autoReplantConn = nil
            end
        end

        ----------------------------------------------------------------
        -- Circle-plant saplings in air at current position
        ----------------------------------------------------------------
        local CIRCLE_SAPLINGS_PER_RING = 20
        local CIRCLE_RADIUS            = 4.0
        local CIRCLE_HEIGHT_STEP       = 10.0

        local function actionCirclePlantSaplingsAtPosition()
            local items = itemsFolder and itemsFolder() or WS:FindFirstChild("Items")
            if not items then return end

            local saplings = {}
            for _,m in ipairs(items:GetChildren()) do
                if m:IsA("Model") and m.Name == "Sapling" then
                    saplings[#saplings+1] = m
                end
            end
            if #saplings == 0 then return end

            local root = hrp()
            if not root then return end
            local origin = root.Position

            for i, m in ipairs(saplings) do
                if m and m.Parent then
                    local idx       = i - 1
                    local ringIndex = math.floor(idx / CIRCLE_SAPLINGS_PER_RING)
                    local angleIdx  = idx % CIRCLE_SAPLINGS_PER_RING
                    local theta     = (2 * math.pi / CIRCLE_SAPLINGS_PER_RING) * angleIdx

                    local y = origin.Y + ringIndex * CIRCLE_HEIGHT_STEP
                    local x = origin.X + math.cos(theta) * CIRCLE_RADIUS
                    local z = origin.Z + math.sin(theta) * CIRCLE_RADIUS
                    local pos = Vector3.new(x, y, z)

                    plantModelAtExactPosition(m, pos)
                end
            end
        end

        ----------------------------------------------------------------
        -- Saplings UI
        ----------------------------------------------------------------
        tab:Section({ Title = "Saplings" })
        tab:Button({ Title = "Drop Saplings", Callback = function() actionDropSaplings() end })
        tab:Button({ Title = "Plant All Saplings", Callback = function() actionPlantAllSaplings() end })

        tab:Toggle({
            Title = "Auto Replant Saplings",
            Value = false,
            Callback = function(state)
                if state then
                    enableAutoReplant()
                else
                    disableAutoReplant()
                end
            end
        })

        tab:Button({
            Title = "Auto Plant Saplings (Circles Here)",
            Callback = function()
                actionCirclePlantSaplingsAtPosition()
            end
        })

        local function enableLoadDefenseSafe()
            local f = nil
            if type(enableLoadDefense) == "function" then f = enableLoadDefense end
            if not f then
                local ok, g = pcall(function() return _G and _G.enableLoadDefense end)
                if ok and type(g) == "function" then f = g end
            end
            if f then pcall(f) end
        end
        local loadDefenseOnDefault = true
        if loadDefenseOnDefault then enableLoadDefenseSafe() end

        Players.LocalPlayer.CharacterAdded:Connect(function()
            local playerGui2 = lp:WaitForChild("PlayerGui")
            local edgeGui2 = playerGui2:FindFirstChild("EdgeButtons")
            if edgeGui2 and edgeGui2.Parent ~= playerGui2 then edgeGui2.Parent = playerGui2 end
            if phaseBtn then phaseBtn.Visible = showPhaseEdge end
            if plantBtn then plantBtn.Visible = showPlantEdge end
            if tpBtn    then tpBtn.Visible    = showTeleportEdge end
            if campBtn  then campBtn.Visible  = showCampEdge end
            if noShadowsOn and not lightConn then enableNoShadows() end
            if loadDefenseOnDefault then enableLoadDefenseSafe() end
            pcall(function() WS.StreamingPauseMode = Enum.StreamingPauseMode.Disabled end)
            if coinOn and not coinConn then enableCoin() end
            if chestFinderOn and enableChestFinder then enableChestFinder() end

            if autoReplantOn and not autoReplantConn then
                local items = itemsFolder and itemsFolder() or WS:FindFirstChild("Items")
                if items then
                    autoReplantConn = items.ChildAdded:Connect(handleNewSapling)
                end
            end
        end)
    end
    local ok, err = pcall(run)
    if not ok then warn("[Auto] module error: " .. tostring(err)) end
end
