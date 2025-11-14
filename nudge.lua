-- nudge.lua
return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI

    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")
    local lp = Players.LocalPlayer

    local Tabs = (UI and UI.Tabs) or {}
    local tab  = Tabs.Nudge or Tabs.Main or Tabs.Auto
    if not tab then return end

    local function hrp(p)
        p = p or lp
        local ch = p.Character or p.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end

    local function mainPart(obj)
        if not obj or not obj.Parent then return nil end
        if obj:IsA("BasePart") then return obj end
        if obj:IsA("Model") then
            if obj.PrimaryPart then return obj.PrimaryPart end
            return obj:FindFirstChildWhichIsA("BasePart")
        end
        return nil
    end

    local function getParts(target)
        local t = {}
        if not target then return t end
        if target:IsA("BasePart") then
            t[1] = target
        elseif target:IsA("Model") then
            for _, d in ipairs(target:GetDescendants()) do
                if d:IsA("BasePart") then
                    t[#t+1] = d
                end
            end
        end
        return t
    end

    local function setCollide(model, on, snap)
        local parts = getParts(model)
        if on and snap then
            for part, can in pairs(snap) do
                if part and part.Parent then
                    part.CanCollide = can
                end
            end
            return
        end
        local s = {}
        for _, p in ipairs(parts) do
            s[p] = p.CanCollide
            p.CanCollide = false
        end
        return s
    end

    local function zeroAssembly(model)
        for _, p in ipairs(getParts(model)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
    end

    local function getRemote(...)
        local re = RS:FindFirstChild("RemoteEvents")
        if not re then return nil end
        for _, n in ipairs({...}) do
            local x = re:FindFirstChild(n)
            if x then return x end
        end
        return nil
    end

    local REM = { StartDrag = nil, StopDrag = nil }

    local function resolveRemotes()
        REM.StartDrag = getRemote("RequestStartDraggingItem", "StartDraggingItem")
        REM.StopDrag  = getRemote("StopDraggingItem", "RequestStopDraggingItem")
    end

    resolveRemotes()

    local function safeStartDrag(model)
        if REM.StartDrag and model and model.Parent then
            pcall(function()
                REM.StartDrag:FireServer(model)
            end)
            return true
        end
        return false
    end

    local function safeStopDrag(model)
        if REM.StopDrag and model and model.Parent then
            pcall(function()
                REM.StopDrag:FireServer(model)
            end)
            return true
        end
        return false
    end

    local function finallyStopDrag(model)
        task.delay(0.05, function()
            pcall(safeStopDrag, model)
        end)
        task.delay(0.20, function()
            pcall(safeStopDrag, model)
        end)
    end

    local function isCharacterModel(m)
        return m
            and m:IsA("Model")
            and m:FindFirstChildOfClass("Humanoid") ~= nil
    end

    local function isNPCModel(m)
        if not isCharacterModel(m) then return false end
        if Players:GetPlayerFromCharacter(m) then return false end
        local n = (m.Name or ""):lower()
        if n:find("horse", 1, true) then return false end
        return true
    end

    local function charDistancePart(m)
        if not (m and m:IsA("Model")) then return nil end
        local h = m:FindFirstChild("HumanoidRootPart")
        if h and h:IsA("BasePart") then return h end
        local pp = m.PrimaryPart
        if pp and pp:IsA("BasePart") then return pp end
        return nil
    end

    local function horiz(v)
        return Vector3.new(v.X, 0, v.Z)
    end

    local function unitOr(v, fallback)
        local m = v.Magnitude
        if m > 1e-3 then
            return v / m
        end
        return fallback
    end

    local Nudge = {
        Dist    = 50,
        Up      = 20,
        Radius  = 15,
        SelfSafe = 3.5,
    }

    local AutoNudge = {
        Enabled     = false,
        MaxPerFrame = 16
    }

    local function preDrag(model)
        local started = safeStartDrag(model)
        if started then
            task.wait(0.02)
        end
        return started
    end

    local function impulseItem(model, fromPos)
        local mp = mainPart(model)
        if not mp then return end

        local pos  = mp.Position
        local away = horiz(pos - fromPos)
        local dist = away.Magnitude
        if dist < 1e-3 then return end

        if dist < Nudge.SelfSafe then
            local out = fromPos + away.Unit * (Nudge.SelfSafe + 0.5)
            local snap0 = setCollide(model, false)
            zeroAssembly(model)
            if model:IsA("Model") then
                model:PivotTo(CFrame.new(Vector3.new(out.X, pos.Y + 0.5, out.Z)))
            else
                mp.CFrame = CFrame.new(Vector3.new(out.X, pos.Y + 0.5, out.Z))
            end
            setCollide(model, true, snap0)

            mp   = mainPart(model) or mp
            pos  = mp.Position
            away = horiz(pos - fromPos)
            dist = away.Magnitude
            if dist < 1e-3 then
                away = Vector3.new(0, 0, 1)
            end
        end

        local dir        = unitOr(away, Vector3.new(0, 0, 1))
        local horizSpeed = math.clamp(Nudge.Dist, 10, 160) * 4.0
        local upSpeed    = math.clamp(Nudge.Up,   5,  80) * 7.0

        task.spawn(function()
            local started = preDrag(model)
            local snap    = setCollide(model, false)

            for _, p in ipairs(getParts(model)) do
                pcall(function()
                    p:SetNetworkOwner(lp)
                end)
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end

            local mass = math.max(mp:GetMass(), 1)

            pcall(function()
                mp:ApplyImpulse(
                    dir * horizSpeed * mass +
                    Vector3.new(0, upSpeed * mass, 0)
                )
            end)

            pcall(function()
                mp:ApplyAngularImpulse(Vector3.new(
                    (math.random() - 0.5) * 150,
                    (math.random() - 0.5) * 200,
                    (math.random() - 0.5) * 150
                ) * mass)
            end)

            mp.AssemblyLinearVelocity =
                dir * horizSpeed + Vector3.new(0, upSpeed, 0)

            task.delay(0.14, function()
                if started then
                    pcall(safeStopDrag, model)
                end
            end)

            task.delay(0.45, function()
                if snap then
                    setCollide(model, true, snap)
                end
            end)

            task.delay(0.9, function()
                for _, p in ipairs(getParts(model)) do
                    pcall(function()
                        p:SetNetworkOwner(nil)
                    end)
                    pcall(function()
                        if p.SetNetworkOwnershipAuto then
                            p:SetNetworkOwnershipAuto()
                        end
                    end)
                end
            end)
        end)
    end

    local function impulseNPC(mdl, fromPos)
        local r = charDistancePart(mdl)
        if not r then return end

        local pos  = r.Position
        local away = horiz(pos - fromPos)
        local dist = away.Magnitude

        if dist < Nudge.SelfSafe then
            away = unitOr(horiz(pos - fromPos), Vector3.new(0, 0, 1))
            pos  = fromPos + away * (Nudge.SelfSafe + 0.5)
        end

        local dir = unitOr(away, Vector3.new(0, 0, 1))
        local vel =
            dir * (math.clamp(Nudge.Dist, 10, 160) * 2.0) +
            Vector3.new(0, math.clamp(Nudge.Up, 5, 80) * 3.0, 0)

        pcall(function()
            r.AssemblyLinearVelocity = vel
        end)
    end

    local function nudgeShockwave(origin, radius)
        local myChar = lp.Character
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { myChar }

        local parts = WS:GetPartBoundsInRadius(origin, radius, params) or {}
        local seen  = {}

        for _, part in ipairs(parts) do
            if part:IsA("BasePart") and not part.Anchored then
                if myChar and part:IsDescendantOf(myChar) then
                else
                    local mdl = part:FindFirstAncestorOfClass("Model") or part
                    if not seen[mdl] then
                        seen[mdl] = true

                        if isCharacterModel(mdl) then
                            if isNPCModel(mdl) then
                                impulseNPC(mdl, origin)
                            end
                        else
                            impulseItem(mdl, origin)
                        end
                    end
                end
            end
        end
    end

    local Center = {
        ItemsEnabled    = false,
        NPCsEnabled     = false,
        TargetRadius    = 100,
        ItemMaxPerStep  = 40,
        NpcMaxPerStep   = 16,
        ItemAccel       = 25,
        NpcAccel        = 40,
        ItemMaxSpeed    = 160,
        NpcMaxSpeed     = 120,
        RescanInterval  = 3.0
    }

    local centerItems      = {}
    local centerNPCs       = {}
    local centerItemIdx    = 1
    local centerNPCIdx     = 1
    local rescanItemsAt    = 0
    local rescanNPCsAt     = 0

    local campModelCache = nil

    local function fireCenterPart(fire)
        return fire:FindFirstChild("Center")
            or fire:FindFirstChild("InnerTouchZone")
            or mainPart(fire)
            or fire.PrimaryPart
    end

    local function resolveCampfireModel()
        if campModelCache and campModelCache.Parent then
            return campModelCache
        end
        local map = WS:FindFirstChild("Map")
        local cg  = map and map:FindFirstChild("Campground")
        local mf  = cg and cg:FindFirstChild("MainFire")
        if mf then
            campModelCache = mf
            return mf
        end
        local best, bestDist = nil, math.huge
        local root = hrp()
        local rootPos = root and root.Position
        for _, d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") then
                local n = (d.Name or ""):lower()
                if n == "mainfire" or n == "campfire" or n == "camp fire" then
                    local mp = mainPart(d)
                    local p = mp and mp.Position or (pcall(d.GetPivot, d) and d:GetPivot().Position) or nil
                    if p and rootPos then
                        local dist = (p - rootPos).Magnitude
                        if dist < bestDist then
                            bestDist = dist
                            best = d
                        end
                    elseif p and not best then
                        best = d
                    end
                end
            end
        end
        campModelCache = best
        return best
    end

    local function campfireCenter()
        local fire = resolveCampfireModel()
        if not fire then return nil end
        local center = fireCenterPart(fire)
        if center and center:IsA("BasePart") then
            return center.Position
        end
        local mp = mainPart(fire)
        if mp then return mp.Position end
        local ok, cf = pcall(fire.GetPivot, fire)
        if ok and cf then
            return cf.Position
        end
        return nil
    end

    local function rebuildCenterItems()
        centerItems = {}
        local items = WS:FindFirstChild("Items")
        if not items then
            centerItemIdx = 1
            return
        end
        for _, m in ipairs(items:GetChildren()) do
            if m:IsA("Model") then
                centerItems[#centerItems+1] = m
            end
        end
        centerItemIdx = 1
    end

    local function rebuildCenterNPCs()
        centerNPCs = {}
        local chars = WS:FindFirstChild("Characters")
        if not chars then
            centerNPCIdx = 1
            return
        end
        for _, mdl in ipairs(chars:GetChildren()) do
            if isNPCModel(mdl) then
                centerNPCs[#centerNPCs+1] = mdl
            end
        end
        centerNPCIdx = 1
    end

    local function stepCenterItems()
        if not Center.ItemsEnabled then return end
        local campPos = campfireCenter()
        if not campPos then return end

        local now = os.clock()
        if now >= rescanItemsAt then
            rebuildCenterItems()
            rescanItemsAt = now + Center.RescanInterval
        end

        local count = #centerItems
        if count == 0 then return end

        local processed = 0
        while processed < Center.ItemMaxPerStep and count > 0 do
            if centerItemIdx > count then
                centerItemIdx = 1
            end
            local m = centerItems[centerItemIdx]
            centerItemIdx += 1
            processed += 1

            if m and m.Parent then
                local mp = mainPart(m)
                if mp and not mp.Anchored then
                    local toCamp = campPos - mp.Position
                    local horizVec = Vector3.new(toCamp.X, 0, toCamp.Z)
                    local dist = horizVec.Magnitude
                    if dist > Center.TargetRadius then
                        local dir = horizVec.Unit
                        local vel = mp.AssemblyLinearVelocity
                        local hv = Vector3.new(vel.X, 0, vel.Z) + dir * Center.ItemAccel
                        local hmag = hv.Magnitude
                        if hmag > Center.ItemMaxSpeed then
                            hv = hv.Unit * Center.ItemMaxSpeed
                        end
                        mp.AssemblyLinearVelocity = Vector3.new(hv.X, vel.Y, hv.Z)
                    end
                end
            end

            count = #centerItems
            if count == 0 then break end
        end
    end

    local function stepCenterNPCs()
        if not Center.NPCsEnabled then return end
        local campPos = campfireCenter()
        if not campPos then return end

        local now = os.clock()
        if now >= rescanNPCsAt then
            rebuildCenterNPCs()
            rescanNPCsAt = now + Center.RescanInterval
        end

        local count = #centerNPCs
        if count == 0 then return end

        local processed = 0
        while processed < Center.NpcMaxPerStep and count > 0 then
            if centerNPCIdx > count then
                centerNPCIdx = 1
            end
            local mdl = centerNPCs[centerNPCIdx]
            centerNPCIdx += 1
            processed += 1

            if mdl and mdl.Parent and isNPCModel(mdl) then
                local rootPart = charDistancePart(mdl)
                if rootPart then
                    local toCamp = campPos - rootPart.Position
                    local horizVec = Vector3.new(toCamp.X, 0, toCamp.Z)
                    local dist = horizVec.Magnitude
                    if dist > Center.TargetRadius then
                        local dir = horizVec.Unit
                        local vel = rootPart.AssemblyLinearVelocity
                        local hv = Vector3.new(vel.X, 0, vel.Z) + dir * Center.NpcAccel
                        local hmag = hv.Magnitude
                        if hmag > Center.NpcMaxSpeed then
                            hv = hv.Unit * Center.NpcMaxSpeed
                        end
                        rootPart.AssemblyLinearVelocity = Vector3.new(hv.X, vel.Y, hv.Z)
                    end
                end
            end

            count = #centerNPCs
            if count == 0 then break end
        end
    end

    local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
    local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
    if not edgeGui then
        edgeGui = Instance.new("ScreenGui")
        edgeGui.Name = "EdgeButtons"
        edgeGui.ResetOnSpawn = false
        pcall(function() edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
        edgeGui.Parent = playerGui
    end

    local stack = edgeGui:FindFirstChild("EdgeStack")
    if not stack then
        stack = Instance.new("Frame")
        stack.Name = "EdgeStack"
        stack.AnchorPoint = Vector2.new(1, 0)
        stack.Position = UDim2.new(1, -6, 0, 6)
        stack.Size = UDim2.new(0, 130, 1, -12)
        stack.BackgroundTransparency = 1
        stack.BorderSizePixel = 0
        stack.Parent = edgeGui
        local list = Instance.new("UIListLayout")
        list.Name = "VList"
        list.FillDirection = Enum.FillDirection.Vertical
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Padding = UDim.new(0, 6)
        list.HorizontalAlignment = Enum.HorizontalAlignment.Right
        list.Parent = stack
    end

    local function makeEdgeBtn(name, label, order)
        local b = stack:FindFirstChild(name)
        if not b then
            b = Instance.new("TextButton")
            b.Name = name
            b.Size = UDim2.new(1, 0, 0, 30)
            b.Text = label
            b.TextSize = 12
            b.Font = Enum.Font.GothamBold
            b.BackgroundColor3 = Color3.fromRGB(30,30,35)
            b.TextColor3 = Color3.new(1,1,1)
            b.BorderSizePixel = 0
            b.Visible = false
            b.LayoutOrder = order or 1
            b.Parent = stack
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 8)
            corner.Parent = b
        else
            b.Text = label
            b.LayoutOrder = order or b.LayoutOrder
            b.Visible = false
        end
        return b
    end

    local shockBtn = makeEdgeBtn("ShockwaveEdge", "Shockwave", 10)

    shockBtn.MouseButton1Click:Connect(function()
        local r = hrp()
        if r then
            nudgeShockwave(r.Position, Nudge.Radius)
        end
    end)

    C.State = C.State or { Toggles = {} }
    C.State.Toggles = C.State.Toggles or {}

    local initialEdge       = (C.State.Toggles.EdgeShockwave == true)
    local initialCenterItems = (C.State.Toggles.CenterItems == true)
    local initialCenterNPCs  = (C.State.Toggles.CenterNPCs == true)

    shockBtn.Visible = initialEdge
    Center.ItemsEnabled = initialCenterItems
    Center.NPCsEnabled  = initialCenterNPCs

    tab:Section({ Title = "Shockwave Nudge" })

    tab:Toggle({
        Title = "Edge Button: Shockwave",
        Value = initialEdge,
        Callback = function(v)
            local on = (v == true)
            C.State.Toggles.EdgeShockwave = on
            if shockBtn then
                shockBtn.Visible = on
            end
        end
    })

    tab:Slider({
        Title = "Nudge Distance",
        Value = { Min = 10, Max = 160, Default = Nudge.Dist },
        Callback = function(v)
            local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
            if n then
                Nudge.Dist = math.clamp(math.floor(n + 0.5), 10, 160)
            end
        end
    })

    tab:Slider({
        Title = "Nudge Height",
        Value = { Min = 5, Max = 80, Default = Nudge.Up },
        Callback = function(v)
            local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
            if n then
                Nudge.Up = math.clamp(math.floor(n + 0.5), 5, 80)
            end
        end
    })

    tab:Slider({
        Title = "Nudge Radius",
        Value = { Min = 5, Max = 60, Default = Nudge.Radius },
        Callback = function(v)
            local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
            if n then
                Nudge.Radius = math.clamp(math.floor(n + 0.5), 5, 60)
            end
        end
    })

    tab:Toggle({
        Title = "Auto Nudge (within Radius)",
        Value = AutoNudge.Enabled,
        Callback = function(on)
            AutoNudge.Enabled = (on == true)
        end
    })

    tab:Section({ Title = "Center Nudge (to Campfire)" })

    tab:Toggle({
        Title = "Nudge Items to Center",
        Value = initialCenterItems,
        Callback = function(on)
            local v = (on == true)
            Center.ItemsEnabled = v
            C.State.Toggles.CenterItems = v
        end
    })

    tab:Toggle({
        Title = "Nudge NPCs to Center",
        Value = initialCenterNPCs,
        Callback = function(on)
            local v = (on == true)
            Center.NPCsEnabled = v
            C.State.Toggles.CenterNPCs = v
        end
    })

    local autoConn
    if autoConn then
        autoConn:Disconnect()
        autoConn = nil
    end

    autoConn = Run.Heartbeat:Connect(function()
        local root = hrp()
        if AutoNudge.Enabled and root then
            nudgeShockwave(root.Position, Nudge.Radius)
        end
        if Center.ItemsEnabled or Center.NPCsEnabled then
            stepCenterItems()
            stepCenterNPCs()
        end
    end)
end
