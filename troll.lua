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

    local TICK               = 0.02
    local DRAG_SETTLE        = 0.05
    local JOB_TIMEOUT_S      = 120
    local REASSIGN_IF_LOST_S = 2.0

    local RESLOT_EVERY_MIN   = 0.45
    local RESLOT_EVERY_MAX   = 1.20
    local BURST_CHANCE_PER_SEC = 0.15
    local BURST_DURATION     = 0.18
    local BURST_PUSH         = 6.5

    local SEARCH_RADIUS = 200

    local CAMPFIRE_AVOID_RADIUS = 35
    local SCRAPPER_AVOID_RADIUS = 35
    local AVOID_LIFT            = 15
    local AVOID_REEVAL_S        = 0.2

    local CFG = {
        Speed       = 1.0,
        TightMin    = 2.0,
        TightMax    = 9.0,
        HeightBase  = 0.5,
        HeightRange = 3.0,
        JitterScale = 1.0,
        MaxLogs     = 50,
    }

    local function cloudParams()
        return {
            Rmin = CFG.TightMin,
            Rmax = CFG.TightMax,
            Hbase = CFG.HeightBase,
            Hmin  = -math.abs(CFG.HeightRange)*0.66,
            Hmax  =  math.abs(CFG.HeightRange),
            JXZ1  = 1.4 * CFG.JitterScale,
            JXZ2  = 0.9 * CFG.JitterScale,
            JY1   = 0.9 * CFG.JitterScale,
            JY2   = 0.6 * CFG.JitterScale,
            Speed = CFG.Speed,
        }
    end

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
    local function setPivot(model, cf)
        if model:IsA("Model") then
            model:PivotTo(cf)
        else
            local p = mainPart(model); if p then p.CFrame = cf end
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
        local items, uniq = {}, {}
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

    local function findFirstModelByNames(names)
        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") then
                local n = (d.Name or ""):lower()
                for _,s in ipairs(names) do
                    if n == s or n:find(s, 1, true) then return d end
                end
            end
        end
        return nil
    end
    local function centerPart(m)
        if not m then return nil end
        return m:FindFirstChild("Center")
            or m:FindFirstChild("InnerTouchZone")
            or mainPart(m)
            or m.PrimaryPart
    end
    local function resolveCampfirePos()
        local m = findFirstModelByNames({ "mainfire", "campfire", "camp fire" })
        local c = centerPart(m)
        if c and c:IsA("BasePart") then return c.Position end
        if m then local ok,cf=pcall(function()return m:GetPivot() end); if ok then return cf.Position end end
        return nil
    end
    local function resolveScrapperPos()
        local m = findFirstModelByNames({ "scrapper", "scrap", "scrap yard", "scrapyard" })
        local c = centerPart(m)
        if c and c:IsA("BasePart") then return c.Position end
        if m then local ok,cf=pcall(function()return m:GetPivot() end); if ok then return cf.Position end end
        return nil
    end

    local function rngFor(seed)
        return Random.new(math.clamp(math.floor((seed or 0) * 100000) % 2147483647, 1, 2147483646))
    end
    local function pickCloudSlot(rng, P)
        local r  = rng:NextNumber(P.Rmin, P.Rmax)
        local th = rng:NextNumber(0, math.pi*2)
        local ph = rng:NextNumber(-0.85, 0.85)
        local x = r * math.cos(th) * math.cos(ph)
        local z = r * math.sin(th) * math.cos(ph)
        local y = P.Hbase + rng:NextNumber(P.Hmin, P.Hmax)
        return Vector3.new(x, y, z)
    end

    local running = false
    local activeJobs = {}
    local rcache     = resolveRemotes()

    local function floatAroundTarget(model, targetPlayer, seed)
        local started = safeStartDrag(rcache, model)
        task.wait(DRAG_SETTLE)
        local snap = setCollide(model, false)
        zeroAssembly(model)

        local rnd   = rngFor((seed or 0) + os.clock())
        local slot  = nil
        local reslotAt = 0
        local burstUntil = 0
        local burstDir   = 1
        local t0 = os.clock()
        local lastSeen = os.clock()
        local phases = {
            xz1 = math.random()*math.pi*2,
            xz2 = math.random()*math.pi*2,
            y1  = math.random()*math.pi*2,
            y2  = math.random()*math.pi*math.pi,
        }
        local w = {
            xz1 = math.random()*1.2 + 1.2,
            xz2 = math.random()*1.6 + 2.0,
            y1  = math.random()*1.0 + 1.0,
            y2  = math.random()*2.0 + 2.0,
        }

        local avoidCampPos, avoidScrapPos = nil, nil
        local lastAvoidCheck = 0

        activeJobs[model] = true
        while running and activeJobs[model] do
            local root = hrp(targetPlayer)
            local now = os.clock()
            if not root then
                if now - lastSeen > REASSIGN_IF_LOST_S then break end
            else
                lastSeen = now
                if now >= reslotAt or not slot then
                    slot = pickCloudSlot(rnd, cloudParams())
                    reslotAt = now + rnd:NextNumber(RESLOT_EVERY_MIN, RESLOT_EVERY_MAX)
                end
                if now >= burstUntil and rnd:NextNumber() < BURST_CHANCE_PER_SEC * TICK then
                    burstUntil = now + BURST_DURATION
                    burstDir   = (rnd:NextNumber() < 0.5) and -1 or 1
                end

                if now - lastAvoidCheck >= AVOID_REEVAL_S then
                    avoidCampPos = resolveCampfirePos()
                    avoidScrapPos = resolveScrapperPos()
                    lastAvoidCheck = now
                end

                local P = cloudParams()
                local base = root.Position
                local t = (now - t0) * P.Speed

                local jx = math.sin(t * w.xz1 + phases.xz1) * P.JXZ1
                         + math.cos(t * w.xz2 + phases.xz2) * P.JXZ2
                local jz = math.cos(t * w.xz1 * 0.8 + phases.xz1*0.7) * P.JXZ1
                         + math.sin(t * w.xz2 * 1.3 + phases.xz2*0.5) * P.JXZ2
                local jy = math.sin(t * w.y1  + phases.y1 ) * P.JY1
                         + math.cos(t * w.y2  + phases.y2 ) * P.JY2

                local off = slot + Vector3.new(jx, jy, jz)

                if now < burstUntil then
                    local dirToTarget = (base - (base + off)).Unit
                    off = off + dirToTarget * (BURST_PUSH * burstDir)
                end

                if avoidCampPos and (base - avoidCampPos).Magnitude <= CAMPFIRE_AVOID_RADIUS then
                    off = off + Vector3.new(0, AVOID_LIFT, 0)
                end
                if avoidScrapPos and (base - avoidScrapPos).Magnitude <= SCRAPPER_AVOID_RADIUS then
                    off = off + Vector3.new(0, AVOID_LIFT, 0)
                end

                local pos = base + off
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
        if #targets == 0 or #logs == 0 then return end
        running = true
        activeJobs = {}
        local idx = 1
        for i,mdl in ipairs(logs) do
            local tgt = targets[idx]
            task.spawn(function() floatAroundTarget(mdl, tgt, i*0.73) end)
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

    tab:Section({ Title = "Troll: Chaotic Log Smog" })
    local selectedPlayers = {}
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
            if playerDD and playerDD.SetValues then playerDD:SetValues(vals) end
        end
    })
    do
        local function autoRefresh()
            while true do
                task.wait(2.0)
                local vals = playerChoices()
                if playerDD and playerDD.SetValues then playerDD:SetValues(vals) end
            end
        end
        task.spawn(autoRefresh)
        Players.PlayerAdded:Connect(function()
            local vals = playerChoices()
            if playerDD and playerDD.SetValues then playerDD:SetValues(vals) end
        end)
        Players.PlayerRemoving:Connect(function()
            local vals = playerChoices()
            if playerDD and playerDD.SetValues then playerDD:SetValues(vals) end
        end)
    end

    tab:Button({
        Title = "Start",
        Callback = function()
            stopAll()
            local targets = selectedPlayersList(selectedPlayers)
            if #targets == 0 then return end
            local logs = logsNearMe(CFG.MaxLogs)
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

    tab:Section({ Title = "Chaos Tuning" })
    tab:Slider({
        Title = "Speed",
        Value = { Min = 0.5, Max = 3.0, Default = CFG.Speed },
        Callback = function(v) local x=tonumber(v.Value or v); if x then CFG.Speed=x end end
    })
    tab:Slider({
        Title = "Tightness (Inner Radius)",
        Value = { Min = 1, Max = 6, Default = CFG.TightMin },
        Callback = function(v) local x=tonumber(v.Value or v); if x then CFG.TightMin=math.clamp(x,0.5,CFG.TightMax-0.25) end end
    })
    tab:Slider({
        Title = "Tightness (Outer Radius)",
        Value = { Min = 4, Max = 18, Default = CFG.TightMax },
        Callback = function(v) local x=tonumber(v.Value or v); if x then CFG.TightMax=math.max(x,CFG.TightMin+0.25) end end
    })
    tab:Slider({
        Title = "Height Bias",
        Value = { Min = -3, Max = 3, Default = CFG.HeightBase },
        Callback = function(v) local x=tonumber(v.Value or v); if x then CFG.HeightBase=x end end
    })
    tab:Slider({
        Title = "Height Spread",
        Value = { Min = 0.5, Max = 8, Default = CFG.HeightRange },
        Callback = function(v) local x=tonumber(v.Value or v); if x then CFG.HeightRange=x end end
    })
    tab:Slider({
        Title = "Jitter Intensity",
        Value = { Min = 0.5, Max = 2.0, Default = CFG.JitterScale },
        Callback = function(v) local x=tonumber(v.Value or v); if x then CFG.JitterScale=x end end
    })
    tab:Slider({
        Title = "Max Logs (Stop→Start)",
        Value = { Min = 5, Max = 150, Default = CFG.MaxLogs },
        Callback = function(v) local x=tonumber(v.Value or v); if x then CFG.MaxLogs=math.floor(x) end end
    })
end
