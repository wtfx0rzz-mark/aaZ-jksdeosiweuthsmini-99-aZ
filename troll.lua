-- troll.lua
return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI

    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")

    local lp = Players.LocalPlayer
    local Tabs = (UI and UI.Tabs) or {}
    local tab  = Tabs.Troll or Tabs.Main or Tabs.Auto
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
            for _,d in ipairs(target:GetDescendants()) do
                if d:IsA("BasePart") then t[#t+1] = d end
            end
        end
        return t
    end
    local function setCollide(model, on, snap)
        local parts = getParts(model)
        if on and snap then
            for part,can in pairs(snap) do if part and part.Parent then part.CanCollide = can end end
            return
        end
        local s = {}
        for _,p in ipairs(parts) do s[p]=p.CanCollide; p.CanCollide=false end
        return s
    end
    local function safeStartDrag(model)
        local re = RS:FindFirstChild("RemoteEvents")
        local ev = re and (re:FindFirstChild("RequestStartDraggingItem") or re:FindFirstChild("StartDraggingItem"))
        if ev and model and model.Parent then pcall(function() ev:FireServer(model) end) return true end
        return false
    end
    local function safeStopDrag(model)
        local re = RS:FindFirstChild("RemoteEvents")
        local ev = re and (re:FindFirstChild("RequestStopDraggingItem") or re:FindFirstChild("StopDraggingItem"))
        if ev and model and model.Parent then pcall(function() ev:FireServer(model) end) return true end
        return false
    end
    local function finallyStopDrag(model)
        task.delay(0.05, function() pcall(safeStopDrag, model) end)
        task.delay(0.20, function() pcall(safeStopDrag, model) end)
    end
    local function zeroAssembly(model)
        for _,p in ipairs(getParts(model)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
    end

    local function isCharacterModel(m)
        return m and m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") ~= nil
    end
    local function charDistancePart(m)
        if not (m and m:IsA("Model")) then return nil end
        local h = m:FindFirstChild("HumanoidRootPart")
        if h and h:IsA("BasePart") then return h end
        local pp = m.PrimaryPart
        if pp and pp:IsA("BasePart") then return pp end
        return nil
    end
    local function collectNPCsInRadius(origin, radius)
        local out = {}
        local chars = WS:FindFirstChild("Characters")
        if not chars then return out end
        for _, mdl in ipairs(chars:GetChildren()) do
            repeat
                if not isCharacterModel(mdl) then break end
                if Players:GetPlayerFromCharacter(mdl) then break end
                local n = (mdl.Name or ""):lower()
                if n:find("horse", 1, true) then break end
                local dpart = charDistancePart(mdl); if not dpart then break end
                if (dpart.Position - origin).Magnitude > radius then break end
                out[#out+1] = mdl
            until true
        end
        return out
    end

    local function horiz(v) return Vector3.new(v.X, 0, v.Z) end
    local function unitOr(v, fallback)
        local m = v.Magnitude
        if m > 1e-3 then return v / m end
        return fallback
    end

    local Nudge = {
        Dist = 50,  -- horizontal flight target (studs)
        Up   = 20,  -- upward flight target (studs)
    }

    local AutoNudge = {
        Enabled = false,
        Radius  = 15.0,
        MaxPerFrame = 16
    }

    local function impulseItem(model, fromPos)
        local mp = mainPart(model); if not mp then return end
        local dir = horiz(mp.Position - fromPos); dir = unitOr(dir, Vector3.new(0,0,1))
        local horizSpeed = math.clamp(Nudge.Dist, 10, 120) * 4.0
        local upSpeed    = math.clamp(Nudge.Up,   5,  60) * 7.0
        task.spawn(function()
            pcall(safeStartDrag, model)
            local snap = setCollide(model, false)
            for _,p in ipairs(getParts(model)) do
                pcall(function() p:SetNetworkOwner(lp) end)
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end
            local mass = math.max(mp:GetMass(), 1)
            pcall(function()
                mp:ApplyImpulse(dir * horizSpeed * mass + Vector3.new(0, upSpeed * mass, 0))
            end)
            pcall(function()
                mp:ApplyAngularImpulse(Vector3.new(
                    (math.random()-0.5)*150,
                    (math.random()-0.5)*200,
                    (math.random()-0.5)*150
                ) * mass)
            end)
            mp.AssemblyLinearVelocity = dir * horizSpeed + Vector3.new(0, upSpeed, 0)
            task.delay(0.12, function() pcall(safeStopDrag, model) end)
            task.delay(0.32, function() if snap then setCollide(model, true, snap) end end)
            task.delay(0.9, function()
                for _,p in ipairs(getParts(model)) do
                    pcall(function() p:SetNetworkOwner(nil) end)
                    pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
                end
            end)
        end)
    end

    local function impulseNPC(mdl, fromPos)
        local r = charDistancePart(mdl); if not r then return end
        local dir = horiz(r.Position - fromPos); dir = unitOr(dir, Vector3.new(0,0,1))
        local before = r.AssemblyLinearVelocity
        pcall(function()
            r.AssemblyLinearVelocity = dir * (math.clamp(Nudge.Dist,10,120) * 2.0) + Vector3.new(0, math.clamp(Nudge.Up,5,60) * 3.0, 0)
        end)
        task.delay(0.05, function()
            if (r.AssemblyLinearVelocity - before).Magnitude < 1 then
                -- server likely enforcing; nothing else to do for NPCs beyond Characters scope
            end
        end)
    end

    local function nudgeShockwave(origin, itemRadius, npcRadius, maxItems)
        local myRoot = hrp(); if not myRoot then return end
        origin = origin or myRoot.Position
        itemRadius = itemRadius or 22
        npcRadius  = npcRadius  or 22
        maxItems   = maxItems   or 64

        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }

        local parts = WS:GetPartBoundsInRadius(origin, itemRadius, params) or {}
        local seen = {}
        local pushed = 0
        for _, part in ipairs(parts) do
            if pushed >= maxItems then break end
            if part:IsA("BasePart") then
                local mdl = part:FindFirstAncestorOfClass("Model") or part
                if not seen[mdl] then
                    seen[mdl] = true
                    if not isCharacterModel(mdl) then
                        local p = mainPart(mdl)
                        if p and (p.Position - origin).Magnitude <= itemRadius then
                            local totalMass, count, anchored = 0, 0, false
                            for _,pp in ipairs(getParts(mdl)) do
                                count += 1
                                totalMass += pp:GetMass()
                                if pp.Anchored then anchored = true break end
                                if count > 80 then break end
                            end
                            if not anchored and count <= 80 and totalMass <= 200 then
                                impulseItem(mdl, origin)
                                pushed += 1
                            end
                        end
                    end
                end
            end
        end

        local npcs = collectNPCsInRadius(origin, npcRadius)
        for _, m in ipairs(npcs) do
            impulseNPC(m, origin)
        end
    end

    local edgeBtnId = nil
    local function ensureEdgeButton(on)
        local Edge = UI and UI.EdgeButtons
        if not Edge then return end
        if on and not edgeBtnId then
            edgeBtnId = Edge:Add({
                Title = "Shockwave",
                Callback = function()
                    local r = hrp()
                    if r then nudgeShockwave(r.Position) end
                end
            })
        elseif (not on) and edgeBtnId then
            pcall(function() Edge:Remove(edgeBtnId) end)
            edgeBtnId = nil
        end
    end

    tab:Section({ Title = "Shockwave Nudge" })

    tab:Toggle({
        Title = "Edge Button: Shockwave",
        Value = C.State and C.State.Toggles and C.State.Toggles.EdgeShockwave or false,
        Callback = function(on)
            C.State = C.State or { Toggles = {} }
            C.State.Toggles = C.State.Toggles or {}
            C.State.Toggles.EdgeShockwave = on and true or false
            ensureEdgeButton(on)
        end
    })

    tab:Button({
        Title = "Shockwave Now",
        Callback = function()
            local r = hrp()
            if r then nudgeShockwave(r.Position) end
        end
    })

    tab:Slider({
        Title = "Nudge Distance",
        Value = { Min = 10, Max = 120, Default = Nudge.Dist },
        Callback = function(v)
            local n = tonumber(type(v)=="table" and (v.Value or v.Current or v.Default) or v)
            if n then Nudge.Dist = math.clamp(math.floor(n+0.5), 10, 120) end
        end
    })
    tab:Slider({
        Title = "Nudge Height",
        Value = { Min = 5, Max = 60, Default = Nudge.Up },
        Callback = function(v)
            local n = tonumber(type(v)=="table" and (v.Value or v.Current or v.Default) or v)
            if n then Nudge.Up = math.clamp(math.floor(n+0.5), 5, 60) end
        end
    })

    tab:Toggle({
        Title = "Auto Nudge (15 studs)",
        Value = AutoNudge.Enabled,
        Callback = function(on)
            AutoNudge.Enabled = (on == true)
        end
    })

    local autoConn
    if autoConn then autoConn:Disconnect() autoConn=nil end
    autoConn = Run.Heartbeat:Connect(function()
        if not AutoNudge.Enabled then return end
        local r = hrp(); if not r then return end
        local origin = r.Position
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(origin, AutoNudge.Radius, params) or {}
        local seen = {}
        local nudged = 0
        for _, part in ipairs(parts) do
            if nudged >= AutoNudge.MaxPerFrame then break end
            if part:IsA("BasePart") then
                local mdl = part:FindFirstAncestorOfClass("Model") or part
                if not seen[mdl] then
                    seen[mdl] = true
                    if isCharacterModel(mdl) then
                        if not Players:GetPlayerFromCharacter(mdl) then
                            impulseNPC(mdl, origin)
                            nudged += 1
                        end
                    else
                        local p = mainPart(mdl)
                        if p then
                            local totalMass, count, anchored = 0, 0, false
                            for _,pp in ipairs(getParts(mdl)) do
                                count += 1
                                totalMass += pp:GetMass()
                                if pp.Anchored then anchored = true break end
                                if count > 80 then break end
                            end
                            if not anchored and count <= 80 and totalMass <= 200 then
                                impulseItem(mdl, origin)
                                nudged += 1
                            end
                        end
                    end
                end
            end
        end
    end)

    ensureEdgeButton(C.State and C.State.Toggles and C.State.Toggles.EdgeShockwave)
end
