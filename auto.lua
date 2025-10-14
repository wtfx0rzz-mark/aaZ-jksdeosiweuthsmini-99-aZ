--=====================================================
-- 1337 Nights | Auto Tab • Edge Buttons (Phase 10 / Teleport / Plant Saplings / Instant Open)
--=====================================================
return function(C, R, UI)
    local Players = C.Services.Players
    local RS      = C.Services.RS or game:GetService("ReplicatedStorage")
    local WS      = C.Services.WS or game:GetService("Workspace")
    local PPS     = game:GetService("ProximityPromptService")
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
        local remotesFolder = RS:WaitForChild("RemoteEvents", 5)
        return remotesFolder and remotesFolder:FindFirstChild(name) or nil
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
        -- fixed row → fixed y-position; consistent regardless of other buttons' visibility
        local b = edgeGui:FindFirstChild(name)
        if not b then
            b = Instance.new("TextButton")
            b.Name = name
            b.AnchorPoint = Vector2.new(1, 0)
            b.Position    = UDim2.new(1, -6, 0, 6 + (row-1)*36) -- rows: 1=top, 2=middle, 3=bottom
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
            -- keep existing Position to preserve requested layout
            b.Visible = false
        end
        return b
    end

    -- Buttons (fixed row indices to lock absolute placement)
    local phaseBtn = makeEdgeBtn("Phase10Edge", 1, "Phase 10")
    local tpBtn    = makeEdgeBtn("TpEdge",      2, "Teleport")
    local plantBtn = makeEdgeBtn("PlantEdge",   3, "Plant")

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
    -- Raycast params + placement tuning
    local AHEAD_DIST  = 3     -- how far in front of the player to plant
    local RAY_HEIGHT  = 500   -- how high above target point to start the ray
    local RAY_DEPTH   = 2000  -- how far down to raycast

    local function findClosestSapling()
        -- Prefer Workspace.Items children named exactly "Sapling"
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
    local promptShownConn, promptAddedConn

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
        -- Prefer matching on either ActionText or the parent/container names
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
        -- Make it instantaneous and lenient to LOS
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
        -- (Optional) You can also reduce cooldown if present in your game with custom attributes
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
        -- Patch when a prompt is shown to the local player (cheap & reliable)
        promptShownConn = PPS.PromptShown:Connect(function(prompt)
            patchPrompt(prompt)
        end)
        -- Also patch all current prompts right now
        scanExistingPrompts()
    end

    local function disableInstantOpen()
        instantOpen = false
        if promptShownConn then promptShownConn:Disconnect() promptShownConn = nil end
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

    -- Buttons persist across respawn (ResetOnSpawn=false); no further action required
    lp.CharacterAdded:Connect(function()
        -- If PlayerGui ever gets rebuilt externally, re-parent edgeGui here.
    end)
end
