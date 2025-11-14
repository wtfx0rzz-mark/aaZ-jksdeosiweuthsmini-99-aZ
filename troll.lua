-- troll.lua
return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")

    local lp = Players.LocalPlayer
    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Troll or Tabs.Main
    if not tab then return end

    local MAX_LOGS               = 50
    local SEARCH_RADIUS          = 200
    local TICK                   = 0.02

    local CAMPFIRE_AVOID_RADIUS  = 35
    local SCRAPPER_AVOID_RADIUS  = 35
    local AVOID_LIFT             = 15
    local AVOID_REEVAL_S         = 0.2

    local BULL_MAX_LOGS   = 120
    local BULL_WIDTH      = 5     -- columns
    local BULL_HEIGHT     = 2     -- rows
    local BULL_THICKNESS  = 2     -- layers front-to-back
    local BULL_PUSH_STUDS = 20
    local BULL_GAP_STUDS  = 1.0
    local BULL_SPEED      = 42

    local BOX_RADIUS         = 20
    local BOX_TOP_ROWS       = 2
    local BOX_LOCK_IN_PLACE  = true
    local BOX_REFRESH_S      = 5.0
    local BOX_MAX_PER_TARGET = 18

    local CHAOS_PER_PLAYER   = 18
    local CLOUD_RADIUS_MIN   = 2.0
    local CLOUD_RADIUS_MAX   = 9.0
    local HEIGHT_BASE        = 0.5
    local HEIGHT_RANGE_MIN   = -2.0
    local HEIGHT_RANGE_MAX   = 3.0
    local JIT_XZ1, JIT_XZ2   = 1.4, 0.9
    local JIT_Y1,  JIT_Y2    = 0.9, 0.6
    local W_XZ1_MIN, W_XZ1_MAX = 1.2, 2.4
    local W_XZ2_MIN, W_XZ2_MAX = 2.0, 3.6
    local W_Y1_MIN,  W_Y1_MAX  = 1.0, 2.0
    local W_Y2_MIN,  W_Y2_MAX  = 2.0, 4.0
    local RESLOT_EVERY_MIN   = 0.45
    local RESLOT_EVERY_MAX   = 1.20
    local BURST_CHANCE_PER_S = 0.15
    local BURST_DURATION     = 0.18
    local BURST_PUSH         = 6.5
    local CHAOS_STEP_S       = 0.02
    local CHAOS_REPL_S       = 0.35

    local function hrpOf(p)
        local ch = (p or lp).Character or (p or lp).CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local function mainPart(m)
        if not m then return nil end
        if m:IsA("BasePart") then return m end
        if m:IsA("Model") then
            if m.PrimaryPart then return m.PrimaryPart end
            return m:FindFirstChildWhichIsA("BasePart")
        end
        return nil
    end
    local function cfLookAt(pos, dir)
        return CFrame.new(pos, pos + (dir.Magnitude > 1e-6 and dir.Unit or Vector3.zAxis))
    end
    local function getItemsFolder() return WS:FindFirstChild("Items") end
    local function worldPosOf(m)
        local mp = mainPart(m)
        if mp then return mp.Position end
        local ok, cf = pcall(function() return m:GetPivot() end)
        return ok and cf.Position or nil
    end
    local function resolveRemotes()
        local re = RS:FindFirstChild("RemoteEvents")
        if not re then return {} end
        return {
            StartDrag = re:FindFirstChild("RequestStartDraggingItem") or re:FindFirstChild("StartDraggingItem"),
            StopDrag  = re:FindFirstChild("StopDraggingItem") or re:FindFirstChild("RequestStopDraggingItem"),
        }
    end
    local function startDrag(m) local r=resolveRemotes(); if r.StartDrag and m and m.Parent then pcall(function() r.StartDrag:FireServer(m) end) end end
    local function stopDrag(m)  local r=resolveRemotes(); if r.StopDrag  and m and m.Parent then pcall(function() r.StopDrag:FireServer(m)  end) end end

    local function moveHoldAt(m, cf)
        if not (m and m.Parent) then return end
        local mp = mainPart(m); if not mp then return end
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then
                d.Anchored = false
                d.CanCollide = true
                d.CanTouch   = true
                d.CanQuery   = true
                d.AssemblyLinearVelocity  = Vector3.new()
                d.AssemblyAngularVelocity = Vector3.new()
                pcall(function() d:SetNetworkOwner(nil) end)
                pcall(function() if d.SetNetworkOwnershipAuto then d:SetNetworkOwnershipAuto() end end)
            end
        end
        if m:IsA("Model") then m:PivotTo(cf) else mp.CFrame = cf end
    end

    local CLAIM_ATTR = "OrbJob"
    local function releaseTags(m) pcall(function() m:SetAttribute(CLAIM_ATTR, nil) end) end
    local function claimLog(m, job)
        if not (m and m.Parent) then return false end
        local tag = m:GetAttribute(CLAIM_ATTR)
        if tag and tag ~= tostring(job) then return false end
        pcall(function() m:SetAttribute(CLAIM_ATTR, tostring(job)) end)
        return true
    end

    local avoidAcc = 0
    local function avoidLiftIfNearDanger(pos)
        avoidAcc += TICK
        if avoidAcc < AVOID_REEVAL_S then return pos end
        avoidAcc = 0
        local fire = (function()
            local map = WS:FindFirstChild("Map"); local cg = map and map:FindFirstChild("Campground"); return cg and cg:FindFirstChild("MainFire")
        end)()
        if fire then
            local fp = worldPosOf(fire)
            if fp and (pos - fp).Magnitude <= CAMPFIRE_AVOID_RADIUS then
                return Vector3.new(pos.X, pos.Y + AVOID_LIFT, pos.Z)
            end
        end
        local scr = (function()
            local map = WS:FindFirstChild("Map"); local cg = map and map:FindFirstChild("Campground"); return cg and cg:FindFirstChild("Scrapper")
        end)()
        if scr then
            local sp = worldPosOf(scr)
            if sp and (pos - sp).Magnitude <= SCRAPPER_AVOID_RADIUS then
                return Vector3.new(pos.X, pos.Y + AVOID_LIFT, pos.Z)
            end
        end
        return pos
    end

    local function nearbyLogs(origin, radius, limit, jobTag)
        local items = getItemsFolder(); if not items then return {} end
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(origin, radius, params) or {}
        local uniq, arr = {}, {}
        for _,part in ipairs(parts) do
            if part:IsA("BasePart") then
                local m = part:FindFirstAncestorOfClass("Model")
                if m and m.Parent == items and m.Name == "Log" and not uniq[m] then
                    uniq[m] = true
                    arr[#arr+1] = m
                end
            end
        end
        local scored = {}
        for _,m in ipairs(arr) do
            local mp = mainPart(m)
            if mp then
                scored[#scored+1] = {m=m, d=(mp.Position - origin).Magnitude}
            end
        end
        table.sort(scored, function(a,b) return a.d < b.d end)
        local out = {}
        for i=1, math.min(limit, #scored) do
            local m = scored[i].m
            local tag = m:GetAttribute(CLAIM_ATTR)
            if (not tag) or tag == tostring(jobTag) then out[#out+1] = m end
        end
        return out
    end

    local selectedTargets = {}
    local function playerList()
        local t = {}
        for _,p in ipairs(Players:GetPlayers()) do if p ~= lp then t[#t+1]=p.Name end end
        table.sort(t); return t
    end
    local nameToUserId = {}
    local function rebuildMap() nameToUserId = {}; for _,p in ipairs(Players:GetPlayers()) do nameToUserId[p.Name]=p.UserId end end
    rebuildMap()
    Players.PlayerAdded:Connect(rebuildMap)
    Players.PlayerRemoving:Connect(function(plr) if plr then selectedTargets[plr.UserId]=nil; rebuildMap() end end)

    tab:Section({ Title = "Targets" })
    local targetDD = tab:Dropdown({
        Title = "Players",
        Values = playerList(),
        Multi = true,
        AllowNone = true,
        Callback = function(choice)
            rebuildMap()
            selectedTargets = {}
            if type(choice) == "table" then
                for _,nm in ipairs(choice) do local uid=nameToUserId[nm]; if uid then selectedTargets[uid]=true end end
            elseif type(choice) == "string" then
                local uid=nameToUserId[choice]; if uid then selectedTargets[uid]=true end
            end
        end
    })
    tab:Button({ Title = "Refresh Player List", Callback = function() rebuildMap(); if targetDD and targetDD.SetValues then targetDD:SetValues(playerList()) end end })

    local chaosOn = false
    local chaosState = {}
    local chaosJobIdByUid = {}
    local chaosReplAcc, chaosStepAcc = 0, 0

    local function pickCloudSlot(rng)
        local r  = rng:NextNumber(CLOUD_RADIUS_MIN, CLOUD_RADIUS_MAX)
        local th = rng:NextNumber(0, math.pi*2)
        local ph = rng:NextNumber(-0.85, 0.85)
        local x = r * math.cos(th) * math.cos(ph)
        local z = r * math.sin(th) * math.cos(ph)
        local y = HEIGHT_BASE + rng:NextNumber(HEIGHT_RANGE_MIN, HEIGHT_RANGE_MAX)
        return Vector3.new(x, y, z)
    end

    local function ensureChaosLogs(uid)
        local plr = Players:GetPlayerByUserId(uid); if not plr then return end
        local hr  = hrpOf(plr); if not hr then return end
        local origin = hr.Position
        local rec = chaosState[uid]
        if not rec then rec = { logs = {}, prop = {}, rng = Random.new(os.clock()*100000 + uid) } chaosState[uid] = rec end
        local have = 0
        for m,_ in pairs(rec.logs) do if m and m.Parent then have += 1 else rec.logs[m]=nil; rec.prop[m]=nil end end
        local targetCount = math.min(CHAOS_PER_PLAYER, MAX_LOGS)
        if have >= targetCount then return end
        local need = targetCount - have
        local jobId = chaosJobIdByUid[uid] or ("CHAOS-%d-%d"):format(uid, math.random(1,1e6))
        chaosJobIdByUid[uid] = jobId
        local got = nearbyLogs(origin, SEARCH_RADIUS, need, jobId)
        for _,m in ipairs(got) do
            if claimLog(m, jobId) then
                startDrag(m)
                rec.logs[m] = true
                rec.prop[m] = {
                    phase = { xz1=math.random()*math.pi*2, xz2=math.random()*math.pi*2, y1=math.random()*math.pi*2, y2=math.random()*math.pi*2 },
                    w = {
                        xz1 = math.random()*(W_XZ1_MAX-W_XZ1_MIN)+W_XZ1_MIN,
                        xz2 = math.random()*(W_XZ2_MAX-W_XZ2_MIN)+W_XZ2_MIN,
                        y1  = math.random()*(W_Y1_MAX -W_Y1_MIN )+W_Y1_MIN,
                        y2  = math.random()*(W_Y2_MAX -W_Y2_MIN )+W_Y2_MIN,
                    },
                    slot    = pickCloudSlot(rec.rng),
                    reslotT = os.clock() + (math.random()*(RESLOT_EVERY_MAX-RESLOT_EVERY_MIN)+RESLOT_EVERY_MIN),
                    burstT  = 0,
                    burstDir= 1,
                }
            end
        end
    end

    local function chaosTick(dt)
        local tNow = os.clock()
        for uid,_ in pairs(selectedTargets) do
            local plr = Players:GetPlayerByUserId(uid)
            local hr  = plr and hrpOf(plr)
            local rec = chaosState[uid]
            if not hr then
                if rec then for m,_ in pairs(rec.logs) do stopDrag(m); releaseTags(m) end chaosState[uid]=nil end
            else
                if not rec then rec = { logs = {}, prop = {}, rng = Random.new(os.clock()*100000 + uid) } chaosState[uid]=rec end
                local base = hr.Position
                for m,_ in pairs(rec.logs) do
                    if not (m and m.Parent) then rec.logs[m]=nil; rec.prop[m]=nil
                    else
                        local st = rec.prop[m]
                        if tNow >= st.reslotT then
                            st.slot = pickCloudSlot(rec.rng)
                            st.reslotT = tNow + (math.random()*(RESLOT_EVERY_MAX-RESLOT_EVERY_MIN)+RESLOT_EVERY_MIN)
                        end
                        if tNow >= st.burstT and math.random() < (BURST_CHANCE_PER_S * CHAOS_STEP_S) then
                            st.burstT  = tNow + BURST_DURATION
                            st.burstDir = (math.random() < 0.5) and -1 or 1
                        end
                        local t = tNow
                        local jx = math.sin(t*st.w.xz1 + st.phase.xz1) * JIT_XZ1 + math.cos(t*st.w.xz2 + st.phase.xz2) * JIT_XZ2
                        local jz = math.cos(t*st.w.xz1*0.8 + st.phase.xz1*0.7) * JIT_XZ1 + math.sin(t*st.w.xz2*1.3 + st.phase.xz2*0.5) * JIT_XZ2
                        local jy = math.sin(t*st.w.y1 + st.phase.y1) * JIT_Y1 + math.cos(t*st.w.y2 + st.phase.y2) * JIT_Y2
                        local off = st.slot + Vector3.new(jx, jy, jz)
                        if tNow < st.burstT then
                            local dirToTarget = (base - (base + off)).Unit
                            off = off + dirToTarget * (BURST_PUSH * st.burstDir)
                        end
                        local pos = avoidLiftIfNearDanger(base + off)
                        local look = (base - pos)
                        moveHoldAt(m, cfLookAt(pos, look))
                    end
                end
            end
        end
    end

    local function enableChaos()
        if chaosOn then return end
        chaosOn = true
        chaosReplAcc, chaosStepAcc = 0, 0
        chaosJobIdByUid = {}
        for uid,_ in pairs(selectedTargets) do chaosJobIdByUid[uid] = ("CHAOS-%d-%d"):format(uid, math.random(1,1e6)) end
    end
    local function disableChaos()
        chaosOn = false
        for _,rec in pairs(chaosState) do for m,_ in pairs(rec.logs) do stopDrag(m); releaseTags(m) end end
        chaosState = {}; chaosJobIdByUid = {}
    end

    tab:Section({ Title = "Chaos Swarm" })
    tab:Toggle({ Title = "Enable Chaotic Logs Around Selected Players", Value = false, Callback = function(s) if s then enableChaos() else disableChaos() end end })

    local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
    local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
    if not edgeGui then
        local g = Instance.new("ScreenGui"); g.Name="EdgeButtons"; g.ResetOnSpawn=false; pcall(function() g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end); g.Parent=playerGui
        edgeGui = g
    end
    local stack = edgeGui:FindFirstChild("EdgeStack")
    if not stack then
        local f = Instance.new("Frame"); f.Name="EdgeStack"; f.AnchorPoint=Vector2.new(1,0); f.Position=UDim2.new(1,-6,0,6); f.Size=UDim2.new(0,130,1,-12); f.BackgroundTransparency=1; f.BorderSizePixel=0; f.Parent=edgeGui
        local l = Instance.new("UIListLayout"); l.Name="VList"; l.FillDirection=Enum.FillDirection.Vertical; l.SortOrder=Enum.SortOrder.LayoutOrder; l.Padding=UDim.new(0,6); l.HorizontalAlignment=Enum.HorizontalAlignment.Right; l.Parent=f
        stack = f
    end
    local function makeEdgeBtn(name, label, order)
        local b = stack:FindFirstChild(name)
        if not b then
            b = Instance.new("TextButton")
            b.Name = name
            b.Size = UDim2.new(1,0,0,30)
            b.Text = label
            b.TextSize = 12
            b.Font = Enum.Font.GothamBold
            b.BackgroundColor3 = Color3.fromRGB(30,30,35)
            b.TextColor3 = Color3.new(1,1,1)
            b.BorderSizePixel = 0
            b.Visible = false
            b.LayoutOrder = order or 10
            b.Parent = stack
            local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = b
        else
            b.Text = label; b.LayoutOrder = order or b.LayoutOrder
        end
        return b
    end

    local bullBtn = makeEdgeBtn("BulldozerEdge", "Bulldozer", 9)
    local showBullEdge = true
    bullBtn.Visible = showBullEdge
    tab:Toggle({ Title = "Show Edge Button: Bulldozer", Value = showBullEdge, Callback = function(s) showBullEdge=s; if bullBtn then bullBtn.Visible=s end end })

    local function bulldozerOnce()
        local root = hrpOf(lp); if not root then return end
        local look = root.CFrame.LookVector
        local right = root.CFrame.RightVector
        local origin = root.Position + look * 6

        local jobId = ("BULL-%d"):format(os.clock()*1000)
        local neededPerWall = BULL_WIDTH * BULL_HEIGHT
        local totalNeeded = math.min(neededPerWall * math.max(1, BULL_THICKNESS), BULL_MAX_LOGS)
        local pool = nearbyLogs(root.Position, SEARCH_RADIUS, totalNeeded, jobId)
        local logs = {}
        for _,m in ipairs(pool) do if claimLog(m, jobId) then startDrag(m); logs[#logs+1]=m end end
        if #logs == 0 then return end

        local sample = mainPart(logs[1])
        local spanX = ((sample and sample.Size.X) or 2.5) + BULL_GAP_STUDS
        local spanY = ((sample and sample.Size.Y) or 2.0) + BULL_GAP_STUDS
        local layerGap = math.max(0.5, (sample and sample.Size.Z or 1.0) * 0.5)

        local idx = 1
        for layer=0,(math.max(1,BULL_THICKNESS)-1) do
            local zBias = -layer * layerGap
            for r=0,(BULL_HEIGHT-1) do
                for c=0,(BULL_WIDTH-1) do
                    if idx > #logs then break end
                    local dx = (c - (BULL_WIDTH-1)/2) * spanX
                    local dy = (r - (BULL_HEIGHT-1)/2) * spanY
                    local pos = origin + right*dx + Vector3.new(0,dy,0) + look*zBias
                    moveHoldAt(logs[idx], cfLookAt(pos, look))
                    idx += 1
                end
            end
        end

        local baseY = mainPart(logs[1]).Position.Y
        local traveled = 0
        local stepPerTick = math.max(1, BULL_SPEED * TICK)
        while traveled < BULL_PUSH_STUDS do
            local delta = look * math.min(stepPerTick, BULL_PUSH_STUDS - traveled)
            origin = origin + delta
            for i=1,#logs do
                local m = logs[i]
                local mp = mainPart(m)
                if m and m.Parent and mp then
                    local p = mp.Position + delta
                    moveHoldAt(m, cfLookAt(Vector3.new(p.X, baseY, p.Z), look))
                end
            end
            traveled += delta.Magnitude
            Run.Heartbeat:Wait()
        end
        for _,m in ipairs(logs) do stopDrag(m); releaseTags(m) end
    end
    bullBtn.MouseButton1Click:Connect(function() bulldozerOnce() end)

    local boxOn, boxJobId = false, nil
    local boxState = {}
    local boxReplAcc, boxRefreshAcc = 0, 0

    local function ensureBoxLogs(uid, want)
        local root = hrpOf(lp); if not root then return end
        local rec = boxState[uid]
        if not rec then rec = { logs={}, anchorPos=nil } boxState[uid]=rec end
        local have = 0
        for m,_ in pairs(rec.logs) do if m and m.Parent then have+=1 else rec.logs[m]=nil end end
        local need = math.max(0, math.min(want, BOX_MAX_PER_TARGET) - have)
        if need <= 0 then return end
        local got = nearbyLogs(root.Position, SEARCH_RADIUS, need, boxJobId)
        for _,m in ipairs(got) do if claimLog(m, boxJobId) then startDrag(m); rec.logs[m]=true end end
    end
    local function boxLayout(centerPos, upVec, rightVec, forwardVec, count)
        local pos = {}
        local perSide = math.max(3, math.floor(count/4))
        local gap = 2.0
        local topRows = math.max(1, BOX_TOP_ROWS)
        for row=0,topRows-1 do
            local y = 2.5 + row*2.0
            local base = centerPos + upVec*y + forwardVec*BOX_RADIUS
            for i=-(perSide-1)/2,(perSide-1)/2 do pos[#pos+1] = base + rightVec*(i*gap) end
            base = centerPos + upVec*y - forwardVec*BOX_RADIUS
            for i=-(perSide-1)/2,(perSide-1)/2 do pos[#pos+1] = base + rightVec*(i*gap) end
            base = centerPos + upVec*y + rightVec*BOX_RADIUS
            for i=-(perSide-1)/2,(perSide-1)/2 do pos[#pos+1] = base + forwardVec*(i*gap) end
            base = centerPos + upVec*y - rightVec*BOX_RADIUS
            for i=-(perSide-1)/2,(perSide-1)/2 do pos[#pos+1] = base + forwardVec*(i*gap) end
        end
        local roofBase = centerPos + upVec * (2.5 + topRows*2.0)
        pos[#pos+1] = roofBase
        pos[#pos+1] = roofBase + rightVec*(gap*0.8)
        pos[#pos+1] = roofBase - rightVec*(gap*0.8)
        pos[#pos+1] = roofBase + forwardVec*(gap*0.8)
        pos[#pos+1] = roofBase - forwardVec*(gap*0.8)
        return pos
    end
    local function updateBoxFor(uid)
        local plr = Players:GetPlayerByUserId(uid); if not plr then return end
        local hr  = hrpOf(plr); if not hr then return end
        local rec = boxState[uid]; if not rec then rec = { logs={}, anchorPos=nil }; boxState[uid]=rec end
        local center
        if BOX_LOCK_IN_PLACE then
            if not rec.anchorPos then rec.anchorPos = hr.Position end
            center = rec.anchorPos
        else
            center = hr.Position
        end
        ensureBoxLogs(uid, BOX_MAX_PER_TARGET)
        local logsArr = {}
        for m,_ in pairs(rec.logs) do if m and m.Parent then logsArr[#logsArr+1]=m end end
        if #logsArr == 0 then return end
        local look = hr.CFrame.LookVector
        local right = hr.CFrame.RightVector
        local up = Vector3.yAxis
        local targets = boxLayout(center, up, right, look, #logsArr)
        local n = math.min(#logsArr, #targets)
        for i=1,n do
            local pos = avoidLiftIfNearDanger(targets[i])
            local dir = (pos - center)
            moveHoldAt(logsArr[i], cfLookAt(pos, dir.Magnitude>1e-3 and dir or look))
        end
    end
    local function enableBox()
        if boxOn then return end
        boxOn = true
        boxJobId = ("BOX-%d"):format(os.clock()*1000)
        boxReplAcc, boxRefreshAcc = 0, 0
    end
    local function disableBox()
        boxOn = false
        for _,rec in pairs(boxState) do for m,_ in pairs(rec.logs) do stopDrag(m); releaseTags(m) end end
        boxState = {}; boxJobId = nil
    end

    tab:Section({ Title = "Box Trap" })
    tab:Toggle({ Title = "Enable Box Trap Around Selected Players", Value = false, Callback = function(s) if s then enableBox() else disableBox() end end })
    tab:Toggle({ Title = "Box: Lock In Place (vs Follow)", Value = BOX_LOCK_IN_PLACE, Callback = function(s) BOX_LOCK_IN_PLACE = s and true or false; for _,rec in pairs(boxState) do rec.anchorPos = nil end end })
    tab:Slider({ Title = "Box Radius", Value = { Min = 8, Max = 40, Default = BOX_RADIUS }, Callback = function(v) local nv=type(v)=="table" and (v.Value or v.Default) or v; nv=tonumber(nv); if nv then BOX_RADIUS=math.clamp(nv,4,80) end end })

    Run.Heartbeat:Connect(function(dt)
        if chaosOn then
            chaosReplAcc += dt; chaosStepAcc += dt
            if chaosReplAcc >= CHAOS_REPL_S then for uid,_ in pairs(selectedTargets) do ensureChaosLogs(uid) end chaosReplAcc=0 end
            while chaosStepAcc >= CHAOS_STEP_S do chaosTick(CHAOS_STEP_S); chaosStepAcc -= CHAOS_STEP_S end
        end
        if boxOn then
            boxReplAcc += dt; boxRefreshAcc += dt
            if boxReplAcc >= 0.35 then for uid,_ in pairs(selectedTargets) do ensureBoxLogs(uid, BOX_MAX_PER_TARGET) end boxReplAcc=0 end
            for uid,_ in pairs(selectedTargets) do updateBoxFor(uid) end
            if boxRefreshAcc >= BOX_REFRESH_S then for _,rec in pairs(boxState) do if BOX_LOCK_IN_PLACE then rec.anchorPos = rec.anchorPos or nil else rec.anchorPos = nil end end boxRefreshAcc=0 end
        end
    end)
end
