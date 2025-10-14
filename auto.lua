--=====================================================
-- 1337 Nights | Auto Tab • Edge Buttons (Phase 10 / Teleport / Plant Saplings / Instant Open / Bring Lost Child w/ temp noclip)
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

    local PHASE_DIST = 10

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

    local DROP_FORWARD = 5
    local DROP_UP      = 5

    local function computeDropCF()
        local root = hrp()
        if not root then return nil, nil end
        local forward = root.CFrame.LookVector
        local ahead   = root.Position + forward * DROP_FORWARD
        local start   = ahead + Vector3.new(0, 500, 0)
        local rc      = WS:Raycast(start, Vector3.new(0, -2000, 0))
        local basePos = rc and rc.Position or ahead
        local dropPos = basePos + Vector3.new(0, DROP_UP, 0)
        return CFrame.lookAt(dropPos, dropPos + forward), forward
    end

    local function getAllParts(target)
        local t = {}
        if target:IsA("BasePart") then
            t[1] = target
        elseif target:IsA("Model") then
            for _,d in ipairs(target:GetDescendants()) do
                if d:IsA("BasePart") then
                    t[#t+1] = d
                end
            end
        end
        return t
    end

    local function quickDrag(model)
        local startRE = getRemote("RequestStartDraggingItem")
        local stopRE  = getRemote("StopDraggingItem")
        if not (startRE and stopRE) then return end
        pcall(function() startRE:FireServer(model) end)
        task.wait(0.04)
        pcall(function() stopRE:FireServer(model) end)
    end

    local function dropAndNudgeAsync(entry, dropCF, forward)
        task.defer(function()
            if not (entry.model and entry.model.Parent and entry.part and entry.part.Parent) then return end
            quickDrag(entry.model)
            task.wait(0.08)
            local v = forward * 6 + Vector3.new(0, -30, 0)
            for _,p in ipairs(getAllParts(entry.model)) do
                p.AssemblyLinearVelocity = v
            end
        end)
    end

    local function teleportOne(entry)
        local root = hrp()
        if not (root and entry and entry.model and entry.part) then return false end
        if not entry.model.Parent or entry.part.Anchored then return false end
        local dropCF, forward = computeDropCF()
        if not dropCF then return false end
        pcall(function() entry.part:SetNetworkOwner(lp) end)
        if entry.model:IsA("Model") then
            entry.model:PivotTo(dropCF)
        else
            entry.part.CFrame = dropCF
        end
        dropAndNudgeAsync(entry, dropCF, forward)
        return true
    end

    local function sortedNear(list)
        local root = hrp()
        if not root then return list end
        table.sort(list, function(a,b)
            return (a.part.Position - root.Position).Magnitude < (b.part.Position - root.Position).Magnitude
        end)
        return list
    end

    local function collectLostChildren()
        local out = {}
        local chars = WS:FindFirstChild("Characters")
        if not chars then return out end
        for _,m in ipairs(chars:GetChildren()) do
            if m:IsA("Model") then
                local raw = (m.Name or "")
                local nm  = raw:lower():gsub("%s+", "")
                if nm == "lostchild" or nm:match("^lostchild%d+$") then
                    local mp = mainPart(m)
                    if mp and not mp.Anchored then
                        out[#out+1] = {model=m, part=mp}
                    end
                end
            end
        end
        return sortedNear(out)
    end

    local function withTemporaryNoClip(model, duration)
        local parts = getAllParts(model)
        local orig = {}
        for _,p in ipairs(parts) do
            orig[p] = p.CanCollide
            p.CanCollide = false
        end
        task.delay(duration or 1, function()
            for p,cc in pairs(orig) do
                if p and p.Parent then
                    p.CanCollide = cc
                end
            end
        end)
    end

    local function bringLostChildren()
        local list = collectLostChildren()
        if #list == 0 then return end
        for _,entry in ipairs(list) do
            withTemporaryNoClip(entry.model, 1.2)
            if teleportOne(entry) then
                task.wait(0.12)
            end
        end
    end

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

    tab:Section({ Title = "Rescue" })
    tab:Button({
        Title = "Bring Lost Child",
        Callback = function()
            bringLostChildren()
        end
    })

    lp.CharacterAdded:Connect(function()
    end)
end
