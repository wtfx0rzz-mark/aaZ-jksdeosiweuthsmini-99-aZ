-- nudge.lua
return function(C, R, UI)
    local function run()
        C  = C  or _G.C
        UI = UI or _G.UI

        local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
        local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
        local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
        local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")
        local lp       = Players.LocalPlayer

        local Tabs = (UI and UI.Tabs) or {}
        local tab  = Tabs.Nudge or Tabs.Main or Tabs.Auto
        if not tab then return end

        -- basic helpers
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

        -- config
        local Nudge = {
            Dist     = 50,
            Up       = 20,
            Radius   = 15,
            SelfSafe = 3.5
        }

        local AutoNudge = {
            Enabled     = false,
            MaxPerFrame = 16
        }

        local CenterCfg = {
            StopRadius       = 100,  -- stop once inside this radius
            ItemSearchRadius = 450,
            NPCSearchRadius  = 450,
            ItemPushDist     = 40,   -- horiz speed toward campfire
            ItemPushUp       = 8,    -- up-speed for items
            NPCPushDist      = 35,   -- horiz speed toward campfire
            NPCPushUp        = 12,   -- up-speed for NPCs
            MaxItemsPerStep  = 40,
            MaxNPCsPerStep   = 20
        }

        local centerItemsOn = false
        local centerNPCsOn  = false

        local function preDrag(model)
            local started = safeStartDrag(model)
            if started then
                task.wait(0.02)
            end
            return started
        end

        -- outward shockwave item impulse (away from origin)
        local function impulseItem(model, fromPos)
            local mp = mainPart(model)
            if not mp then return end

            local pos  = mp.Position
            local away = horiz(pos - fromPos)
            local dist = away.Magnitude
            if dist < 1e-3 then return end

            -- keep items from spawning directly inside us
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

        -- outward shockwave NPC impulse
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
                        -- skip self
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

        -- campfire resolution
        local function fireCenterPart(fire)
            return fire:FindFirstChild("Center")
                or fire:FindFirstChild("InnerTouchZone")
                or mainPart(fire)
                or fire.PrimaryPart
        end

        local campCache
        local function resolveCampfireModel()
            if campCache and campCache.Parent then
                return campCache
            end
            local map = WS:FindFirstChild("Map")
            local cg  = map and map:FindFirstChild("Campground")
            local mf  = cg and cg:FindFirstChild("MainFire")
            if mf then
                campCache = mf
                return campCache
            end
            local best, bestDist
            local root = hrp()
            for _, d in ipairs(WS:GetDescendants()) do
                if d:IsA("Model") then
                    local n = (d.Name or ""):lower()
                    if n == "mainfire" or n == "campfire" or n == "camp fire" then
                        local mp = mainPart(d)
                        if mp and root then
                            local dist = (mp.Position - root.Position).Magnitude
                            if not bestDist or dist < bestDist then
                                bestDist, best = dist, d
                            end
                        else
                            best = d
                        end
                    end
                end
            end
            campCache = best
            return campCache
        end

        local function campfireCenterPos()
            local fire = resolveCampfireModel()
            if not fire then return nil end
            local c = fireCenterPart(fire)
            if c and c:IsA("BasePart") then
                return c.Position
            end
            local ok, cf = pcall(function() return fire:GetPivot() end)
            return ok and cf.Position or nil
        end

        ----------------------------------------------------------------
        -- CENTER-PULL IMPLEMENTATION (toward campfire)
        ----------------------------------------------------------------

        local function centerImpulseItem(model, centerPos)
            local mp = mainPart(model)
            if not mp or mp.Anchored then return end

            local pos  = mp.Position
            local dir3 = horiz(centerPos - pos)
            local dist = dir3.Magnitude
            if dist < 1e-3 then return end

            local dir = dir3.Unit
            local horizSpeed = CenterCfg.ItemPushDist
            local upSpeed    = CenterCfg.ItemPushUp

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
                        (math.random() - 0.5) * 80,
                        (math.random() - 0.5) * 120,
                        (math.random() - 0.5) * 80
                    ) * mass)
                end)

                mp.AssemblyLinearVelocity =
                    dir * horizSpeed + Vector3.new(0, upSpeed, 0)

                task.delay(0.12, function()
                    if started then
                        pcall(safeStopDrag, model)
                    end
                end)

                task.delay(0.4, function()
                    if snap then
                        setCollide(model, true, snap)
                    end
                end)

                task.delay(0.8, function()
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

        local function centerImpulseNPC(mdl, centerPos)
            local r = charDistancePart(mdl)
            if not r then return end
            local pos  = r.Position
            local dir3 = horiz(centerPos - pos)
            local dist = dir3.Magnitude
            if dist < 1e-3 then return end

            local dir = dir3.Unit
            local horizSpeed = CenterCfg.NPCPushDist
            local upSpeed    = CenterCfg.NPCPushUp

            pcall(function()
                r.AssemblyLinearVelocity =
                    dir * horizSpeed + Vector3.new(0, upSpeed, 0)
            end)
        end

        local function centerStepItems(centerPos)
            local itemsFolder = WS:FindFirstChild("Items")
            if not itemsFolder then return end
            local processed = 0

            for _, m in ipairs(itemsFolder:GetChildren()) do
                if processed >= CenterCfg.MaxItemsPerStep then break end
                if m:IsA("Model") then
                    local mp = mainPart(m)
                    if mp and not mp.Anchored then
                        local off  = horiz(mp.Position - centerPos)
                        local dist = off.Magnitude
                        if dist > CenterCfg.StopRadius and dist < CenterCfg.ItemSearchRadius then
                            centerImpulseItem(m, centerPos)
                            processed += 1
                        end
                    end
                end
            end
        end

        local function centerStepNPCs(centerPos)
            local chars = WS:FindFirstChild("Characters")
            if not chars then return end
            local processed = 0

            for _, m in ipairs(chars:GetChildren()) do
                if processed >= CenterCfg.MaxNPCsPerStep then break end
                if isNPCModel(m) then
                    local r = charDistancePart(m)
                    if r then
                        local off  = horiz(r.Position - centerPos)
                        local dist = off.Magnitude
                        if dist > CenterCfg.StopRadius and dist < CenterCfg.NPCSearchRadius then
                            centerImpulseNPC(m, centerPos)
                            processed += 1
                        end
                    end
                end
            end
        end

        ----------------------------------------------------------------
        -- EDGE BUTTON WIRING (Shockwave)
        ----------------------------------------------------------------

        local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
        local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
        if not edgeGui then
            edgeGui = Instance.new("ScreenGui")
            edgeGui.Name = "EdgeButtons"
            edgeGui.ResetOnSpawn = false
            pcall(function()
                edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            end)
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
                b.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
                b.TextColor3 = Color3.new(1, 1, 1)
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

        local shockBtn      = makeEdgeBtn("ShockwaveEdge", "Shockwave", 20)
        local showShockEdge = false
        shockBtn.Visible    = showShockEdge

        ----------------------------------------------------------------
        -- UI: Shockwave + Auto Nudge
        ----------------------------------------------------------------

        tab:Section({ Title = "Shockwave Nudge" })

        tab:Toggle({
            Title = "Edge Button: Shockwave",
            Value = false,
            Callback = function(state)
                showShockEdge = state and true or false
                if shockBtn then
                    shockBtn.Visible = showShockEdge
                end
            end
        })

        shockBtn.MouseButton1Click:Connect(function()
            local r = hrp()
            if r then
                nudgeShockwave(r.Position, Nudge.Radius)
            end
        end)

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

        ----------------------------------------------------------------
        -- UI: Center Pull
        ----------------------------------------------------------------

        tab:Section({ Title = "Center Pull to Campfire" })

        tab:Toggle({
            Title = "Nudge Items Toward Campfire",
            Value = false,
            Callback = function(on)
                centerItemsOn = (on == true)
            end
        })

        tab:Toggle({
            Title = "Nudge NPCs Toward Campfire",
            Value = false,
            Callback = function(on)
                centerNPCsOn = (on == true)
            end
        })

        tab:Slider({
            Title = "Center Stop Radius",
            Value = { Min = 50, Max = 200, Default = CenterCfg.StopRadius },
            Callback = function(v)
                local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
                if n then
                    CenterCfg.StopRadius = math.clamp(math.floor(n + 0.5), 20, 400)
                end
            end
        })

        ----------------------------------------------------------------
        -- Heartbeat loop
        ----------------------------------------------------------------

        local hbConn
        if hbConn then
            hbConn:Disconnect()
            hbConn = nil
        end

        hbConn = Run.Heartbeat:Connect(function()
            local r = hrp()
            if AutoNudge.Enabled and r then
                nudgeShockwave(r.Position, Nudge.Radius)
            end

            if centerItemsOn or centerNPCsOn then
                local cpos = campfireCenterPos()
                if cpos then
                    if centerItemsOn then
                        centerStepItems(cpos)
                    end
                    if centerNPCsOn then
                        centerStepNPCs(cpos)
                    end
                end
            end
        end)

        Players.LocalPlayer.CharacterAdded:Connect(function()
            task.defer(function()
                local pg = lp:WaitForChild("PlayerGui")
                local eg = pg:FindFirstChild("EdgeButtons")
                if eg and edgeGui and edgeGui.Parent ~= pg then
                    edgeGui.Parent = pg
                end
                if shockBtn then
                    shockBtn.Visible = showShockEdge
                end
            end)
        end)
    end

    local ok, err = pcall(run)
    if not ok then
        warn("[Nudge] module error: " .. tostring(err))
    end
end
