-- troll.lua (chaos swarm + avoidance, optimized to prevent freezes)
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

    -- Search / selection
    local MAX_LOGS       = 50
    local SEARCH_RADIUS  = 200

    -- Motion: chaotic 3D swarm
    local TICK                 = 0.03         -- relaxed tick
    local CLOUD_RADIUS_MIN     = 2.0
    local CLOUD_RADIUS_MAX     = 9.0
    local HEIGHT_BASE          = 0.5
    local HEIGHT_RANGE_MIN     = -2.0
    local HEIGHT_RANGE_MAX     = 3.0

    local JIT_XZ1              = 1.4
    local JIT_XZ2              = 0.9
    local JIT_Y1               = 0.9
    local JIT_Y2               = 0.6
    local W_XZ1_MIN, W_XZ1_MAX = 1.2, 2.4
    local W_XZ2_MIN, W_XZ2_MAX = 2.0, 3.6
    local W_Y1_MIN,  W_Y1_MAX  = 1.0, 2.0
    local W_Y2_MIN,  W_Y2_MAX  = 2.0, 4.0

    local RESLOT_EVERY_MIN     = 0.45
    local RESLOT_EVERY_MAX     = 1.20

    local BURST_CHANCE_PER_SEC = 0.15
    local BURST_DURATION       = 0.18
    local BURST_PUSH           = 6.5

    local DRAG_SETTLE          = 0.03
    local JOB_TIMEOUT_S        = 120
    local REASSIGN_IF_LOST_S   = 2.0

    -- Avoidance
    local CAMPFIRE_AVOID_RADIUS  = 35
    local SCRAPPER_AVOID_RADIUS  = 35
    local AVOID_LIFT             = 15
    local AVOID_REEVAL_S         = 0.75      -- slower, global updater

    -- Micro-tuning
    local ZERO_VEL_EVERY_TICKS   = 4         -- zero velocities every N ticks, not every frame

    -- ===== helpers =====
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

    -- ==== avoidance cache: single lightweight updater ====
    local Avoid = { fire=nil, scrap=nil, last=-1 }
    local function findByNamesFast(names)
        local best, bestD = nil, math.huge
        local root = hrp()
        if not root then return nil end
        local rootPos = root.Position
        -- Search limited: only Models under Workspace.Map or workspace root
        local function consider(container)
            if not container then return end
            for _,inst in ipairs(container:GetChildren()) do
                if inst:IsA("Model") or inst:IsA("BasePart") then
                    local n = (inst.Name or ""):lower()
                    for _,want in ipairs(names) do
                        if n == want or n:find(want, 1, true) then
                            local mp = mainPart(inst)
                            if mp then
                                local d = (mp.Position - rootPos).Magnitude
                                if d < bestD then bestD, best = d, mp.Position end
                            end
                            break
                        end
                    end
                end
            end
        end
        consider(WS:FindFirstChild("Map"))
        consider(WS)
        return best
    end
    local function avoidanceUpdater()
        while true do
            Avoid.fire  = findByNamesFast({ "mainfire","campfire","camp fire" })
            Avoid.scrap = findByNamesFast({ "scrapper","scrap","scrapperstation","scrap station" })
            Avoid.last  = os.clock()
            task.wait(AVOID_REEVAL_S)
        end
    end
    task.spawn(avoidanceUpdater)

    local function applyAvoidance(pos)
        local lift = 0
        if Avoid.fire and (pos - Avoid.fire).Magnitude <= CAMPFIRE_AVOID_RADIUS then
            lift = math.max(lift, AVOID_LIFT)
        end
        if Avoid.scrap and (pos - Avoid.scrap).Magnitude <= SCRAPPER_AVOID_RADIUS then
            lift = math.max(lift, AVOID_LIFT)
        end
        if lift > 0 then
            return pos + Vector3.new(0, lift, 0)
        end
        return pos
    end

    -- ===== chaos engine =====
    local running = false
    local activeJobs = {}
    local rcache     = resolveRemotes()

    -- per-model cached parts to avoid GetDescendants() each tick
    local partsCache = setmetatable({}, { __mode = "k" })
    local function cachedParts(m)
        local list = partsCache[m]
        if list then return list end
        local t = {}
        if m:IsA("Model") then
            for _,d in ipairs(m:GetDescendants()) do
                if d:IsA("BasePart") then t[#t+1] = d end
            end
        elseif m:IsA("BasePart") then
            t[1] = m
        end
        partsCache[m] = t
        return t
    end

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
        local r  = rng:NextNumber(CLOUD_RADIUS_MIN, CLOUD_RADIUS_MAX)
        local th = rng:NextNumber(0, math.pi*2)
        local ph = rng:NextNumber(-0.85, 0.85)
        local x = r * math.cos(th) * math.cos(ph)
        local z = r * math.sin(th) * math.cos(ph)
        local y = HEIGHT_BASE + rng:NextNumber(HEIGHT_RANGE_MIN, HEIGHT_RANGE_MAX)
        return Vector3.new(x, y, z)
    end

    local function floatAroundTarget(model, targetPlayer, seed)
        local started = safeStartDrag(rcache, model)
        task.wait(DRAG_SETTLE)

        -- disable collision once, cache original values
        local snapshot = {}
        for _,p in ipairs(cachedParts(model)) do
            snapshot[p] = p.CanCollide
            p.CanCollide = false
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
        end

        local rnd = rngFor((seed or 0) + os.clock())
        local phases = {
            xz1 = rnd:NextNumber(0, math.pi*2),
            xz2 = rnd:NextNumber(0, math.pi*2),
            y1  = rnd:NextNumber(0, math.pi*2),
            y2  = rnd:NextNumber(0, math.pi*2),
        }
        local w = {
            xz1 = rnd:NextNumber(W_XZ1_MIN, W_XZ1_MAX),
            xz2 = rnd:NextNumber(W_XZ2_MIN, W_XZ2_MAX),
            y1  = rnd:NextNumber(W_Y1_MIN,  W_Y1_MAX ),
            y2  = rnd:NextNumber(W_Y2_MIN,  W_Y2_MAX ),
        }

        local slot        = nil
        local reslotAt    = 0
        local burstUntil  = 0
        local burstDir    = 1
        local t0          = os.clock()
        local lastSeen    = os.clock()
        local tickCount   = 0

        activeJobs[model] = true
        while running and activeJobs[model] do
            local root = hrp(targetPlayer)
            if not root then
                if os.clock() - lastSeen > REASSIGN_IF_LOST_S then break end
            else
                lastSeen = os.clock()
                local now = os.clock()
                if (not slot) or now >= reslotAt then
                    slot = pickCloudSlot(rnd)
                    reslotAt = now + rnd:NextNumber(RESLOT_EVERY_MIN, RESLOT_EVERY_MAX)
                end
                if now >= burstUntil and rnd:NextNumber() < BURST_CHANCE_PER_SEC * TICK then
                    burstUntil = now + BURST_DURATION
                    burstDir   = (rnd:NextNumber() < 0.5) and -1 or 1
                end

                local base = root.Position
                local t = now - t0

                local jx = math.sin(t * w.xz1 + phases.xz1) * JIT_XZ1
                         + math.cos(t * w.xz2 + phases.xz2) * JIT_XZ2
                local jz = math.cos(t * w.xz1 * 0.8 + phases.xz1*0.7) * JIT_XZ1
                         + math.sin(t * w.xz2 * 1.3 + phases.xz2*0.5) * JIT_XZ2
                local jy = math.sin(t * w.y1  + phases.y1 ) * JIT_Y1
                         + math.cos(t * w.y2  + phases.y2 ) * JIT_Y2

                local off = slot + Vector3.new(jx, jy, jz)
                if now < burstUntil then
                    local dirToTarget = (base - (base + off)).Unit
                    off = off + dirToTarget * (BURST_PUSH * burstDir)
                end

                local pos = base + off
                pos = applyAvoidance(pos)

                local look = (base - pos).Unit
                setPivot(model, CFrame.new(pos, pos + look))

                tickCount += 1
                if tickCount % ZERO_VEL_EVERY_TICKS == 0 then
                    for _,p in ipairs(cachedParts(model)) do
                        p.AssemblyLinearVelocity  = Vector3.new()
                        p.AssemblyAngularVelocity = Vector3.new()
                    end
                end
            end
            task.wait(TICK)
        end

        -- restore collision and stop drag
        for part,can in pairs(snapshot) do
            if part and part.Parent then part.CanCollide = can end
        end
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
                for _,p in ipairs(cachedParts(m)) do
                    p.Anchored = false
                    p.AssemblyLinearVelocity  = Vector3.new()
                    p.AssemblyAngularVelocity = Vector3.new()
                    pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
                end
            end
            activeJobs[m] = nil
        end
    end

    -- UI
    local selectedPlayers = {}

    local function buildValues()
        local v = {}
        for _,p in ipairs(Players:GetPlayers()) do
            if p ~= lp then v[#v+1]=("%s#%d"):format(p.Name, p.UserId) end
        end
        table.sort(v)
        return v
    end

    tab:Section({ Title = "Troll: Chaotic Log Smog" })

    local playerDD = tab:Dropdown({
        Title = "Players",
        Values = buildValues(),
        Multi = true,
        AllowNone = true,
        Callback = function(choice)
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
            selectedPlayers = set
        end
    })

    local function refreshDropdown()
        local vals = buildValues()
        if playerDD and playerDD.SetValues then playerDD:SetValues(vals) end
    end

    tab:Button({ Title = "Refresh Player List", Callback = refreshDropdown })
    Players.PlayerAdded:Connect(function(p) if p ~= lp then refreshDropdown() end end)
    Players.PlayerRemoving:Connect(function(p) if p ~= lp then refreshDropdown() end end)

    local function selectedPlayersList(fromSet)
        local out = {}
        for userIdStr,_ in pairs(fromSet or {}) do
            local uid = tonumber(userIdStr)
            if uid then
                for _,p in ipairs(Players:GetPlayers()) do
                    if p.UserId == uid and p ~= lp then out[#out+1] = p; break end
                end
            end
        end
        return out
    end

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

    tab:Button({ Title = "Stop", Callback = stopAll })
end
