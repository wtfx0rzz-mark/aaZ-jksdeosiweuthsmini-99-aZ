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
    assert(tab, "Troll tab not found in UI")

    -- Search/selection
    local MAX_LOGS       = 50
    local SEARCH_RADIUS  = 200

    -- Motion
    local TICK              = 0.03
    local FLOAT_RADIUS_MIN  = 3.0
    local FLOAT_RADIUS_MAX  = 7.5
    local ANGULAR_SPEED_MIN = 0.7
    local ANGULAR_SPEED_MAX = 1.8

    -- Height: orbit around torso level, small wobble
    local HEIGHT_BASE      = 1.25   -- studs above HRP
    local HEIGHT_WOBBLE    = 0.35   -- +/- wobble
    local HEIGHT_WOBBLE_HZ = 0.6

    -- Drag and safety
    local DRAG_SETTLE     = 0.06
    local JOB_TIMEOUT_S   = 90
    local REASSIGN_IF_LOST_S = 2.0

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
    local function getAllParts(target)
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
    local function setCollide(model, on, snapshot)
        local parts = getAllParts(model)
        if on and snapshot then
            for part,can in pairs(snapshot) do
                if part and part.Parent then part.CanCollide = can end
            end
            return
        end
        local snap = {}
        for _,p in ipairs(parts) do snap[p]=p.CanCollide; p.CanCollide=false end
        return snap
    end
    local function zeroAssembly(model)
        for _,p in ipairs(getAllParts(model)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
    end

    local function getRemote(...)
        local re = RS:FindFirstChild("RemoteEvents"); if not re then return nil end
        for _,n in ipairs({...}) do local x=re:FindFirstChild(n); if x then return x end end
        return nil
    end
    local function resolveRemotes()
        return {
            StartDrag = getRemote("RequestStartDraggingItem","StartDraggingItem"),
            StopDrag  = getRemote("StopDraggingItem","RequestStopDraggingItem"),
        }
    end
    local function safeStartDrag(r, model)
        if r and r.StartDrag and model and model.Parent then
            pcall(function() r.StartDrag:FireServer(model) end)
            return true
        end
        return false
    end
    local function safeStopDrag(r, model)
        if r and r.StopDrag and model and model.Parent then
            pcall(function() r.StopDrag:FireServer(model) end)
            return true
        end
        return false
    end
    local function finallyStopDrag(r, model)
        task.delay(0.05, function() pcall(safeStopDrag, r, model) end)
        task.delay(0.20, function() pcall(safeStopDrag, r, model) end)
    end

    local function logsNearMe(maxCount)
        local root = hrp(); if not root then return {} end
        local center = root.Position
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(center, SEARCH_RADIUS, params) or {}
        local items = {}
        local uniq  = {}
        for _,part in ipairs(parts) do
            if part:IsA("BasePart") then
                local m = part:FindFirstAncestorOfClass("Model")
                if m and m.Name == "Log" and not uniq[m] then
                    local mp = mainPart(m)
                    if mp then
                        uniq[m] = true
                        items[#items+1] = {m=m, d=(mp.Position - center).Magnitude}
                    end
                end
            end
        end
        table.sort(items, function(a,b) return a.d < b.d end)
        local out = {}
        for i=1, math.min(maxCount, #items) do out[#out+1] = items[i].m end
        return out
    end

    local function playerChoices()
        local vals = {}
        for _,p in ipairs(Players:GetPlayers()) do
            if p ~= lp then
                vals[#vals+1] = ("%s#%d"):format(p.Name, p.UserId)
            end
        end
        table.sort(vals)
        return vals
    end
    local function parseSelection(choice)
        local set = {}
        if type(choice) == "table" then
            for _,v in ipairs(choice) do
                local uid = tonumber((tostring(v):match("#(%d+)$") or ""))
                if uid then set[tostring(uid)] = true end
            end
        else
            local uid = tonumber((tostring(choice or ""):match("#(%d+)$") or ""))
            if uid then set[tostring(uid)] = true end
        end
        return set
    end
    local function selectedPlayersList(fromSet)
        local out = {}
        for userIdStr,_ in pairs(fromSet or {}) do
            local uid = tonumber(userIdStr)
            if uid then
                for _,p in ipairs(Players:GetPlayers()) do
                    if p.UserId == uid and p ~= lp then
                        out[#out+1] = p
                        break
                    end
                end
            end
        end
        return out
    end

    local running = false
    local activeJobs = {}
    local rcache     = resolveRemotes()

    local function setPivot(model, cf)
        if model:IsA("Model") then
            model:PivotTo(cf)
        else
            local p = mainPart(model); if p then p.CFrame = cf end
        end
    end

    -- Updated orbit: keep Y near target HRP + HEIGHT_BASE with a small wobble
    local function floatAroundTarget(model, targetPlayer, seed)
        local st = os.clock()
        local r  = math.random(FLOAT_RADIUS_MIN*100, FLOAT_RADIUS_MAX*100)/100
        local w  = math.random(ANGULAR_SPEED_MIN*100, ANGULAR_SPEED_MAX*100)/100
        local phase = (seed or 0) % (2*math.pi)
        activeJobs[model] = { stop = false }
        local jobRef = activeJobs[model]

        local started = safeStartDrag(rcache, model)
        task.wait(DRAG_SETTLE)
        local snap = setCollide(model, false)
        zeroAssembly(model)

        local lastSeen = os.clock()

        while running and jobRef == activeJobs[model] do
            local root = hrp(targetPlayer)
            if not root then
                if os.clock() - lastSeen > REASSIGN_IF_LOST_S then break end
            else
                lastSeen = os.clock()
                local base = root.Position
                local t = os.clock() - st
                local ang = phase + w * t
                local y  = base.Y + HEIGHT_BASE + math.sin(t * HEIGHT_WOBBLE_HZ) * HEIGHT_WOBBLE
                local pos = Vector3.new(
                    base.X + math.cos(ang) * r,
                    y,
                    base.Z + math.sin(ang) * r
                )
                local look = (base - pos).Unit
                setPivot(model, CFrame.new(pos, pos + look))
                for _,p in ipairs(getAllParts(model)) do
                    p.AssemblyLinearVelocity  = Vector3.new()
                    p.AssemblyAngularVelocity = Vector3.new()
                end
            end
            task.wait(TICK)
        end

        setCollide(model, true, snap)
        if started then finallyStopDrag(rcache, model) end
        activeJobs[model] = nil
    end

    local function startFloat(logs, targets)
        running = true
        activeJobs = {}

        if #targets == 0 or #logs == 0 then return end
        local idx = 1
        for i,mdl in ipairs(logs) do
            local tgt = targets[idx]
            task.spawn(function()
                floatAroundTarget(mdl, tgt, i*0.37)
            end)
            idx += 1
            if idx > #targets then idx = 1 end
        end
    end

    local function stopAll()
        running = false
        for m,_ in pairs(activeJobs) do
            if m and m.Parent then
                pcall(function()
                    for _,p in ipairs(getAllParts(m)) do
                        p.Anchored = false
                        p.AssemblyLinearVelocity  = Vector3.new()
                        p.AssemblyAngularVelocity = Vector3.new()
                        pcall(function() p:SetNetworkOwner(nil) end)
                        pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
                    end
                end)
            end
            activeJobs[m] = nil
        end
    end

    local selectedPlayers = {}

    tab:Section({ Title = "Troll: Orbit Logs Around Players" })
    local playerDD = tab:Dropdown({
        Title = "Players",
        Values = playerChoices(),
        Multi = true,
        AllowNone = true,
        Callback = function(choice)
            selectedPlayers = parseSelection(choice)
        end
    })
    tab:Button({
        Title = "Refresh Player List",
        Callback = function()
            local vals = playerChoices()
            if playerDD and playerDD.SetValues then
                playerDD:SetValues(vals)
            end
        end
    })
    tab:Button({
        Title = "Start",
        Callback = function()
            stopAll()
            local targets = selectedPlayersList(selectedPlayers)
            if #targets == 0 then return end
            local logs = logsNearMe(MAX_LOGS)
            if #logs == 0 then return end
            startFloat(logs, targets)
            task.delay(JOB_TIMEOUT_S, function() if running then stopAll() end end)
        end
    })
    tab:Button({
        Title = "Stop",
        Callback = function()
            stopAll()
        end
    })
end
