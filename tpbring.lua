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
    local function getAllParts(m)
        local t = {}
        if not m then return t end
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then t[#t+1] = d end
        end
        return t
    end
    local function bboxHeight(m)
        if m and m:IsA("Model") then
            local s = m:GetExtentsSize()
            return s.Y
        end
        local p = mainPart(m)
        return p and p.Size.Y or 2
    end
    local function zeroAssembly(m)
        for _,p in ipairs(getAllParts(m)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
    end
    local function setCollide(m, on, snap)
        if on and snap then
            for part,can in pairs(snap) do if part and part.Parent then part.CanCollide = can end end
            return
        end
        local s = {}
        for _,p in ipairs(getAllParts(m)) do s[p]=p.CanCollide; p.CanCollide=false end
        return s
    end
    local function setPivot(m, cf)
        if m:IsA("Model") then m:PivotTo(cf) else local p=mainPart(m); if p then p.CFrame = cf end end
    end

    local startDrag, stopDrag = nil, nil
    do
        local re = RS:FindFirstChild("RemoteEvents")
        if re then
            startDrag = re:FindFirstChild("RequestStartDraggingItem")
            stopDrag  = re:FindFirstChild("StopDraggingItem")
        end
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

    local STOP_BTN = makeEdgeBtn("TPBringStop", "STOP", 50)

    local ORB_OFFSET_Y        = 12
    local ORB_AHEAD           = 4
    local PICK_RADIUS         = 50
    local CONVEYOR_MAX_ACTIVE = 10
    local START_STAGGER       = 0.15
    local STEP_WAIT           = 0.03
    local DRAG_SPEED          = 18
    local VERTICAL_MULT       = 1.35
    local ORB_JITTER_CLEAR    = 0.25

    local INFLT_ATTR = "OrbInFlightAt"
    local JOB_ATTR   = "OrbJob"
    local DELIVER_ATTR = "DeliveredAtOrb"

    local running  = false
    local hb       = nil
    local orb      = nil

    local function ensureOrb()
        if orb and orb.Parent then return orb end
        local o = Instance.new("Part")
        o.Name = "tp_orb"
        o.Shape = Enum.PartType.Ball
        o.Size = Vector3.new(1.5,1.5,1.5)
        o.Material = Enum.Material.Neon
        o.Color = Color3.fromRGB(80,180,255)
        o.Anchored, o.CanCollide, o.CanTouch, o.CanQuery = true,false,false,false
        o.Parent = WS
        local l = Instance.new("PointLight"); l.Range = 16; l.Brightness = 2.5; l.Parent = o
        orb = o
        return o
    end
    local function updateOrb()
        local o = ensureOrb(); local r = hrp(); if not (o and r) then return end
        local pos = r.Position + r.CFrame.LookVector*ORB_AHEAD + Vector3.new(0, ORB_OFFSET_Y, 0)
        o.CFrame = CFrame.new(pos)
    end
    local function orbPos()
        return (orb and orb.Parent) and orb.Position or nil
    end
    local function destroyOrb() if orb then pcall(function() orb:Destroy() end) orb=nil end end

    local function itemsRoot() return WS:FindFirstChild("Items") end
    local function isLog(m)
        if not (m and m:IsA("Model")) then return false end
        local n = (m.Name or "")
        return n=="Log" or n=="TreeLog" or n=="Wood Log" or (n:match("^Log%d+$") ~= nil)
    end
    local function canPick(m, center, radius, jobId)
        if not (m and m.Parent and m:IsA("Model")) then return false end
        if not isLog(m) then return false end
        local mp = mainPart(m); if not mp then return false end
        local del = m:GetAttribute(DELIVER_ATTR)
        if del and tostring(del) == tostring(jobId) then return false end
        local tIn = m:GetAttribute(INFLT_ATTR)
        local jIn = m:GetAttribute(JOB_ATTR)
        if tIn then
            if jIn and tostring(jIn) ~= tostring(jobId) then
                if os.clock() - tIn < 6.0 then return false else pcall(function() m:SetAttribute(INFLT_ATTR,nil) m:SetAttribute(JOB_ATTR,nil) end) end
            elseif os.clock() - tIn < 6.0 then
                return false
            else
                pcall(function() m:SetAttribute(INFLT_ATTR,nil) m:SetAttribute(JOB_ATTR,nil) end)
            end
        end
        return (mp.Position - center).Magnitude <= radius
    end
    local function getCandidates(center, radius, jobId)
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(center, radius, params) or {}
        local uniq, out = {}, {}
        for _,p in ipairs(parts) do
            local m = p:FindFirstAncestorOfClass("Model")
            if m and not uniq[m] and canPick(m, center, radius, jobId) then uniq[m]=true; out[#out+1]=m end
        end
        return out
    end

    local function moveVerticalToY(m, targetY, lookDir, keepNoCollide)
        local snap = keepNoCollide and nil or setCollide(m, false)
        zeroAssembly(m)
        while running and m and m.Parent do
            local pivot = m:IsA("Model") and m:GetPivot() or (mainPart(m) and mainPart(m).CFrame)
            if not pivot then break end
            local pos = pivot.Position
            local dy = targetY - pos.Y
            if math.abs(dy) <= 0.4 then break end
            local stepY = math.sign(dy) * math.min(DRAG_SPEED * VERTICAL_MULT * STEP_WAIT, math.abs(dy))
            local newPos = Vector3.new(pos.X, pos.Y + stepY, pos.Z)
            setPivot(m, CFrame.new(newPos, newPos + (lookDir or Vector3.zAxis)))
            zeroAssembly(m)
            task.wait(STEP_WAIT)
        end
        if not keepNoCollide then setCollide(m, true, snap) end
    end
    local function moveHorizontalToXZ(m, destXZ, yFixed, keepNoCollide)
        local snap = keepNoCollide and nil or setCollide(m, false)
        zeroAssembly(m)
        while running and m and m.Parent do
            local pivot = m:IsA("Model") and m:GetPivot() or (mainPart(m) and mainPart(m).CFrame)
            if not pivot then break end
            local pos = pivot.Position
            local delta = Vector3.new(destXZ.X - pos.X, 0, destXZ.Z - pos.Z)
            local dist = delta.Magnitude
            if dist <= 1.0 then break end
            local step = math.min(DRAG_SPEED * STEP_WAIT, dist)
            local dir = delta.Unit
            local newPos = Vector3.new(pos.X, yFixed or pos.Y, pos.Z) + dir * step
            setPivot(m, CFrame.new(newPos, newPos + dir))
            zeroAssembly(m)
            task.wait(STEP_WAIT)
        end
        if not keepNoCollide then setCollide(m, true, snap) end
    end
    local function dropFromOrbClean(m, oPos, jobId, origSnap, H)
        zeroAssembly(m)
        local above = oPos + Vector3.new(0, math.max(0.5, H * 0.25), 0)
        setPivot(m, CFrame.new(above))
        for _,p in ipairs(getAllParts(m)) do
            p.Anchored = false
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
        end
        setCollide(m, true, origSnap)
        pcall(function()
            m:SetAttribute(INFLT_ATTR, nil)
            m:SetAttribute(JOB_ATTR, nil)
            m:SetAttribute(DELIVER_ATTR, tostring(jobId))
        end)
        task.delay(ORB_JITTER_CLEAR, function()
            if m and m.Parent then zeroAssembly(m) end
        end)
    end

    local function startConveyor(m, oPos, jobId)
        if not running or not m or not m.Parent or not oPos then return end
        pcall(function() m:SetAttribute(INFLT_ATTR, os.clock()) m:SetAttribute(JOB_ATTR, tostring(jobId)) end)
        local mp = mainPart(m); if not mp then return end
        local H = bboxHeight(m)
        local riserY = oPos.Y - 1.0 + math.clamp(H * 0.45, 0.8, 3.0)
        local lookDir = (Vector3.new(oPos.X, mp.Position.Y, oPos.Z) - mp.Position)
        lookDir = (lookDir.Magnitude > 0.001) and lookDir.Unit or Vector3.zAxis

        local snapOrig = setCollide(m, false)
        zeroAssembly(m)

        if startDrag then pcall(function() startDrag:FireServer(m) end) end
        moveVerticalToY(m, riserY, lookDir, true)
        moveHorizontalToXZ(m, Vector3.new(oPos.X, 0, oPos.Z), riserY, true)
        if stopDrag then pcall(function() stopDrag:FireServer(m) end) end

        dropFromOrbClean(m, oPos, jobId, snapOrig, H)
    end

    local function runConveyorWave(centerPos, oPos, jobId)
        local picked = getCandidates(centerPos, PICK_RADIUS, jobId)
        if #picked == 0 then return 0 end
        local active = 0
        local function spawnOne(m)
            if not running then return end
            if m and m.Parent then
                active += 1
                task.spawn(function()
                    startConveyor(m, oPos, jobId)
                    active -= 1
                end)
            end
        end
        for i=1,#picked do
            if not running then break end
            while running and active >= CONVEYOR_MAX_ACTIVE do Run.Heartbeat:Wait() end
            spawnOne(picked[i])
            task.wait(START_STAGGER)
        end
        local deadline = os.clock() + math.max(5, START_STAGGER * #picked + 5)
        while running and active > 0 and os.clock() < deadline do Run.Heartbeat:Wait() end
        return #picked
    end

    local function stopAll()
        running = false
        if hb then hb:Disconnect(); hb=nil end
        STOP_BTN.Visible = false
        destroyOrb()
    end
    STOP_BTN.MouseButton1Click:Connect(stopAll)

    local function startAll()
        if running then return end
        running = true
        STOP_BTN.Visible = true
        if hb then hb:Disconnect() end
        hb = Run.Heartbeat:Connect(function()
            if not running then return end
            local r = hrp(); if not r then return end
            updateOrb()
            local oP = orbPos(); if not oP then return end
            local jobId = ("%d-%d"):format(os.time(), math.random(1,1e6))
            runConveyorWave(r.Position, oP, jobId)
        end)
    end

    tab:Button({
        Title = "Get Logs",
        Callback = function()
            if running then return end
            startAll()
        end
    })

    Players.LocalPlayer.CharacterAdded:Connect(function()
        if running then
            ensureOrb()
            STOP_BTN.Visible = true
        end
    end)
end
