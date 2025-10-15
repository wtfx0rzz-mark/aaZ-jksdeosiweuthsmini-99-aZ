return function(C, R, UI)
    -- Services
    local Players = (C and C.Services and C.Services.Players) or game:GetService("Players")
    local RS      = (C and C.Services and C.Services.RS)      or game:GetService("ReplicatedStorage")
    local WS      = (C and C.Services and C.Services.WS)      or game:GetService("Workspace")
    local Run     = game:GetService("RunService")

    -- Resolve tab (create if missing)
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

    ----------------------------------------------------------------
    -- Tunables
    ----------------------------------------------------------------
    local MAX_CARRY      = 50
    local DEFAULT_RADIUS = 80
    local DEFAULT_DEPTH  = 35
    local SCAN_INTERVAL  = 0.25

    -- log stack config
    local STACK_COLS          = 10
    local STACK_H_GAP         = 0.35
    local STACK_V_GAP         = 0.15
    local LOG_ALIGN_ALONG_FWD = true

    ----------------------------------------------------------------
    -- Remotes
    ----------------------------------------------------------------
    local RemoteFolder = RS:FindFirstChild("RemoteEvents")
    local StartDrag    = RemoteFolder and RemoteFolder:FindFirstChild("RequestStartDraggingItem") or nil
    local StopDrag     = RemoteFolder and RemoteFolder:FindFirstChild("StopDraggingItem") or nil

    ----------------------------------------------------------------
    -- State
    ----------------------------------------------------------------
    local lp  = Players.LocalPlayer
    local carried   = {}   -- [Model]=true
    local carryList = {}
    local carryCount = 0

    local gatherEnabled = false
    local scanningOn    = false
    local tetherOn      = false

    local resourceType = "Logs"
    local carryRadius = DEFAULT_RADIUS
    local carryDepth  = DEFAULT_DEPTH
    local baselineY = nil
    local rsConn = nil
    local scanThreadRunning = false
    local gatherToggleHandle = nil

    ----------------------------------------------------------------
    -- Helpers
    ----------------------------------------------------------------
    local function clamp(v, lo, hi)
        v = tonumber(v) or lo
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end
    local function hrp()
        local ch = lp and (lp.Character or lp.CharacterAdded:Wait())
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local function groundBaselineY()
        local root = hrp(); if not root then return nil end
        local origin = root.Position + Vector3.new(0, 500, 0)
        local rc = WS:Raycast(origin, Vector3.new(0, -2000, 0))
        return rc and rc.Position.Y or (root.Position.Y - 10)
    end
    local function belowMapCFrame()
        local root = hrp(); if not (root and baselineY) then return nil end
        local pos = Vector3.new(root.Position.X, baselineY - carryDepth, root.Position.Z)
        return CFrame.new(pos, pos + root.CFrame.LookVector)
    end
    local function mainPart(m)
        if not m then return nil end
        if m:IsA("Model") then
            return m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
        elseif m:IsA("BasePart") then
            return m
        end
        return nil
    end
    local function ensurePrimary(m)
        if m and m:IsA("Model") and not m.PrimaryPart then
            local p = m:FindFirstChildWhichIsA("BasePart")
            if p then m.PrimaryPart = p end
        end
    end
    local function matchesResource(name)
        local n = string.lower(name or "")
        if resourceType == "Logs"    then return n:find("log",   1, true) ~= nil end
        if resourceType == "Stone"   then return n:find("stone", 1, true) or n:find("rock", 1, true) end
        if resourceType == "Berries" then return n:find("berry", 1, true) ~= nil end
        return false
    end
    local function blacklist(m)
        local n = string.lower(m.Name or "")
        return n:find("trader", 1, true) or n:find("shopkeeper", 1, true) or n:find("campfire", 1, true)
    end
    local function toList(t)
        local out = {}
        for k in pairs(t) do out[#out+1] = k end
        return out
    end
    local function addCarry(m)
        if carried[m] or carryCount >= MAX_CARRY then return false end
        carried[m] = true
        carryCount = carryCount + 1
        carryList = toList(carried)
        return true
    end
    local function removeCarry(m)
        if not carried[m] then return end
        carried[m] = nil
        carryCount = carryCount - 1
        if carryCount < 0 then carryCount = 0 end
        carryList = toList(carried)
    end
    local function setNoCollide(m, on)
        local mp = mainPart(m); if not mp then return end
        if m:IsA("Model") then
            for _,d in ipairs(m:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.CanCollide = not on
                    d.Anchored = false
                    if typeof(d.SetNetworkOwner) == "function" then
                        pcall(function() d:SetNetworkOwner(lp) end)
                    end
                end
            end
        else
            mp.CanCollide = not on
            mp.Anchored = false
            if typeof(mp.SetNetworkOwner) == "function" then
                pcall(function() mp:SetNetworkOwner(lp) end)
            end
        end
    end
    local function startDrag(m)
        if StartDrag and m then pcall(function() StartDrag:FireServer(m) end) end
    end
    local function stopDrag(m)
        if StopDrag and m then pcall(function() StopDrag:FireServer(m) end) end
    end

    -- Robust UI toggle setter
    local function uiSetToggle(state)
        local h = gatherToggleHandle
        if not h then return end
        pcall(function() if h.SetValue then h:SetValue(state) end end)
        pcall(function() if h.SetState then h:SetState(state) end end)
        pcall(function() if h.Set      then h:Set(state)      end end)
        pcall(function() if h.Update   then h:Update(state)   end end)
        pcall(function() if h.Value ~= nil then h.Value = state end end)
    end

    ----------------------------------------------------------------
    -- Tether + Scanner
    ----------------------------------------------------------------
    local function startTether()
        if tetherOn then return end
        tetherOn = true
        if rsConn then rsConn:Disconnect(); rsConn = nil end
        rsConn = Run.RenderStepped:Connect(function()
            if not tetherOn then return end
            local cf = belowMapCFrame(); if not cf then return end
            for i = 1, #carryList do
                local m = carryList[i]
                if m and m.Parent then
                    local mp = mainPart(m)
                    if mp then
                        if m:IsA("Model") and m.PrimaryPart then
                            pcall(function() m:PivotTo(cf) end)
                        else
                            pcall(function() mp.CFrame = cf end)
                        end
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
        scanThreadRunning = true
        scanningOn = true
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
                                addCarry(m)
                                setNoCollide(m, true)
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
            baselineY = groundBaselineY()
            startTether()
            startScanner()
        else
            stopScanner()
            stopTether()
        end
    end

    ----------------------------------------------------------------
    -- Placement (sequential, anchored)
    ----------------------------------------------------------------
    local function avgSize(objs)
        local sum = Vector3.new()
        local n = 0
        for _, m in ipairs(objs) do
            if m and m.Parent then
                if m:IsA("Model") then
                    local _, s = m:GetBoundingBox()
                    sum = sum + s; n = n + 1
                else
                    local p = mainPart(m)
                    if p then sum = sum + p.Size; n = n + 1 end
                end
            end
        end
        if n == 0 then return Vector3.new(3,2.5,3) end
        return sum / n
    end
    local function anchorModel(m, anchored)
        if m:IsA("Model") then
            for _,d in ipairs(m:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.Anchored = anchored and true or false
                    d.CanCollide = true
                    d.AssemblyAngularVelocity = Vector3.new()
                    d.AssemblyLinearVelocity  = Vector3.new()
                    d.Massless = false
                end
            end
        else
            local p = mainPart(m)
            if p then
                p.Anchored = anchored and true or false
                p.CanCollide = true
                p.AssemblyAngularVelocity = Vector3.new()
                p.AssemblyLinearVelocity  = Vector3.new()
                p.Massless = false
            end
        end
    end

    local function placeLogStackSequential(list)
        local root = hrp(); if not root then return end
        local forward = root.CFrame.LookVector
        local right   = root.CFrame.RightVector
        local basePos = root.Position + Vector3.new(0, 5, 0) + forward * 5

        local s = avgSize(list)
        local stepX = s.X + STACK_H_GAP
        local stepY = s.Y + STACK_V_GAP
        local halfCols = (STACK_COLS - 1) / 2

        local i = 0
        for _, m in ipairs(list) do
            if m and m.Parent then
                ensurePrimary(m)
                stopDrag(m)
                setNoCollide(m, false)

                local col = i % STACK_COLS
                local row = math.floor(i / STACK_COLS)
                local lateral = (col - halfCols) * stepX
                local height  = row * stepY
                local pos = basePos + right * lateral + Vector3.new(0, height, 0)
                local lookDir = LOG_ALIGN_ALONG_FWD and forward or right
                local cf = CFrame.new(pos, pos + lookDir)

                local mp = mainPart(m)
                if m:IsA("Model") and m.PrimaryPart then
                    pcall(function() m:PivotTo(cf) end)
                elseif mp then
                    pcall(function() mp.CFrame = cf end)
                end

                anchorModel(m, true)
                removeCarry(m)
                task.wait(0.01)
                i = i + 1
            end
        end
    end

    local function placeOthersSequential(list)
        local root = hrp(); if not root then return end
        local forward = root.CFrame.LookVector
        local right   = root.CFrame.RightVector
        local basePos = root.Position + Vector3.new(0, 5, 0) + forward * 5

        local s = avgSize(list)
        local stepX = math.max(1, s.X * 0.8)
        local stepY = math.max(0.8, s.Y * 0.8)
        local cols  = 6
        local halfCols = (cols - 1) / 2

        local i = 0
        for _, m in ipairs(list) do
            if m and m.Parent then
                ensurePrimary(m)
                stopDrag(m)
                setNoCollide(m, false)

                local col = i % cols
                local row = math.floor(i / cols)
                local pos = basePos + right * ((col - halfCols) * stepX) + Vector3.new(0, row * stepY, 0)
                local cf  = CFrame.new(pos, pos + forward)

                local mp = mainPart(m)
                if m:IsA("Model") and m.PrimaryPart then
                    pcall(function() m:PivotTo(cf) end)
                elseif mp then
                    pcall(function() mp.CFrame = cf end)
                end

                anchorModel(m, true)
                removeCarry(m)
                task.wait(0.01)
                i = i + 1
            end
        end
    end

    local function setItemsVisible()
        -- Force OFF visually and logically first
        uiSetToggle(false)
        setEnabled(false)

        -- Snapshot current carried list
        local snap = {}
        for i = 1, #carryList do snap[i] = carryList[i] end
        if #snap == 0 then return end

        -- Partition logs vs others
        local logs, others = {}, {}
        for _, m in ipairs(snap) do
            local n = (m and m.Name) and m.Name:lower() or ""
            if n:find("log", 1, true) then
                logs[#logs+1] = m
            else
                others[#others+1] = m
            end
        end

        if #logs > 0 then placeLogStackSequential(logs) end
        if #others > 0 then placeOthersSequential(others) end
        -- Leave toggle OFF; user can re-enable.
    end

    ----------------------------------------------------------------
    -- Respawn
    ----------------------------------------------------------------
    Players.LocalPlayer.CharacterAdded:Connect(function()
        task.defer(function()
            if gatherEnabled then baselineY = groundBaselineY() end
        end)
    end)

    ----------------------------------------------------------------
    -- UI
    ----------------------------------------------------------------
    tab:Section({ Title = "Gather" })

    gatherToggleHandle = tab:Toggle({
        Title = "Gather Items",
        Value = false,
        Callback = function(state)
            setEnabled(state)
        end
    })

    tab:Dropdown({
        Title = "Resource Type",
        Values = { "Logs", "Stone", "Berries" },
        Multi = false,
        AllowNone = false,
        Callback = function(choice)
            if choice and choice ~= "" then resourceType = choice end
        end
    })

    tab:Slider({
        Title = "Carry Radius",
        Value = { Min = 20, Max = 300, Default = DEFAULT_RADIUS },
        Callback = function(v) carryRadius = clamp(v, 10, 500) end
    })

    tab:Slider({
        Title = "Depth Below Ground",
        Value = { Min = 10, Max = 100, Default = DEFAULT_DEPTH },
        Callback = function(v) carryDepth = clamp(v, 5, 200) end
    })

    tab:Button({
        Title = "Set Items",
        Callback = setItemsVisible
    })

    tab:Section({ Title = "Max Carry: "..tostring(MAX_CARRY) })
end
