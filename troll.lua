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

    local MAX_LOGS          = 50
    local SEARCH_RADIUS     = 200
    local TICK              = 0.02

    local CAMPFIRE_AVOID_RADIUS = 20
    local CAMPFIRE_AVOID_UP     = 8
    local CAMPFIRE_REEVAL_S     = 0.2

    local BULL_MAX_LOGS    = 120
    local BULL_THICKNESS   = 3
    local BULL_PUSH_STUDS  = 10

    local function mainPart(obj)
        if not obj or not obj.Parent then return nil end
        if obj:IsA("BasePart") then return obj end
        if obj:IsA("Model") then
            if obj.PrimaryPart then return obj.PrimaryPart end
            return obj:FindFirstChildWhichIsA("BasePart")
        end
        return nil
    end
    local function hrp(p)
        p = p or lp
        local ch = p.Character or p.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
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
        if model:IsA("Model") then model:PivotTo(cf) else local p=mainPart(model); if p then p.CFrame=cf end end
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
    local rcache = resolveRemotes()
    local function safeStartDrag(r, model)
        if r and r.StartDrag and model and model.Parent then pcall(function() r.StartDrag:FireServer(model) end); return true end
        return false
    end
    local function safeStopDrag(r, model)
        if r and r.StopDrag and model and model.Parent then pcall(function() r.StopDrag:FireServer(model) end); return true end
        return false
    end
    local function finallyStopDrag(r, model)
        task.delay(0.05, function() pcall(safeStopDrag, r, model) end)
        task.delay(0.20, function() pcall(safeStopDrag, r, model) end)
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
                if n == "mainfire" or n == "campfire" or n == "camp fire" then
                    return d
                end
            end
        end
        return nil
    end

    local running = false
    local activeJobs = {}
    local modelToTarget = setmetatable({}, {__mode="k"})
    local assignedSet = setmetatable({}, {__mode="k"})

    local lastCampCheck, campModel, campCenter = 0, nil, nil
    local function refreshCamp()
        campModel = resolveCampfireModel()
        local c = fireCenterPart(campModel)
        campCenter = c and (c.Position or (campModel:GetPivot().Position)) or nil
    end

    local function floatAroundTarget(model, targetPlayer, seed)
        modelToTarget[model] = targetPlayer
        assignedSet[model] = true
        local started = safeStartDrag(rcache, model)
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
        local avoidUp, avoidUntil = 0, 0

        activeJobs[model] = true
        while running and activeJobs[model] do
            local root = hrp(modelToTarget[model])
            if not root then break end

            local now = os.clock()
            if now - (lastCampCheck or 0) >= CAMPFIRE_REEVAL_S then
                refreshCamp()
                lastCampCheck = now
            end
            if campCenter then
                local d = (root.Position - campCenter).Magnitude
                if d <= CAMPFIRE_AVOID_RADIUS then
                    avoidUp = CAMPFIRE_AVOID_UP
                    avoidUntil = now + 0.35
                elseif now >= avoidUntil then
                    avoidUp = 0
                end
            else
                avoidUp = (now >= avoidUntil) and 0 or avoidUp
            end

            if (not slot) or now >= reslotAt then
                slot = pickOffset()
                reslotAt = now + rng:NextNumber(0.45, 1.20)
            end
            local jx = math.sin(now* (rng:NextNumber(1.2,2.4))) * 1.4 + math.cos(now*(rng:NextNumber(2.0,3.6))) * 0.9
            local jz = math.cos(now* (rng:NextNumber(1.0,2.0))) * 1.4 + math.sin(now*(rng:NextNumber(2.0,4.0))) * 0.9
            local jy = math.sin(now* (rng:NextNumber(1.0,2.0))) * 0.9 + math.cos(now*(rng:NextNumber(2.0,4.0))) * 0.6
            local off = slot + Vector3.new(jx, jy + avoidUp, jz)
            local base = root.Position
            local pos  = base + off
            local look = (base - pos).Unit
            setPivot(model, CFrame.new(pos, pos + look))
            for _,p in ipairs(getAllParts(model)) do
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
                p.Anchored = false
                p.CanCollide = true
            end
            task.wait(TICK)
        end
        setCollide(model, true, snap)
        if started then finallyStopDrag(rcache, model) end
        activeJobs[model] = nil
        assignedSet[model] = nil
        modelToTarget[model] = nil
    end

    local function assignAndStart(models, targets, startIndex)
        if #targets == 0 then return startIndex end
        local idx = startIndex or 1
        for i,mdl in ipairs(models) do
            if not assignedSet[mdl] then
                local tgt = targets[idx]
                assignedSet[mdl] = true
                modelToTarget[mdl] = tgt
                task.spawn(function() floatAroundTarget(mdl, tgt, i*0.73 + idx*1.11) end)
                idx += 1
                if idx > #targets then idx = 1 end
            end
        end
        return idx
    end

    local function selectedPlayersList(selectedSet)
        local out = {}
        for userIdStr,_ in pairs(selectedSet or {}) do
            local uid = tonumber(userIdStr)
            if uid then
                for _,p in ipairs(Players:GetPlayers()) do
                    if p.UserId == uid and p ~= lp then out[#out+1] = p; break end
                end
            end
        end
        return out
    end
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

    local function supervisor(targets)
        local rr = 1
        while running do
            for m,_ in pairs(assignedSet) do
                if (not m) or (not m.Parent) or (not activeJobs[m]) then assignedSet[m] = nil end
            end
            local cur = 0; for _ in pairs(activeJobs) do cur+=1 end
            local need = math.max(0, math.min(MAX_LOGS, #targets * math.ceil(MAX_LOGS / math.max(1,#targets))) - cur)
            if need > 0 then
                local exclude = {}
                for m,_ in pairs(assignedSet) do exclude[m] = true end
                local pool = logsNearMe(need*2, exclude)
                if #pool > 0 then rr = assignAndStart(pool, targets, rr) end
            end
            Run.Heartbeat:Wait()
        end
    end

    local function startFloat(initialLogs, targets)
        if #targets == 0 then return end
        running = true
        activeJobs = {}
        assignedSet = setmetatable({}, {__mode="k"})
        modelToTarget = setmetatable({}, {__mode="k"})
        refreshCamp()
        assignAndStart(initialLogs, targets, 1)
        task.spawn(function() supervisor(targets) end)
    end

    local function stopAll()
        running = false
        for m,_ in pairs(activeJobs) do
            if m and m.Parent then
                for _,p in ipairs(getAllParts(m)) do
                    p.Anchored = false
                    p.CanCollide = true
                    p.AssemblyLinearVelocity  = Vector3.new()
                    p.AssemblyAngularVelocity = Vector3.new()
                    pcall(function() p:SetNetworkOwner(nil) end)
                    pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
                end
            end
            activeJobs[m] = nil
            assignedSet[m] = nil
            modelToTarget[m] = nil
        end
    end

    tab:Section({ Title = "Troll: Chaotic Log Smog" })
    local selectedPlayers = {}
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
    tab:Button({ Title = "Start", Callback = function()
        stopAll()
        local targets = selectedPlayersList(selectedPlayers)
        if #targets == 0 then return end
        local logs = logsNearMe(MAX_LOGS)
        if #logs == 0 then return end
        startFloat(logs, targets)
    end })
    tab:Button({ Title = "Stop", Callback = function() stopAll() end })

    local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
    local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
    if not edgeGui then
        edgeGui = Instance.new("ScreenGui")
        edgeGui.Name = "EdgeButtons"
        edgeGui.ResetOnSpawn = false
        pcall(function() edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
        edgeGui.Parent = playerGui
    end
    local stack = edgeGui:FindFirstChild("EdgeStack")
    if not stack then
        stack = Instance.new("Frame")
        stack.Name = "EdgeStack"
        stack.AnchorPoint = Vector2.new(1, 0)
        stack.Position = UDim2.new(1, -6, 0, 6)
        stack.Size = UDim2.new(0, 130, 1, -12)
        stack.BackgroundTransparency = 1
        stack.BorderSizePixel = 0
        stack.Parent = edgeGui
        local list = Instance.new("UIListLayout")
        list.Name = "VList"
        list.FillDirection = Enum.FillDirection.Vertical
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Padding = UDim.new(0, 6)
        list.HorizontalAlignment = Enum.HorizontalAlignment.Right
        list.Parent = stack
    end
    local function makeEdgeBtn(name, label, order)
        local b = stack:FindFirstChild(name)
        if not b then
            b = Instance.new("TextButton")
            b.Name = name
            b.Size = UDim2.new(1, 0, 0, 30)
            b.Text = label
            b.TextSize = 12
            b.Font = Enum.Font.GothamBold
            b.BackgroundColor3 = Color3.fromRGB(30,30,35)
            b.TextColor3 = Color3.new(1,1,1)
            b.BorderSizePixel = 0
            b.Visible = false
            b.LayoutOrder = order or 50
            b.Parent = stack
            local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = b
        else
            b.Text = label
            b.LayoutOrder = order or b.LayoutOrder
            b.Visible = false
        end
        return b
    end

    local bullBtn = makeEdgeBtn("LogBulldozerEdge", "Log Bulldozer", 50)

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

    local function wallPositionsThick(frontCF, count, thickness)
        local t = math.max(1, thickness or 1)
        local cols = math.clamp(math.ceil(math.sqrt(count / t)), 4, 12)
        local rows = math.clamp(math.ceil(count / (cols * t)), 2, 10)
        local spacingX = 2.2
        local spacingY = 1.6
        local spacingZ = 1.6
        local fw = frontCF.LookVector
        local rt = frontCF.RightVector
        local up = frontCF.UpVector
        local center = frontCF.Position + fw * 2.5
        local positions = {}
        local totalW = (cols - 1) * spacingX
        local totalH = (rows - 1) * spacingY
        local totalD = (t - 1)   * spacingZ
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
        return positions, fw
    end

    local function placeWall(models, frontCF, thickness)
        local poses, fw = wallPositionsThick(frontCF, #models, thickness)
        for i,m in ipairs(models) do
            if m and m.Parent then
                local snap = setCollide(m, false)
                zeroAssembly(m)
                setPivot(m, poses[i])
                setCollide(m, true, snap)
            end
        end
        return fw
    end

    local function pushForward(models, fw, studs)
        local dist = math.max(0, studs or 10)
        local speed = 32
        local step = 0.03
        local tEnd = dist / speed
        local t = 0
        local snaps = {}
        for _,m in ipairs(models) do snaps[m] = setCollide(m, false) end
        while t < tEnd do
            for _,m in ipairs(models) do
                if m and m.Parent then
                    local pivot = m:IsA("Model") and m:GetPivot() or (mainPart(m) and mainPart(m).CFrame)
                    if pivot then
                        local newPos = pivot.Position + fw * (speed * step)
                        setPivot(m, CFrame.new(newPos, newPos + fw))
                        for _,p in ipairs(getAllParts(m)) do
                            p.Anchored = false
                            p.CanCollide = true
                            p.AssemblyLinearVelocity  = Vector3.new()
                            p.AssemblyAngularVelocity = Vector3.new()
                            p:SetNetworkOwner(nil)
                            if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end
                        end
                    end
                end
            end
            t += step
            task.wait(step)
        end
        for m,s in pairs(snaps) do setCollide(m, true, s) end
    end

    local function bulldozeOnce()
        local root = hrp(); if not root then return end
        local logs = logsNearMe(BULL_MAX_LOGS, {})
        if #logs == 0 then return end
        local r = rcache
        for _,m in ipairs(logs) do safeStartDrag(r, m) end
        task.wait(0.05)
        local baseGround = groundAhead(root)
        local frontCF = CFrame.new(
            Vector3.new(baseGround.X, baseGround.Y + 3.0, baseGround.Z),
            (root.Position + root.CFrame.LookVector*6)
        )
        local fw = placeWall(logs, frontCF, BULL_THICKNESS)
        task.wait(0.05)
        pushForward(logs, fw, BULL_PUSH_STUDS)
        task.delay(0.1, function() for _,m in ipairs(logs) do finallyStopDrag(r, m) end end)
    end

    bullBtn.MouseButton1Click:Connect(function() bulldozeOnce() end)
    local showBulldozer = false
    tab:Toggle({
        Title = "Edge Button: Log Bulldozer",
        Value = false,
        Callback = function(state)
            showBulldozer = state and true or false
            if bullBtn then bullBtn.Visible = showBulldozer end
        end
    })

    local boxBtn = makeEdgeBtn("BoxTrapEdge", "Box Trap", 51)

    local function targetsWithin(radius)
        local root = hrp(); if not root then return {} end
        local center = root.Position
        local out = {}
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(center, radius, params) or {}
        local uniqModel = {}
        for _,part in ipairs(parts) do
            if part:IsA("BasePart") then
                local m = part:FindFirstAncestorOfClass("Model")
                if m and m.Parent and not uniqModel[m] then
                    local isPlayer = m:FindFirstChildOfClass("Humanoid") ~= nil and m:FindFirstChild("HumanoidRootPart") ~= nil
                    if isPlayer then
                        local owner = Players:GetPlayerFromCharacter(m)
                        if not owner or owner ~= lp then
                            uniqModel[m] = true
                            out[#out+1] = m
                        end
                    else
                        local hum = m:FindFirstChildOfClass("Humanoid")
                        if hum then
                            uniqModel[m] = true
                            out[#out+1] = m
                        end
                    end
                end
            end
        end
        return out
    end

    local function makePillarCFs(centerPos, side, baseY, heightY)
        local half = side * 0.5
        local rt = Vector3.new(1,0,0)
        local fw = Vector3.new(0,0,1)
        local up = Vector3.new(0,1,0)
        local c = centerPos
        local pts = {
            c + rt*half + fw*half,
            c - rt*half + fw*half,
            c + rt*half - fw*half,
            c - rt*half - fw*half,
        }
        local cfs = {}
        for i=1,#pts do
            local p = Vector3.new(pts[i].X, baseY, pts[i].Z)
            cfs[#cfs+1] = CFrame.new(p, p + up)
        end
        local top = {}
        for i=1,#pts do
            local p = Vector3.new(pts[i].X, heightY, pts[i].Z)
            top[#top+1] = CFrame.new(p, p + fw)
        end
        return cfs, top
    end

    local function takeLogs(n, exclude)
        local ex = exclude or {}
        local pool = logsNearMe(n*2, ex)
        local out = {}
        for i=1, math.min(n, #pool) do
            out[#out+1] = pool[i]
            ex[pool[i]] = true
        end
        return out, ex
    end

    local function placeAtCF(m, cf)
        local snap = setCollide(m, false)
        zeroAssembly(m)
        setPivot(m, cf)
        setCollide(m, true, snap)
    end

    local function boxTrapOnce()
        local root = hrp(); if not root then return end
        local tgts = targetsWithin(20)
        if #tgts == 0 then return end

        local used = {}
        local r = rcache

        for _,tgt in ipairs(tgts) do
            local mp = mainPart(tgt); if not mp then continue end
            local sizeY = (mp.Size and mp.Size.Y) or 4
            local baseY = math.max( (mp.Position.Y - sizeY*0.5) + 0.5, mp.Position.Y - 2 )
            local heightY = mp.Position.Y + sizeY*0.5 + 2.5
            local side = math.clamp(math.max(mp.Size.X, mp.Size.Z) + 2.5, 4.0, 8.0)

            local need = 4 + 2
            local logs, ex = takeLogs(need, used)
            used = ex
            if #logs == 0 then break end

            for _,m in ipairs(logs) do safeStartDrag(r, m) end
            task.wait(0.03)

            local pillars, top = makePillarCFs(mp.Position, side, baseY, heightY)

            local pi = 1
            while pi <= 4 and pi <= #logs do
                placeAtCF(logs[pi], pillars[pi]); pi += 1
            end
            local ti = 1
            while pi <= #logs and ti <= #top do
                placeAtCF(logs[pi], top[ti]); pi += 1; ti += 1
            end

            task.delay(0.1, function()
                for _,m in ipairs(logs) do finallyStopDrag(rcache, m) end
            end)
        end
    end

    boxBtn.MouseButton1Click:Connect(function() boxTrapOnce() end)

    local showBoxTrap = false
    tab:Toggle({
        Title = "Edge Button: Box Trap",
        Value = false,
        Callback = function(state)
            showBoxTrap = state and true or false
            if boxBtn then boxBtn.Visible = showBoxTrap end
        end
    })
end
