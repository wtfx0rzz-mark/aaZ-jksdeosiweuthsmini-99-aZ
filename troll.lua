-- troll.lua (chaos swarm + campfire/scrapper avoidance + live player list refresh)
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
    local SEARCH_RADIUS  = 150

    -- Motion: chaotic 3D swarm
    local TICK                 = 0.02
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

    local DRAG_SETTLE          = 0.05
    local JOB_TIMEOUT_S        = 120
    local REASSIGN_IF_LOST_S   = 2.0

    -- Avoidance
    local CAMPFIRE_AVOID_RADIUS  = 35
    local SCRAPPER_AVOID_RADIUS  = 35
    local AVOID_LIFT             = 15
    local AVOID_REEVAL_S         = 0.2

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

    -- Campfire/Scrapper locating
    local function nearestCenterByNames(names)
        local best, bestD = nil, math.huge
        for _,inst in ipairs(WS:GetDescendants()) do
            if inst:IsA("Model") or inst:IsA("BasePart") then
                local n = (inst.Name or ""):lower()
                for _,want in ipairs(names) do
                    if n == want or n:find(want, 1, true) then
                        local mp = mainPart(inst)
                        if mp then
                            local root = hrp()
                            if root then
                                local d = (mp.Position - root.Position).Magnitude
                                if d < bestD then bestD, best = d, mp.Position end
                            end
                        end
                        break
                    end
                end
            end
        end
        return best
    end
    local function campfirePos()
        return nearestCenterByNames({ "mainfire","campfire","camp fire" })
    end
    local function scrapperPos()
        return nearestCenterByNames({ "scrapper","scrap","scrapperstation","scrap station" })
    end

    local function applyAvoidance(pos, now, cache)
        if now - cache.last >= AVOID_REEVAL_S then
            cache.last = now
            cache.fire   = campfirePos()
            cache.scrap  = scrapperPos()
        end
        local lift = 0
        if cache.fire then
            if (pos - cache.fire).Magnitude <= CAMPFIRE_AVOID_RADIUS then lift = math.max(lift, AVOID_LIFT) end
        end
        if cache.scrap then
            if (pos - cache.scrap).Magnitude <= SCRAPPER_AVOID_RADIUS then lift = math.max(lift, AVOID_LIFT) end
        end
        if lift > 0 then
            return pos + Vector3.new(0, lift, 0)
        end
        return pos
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
                xz1 = math.random()*(W_XZ1_MAX-W_XZ1_MIN)+W_XZ1_MIN,
                xz2 = math.random()*(W_XZ2_MAX-W_XZ2_MIN)+W_XZ2_MIN,
                y1  = math.random()*(W_Y1_MAX -W_Y1_MIN )+W_Y1_MIN,
                y2  = math.random()*(W_Y2_MAX -W_Y2_MIN )+W_Y2_MIN,
            },
            avoid = { last = -1, fire = nil, scrap = nil },
        }

        local function ensureSlot()
            local now = os.clock()
            if (not state.slot) or now >= state.reslotAt then
                state.slot = pickCloudSlot(state.rng)
                state.reslotAt = now + state.rng:NextNumber(RESLOT_EVERY_MIN, RESLOT_EVERY_MAX)
            end
        end

        local function maybeBurst()
            local now = os.clock()
            if now < state.burstUntil then return end
            if state.rng:NextNumber() < BURST_CHANCE_PER_SEC * TICK then
                state.burstUntil = now + BURST_DURATION
                state.burstDir   = (state.rng:NextNumber() < 0.5) and -1 or 1
            end
        end

        activeJobs[model] = true
        while running and activeJobs[model] do
            local root = hrp(targetPlayer)
            if not root then
                if os.clock() - state.lastSeen > REASSIGN_IF_LOST_S then break end
            else
                state.lastSeen = os.clock()
                ensureSlot()
                maybeBurst()

                local base = root.Position
                local t = os.clock() - state.t0

                local jx = math.sin(t * state.w.xz1 + state.phases.xz1) * JIT_XZ1
                         + math.cos(t * state.w.xz2 + state.phases.xz2) * JIT_XZ2
                local jz = math.cos(t * state.w.xz1 * 0.8 + state.phases.xz1*0.7) * JIT_XZ1
                         + math.sin(t * state.w.xz2 * 1.3 + state.phases.xz2*0.5) * JIT_XZ2
                local jy = math.sin(t * state.w.y1  + state.phases.y1 ) * JIT_Y1
                         + math.cos(t * state.w.y2  + state.phases.y2 ) * JIT_Y2

                local off = state.slot + Vector3.new(jx, jy, jz)

                if os.clock() < state.burstUntil then
                    local dirToTarget = (base - (base + off)).Unit
                    off = off + dirToTarget * (BURST_PUSH * state.burstDir)
                end

                local pos = base + off
                pos = applyAvoidance(pos, os.clock(), state.avoid)

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
            selectedPlayers = parseSelection(choice)
        end
    })

    local function refreshDropdown()
        local vals = buildValues()
        if playerDD and playerDD.SetValues then
            playerDD:SetValues(vals)
        end
    end

    tab:Button({
        Title = "Refresh Player List",
        Callback = function()
            refreshDropdown()
        end
    })

    -- auto-refresh on join/leave
    Players.PlayerAdded:Connect(function(p)
        if p ~= lp then refreshDropdown() end
    end)
    Players.PlayerRemoving:Connect(function(p)
        if p ~= lp then refreshDropdown() end
    end)

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
