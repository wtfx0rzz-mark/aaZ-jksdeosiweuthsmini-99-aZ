-- File: tpbring.lua
return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(UI and UI.Tabs and UI.Tabs.TPBring, "tpbring.lua: TPBring tab missing")

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

    local function snapshotCollide()
        local ch = lp.Character
        if not ch then return {} end
        local t = {}
        for _,d in ipairs(ch:GetDescendants()) do
            if d:IsA("BasePart") then t[d] = d.CanCollide end
        end
        return t
    end
    local function setCollideAll(on, snap)
        local ch = lp.Character
        if not ch then return end
        if on and snap then
            for p,can in pairs(snap) do
                if p and p.Parent then p.CanCollide = can end
            end
        else
            for _,d in ipairs(ch:GetDescendants()) do
                if d:IsA("BasePart") then d.CanCollide = false end
            end
        end
    end
    local function zeroAssemblyRoot(root)
        if not root then return end
        root.AssemblyLinearVelocity  = Vector3.new()
        root.AssemblyAngularVelocity = Vector3.new()
    end

    local function groundFrom(pos, exclude, maxDown)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = exclude or {}
        local hit = WS:Raycast(pos + Vector3.new(0, 400, 0), Vector3.new(0, -(maxDown or 2000), 0), params)
        return (hit and hit.Position) or pos
    end

    local function teleportSmooth(cf)
        local root = hrp(); if not root then return end
        local ch = lp.Character
        local snap = snapshotCollide()
        setCollideAll(false)
        for _=1,6 do
            if ch then pcall(function() ch:PivotTo(cf) end) end
            pcall(function() root.CFrame = cf end)
            zeroAssemblyRoot(root)
            Run.Heartbeat:Wait()
        end
        setCollideAll(true, snap)
        zeroAssemblyRoot(root)
    end

    local function itemsFolder() return WS:FindFirstChild("Items") end
    local function getRemote(name)
        local f = RS:FindFirstChild("RemoteEvents")
        return f and f:FindFirstChild(name) or nil
    end

    local TREE_NAMES = { ["Small Tree"]=true, ["Snowy Small Tree"]=true, ["Small Webbed Tree"]=true }
    local function isSmallTreeModel(m)
        return m and m:IsA("Model") and TREE_NAMES[m.Name] == true
    end

    local function nearestSmallTree(origin)
        local best, bestD = nil, math.huge
        for _,d in ipairs(WS:GetDescendants()) do
            if isSmallTreeModel(d) then
                local p = mainPart(d)
                if p then
                    local dist = (p.Position - origin).Magnitude
                    if dist < bestD then bestD, best = dist, d end
                end
            end
        end
        return best
    end

    local function safeCFAtTree(tree)
        local part = mainPart(tree); if not part then return nil end
        local trunkPos = part.Position
        local g = groundFrom(trunkPos, {lp.Character}, 4000)
        local dropY = g.Y + 2.6
        local dir = (trunkPos - Vector3.new(trunkPos.X, dropY, trunkPos.Z))
        local look = (dir.Magnitude > 0.01) and dir.Unit or Vector3.zAxis
        return CFrame.lookAt(Vector3.new(trunkPos.X, dropY, trunkPos.Z) + (-look*3.6), trunkPos)
    end

    local function waitTreeDestroyedAndFindLog(treeModel, timeout, cancelToken)
        local tEnd = os.clock() + (timeout or 15)
        local mp = mainPart(treeModel)
        local treePos = mp and mp.Position or nil
        local found = nil
        local it = itemsFolder()
        local nearby = {}
        local function consider(m)
            if not (m and m:IsA("Model") and m.Name=="Log") then return end
            local pm = mainPart(m); if not pm then return end
            local ref = treePos or pm.Position
            if (pm.Position - ref).Magnitude <= 30 then
                nearby[#nearby+1] = m
            end
        end
        local addConn
        if it then
            addConn = it.ChildAdded:Connect(consider)
            for _,c in ipairs(it:GetChildren()) do consider(c) end
        end
        while os.clock() < tEnd do
            if cancelToken.cancel then break end
            if #nearby > 0 then
                for i=#nearby,1,-1 do
                    local m = nearby[i]
                    if m and m.Parent then found = m; break
                    else table.remove(nearby, i) end
                end
            end
            local gone = (not treeModel) or (not treeModel.Parent)
            if gone and found then break end
            Run.Heartbeat:Wait()
        end
        if addConn then addConn:Disconnect() end
        return found
    end

    local function startDrag(model)
        local r = getRemote("RequestStartDraggingItem")
        if r then pcall(function() r:FireServer(model) end) end
        return r
    end
    local function stopDrag(model)
        local r = getRemote("StopDraggingItem")
        if r then pcall(function() r:FireServer(model) end) end
    end

    local function moveItemTo(cf, model)
        if not (model and model.Parent) then return end
        local snap = {}
        for _,p in ipairs(model:GetDescendants()) do
            if p:IsA("BasePart") then snap[p]=p.CanCollide; p.CanCollide=false end
        end
        if model:IsA("Model") then model:PivotTo(cf)
        else local p = mainPart(model); if p then p.CFrame = cf end end
        for _,p in ipairs(model:GetDescendants()) do
            if p:IsA("BasePart") then
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end
        end
        for p,can in pairs(snap) do if p and p.Parent then p.CanCollide = can end end
    end

    local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
    local edgeGui   = (function()
        local g = playerGui:FindFirstChild("EdgeButtons")
        if g then return g end
        g = Instance.new("ScreenGui")
        g.Name = "EdgeButtons"
        g.ResetOnSpawn = false
        pcall(function() g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
        g.Parent = playerGui
        return g
    end)()
    local stack = (function()
        local f = edgeGui:FindFirstChild("EdgeStack")
        if f then return f end
        f = Instance.new("Frame")
        f.Name = "EdgeStack"
        f.AnchorPoint = Vector2.new(1, 0)
        f.Position = UDim2.new(1, -6, 0, 6)
        f.Size = UDim2.new(0, 130, 1, -12)
        f.BackgroundTransparency = 1
        f.BorderSizePixel = 0
        f.Parent = edgeGui
        local list = Instance.new("UIListLayout")
        list.FillDirection = Enum.FillDirection.Vertical
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Padding = UDim.new(0, 6)
        list.HorizontalAlignment = Enum.HorizontalAlignment.Right
        list.Parent = f
        return f
    end)()
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

    local tab = UI.Tabs.TPBring
    tab:Section({ Title = "TP Bring" })

    local stopBtn = makeEdgeBtn("StopGetLogs", "STOP", 99)
    local orb, orbCF
    local running = false
    local token = { cancel=false }
    local watchdogCn

    local function destroyOrb()
        if orb then pcall(function() orb:Destroy() end) orb = nil end
        orbCF = nil
    end
    local function showStop(v)
        if stopBtn then stopBtn.Visible = v and true or false end
    end

    local function createOrbAtPlayer()
        local root = hrp(); if not root then return end
        destroyOrb()
        local pos = groundFrom(root.Position, {lp.Character}, 4000)
        local p = Instance.new("Part")
        p.Name = "__LogOrb__"
        p.Shape = Enum.PartType.Ball
        p.Size = Vector3.new(2.4, 2.4, 2.4)
        p.Material = Enum.Material.Neon
        p.Color = Color3.fromRGB(80, 180, 255)
        p.Anchored = true
        p.CanCollide = false
        orbCF = CFrame.new(Vector3.new(pos.X, pos.Y + 2.0, pos.Z))
        p.CFrame = orbCF
        p.Parent = WS
        orb = p
    end

    local function moveLogToOrb(logModel)
        if not (logModel and logModel.Parent and orbCF) then return end
        startDrag(logModel)
        Run.Heartbeat:Wait()
        moveItemTo(orbCF + Vector3.new(0, 1.8, 0), logModel)
        Run.Heartbeat:Wait()
        stopDrag(logModel)
    end

    local function keepOnTarget(targetTree)
        if watchdogCn then watchdogCn:Disconnect() watchdogCn = nil end
        watchdogCn = Run.Heartbeat:Connect(function()
            if not running then return end
            local root = hrp(); if not root then return end
            local treeAlive = targetTree and targetTree.Parent
            if not treeAlive then return end
            local part = mainPart(targetTree); if not part then return end
            local here = root.Position
            local trunk = part.Position
            local d = (here - trunk).Magnitude
            if d >= 35 then
                local cf = safeCFAtTree(targetTree)
                if cf then teleportSmooth(cf) end
            end
        end)
    end

    local function jobLoop()
        running = true
        token.cancel = false
        createOrbAtPlayer()
        showStop(true)
        while running do
            local root = hrp(); if not root then break end
            local tree = nearestSmallTree(root.Position)
            if not (tree and tree.Parent) then break end
            local destCF = safeCFAtTree(tree)
            if token.cancel then break end
            if destCF then teleportSmooth(destCF) end
            if token.cancel then break end
            keepOnTarget(tree)
            local logModel = waitTreeDestroyedAndFindLog(tree, 25, token)
            if token.cancel then break end
            if logModel and logModel.Parent then
                moveLogToOrb(logModel)
            end
            Run.Heartbeat:Wait()
        end
        if watchdogCn then watchdogCn:Disconnect() watchdogCn = nil end
        destroyOrb()
        showStop(false)
        running = false
        token.cancel = false
    end

    stopBtn.MouseButton1Click:Connect(function()
        showStop(false)
        token.cancel = true
        running = false
        if watchdogCn then watchdogCn:Disconnect() watchdogCn = nil end
        destroyOrb()
    end)

    tab:Button({
        Title = "Get Logs",
        Callback = function()
            if running then return end
            task.spawn(jobLoop)
        end
    })

    Players.LocalPlayer.CharacterAdded:Connect(function()
        local pg = lp:WaitForChild("PlayerGui")
        if edgeGui and edgeGui.Parent ~= pg then edgeGui.Parent = pg end
        if running then showStop(true) else showStop(false) end
        if orb and not orb.Parent then orb = nil; orbCF = nil end
    end)
end
