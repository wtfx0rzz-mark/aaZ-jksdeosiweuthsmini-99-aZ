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

    ----------------------------------------------------------------
    -- Tunables
    ----------------------------------------------------------------
    local MAX_LOGS               = 50
    local SEARCH_RADIUS          = 200
    local TICK                   = 0.02

    -- Chaotic/avoidance
    local CAMPFIRE_AVOID_RADIUS  = 35
    local SCRAPPER_AVOID_RADIUS  = 35
    local AVOID_LIFT             = 8
    local AVOID_REEVAL_S         = 0.2

    -- Bulldozer
    local BULL_MAX_LOGS   = 120
    local BULL_THICKNESS  = 3
    local BULL_PUSH_STUDS = 10
    local BULL_GAP_STUDS  = 2.0

    -- Box trap
    local BOX_RADIUS         = 20
    local BOX_TOP_ROWS       = 2
    local BOX_LOCK_IN_PLACE  = true   -- true = lock at snapshot, refresh every BOX_REFRESH_S; false = follow
    local BOX_REFRESH_S      = 5.0    -- re-fit cadence when locked
    local BOX_MAX_PER_TARGET = 16     -- pillar + roof budget per target
    ----------------------------------------------------------------

    local function mainPart(obj)
        if not obj or not obj.Parent then return nil end
        if obj:IsA("BasePart") then return obj end
        if obj:IsA("Model") then
            return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
        end
        return nil
    end
    local function hrp(p)
        p = p or lp
        local ch = p.Character or p.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end
    local function allParts(target)
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
        local parts = allParts(model)
        if on and snapshot then
            for part,can in pairs(snapshot) do
                if part and part.Parent then part.CanCollide = can end
            end
            return
        end
        local snap = {}
        for _,p in ipairs(parts) do
            snap[p] = p.CanCollide
            p.CanCollide = false
        end
        return snap
    end
    local function hardEnableCollision(model)
        for _,p in ipairs(allParts(model)) do
            p.Anchored = false
            p.CanCollide = true
            p.CanQuery  = true
            p.CanTouch  = true
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
        end
    end
    local function zeroAssembly(model)
        for _,p in ipairs(allParts(model)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            p.Anchored = false
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
    local rcache = {
        StartDrag = getRemote("RequestStartDraggingItem","StartDraggingItem"),
        StopDrag  = getRemote("StopDraggingItem","RequestStopDraggingItem"),
    }
    local function safeStartDrag(model)
        if rcache.StartDrag and model and model.Parent then
            pcall(function() rcache.StartDrag:FireServer(model) end)
            return true
        end
        return false
    end
    local function safeStopDrag(model)
        if rcache.StopDrag and model and model.Parent then
            pcall(function() rcache.StopDrag:FireServer(model) end)
            return true
        end
        return false
    end
    local function finallyStopDrag(model)
        task.delay(0.05, function() pcall(safeStopDrag, model) end)
        task.delay(0.20, function() pcall(safeStopDrag, model) end)
    end

    local function logsNearMe(maxCount, exclude)
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
                if m and m.Name == "Log" and not uniq[m] and not (exclude and exclude[m]) then
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

    local function fireCenterPart(fire)
        return fire and (fire:FindFirstChild("Center")
            or fire:FindFirstChild("InnerTouchZone")
            or fire.PrimaryPart
            or fire:FindFirstChildWhichIsA("BasePart")) or nil
    end
    local function resolveCampfireModel()
        local map = WS:FindFirstChild("Map")
        local cg  = map and map:FindFirstChild("Campground")
        local mf  = cg and cg:FindFirstChild("MainFire")
        if mf then return mf end
        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") then
                local n = (d.Name or ""):lower()
                if n:find("campfire",1,true) or n=="mainfire" or n=="camp fire" then
                    return d
                end
            end
        end
        return nil
    end
    local function resolveScrapperModel()
        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") then
                local n = (d.Name or ""):lower()
                if n:find("scrap",1,true) or n:find("scrapper",1,true) then
                    return d
                end
            end
        end
        return nil
    end

    local lastAvoidCheck, campCenter, scrapCenter = 0, nil, nil
    local function refreshAvoidCenters()
        local camp = resolveCampfireModel()
        local c = fireCenterPart(camp)
        campCenter = c and (c.Position or (camp:GetPivot().Position)) or nil
        local scr  = resolveScrapperModel()
        local s = fireCenterPart(scr) or (scr and scr.PrimaryPart)
        scrapCenter = s and (s.Position or (scr:GetPivot().Position)) or nil
    end
    local function avoidLift(basePos)
        local now = os.clock()
        if now - (lastAvoidCheck or 0) >= AVOID_REEVAL_S then
            refreshAvoidCenters()
            lastAvoidCheck = now
        end
        local dCamp = campCenter and (basePos - campCenter).Magnitude or math.huge
        local dScr  = scrapCenter and (basePos - scrapCenter).Magnitude or math.huge
        if dCamp <= CAMPFIRE_AVOID_RADIUS or dScr <= SCRAPPER_AVOID_RADIUS then
            return AVOID_LIFT
        end
        return 0
    end

    ----------------------------------------------------------------
    -- Chaotic float (unchanged behavior; used as reference)
    ----------------------------------------------------------------
    local chaoticRunning = false
    local chaoticActiveJobs = {}
    local chaoticAssigned = setmetatable({}, {__mode="k"})
    local chaoticTargetOf = setmetatable({}, {__mode="k"})

    local function floatAroundTarget(model, targetPlayer, seed)
        chaoticTargetOf[model] = targetPlayer
        chaoticAssigned[model] = true
        local started = safeStartDrag(model)
        task.wait(0.05)
        local snap = setCollide(model, false)
        zeroAssembly(model)

        local rng = Random.new(math.floor((seed or 0)*100000)%2147483646 + 1)
        local function pickOffset()
            local r  = rng:NextNumber(2, 9)
            local th = rng:NextNumber(0, math.pi*2)
            local ph = rng:NextNumber(-0.85, 0.85)
            local x = r * math.cos(th) * math.cos(ph)
            local z = r * math.sin(th) * math.cos(ph)
            local y = 0.5 + rng:NextNumber(-2.0, 3.0)
            return Vector3.new(x, y, z)
        end
        local slot, reslotAt = nil, 0

        chaoticActiveJobs[model] = true
        while chaoticRunning and chaoticActiveJobs[model] do
            local root = hrp(chaoticTargetOf[model])
            if not root then break end

            if (not slot) or os.clock() >= reslotAt then
                slot = pickOffset()
                reslotAt = os.clock() + rng:NextNumber(0.45, 1.20)
            end
            local base = root.Position
            local lift = avoidLift(base)
            local noise = Vector3.new(
                math.sin(os.clock()*1.7 + seed)*1.3,
                math.cos(os.clock()*2.1 + seed)*0.8,
                math.cos(os.clock()*1.3 + seed*1.9)*1.1
            )
            local pos  = base + slot + noise + Vector3.new(0, lift, 0)
            local look = (base - pos).Unit
            setPivot(model, CFrame.new(pos, pos + look))
            hardEnableCollision(model)
            task.wait(TICK)
        end
        setCollide(model, true, snap)
        if started then finallyStopDrag(model) end
        chaoticActiveJobs[model] = nil
        chaoticAssigned[model] = nil
        chaoticTargetOf[model] = nil
    end

    local function logsNearMeExcluding(excl, n)
        return logsNearMe(n or MAX_LOGS, excl)
    end
    local function assignChaotic(models, targets)
        if #targets == 0 then return end
        local idx = 1
        for i,mdl in ipairs(models) do
            if not chaoticAssigned[mdl] then
                chaoticAssigned[mdl] = true
                local tgt = targets[idx]
                chaoticTargetOf[mdl] = tgt
                task.spawn(function() floatAroundTarget(mdl, tgt, i*0.73 + idx*1.11) end)
                idx += 1
                if idx > #targets then idx = 1 end
            end
        end
    end
    local function chaoticSupervisor(targets)
        while chaoticRunning do
            for m,_ in pairs(chaoticAssigned) do
                if (not m) or (not m.Parent) or (not chaoticActiveJobs[m]) then chaoticAssigned[m] = nil end
            end
            local cur = 0; for _ in pairs(chaoticActiveJobs) do cur+=1 end
            local need = math.max(0, math.min(MAX_LOGS, #targets * math.ceil(MAX_LOGS / math.max(1,#targets))) - cur)
            if need > 0 then
                local exclude = {}
                for m,_ in pairs(chaoticAssigned) do exclude[m] = true end
                local pool = logsNearMeExcluding(exclude, need*2)
                if #pool > 0 then assignChaotic(pool, targets) end
            end
            Run.Heartbeat:Wait()
        end
    end

    ----------------------------------------------------------------
    -- Bulldozer
    ----------------------------------------------------------------
    local function groundAhead(root)
        if not root then return nil end
        local ch   = lp.Character
        local head = ch and ch:FindFirstChild("Head")
        local castFrom = (head and head.Position or root.Position) + root.CFrame.LookVector * 3
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character, WS:FindFirstChild("Items") }
        local hit = WS:Raycast(castFrom, Vector3.new(0, -2000, 0), params)
        return hit and hit.Position or (castFrom - Vector3.new(0, 3, 0))
    end
    local function wallPositions(frontCF, count, thickness, gapBack)
        local t = math.max(1, thickness or 1)
        local cols = math.clamp(math.ceil(math.sqrt(count / t)), 4, 12)
        local rows = math.clamp(math.ceil(count / (cols * t)), 2, 10)
        local spacingX, spacingY, spacingZ = 2.2, 1.6, 1.6
        local fw, rt, up = frontCF.LookVector, frontCF.RightVector, frontCF.UpVector
        local center = frontCF.Position + fw * 2.5
        local totalW = (cols - 1) * spacingX
        local totalH = (rows - 1) * spacingY
        local totalD = (t - 1)   * spacingZ
        local positions = {}
        for d=0,t-1 do
            for r=0,rows-1 do
                for c=0,cols-1 do
                    if #positions >= count then break end
                    local offX = (c * spacingX) - totalW * 0.5
                    local offY = (r * spacingY) - totalH * 0.4
                    local offZ = (d * spacingZ) - totalD * 0.5
                    local p = center + rt * offX + up * offY - fw * offZ
                    positions[#positions+1] = CFrame.new(p, p + fw)
                end
                if #positions >= count then break end
            end
            if #positions >= count then break end
        end
        if gapBack and gapBack > 0 then
            local back = {}
            for i=1,#positions do back[i] = positions[i] - fw * gapBack end
            return positions, back, fw
        end
        return positions, nil, fw
    end
    local function placeAt(models, cfs, keepNoCollide)
        local snaps = {}
        for i,m in ipairs(models) do
            if m and m.Parent and cfs[i] then
                snaps[m] = setCollide(m, false)
                zeroAssembly(m)
                setPivot(m, cfs[i])
                if not keepNoCollide then setCollide(m, true, snaps[m]); snaps[m] = nil end
            end
        end
        return snaps
    end
    local function pushForwardHold(models, fw, studs)
        local dist = math.max(0, studs or 10)
        local speed, step = 32, 0.03
        local t, tEnd = 0, dist / speed
        while t < tEnd do
            for _,m in ipairs(models) do
                if m and m.Parent then
                    local pivot = m:IsA("Model") and m:GetPivot() or (mainPart(m) and mainPart(m).CFrame)
                    if pivot then
                        local newPos = pivot.Position + fw * (speed * step) + Vector3.new(0, avoidLift(pivot.Position), 0)
                        setPivot(m, CFrame.new(newPos, newPos + fw))
                        hardEnableCollision(m)
                    end
                end
            end
            t += step
            task.wait(step)
        end
    end
    local function bulldozeOnce()
        local root = hrp(); if not root then return end
        local logs = logsNearMe(BULL_MAX_LOGS, {})
        if #logs == 0 then return end
        for _,m in ipairs(logs) do safeStartDrag(m) end
        task.wait(0.03)
        local baseGround = groundAhead(root)
        local frontCF = CFrame.new(
            Vector3.new(baseGround.X, baseGround.Y + 3.0, baseGround.Z),
            (root.Position + root.CFrame.LookVector*6)
        )
        local half = math.ceil(#logs/2)
        local groupA, groupB = {}, {}
        for i=1,#logs do if i<=half then groupA[#groupA+1]=logs[i] else groupB[#groupB+1]=logs[i] end end
        local cfsA, _, fw = wallPositions(frontCF, #groupA, BULL_THICKNESS, 0)
        local cfsB = {table.unpack(cfsA)}
        for i=1,#cfsB do cfsB[i] = cfsB[i] - fw * BULL_GAP_STUDS end
        local snapsA = placeAt(groupA, cfsA, true)
        local snapsB = placeAt(groupB, cfsB, true)
        task.wait(0.03)
        pushForwardHold(groupA, fw, BULL_PUSH_STUDS)
        pushForwardHold(groupB, fw, BULL_PUSH_STUDS)
        task.delay(0.10, function()
            for m,s in pairs(snapsA) do setCollide(m, true, s) end
            for m,s in pairs(snapsB) do setCollide(m, true, s) end
            for _,m in ipairs(logs) do finallyStopDrag(m) end
        end)
    end

    ----------------------------------------------------------------
    -- Box trap with stop, lock/follow, roof center, auto-replace, avoidance
    ----------------------------------------------------------------
    local function targetsWithin(radius)
        local root = hrp(); if not root then return {} end
        local center = root.Position
        local out, seen = {}, {}
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(center, radius, params) or {}
        for _,part in ipairs(parts) do
            if part:IsA("BasePart") then
                local m = part:FindFirstAncestorOfClass("Model")
                if m and m.Parent and not seen[m] then
                    local isPlayer = m:FindFirstChild("HumanoidRootPart") and m:FindFirstChildOfClass("Humanoid")
                    if isPlayer then
                        local owner = Players:GetPlayerFromCharacter(m)
                        if not owner or owner ~= lp then seen[m] = true; out[#out+1] = m end
                    else
                        local hum = m:FindFirstChildOfClass("Humanoid")
                        if hum then seen[m] = true; out[#out+1] = m end
                    end
                end
            end
        end
        return out
    end

    local function makeCageCFs(centerPos, side, baseY, heightY)
        -- 4 pillars + a simple roof ring and one center roof log
        local half = side * 0.5
        local rt, fw, up = Vector3.new(1,0,0), Vector3.new(0,0,1), Vector3.new(0,1,0)
        local c = centerPos
        local corner = {
            c + rt*half + fw*half,
            c - rt*half + fw*half,
            c + rt*half - fw*half,
            c - rt*half - fw*half,
        }
        local pillars = {}
        for i=1,4 do
            local p = Vector3.new(corner[i].X, baseY, corner[i].Z)
            pillars[#pillars+1] = CFrame.new(p, p + up)
        end
        local roof = {}
        for i=1,4 do
            for r=0,BOX_TOP_ROWS-1 do
                local p = Vector3.new(corner[i].X, heightY + r*1.4, corner[i].Z)
                roof[#roof+1] = CFrame.new(p, p + fw)
            end
        end
        -- center roof log (new)
        local centerRoof = CFrame.new(Vector3.new(c.X, heightY + 0.7, c.Z), c + fw)
        return pillars, roof, centerRoof
    end

    -- Box trap state
    local boxTrapOn = false
    local boxSlots = {}    -- [targetModel] = { logs = {m1=..., ...}, anchors = {fn per log}, lastSnapPos = Vector3 }
    local holdThreads = setmetatable({}, {__mode="k"})

    local function startHold(model, anchorFn)
        if holdThreads[model] then return end
        local started = safeStartDrag(model)
        local snap = setCollide(model, false)
        zeroAssembly(model)
        holdThreads[model] = task.spawn(function()
            while boxTrapOn do
                if not model or not model.Parent then break end
                local cf = anchorFn(); if not cf then break end
                -- avoidance lift applied via anchorFn or here:
                local pos = cf.Position
                local lift = avoidLift(pos)
                if lift ~= 0 then cf = cf + Vector3.new(0, lift, 0) end
                setPivot(model, cf)
                hardEnableCollision(model)
                task.wait(TICK)
            end
            setCollide(model, true, snap)
            if started then finallyStopDrag(model) end
            holdThreads[model] = nil
        end)
    end

    local function stopBoxTrap()
        boxTrapOn = false
        for mdl, th in pairs(holdThreads) do
            if th then pcall(task.cancel, th) end
            if mdl and mdl.Parent then
                hardEnableCollision(mdl)
                finallyStopDrag(mdl)
            end
            holdThreads[mdl] = nil
        end
        boxSlots = {}
    end

    local function takeLogs(n, exclude)
        local pool = logsNearMe(n*2, exclude)
        local out = {}
        for i=1, math.min(n, #pool) do
            out[#out+1] = pool[i]
            if exclude then exclude[pool[i]] = true end
        end
        return out
    end

    local function ensureSlotLog(slotRec, idx, maker)
        local m = slotRec.logs[idx]
        if m and m.Parent and holdThreads[m] then return m end
        -- need replacement
        local replace = takeLogs(1, slotRec.used)[1]
        if not replace then return nil end
        slotRec.logs[idx] = replace
        slotRec.used[replace] = true
        startHold(replace, maker)
        return replace
    end

    local function fitBoxForTarget(targetModel, snapPos)
        local mp = mainPart(targetModel); if not mp then return nil end
        local sizeY = (mp.Size and mp.Size.Y) or 4
        local baseY = math.max((mp.Position.Y - sizeY*0.5) + 0.5, mp.Position.Y - 2)
        local heightY = mp.Position.Y + sizeY*0.5 + 2.5
        local side = math.clamp(math.max(mp.Size.X, mp.Size.Z) + 2.5, 4.0, 8.0)
        local center = (BOX_LOCK_IN_PLACE and snapPos) or mp.Position

        local pillars, roof, centerRoof = makeCageCFs(center, side, baseY, heightY)
        -- cap the number of roof logs to budget
        while (#pillars + #roof + 1) > BOX_MAX_PER_TARGET and #roof > 0 do
            table.remove(roof) -- trim roof if over budget
        end
        return pillars, roof, centerRoof
    end

    local function startBoxTrap()
        stopBoxTrap() -- reset
        local targets = targetsWithin(BOX_RADIUS)
        if #targets == 0 then return end

        boxTrapOn = true
        local exclude = {}
        for _,tgt in ipairs(targets) do
            local mp = mainPart(tgt); if not mp then continue end
            local snapPos = mp.Position
            local pillars, roof, centerRoof = fitBoxForTarget(tgt, snapPos)
            local total = math.min(BOX_MAX_PER_TARGET, #pillars + #roof + 1)
            local list = takeLogs(total, exclude)
            if #list == 0 then break end

            local slot = { logs = {}, used = {}, lastSnap = snapPos, make = {} }
            boxSlots[tgt] = slot
            for _,m in ipairs(list) do slot.used[m] = true end

            local k = 1
            for i=1,#pillars do
                local myIndex = k
                slot.make[myIndex] = function()
                    if not boxTrapOn then return nil end
                    if not tgt or not tgt.Parent then return nil end
                    local usePos = (BOX_LOCK_IN_PLACE and slot.lastSnap) or (mainPart(tgt) and mainPart(tgt).Position) or snapPos
                    local p, _, _ = makeCageCFs(usePos, math.clamp(math.max((mainPart(tgt).Size or Vector3.new(4,4,4)).X, (mainPart(tgt).Size or Vector3.new(4,4,4)).Z) + 2.5, 4.0, 8.0),
                                                math.max((usePos.Y - ((mainPart(tgt).Size and mainPart(tgt).Size.Y) or 4)*0.5) + 0.5, usePos.Y - 2),
                                                usePos.Y + (((mainPart(tgt).Size and mainPart(tgt).Size.Y) or 4)*0.5) + 2.5)
                    return p[i]
                end
                slot.logs[myIndex] = list[k]; startHold(list[k], slot.make[myIndex]); k += 1
            end
            for j=1,#roof do
                if k > #list then break end
                local myIndex = k
                slot.make[myIndex] = function()
                    if not boxTrapOn then return nil end
                    if not tgt or not tgt.Parent then return nil end
                    local usePos = (BOX_LOCK_IN_PLACE and slot.lastSnap) or (mainPart(tgt) and mainPart(tgt).Position) or snapPos
                    local _, r, _ = makeCageCFs(usePos, math.clamp(math.max((mainPart(tgt).Size or Vector3.new(4,4,4)).X, (mainPart(tgt).Size or Vector3.new(4,4,4)).Z) + 2.5, 4.0, 8.0),
                                                math.max((usePos.Y - ((mainPart(tgt).Size and mainPart(tgt).Size.Y) or 4)*0.5) + 0.5, usePos.Y - 2),
                                                usePos.Y + (((mainPart(tgt).Size and mainPart(tgt).Size.Y) or 4)*0.5) + 2.5)
                    return r[j]
                end
                slot.logs[myIndex] = list[k]; startHold(list[k], slot.make[myIndex]); k += 1
            end
            -- center roof log
            if k <= #list then
                local myIndex = k
                slot.make[myIndex] = function()
                    if not boxTrapOn then return nil end
                    if not tgt or not tgt.Parent then return nil end
                    local mp2 = mainPart(tgt); if not mp2 then return nil end
                    local sizeY = (mp2.Size and mp2.Size.Y) or 4
                    local heightY = mp2.Position.Y + sizeY*0.5 + 2.5
                    local centerRoof = CFrame.new(Vector3.new(((BOX_LOCK_IN_PLACE and slot.lastSnap) or mp2.Position).X, heightY + 0.7, ((BOX_LOCK_IN_PLACE and slot.lastSnap) or mp2.Position).Z), mp2.Position + Vector3.new(0,0,1))
                    return centerRoof
                end
                slot.logs[myIndex] = list[k]; startHold(list[k], slot.make[myIndex]); k += 1
            end
        end

        -- Replacement + optional re-fit supervisor
        task.spawn(function()
            local acc = 0
            while boxTrapOn do
                local dt = Run.Heartbeat:Wait()
                acc += dt
                for tgt, slot in pairs(boxSlots) do
                    if not tgt or not tgt.Parent then boxSlots[tgt] = nil else
                        -- lock-in-place refresh
                        if BOX_LOCK_IN_PLACE and acc >= BOX_REFRESH_S then
                            local mp = mainPart(tgt)
                            if mp then slot.lastSnap = slot.lastSnap or mp.Position end
                            -- keep same positions; only re-evaluate make() lazily per tick
                        elseif (not BOX_LOCK_IN_PLACE) then
                            -- follow: nothing to do; makers read live target position
                        end
                        -- auto-replace any missing logs
                        for i=1,#slot.logs do
                            ensureSlotLog(slot, i, slot.make[i])
                        end
                    end
                end
                if acc >= BOX_REFRESH_S then acc = 0 end
            end
        end)
    end

    ----------------------------------------------------------------
    -- UI
    ----------------------------------------------------------------
    tab:Section({ Title = "Troll: Chaotic Log Smog" })
    local selectedPlayers = {}
    local function playerChoices()
        local vals = {}
        for _,p in ipairs(Players:GetPlayers()) do
            if p ~= lp then vals[#vals+1] = ("%s#%d"):format(p.Name, p.UserId) end
        end
        table.sort(vals)
        return vals
    end
    local function parseSelection(choice)
        local set = {}
        if type(choice) == "table" then
            for _,v in ipairs(choice) do local uid = tonumber((tostring(v):match("#(%d+)$") or "")); if uid then set[tostring(uid)] = true end end
        else
            local uid = tonumber((tostring(choice or ""):match("#(%d+)$") or "")); if uid then set[tostring(uid)] = true end
        end
        return set
    end
    local playerDD = tab:Dropdown({
        Title = "Players",
        Values = playerChoices(),
        Multi = true,
        AllowNone = true,
        Callback = function(choice) selectedPlayers = parseSelection(choice) end
    })
    tab:Button({ Title = "Refresh Player List", Callback = function()
        local vals = playerChoices()
        if playerDD and playerDD.SetValues then playerDD:SetValues(vals) end
    end })

    tab:Button({ Title = "Chaos: Start", Callback = function()
        chaoticRunning = false
        for _,th in pairs(chaoticActiveJobs) do pcall(task.cancel, th) end
        chaoticActiveJobs, chaoticAssigned, chaoticTargetOf = {}, setmetatable({}, {__mode="k"}), setmetatable({}, {__mode="k"})
        local targets = {}
        for userIdStr,_ in pairs(selectedPlayers or {}) do
            local uid = tonumber(userIdStr)
            for _,p in ipairs(Players:GetPlayers()) do
                if p.UserId == uid and p ~= lp then targets[#targets+1] = p break end
            end
        end
        if #targets == 0 then return end
        local pool = logsNearMe(MAX_LOGS, {})
        if #pool == 0 then return end
        chaoticRunning = true
        assignChaotic(pool, targets)
        task.spawn(function() chaoticSupervisor(targets) end)
    end })
    tab:Button({ Title = "Chaos: Stop", Callback = function()
        chaoticRunning = false
        for mdl,th in pairs(chaoticActiveJobs) do if th then pcall(task.cancel, th) end chaoticActiveJobs[mdl]=nil end
        for mdl,_ in pairs(chaoticAssigned) do if mdl and mdl.Parent then finallyStopDrag(mdl); hardEnableCollision(mdl) end chaoticAssigned[mdl]=nil end
        chaoticTargetOf = {}
    end })

    tab:Section({ Title = "Troll: Bulldozer" })
    tab:Button({ Title = "Log Bulldozer", Callback = function() bulldozeOnce() end })
    tab:Slider({
        Title = "Bulldozer Thickness",
        Value = { Min = 1, Max = 5, Default = BULL_THICKNESS },
        Callback = function(v) local nv=tonumber(type(v)=="table" and (v.Value or v.Default) or v); if nv then BULL_THICKNESS = math.clamp(nv,1,5) end end
    })

    tab:Section({ Title = "Troll: Box Trap" })
    tab:Toggle({
        Title = "Box Trap Lock In Place",
        Value = BOX_LOCK_IN_PLACE,
        Callback = function(state) BOX_LOCK_IN_PLACE = state and true or false end
    })
    tab:Slider({
        Title = "Box Trap Refresh (s)",
        Value = { Min = 1, Max = 15, Default = BOX_REFRESH_S },
        Callback = function(v) local nv=tonumber(type(v)=="table" and (v.Value or v.Default) or v); if nv then BOX_REFRESH_S = math.clamp(nv,1,30) end end
    })
    tab:Button({ Title = "Box Trap: Start", Callback = function() startBoxTrap() end })
    tab:Button({ Title = "Box Trap: Stop",  Callback = function() stopBoxTrap()  end })
end
