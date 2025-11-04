-- File: modules/tpbring.lua
return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.TPBring, "tpbring.lua: TPBring tab missing")

    local Players  = (C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C.Services and C.Services.Run)      or game:GetService("RunService")

    local lp = C.LocalPlayer or Players.LocalPlayer

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end
    local function mainPart(m)
        if not (m and m:IsA("Model")) then return nil end
        if m.PrimaryPart then return m.PrimaryPart end
        return m:FindFirstChildWhichIsA("BasePart")
    end
    local function zeroAssembly(root)
        if not root then return end
        root.AssemblyLinearVelocity  = Vector3.new(0,0,0)
        root.AssemblyAngularVelocity = Vector3.new(0,0,0)
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
    local function teleportSticky(cf)
        local root = hrp(); if not root then return end
        local ch = lp.Character
        local snap = snapshotCollide()
        setCollideAll(false)
        for i=1,6 do
            if ch then pcall(function() ch:PivotTo(cf) end) end
            pcall(function() root.CFrame = cf end)
            zeroAssembly(root)
            Run.Heartbeat:Wait()
        end
        setCollideAll(true, snap)
        zeroAssembly(root)
    end

    local function groundBelow(pos)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local a = WS:Raycast(pos + Vector3.new(0, 5, 0), Vector3.new(0, -1000, 0), params)
        if a then return a.Position end
        local b = WS:Raycast(pos + Vector3.new(0, 200, 0), Vector3.new(0, -1000, 0), params)
        return (b and b.Position) or pos
    end

    local function itemsFolder()
        return WS:FindFirstChild("Items")
    end
    local function getRemote(name)
        local f = RS:FindFirstChild("RemoteEvents")
        return f and f:FindFirstChild(name) or nil
    end

    local TREE_NAMES = { ["Small Tree"]=true, ["Snowy Small Tree"]=true, ["Small Webbed Tree"]=true }
    local function isSmallTreeModel(m)
        return m and m:IsA("Model") and TREE_NAMES[m.Name] == true
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

    local stopBtn = makeEdgeBtn("StopLogsEdge", "STOP", 21)

    local orb, orbCF
    local function createOrbAtPlayer()
        local root = hrp(); if not root then return end
        if orb then pcall(function() orb:Destroy() end) orb = nil end
        local p = Instance.new("Part")
        p.Name = "__LogOrb__"
        p.Shape = Enum.PartType.Ball
        p.Size = Vector3.new(2.4, 2.4, 2.4)
        p.Material = Enum.Material.Neon
        p.Color = Color3.fromRGB(80, 180, 255)
        p.Anchored = true
        p.CanCollide = false
        local pos = groundBelow(root.Position)
        orbCF = CFrame.new(Vector3.new(pos.X, pos.Y + 2.0, pos.Z))
        p.CFrame = orbCF
        p.Parent = WS
        orb = p
    end

    local running = false

    local function nearestSmallTree(origin)
        local best, bestD = nil, math.huge
        for _,d in ipairs(WS:GetDescendants()) do
            if isSmallTreeModel(d) then
                local part = mainPart(d)
                if part then
                    local dist = (part.Position - origin).Magnitude
                    if dist < bestD then bestD, best = dist, d end
                end
            end
        end
        return best
    end

    local function waitTreeDestroyedAndFindLog(treeModel, timeout)
        local deadline = os.clock() + (timeout or 15)
        local treeGone = false
        local treePos = nil
        local mp = mainPart(treeModel)
        if mp then treePos = mp.Position end
        local logFound = nil
        local items = itemsFolder()
        local nearby = {}
        local function consider(child)
            if not child or not child:IsA("Model") then return end
            if child.Name ~= "Log" then return end
            local pm = mainPart(child)
            if not pm then return end
            local p = pm.Position
            local ref = treePos or p
            if (p - ref).Magnitude <= 30 then
                nearby[#nearby+1] = child
            end
        end
        local addConn
        if items then
            addConn = items.ChildAdded:Connect(function(c) consider(c) end)
            for _,c in ipairs(items:GetChildren()) do consider(c) end
        end
        while os.clock() < deadline do
            if not treeGone then
                treeGone = (not treeModel) or (not treeModel.Parent)
            end
            if #nearby > 0 then
                for i=#nearby,1,-1 do
                    local m = nearby[i]
                    if m and m.Parent then
                        logFound = m; break
                    else
                        table.remove(nearby, i)
                    end
                end
            end
            if treeGone and logFound then break end
            Run.Heartbeat:Wait()
        end
        if addConn then addConn:Disconnect() end
        return logFound
    end

    local function moveItemToOrb(model)
        if not (model and model.Parent and orbCF) then return end
        local startDrag = getRemote("RequestStartDraggingItem")
        local stopDrag  = getRemote("StopDraggingItem")
        if startDrag then pcall(function() startDrag:FireServer(model) end) end
        Run.Heartbeat:Wait()
        pcall(function()
            if model:IsA("Model") then
                model:PivotTo(orbCF + Vector3.new(0, 1.8, 0))
            else
                local p = mainPart(model)
                if p then p.CFrame = orbCF + Vector3.new(0, 1.8, 0) end
            end
        end)
        task.wait(0.05)
        if stopDrag then pcall(function() stopDrag:FireServer(model) end) end
    end

    local function standInFrontOfTree(m)
        local part = mainPart(m); if not part then return end
        local center = part.Position
        local dir = -part.CFrame.LookVector
        local desired = center + dir.Unit * 4.0
        local g = groundBelow(desired)
        local cf = CFrame.new(Vector3.new(desired.X, g.Y + 2.5, desired.Z), center)
        teleportSticky(cf)
    end

    local function getLogsLoop()
        running = true
        stopBtn.Visible = true
        while running do
            local root = hrp(); if not root then break end
            local tree = nearestSmallTree(root.Position)
            if not (tree and tree.Parent) then break end
            standInFrontOfTree(tree)
            local logItem = waitTreeDestroyedAndFindLog(tree, 20)
            if logItem and logItem.Parent then
                moveItemToOrb(logItem)
            end
            Run.Heartbeat:Wait()
        end
        stopBtn.Visible = false
    end

    stopBtn.MouseButton1Click:Connect(function()
        running = false
    end)

    Players.LocalPlayer.CharacterAdded:Connect(function()
        local pg = lp:WaitForChild("PlayerGui")
        if edgeGui and edgeGui.Parent ~= pg then edgeGui.Parent = pg end
        stopBtn.Visible = running
        if orb and not orb.Parent then orb = nil end
    end)

    local tab = UI.Tabs.TPBring
    tab:Section({ Title = "TP Bring" })
    tab:Button({
        Title = "Get Logs",
        Callback = function()
            if running then return end
            createOrbAtPlayer()
            task.spawn(getLogsLoop)
        end
    })
end
