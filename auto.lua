--=====================================================
-- 1337 Nights | Auto Tab • Edge Buttons + Lost Child Toggle + Instant Interact
--  + PlaceEdge button (visible while Gather is ON)
--=====================================================
return function(C, R, UI)
    local Players = (C and C.Services and C.Services.Players) or game:GetService("Players")
    local RS      = (C and C.Services and C.Services.RS)      or game:GetService("ReplicatedStorage")
    local WS      = (C and C.Services and C.Services.WS)      or game:GetService("Workspace")

    local lp = Players.LocalPlayer
    local Tabs = (UI and UI.Tabs) or {}
    local tab  = Tabs.Auto
    if not tab then
        warn("[Auto] Auto tab not found in UI")
        return
    end

    --========================
    -- Shared helpers
    --========================
    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
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
    local function teleportTo(cf)
        local root = hrp(); if not root then return end
        zeroAssembly(root)
        root.CFrame = cf
        zeroAssembly(root)
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

    --========================
    -- Edge button GUI
    --========================
    local PHASE_DIST = 10
    local ROW_HEIGHT = 36
    local TOP_PAD    = 6

    local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
    local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
    if not edgeGui then
        edgeGui = Instance.new("ScreenGui")
        edgeGui.Name = "EdgeButtons"
        edgeGui.ResetOnSpawn = false
        edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        edgeGui.Parent = playerGui
    end

    local function makeEdgeBtn(name, label)
        local b = edgeGui:FindFirstChild(name)
        if not b then
            b = Instance.new("TextButton")
            b.Name = name
            b.AnchorPoint = Vector2.new(1, 0)
            b.Position    = UDim2.new(1, -6, 0, TOP_PAD) -- y will be laid out
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

    -- New: Place button (appears while Gather is ON)
    local placeBtn = makeEdgeBtn("PlaceEdge",  "Place")
    local phaseBtn = makeEdgeBtn("Phase10Edge","Phase 10")
    local tpBtn    = makeEdgeBtn("TpEdge",     "Teleport")
    local plantBtn = makeEdgeBtn("PlantEdge",  "Plant")
    local lostBtn  = makeEdgeBtn("LostEdge",   "Lost Child")

    -- Lay out buttons top→bottom with uniform spacing based on visibility
    local function layoutEdgeButtons()
        local yIndex = 0
        local function placeRow(btn)
            if not btn.Visible then return end
            btn.Position = UDim2.new(1, -6, 0, TOP_PAD + yIndex * ROW_HEIGHT)
            yIndex += 1
        end
        -- Order: Place (if visible) above Phase, then Phase, Teleport, Plant, Lost
        placeRow(placeBtn)
        placeRow(phaseBtn)
        placeRow(tpBtn)
        placeRow(plantBtn)
        placeRow(lostBtn)
    end

    --========================
    -- Edge button behaviors
    --========================
    phaseBtn.MouseButton1Click:Connect(function()
        local root = hrp()
        if not root then return end
        local dest = root.Position + root.CFrame.LookVector * PHASE_DIST
        teleportTo(CFrame.new(dest, dest + root.CFrame.LookVector))
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
        teleportTo(markedCF)
    end)

    --========================
    -- Plant helpers
    --========================
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

        local root = hrp()
        if not root then return end
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
    plantBtn.MouseButton1Click:Connect(function()
        plantNearestSaplingInFront()
    end)

    --========================
    -- Lost Child
    --========================
    local MAX_TO_SAVE   = 4
    local SCAN_INTERVAL = 0.5
    local savedCount    = 0
    local knownLost     = {}
    local autoLostEnabled = false

    local function isLostChildModel(m)
        return m and m:IsA("Model") and m.Name:match("^Lost Child")
    end
    local function isEligibleLost(m)
        return isLostChildModel(m) and (m:GetAttribute("Lost") == true)
    end
    local function findNearestEligibleLost()
        local root = hrp(); if not root then return nil end
        local best, bestD = nil, math.huge
        for _,d in ipairs(WS:GetDescendants()) do
            if isEligibleLost(d) then
                local mp = mainPart(d)
                if mp then
                    local dist = (mp.Position - root.Position).Magnitude
                    if dist < bestD then bestD, best = dist, d end
                end
            end
        end
        return best
    end
    local function teleportToNearestLost()
        if savedCount >= MAX_TO_SAVE then return end
        local target = findNearestEligibleLost()
        if not target then return end

        local root = hrp(); if not root then return end
        local hadNoclip = isNoclipNow()
        local snap
        if not hadNoclip then
            snap = snapshotCollide()
            setCollideAll(false)
        end

        local mp = mainPart(target)
        if mp then
            teleportTo(CFrame.new(mp.Position + Vector3.new(0, 3, 0), mp.Position))
        end

        if not hadNoclip then
            setCollideAll(true, snap)
        end
    end
    lostBtn.MouseButton1Click:Connect(function()
        teleportToNearestLost()
    end)

    --========================
    -- NEW: PlaceEdge wiring
    --========================
    local function isGatherOn()
        -- Prefer explicit API from Gather module if present
        if C and C.Gather and typeof(C.Gather.IsOn) == "function" then
            local ok, val = pcall(C.Gather.IsOn)
            if ok and val ~= nil then return val end
        end
        -- Fallback to shared state, if maintained by your gather.lua
        if C and C.State and C.State.Toggles and type(C.State.Toggles.GatherOn) == "boolean" then
            return C.State.Toggles.GatherOn
        end
        return false
    end

    local function placeDownViaGather()
        -- Prefer direct function from Gather
        if C and C.Gather and typeof(C.Gather.PlaceDown) == "function" then
            local ok = pcall(C.Gather.PlaceDown)
            if ok then return end
        end
        -- Optional: as a last resort, try a Bindable in RS (if you wire one there)
        local be = RS:FindFirstChild("GatherPlaceDownBindable")
        if be and be:IsA("BindableEvent") then
            pcall(function() be:Fire() end)
        end
    end

    placeBtn.MouseButton1Click:Connect(function()
        placeDownViaGather()
    end)

    --========================
    -- Background updater (visibility + layout)
    --========================
    task.spawn(function()
        while true do
            -- Lost button visibility is managed here already
            for _,d in ipairs(WS:GetDescendants()) do
                if isLostChildModel(d) then
                    local cur = d:GetAttribute("Lost") == true
                    local prev = knownLost[d]
                    if prev == nil then
                        knownLost[d] = cur
                    elseif prev == true and cur == false then
                        if savedCount < MAX_TO_SAVE then
                            savedCount += 1
                        end
                        knownLost[d] = cur
                    else
                        knownLost[d] = cur
                    end
                end
            end

            local anyEligible = false
            if savedCount < MAX_TO_SAVE and autoLostEnabled then
                anyEligible = (findNearestEligibleLost() ~= nil)
            end
            lostBtn.Visible = anyEligible and autoLostEnabled

            -- NEW: show/hide Place button based on Gather mode
            local showPlace = isGatherOn()
            if placeBtn.Visible ~= showPlace then
                placeBtn.Visible = showPlace
            end

            -- Maintain layout order and spacing
            layoutEdgeButtons()

            task.wait(SCAN_INTERVAL)
        end
    end)

    --========================
    -- Auto tab toggles
    --========================
    tab:Section({ Title = "Quick Moves", Icon = "zap" })

    tab:Toggle({
        Title = "Show Phase 10 button",
        Value = false,
        Callback = function(state)
            phaseBtn.Visible = state
            layoutEdgeButtons()
        end
    })

    tab:Toggle({
        Title = "Show Teleport button",
        Value = false,
        Callback = function(state)
            tpBtn.Visible = state
            layoutEdgeButtons()
        end
    })

    tab:Toggle({
        Title = "Plant Saplings",
        Value = false,
        Callback = function(state)
            plantBtn.Visible = state
            layoutEdgeButtons()
        end
    })

    tab:Toggle({
        Title = "Auto Teleport to Lost Child",
        Value = false,
        Callback = function(state)
            autoLostEnabled = state
            if not state then
                lostBtn.Visible = false
            end
            layoutEdgeButtons()
        end
    })

    -- Instant Interact
    local promptDurations = setmetatable({}, { __mode = "k" })
    local promptsConn

    local function setPromptInstant(p)
        if not p or not p:IsA("ProximityPrompt") then return end
        if promptDurations[p] == nil then
            promptDurations[p] = p.HoldDuration
        end
        p.HoldDuration = 0
    end
    local function enableInstantInteract()
        if promptsConn then return end
        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                setPromptInstant(d)
            end
        end
        promptsConn = WS.DescendantAdded:Connect(function(d)
            if d:IsA("ProximityPrompt") then
                setPromptInstant(d)
            end
        end)
    end
    local function disableInstantInteract()
        if promptsConn then
            promptsConn:Disconnect()
            promptsConn = nil
        end
        for p,orig in pairs(promptDurations) do
            if p and p.Parent then
                p.HoldDuration = typeof(orig) == "number" and orig or p.HoldDuration
            end
        end
    end

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
        -- layout refresh on respawn
        layoutEdgeButtons()
    end)
end
