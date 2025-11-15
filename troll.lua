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
    assert(tab, "Troll tab not found")

    local INITIAL_POPULATE_DELAY = 2.0

    local TICK = 0.02
    local SEARCH_RADIUS = 200
    local CFG = {
        DesiredLogs = 5,
        Speed       = 1.0,
        HeightRange = 5.0,
        CloudMinR   = 2.0,
        CloudMaxR   = 9.0,

        CampRadius  = 35,
        ScrapRadius = 35,
        AvoidLift   = 15,
        AvoidReeval = 0.2,

        LeadBase    = 0.18,
        LeadGain    = 0.25,
        LeadMax     = 0.60,
        LeadStop    = 2.0,
        FlipDart    = 0.22,
        FlipThresh  = -0.30,
        FlipPush    = 10.0,

        NudgeChancePerSec = 0.18,
        NudgeDuration     = 0.55,
        NudgeAhead        = 6.0,
        NudgeEyeY         = 2.0,
        NudgeSideJitter   = 1.2,

        HazardTopPad = 6.0,
        HazardRadPad = 2.0
    }

    local BURST_CHANCE_PER_SEC = 0.15
    local BURST_DURATION       = 0.18
    local BURST_PUSH_BASE      = 6.5

    local RESLOT_MIN = 0.45
    local RESLOT_MAX = 1.20

    local JIT_XZ1, JIT_XZ2 = 1.4, 0.9
    local JIT_Y1,  JIT_Y2  = 0.9, 0.6
    local W_XZ1_MIN, W_XZ1_MAX = 1.2, 2.4
    local W_XZ2_MIN, W_XZ2_MAX = 2.0, 3.6
    local W_Y1_MIN,  W_Y1_MAX  = 1.0, 2.0
    local W_Y2_MIN,  W_Y2_MAX  = 2.0, 4.0

    local REASSIGN_IF_LOST_S = 2.0

    local PLAYER_NUDGE_RANGE    = 300
    local PLAYER_NUDGE_UP       = 20
    local PLAYER_NUDGE_AWAY     = 50
    local PLAYER_NUDGE_COOLDOWN = 0.1

    local SINK_Y_TARGET         = -500

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

    local function isCharacterModel(m)
        return m
            and m:IsA("Model")
            and m:FindFirstChildOfClass("Humanoid") ~= nil
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
            for part,can in pairs(snap) do
                if part and part.Parent then
                    part.CanCollide = can
                end
            end
            return
        end
        local s = {}
        for _,p in ipairs(parts) do
            s[p] = p.CanCollide
            p.CanCollide = false
        end
        return s
    end

    local function zeroAssembly(model)
        for _,p in ipairs(getParts(model)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
    end

    local function getPivotPos(model)
        if model:IsA("Model") then
            local ok, cf = pcall(model.GetPivot, model)
            if ok and cf then return cf.Position end
            local mp = mainPart(model); return mp and mp.Position or nil
        else
            local mp = mainPart(model); return mp and mp.Position or nil
        end
    end

    local function setPivot(model, cf)
        if model:IsA("Model") then
            model:PivotTo(cf)
        else
            local p = mainPart(model)
            if p then p.CFrame = cf end
        end
    end

    local function getRemote(...)
        local re = RS:FindFirstChild("RemoteEvents"); if not re then return nil end
        for _,n in ipairs({...}) do
            local x = re:FindFirstChild(n)
            if x then return x end
        end
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

    local function logsNear(center, excludeSet, limit)
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }

        local parts = WS:GetPartBoundsInRadius(center, SEARCH_RADIUS, params) or {}
        local items, uniq = {}, {}
        for _,part in ipairs(parts) do
            if part:IsA("BasePart") then
                local m = part:FindFirstAncestorOfClass("Model")
                if m and m.Name == "Log" and not uniq[m] and not excludeSet[m] then
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
        for i=1, math.min(limit or #items, #items) do
            out[#out+1] = items[i].m
        end
        return out
    end

    local function playersList()
        local vals = {}
        for _,p in ipairs(Players:GetPlayers()) do
            if p ~= lp then
                vals[#vals+1]=("%s#%d"):format(p.Name, p.UserId)
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
                if uid then set[uid] = true end
            end
        else
            local uid = tonumber((tostring(choice or ""):match("#(%d+)$") or ""))
            if uid then set[uid] = true end
        end
        return set
    end

    local function selectedPlayersList(set)
        local out = {}
        for _,p in ipairs(Players:GetPlayers()) do
            if set[p.UserId] and p ~= lp then
                out[#out+1] = p
            end
        end
        return out
    end

    local function rngFor(seed)
        return Random.new(math.clamp(math.floor((seed or 0) * 100000) % 2^31, 1, 2^31-1))
    end

    local function heightMinMax()
        local span = math.clamp(CFG.HeightRange, 1, 10)
        local minY = -0.4 * span
        local maxY =  0.6 * span
        return minY, maxY
    end

    local campCache, scrapCache, lastAvoidAt = nil, nil, 0

    local function partCenter(m)
        if not m then return nil end
        local mp = mainPart(m)
        if mp then return mp.Position end
        local ok, cf = pcall(function() return m:GetPivot() end)
        return ok and cf.Position or nil
    end

    local function findByNames(names)
        local best, bestDist = nil, math.huge
        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") then
                local n = (d.Name or ""):lower()
                for _,nn in ipairs(names) do
                    if n == nn then
                        local p = partCenter(d)
                        if p then
                            local root = hrp()
                            if root then
                                local dist = (p - root.Position).Magnitude
                                if dist < bestDist then
                                    bestDist, best = dist, d
                                end
                            end
                        end
                    end
                end
            end
        end
        return best
    end

    local function refreshAvoidTargets(now)
        if now - lastAvoidAt < CFG.AvoidReeval then return end
        lastAvoidAt = now
        if not campCache or not campCache.Parent then
            local map = WS:FindFirstChild("Map")
            local cg  = map and map:FindFirstChild("Campground")
            local mf  = cg and cg:FindFirstChild("MainFire")
            campCache = mf or findByNames({ "mainfire", "campfire", "camp fire" })
        end
        if not scrapCache or not scrapCache.Parent then
            scrapCache = findByNames({ "scrapper", "scrap", "scrapperstation" })
        end
    end

    local function hazardInfo()
        refreshAvoidTargets(os.clock())
        local list = {}
        if campCache then table.insert(list, {center=partCenter(campCache), r=CFG.CampRadius}) end
        if scrapCache then table.insert(list, {center=partCenter(scrapCache), r=CFG.ScrapRadius}) end
        return list
    end

    local function projectOutOfHazards(pos)
        local hs = hazardInfo()
        if #hs == 0 then return pos end
        for _,h in ipairs(hs) do
            local c = h.center; if not c then continue end
            local rSafe = (h.r or 0) + CFG.HazardRadPad
            local v = pos - c
            local vr = Vector3.new(v.X, 0, v.Z)
            local d = vr.Magnitude
            if d < rSafe then
                if d > 1e-3 then
                    local rim = c + vr.Unit * rSafe
                    pos = Vector3.new(rim.X, math.max(pos.Y, c.Y + CFG.HazardTopPad), rim.Z) + Vector3.new(0, CFG.AvoidLift, 0)
                else
                    pos = Vector3.new(c.X + rSafe, math.max(pos.Y, c.Y + CFG.HazardTopPad), c.Z) + Vector3.new(0, CFG.AvoidLift, 0)
                end
            end
        end
        return pos
    end

    local function insideHazard(base)
        local hs = hazardInfo()
        for _,h in ipairs(hs) do
            local c = h.center; if not c then continue end
            local r = (h.r or 0)
            local vr = Vector3.new(base.X-c.X, 0, base.Z-c.Z)
            if vr.Magnitude <= r then return true, c end
        end
        return false, nil
    end

    local function itemsRoot()
        return WS:FindFirstChild("Items") or WS:FindFirstChild("items")
    end

    local running = false
    local desiredPerTarget = CFG.DesiredLogs
    local active  = {}
    local activeList = {}
    local targets = {}
    local activeByUid = {}
    local countByUid = {}
    local reconcileConn, hbConn = nil, nil
    local lastDt = 1/60
    local scanAt = 0
    local scanCache = {}

    local playerNudgeEnabled = false
    local playerNudgeConn    = nil
    local lastNudgeItemAt    = {}

    local sinkItemsEnabled   = false
    local sinkItemsConn      = nil

    local function clampOrbital(off)
        local maxOff = CFG.CloudMaxR + 3.0
        local m = off.Magnitude
        if m > maxOff then return off.Unit * maxOff end
        return off
    end

    local function ensureUid(uid)
        if not activeByUid[uid] then activeByUid[uid] = {} end
        if not countByUid[uid] then countByUid[uid] = 0 end
    end

    local function adopt(model, tgt, seed)
        if active[model] then return end
        local uid = tgt.UserId
        ensureUid(uid)
        active[model] = {
            target = tgt,
            uid = uid,
            t0 = os.clock(),
            seed = seed,
            rng = rngFor((seed or 0) + os.clock()),
            slot = nil,
            reslotAt = 0,
            burstUntil = 0,
            burstDir = 1,
            phases = {
                xz1 = math.random()*math.pi*2,
                xz2 = math.random()*math.pi*2,
                y1  = math.random()*math.pi*2,
                y2  = math.random()*math.pi*2
            },
            w = {
                xz1 = math.random()*(W_XZ1_MAX-W_XZ1_MIN)+W_XZ1_MIN,
                xz2 = math.random()*(W_XZ2_MAX-W_XZ2_MIN)+W_XZ2_MIN,
                y1  = math.random()*(W_Y1_MAX -W_Y1_MIN )+W_Y1_MIN,
                y2  = math.random()*(W_Y2_MAX -W_Y2_MIN )+W_Y2_MAX,
            },
            started    = false,
            snap       = nil,
            lastSeen   = os.clock(),
            lastVel    = Vector3.zero,
            nudgeUntil = 0,
            nudgeSide  = 0
        }
        table.insert(activeList, model)
        table.insert(activeByUid[uid], model)
        countByUid[uid] += 1
        task.spawn(function()
            local st = active[model]; if not st then return end
            local started = safeStartDrag(model); st.started = started
            task.wait(0.05)
            st.snap = setCollide(model, false)
            for _,p in ipairs(getParts(model)) do
                pcall(function() p:SetNetworkOwner(lp) end)
            end
            zeroAssembly(model)
        end)
    end

    local function shed(model)
        local st = active[model]
        active[model] = nil
        for i=#activeList,1,-1 do
            if activeList[i] == model then
                table.remove(activeList, i)
                break
            end
        end
        if st then
            if st.snap then setCollide(model, true, st.snap) end
            local uid = st.uid
            if uid and activeByUid[uid] then
                for i=#activeByUid[uid],1,-1 do
                    if activeByUid[uid][i] == model then
                        table.remove(activeByUid[uid], i)
                        break
                    end
                end
                if countByUid[uid] and countByUid[uid] > 0 then
                    countByUid[uid] -= 1
                end
            end
        end
        finallyStopDrag(model)
        for _,p in ipairs(getParts(model)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function()
                if p.SetNetworkOwnershipAuto then
                    p:SetNetworkOwnershipAuto()
                end
            end)
        end
    end

    local function ensureSlot(st)
        local now = os.clock()
        if (not st.slot) or now >= st.reslotAt then
            local r  = st.rng:NextNumber(CFG.CloudMinR, CFG.CloudMaxR)
            local th = st.rng:NextNumber(0, math.pi*2)
            local ph = st.rng:NextNumber(-0.85, 0.85)
            local ymin, ymax = heightMinMax()
            local y = st.rng:NextNumber(ymin, ymax)
            local x = r * math.cos(th) * math.cos(ph)
            local z = r * math.sin(th) * math.cos(ph)
            st.slot = Vector3.new(x, y, z)
            local reslotK = st.rng:NextNumber(RESLOT_MIN, RESLOT_MAX) / math.max(0.25, CFG.Speed)
            st.reslotAt = now + reslotK
        end
    end

    local function maybeBurst(st)
        local now = os.clock()
        if now < st.burstUntil then return end
        local chance = BURST_CHANCE_PER_SEC * CFG.Speed
        if st.rng:NextNumber() < chance * TICK then
            st.burstUntil = now + BURST_DURATION / math.max(0.5, CFG.Speed)
            st.burstDir   = (st.rng:NextNumber() < 0.5) and -1 or 1
        end
    end

    local function predictiveBaseFor(st)
        local root = hrp(st.target)
        if not root then return nil, Vector3.new(0,0,-1) end
        local vel = root.AssemblyLinearVelocity
        local speed = vel.Magnitude
        local leadT = 0
        if speed > CFG.LeadStop then
            leadT = math.clamp(
                CFG.LeadBase + CFG.LeadGain * (speed/16),
                0,
                CFG.LeadMax
            )
        end
        local base = root.Position + vel * leadT
        local look = (speed > 1e-3) and (vel / speed) or (root.CFrame.LookVector)
        local inside, c = insideHazard(base)
        if inside and c then
            base = Vector3.new(base.X, math.max(base.Y, c.Y + CFG.HazardTopPad), base.Z)
        end
        return base, look
    end

    local function maybeStartNudge(st, dt)
        if os.clock() < st.nudgeUntil then return end
        local chance = CFG.NudgeChancePerSec * CFG.Speed
        if st.rng:NextNumber() < chance * math.clamp(dt, 0.01, 0.1) then
            st.nudgeUntil = os.clock() + CFG.NudgeDuration
            st.nudgeSide  = (st.rng:NextNumber() < 0.5) and -1 or 1
        end
    end

    local function floatStep(model, st, dt)
        local base, baseLook = predictiveBaseFor(st)
        if not base then
            if os.clock() - st.lastSeen > REASSIGN_IF_LOST_S then
                return false
            end
            return true
        end
        st.lastSeen = os.clock()
        ensureSlot(st)
        maybeBurst(st)
        maybeStartNudge(st, dt)

        local t = (os.clock() - (st.t0 or os.clock())) * CFG.Speed

        local jx = math.sin(t * st.w.xz1 + st.phases.xz1) * JIT_XZ1
                 + math.cos(t * st.w.xz2 + st.phases.xz2) * JIT_XZ2
        local jz = math.cos(t * st.w.xz1 * 0.8 + st.phases.xz1*0.7) * JIT_XZ1
                 + math.sin(t * st.w.xz2 * 1.3 + st.phases.xz2*0.5) * JIT_XZ2
        local jy = math.sin(t * st.w.y1  + st.phases.y1 ) * JIT_Y1
                 + math.cos(t * st.w.y2  + st.phases.y2 ) * JIT_Y2

        local off = st.slot + Vector3.new(jx, jy, jz)

        local root = hrp(st.target)
        if root then
            local vel = root.AssemblyLinearVelocity
            local speed = vel.Magnitude
            local newDir = speed > 1e-3 and (vel / speed) or Vector3.zero
            if st.lastVel.Magnitude > 1e-3 and newDir ~= Vector3.zero then
                local dot = newDir:Dot(
                    st.lastVel.Magnitude > 1e-3 and st.lastVel.Unit or newDir
                )
                if dot < CFG.FlipThresh then
                    st.burstUntil = os.clock() + CFG.FlipDart
                    st.burstDir   = 1
                    st.flipPushDir = newDir
                end
            end
            st.lastVel = vel
        end

        if os.clock() < st.burstUntil then
            local dir = st.flipPushDir or (-off).Unit
            off = off + dir * (CFG.FlipPush + BURST_PUSH_BASE) * CFG.Speed * st.burstDir
        end
        st.flipPushDir = nil

        off = clampOrbital(off)

        local posCandidate
        if os.clock() < st.nudgeUntil and root then
            local eye = root.Position + Vector3.new(0, CFG.NudgeEyeY, 0)
            local look = baseLook or root.CFrame.LookVector
            local right = root.CFrame.RightVector
            local side = right * (st.nudgeSide * CFG.NudgeSideJitter)
            posCandidate = eye + look * CFG.NudgeAhead + side + Vector3.new(0, jy * 0.3, 0)
        else
            posCandidate = base + off
        end

        posCandidate = projectOutOfHazards(posCandidate)

        local leashR = CFG.CloudMaxR + 6.0
        local vecFromBase = posCandidate - base
        local dist = vecFromBase.Magnitude
        if dist > leashR then
            posCandidate = base + vecFromBase.Unit * leashR
        end

        local cur = getPivotPos(model) or posCandidate
        local lookVec = (base - cur)
        if lookVec.Magnitude < 1e-3 then
            lookVec = baseLook or Vector3.new(0,0,-1)
        else
            lookVec = lookVec.Unit
        end
        setPivot(model, CFrame.new(posCandidate, posCandidate + lookVec))

        for _,p in ipairs(getParts(model)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
        return true
    end

    local function reconcile()
        if not running then return end
        local myRoot = hrp(); if not myRoot then return end
        if os.clock() >= scanAt then
            local exclude = {}
            for m,_ in pairs(active) do exclude[m] = true end
            scanCache = logsNear(myRoot.Position, exclude, 400)
            scanAt = os.clock() + 0.5
        end

        local nTargets = #targets
        if nTargets == 0 then return end

        local wantPer = math.clamp(desiredPerTarget, 1, 50)
        for _,tgt in ipairs(targets) do
            ensureUid(tgt.UserId)
        end

        for _,tgt in ipairs(targets) do
            local uid  = tgt.UserId
            local have = countByUid[uid] or 0
            if have < wantPer then
                local deficit = wantPer - have
                local toAdd = math.clamp(deficit, 1, 12)
                local idx = 1
                while toAdd > 0 and idx <= #scanCache do
                    local mdl = scanCache[idx]; idx += 1
                    if mdl and mdl.Parent and not active[mdl] then
                        adopt(mdl, tgt, (have + toAdd) * 0.73 + uid%97)
                        toAdd -= 1
                    end
                end
            elseif have > wantPer then
                local over = have - wantPer
                local list = activeByUid[uid] or {}
                local i = #list
                while over > 0 and i >= 1 do
                    local mdl = list[i]
                    if mdl and active[mdl] then
                        shed(mdl)
                        over -= 1
                    end
                    i -= 1
                end
            end
        end
    end

    local function stopAll()
        running = false
        if reconcileConn then reconcileConn:Disconnect(); reconcileConn=nil end
        if hbConn then hbConn:Disconnect(); hbConn=nil end
        for i=#activeList,1,-1 do
            local mdl = activeList[i]
            if mdl then shed(mdl) end
        end
        active      = {}
        activeList  = {}
        activeByUid = {}
        countByUid  = {}
    end

    local selectedSet = {}
    local playerDD

    local function buildPlayerDropdownOnce()
        if playerDD then return end
        playerDD = tab:Dropdown({
            Title = "Players",
            Values = playersList(),
            Multi = true,
            AllowNone = true,
            Callback = function(choice)
                selectedSet = parseSelection(choice)
            end
        })
    end

    buildPlayerDropdownOnce()
    task.delay(INITIAL_POPULATE_DELAY, buildPlayerDropdownOnce)

    tab:Section({ Title = "Troll: Chaotic Log Smog" })

    tab:Slider({
        Title = "Logs (per target)",
        Value = { Min = 1, Max = 50, Default = 5 },
        Callback = function(v)
            local n = tonumber(type(v)=="table" and (v.Value or v.Current or v.Default) or v)
            if n then
                desiredPerTarget = math.clamp(math.floor(n + 0.5), 1, 50)
            end
        end
    })

    tab:Slider({
        Title = "Speed",
        Value = { Min = 0.5, Max = 3.0, Default = 1.0 },
        Callback = function(v)
            local n = tonumber(type(v)=="table" and (v.Value or v.Current or v.Default) or v)
            if n then
                CFG.Speed = math.clamp(n, 0.5, 3.0)
            end
        end
    })

    tab:Slider({
        Title = "Height Range",
        Value = { Min = 1.0, Max = 10.0, Default = 5.0 },
        Callback = function(v)
            local n = tonumber(type(v)=="table" and (v.Value or v.Current or v.Default) or v)
            if n then
                CFG.HeightRange = math.clamp(n, 1.0, 10.0)
            end
        end
    })

    tab:Button({
        Title = "Start",
        Callback = function()
            stopAll()
            resolveRemotes()
            if not playerDD then buildPlayerDropdownOnce() end
            targets = selectedPlayersList(selectedSet)
            if #targets == 0 then return end
            for _,tgt in ipairs(targets) do ensureUid(tgt.UserId) end
            running = true
            hbConn = Run.Heartbeat:Connect(function(dt)
                lastDt = dt
                if not running then return end
                for mdl,st in pairs(active) do
                    if mdl and mdl.Parent and st and st.target then
                        local ok = floatStep(mdl, st, dt)
                        if not ok then shed(mdl) end
                    else
                        if mdl then shed(mdl) end
                    end
                end
            end)
            reconcileConn = Run.Heartbeat:Connect(function()
                reconcile()
            end)
        end
    })

    tab:Button({
        Title = "Stop",
        Callback = function()
            stopAll()
        end
    })

    local function doPlayerNudgeStep(dt)
        if not playerNudgeEnabled then return end

        local now = os.clock()
        local pTargets = selectedPlayersList(selectedSet)
        if #pTargets == 0 then return end

        for _, tgt in ipairs(pTargets) do
            local root = hrp(tgt)
            if root then
                local origin = root.Position

                local filterList = { lp.Character }
                if tgt.Character then
                    table.insert(filterList, tgt.Character)
                end

                local params = OverlapParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = filterList

                local parts = WS:GetPartBoundsInRadius(origin, PLAYER_NUDGE_RANGE, params) or {}
                for _, part in ipairs(parts) do
                    if part:IsA("BasePart") and not part.Anchored then
                        local mdl = part:FindFirstAncestorOfClass("Model") or part
                        if mdl and not isCharacterModel(mdl) then
                            if not active[mdl] then
                                local last = lastNudgeItemAt[mdl] or 0
                                if now - last >= PLAYER_NUDGE_COOLDOWN then
                                    lastNudgeItemAt[mdl] = now
                                    local mp = mainPart(mdl)
                                    if mp then
                                        local toItem = mp.Position - origin
                                        local horiz = Vector3.new(toItem.X, 0, toItem.Z)
                                        if horiz.Magnitude < 1e-3 then
                                            local look = root.CFrame.LookVector
                                            horiz = Vector3.new(look.X, 0, look.Z)
                                        end
                                        local dir = horiz.Magnitude > 1e-3 and horiz.Unit or Vector3.new(0, 0, 1)
                                        local vel = dir * PLAYER_NUDGE_AWAY + Vector3.new(0, PLAYER_NUDGE_UP, 0)
                                        mp.AssemblyLinearVelocity = vel
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    tab:Section({ Title = "Player Nudge" })

    tab:Toggle({
        Title = "Enable Player Nudge",
        Value = false,
        Callback = function(on)
            playerNudgeEnabled = (on == true)
            if playerNudgeEnabled then
                if not playerNudgeConn then
                    playerNudgeConn = Run.Heartbeat:Connect(function(dt)
                        doPlayerNudgeStep(dt)
                    end)
                end
            else
                if playerNudgeConn then
                    playerNudgeConn:Disconnect()
                    playerNudgeConn = nil
                end
            end
        end
    })

    local function doSinkItemsStep(dt)
        if not sinkItemsEnabled then return end
        local rootFolder = itemsRoot()
        if not rootFolder then return end

        for _, obj in ipairs(rootFolder:GetChildren()) do
            local mdl
            if obj:IsA("Model") then
                mdl = obj
            elseif obj:IsA("BasePart") then
                mdl = obj:FindFirstAncestorOfClass("Model") or obj
            end

            if mdl then
                local mp = mainPart(mdl)
                if mp then
                    local pos = mp.Position
                    if pos.Y > SINK_Y_TARGET then
                        local targetCf = CFrame.new(pos.X, SINK_Y_TARGET, pos.Z)
                        if mdl:IsA("Model") then
                            setPivot(mdl, targetCf)
                        else
                            mp.CFrame = targetCf
                        end
                    end
                end
            end
        end
    end

    tab:Section({ Title = "Sink Items" })

    tab:Toggle({
        Title = "Sink Items",
        Value = false,
        Callback = function(on)
            sinkItemsEnabled = (on == true)
            if sinkItemsEnabled then
                if not sinkItemsConn then
                    sinkItemsConn = Run.Heartbeat:Connect(function(dt)
                        doSinkItemsStep(dt)
                    end)
                end
            else
                if sinkItemsConn then
                    sinkItemsConn:Disconnect()
                    sinkItemsConn = nil
                end
            end
        end
    })
end
