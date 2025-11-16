return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")
    local WDModule = (RS and RS:FindFirstChild("LoopWatchdog")) or (RS and RS:WaitForChild("LoopWatchdog"))
    if not WDModule then
        local defaultRS = game:GetService("ReplicatedStorage")
        WDModule = defaultRS:WaitForChild("LoopWatchdog")
    end
    local WD = require(WDModule)
    local CS       = game:GetService("CollectionService")
    local UIS      = game:GetService("UserInputService")

    local lp  = Players.LocalPlayer
    local tabs = UI and UI.Tabs
    local tab  = tabs and (tabs.Debug or tabs.TPBring or tabs.Auto or tabs.Main)
    assert(tab, "No tab")

    local RADIUS = 20

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    local function mainPart(m)
        if not m then return nil end
        if m:IsA("BasePart") then return m end
        if m:IsA("Model") then
            if m.PrimaryPart then return m.PrimaryPart end
            return m:FindFirstChildWhichIsA("BasePart")
        end
        return nil
    end

    local function getRemote(...)
        local f = RS:FindFirstChild("RemoteEvents"); if not f then return nil end
        for i = 1, select("#", ...) do
            local n = select(i, ...)
            local x = f:FindFirstChild(n)
            if x then return x end
        end
        return nil
    end

    local RF_Start = getRemote("RequestStartDraggingItem","StartDraggingItem")
    local RF_Stop  = getRemote("RequestStopDraggingItem","StopDraggingItem","StopDraggingItemRemote")

    local function itemsFolder()
        return WS:FindFirstChild("Items") or WS
    end

    local function nearbyItems()
        local out, root = {}, hrp(); if not root then return out end
        local origin = root.Position
        for _,d in ipairs(itemsFolder():GetDescendants()) do
            local m = d:IsA("Model") and d
                or (d:IsA("BasePart") and d:FindFirstAncestorOfClass("Model"))
                or nil
            if m and m.Parent then
                local p = mainPart(m)
                if p and (p.Position - origin).Magnitude <= RADIUS then
                    out[#out+1] = m
                end
            end
        end
        return out
    end

    local function setPhysicsRestore(m)
        for _,p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then
                p.Anchored = false
                p.CanCollide = true
                p.CanTouch = true
                p.CanQuery = true
                p.Massless = false
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
                p.CollisionGroupId = 0
                pcall(function() p:SetNetworkOwner(nil) end)
                pcall(function()
                    if p.SetNetworkOwnershipAuto then
                        p:SetNetworkOwnershipAuto()
                    end
                end)
            end
        end
        for _,pp in ipairs(m:GetDescendants()) do
            if pp:IsA("ProximityPrompt") then
                pp.Enabled = true
            end
        end
        m:SetAttribute("Dragging", nil)
        m:SetAttribute("PickedUp", nil)
    end

    local function snapshotCollision(m)
        local t = {}
        for _,p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then
                t[p] = {
                    CanCollide = p.CanCollide,
                    CanQuery   = p.CanQuery,
                    CanTouch   = p.CanTouch,
                }
            end
        end
        return t
    end

    local function setCollisionOff(m)
        for _,p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CanCollide = false
                p.CanQuery   = false
                p.CanTouch   = false
            end
        end
    end

    local function restoreCollision(m, snap)
        if not snap then return end
        for part,st in pairs(snap) do
            if part and part.Parent then
                part.CanCollide = st.CanCollide
                part.CanQuery   = st.CanQuery
                part.CanTouch   = st.CanTouch
            end
        end
    end

    local function ownAll()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            if RF_Start then
                pcall(function() RF_Start:FireServer(m) end)
            end
            local p = mainPart(m)
            if p then
                pcall(function() p:SetNetworkOwner(lp) end)
                for _,bp in ipairs(m:GetDescendants()) do
                    if bp:IsA("BasePart") then
                        bp.Anchored = true
                        bp.CanTouch = true
                        bp.CanQuery = true
                    end
                end
            end
        end
    end

    local function disownAll()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            if RF_Stop then
                pcall(function() RF_Stop:FireServer(m) end)
            end
            setPhysicsRestore(m)
        end
    end

    local function startDragAll()
        if not RF_Start then return end
        local list = nearbyItems()
        for _,m in ipairs(list) do
            pcall(function() RF_Start:FireServer(m) end)
            Run.Heartbeat:Wait()
        end
    end

    local function stopDragAll()
        if not RF_Stop then return end
        local list = nearbyItems()
        for _,m in ipairs(list) do
            pcall(function() RF_Stop:FireServer(m) end)
            Run.Heartbeat:Wait()
        end
    end

    local function wakeGentle()
        local list = nearbyItems()
        local lin, ang = 0.05, 0.05
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") and not p.Anchored then
                    local lv = p.AssemblyLinearVelocity
                    local av = p.AssemblyAngularVelocity
                    if lv.Magnitude < 0.02 and av.Magnitude < 0.02 then
                        p.AssemblyLinearVelocity  = lv + Vector3.new(
                            (math.random()-0.5)*lin,
                            (math.random()-0.5)*lin,
                            (math.random()-0.5)*lin
                        )
                        p.AssemblyAngularVelocity = av + Vector3.new(
                            (math.random()-0.5)*ang,
                            (math.random()-0.5)*ang,
                            (math.random()-0.5)*ang
                        )
                    end
                end
            end
        end
    end

    local function deoverlap()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            local p = mainPart(m)
            if p and not p.Anchored then
                local cf = (m:IsA("Model") and m:GetPivot()) or p.CFrame
                local jitter = 0.03
                local dx = (math.random()-0.5)*jitter
                local dz = (math.random()-0.5)*jitter
                local offset = Vector3.new(dx, 0, dz)
                if m:IsA("Model") then
                    m:PivotTo(cf + offset)
                else
                    p.CFrame = cf + offset
                end
            end
        end
    end

    local function nudgeAll()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            setPhysicsRestore(m)
        end
        Run.Heartbeat:Wait()
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") and not p.Anchored then
                    p.AssemblyLinearVelocity  = p.AssemblyLinearVelocity  + Vector3.new(0, 0.6, 0)
                    p.AssemblyAngularVelocity = p.AssemblyAngularVelocity + Vector3.new(
                        0,
                        0.3*(math.random()-0.5),
                        0
                    )
                end
            end
        end
    end

    local function mineOwnership()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.Anchored = false
                    pcall(function() p:SetNetworkOwner(lp) end)
                end
            end
        end
    end

    local function serverOwnership()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.Anchored = false
                    pcall(function() p:SetNetworkOwner(nil) end)
                    pcall(function()
                        if p.SetNetworkOwnershipAuto then
                            p:SetNetworkOwnershipAuto()
                        end
                    end)
                end
            end
        end
    end

    local function groundBelow(pos)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local ex = { lp.Character }

        local map = WS:FindFirstChild("Map")
        if map then
            local fol = map:FindFirstChild("Foliage")
            if fol then
                table.insert(ex, fol)
            end
        end

        local items = WS:FindFirstChild("Items")
        if items then
            table.insert(ex, items)
        end

        params.FilterDescendantsInstances = ex

        local start = pos + Vector3.new(0, 5, 0)
        local hit = WS:Raycast(start, Vector3.new(0, -1000, 0), params)
        if hit then return hit.Position end

        hit = WS:Raycast(pos + Vector3.new(0, 200, 0), Vector3.new(0, -1000, 0), params)
        return (hit and hit.Position) or pos
    end

    local function zeroAssembly(root)
        if not root then return end
        root.AssemblyLinearVelocity  = Vector3.new()
        root.AssemblyAngularVelocity = Vector3.new()
    end

    local function allBodyModels()
        local out = {}
        local chars = WS:FindFirstChild("Characters") or WS
        for _,m in ipairs(chars:GetChildren()) do
            if m:IsA("Model") and m.Name:match("%sBody$") and mainPart(m) then
                out[#out+1] = m
            end
        end
        return out
    end

    local function findNearestBody()
        local root = hrp(); if not root then return nil end
        local best, bestD = nil, math.huge
        for _,m in ipairs(allBodyModels()) do
            local p = mainPart(m)
            if p then
                local d = (p.Position - root.Position).Magnitude
                if d < bestD then
                    bestD, best = d, m
                end
            end
        end
        return best
    end

    local function tpPlayerToBody()
        local m = findNearestBody(); if not m then return end
        local p = mainPart(m); if not p then return end
        local g = groundBelow(p.Position)
        local dest = Vector3.new(p.Position.X, g.Y + 2.5, p.Position.Z)
        local root = hrp(); if not root then return end

        local look = (p.Position - root.Position)
        if look.Magnitude < 1e-3 then
            look = root.CFrame.LookVector
        end

        local cf = CFrame.new(dest, dest + look.Unit)
        pcall(function()
            (lp.Character or {}).PrimaryPart.CFrame = cf
        end)
        pcall(function()
            root.CFrame = cf
        end)
        zeroAssembly(root)
    end

    local function bringBodiesFast()
        local root = hrp(); if not root then return end
        local bodies = allBodyModels(); if #bodies == 0 then return end

        local targetPos = groundBelow(root.Position + root.CFrame.LookVector * 2)
        local cf = CFrame.new(
            Vector3.new(targetPos.X, targetPos.Y + 1.5, targetPos.Z),
            root.Position
        )

        for _,m in ipairs(bodies) do
            local snap = snapshotCollision(m)
            setCollisionOff(m)
            if RF_Start then pcall(function() RF_Start:FireServer(m) end) end
            Run.Heartbeat:Wait()
            pcall(function() m:PivotTo(cf) end)
            Run.Heartbeat:Wait()
            restoreCollision(m, snap)
            if RF_Stop then pcall(function() RF_Stop:FireServer(m) end) end
            setPhysicsRestore(m)
            Run.Heartbeat:Wait()
        end
    end

    local function releaseBody()
        local m = findNearestBody(); if not m then return end
        if RF_Stop then
            pcall(function() RF_Stop:FireServer(m) end)
        end
        setPhysicsRestore(m)
    end

    local CAMP_CACHE = nil

    local function fireCenterPart(fire)
        if not fire then return nil end
        local c = fire:FindFirstChild("Center")
            or fire:FindFirstChild("InnerTouchZone")
            or fire:FindFirstChildWhichIsA("BasePart")
            or fire.PrimaryPart
        if c and c:IsA("BasePart") then
            return c
        end
        return nil
    end

    local function resolveCampfireModel()
        if CAMP_CACHE and CAMP_CACHE.Parent then
            return CAMP_CACHE
        end

        local function nameHit(n)
            n = (n or ""):lower()
            if n == "mainfire" then return true end
            if n == "campfire" or n == "camp fire" then return true end
            if n:find("main") and n:find("fire") then return true end
            if n:find("camp") and n:find("fire") then return true end
            return false
        end

        local map = WS:FindFirstChild("Map")
        local cg  = map and map:FindFirstChild("Campground")
        local mf  = cg and (
            cg:FindFirstChild("MainFire")
            or cg:FindFirstChild("Campfire")
            or cg:FindFirstChild("CampFire")
        )

        if mf then
            CAMP_CACHE = mf
            return mf
        end

        if map then
            for _,d in ipairs(map:GetDescendants()) do
                if d:IsA("Model") and nameHit(d.Name) then
                    CAMP_CACHE = d
                    return d
                end
            end
        end

        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") and nameHit(d.Name) then
                CAMP_CACHE = d
                return d
            end
        end

        return nil
    end

    local function campTargetCF()
        local fire = resolveCampfireModel(); if not fire then return nil end
        local c = fireCenterPart(fire); if not c then return nil end

        local size = Vector3.new()
        pcall(function()
            local min, max = fire:GetBoundingBox()
            size = (max - min)
        end)

        local pad = math.max(size.X, size.Z)
        if pad == 0 then
            local zone = fire:FindFirstChild("InnerTouchZone")
            if zone and zone:IsA("BasePart") then
                pad = math.max(zone.Size.X, zone.Size.Z)
            end
        end
        if pad == 0 then pad = 6 end

        local posAhead = c.Position + c.CFrame.LookVector * (pad * 0.5 + 2)
        local g = groundBelow(posAhead)
        local pos = Vector3.new(posAhead.X, g.Y + 1.5, posAhead.Z)
        return CFrame.new(pos, c.Position)
    end

    local function sendBodiesToCamp()
        local bodies = allBodyModels(); if #bodies == 0 then return end
        local cf = campTargetCF(); if not cf then return end

        for _,m in ipairs(bodies) do
            local snap = snapshotCollision(m)
            setCollisionOff(m)
            if RF_Start then pcall(function() RF_Start:FireServer(m) end) end
            Run.Heartbeat:Wait()
            pcall(function() m:PivotTo(cf) end)
            Run.Heartbeat:Wait()
            restoreCollision(m, snap)
            if RF_Stop then pcall(function() RF_Stop:FireServer(m) end) end
            setPhysicsRestore(m)
            Run.Heartbeat:Wait()
        end
    end

    ----------------------------------------------------------------
    -- Sapling protection
    ----------------------------------------------------------------
    local SAP_Enable = false
    local sap_seen = setmetatable({}, { __mode = "k" })
    local sap_conns = {}

    local function isSapling(m)
        if not m or not m.Parent then return false end
        if m:IsA("Model") then
            local n = (m.Name or ""):lower()
            if n:find("sapling") then return true end
            if CS:HasTag(m, "Sapling") then return true end
            if m:GetAttribute("IsSapling") == true then return true end
        end
        return false
    end

    local function tryStartDragSapling(m)
        if not SAP_Enable then return end
        if not m or not m.Parent then return end
        if not isSapling(m) then return end
        if sap_seen[m] then return end
        sap_seen[m] = true
        if RF_Start then
            pcall(function() RF_Start:FireServer(m) end)
        end
    end

    local function bindSaplingWatcher(items)
        for _,c in ipairs(sap_conns) do
            c:Disconnect()
        end
        table.clear(sap_conns)

        if not SAP_Enable then
            table.clear(sap_seen)
            return
        end

        if not items or not items.Parent then
            items = itemsFolder()
        end

        for _,d in ipairs(items:GetDescendants()) do
            local m = d:IsA("Model") and d or d:FindFirstAncestorOfClass("Model")
            if m then
                tryStartDragSapling(m)
            end
        end

        sap_conns[#sap_conns+1] = items.DescendantAdded:Connect(function(d)
            local m = d:IsA("Model") and d or d:FindFirstAncestorOfClass("Model")
            if m then
                tryStartDragSapling(m)
            end
        end)

        sap_conns[#sap_conns+1] = WS.ChildAdded:Connect(function(ch)
            if ch.Name == "Items" or ch == items then
                task.defer(function()
                    bindSaplingWatcher(itemsFolder())
                end)
            end
        end)
    end

    ----------------------------------------------------------------
    -- Precision movement controls + camera lock (camera-based)
    ----------------------------------------------------------------
    local PREC_Enable = false
    local PREC_Speed  = 2.0 -- studs/sec, controlled by slider
    local wd_precisionMove = WD.register("debug::precisionMove", function() return PREC_Enable end)

    local PREC_BaseLook   = nil
    local PREC_BaseRight  = nil
    local PREC_CamOffset  = nil

    local moveForward = false
    local moveBack    = false
    local moveLeft    = false
    local moveRight   = false
    local moveUp      = false
    local moveDown    = false

    local moveGui     = nil
    local moveConn    = nil
    local moveGuiConns = {}

    local origCamType    = nil
    local origCamSubject = nil

    local function clearMoveFlags()
        moveForward = false
        moveBack    = false
        moveLeft    = false
        moveRight   = false
        moveUp      = false
        moveDown    = false
    end

    local function trackMoveConn(conn)
        if conn then
            moveGuiConns[#moveGuiConns+1] = conn
        end
        return conn
    end

    local function destroyMoveGui()
        clearMoveFlags()
        if moveGui then
            pcall(function() moveGui:Destroy() end)
        end
        moveGui = nil
        if moveConn then
            moveConn:Disconnect()
            moveConn = nil
        end
        for i = #moveGuiConns, 1, -1 do
            local conn = moveGuiConns[i]
            if conn and conn.Disconnect then
                pcall(function() conn:Disconnect() end)
            end
            moveGuiConns[i] = nil
        end
    end

    local function ensureMoveHeartbeat()
        if moveConn then return end

        moveConn = Run.Heartbeat:Connect(function(dt)
            wd_precisionMove:tick()
            if not PREC_Enable then return end
            local root = hrp(); if not root then return end
            if not PREC_BaseLook or not PREC_BaseRight or not PREC_CamOffset then return end

            local rootPos = root.Position

            -- Camera lock: keep camera in a fixed offset and angle captured at toggle-on
            local cam = workspace.CurrentCamera
            if cam then
                local camPos = rootPos + PREC_CamOffset
                cam.CFrame = CFrame.new(camPos, camPos + PREC_BaseLook)
            end

            -- Movement directions based on camera angle at toggle time
            local forward3D = PREC_BaseLook
            local right3D   = PREC_BaseRight

            local forward = Vector3.new(forward3D.X, 0, forward3D.Z)
            if forward.Magnitude < 1e-4 then
                forward = Vector3.new(0, 0, -1)
            else
                forward = forward.Unit
            end

            local right = Vector3.new(right3D.X, 0, right3D.Z)
            if right.Magnitude < 1e-4 then
                right = Vector3.new(1, 0, 0)
            else
                right = right.Unit
            end

            local up = Vector3.new(0, 1, 0)

            local dir = Vector3.new(0, 0, 0)
            if moveForward then dir += forward end
            if moveBack    then dir -= forward end
            if moveRight   then dir += right   end
            if moveLeft    then dir -= right   end
            if moveUp      then dir += up      end
            if moveDown    then dir -= up      end

            if dir.Magnitude <= 0 then return end
            dir = dir.Unit

            local step   = PREC_Speed * dt
            local newPos = rootPos + dir * step

            local look = PREC_BaseLook or root.CFrame.LookVector
            if look.Magnitude < 1e-4 then
                look = Vector3.new(0, 0, -1)
            end

            local newCF = CFrame.new(newPos, newPos + look.Unit)
            root.CFrame = newCF
            zeroAssembly(root)
        end)
    end

    local function bindMoveButton(btn, setter)
        trackMoveConn(btn.MouseButton1Down:Connect(function()
            setter(true)
        end))
        trackMoveConn(btn.MouseButton1Up:Connect(function()
            setter(false)
        end))
        trackMoveConn(btn.MouseLeave:Connect(function()
            setter(false)
        end))
    end

    local function createMoveGui()
        if moveGui then return end

        local pg = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")

        local gui = Instance.new("ScreenGui")
        gui.Name = "PrecisionMoveGui"
        gui.ResetOnSpawn = false
        gui.Parent = pg

        -- Movement pad (no black box, higher up)
        local frame = Instance.new("Frame")
        frame.Name = "Pad"
        frame.Size = UDim2.new(0, 220, 0, 220)
        frame.Position = UDim2.new(1, -230, 1, -380) -- was -300, moved higher
        frame.BackgroundTransparency = 1
        frame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
        frame.BorderSizePixel = 0
        frame.Parent = gui

        local layout = Instance.new("UIGridLayout")
        layout.CellSize = UDim2.new(0, 70, 0, 70)
        layout.CellPadding = UDim2.new(0, 5, 0, 5)
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.VerticalAlignment   = Enum.VerticalAlignment.Center
        layout.FillDirection       = Enum.FillDirection.Horizontal
        layout.SortOrder           = Enum.SortOrder.LayoutOrder
        layout.Parent = frame

        local function makeButton(text, order)
            local b = Instance.new("TextButton")
            b.LayoutOrder = order or 0
            b.Size = UDim2.new(0, 70, 0, 70)
            b.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
            b.BorderSizePixel = 0
            b.TextColor3 = Color3.fromRGB(255, 255, 255)
            b.TextSize = 18
            b.TextWrapped = true
            b.Font = Enum.Font.SourceSansBold
            b.Text = text
            b.AutoButtonColor = true
            b.Parent = frame

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 8)
            corner.Parent = b

            return b
        end

        local btnUp      = makeButton("Up",      1)
        local btnForward = makeButton("Forward", 2)
        local btnDown    = makeButton("Down",    3)
        local btnLeft    = makeButton("Left",    4)
        local btnBack    = makeButton("Back",    5)
        local btnRight   = makeButton("Right",   6)

        bindMoveButton(btnUp,      function(v) moveUp      = v end)
        bindMoveButton(btnDown,    function(v) moveDown    = v end)
        bindMoveButton(btnForward, function(v) moveForward = v end)
        bindMoveButton(btnBack,    function(v) moveBack    = v end)
        bindMoveButton(btnLeft,    function(v) moveLeft    = v end)
        bindMoveButton(btnRight,   function(v) moveRight   = v end)

        -- Custom speed slider, under the pad (also moved higher)
        local sliderFrame = Instance.new("Frame")
        sliderFrame.Name = "SpeedSliderFrame"
        sliderFrame.Size = UDim2.new(0, 220, 0, 40)
        sliderFrame.Position = UDim2.new(1, -230, 1, -150) -- was -70, moved higher
        sliderFrame.BackgroundTransparency = 1
        sliderFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
        sliderFrame.BorderSizePixel = 0
        sliderFrame.Parent = gui

        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.Size = UDim2.new(1, 0, 0, 18)
        label.Position = UDim2.new(0, 0, 0, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextSize = 14
        label.Font = Enum.Font.SourceSans
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Text = "Speed: 2.00"
        label.Parent = sliderFrame

        local bar = Instance.new("Frame")
        bar.Name = "Bar"
        bar.Size = UDim2.new(0, 140, 0, 6)
        bar.Position = UDim2.new(0, 5, 1, -16)
        bar.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        bar.BorderSizePixel = 0
        bar.Parent = sliderFrame

        local barCorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(0, 3)
        barCorner.Parent = bar

        local thumb = Instance.new("TextButton")
        thumb.Name = "Thumb"
        thumb.Size = UDim2.new(0, 14, 0, 22)
        thumb.Position = UDim2.new(0, 0, 0.5, -11)
        thumb.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
        thumb.BorderSizePixel = 0
        thumb.Text = ""
        thumb.AutoButtonColor = true
        thumb.Parent = bar

        local thumbCorner = Instance.new("UICorner")
        thumbCorner.CornerRadius = UDim.new(0, 7)
        thumbCorner.Parent = thumb

        local MIN_SPEED = 0.1
        local MAX_SPEED = 25

        local dragging = false
        local dragInput = nil

        local function getBarWidth()
            local w = bar.AbsoluteSize.X
            if w <= 0 then
                w = bar.Size.X.Offset
            end
            if w <= 0 then
                w = 140
            end
            return w
        end

        local function applyAlpha(alpha)
            alpha = math.clamp(alpha, 0, 1)
            local speed = MIN_SPEED + (MAX_SPEED - MIN_SPEED) * alpha
            PREC_Speed = speed
            label.Text = string.format("Speed: %.2f", speed)

            local w = getBarWidth()
            local thumbX = alpha * w
            local halfThumb = thumb.Size.X.Offset / 2
            thumb.Position = UDim2.new(0, math.floor(thumbX - halfThumb), 0.5, -thumb.Size.Y.Offset/2)
        end

        local function setFromX(screenX)
            local barPos = bar.AbsolutePosition.X
            local w = getBarWidth()
            local rel = (screenX - barPos) / w
            applyAlpha(rel)
        end

        thumb.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragInput = input
                setFromX(input.Position.X)
            end
        end)

        thumb.InputEnded:Connect(function(input)
            if input == dragInput then
                dragging = false
                dragInput = nil
            end
        end)

        trackMoveConn(bar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragInput = input
                setFromX(input.Position.X)
            end
        end))

        trackMoveConn(UIS.InputChanged:Connect(function(input)
            if dragging then
                setFromX(input.Position.X)
            end
        end))

        trackMoveConn(UIS.InputEnded:Connect(function(input)
            if input == dragInput then
                dragging = false
                dragInput = nil
            end
        end))

        -- Initial slider position (~low speed for precision)
        applyAlpha(0.1) -- ~10% of range

        moveGui = gui
        ensureMoveHeartbeat()
    end

    local function setPrecisionEnabled(on)
        local cam = workspace.CurrentCamera
        local root = hrp()

        if on and not PREC_Enable then
            PREC_Enable = true

            if cam and root then
                if not origCamType then
                    origCamType = cam.CameraType
                end
                if not origCamSubject then
                    origCamSubject = cam.CameraSubject
                end

                local baseCF = cam.CFrame
                PREC_BaseLook  = baseCF.LookVector
                PREC_BaseRight = baseCF.RightVector
                PREC_CamOffset = baseCF.Position - root.Position

                cam.CameraType = Enum.CameraType.Scriptable
            end

            createMoveGui()
        elseif (not on) and PREC_Enable then
            PREC_Enable = false
            destroyMoveGui()
            if cam then
                if origCamType then
                    cam.CameraType = origCamType
                end
                if origCamSubject then
                    cam.CameraSubject = origCamSubject
                end
            end
            origCamType, origCamSubject = nil, nil
            wd_precisionMove:stop()
        end
    end

    ----------------------------------------------------------------
    -- UI SECTIONS
    ----------------------------------------------------------------
    tab:Section({ Title = "Item Recovery" })
    tab:Button({ Title = "Own All Items",    Callback = function() ownAll() end })
    tab:Button({ Title = "Disown All Items", Callback = function() disownAll() end })
    tab:Button({ Title = "Wake (Gentle)",    Callback = function() wakeGentle() end })
    tab:Button({ Title = "De-overlap",       Callback = function() deoverlap() end })
    tab:Button({ Title = "Nudge Items",      Callback = function() nudgeAll() end })
    tab:Button({ Title = "Mine Ownership",   Callback = function() mineOwnership() end })
    tab:Button({ Title = "Server Ownership", Callback = function() serverOwnership() end })

    tab:Section({ Title = "Drag Remotes" })
    tab:Button({ Title = "Start Drag Nearby", Callback = function() startDragAll() end })
    tab:Button({ Title = "Stop Drag Nearby",  Callback = function() stopDragAll() end })

    tab:Section({ Title = "Body Tests" })
    tab:Button({ Title = "TP To Body",              Callback = function() tpPlayerToBody() end })
    tab:Button({ Title = "Bring Body (Fast Drag)",  Callback = function() bringBodiesFast() end })
    tab:Button({ Title = "Release Body",            Callback = function() releaseBody() end })
    tab:Button({ Title = "Send All Bodies To Camp", Callback = function() sendBodiesToCamp() end })

    tab:Section({ Title = "Protection" })
    if tab.Toggle then
        tab:Toggle({
            Title = "Sapling Protection",
            Default = false,
            Callback = function(v)
                SAP_Enable = v and true or false
                bindSaplingWatcher(itemsFolder())
            end
        })
    else
        tab:Button({
            Title = "Sapling Protection: OFF",
            Callback = function(btn)
                SAP_Enable = not SAP_Enable
                if btn and btn.SetTitle then
                    btn:SetTitle("Sapling Protection: " .. (SAP_Enable and "ON" or "OFF"))
                end
                bindSaplingWatcher(itemsFolder())
            end
        })
    end

    tab:Section({ Title = "Precision Movement" })
    if tab.Toggle then
        tab:Toggle({
            Title = "Precision Movement Controls",
            Default = false,
            Callback = function(v)
                setPrecisionEnabled(v)
            end
        })
    else
        tab:Button({
            Title = "Precision Movement Controls: OFF",
            Callback = function(btn)
                local newState = not PREC_Enable
                if btn and btn.SetTitle then
                    btn:SetTitle("Precision Movement Controls: " .. (newState and "ON" or "OFF"))
                end
                setPrecisionEnabled(newState)
            end
        })
    end
end
