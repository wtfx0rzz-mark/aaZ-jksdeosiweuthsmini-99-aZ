-- File: tpbring.lua
return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")
    local UIS      = (C and C.Services and C.Services.UIS)      or game:GetService("UserInputService")

    local lp = Players.LocalPlayer
    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.TPBring
    assert(tab, "TPBring tab missing")

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end
    local function hum()
        local ch = lp.Character
        return ch and ch:FindFirstChildOfClass("Humanoid")
    end
    local function mainPart(m)
        if not (m and m:IsA("Model")) then return nil end
        if m.PrimaryPart then return m.PrimaryPart end
        return m:FindFirstChildWhichIsA("BasePart")
    end
    local function getRemote(n)
        local t = RS:FindFirstChild("RemoteEvents")
        return t and t:FindFirstChild(n) or nil
    end

    -- ===== safe teleport (same behavior as Phase 10) ========================
    local STICK_DURATION, STICK_EXTRA_FR = 0.35, 2
    local TELEPORT_UP_NUDGE = 0.05
    local STREAM_TIMEOUT    = 6.0

    local function zeroAssembly(root)
        if not root then return end
        root.AssemblyLinearVelocity  = Vector3.new()
        root.AssemblyAngularVelocity = Vector3.new()
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
            for p,c in pairs(snap) do if p and p.Parent then p.CanCollide = c end end
        else
            for _,d in ipairs(ch:GetDescendants()) do
                if d:IsA("BasePart") then d.CanCollide = false end
            end
        end
    end
    local function requestStreamAt(pos, timeout)
        local p = typeof(pos)=="CFrame" and pos.Position or pos
        local ok = pcall(function() WS:RequestStreamAroundAsync(p, timeout or STREAM_TIMEOUT) end)
        return ok
    end
    local function teleportSticky(cf)
        local root = hrp(); if not root then return end
        local ch   = lp.Character
        local targetCF = cf + Vector3.new(0, TELEPORT_UP_NUDGE, 0)
        requestStreamAt(targetCF)

        local snap = snapshotCollide()
        setCollideAll(false)

        if ch then pcall(function() ch:PivotTo(targetCF) end) end
        pcall(function() root.CFrame = targetCF end)
        zeroAssembly(root)

        local t0 = os.clock()
        while (os.clock() - t0) < STICK_DURATION do
            if ch then pcall(function() ch:PivotTo(targetCF) end) end
            pcall(function() root.CFrame = targetCF end)
            zeroAssembly(root)
            Run.Heartbeat:Wait()
        end
        for _=1,STICK_EXTRA_FR do
            if ch then pcall(function() ch:PivotTo(targetCF) end) end
            pcall(function() root.CFrame = targetCF end)
            zeroAssembly(root)
            Run.Heartbeat:Wait()
        end
        setCollideAll(true, snap)
        zeroAssembly(root)
    end

    -- ===== placement helpers ===============================================
    local function groundBelow(pos)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local ex = { lp.Character }
        local items = WS:FindFirstChild("Items");      if items then table.insert(ex, items) end
        local chars = WS:FindFirstChild("Characters"); if chars then table.insert(ex, chars) end
        params.FilterDescendantsInstances = ex
        local start = pos + Vector3.new(0, 200, 0)
        local hit = WS:Raycast(start, Vector3.new(0, -1000, 0), params)
        return (hit and hit.Position) or pos
    end
    local function campfireModel()
        local map = WS:FindFirstChild("Map")
        local cg  = map and map:FindFirstChild("Campground")
        local mf  = cg and cg:FindFirstChild("MainFire")
        if mf then return mf end
        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") then
                local n = (d.Name or ""):lower()
                if n=="mainfire" or n=="campfire" or n=="camp fire" then return d end
            end
        end
        return nil
    end
    local function campOrbPos()
        local fire = campfireModel(); if not fire then return nil end
        local p = mainPart(fire) or fire.PrimaryPart
        local c = (p and p.CFrame) or fire:GetPivot()
        return c.Position + Vector3.new(0, 14, 0)
    end
    local function makeOrb(pos)
        local part = Instance.new("Part")
        part.Name = "TPOrb"
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(1.5,1.5,1.5)
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(80,180,255)
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CFrame = CFrame.new(pos)
        part.Parent = WS
        return part
    end

    -- ===== item move (drag like Bring) =====================================
    local function allParts(m)
        local t = {}
        if not m then return t end
        if m:IsA("BasePart") then t[1]=m; return t end
        if m:IsA("Model") then
            for _,d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then t[#t+1]=d end end
        end
        return t
    end
    local function setCollideModel(m, on, snap)
        local parts = allParts(m)
        if on and snap then
            for p,c in pairs(snap) do if p and p.Parent then p.CanCollide = c end end
            return
        end
        local s = {}
        for _,p in ipairs(parts) do s[p]=p.CanCollide; p.CanCollide=false end
        return s
    end
    local function zeroModel(m)
        for _,p in ipairs(allParts(m)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
    end
    local function startDragRem()  return getRemote("RequestStartDraggingItem") or getRemote("StartDraggingItem") end
    local function stopDragRem()   return getRemote("StopDraggingItem") or getRemote("RequestStopDraggingItem") end

    local function dropAt(m, cf)
        local sd = startDragRem()
        local ed = stopDragRem()
        if sd then pcall(function() sd:FireServer(m) end); pcall(function() sd:FireServer(Instance.new("Model")) end) end
        Run.Heartbeat:Wait()
        local snap = setCollideModel(m, false)
        zeroModel(m)
        if m:IsA("Model") then m:PivotTo(cf) else local p=mainPart(m); if p then p.CFrame=cf end end
        setCollideModel(m, true, snap)
        if ed then pcall(function() ed:FireServer(m) end); pcall(function() ed:FireServer(Instance.new("Model")) end) end
    end

    local function collectNearbyLogs(center, radius)
        local items = WS:FindFirstChild("Items"); if not items then return {} end
        local out = {}
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(center, radius, params) or {}
        local uniq = {}
        for _,p in ipairs(parts) do
            local m = p:FindFirstAncestorOfClass("Model")
            if m and not uniq[m] and m.Name=="Log" then uniq[m]=true; out[#out+1]=m end
        end
        return out
    end

    -- ===== tree find + chop ================================================
    local TREE_NAMES = { "Small Tree", "Snowy Small Tree" }
    local CHOP_DELAY = tonumber((C and C.Config and C.Config.CHOP_SWING_DELAY) or 0.55) or 0.55
    local UID_SUFFIX = (C and C.Config and C.Config.UID_SUFFIX) or "0000000000"
    local PREFER     = (C and C.Config and C.Config.ChopPrefer) or { "Chainsaw","Strong Axe","Good Axe","Old Axe" }

    local function equipToolByName()
        local inv = lp:FindFirstChild("Inventory"); if not inv then return nil end
        for _,name in ipairs(PREFER) do
            local it = inv:FindFirstChild(name)
            if it then
                local ev = getRemote("EquipItemHandle")
                if ev then pcall(function() ev:FireServer("FireAllClients", it) end) end
                return it
            end
        end
        return nil
    end

    local function toolDamage(tree, tool, impactCF)
        local rf = getRemote("ToolDamageObject"); if not rf then return end
        local ok = pcall(function()
            if rf:IsA("RemoteFunction") then
                return rf:InvokeServer(tree, tool, UID_SUFFIX, impactCF)
            else
                rf:FireServer(tree, tool, UID_SUFFIX, impactCF); return true
            end
        end)
        return ok
    end

    local function isTreeModel(m)
        if not (m and m:IsA("Model")) then return false end
        local n = m.Name
        for _,t in ipairs(TREE_NAMES) do if n==t then return true end end
        return false
    end
    local function nearestTree(maxR)
        local items = WS:FindFirstChild("Items"); if not items then return nil end
        local rp = hrp(); if not rp then return nil end
        local best, bestD = nil, maxR or math.huge
        for _,m in ipairs(items:GetChildren()) do
            if isTreeModel(m) then
                local mp = mainPart(m)
                if mp then
                    local d = (mp.Position - rp.Position).Magnitude
                    if d < bestD then best, bestD = m, d end
                end
            end
        end
        return best
    end

    local function landByTree(tree)
        local mp = mainPart(tree); if not mp then return false end
        local trunk = mp.Position
        local g = groundBelow(trunk)
        local stand = Vector3.new(trunk.X, g.Y + 2.5, trunk.Z - 2)
        teleportSticky(CFrame.new(stand, trunk))
        return true
    end

    local function chopTree(tree)
        local mp = mainPart(tree); if not mp then return end
        local tool = equipToolByName()
        local tries = 0
        while tree and tree.Parent and tries < 60 do
            local impact = CFrame.new(mp.Position + Vector3.new(0, 0.5, 0))
            toolDamage(tree, tool, impact)
            tries += 1
            task.wait(CHOP_DELAY)
        end
    end

    -- ===== UI + control =====================================================
    local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
    local edgeGui = playerGui:FindFirstChild("EdgeButtons")
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
        stack.BorderSizePixel = 0
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
            b.LayoutOrder = order or 1
            b.Visible = false
            b.Parent = stack
            local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,8); corner.Parent = b
        else
            b.Text = label
            b.LayoutOrder = order or b.LayoutOrder
            b.Visible = false
        end
        return b
    end

    local stopBtn = makeEdgeBtn("TPStopEdge", "STOP", 10)

    local RUNNING = false
    local abort = false
    local orb = nil

    local function cleanup()
        RUNNING = false
        abort = false
        if stopBtn then stopBtn.Visible = false end
        if orb then orb:Destroy(); orb = nil end
    end

    stopBtn.MouseButton1Click:Connect(function()
        abort = true
        if stopBtn then stopBtn.Visible = false end
        if orb then orb:Destroy(); orb = nil end
    end)

    local function cycle()
        RUNNING = true
        abort = false
        stopBtn.Visible = true
        local campPos = campOrbPos()
        if not campPos then cleanup(); return end
        orb = makeOrb(campPos)

        while not abort do
            local t = nearestTree(600)
            if not t then break end
            landByTree(t)
            if abort then break end
            chopTree(t)
            if abort then break end

            local logs = collectNearbyLogs( (mainPart(t) and mainPart(t).Position) or hrp().Position, 40 )
            for i=1,#logs do
                if abort then break end
                local m = logs[i]
                if m and m.Parent then
                    dropAt(m, CFrame.new(campPos + Vector3.new(0, 0.6, 0)))
                    Run.Heartbeat:Wait()
                end
            end
            Run.Heartbeat:Wait()
        end
        cleanup()
    end

    tab:Section({ Title = "TP Bring" })
    tab:Button({
        Title = "Get Logs (TP)",
        Callback = function()
            if RUNNING then return end
            task.spawn(cycle)
        end
    })

    Players.LocalPlayer.CharacterAdded:Connect(function()
        if edgeGui and edgeGui.Parent ~= playerGui then edgeGui.Parent = playerGui end
        if RUNNING then stopBtn.Visible = true end
    end)
end
