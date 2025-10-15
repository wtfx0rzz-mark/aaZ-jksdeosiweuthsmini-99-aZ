return function(C, R, UI)
    local Players = (C and C.Services and C.Services.Players) or game:GetService("Players")
    local RS      = (C and C.Services and C.Services.RS)      or game:GetService("ReplicatedStorage")
    local WS      = (C and C.Services and C.Services.WS)      or game:GetService("Workspace")
    local Run     = (C and C.Services and C.Services.Run)     or game:GetService("RunService")

    local lp  = Players.LocalPlayer
    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Gather
    assert(tab, "Gather tab not found in UI")

    -- Tunables
    local MAX_CARRY      = 50
    local DEFAULT_RADIUS = 80
    local DEFAULT_DEPTH  = 35
    local SCAN_INTERVAL  = 0.25

    -- Remotes
    local RemoteFolder = RS:FindFirstChild("RemoteEvents")
    local StartDrag    = RemoteFolder and RemoteFolder:FindFirstChild("RequestStartDraggingItem")
    local StopDrag     = RemoteFolder and RemoteFolder:FindFirstChild("StopDraggingItem")

    -- State
    local carried   = {}   -- [Model]=true
    local carryList = {}
    local carryCount = 0
    local enabled = false
    local resourceType = "Logs"
    local carryRadius = DEFAULT_RADIUS
    local carryDepth  = DEFAULT_DEPTH
    local baselineY = nil
    local rsConn = nil
    local scanThreadRunning = false

    -- Helpers
    local function toList(t)
        local out = {}
        for k in pairs(t) do out[#out+1] = k end
        return out
    end

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
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
        -- avoid NPCs, traders, shopkeepers, campfire models
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
        carryCount = math.max(0, carryCount - 1)
        carryList = toList(carried)
    end

    local function startDrag(m)
        if StartDrag and m then pcall(function() StartDrag:FireServer(m) end) end
    end

    local function stopDrag(m)
        if StopDrag and m then pcall(function() StopDrag:FireServer(m) end) end
    end

    local function clearRemoved()
        for i = #carryList, 1, -1 do
            local m = carryList[i]
            if not (m and m.Parent) then removeCarry(m) end
        end
    end

    local function setNoCollide(m, on)
        local mp = mainPart(m); if not mp then return end
        if m:IsA("Model") then
            for _,d in ipairs(m:GetDescendants()) do
                if d:IsA("BasePart") then
                    if on then d.CanCollide = false end
                    d.Anchored = false
                    pcall(function() d:SetNetworkOwner(lp) end)
                end
            end
        else
            if on then mp.CanCollide = false end
            mp.Anchored = false
            pcall(function() mp:SetNetworkOwner(lp) end)
        end
    end

    local function repositionAll()
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
    end

    local function scanAndPickup()
        if scanThreadRunning then return end
        scanThreadRunning = true
        task.spawn(function()
            while enabled do
                clearRemoved()
                local items = WS:FindFirstChild("Items")
                local root = hrp()
                if items and root then
                    local origin = root.Position
                    for _,m in ipairs(items:GetChildren()) do
                        if not enabled or carryCount >= MAX_CARRY then break end
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

    local function enable()
        if enabled then return end
        enabled = true
        baselineY = groundBaselineY()
        if rsConn then rsConn:Disconnect() end
        rsConn = Run.RenderStepped:Connect(repositionAll)
        scanAndPickup()
    end

    local function disable()
        if not enabled then return end
        enabled = false
        if rsConn then rsConn:Disconnect(); rsConn = nil end
        for m in pairs(carried) do
            stopDrag(m)
            setNoCollide(m, false)
        end
        carried, carryList, carryCount = {}, {}, 0
    end

    local function modelSize(m)
        if m:IsA("Model") then
            local _, size = m:GetBoundingBox()
            return size
        else
            local p = mainPart(m)
            return p and p.Size or Vector3.new(2,2,2)
        end
    end

    local function setItemsStack()
        local root = hrp(); if not root then return end
        local basePos = root.Position + Vector3.new(0, 10, 0)
        local colCount = 5
        local i = 0
        for _, m in ipairs(carryList) do
            if m and m.Parent then
                ensurePrimary(m)
                local size = modelSize(m)
                local stepX = math.max(3, size.X + 0.5)
                local stepY = math.max(2.5, size.Y + 0.25)
                local col = i % colCount
                local row = math.floor(i / colCount)
                local offsetX = (col - (colCount-1)/2) * stepX
                local pos = basePos + Vector3.new(offsetX, row * stepY, 0)
                local cf = CFrame.new(pos, pos + root.CFrame.LookVector)

                stopDrag(m)
                local mp = mainPart(m)
                if m:IsA("Model") and m.PrimaryPart then
                    pcall(function() m:PivotTo(cf) end)
                elseif mp then
                    pcall(function() mp.CFrame = cf end)
                end

                if m:IsA("Model") then
                    for _,d in ipairs(m:GetDescendants()) do
                        if d:IsA("BasePart") then
                            d.Anchored = true
                            d.CanCollide = true
                        end
                    end
                elseif mp then
                    mp.Anchored = true
                    mp.CanCollide = true
                end
            end
            removeCarry(m)
            i = i + 1
        end
    end

    Players.LocalPlayer.CharacterAdded:Connect(function()
        task.defer(function()
            if enabled then baselineY = groundBaselineY() end
        end)
    end)

    -- UI (match Bring tab style)
    tab:Section({ Title = "Gather" })

    tab:Toggle({
        Title = "Carry Under Map",
        Value = false,
        Callback = function(state)
            if state then enable() else disable() end
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
        Callback = function(v)
            carryRadius = math.clamp(tonumber(v) or DEFAULT_RADIUS, 10, 500)
        end
    })

    tab:Slider({
        Title = "Depth Below Ground",
        Value = { Min = 10, Max = 100, Default = DEFAULT_DEPTH },
        Callback = function(v)
            carryDepth = math.clamp(tonumber(v) or DEFAULT_DEPTH, 5, 200)
        end
    })

    tab:Button({
        Title = "Set Items",
        Callback = function()
            setItemsStack()
        end
    })

    tab:Section({ Title = "Max Carry: "..tostring(MAX_CARRY) })
end
