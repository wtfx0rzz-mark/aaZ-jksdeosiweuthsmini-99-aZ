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
    local BULL_THICKNESS  = 3
    local BULL_PUSH_STUDS = 20
    local BULL_GAP_STUDS  = 1.0
    local BULL_SPEED      = 42

    local BOX_RADIUS         = 20
    local BOX_TOP_ROWS       = 2
    local BOX_LOCK_IN_PLACE  = true
    local BOX_REFRESH_S      = 5.0
    local BOX_MAX_PER_TARGET = 18

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
            local nm = (cur.Name or ""):lower()
            if nm == "logwall" or nm == "log wall" or (nm:find("log",1,true) and nm:find("wall",1,true)) then
                return true
            end
            cur = cur.Parent
        end
        return false
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
    local function worldPosOf(m)
        local mp = mainPart(m)
        if mp then return mp.Position end
        local ok, cf = pcall(function() return m:GetPivot() end)
        return ok and cf.Position or nil
    end
    local function resolveRemotes()
        local re = RS:FindFirstChild("RemoteEvents"); if not re then return {} end
        return {
            StartDrag = re:FindFirstChild("RequestStartDraggingItem") or re:FindFirstChild("StartDraggingItem"),
            StopDrag  = re:FindFirstChild("StopDraggingItem") or re:FindFirstChild("RequestStopDraggingItem"),
        }
    end
    local function beginDrag(m)
        local r = resolveRemotes()
        if r.StartDrag and m and m.Parent then pcall(function() r.StartDrag:FireServer(m) end) end
    end
    local function endDrag(m)
        local r = resolveRemotes()
        if r.StopDrag and m and m.Parent then pcall(function() r.StopDrag:FireServer(m) end) end
    end
    local function setNoCollide(model, on)
        local t = {}
        for _,d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                t[#t+1] = d
            end
        end
        for _,p in ipairs(t) do
            p.CanCollide = not on and true or false
            p.CanTouch   = not on and true or false
            p.CanQuery   = not on and true or false
            p.Anchored   = false
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
        end
    end
    local function holdAtCF(m, cf)
        if not (m and m.Parent) then return end
        local mp = mainPart(m); if not mp then return end
        setNoCollide(m, true)
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
        if m:GetAttribute(CLAIM_ATTR) then return false end
        pcall(function()
            m:SetAttribute(CLAIM_ATTR, tostring(job))
            m:SetAttribute(INFLT_ATTR, os.clock())
        end)
        return true
    end

    local function nearbyLogs(origin, radius, limit, currentJob)
        local items = getItemsFolder(); if not items then return {} end
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(origin, radius, params) or {}
        local uniq = {}
        local out = {}
        for _,part in ipairs(parts) do
            if part:IsA("BasePart") then
                local m = part:FindFirstAncestorOfClass("Model")
                if m and m.Parent == items and m.Name == "Log" and not uniq[m] and not isUnderLogWall(m) then
                    if not m:GetAttribute(CLAIM_ATTR) or m:GetAttribute(CLAIM_ATTR) == tostring(currentJob) then
                        uniq[m] = true
                        out[#out+1] = m
                        if #out >= limit then break end
                    end
                end
            end
        end
        return out
    end

    local function cfLookAt(pos, dir)
        return CFrame.new(pos, pos + (dir.Magnitude > 1e-6 and dir.Unit or Vector3.zAxis))
    end

    local function avoidLiftIfNearDanger(targetPos)
        local fire = campfireModel()
        local scr  = scrapperModel()
        local liftY = nil
        if fire then
            local fp = worldPosOf(fire)
            if fp and (targetPos - fp).Magnitude <= CAMPFIRE_AVOID_RADIUS then
                liftY = (liftY or targetPos.Y) + AVOID_LIFT
            end
        end
        if scr then
            local sp = worldPosOf(scr)
            if sp and (targetPos - sp).Magnitude <= SCRAPPER_AVOID_RADIUS then
                liftY = (liftY or targetPos.Y) + AVOID_LIFT
            end
        end
        if liftY then
            return Vector3.new(targetPos.X, liftY, targetPos.Z)
        end
        return targetPos
    end

    local chaosOn = false
    local chaosJobId = nil
    local chaosTargets = {}    -- [player.UserId] = { logs = {model->true}, lastPos = Vector3 }
    local chaosHB, chaosAcc = nil, 0
    local CHAOS_ORBIT_R = 5
    local CHAOS_VERT_JITTER = 3
    local CHAOS_HALT_S = 0.15
    local CHAOS_REPLENISH_S = 0.35
    local CHAOS_PER_PLAYER = 18

    local function chaosPickFor(uid, want)
        local root = hrpOf(lp); if not root then return end
        local need = want
        local found = nearbyLogs(root.Position, SEARCH_RADIUS, need, chaosJobId)
        for _,m in ipairs(found) do
            if claimLog(m, chaosJobId) then beginDrag(m) end
        end
        return found
    end

    local function chaosEnsureLogsFor(playersSet)
        for uid,_ in pairs(playersSet) do
            local rec = chaosTargets[uid]
            local have = 0
            if rec and rec.logs then
                for m,_ in pairs(rec.logs) do if m and m.Parent then have += 1 end end
            end
            local want = math.max(0, math.min(CHAOS_PER_PLAYER, MAX_LOGS) - have)
            if want > 0 then
                local got = chaosPickFor(uid, want)
                chaosTargets[uid] = chaosTargets[uid] or { logs = {} }
                for _,m in ipairs(got) do chaosTargets[uid].logs[m] = true end
            end
        end
    end

    local function chaosTick(playersSet, dt)
        local root = hrpOf(lp); if not root then return end
        local t = os.clock()
        for uid,_ in pairs(playersSet) do
            local p = Players:GetPlayerByUserId(uid)
            local hr = p and hrpOf(p)
            if not hr then
                if chaosTargets[uid] then
                    for m,_ in pairs(chaosTargets[uid].logs) do endDrag(m); releaseTags(m) end
                end
                chaosTargets[uid] = nil
            else
                local base = hr.Position
                local rec = chaosTargets[uid] or { logs = {} }
                chaosTargets[uid] = rec
                local i = 0
                for m,_ in pairs(rec.logs) do
                    if not (m and m.Parent) then rec.logs[m]=nil else
                        i += 1
                        local ang = t*1.8 + i*0.9
                        local r   = CHAOS_ORBIT_R + (i%3)
                        local off = Vector3.new(math.cos(ang)*r, math.sin(ang*2.3)*CHAOS_VERT_JITTER*0.35, math.sin(ang)*r)
                        local pos = base + off
                        pos = avoidLiftIfNearDanger(pos)
                        holdAtCF(m, cfLookAt(pos, (pos - root.Position)))
                    end
                end
            end
        end
    end

    local chaosSelected = {} -- [userId]=true
    local function enableChaos()
        if chaosOn then return end
        chaosOn = true
        chaosJobId = ("%d-%d"):format(os.time(), math.random(1,1e6))
        chaosHB = Run.Heartbeat:Connect(function(dt)
            chaosAcc += dt
            if chaosAcc >= CHAOS_HALT_S then
                chaosAcc = 0
                chaosEnsureLogsFor(chaosSelected)
                chaosTick(chaosSelected, CHAOS_HALT_S)
            end
        end)
    end
    local function disableChaos()
        chaosOn = false
        if chaosHB then chaosHB:Disconnect(); chaosHB = nil end
        for uid,rec in pairs(chaosTargets) do
            for m,_ in pairs(rec.logs or {}) do endDrag(m); releaseTags(m) end
        end
        chaosTargets = {}
        chaosJobId = nil
    end

    local boxOn = false
    local boxJobId = nil
    local boxState = { targets = {}, lastRefresh = 0 } -- [uid] = { logs = {m}, anchorCFs = {CFs} }
    local function buildBoxAnchors(centerCF)
        local anchors = {}
        local r = BOX_RADIUS
        local up = Vector3.new(0,1,0)
        local f  = centerCF.LookVector
        local rgt= centerCF.RightVector
        local base = centerCF.Position
        local edges = {
            base + f*r + up*2, base - f*r + up*2, base + rgt*r + up*2, base - rgt*r + up*2,
            base + f*r + rgt*r + up*2, base + f*r - rgt*r + up*2, base - f*r + rgt*r + up*2, base - f*r - rgt*r + up*2
        }
        local rows = BOX_TOP_ROWS
        for i=1,rows do
            local y = (i-1)*2.5
            for _,p in ipairs(edges) do anchors[#anchors+1] = p + Vector3.new(0,y,0) end
        end
        anchors[#anchors+1] = base + up*(2 + rows*2.5) -- middle roof
        return anchors
    end
    local function ensureBoxLogs(uid, need)
        local root = hrpOf(lp); if not root then return end
        local got = nearbyLogs(root.Position, SEARCH_RADIUS, need, boxJobId)
        for _,m in ipairs(got) do
            if claimLog(m, boxJobId) then beginDrag(m) end
        end
        return got
    end
    local function enableBox(targetPlayers)
        if boxOn then return end
        boxOn = true
        boxJobId = ("%d-%d"):format(os.time(), math.random(1,1e6))
        boxState.targets = {}
        for _,p in ipairs(targetPlayers) do
            local hr = hrpOf(p)
            if hr then
                local cf = hr.CFrame
                local anchors = buildBoxAnchors(cf)
                local need = math.min(#anchors, BOX_MAX_PER_TARGET)
                local picked = ensureBoxLogs(p.UserId, need)
                local logs = {}
                for i=1,need do logs[i] = picked[i] end
                boxState.targets[p.UserId] = { anchors = anchors, logs = logs, lock = BOX_LOCK_IN_PLACE, baseCF = cf }
            end
        end
        Run.Heartbeat:Connect(function(dt)
            if not boxOn then return end
            local now = os.clock()
            local refresh = (now - (boxState.lastRefresh or 0)) >= BOX_REFRESH_S
            for uid,rec in pairs(boxState.targets) do
                local targetP = Players:GetPlayerByUserId(uid)
                local baseCF = rec.baseCF
                if not rec.lock and targetP and hrpOf(targetP) then
                    baseCF = hrpOf(targetP).CFrame
                    rec.baseCF = baseCF
                    rec.anchors = buildBoxAnchors(baseCF)
                end
                if refresh then
                    local have = 0
                    for _,m in ipairs(rec.logs) do if m and m.Parent then have += 1 end end
                    if have < math.min(#rec.anchors, BOX_MAX_PER_TARGET) then
                        local got = ensureBoxLogs(uid, math.min(#rec.anchors, BOX_MAX_PER_TARGET) - have)
                        for _,m in ipairs(got) do table.insert(rec.logs, m) end
                    end
                end
                for i,anchor in ipairs(rec.anchors) do
                    local m = rec.logs[i]
                    if m and m.Parent then
                        local pos = avoidLiftIfNearDanger(anchor)
                        holdAtCF(m, cfLookAt(pos, (pos - baseCF.Position)))
                    end
                end
            end
            if refresh then boxState.lastRefresh = now end
        end)
    end
    local function disableBox()
        boxOn = false
        for uid,rec in pairs(boxState.targets or {}) do
            for _,m in ipairs(rec.logs or {}) do endDrag(m); releaseTags(m) end
        end
        boxState = { targets = {}, lastRefresh = 0 }
        boxJobId = nil
    end

    local bullBtnRef = nil
    local function ensureEdgeStack()
        local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
        local edgeGui = playerGui:FindFirstChild("EdgeButtons")
        if not edgeGui then
            edgeGui = Instance.new("ScreenGui")
            edgeGui.Name = "EdgeButtons"
            edgeGui.ResetOnSpawn = false
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
        return stack
    end

    local function startBulldozerWall()
        local root = hrpOf(lp); if not root then return end
        local startCF = root.CFrame
        local look = startCF.LookVector
        local right = startCF.RightVector
        local head  = (lp.Character and lp.Character:FindFirstChild("Head"))
        local basePos = (head and head.Position or root.Position) + look*3 + Vector3.new(0, 2.5, 0)
        local jobId = ("%d-%d"):format(os.time(), math.random(1,1e6))

        local needWide = math.clamp(math.floor(12 / (BULL_GAP_STUDS + 1)), 4, 20)
        local need = math.min(BULL_MAX_LOGS, needWide * BULL_THICKNESS * 2)
        local picked = nearbyLogs(root.Position, SEARCH_RADIUS, need, jobId)
        local logs = {}
        local baselineY = basePos.Y

        local idx = 1
        for layer=1,2 do
            local layerOffset = (layer==1) and 0 or 2.5
            for t=1,BULL_THICKNESS do
                local depthOff = (t-1)*(BULL_GAP_STUDS+1)
                for w=-(math.floor(needWide/2)), math.floor(needWide/2) do
                    local m = picked[idx]; idx += 1
                    if not m then break end
                    if claimLog(m, jobId) then beginDrag(m) end
                    logs[#logs+1] = { m=m, offset = right*w*(BULL_GAP_STUDS+1) - look*depthOff, y = baselineY + layerOffset }
                    if idx > #picked then break end
                end
                if idx > #picked then break end
            end
            if idx > #picked then break end
        end

        for _,rec in ipairs(logs) do
            local pos = basePos + rec.offset
            pos = Vector3.new(pos.X, rec.y, pos.Z)
            holdAtCF(rec.m, cfLookAt(pos, look))
        end

        local traveled = 0
        while traveled < BULL_PUSH_STUDS do
            local step = math.min(BULL_SPEED * TICK, BULL_PUSH_STUDS - traveled)
            traveled += step
            local advance = look * step
            for _,rec in ipairs(logs) do
                if rec.m and rec.m.Parent then
                    local mp = mainPart(rec.m); if not mp then continue end
                    local cur = mp.Position
                    local pos = Vector3.new(cur.X, rec.y, cur.Z) + advance
                    holdAtCF(rec.m, cfLookAt(pos, look))
                end
            end
            task.wait(TICK)
        end
    end

    local function ensureBulldozerEdgeButton()
        local stack = ensureEdgeStack()
        local btn = stack:FindFirstChild("BulldozerEdge")
        if not btn then
            btn = Instance.new("TextButton")
            btn.Name = "BulldozerEdge"
            btn.Size = UDim2.new(1, 0, 0, 30)
            btn.Text = "Bulldozer"
            btn.TextSize = 12
            btn.Font = Enum.Font.GothamBold
            btn.BackgroundColor3 = Color3.fromRGB(30,30,35)
            btn.TextColor3 = Color3.new(1,1,1)
            btn.BorderSizePixel = 0
            btn.Visible = false
            btn.LayoutOrder = 7
            btn.Parent = stack
            local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = btn
            btn.MouseButton1Click:Connect(function() startBulldozerWall() end)
        end
        bullBtnRef = btn
    end
    ensureBulldozerEdgeButton()

    local function listPlayers()
        local vals = {}
        for _,p in ipairs(Players:GetPlayers()) do
            if p ~= lp then table.insert(vals, p.Name) end
        end
        table.sort(vals)
        return vals
    end
    local function nameToPlayerSet(names)
        local set = {}
        if type(names) == "table" then
            for _,n in ipairs(names) do
                local p = Players:FindFirstChild(n)
                if p and p ~= lp then set[p.UserId] = true end
            end
        elseif type(names) == "string" and names ~= "" then
            local p = Players:FindFirstChild(names)
            if p and p ~= lp then set[p.UserId] = true end
        end
        return set
    end

    tab:Section({ Title = "Targets" })
    local lastChoices = listPlayers()
    local picker = tab:Dropdown({
        Title = "Players",
        Values = lastChoices,
        Multi = true,
        AllowNone = true,
        Callback = function(choice)
            chaosSelected = nameToPlayerSet(choice)
        end
    })
    tab:Button({
        Title = "Refresh Players",
        Callback = function()
            local vals = listPlayers()
            if picker and picker.SetValues then pcall(function() picker:SetValues(vals) end) end
            lastChoices = vals
        end
    })

    tab:Section({ Title = "Chaos Swarm" })
    tab:Button({ Title = "Start Chaos", Callback = function()
        if next(chaosSelected) == nil then return end
        enableChaos()
    end })
    tab:Button({ Title = "Stop Chaos", Callback = function() disableChaos() end })

    tab:Section({ Title = "Box Trap" })
    local boxChoices = {}
    local boxPicker = tab:Dropdown({
        Title = "Players",
        Values = listPlayers(),
        Multi = true,
        AllowNone = true,
        Callback = function(choice)
            boxChoices = {}
            if type(choice)=="table" then
                for _,n in ipairs(choice) do
                    local p = Players:FindFirstChild(n)
                    if p and p~=lp then table.insert(boxChoices, p) end
                end
            end
        end
    })
    tab:Button({ Title = "Refresh Players (Box)", Callback = function()
        local vals = listPlayers()
        if boxPicker and boxPicker.SetValues then pcall(function() boxPicker:SetValues(vals) end) end
    end })
    tab:Toggle({
        Title = "Box Locks In Place",
        Value = BOX_LOCK_IN_PLACE,
        Callback = function(state) BOX_LOCK_IN_PLACE = state end
    })
    tab:Button({ Title = "Start Box", Callback = function()
        if #boxChoices == 0 then return end
        disableBox()
        enableBox(boxChoices)
    end })
    tab:Button({ Title = "Stop Box", Callback = function() disableBox() end })

    tab:Section({ Title = "Bulldozer" })
    ensureBulldozerEdgeButton()
    tab:Toggle({
        Title = "Edge Button: Bulldozer",
        Value = false,
        Callback = function(state)
            if bullBtnRef then bullBtnRef.Visible = state end
        end
    })

    Players.PlayerRemoving:Connect(function(p)
        local uid = p.UserId
        if chaosTargets[uid] then
            for m,_ in pairs(chaosTargets[uid].logs) do endDrag(m); releaseTags(m) end
            chaosTargets[uid] = nil
        end
        if boxState.targets[uid] then
            for _,m in ipairs(boxState.targets[uid].logs or {}) do endDrag(m); releaseTags(m) end
            boxState.targets[uid] = nil
        end
    end)
end
