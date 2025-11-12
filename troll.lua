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

    ----------------------------------------------------------------
    -- Tunables (your last shared values)
    ----------------------------------------------------------------
    local MAX_LOGS               = 80
    local SEARCH_RADIUS          = 200
    local TICK                   = 0.02

    local CAMPFIRE_AVOID_RADIUS  = 35
    local SCRAPPER_AVOID_RADIUS  = 35
    local AVOID_LIFT             = 15
    local AVOID_REEVAL_S         = 0.2

    local BULL_MAX_LOGS   = 120
    local BULL_THICKNESS  = 3
    local BULL_PUSH_STUDS = 20
    local BULL_GAP_STUDS  = 1.5
    local BULL_SPEED      = 42

    local BOX_RADIUS         = 20
    local BOX_TOP_ROWS       = 2
    local BOX_LOCK_IN_PLACE  = true
    local BOX_REFRESH_S      = 5.0
    local BOX_MAX_PER_TARGET = 18

    ----------------------------------------------------------------
    -- Chaos parameters (increased 3D energy)
    ----------------------------------------------------------------
    local CHAOS_PER_PLAYER   = 18
    local CHAOS_BASE_R       = 6
    local CHAOS_R_WOBBLE     = 3.5
    local CHAOS_VERT_BASE    = 2.5     -- base shell height contribution
    local CHAOS_VERT_BOB     = 4.0     -- extra bob
    local CHAOS_LAYERS       = 3       -- vertical shells
    local CHAOS_XZ_JITTER    = 2.2
    local CHAOS_FREQ_BASE    = 2.6
    local CHAOS_FREQ_JIT     = 1.8
    local CHAOS_PAUSE_PROB   = 0.08
    local CHAOS_PAUSE_MS_MIN = 80
    local CHAOS_PAUSE_MS_MAX = 240
    local CHAOS_FLIP_PROB    = 0.07
    local CHAOS_REPL_S       = 0.35
    local CHAOS_STEP_S       = 0.015

    ----------------------------------------------------------------
    -- Utils
    ----------------------------------------------------------------
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
    local function getItemsFolder() return WS:FindFirstChild("Items") end

    local function isUnderLogWall(inst)
        local cur = inst
        while cur and cur ~= WS do
            local n = (cur.Name or ""):lower()
            if n == "logwall" or n == "log wall" or (n:find("log",1,true) and n:find("wall",1,true)) then
                return true
            end
            cur = cur.Parent
        end
        return false
    end

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
    local function startDrag(m)
        local r = resolveRemotes()
        if r.StartDrag and m and m.Parent then pcall(function() r.StartDrag:FireServer(m) end) end
    end
    local function stopDrag(m)
        local r = resolveRemotes()
        if r.StopDrag and m and m.Parent then pcall(function() r.StopDrag:FireServer(m) end) end
    end

    local function cfLookAt(pos, dir)
        return CFrame.new(pos, pos + (dir.Magnitude > 1e-6 and dir.Unit or Vector3.zAxis))
    end

    -- Move while collidable and unanchored.
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
        if m:IsA("Model") then
            m:PivotTo(cf)
        else
            mp.CFrame = cf
        end
    end

    local CLAIM_ATTR = "OrbJob"
    local INFLT_ATTR = "OrbInFlightAt"

    local function releaseTags(m)
        if not m then return end
        pcall(function()
            m:SetAttribute(CLAIM_ATTR, nil)
            m:SetAttribute(INFLT_ATTR, nil)
        end)
    end
    local function claimLog(m, job)
        if not (m and m.Parent) then return false end
        local tag = m:GetAttribute(CLAIM_ATTR)
        if tag and tag ~= tostring(job) then return false end
        pcall(function()
            m:SetAttribute(CLAIM_ATTR, tostring(job))
            m:SetAttribute(INFLT_ATTR, os.clock())
        end)
        return true
    end

    local function nearbyLogs(origin, radius, limit, jobTag)
        local items = getItemsFolder(); if not items then return {} end
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(origin, radius, params) or {}
        local uniq, out = {}, {}
        for _,part in ipairs(parts) do
            if part:IsA("BasePart") then
                local m = part:FindFirstAncestorOfClass("Model")
                if m and m.Parent == items and m.Name == "Log" and not uniq[m] and not isUnderLogWall(m) then
                    local tag = m:GetAttribute(CLAIM_ATTR)
                    if (not tag) or tag == tostring(jobTag) then
                        uniq[m] = true
                        out[#out+1] = m
                        if #out >= limit then break end
                    end
                end
            end
        end
        return out
    end

    local function campfireModel()
        local map = WS:FindFirstChild("Map")
        local cg  = map and map:FindFirstChild("Campground")
        return cg and cg:FindFirstChild("MainFire")
    end
    local function scrapperModel()
        local map = WS:FindFirstChild("Map")
        local cg  = map and map:FindFirstChild("Campground")
        return cg and cg:FindFirstChild("Scrapper")
    end

    local function avoidLiftIfNearDanger(pos)
        local fire = campfireModel()
        if fire then
            local fp = worldPosOf(fire)
            if fp and (pos - fp).Magnitude <= CAMPFIRE_AVOID_RADIUS then
                return Vector3.new(pos.X, pos.Y + AVOID_LIFT, pos.Z)
            end
        end
        local scr = scrapperModel()
        if scr then
            local sp = worldPosOf(scr)
            if sp and (pos - sp).Magnitude <= SCRAPPER_AVOID_RADIUS then
                return Vector3.new(pos.X, pos.Y + AVOID_LIFT, pos.Z)
            end
        end
        return pos
    end

    ----------------------------------------------------------------
    -- Player dropdown with refresh (auto + manual)
    ----------------------------------------------------------------
    local selectedTargets = {}  -- [userId]=true
    local function playerList()
        local t = {}
        for _,p in ipairs(Players:GetPlayers()) do
            if p ~= lp then table.insert(t, p.Name) end
        end
        table.sort(t)
        return t
    end
    local nameToUserId = {}
    local function rebuildMap()
        nameToUserId = {}
        for _,p in ipairs(Players:GetPlayers()) do
            nameToUserId[p.Name] = p.UserId
        end
    end
    rebuildMap()
    Players.PlayerAdded:Connect(rebuildMap)
    Players.PlayerRemoving:Connect(function(plr)
        if plr then
            selectedTargets[plr.UserId] = nil
            rebuildMap()
        end
    end)

    tab:Section({ Title = "Targets" })
    local targetDD
    targetDD = tab:Dropdown({
        Title = "Players",
        Values = playerList(),
        Multi = true,
        AllowNone = true,
        Callback = function(choice)
            rebuildMap()
            selectedTargets = {}
            if type(choice) == "table" then
                for _,nm in ipairs(choice) do
                    local uid = nameToUserId[nm]
                    if uid then selectedTargets[uid] = true end
                end
            elseif type(choice) == "string" then
                local uid = nameToUserId[choice]
                if uid then selectedTargets[uid] = true end
            end
        end
    })
    tab:Button({
        Title = "Refresh Player List",
        Callback = function()
            rebuildMap()
            if targetDD and targetDD.SetValues then targetDD:SetValues(playerList()) end
        end
    })

    ----------------------------------------------------------------
    -- CHAOS MODE
    ----------------------------------------------------------------
    local chaosOn = false
    local chaosJobId = nil
    local chaosState = {} -- [uid] = { logs = { [model]=true }, prop = { [model]=per-log-state }, layerSeed }
    local chaosReplAcc, chaosStepAcc, dangerReevalAcc = 0, 0, 0

    local function ensureChaosLogs(uid)
        local root = hrpOf(lp); if not root then return end
        local rec = chaosState[uid]
        if not rec then rec = { logs = {}, prop = {}, layerSeed = math.random() } chaosState[uid] = rec end
        local have = 0
        for m,_ in pairs(rec.logs) do
            if m and m.Parent then have += 1 else rec.logs[m]=nil; rec.prop[m]=nil end
        end
        local need = math.max(0, math.min(CHAOS_PER_PLAYER, MAX_LOGS) - have)
        if need > 0 then
            local got = nearbyLogs(root.Position, SEARCH_RADIUS, need, chaosJobId)
            for _,m in ipairs(got) do
                if claimLog(m, chaosJobId) then
                    startDrag(m)
                    rec.logs[m] = true
                    rec.prop[m] = {
                        seed = math.random(),
                        dir  = (math.random() < 0.5) and -1 or 1,
                        pauseUntil = 0,
                        flipUntil  = 0,
                        layer = (math.random(1, CHAOS_LAYERS) - 1), -- 0..L-1
                    }
                end
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
                if rec then
                    for m,_ in pairs(rec.logs) do stopDrag(m); releaseTags(m) end
                    chaosState[uid] = nil
                end
            else
                if not rec then rec = { logs = {}, prop = {}, layerSeed = math.random() } chaosState[uid] = rec end
                local base = hr.Position
                local i = 0
                for m,_ in pairs(rec.logs) do
                    if not (m and m.Parent) then
                        rec.logs[m] = nil
                        rec.prop[m] = nil
                    else
                        i += 1
                        local st = rec.prop[m]
                        if st.pauseUntil <= tNow and math.random() < CHAOS_PAUSE_PROB then
                            st.pauseUntil = tNow + (CHAOS_PAUSE_MS_MIN + math.random()*(CHAOS_PAUSE_MS_MAX-CHAOS_PAUSE_MS_MIN))/1000
                        end
                        if st.flipUntil <= tNow and math.random() < CHAOS_FLIP_PROB then
                            st.dir = -st.dir
                            st.flipUntil = tNow + (0.22 + math.random()*0.5)
                        end

                        -- Per-layer shell height and radius wobble
                        local layerFrac = (st.layer / math.max(1, CHAOS_LAYERS-1)) -- 0..1
                        local shellH = CHAOS_VERT_BASE + layerFrac * (CHAOS_VERT_BASE + CHAOS_VERT_BOB)
                        local rBase  = CHAOS_BASE_R + layerFrac * CHAOS_R_WOBBLE

                        local freq   = CHAOS_FREQ_BASE + (math.random()*2-1)*CHAOS_FREQ_JIT
                        local phase  = (tNow * freq * st.dir) + (i*0.91) + st.seed*6.28

                        local radial = rBase + math.sin(tNow*0.7 + st.seed*3.1 + i*0.41)*CHAOS_R_WOBBLE
                        local bob    = math.sin(phase*2.0 + st.seed*1.7) * CHAOS_VERT_BOB
                        local xzJ    = Vector3.new((math.random()*2-1)*CHAOS_XZ_JITTER, 0, (math.random()*2-1)*CHAOS_XZ_JITTER)

                        local offset = Vector3.new(math.cos(phase)*radial,
                                                   shellH + bob,
                                                   math.sin(phase)*radial) + xzJ
                        local pos = base + offset
                        pos = avoidLiftIfNearDanger(pos)

                        moveHoldAt(m, cfLookAt(pos, (pos - base)))
                    end
                end
            end
        end
    end

    local function enableChaos()
        if chaosOn then return end
        chaosOn = true
        chaosJobId = ("%d-%d"):format(os.time(), math.random(1,1e6))
        chaosReplAcc, chaosStepAcc, dangerReevalAcc = 0, 0, 0
    end
    local function disableChaos()
        chaosOn = false
        for uid,rec in pairs(chaosState) do
            for m,_ in pairs(rec.logs) do stopDrag(m); releaseTags(m) end
        end
        chaosState = {}
        chaosJobId = nil
    end

    tab:Section({ Title = "Chaos Swarm" })
    tab:Toggle({
        Title = "Enable Chaotic Logs Around Selected Players",
        Value = false,
        Callback = function(state)
            if state then enableChaos() else disableChaos() end
        end
    })

    ----------------------------------------------------------------
    -- BULLDOZER EDGE BUTTON
    ----------------------------------------------------------------
    -- Edge UI (same pattern as your Auto)
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
            b.LayoutOrder = order or 10
            b.Parent = stack
            local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = b
        else
            b.Text = label
            b.LayoutOrder = order or b.LayoutOrder
        end
        return b
    end

    local bullBtn = makeEdgeBtn("BulldozerEdge", "Bulldozer", 9)
    local showBullEdge = true  -- restored, default on
    bullBtn.Visible = showBullEdge

    -- Uniform grid for the wall; compute size by log primary part size if available.
    local function logSizeY(m)
        local mp = mainPart(m); if not mp then return 2 end
        return mp.Size.Y
    end
    local function gridFor(count, thickness)
        local cols = math.max(1, math.ceil(count / math.max(1, thickness)))
        local rows = math.min(thickness, count)
        return cols, rows
    end

    local function bulldozerOnce()
        local root = hrpOf(lp); if not root then return end
        local look = root.CFrame.LookVector
        local origin = root.Position + look * 6
        local jobId = ("BULL-%d"):format(os.clock()*1000)
        -- Acquire logs
        local pool = nearbyLogs(root.Position, SEARCH_RADIUS, BULL_MAX_LOGS, jobId)
        local logs = {}
        for _,m in ipairs(pool) do
            if claimLog(m, jobId) then
                startDrag(m)
                logs[#logs+1] = m
            end
        end
        if #logs == 0 then return end

        -- Build two back-to-back walls tightly
        local cols, rows = gridFor(#logs, BULL_THICKNESS)
        local firstHalf = math.ceil(#logs/2)
        local secondHalf = #logs - firstHalf
        local frontZOffset = 0.75  -- small separation between the two walls

        -- Estimate spacing from first log dimensions
        local mp0 = mainPart(logs[1])
        local spanX = (mp0 and mp0.Size.X or 2.5) + BULL_GAP_STUDS
        local spanY = (mp0 and mp0.Size.Y or 2.0) + BULL_GAP_STUDS

        local function placeWall(startIdx, count, zBias)
            for i=0,count-1 do
                local c = (i % cols)
                local r = math.floor(i / cols)
                local dx = (c - (cols-1)/2) * spanX
                local dy = (r - (rows-1)/2) * spanY
                local offset = root.CFrame.RightVector * dx + Vector3.new(0, dy, 0) + look * zBias
                local pos = origin + offset
                local forward = cfLookAt(pos, look)
                moveHoldAt(logs[startIdx + i], forward)
            end
        end

        placeWall(1, firstHalf, 0)                -- front wall
        if secondHalf > 0 then
            placeWall(firstHalf+1, secondHalf, -frontZOffset) -- back wall slightly behind
        end

        -- Push forward in steps. Keep CanCollide enabled and keep dragging.
        local travel = 0
        local step   = math.max(1, BULL_SPEED * TICK)
        while travel < BULL_PUSH_STUDS do
            local delta = look * math.min(step, BULL_PUSH_STUDS - travel)
            origin = origin + delta
            for i,m in ipairs(logs) do
                local mp = mainPart(m)
                if m and m.Parent and mp then
                    local pos = mp.Position + delta
                    -- prevent downward drift: lock Y near the first placement height
                    local yLock = mp.Position.Y
                    local cf = cfLookAt(Vector3.new(pos.X, yLock, pos.Z), look)
                    moveHoldAt(m, cf)
                end
            end
            travel += delta.Magnitude
            Run.Heartbeat:Wait()
        end

        -- Clean up
        for _,m in ipairs(logs) do stopDrag(m); releaseTags(m) end
    end

    bullBtn.MouseButton1Click:Connect(function()
        bulldozerOnce()
    end)

    tab:Toggle({
        Title = "Show Edge Button: Bulldozer",
        Value = showBullEdge,
        Callback = function(state)
            showBullEdge = state
            if bullBtn then bullBtn.Visible = state end
        end
    })

    ----------------------------------------------------------------
    -- Heartbeat loop
    ----------------------------------------------------------------
    Run.Heartbeat:Connect(function(dt)
        -- chaos maintenance
        if chaosOn then
            chaosReplAcc += dt
            chaosStepAcc += dt
            if chaosReplAcc >= CHAOS_REPL_S then
                for uid,_ in pairs(selectedTargets) do ensureChaosLogs(uid) end
                chaosReplAcc = 0
            end
            while chaosStepAcc >= CHAOS_STEP_S do
                chaosTick(CHAOS_STEP_S)
                chaosStepAcc -= CHAOS_STEP_S
            end
        end
    end)
end
