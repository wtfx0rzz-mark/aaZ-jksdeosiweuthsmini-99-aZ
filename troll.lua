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

    local TICK = 0.02
    local SEARCH_RADIUS = 200

    local CFG = {
        DesiredLogs = 5,        -- slider 1..50 (default 5)
        Speed       = 1.0,      -- slider 0.5..3.0
        HeightRange = 5.0,      -- slider 1..10  (maps to [-2, +3] at default 5)
        CloudMinR   = 2.0,
        CloudMaxR   = 9.0,

        CampRadius  = 35,
        ScrapRadius = 35,
        AvoidLift   = 15,
        AvoidReeval = 0.2,
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

    local JOB_TIMEOUT_S      = 120
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
    local function setPivot(model, cf)
        if model:IsA("Model") then model:PivotTo(cf) else local p=mainPart(model); if p then p.CFrame=cf end end
    end
    local function getRemote(...)
        local re = RS:FindFirstChild("RemoteEvents"); if not re then return nil end
        for _,n in ipairs({...}) do local x=re:FindFirstChild(n); if x then return x end end
        return nil
    end
    local REM = {
        StartDrag = nil,
        StopDrag  = nil,
    }
    local function resolveRemotes()
        REM.StartDrag = getRemote("RequestStartDraggingItem","StartDraggingItem")
        REM.StopDrag  = getRemote("StopDraggingItem","RequestStopDraggingItem")
    end
    resolveRemotes()

    local function safeStartDrag(model)
        if REM.StartDrag and model and model.Parent then pcall(function() REM.StartDrag:FireServer(model) end); return true end
        return false
    end
    local function safeStopDrag(model)
        if REM.StopDrag and model and model.Parent then pcall(function() REM.StopDrag:FireServer(model) end); return true end
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
        for i=1, math.min(limit or #items, #items) do out[#out+1] = items[i].m end
        return out
    end

    local function playersList()
        local vals = {}
        for _,p in ipairs(Players:GetPlayers()) do if p ~= lp then vals[#vals+1]=("%s#%d"):format(p.Name, p.UserId) end end
        table.sort(vals); return vals
    end
    local function parseSelection(choice)
        local set = {}
        if type(choice) == "table" then
            for _,v in ipairs(choice) do local uid=tonumber((tostring(v):match("#(%d+)$") or "")); if uid then set[uid]=true end end
        else
            local uid=tonumber((tostring(choice or ""):match("#(%d+)$") or "")); if uid then set[uid]=true end
        end
        return set
    end
    local function selectedPlayersList(set)
        local out = {}
        for _,p in ipairs(Players:GetPlayers()) do if set[p.UserId] and p~=lp then out[#out+1]=p end end
        return out
    end

    local function rngFor(seed) return Random.new(math.clamp(math.floor((seed or 0) * 100000) % 2^31, 1, 2^31-1)) end
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
                                if dist < bestDist then bestDist, best = dist, d end
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
    local function avoidOffsetFor(pos)
        refreshAvoidTargets(os.clock())
        local lift = 0
        if campCache then
            local pc = partCenter(campCache)
            if pc and (pos - pc).Magnitude <= CFG.CampRadius then lift = math.max(lift, CFG.AvoidLift) end
        end
        if scrapCache then
            local ps = partCenter(scrapCache)
            if ps and (pos - ps).Magnitude <= CFG.ScrapRadius then lift = math.max(lift, CFG.AvoidLift) end
        end
        if lift > 0 then return Vector3.new(0, lift, 0) end
        return Vector3.new()
    end

    local running = false
    local desired = CFG.DesiredLogs
    local active  = {}          -- {model -> state}
    local activeList = {}       -- array of models for ordering
    local targets = {}          -- list of Players
    local reconcileConn, hbConn = nil, nil
    local lastDt = 1/60
    local scanAt = 0
    local scanCache = {}

    local function adopt(model, tgt, seed)
        if active[model] then return end
        active[model] = { target = tgt, t0 = os.clock(), seed = seed, rng = rngFor((seed or 0) + os.clock()),
                          slot = nil, reslotAt = 0, burstUntil = 0, burstDir = 1,
                          phases = { xz1=math.random()*math.pi*2, xz2=math.random()*math.pi*2, y1=math.random()*math.pi*2, y2=math.random()*math.pi*2 },
                          w = {
                              xz1 = math.random()*(W_XZ1_MAX-W_XZ1_MIN)+W_XZ1_MIN,
                              xz2 = math.random()*(W_XZ2_MAX-W_XZ2_MIN)+W_XZ2_MIN,
                              y1  = math.random()*(W_Y1_MAX -W_Y1_MIN )+W_Y1_MIN,
                              y2  = math.random()*(W_Y2_MAX -W_Y2_MIN )+W_Y2_MIN,
                          },
                          started = false,
                          snap = nil
        }
        table.insert(activeList, model)
        task.spawn(function()
            local st = active[model]; if not st then return end
            local started = safeStartDrag(model); st.started = started
            task.wait(0.05)
            st.snap = setCollide(model, false)
            for _,p in ipairs(getParts(model)) do pcall(function() p:SetNetworkOwner(lp) end) end
            zeroAssembly(model)
        end)
    end
    local function shed(model)
        local st = active[model]
        active[model] = nil
        for i=#activeList,1,-1 do if activeList[i]==model then table.remove(activeList,i) break end end
        if st and st.snap then setCollide(model, true, st.snap) end
        finallyStopDrag(model)
        for _,p in ipairs(getParts(model)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
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

    local function floatStep(model, st, dt)
        local tgtRoot = hrp(st.target)
        if not tgtRoot then
            if os.clock() - st.lastSeen > REASSIGN_IF_LOST_S then return false end
            return true
        end
        st.lastSeen = os.clock()
        ensureSlot(st)
        maybeBurst(st)

        local base = tgtRoot.Position
        local t = (os.clock() - (st.t0 or os.clock())) * CFG.Speed

        local jx = math.sin(t * st.w.xz1 + st.phases.xz1) * JIT_XZ1
                 + math.cos(t * st.w.xz2 + st.phases.xz2) * JIT_XZ2
        local jz = math.cos(t * st.w.xz1 * 0.8 + st.phases.xz1*0.7) * JIT_XZ1
                 + math.sin(t * st.w.xz2 * 1.3 + st.phases.xz2*0.5) * JIT_XZ2
        local jy = math.sin(t * st.w.y1  + st.phases.y1 ) * JIT_Y1
                 + math.cos(t * st.w.y2  + st.phases.y2 ) * JIT_Y2

        local off = st.slot + Vector3.new(jx, jy, jz)

        if os.clock() < st.burstUntil then
            local dirToTarget = (base - (base + off)).Unit
            off = off + dirToTarget * (BURST_PUSH_BASE * CFG.Speed * st.burstDir)
        end

        local pos = base + off + avoidOffsetFor(base)
        local look = (base - pos).Magnitude > 1e-3 and (base - pos).Unit or Vector3.new(0,0,-1)
        setPivot(model, CFrame.new(pos, pos + look))

        for _,p in ipairs(getParts(model)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
        return true
    end

    local function reconcile()
        if not running then return end
        local root = hrp(); if not root then return end
        if os.clock() >= scanAt then
            local exclude = {}
            for m,_ in pairs(active) do exclude[m]=true end
            scanCache = logsNear(root.Position, exclude, 200)
            scanAt = os.clock() + 0.8
        end
        local want = math.clamp(desired, 1, 50)
        local have = #activeList
        local batch = 4

        if have < want and lastDt <= (1/45) then
            local toAdd = math.min(batch, want - have)
            local idx = 1
            while toAdd > 0 and idx <= #scanCache do
                local mdl = scanCache[idx]; idx += 1
                if mdl and mdl.Parent and not active[mdl] then
                    local tgt = targets[ ((#activeList) % math.max(1,#targets)) + 1 ]
                    if tgt then
                        adopt(mdl, tgt, (#activeList + 1) * 0.73)
                        toAdd -= 1
                    end
                end
            end
        elseif have > want then
            local toDrop = math.min(batch, have - want)
            for i=have, math.max(1, have - toDrop + 1), -1 do
                local mdl = activeList[i]
                if mdl then shed(mdl) end
            end
        end
    end

    local function stopAll()
        running = false
        if reconcileConn then reconcileConn:Disconnect(); reconcileConn=nil end
        if hbConn then hbConn:Disconnect(); hbConn=nil end
        for i=#activeList,1,-1 do local mdl=activeList[i]; if mdl then shed(mdl) end end
        active = {}; activeList = {}
    end

    local selectedSet = {}
    tab:Section({ Title = "Troll: Chaotic Log Smog" })
    local playerDD = tab:Dropdown({
        Title = "Players",
        Values = playersList(),
        Multi = true,
        AllowNone = true,
        Callback = function(choice) selectedSet = parseSelection(choice) end
    })
    tab:Button({
        Title = "Refresh Player List",
        Callback = function()
            local vals = playersList()
            if playerDD and playerDD.SetValues then playerDD:SetValues(vals) end
        end
    })

    tab:Slider({
        Title = "Logs",
        Value = { Min = 1, Max = 50, Default = 5 },
        Callback = function(v)
            local n = tonumber(type(v)=="table" and (v.Value or v.Current or v.Default) or v)
            if n then desired = math.clamp(math.floor(n + 0.5), 1, 50) end
        end
    })
    tab:Slider({
        Title = "Speed",
        Value = { Min = 0.5, Max = 3.0, Default = 1.0 },
        Callback = function(v)
            local n = tonumber(type(v)=="table" and (v.Value or v.Current or v.Default) or v)
            if n then CFG.Speed = math.clamp(n, 0.5, 3.0) end
        end
    })
    tab:Slider({
        Title = "Height Range",
        Value = { Min = 1.0, Max = 10.0, Default = 5.0 },
        Callback = function(v)
            local n = tonumber(type(v)=="table" and (v.Value or v.Current or v.Default) or v)
            if n then CFG.HeightRange = math.clamp(n, 1.0, 10.0) end
        end
    })

    tab:Button({
        Title = "Start",
        Callback = function()
            stopAll()
            resolveRemotes()
            targets = selectedPlayersList(selectedSet)
            if #targets == 0 then return end
            running = true
            local last = os.clock()
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
            task.delay(JOB_TIMEOUT_S, function() if running then stopAll() end end)
        end
    })
    tab:Button({ Title = "Stop", Callback = function() stopAll() end })
end
