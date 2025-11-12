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

    local CFG = {
        Tick = 0.02,
        MaxLogs = 50,
        SearchRadius = 200,

        CloudRadiusMin = 2.0,
        CloudRadiusMax = 9.0,
        HeightBase = 0.5,
        HeightRangeMin = -2.0,
        HeightRangeMax = 3.0,

        JIT_XZ1 = 1.4,
        JIT_XZ2 = 0.9,
        JIT_Y1  = 0.9,
        JIT_Y2  = 0.6,

        W_XZ1_MIN = 1.2, W_XZ1_MAX = 2.4,
        W_XZ2_MIN = 2.0, W_XZ2_MAX = 3.6,
        W_Y1_MIN  = 1.0, W_Y1_MAX  = 2.0,
        W_Y2_MIN  = 2.0, W_Y2_MAX  = 4.0,

        ReslotMin = 0.45,
        ReslotMax = 1.20,

        BurstChancePerSec = 0.15,
        BurstDuration = 0.18,
        BurstPush = 6.5,

        DragSettle = 0.05,
        ReassignIfLostS = 2.0,
        JobTimeoutS = nil,

        CampfireAvoidRadius = 35,
        ScrapperAvoidRadius = 35,
        AvoidLift = 15,
        AvoidReevalS = 0.2,

        SpeedMul = 1.0
    }

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
        local parts = WS:GetPartBoundsInRadius(center, CFG.SearchRadius, params) or {}
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

    local function fireCenterPart(fire)
        return fire:FindFirstChild("Center")
            or fire:FindFirstChild("InnerTouchZone")
            or mainPart(fire)
            or fire.PrimaryPart
    end
    local function resolveCampfire()
        local map = WS:FindFirstChild("Map")
        local cg  = map and map:FindFirstChild("Campground")
        local mf  = cg and cg:FindFirstChild("MainFire")
        if mf then
            local c = fireCenterPart(mf)
            return c and c.Position or mf:GetPivot().Position
        end
        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") then
                local n = (d.Name or ""):lower()
                if n == "mainfire" or n == "campfire" or n == "camp fire" then
                    local c = fireCenterPart(d)
                    return c and c.Position or d:GetPivot().Position
                end
            end
        end
        return nil
    end
    local function resolveScrapper()
        local candidates = {}
        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") then
                local n = (d.Name or ""):lower()
                if n:find("scrap") or n:find("scrapper") then
                    candidates[#candidates+1] = d
                end
            end
        end
        if #candidates == 0 then return nil end
        local best, bestD = nil, math.huge
        local me = hrp(); me = me and me.Position or Vector3.new()
        for _,m in ipairs(candidates) do
            local p = (mainPart(m) and mainPart(m).Position) or m:GetPivot().Position
            local d = (p - me).Magnitude
            if d < bestD then bestD, best = d, p end
        end
        return best
    end

    local avoidLastEval = 0
    local avoidCampPos, avoidScrapPos = nil, nil
    local function refreshAvoidCenters(now)
        if now - avoidLastEval < CFG.AvoidReevalS then return end
        avoidCampPos = resolveCampfire()
        avoidScrapPos = resolveScrapper()
        avoidLastEval = now
    end
    local function applyAvoid(pos)
        local out = pos
        if avoidCampPos then
            if (pos - avoidCampPos).Magnitude <= CFG.CampfireAvoidRadius then
                out = out + Vector3.new(0, CFG.AvoidLift, 0)
            end
        end
        if avoidScrapPos then
            if (pos - avoidScrapPos).Magnitude <= CFG.ScrapperAvoidRadius then
                out = out + Vector3.new(0, CFG.AvoidLift, 0)
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
    local function rngFor(seed)
        return Random.new(math.clamp(math.floor((seed or 0) * 100000) % 2^31, 1, 2^31-1))
    end
    local function pickCloudSlot(rng)
        local r  = rng:NextNumber(CFG.CloudRadiusMin, CFG.CloudRadiusMax)
        local th = rng:NextNumber(0, math.pi*2)
        local ph = rng:NextNumber(-0.85, 0.85)
        local x = r * math.cos(th) * math.cos(ph)
        local z = r * math.sin(th) * math.cos(ph)
        local y = CFG.HeightBase + rng:NextNumber(CFG.HeightRangeMin, CFG.HeightRangeMax)
        return Vector3.new(x, y, z)
    end

    local function floatAroundTarget(model, targetPlayer, seed)
        local started = safeStartDrag(rcache, model)
        task.wait(CFG.DragSettle)
        local snap = setCollide(model, false)
        zeroAssembly(model)

        local state = {
            rng         = rngFor((seed or 0) + os.clock()),
            slot        = nil,
            reslotAt    = 0,
            burstUntil  = 0,
            burstDir    = 1,
            t0          = os.clock(),
            lastSeen    = os.clock(),
            phases = {
                xz1 = math.random()*math.pi*2,
                xz2 = math.random()*math.pi*2,
                y1  = math.random()*math.pi*2,
                y2  = math.random()*math.pi*2,
            },
            w = {
                xz1 = (math.random()*(CFG.W_XZ1_MAX-CFG.W_XZ1_MIN)+CFG.W_XZ1_MIN)*CFG.SpeedMul,
                xz2 = (math.random()*(CFG.W_XZ2_MAX-CFG.W_XZ2_MIN)+CFG.W_XZ2_MIN)*CFG.SpeedMul,
                y1  = (math.random()*(CFG.W_Y1_MAX -CFG.W_Y1_MIN )+CFG.W_Y1_MIN )*CFG.SpeedMul,
                y2  = (math.random()*(CFG.W_Y2_MAX -CFG.W_Y2_MIN )+CFG.W_Y2_MIN )*CFG.SpeedMul,
            },
        }

        local function ensureSlot(now)
            if (not state.slot) or now >= state.reslotAt then
                state.slot = pickCloudSlot(state.rng)
                local res = state.rng:NextNumber(CFG.ReslotMin, CFG.ReslotMax) / math.max(0.1, CFG.SpeedMul)
                state.reslotAt = now + res
            end
        end
        local function maybeBurst(now)
            if now < state.burstUntil then return end
            if state.rng:NextNumber() < CFG.BurstChancePerSec * CFG.Tick then
                state.burstUntil = now + CFG.BurstDuration
                state.burstDir   = (state.rng:NextNumber() < 0.5) and -1 or 1
            end
        end

        activeJobs[model] = true
        while running and activeJobs[model] do
            local now = os.clock()
            refreshAvoidCenters(now)

            local root = hrp(targetPlayer)
            if not root then
                if now - state.lastSeen > CFG.ReassignIfLostS then break end
            else
                state.lastSeen = now
                ensureSlot(now)
                maybeBurst(now)

                local base = root.Position
                local t = (now - state.t0)

                local jx = math.sin(t * state.w.xz1 + state.phases.xz1) * CFG.JIT_XZ1
                         + math.cos(t * state.w.xz2 + state.phases.xz2) * CFG.JIT_XZ2
                local jz = math.cos(t * state.w.xz1 * 0.8 + state.phases.xz1*0.7) * CFG.JIT_XZ1
                         + math.sin(t * state.w.xz2 * 1.3 + state.phases.xz2*0.5) * CFG.JIT_XZ2
                local jy = math.sin(t * state.w.y1  + state.phases.y1 ) * CFG.JIT_Y1
                         + math.cos(t * state.w.y2  + state.phases.y2 ) * CFG.JIT_Y2

                local off = state.slot + Vector3.new(jx, jy, jz)

                if now < state.burstUntil then
                    local dirToTarget = (base - (base + off)).Unit
                    off = off + dirToTarget * (CFG.BurstPush * state.burstDir)
                end

                local pos = base + off
                pos = applyAvoid(pos)

                local look = (base - pos).Unit
                setPivot(model, CFrame.new(pos, pos + look))

                for _,p in ipairs(getAllParts(model)) do
                    p.AssemblyLinearVelocity  = Vector3.new()
                    p.AssemblyAngularVelocity = Vector3.new()
                end
            end
            task.wait(CFG.Tick)
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
            task.spawn(function()
                floatAroundTarget(mdl, tgt, i*0.73)
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
    tab:Section({ Title = "Troll: Chaotic Log Tornado" })

    local playerDD
    playerDD = tab:Dropdown({
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
            if playerDD and playerDD.SetValues then playerDD:SetValues(playerChoices()) end
        end
    })

    tab:Section({ Title = "Behavior" })
    tab:Slider({
        Title = "Speed Multiplier",
        Value = { Min = 0.3, Max = 3.0, Default = CFG.SpeedMul },
        Callback = function(v) CFG.SpeedMul = tonumber(v.Value or v) or CFG.SpeedMul end
    })
    tab:Slider({
        Title = "Max Logs",
        Value = { Min = 5, Max = 200, Default = CFG.MaxLogs },
        Callback = function(v) CFG.MaxLogs = math.clamp(tonumber(v.Value or v) or CFG.MaxLogs, 1, 500) end
    })
    tab:Slider({
        Title = "Cloud Radius Min",
        Value = { Min = 0.5, Max = 8.0, Default = CFG.CloudRadiusMin },
        Callback = function(v) CFG.CloudRadiusMin = tonumber(v.Value or v) or CFG.CloudRadiusMin end
    })
    tab:Slider({
        Title = "Cloud Radius Max",
        Value = { Min = 2.0, Max = 16.0, Default = CFG.CloudRadiusMax },
        Callback = function(v) CFG.CloudRadiusMax = tonumber(v.Value or v) or CFG.CloudRadiusMax end
    })
    tab:Slider({
        Title = "Height Base",
        Value = { Min = -3.0, Max = 6.0, Default = CFG.HeightBase },
        Callback = function(v) CFG.HeightBase = tonumber(v.Value or v) or CFG.HeightBase end
    })
    tab:Slider({
        Title = "Height Range Min",
        Value = { Min = -6.0, Max = 0.0, Default = CFG.HeightRangeMin },
        Callback = function(v) CFG.HeightRangeMin = tonumber(v.Value or v) or CFG.HeightRangeMin end
    })
    tab:Slider({
        Title = "Height Range Max",
        Value = { Min = 0.5, Max = 8.0, Default = CFG.HeightRangeMax },
        Callback = function(v) CFG.HeightRangeMax = tonumber(v.Value or v) or CFG.HeightRangeMax end
    })

    tab:Section({ Title = "Avoidance" })
    tab:Slider({
        Title = "Campfire Avoid Radius",
        Value = { Min = 0, Max = 60, Default = CFG.CampfireAvoidRadius },
        Callback = function(v) CFG.CampfireAvoidRadius = tonumber(v.Value or v) or CFG.CampfireAvoidRadius end
    })
    tab:Slider({
        Title = "Scrapper Avoid Radius",
        Value = { Min = 0, Max = 60, Default = CFG.ScrapperAvoidRadius },
        Callback = function(v) CFG.ScrapperAvoidRadius = tonumber(v.Value or v) or CFG.ScrapperAvoidRadius end
    })
    tab:Slider({
        Title = "Avoid Lift",
        Value = { Min = 0, Max = 30, Default = CFG.AvoidLift },
        Callback = function(v) CFG.AvoidLift = tonumber(v.Value or v) or CFG.AvoidLift end
    })

    tab:Section({ Title = "Controls" })
    tab:Button({
        Title = "Start",
        Callback = function()
            stopAll()
            local targets = selectedPlayersList(selectedPlayers)
            if #targets == 0 then return end
            local logs = logsNearMe(CFG.MaxLogs)
            if #logs == 0 then return end
            startFloat(logs, targets)
            if CFG.JobTimeoutS and CFG.JobTimeoutS > 0 then
                task.delay(CFG.JobTimeoutS, function() if running then stopAll() end end)
            end
        end
    })
    tab:Button({
        Title = "Stop",
        Callback = function() stopAll() end
    })
end
