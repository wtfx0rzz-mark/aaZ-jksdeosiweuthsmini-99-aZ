-- tpbring.lua
return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")

    local lp  = Players.LocalPlayer
    local tab = UI and UI.Tabs and (UI.Tabs.TPBring or UI.Tabs.Bring or UI.Tabs.Auto or UI.Tabs.Main)

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end
    local function mainPart(m)
        if not (m and m:IsA("Model")) then return nil end
        return m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
    end
    local function allParts(m)
        local t = {}
        if not m then return t end
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then t[#t+1] = d end
        end
        return t
    end
    local function setPivot(m, cf)
        if m:IsA("Model") then m:PivotTo(cf) else local p=mainPart(m); if p then p.CFrame = cf end end
    end
    local function zeroAssembly(m)
        for _,p in ipairs(allParts(m)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
    end
    local function snapshotCollide(m)
        local s = {}
        for _,p in ipairs(allParts(m)) do s[p] = p.CanCollide end
        return s
    end
    local function setCollideFromSnapshot(snap)
        for part,can in pairs(snap or {}) do
            if part and part.Parent then part.CanCollide = can end
        end
    end
    local function setAnchored(m, on)
        for _,p in ipairs(allParts(m)) do p.Anchored = on end
    end
    local function setNoCollide(m)
        local s = {}
        for _,p in ipairs(allParts(m)) do s[p]=p.CanCollide; p.CanCollide=false end
        return s
    end

    local startDrag, stopDrag = nil, nil
    do
        local re = RS:FindFirstChild("RemoteEvents")
        if re then
            startDrag = re:FindFirstChild("RequestStartDraggingItem")
            stopDrag  = re:FindFirstChild("StopDraggingItem")
        end
    end

    local function groundBelow(pos)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local start = pos + Vector3.new(0, 200, 0)
        local hit = WS:Raycast(start, Vector3.new(0, -1000, 0), params)
        return (hit and hit.Position) or pos
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
            b.Text = label; b.LayoutOrder = order or b.LayoutOrder; b.Visible = false
        end
        return b
    end

    local STOP_BTN = makeEdgeBtn("TPBringStop", "STOP", 50)

    local DRAG_SPEED    = 36
    local PICK_RADIUS   = 50
    local ORB_HEIGHT    = 20
    local MAX_CONCURRENT= 12
    local START_STAGGER = 0.05

    local LAND_MIN   = 1.2
    local LAND_MAX   = 3.0
    local ARRIVE_EPS_H = 1.25
    local STALL_SEC    = 0.6

    local INFLT_ATTR = "OrbInFlightAt"
    local JOB_ATTR   = "OrbJob"

    local running   = false
    local hb        = nil
    local orb       = nil
    local orbPosVec = nil

    local inflight = {}
    local activeCount = 0

    local function spawnOrbAt(pos)
        if orb then pcall(function() orb:Destroy() end) end
        local o = Instance.new("Part")
        o.Name = "tp_orb_fixed"
        o.Shape = Enum.PartType.Ball
        o.Size = Vector3.new(1.5,1.5,1.5)
        o.Material = Enum.Material.Neon
        o.Color = Color3.fromRGB(80,180,255)
        o.Anchored, o.CanCollide, o.CanTouch, o.CanQuery = true,false,false,false
        o.CFrame = CFrame.new(pos + Vector3.new(0, ORB_HEIGHT, 0))
        o.Parent = WS
        local l = Instance.new("PointLight"); l.Range = 16; l.Brightness = 2.5; l.Parent = o
        orb = o
        orbPosVec = orb.Position
    end
    local function destroyOrb()
        if orb then pcall(function() orb:Destroy() end) orb=nil end
        orbPosVec = nil
    end

    local function isLogModel(m)
        if not (m and m:IsA("Model")) then return false end
        local n = (m.Name or "")
        return n=="Log" or n=="TreeLog" or n=="Wood Log" or (n:match("^Log%d+$") ~= nil)
    end

    local function nearbyCandidates(center, radius, jobId)
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(center, radius, params) or {}
        local uniq, out = {}, {}
        for _,p in ipairs(parts) do
            local m = p:FindFirstAncestorOfClass("Model")
            if m and not uniq[m] and isLogModel(m) and m.Parent and not inflight[m] then
                local tIn = m:GetAttribute(INFLT_ATTR)
                local jIn = m:GetAttribute(JOB_ATTR)
                if tIn and jIn and tostring(jIn) ~= jobId and os.clock() - tIn < 6.0 then
                else
                    uniq[m]=true; out[#out+1]=m
                end
            end
        end
        return out
    end

    local function dropToGroundAt(m, aroundPos)
        if not (m and m.Parent) then return end
        local g = groundBelow(aroundPos or (mainPart(m) and mainPart(m).Position) or Vector3.new())
        local pos = Vector3.new(g.X, g.Y + 1.25, g.Z)
        setPivot(m, CFrame.new(pos))
        zeroAssembly(m)
        setAnchored(m, false)
    end

    local function restoreModelState(m)
        local rec = inflight[m]; if not rec then return end
        if rec.conn then rec.conn:Disconnect() end
        if stopDrag then pcall(function() stopDrag:FireServer(m) end) end
        setAnchored(m, false)
        setCollideFromSnapshot(rec.snap)
        pcall(function() m:SetAttribute(INFLT_ATTR, nil); m:SetAttribute(JOB_ATTR, nil) end)
        inflight[m] = nil
    end

    local bxor = bit32 and bit32.bxor or function(a,b)
        local res, bit, p = 0, 1, 0
        while a > 0 or b > 0 do
            local aa = a % 2
            local bb = b % 2
            if (aa + bb) == 1 then res = res + bit end
            a = (a - aa) / 2
            b = (b - bb) / 2
            bit = bit * 2
            p = p + 1
            if p > 32 then break end
        end
        return res
    end
    local function hash01(str)
        local h = 2166136261
        for i=1,#str do
            h = (bxor(h, string.byte(str,i)) * 16777619) % 2^32
        end
        return (h % 100000) / 100000
    end
    local function landingOffset(m, jobId)
        local key = (typeof(m.GetDebugId)=="function" and m:GetDebugId() or (m.Name or "")) .. tostring(jobId)
        local r1 = hash01(key .. "a")
        local r2 = hash01(key .. "b")
        local ang = r1 * math.pi * 2
        local rad = LAND_MIN + (LAND_MAX - LAND_MIN) * r2
        return Vector3.new(math.cos(ang)*rad, 0, math.sin(ang)*rad)
    end

    local function startConveyor(m, jobId)
        if not (running and m and m.Parent and orbPosVec) then return end
        local mp = mainPart(m); if not mp then return end

        local off = landingOffset(m, jobId)
        local function target()
            return (orbPosVec or mp.Position) + off
        end

        pcall(function() m:SetAttribute(INFLT_ATTR, os.clock()) end)
        pcall(function() m:SetAttribute(JOB_ATTR, jobId) end)

        local snap = setNoCollide(m)
        setAnchored(m, true)
        zeroAssembly(m)
        if startDrag then pcall(function() startDrag:FireServer(m) end) end

        local rec = { snap = snap, conn = nil, lastD = math.huge, lastT = os.clock() }
        inflight[m] = rec

        rec.conn = Run.Heartbeat:Connect(function(dt)
            if not (running and m and m.Parent and orbPosVec) then
                restoreModelState(m)
                dropToGroundAt(m)
                activeCount = math.max(0, activeCount-1)
                return
            end

            local pivot = m:IsA("Model") and m:GetPivot() or (mp and mp.CFrame)
            if not pivot then
                restoreModelState(m)
                activeCount = math.max(0, activeCount-1)
                return
            end

            local pos = pivot.Position
            local tgt = target()
            local delta = Vector3.new(tgt.X - pos.X, 0, tgt.Z - pos.Z)
            local distH = delta.Magnitude

            if distH <= ARRIVE_EPS_H then
                if stopDrag then pcall(function() stopDrag:FireServer(m) end) end
                setAnchored(m, false)
                setCollideFromSnapshot(snap)
                dropToGroundAt(m, tgt)
                pcall(function() m:SetAttribute(INFLT_ATTR, nil); m:SetAttribute(JOB_ATTR, nil) end)
                if rec.conn then rec.conn:Disconnect() end
                inflight[m] = nil
                activeCount = math.max(0, activeCount-1)
                return
            end

            if distH >= rec.lastD - 0.02 then
                if os.clock() - rec.lastT >= STALL_SEC then
                    off = landingOffset(m, tostring(jobId) .. tostring(os.clock()))
                    rec.lastT = os.clock()
                end
            else
                rec.lastT = os.clock()
            end
            rec.lastD = distH

            local step = math.min(DRAG_SPEED * dt, distH)
            local dir  = distH > 1e-3 and (delta / distH) or Vector3.new()
            local newPos = pos + dir * step
            local look = dir.Magnitude > 0 and dir or Vector3.new(0,0,1)
            setPivot(m, CFrame.new(newPos, newPos + look))
        end)
    end

    local function wave(center)
        local jobId = tostring(os.clock())
        local list = nearbyCandidates(center, PICK_RADIUS, jobId)
        for i=1,#list do
            if not running then break end
            while running and activeCount >= MAX_CONCURRENT do Run.Heartbeat:Wait() end
            local m = list[i]
            if m and m.Parent and not inflight[m] then
                activeCount += 1
                task.spawn(function()
                    startConveyor(m, jobId)
                end)
                task.wait(START_STAGGER)
            end
        end
    end

    local function stopAll()
        running = false
        if hb then hb:Disconnect(); hb=nil end
        STOP_BTN.Visible = false
        for m,rec in pairs(inflight) do
            if rec and rec.conn then rec.conn:Disconnect() end
            if stopDrag then pcall(function() stopDrag:FireServer(m) end) end
            setAnchored(m, false)
            setCollideFromSnapshot(rec and rec.snap or snapshotCollide(m))
            dropToGroundAt(m)
            pcall(function() m:SetAttribute(INFLT_ATTR, nil); m:SetAttribute(JOB_ATTR, nil) end)
            inflight[m] = nil
        end
        activeCount = 0
        destroyOrb()
    end

    STOP_BTN.MouseButton1Click:Connect(stopAll)

    local function startAll()
        if running then return end
        local r = hrp(); if not r then return end
        spawnOrbAt(r.Position)
        running = true
        STOP_BTN.Visible = true
        if hb then hb:Disconnect() end
        hb = Run.Heartbeat:Connect(function()
            if not running then return end
            local root = hrp(); if not root then return end
            wave(root.Position)
        end)
    end

    if tab then
        tab:Button({
            Title = "Get Logs",
            Callback = function()
                if running then return end
                startAll()
            end
        })
    end

    Players.LocalPlayer.CharacterAdded:Connect(function()
        if running and orb and not orb.Parent then
            destroyOrb()
            local r = hrp()
            if r then spawnOrbAt(r.Position) end
        end
    end)
end
