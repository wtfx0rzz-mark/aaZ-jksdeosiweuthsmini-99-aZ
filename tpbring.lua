-- tpbring.lua
return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")

    local lp = Players.LocalPlayer
    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.TPBring
    assert(tab, "TPBring tab missing")

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end
    local function mainPart(m)
        if not (m and m:IsA("Model")) then return nil end
        return m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
    end
    local function zeroVel(p)
        if not p then return end
        p.AssemblyLinearVelocity  = Vector3.new()
        p.AssemblyAngularVelocity = Vector3.new()
    end
    local function setModelCollide(m, on, snap)
        if not m then return end
        if on and snap then
            for part,can in pairs(snap) do
                if part and part.Parent then part.CanCollide = can end
            end
            return
        end
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then d.CanCollide = false end
        end
    end
    local function snapCollide(m)
        local t = {}
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then t[d] = d.CanCollide end
        end
        return t
    end

    local startDrag, stopDrag
    do
        local f = RS:FindFirstChild("RemoteEvents")
        startDrag = f and f:FindChild("RequestStartDraggingItem") or f and f:FindFirstChild("RequestStartDraggingItem")
        stopDrag  = f and f:FindChild("StopDraggingItem")         or f and f:FindFirstChild("StopDraggingItem")
    end

    local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
    local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
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
            b.Visible = false
            b.LayoutOrder = order or 1
            b.Parent = stack
            local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,8); corner.Parent = b
        else
            b.Text = label
            b.LayoutOrder = order or b.LayoutOrder
            b.Visible = false
        end
        return b
    end

    local STOP_BTN   = makeEdgeBtn("TpBringStop", "STOP", 50)
    local running    = false
    local orb        = nil
    local hb         = nil

    local ORB_AHEAD      = 6
    local ORB_HEIGHT     = 12
    local ORB_SIZE       = 2
    local SCAN_RADIUS    = 50
    local STEP_INTERVAL  = 0.05
    local ARRIVE_DIST    = 2.2
    local LIFT_OVER_ORB  = 2.5
    local RESEEN_COOLDWN = 1.0

    local seenAt = setmetatable({}, {__mode="k"})

    local function ensureOrb()
        if orb and orb.Parent then return orb end
        local root = hrp(); if not root then return nil end
        local pos  = root.Position + root.CFrame.LookVector*ORB_AHEAD + Vector3.new(0, ORB_HEIGHT, 0)
        local p = Instance.new("Part")
        p.Name = "TP_Orb"
        p.Shape = Enum.PartType.Ball
        p.Material = Enum.Material.Neon
        p.Color = Color3.fromRGB(80,180,255)
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.Size = Vector3.new(ORB_SIZE, ORB_SIZE, ORB_SIZE)
        p.CFrame = CFrame.new(pos)
        p.Parent = WS
        orb = p
        return p
    end
    local function orbPos()
        local o = ensureOrb()
        return o and o.Position or nil
    end
    local function destroyOrb()
        if orb then pcall(function() orb:Destroy() end) end
        orb = nil
    end

    local function isLog(m)
        if not (m and m:IsA("Model")) then return false end
        local n = tostring(m.Name)
        if n == "Log" or n == "TreeLog" or n == "Wood Log" then return true end
        if n:match("Log%d+$") then return true end
        return false
    end
    local function itemsFolder()
        return WS:FindFirstChild("Items")
    end
    local function collectNearbyLogs(center)
        local out = {}
        local items = itemsFolder(); if not (items and center) then return out end
        local now = os.clock()
        for _,m in ipairs(items:GetChildren()) do
            if isLog(m) then
                local mp = mainPart(m)
                if mp and (mp.Position - center).Magnitude <= SCAN_RADIUS then
                    local t = seenAt[m]
                    if not t or (now - t) > RESEEN_COOLDWN then
                        out[#out+1] = m
                        seenAt[m] = now
                    end
                end
            end
        end
        return out
    end

    local function dragOnce(m)
        local o = orbPos(); if not (m and m.Parent and o) then return end
        local mp = mainPart(m); if not mp then return end

        local snap = snapCollide(m)
        setModelCollide(m, false)

        if startDrag then pcall(function() startDrag:FireServer(m) end) end
        Run.Heartbeat:Wait()

        local destAbove = CFrame.new(o + Vector3.new(0, LIFT_OVER_ORB, 0))
        pcall(function()
            if m:IsA("Model") then m:PivotTo(destAbove)
            else local p = mainPart(m); if p then p.CFrame = destAbove end end
        end)

        Run.Heartbeat:Wait()

        local close = (mainPart(m).Position - o).Magnitude <= ARRIVE_DIST
        if stopDrag then pcall(function() stopDrag:FireServer(m) end) end

        local p = mainPart(m)
        if p then zeroVel(p) end
        setModelCollide(m, true, snap)

        if close then
            pcall(function()
                if m:IsA("Model") then m:PivotTo(CFrame.new(o + Vector3.new(0, 0.01, 0)))
                else local pr = mainPart(m); if pr then pr.CFrame = CFrame.new(o + Vector3.new(0, 0.01, 0)) end end
            end)
            local pr = mainPart(m)
            if pr then zeroVel(pr) end
        end
    end

    local function tickCycle()
        local root = hrp(); if not root then return end
        ensureOrb()
        local logs = collectNearbyLogs(root.Position)
        for i=1,#logs do
            if not running then return end
            if logs[i] and logs[i].Parent then dragOnce(logs[i]) end
            task.wait(STEP_INTERVAL)
        end
    end

    local function stop()
        running = false
        if hb then hb:Disconnect(); hb = nil end
        STOP_BTN.Visible = false
        destroyOrb()
    end
    STOP_BTN.MouseButton1Click:Connect(stop)

    local function start()
        if running then return end
        running = true
        ensureOrb()
        STOP_BTN.Visible = true
        if hb then hb:Disconnect() end
        hb = Run.Heartbeat:Connect(function()
            if running then tickCycle() end
        end)
    end

    tab:Button({
        Title = "Get Logs",
        Callback = function()
            if running then return end
            start()
        end
    })

    Players.LocalPlayer.CharacterAdded:Connect(function()
        if running then
            ensureOrb()
            STOP_BTN.Visible = true
        end
    end)
end
