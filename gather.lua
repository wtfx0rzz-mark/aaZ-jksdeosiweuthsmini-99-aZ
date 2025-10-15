--=====================================================
-- 1337 Nights | Gather Module (dynamic baseline + auto toggle-off)
--=====================================================
return function(C, R, UI)
    -----------------------------------------------------
    -- Services
    -----------------------------------------------------
    local Players = (C and C.Services and C.Services.Players) or game:GetService("Players")
    local RS      = (C and C.Services and C.Services.RS)      or game:GetService("ReplicatedStorage")
    local WS      = (C and C.Services and C.Services.WS)      or game:GetService("Workspace")
    local Run     = game:GetService("RunService")

    -----------------------------------------------------
    -- Tab
    -----------------------------------------------------
    local Tabs = (UI and UI.Tabs) or {}
    local tab  = Tabs.Gather
    if not tab then
        local Window = UI and UI.Window
        if Window and Window.Tab then
            tab = Window:Tab({ Title = "Gather", Icon = "package", Desc = "Collect and place resources" })
            Tabs.Gather = tab
        else
            warn("[Gather] UI.Tabs.Gather not found and cannot create tab")
            return
        end
    end

    -----------------------------------------------------
    -- Tunables
    -----------------------------------------------------
    local MAX_CARRY       = 50
    local DEFAULT_RADIUS  = 80
    local DEFAULT_DEPTH   = 35
    local SCAN_INTERVAL   = 0.25
    local STACK_COLS      = 10
    local STACK_H_GAP     = 0.35
    local STACK_V_GAP     = 0.15
    local TETHER_SPREAD   = 0.35
    local TETHER_RING     = 8

    -----------------------------------------------------
    -- Remotes
    -----------------------------------------------------
    local RemoteFolder = RS:FindFirstChild("RemoteEvents")
    local StartDrag    = RemoteFolder and RemoteFolder:FindFirstChild("RequestStartDraggingItem")
    local StopDrag     = RemoteFolder and RemoteFolder:FindFirstChild("StopDraggingItem")

    -----------------------------------------------------
    -- State
    -----------------------------------------------------
    local lp  = Players.LocalPlayer
    local carried, carryList, carryCount = {}, {}, 0
    local gatherEnabled, scanningOn, tetherOn = false, false, false
    local resourceType = "Logs"
    local carryRadius, carryDepth = DEFAULT_RADIUS, DEFAULT_DEPTH
    local rsConn, scanThreadRunning, gatherToggleHandle

    -----------------------------------------------------
    -- Helpers
    -----------------------------------------------------
    local function hrp()
        local ch = lp and (lp.Character or lp.CharacterAdded:Wait())
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    local function clamp(v, lo, hi)
        v = tonumber(v) or lo
        return math.clamp(v, lo, hi)
    end

    local function mainPart(m)
        if not m then return nil end
        if m:IsA("Model") then return m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
        elseif m:IsA("BasePart") then return m end
        return nil
    end

    local function ensurePrimary(m)
        if m and m:IsA("Model") and not m.PrimaryPart then
            local p = m:FindFirstChildWhichIsA("BasePart")
            if p then m.PrimaryPart = p end
        end
    end

    local function groundYAt(pos)
        local rc = WS:Raycast(pos + Vector3.new(0, 100, 0), Vector3.new(0, -300, 0))
        return rc and rc.Position.Y or pos.Y
    end

    local function belowMapCFrameWithOffset(i)
        local root = hrp(); if not root then return nil end
        local groundY = groundYAt(root.Position)
        local basePos = Vector3.new(root.Position.X, groundY - carryDepth, root.Position.Z)

        local ring = math.floor((i-1) / TETHER_RING)
        local idx  = (i-1) % TETHER_RING
        local angle = (idx / TETHER_RING) * math.pi * 2
        local radius = (ring+1) * TETHER_SPREAD
        local offset = Vector3.new(math.cos(angle)*radius, 0, math.sin(angle)*radius)

        local pos = basePos + offset
        return CFrame.new(pos, pos + root.CFrame.LookVector)
    end

    local function matchesResource(name)
        local n = string.lower(name or "")
        if resourceType == "Logs"    then return n:find("log") ~= nil end
        if resourceType == "Stone"   then return n:find("stone") or n:find("rock") end
        if resourceType == "Berries" then return n:find("berry") ~= nil end
        return false
    end

    local function blacklist(m)
        local n = string.lower(m.Name or "")
        return n:find("trader") or n:find("shopkeeper") or n:find("campfire")
    end

    local function toList(t)
        local out = {}
        for k in pairs(t) do out[#out+1] = k end
        return out
    end

    local function addCarry(m)
        if carried[m] or carryCount >= MAX_CARRY then return false end
        carried[m] = true
        carryCount += 1
        carryList = toList(carried)
        return true
    end

    local function removeCarry(m)
        if not carried[m] then return end
        carried[m] = nil
        carryCount -= 1
        if carryCount < 0 then carryCount = 0 end
        carryList = toList(carried)
    end

    local function setNoCollide(m, on)
        local parts = m:IsA("Model") and m:GetDescendants() or {m}
        for _,d in ipairs(parts) do
            if d:IsA("BasePart") then
                d.CanCollide = not on
                d.Anchored = false
                if typeof(d.SetNetworkOwner) == "function" then
                    pcall(function() d:SetNetworkOwner(lp) end)
                end
            end
        end
    end

    local function hideLocal(m)
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then
                d.LocalTransparencyModifier = 1
                d.CastShadow = false
            end
        end
    end

    local function showLocal(m)
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then
                d.LocalTransparencyModifier = 0
                d.CastShadow = true
            end
        end
    end

    local function startDrag(m) if StartDrag and m then pcall(function() StartDrag:FireServer(m) end) end end
    local function stopDrag(m)  if StopDrag  and m then pcall(function() StopDrag:FireServer(m) end)  end end

    local function uiSetToggle(state)
        local h = gatherToggleHandle
        if not h then return end
        pcall(function() if h.SetValue then h:SetValue(state) end end)
        pcall(function() if h.SetState then h:SetState(state) end end)
        pcall(function() if h.Value ~= nil then h.Value = state end end)
    end

    -----------------------------------------------------
    -- Tether + Scanner
    -----------------------------------------------------
    local function startTether()
        if tetherOn then return end
        tetherOn = true
        if rsConn then rsConn:Disconnect() end
        rsConn = Run.RenderStepped:Connect(function()
            if not tetherOn then return end
            for i,m in ipairs(carryList) do
                local cf = belowMapCFrameWithOffset(i)
                local mp = mainPart(m)
                if m and mp and cf then
                    if m:IsA("Model") and m.PrimaryPart then
                        pcall(function() m:PivotTo(cf) end)
                    else
                        pcall(function() mp.CFrame = cf end)
                    end
                end
            end
        end)
    end

    local function stopTether()
        tetherOn = false
        if rsConn then rsConn:Disconnect(); rsConn = nil end
    end

    local function startScanner()
        if scanThreadRunning then return end
        scanThreadRunning, scanningOn = true, true
        task.spawn(function()
            while scanningOn do
                local items = WS:FindFirstChild("Items")
                local root = hrp()
                if not scanningOn then break end
                if items and root then
                    local origin = root.Position
                    for _,m in ipairs(items:GetChildren()) do
                        if not scanningOn or carryCount >= MAX_CARRY then break end
                        if m:IsA("Model") and not carried[m] and not blacklist(m) and matchesResource(m.Name) then
                            local mp = mainPart(m)
                            if mp and (mp.Position - origin).Magnitude <= carryRadius then
                                startDrag(m)
                                if addCarry(m) then
                                    setNoCollide(m,true)
                                    hideLocal(m)
                                end
                            end
                        end
                    end
                end
                task.wait(SCAN_INTERVAL)
            end
            scanThreadRunning = false
        end)
    end

    local function stopScanner()
        scanningOn = false
    end

    local function setEnabled(on)
        gatherEnabled = on
        if on then
            startTether()
            startScanner()
        else
            stopScanner()
            stopTether()
        end
    end

    -----------------------------------------------------
    -- Placement
    -----------------------------------------------------
    local function anchorModel(m, anchored)
        local parts = m:IsA("Model") and m:GetDescendants() or {m}
        for _,d in ipairs(parts) do
            if d:IsA("BasePart") then
                d.Anchored = anchored
                d.CanCollide = true
                d.AssemblyLinearVelocity  = Vector3.new()
                d.AssemblyAngularVelocity = Vector3.new()
            end
        end
    end

    local function avgSize(list)
        local s, n = Vector3.new(), 0
        for _,m in ipairs(list) do
            if m and m.Parent then
                local _, box = m:GetBoundingBox()
                s += box; n += 1
            end
        end
        return n>0 and (s/n) or Vector3.new(3,2.5,3)
    end

    local function placeLogStackSequential(list)
        local root = hrp(); if not root then return end
        local forward, right = root.CFrame.LookVector, root.CFrame.RightVector
        local basePos = root.Position + forward*5

        local s = avgSize(list)
        local logLength, logHeight = s.Z, s.Y
        local stepF = logLength + STACK_H_GAP
        local stepY = logHeight + STACK_V_GAP
        local halfCols = (STACK_COLS - 1) / 2

        for i,m in ipairs(list) do
            ensurePrimary(m); stopDrag(m); setNoCollide(m,false); showLocal(m)
            local col = i % STACK_COLS
            local row = math.floor(i / STACK_COLS)
            local lateral = (col - halfCols) * stepF
            local height = row * stepY
            local pos = basePos + forward * lateral + Vector3.new(0,height,0)
            local groundY = groundYAt(pos)
            pos = Vector3.new(pos.X, groundY + logHeight/2, pos.Z)
            local cf = CFrame.new(pos, pos + right)
            local mp = mainPart(m)
            if m:IsA("Model") and m.PrimaryPart then
                pcall(function() m:PivotTo(cf) end)
            elseif mp then
                pcall(function() mp.CFrame = cf end)
            end
            anchorModel(m,true)
            removeCarry(m)
            task.wait(0.01)
        end
    end

    local function placeOthersSequential(list)
        local root = hrp(); if not root then return end
        local forward, right = root.CFrame.LookVector, root.CFrame.RightVector
        local basePos = root.Position + forward*5
        local s = avgSize(list)
        local stepX, stepY = math.max(1,s.X*0.8), math.max(0.8,s.Y*0.8)
        local cols, halfCols = 6, 2.5

        for i,m in ipairs(list) do
            ensurePrimary(m); stopDrag(m); setNoCollide(m,false); showLocal(m)
            local col = i % cols
            local row = math.floor(i / cols)
            local pos = basePos + right*((col-halfCols)*stepX) + Vector3.new(0,row*stepY,0)
            local groundY = groundYAt(pos)
            pos = Vector3.new(pos.X, groundY + s.Y/2, pos.Z)
            local cf = CFrame.new(pos, pos + forward)
            local mp = mainPart(m)
            if m:IsA("Model") and m.PrimaryPart then
                pcall(function() m:PivotTo(cf) end)
            elseif mp then
                pcall(function() mp.CFrame = cf end)
            end
            anchorModel(m,true)
            removeCarry(m)
            task.wait(0.01)
        end
    end

    local function setItemsVisible()
        uiSetToggle(false)
        setEnabled(false)
        local snap = table.clone(carryList)
        if #snap == 0 then return end
        local logs, others = {}, {}
        for _,m in ipairs(snap) do
            local n = string.lower(m.Name or "")
            if n:find("log") then table.insert(logs,m) else table.insert(others,m) end
        end
        if #logs>0 then placeLogStackSequential(logs) end
        if #others>0 then placeOthersSequential(others) end
    end

    -----------------------------------------------------
    -- UI
    -----------------------------------------------------
    tab:Section({ Title = "Gather" })

    gatherToggleHandle = tab:Toggle({
        Title = "Gather Items",
        Value = false,
        Callback = function(state) setEnabled(state) end
    })

    tab:Dropdown({
        Title = "Resource Type",
        Values = {"Logs","Stone","Berries"},
        Multi = false,
        AllowNone = false,
        Callback = function(c) if c and c~="" then resourceType=c end end
    })

    tab:Slider({
        Title = "Carry Radius",
        Value = {Min=20,Max=300,Default=DEFAULT_RADIUS},
        Callback = function(v) carryRadius=clamp(v,10,500) end
    })

    tab:Slider({
        Title = "Depth Below Ground",
        Value = {Min=10,Max=100,Default=DEFAULT_DEPTH},
        Callback = function(v) carryDepth=clamp(v,5,200) end
    })

    tab:Button({ Title = "Set Items", Callback = setItemsVisible })

    tab:Section({ Title = "Max Carry: "..tostring(MAX_CARRY) })
end
