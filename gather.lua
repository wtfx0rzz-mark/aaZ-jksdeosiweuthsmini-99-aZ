return function(C, R, UI)
    -- Services
    local Players = (C and C.Services and C.Services.Players) or game:GetService("Players")
    local RS      = (C and C.Services and C.Services.RS)      or game:GetService("ReplicatedStorage")
    local WS      = (C and C.Services and C.Services.WS)      or game:GetService("Workspace")
    local Run     = (C and C.Services and C.Services.Run)     or game:GetService("RunService")

    -- UI tab
    local Tabs = (UI and UI.Tabs) or {}
    local tab  = Tabs.Gather
    if not tab then return end

    ----------------------------------------------------------------
    -- Tunables
    ----------------------------------------------------------------
    local MAX_CARRY      = 100
    local DEFAULT_RADIUS = 80
    local DEFAULT_DEPTH  = 35
    local SCAN_INTERVAL  = 0.25

    ----------------------------------------------------------------
    -- Helpers
    ----------------------------------------------------------------
    local function clamp(v, lo, hi)
        v = tonumber(v) or lo
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    local function setToggleCompat(handle, state)
        if not handle then return end
        local ok = false
        ok = ok or pcall(function() if handle.SetValue then handle:SetValue(state) end end)
        ok = ok or pcall(function() if handle.SetState then handle:SetState(state) end end)
        ok = ok or pcall(function() if handle.Set then handle:Set(state) end end)
        ok = ok or pcall(function() if handle.Update then handle:Update(state) end end)
        ok = ok or pcall(function() if handle.Value ~= nil then handle.Value = state end end)
        return ok
    end

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

    local gatherEnabled = false     -- user toggle state
    local scanningOn    = false     -- background scanner running
    local tetherOn      = false     -- under-map repositioner running

    local resourceType = "Logs"
    local carryRadius = DEFAULT_RADIUS
    local carryDepth  = DEFAULT_DEPTH
    local baselineY = nil
    local rsConn = nil
    local scanThreadRunning = false
    local gatherToggleHandle = nil

    ----------------------------------------------------------------
    -- Common fns
    ----------------------------------------------------------------
    local function toList(t)
        local out = {}
        for k in pairs(t) do out[#out+1] = k end
        return out
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

    local function startDrag(m)
        if StartDrag and m then pcall(function() StartDrag:FireServer(m) end) end
    end

    local function stopDrag(m)
        if StopDrag and m then pcall(function() StopDrag:FireServer(m) end) end
    end

    local function setNoCollide(m, on)
        local mp = mainPart(m); if not mp then return end
        if m:IsA("Model") then
            for _,d in ipairs(m:GetDescendants()) do
                if d:IsA("BasePart") then
                    if on then d.CanCollide = false else d.CanCollide = true end
                    d.Anchored = false
                    if typeof(d.SetNetworkOwner) == "function" then
                        pcall(function() d:SetNetworkOwner(lp) end)
                    end
                end
            end
        else
            if on then mp.CanCollide = false else mp.CanCollide = true end
            mp.Anchored = false
            if typeof(mp.SetNetworkOwner) == "function" then
                pcall(function() mp:SetNetworkOwner(lp) end)
            end
        end
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
                        if not scanningOn then break end
                        if carryCount >= MAX_CARRY then break end
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

    -- Enable without clearing items
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

    -- Full clear (not used by Set Items)
    local function fullDisableAndClear()
        setEnabled(false)
        for m in pairs(carried) do
            stopDrag(m)
            setNoCollide(m, false)
        end
        carried, carryList, carryCount = {}, {}, 0
    end

    ----------------------------------------------------------------
    -- Placement: visible pile 5 up + 5 forward, physics on
    ----------------------------------------------------------------
    local function dropPhysicsify(m, dropVelocity)
        if m:IsA("Model") then
            for _,d in ipairs(m:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.Anchored = false
                    d.CanCollide = true
                    if typeof(d.SetNetworkOwner) == "function" then
                        pcall(function() d:SetNetworkOwner(lp) end)
                    end
                    d.AssemblyAngularVelocity = Vector3.new(0, math.random() * 2, 0)
                    d.AssemblyLinearVelocity  = dropVelocity
                    d.Massless = false
                end
            end
        else
            local p = mainPart(m)
            if p then
                p.Anchored = false
                p.CanCollide = true
                if typeof(p.SetNetworkOwner) == "function" then
                    pcall(function() p:SetNetworkOwner(lp) end)
                end
                p.AssemblyAngularVelocity = Vector3.new(0, math.random() * 2, 0)
                p.AssemblyLinearVelocity  = dropVelocity
                p.Massless = false
            end
        end
    end

    local function setItemsVisiblePile()
        -- 1) Turn OFF toggle visually and logically, but KEEP carried list
        setToggleCompat(gatherToggleHandle, false)
        setEnabled(false)

        -- 2) Place items visibly
        local root = hrp(); if not root then return end
        local forward = root.CFrame.LookVector
        local pilePos = root.Position + Vector3.new(0, 5, 0) + forward * 5
        local function jitter() return Vector3.new((math.random()-0.5)*0.8, 0, (math.random()-0.5)*0.8) end
        local downVel = Vector3.new(0, -30, 0)

        local list = {}
        for i = 1, #carryList do list[i] = carryList[i] end

        for _, m in ipairs(list) do
            if m and m.Parent then
                ensurePrimary(m)
                stopDrag(m)
                setNoCollide(m, false) -- restore collisions before placing

                local mp = mainPart(m)
                local targetCF = CFrame.new(pilePos + jitter(), pilePos + forward)

                if m:IsA("Model") and m.PrimaryPart then
                    pcall(function() m:PivotTo(targetCF) end)
                elseif mp then
                    pcall(function() mp.CFrame = targetCF end)
                end

                dropPhysicsify(m, downVel)
            end
            removeCarry(m)
        end
        -- leave toggle OFF; user can re-enable manually
    end

    ----------------------------------------------------------------
    -- Respawn baseline refresh
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
        Callback = setItemsVisiblePile
    })

    tab:Section({ Title = "Max Carry: "..tostring(MAX_CARRY) })
end
