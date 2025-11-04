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
    local function zeroAssembly(root)
        if not root then return end
        root.AssemblyLinearVelocity  = Vector3.new()
        root.AssemblyAngularVelocity = Vector3.new()
    end

    local startDrag = nil
    local stopDrag  = nil
    do
        local f = RS:FindFirstChild("RemoteEvents")
        startDrag = f and f:FindFirstChild("RequestStartDraggingItem")
        stopDrag  = f and f:FindFirstChild("StopDraggingItem")
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

    local running = false
    local orbPart = nil
    local hbConn  = nil
    local stopBtn = makeEdgeBtn("TpBringStop", "STOP", 50)

    local ORB_OFFSET_AHEAD = 6
    local ORB_HEIGHT       = 12
    local CYCLE_INTERVAL   = 0.05
    local SCAN_RADIUS      = 80
    local LIFT_OFFSET_Y    = 2.5

    local function ensureOrb()
        if orbPart and orbPart.Parent then return orbPart end
        local root = hrp(); if not root then return nil end
        local pos  = root.Position + root.CFrame.LookVector*ORB_OFFSET_AHEAD + Vector3.new(0, ORB_HEIGHT, 0)
        local p = Instance.new("Part")
        p.Name = "TP_Orb"
        p.Shape = Enum.PartType.Ball
        p.Material = Enum.Material.Neon
        p.Color = Color3.fromRGB(80,180,255)
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.Size = Vector3.new(2,2,2)
        p.CFrame = CFrame.new(pos)
        p.Parent = WS
        orbPart = p
        return p
    end
    local function orbPos()
        local o = ensureOrb()
        return o and o.Position or nil
    end
    local function destroyOrb()
        if orbPart then pcall(function() orbPart:Destroy() end) end
        orbPart = nil
    end

    local function isLogModel(m)
        if not (m and m:IsA("Model")) then return false end
        local n = tostring(m.Name)
        if n == "Log" or n == "TreeLog" or n == "Wood Log" then return true end
        if n:match("Log%d+$") then return true end
        return false
    end
    local function itemsFolder()
        return WS:FindFirstChild("Items")
    end
    local function nearbyLogs(center, r)
        local out = {}
        local items = itemsFolder(); if not (items and center) then return out end
        for _,m in ipairs(items:GetChildren()) do
            if isLogModel(m) then
                local mp = mainPart(m)
                if mp and (mp.Position - center).Magnitude <= r then
                    out[#out+1] = m
                end
            end
        end
        return out
    end

    local function dragToOrb(m, target)
        if not (m and m.Parent and target) then return end
        if startDrag then pcall(function() startDrag:FireServer(m) end) end
        Run.Heartbeat:Wait()
        local lift = CFrame.new(target + Vector3.new(0, LIFT_OFFSET_Y, 0))
        pcall(function()
            if m:IsA("Model") then m:PivotTo(lift)
            else local p = mainPart(m); if p then p.CFrame = lift end end
        end)
        local root = hrp(); if root then zeroAssembly(root) end
        Run.Heartbeat:Wait()
        if stopDrag then pcall(function() stopDrag:FireServer(m) end) end
    end

    local function cycle()
        local oPos = orbPos(); if not oPos then return end
        local root = hrp(); if not root then return end
        local logs = nearbyLogs(root.Position, SCAN_RADIUS)
        for i=1,#logs do
            if not running then return end
            local m = logs[i]
            if m and m.Parent then
                dragToOrb(m, oPos)
            end
            task.wait(CYCLE_INTERVAL)
        end
    end

    local function stop()
        running = false
        if hbConn then hbConn:Disconnect(); hbConn = nil end
        stopBtn.Visible = false
        destroyOrb()
    end

    stopBtn.MouseButton1Click:Connect(stop)

    local function start()
        if running then return end
        running = true
        ensureOrb()
        stopBtn.Visible = true
        if hbConn then hbConn:Disconnect() end
        hbConn = Run.Heartbeat:Connect(function()
            if not running then return end
            cycle()
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
        if stopBtn and running then stopBtn.Visible = true end
        if running then ensureOrb() end
    end)
end
