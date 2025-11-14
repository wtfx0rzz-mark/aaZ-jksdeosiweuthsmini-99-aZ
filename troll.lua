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
    local function zeroAssembly(model)
        for _,p in ipairs(getParts(model)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
    end

    local function getRemote(...)
        local re = RS:FindFirstChild("RemoteEvents"); if not re then return nil end
        for _,n in ipairs({...}) do local x=re:FindFirstChild(n); if x then return x end end
        return nil
    end
    local REM = { StartDrag=nil, StopDrag=nil }
    local function resolveRemotes()
        REM.StartDrag = getRemote("RequestStartDraggingItem","StartDraggingItem")
        REM.StopDrag  = getRemote("StopDraggingItem","RequestStopDraggingItem")
    end
    resolveRemotes()

    local function safeStartDrag(model)
        if REM.StartDrag and model and model.Parent then
            pcall(function() REM.StartDrag:FireServer(model) end)
            return true
        end
        return false
    end
    local function safeStopDrag(model)
        if REM.StopDrag and model and model.Parent then
            pcall(function() REM.StopDrag:FireServer(model) end)
            return true
        end
        return false
    end
    local function finallyStopDrag(model)
        task.delay(0.05, function() pcall(safeStopDrag, model) end)
        task.delay(0.20, function() pcall(safeStopDrag, model) end)
    end

    local function isCharacterModel(m)
        return m and m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") ~= nil
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
    local function collectNPCsInRadius(origin, radius)
        local out = {}
        local chars = WS:FindFirstChild("Characters")
        if not chars then return out end
        for _, mdl in ipairs(chars:GetChildren()) do
            if isNPCModel(mdl) then
                local dpart = charDistancePart(mdl)
                if dpart and (dpart.Position - origin).Magnitude <= radius then
                    out[#out+1] = mdl
                end
            end
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
        Dist = 50,
        Up   = 20,
        Radius = 15,     -- configurable radius for shockwave/auto
        SelfSafe = 3.5,  -- minimum gap from me before impulse
    }

    local AutoNudge = {
        Enabled = false,
        MaxPerFrame = 16
    }

    local function preDrag(model)
        local started = safeStartDrag(model)
        if started then task.wait(0.02) end
        return started
    end

    local function impulseItem(model, fromPos)
        local mp = mainPart(model); if not mp then return end
        local pos = mp.Position
        local away = horiz(pos - fromPos)
        local dist = away.Magnitude
        if dist < 1e-3 then return end
        if dist < Nudge.SelfSafe then
            local out = fromPos + away.Unit * (Nudge.SelfSafe + 0.5)
            local snap0 = setCollide(model, false)
            zeroAssembly(model)
            if model:IsA("Model") then model:PivotTo(CFrame.new(Vector3.new(out.X, pos.Y + 0.5, out.Z))) else mp.CFrame = CFrame.new(Vector3.new(out.X, pos.Y + 0.5, out.Z)) end
            setCollide(model, true, snap0)
            pos = (mainPart(model) or mp).Position
            away = horiz(pos - fromPos)
            dist = away.Magnitude
            if dist < 1e-3 then away = Vector3.new(0,0,1) end
        end
        local dir = unitOr(away, Vector3.new(0,0,1))
        local horizSpeed = math.clamp(Nudge.Dist, 10, 160) * 4.0
        local upSpeed    = math.clamp(Nudge.Up,   5,  80) * 7.0

        task.spawn(function()
            local started = preDrag(model)
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
            task.delay(0.14, function() if started then pcall(safeStopDrag, model) end end)
            task.delay(0.45, function() if snap then setCollide(model, true, snap) end end)
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
        local pos = r.Position
        local away = horiz(pos - fromPos)
        local dist = away.Magnitude
        if dist < Nudge.SelfSafe then
            away = unitOr(horiz((pos - fromPos)), Vector3.new(0,0,1))
            pos = fromPos + away * (Nudge.SelfSafe + 0.5)
        end
        local dir = unitOr(away, Vector3.new(0,0,1))
        local vel = dir * (math.clamp(Nudge.Dist,10,160) * 2.0) + Vector3.new(0, math.clamp(Nudge.Up,5,80) * 3.0, 0)
        pcall(function() r.AssemblyLinearVelocity = vel end)
    end

    local function nudgeShockwave(origin, radius)
        local myChar = lp.Character
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { myChar }

        local parts = WS:GetPartBoundsInRadius(origin, radius, params) or {}
        local seen = {}
        for _, part in ipairs(parts) do
            if not part:IsA("BasePart") then continue end
            local mdl = part:FindFirstAncestorOfClass("Model") or part
            if seen[mdl] then continue end
            seen[mdl] = true

            if isCharacterModel(mdl) then
                if isNPCModel(mdl) then impulseNPC(mdl, origin) end
            else
                impulseItem(mdl, origin)
            end
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
                    if r then nudgeShockwave(r.Position, Nudge.Radius) end
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

    tab:Slider({
        Title = "Nudge Distance",
        Value = { Min = 10, Max = 160, Default = Nudge.Dist },
        Callback = function(v)
            local n = tonumber(type(v)=="table" and (v.Value or v.Current or v.Default) or v)
            if n then Nudge.Dist = math.clamp(math.floor(n+0.5), 10, 160) end
        end
    })
    tab:Slider({
        Title = "Nudge Height",
        Value = { Min = 5, Max = 80, Default = Nudge.Up },
        Callback = function(v)
            local n = tonumber(type(v)=="table" and (v.Value or v.Current or v.Default) or v)
            if n then Nudge.Up = math.clamp(math.floor(n+0.5), 5, 80) end
        end
    })
    tab:Slider({
        Title = "Nudge Radius",
        Value = { Min = 5, Max = 60, Default = Nudge.Radius },
        Callback = function(v)
            local n = tonumber(type(v)=="table" and (v.Value or v.Current or v.Default) or v)
            if n then Nudge.Radius = math.clamp(math.floor(n+0.5), 5, 60) end
        end
    })

    tab:Toggle({
        Title = "Auto Nudge (within Radius)",
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
        nudgeShockwave(r.Position, Nudge.Radius)
    end)

    ensureEdgeButton(C.State and C.State.Toggles and C.State.Toggles.EdgeShockwave)
end
