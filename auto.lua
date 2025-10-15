--=====================================================
-- 1337 Nights | Auto Tab • Edge Buttons (Phase 10 / Teleport / Plant Saplings / Instant Open / Bring Lost Child via Drag-Hop)
--=====================================================
return function(C, R, UI)
    local Players = C.Services.Players
    local RS      = C.Services.RS or game:GetService("ReplicatedStorage")
    local WS      = C.Services.WS or game:GetService("Workspace")
    local PPS     = game:GetService("ProximityPromptService")
    local Run     = C.Services.Run or game:GetService("RunService")
    local lp      = Players.LocalPlayer

    local Tabs    = UI and UI.Tabs or {}
    local tab     = Tabs.Auto
    assert(tab, "Auto tab not found in UI")

    --========================
    -- Utilities
    --========================
    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end
    local function humanoid()
        local ch = lp.Character
        return ch and ch:FindFirstChildOfClass("Humanoid")
    end
    local function mainPart(model)
        if not (model and model:IsA("Model")) then return nil end
        if model.PrimaryPart then return model.PrimaryPart end
        return model:FindFirstChildWhichIsA("BasePart")
    end
    local function getRemote(name)
        local remotesFolder = RS:FindFirstChild("RemoteEvents")
        return remotesFolder and remotesFolder:FindFirstChild(name) or nil
    end
    local function waitHeartbeats(n)
        for _=1,(n or 1) do Run.Heartbeat:Wait() end
    end

    --========================
    -- Edge buttons (no Rayfield)
    --========================
    local PHASE_DIST = 10 -- Phase 10 distance forward

    local edgeGui = lp:WaitForChild("PlayerGui"):FindFirstChild("EdgeButtons")
    if not edgeGui then
        edgeGui = Instance.new("ScreenGui")
        edgeGui.Name = "EdgeButtons"
        edgeGui.ResetOnSpawn = false
        edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        edgeGui.Parent = lp:WaitForChild("PlayerGui")
    end

    local function makeEdgeBtn(name, row, label)
        local b = edgeGui:FindFirstChild(name)
        if not b then
            b = Instance.new("TextButton")
            b.Name = name
            b.AnchorPoint = Vector2.new(1, 0)
            b.Position    = UDim2.new(1, -6, 0, 6 + (row-1)*36) -- rows: 1=top, 2=middle, 3=bottom, 4=below
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

    -- Buttons (fixed row indices to lock absolute placement)
    local phaseBtn   = makeEdgeBtn("Phase10Edge", 1, "Phase 10")
    local tpBtn      = makeEdgeBtn("TpEdge",      2, "Teleport")
    local plantBtn   = makeEdgeBtn("PlantEdge",   3, "Plant")

    --========================
    -- Phase 10 behavior
    --========================
    phaseBtn.MouseButton1Click:Connect(function()
        local root = hrp()
        if not root then return end
        local dest = root.Position + root.CFrame.LookVector * PHASE_DIST
        root.AssemblyLinearVelocity  = Vector3.new(0,0,0)
        root.AssemblyAngularVelocity = Vector3.new(0,0,0)
        root.CFrame = CFrame.new(dest, dest + root.CFrame.LookVector)
        root.AssemblyLinearVelocity  = Vector3.new(0,0,0)
        root.AssemblyAngularVelocity = Vector3.new(0,0,0)
    end)

    --========================
    -- Teleport behavior (hold to mark, tap to go)
    --========================
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
        local root = hrp()
        if not (root and markedCF) then return end
        root.AssemblyLinearVelocity  = Vector3.new(0,0,0)
        root.AssemblyAngularVelocity = Vector3.new(0,0,0)
        root.CFrame = markedCF
        root.AssemblyLinearVelocity  = Vector3.new(0,0,0)
        root.AssemblyAngularVelocity = Vector3.new(0,0,0)
    end)

    --========================
    -- Plant Saplings behavior
    --========================
    local AHEAD_DIST  = 3
    local RAY_HEIGHT  = 500
    local RAY_DEPTH   = 2000

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
                    if d < bestDist then
                        bestDist = d
                        closest  = m
                    end
                end
            end
        end
        return closest
    end

    local function groundAhead(root)
        local base    = root.Position + root.CFrame.LookVector * AHEAD_DIST
        local start   = base + Vector3.new(0, RAY_HEIGHT, 0)
        local result  = WS:Raycast(start, Vector3.new(0, -RAY_DEPTH, 0))
        return result and result.Position or base
    end

    local function plantNearestSaplingInFront()
        local sapling = findClosestSapling()
        if not sapling then return end

        local startDrag = getRemote("RequestStartDraggingItem")
        local stopDrag  = getRemote("StopDraggingItem")
        local plantRF   = getRemote("RequestPlantItem")

        local root = hrp()
        if not root then return end
        local plantPos = groundAhead(root)

        if startDrag then
            pcall(function() startDrag:FireServer(sapling) end)
            pcall(function() startDrag:FireServer(Instance.new("Model")) end)
        end

        task.wait(0.05)

        if plantRF then
            local did = pcall(function()
                return plantRF:InvokeServer(sapling, Vector3.new(plantPos.X, plantPos.Y, plantPos.Z))
            end)
            if not did then
                local dummy = Instance.new("Model")
                did = pcall(function()
                    return plantRF:InvokeServer(dummy, Vector3.new(plantPos.X, plantPos.Y, plantPos.Z))
                end)
            end
            if not did then
                pcall(function() plantRF:FireServer(sapling, Vector3.new(plantPos.X, plantPos.Y, plantPos.Z)) end)
                pcall(function() plantRF:FireServer(Instance.new("Model"), Vector3.new(plantPos.X, plantPos.Y, plantPos.Z)) end)
            end
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
    -- Instant Open (ProximityPrompt) behavior
    --========================
    local instantOpen = false
    local promptShownConn

    local KEYWORDS_NAME   = {"chest","crate","locker","cabinet","cupboard","safe","case","stash","cache","box"}
    local KEYWORDS_ACTION = {"open","unlock","search","loot"}

    local function containsAny(s, list)
        s = string.lower(s or "")
        for _,k in ipairs(list) do
            if string.find(s, k, 1, true) then return true end
        end
        return false
    end

    local function shouldTargetPrompt(prompt)
        if not prompt or not prompt:IsA("ProximityPrompt") then return false end
        if containsAny(prompt.ActionText or "", KEYWORDS_ACTION) then return true end
        local p = prompt.Parent
        while p and p ~= WS do
            if containsAny(p.Name or "", KEYWORDS_NAME) then return true end
            p = p.Parent
        end
        return false
    end

    local function patchPrompt(prompt)
        if not (prompt and prompt:IsA("ProximityPrompt")) then return end
        if not shouldTargetPrompt(prompt) then return end
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
    end

    local function scanExistingPrompts()
        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                patchPrompt(d)
            end
        end
    end

    local function enableInstantOpen()
        if instantOpen then return end
        instantOpen = true
        promptShownConn = PPS.PromptShown:Connect(function(prompt)
            patchPrompt(prompt)
        end)
        scanExistingPrompts()
    end

    local function disableInstantOpen()
        instantOpen = false
        if promptShownConn then promptShownConn:Disconnect() promptShownConn = nil end
    end

    --========================
    -- Bring Lost Child (drag-hop)
    --========================
    local APPROACH_DIST = 2.0
    local RETURN_HB     = 3
    local DRAG_HB       = 3

    local function hopPlayer(toCF)
        local root = hrp()
        if not (root and toCF) then return end
        root.AssemblyLinearVelocity  = Vector3.new()
        root.AssemblyAngularVelocity = Vector3.new()
        root.CFrame = toCF
    end

    local function groundAt(pos)
        local start = pos + Vector3.new(0, 500, 0)
        local rc = WS:Raycast(start, Vector3.new(0, -2000, 0))
        return rc and rc.Position or pos
    end

    local function approachCFForPart(part, homePos)
        local p = part.Position
        local dir = (homePos and (homePos - p).Unit) or Vector3.new(1,0,0)
        if dir.Magnitude == 0 then dir = Vector3.new(1,0,0) end
        local flatDir = Vector3.new(dir.X, 0, dir.Z)
        if flatDir.Magnitude == 0 then flatDir = Vector3.new(1,0,0) end
        flatDir = flatDir.Unit
        local target = p + flatDir * APPROACH_DIST
        local gp = groundAt(target) + Vector3.new(0, 3, 0)
        return CFrame.lookAt(gp, Vector3.new(p.X, gp.Y, p.Z))
    end

    local function startDrag(model)
        local re = getRemote("RequestStartDraggingItem")
        if re then pcall(function() re:FireServer(model) end) end
    end
    local function stopDrag(model)
        local re = getRemote("StopDraggingItem")
        if re then pcall(function() re:FireServer(model) end) end
    end

    local function findNearestLostChild()
        local chars = WS:FindFirstChild("Characters")
        if not chars then return nil end
        local root = hrp()
        if not root then return nil end
        local nearest, best = nil, math.huge
        for _,m in ipairs(chars:GetChildren()) do
            if m:IsA("Model") then
                local n = m.Name or ""
                -- Match: "Lostchild" or "Lostchild <digits>"
                if n == "Lostchild" or n:match("^Lostchild%s*%d+$") then
                    local mp = mainPart(m)
                    if mp then
                        local d = (mp.Position - root.Position).Magnitude
                        if d < best then
                            best = d
                            nearest = m
                        end
                    end
                end
            end
        end
        return nearest
    end

    local function dragHopBringChild(childModel)
        local root = hrp()
        if not (root and childModel) then return end
        local mp = mainPart(childModel)
        if not mp then return end

        local homeCF = root.CFrame
        local approachCF = approachCFForPart(mp, homeCF.Position)

        -- hop to child, start drag, hop back, stop drag
        hopPlayer(approachCF)
        waitHeartbeats(RETURN_HB)

        startDrag(childModel)
        waitHeartbeats(DRAG_HB)

        hopPlayer(homeCF)
        waitHeartbeats(RETURN_HB)

        stopDrag(childModel)
    end

    --========================
    -- Wind UI switches
    --========================
    tab:Section({ Title = "Quick Moves", Icon = "zap" })

    tab:Toggle({
        Title = "Show Phase 10 button",
        Value = false,
        Callback = function(state)
            phaseBtn.Visible = state
        end
    })

    tab:Toggle({
        Title = "Show Teleport button",
        Value = false,
        Callback = function(state)
            tpBtn.Visible = state
        end
    })

    tab:Toggle({
        Title = "Plant Saplings",
        Value = false,
        Callback = function(state)
            plantBtn.Visible = state
        end
    })

    tab:Toggle({
        Title = "Instant Open (chests)",
        Value = false,
        Callback = function(state)
            if state then enableInstantOpen() else disableInstantOpen() end
        end
    })

    -- Button: Bring Lost Child (drag-hop)
    tab:Button({
        Title = "Bring Lost Child",
        Callback = function()
            local child = findNearestLostChild()
            if child then
                dragHopBringChild(child)
            end
        end
    })

    -- Buttons persist across respawn (ResetOnSpawn=false); no further action required
    lp.CharacterAdded:Connect(function()
        -- If PlayerGui ever gets rebuilt externally, re-parent edgeGui here.
    end)
end
