-- troll.lua
return function(C, R, UI)
    local Players  = C.Services.Players
    local RS       = C.Services.RS
    local WS       = C.Services.WS
    local Run      = C.Services.Run
    local lp       = Players.LocalPlayer

    local tab = UI and UI.Tabs and UI.Tabs.Troll
    assert(tab, "Troll tab not found")

    -- Tunables
    local DRAG_RADIUS        = 200
    local MAX_PER_TARGET     = 20
    local RAIN_MIN_Y         = 18
    local RAIN_MAX_Y         = 35
    local RING_MIN_R         = 0.5
    local RING_MAX_R         = 3.2
    local RING_STEP_R        = 0.11
    local DROP_SPIN_AV       = 8
    local COLLIDE_RESTORE_S  = 0.25
    local CLEAN_ATTRS_DELAY  = 0.6
    local BETWEEN_DROPS_S    = 0.07

    local running = false
    local selected = {}
    local statusLabel

    -- Utilities
    local function hrp(p)
        local who = p or lp
        local ch = who.Character or who.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end
    local function mainPart(m)
        if not (m and m:IsA("Model")) then return nil end
        return m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
    end
    local function allParts(m)
        local t = {}
        if not m then return t end
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then t[#t+1] = d end
        end
        return t
    end
    local function itemsRootOrNil()
        return WS:FindFirstChild("Items") or WS
    end
    local function uiStatus(msg)
        if statusLabel then statusLabel:SetText(msg) end
        print("[Troll] " .. tostring(msg))
    end

    -- Remotes
    local function getRemote(...)
        local re = RS:FindFirstChild("RemoteEvents"); if not re then return nil end
        for _,n in ipairs({...}) do local x=re:FindFirstChild(n); if x then return x end end
        return nil
    end
    local REM = {
        StartDrag = getRemote("RequestStartDraggingItem","StartDraggingItem"),
        StopDrag  = getRemote("StopDraggingItem","RequestStopDraggingItem"),
    }
    local function startDrag(model)
        if REM.StartDrag and model and model.Parent then
            local ok,err = pcall(function() REM.StartDrag:FireServer(model) end)
            if not ok then uiStatus("StartDrag failed: "..tostring(err)) end
            return ok
        end
        return false
    end
    local function stopDrag(model)
        if REM.StopDrag and model and model.Parent then
            pcall(function() REM.StopDrag:FireServer(model) end)
            return true
        end
        return false
    end

    -- Collision helpers
    local function setNoCollide(m)
        local snap = {}
        for _,p in ipairs(allParts(m)) do
            snap[p] = p.CanCollide
            p.CanCollide = false
            p.CanTouch   = false
        end
        return snap
    end
    local function restoreCollide(m, snap)
        for part,can in pairs(snap or {}) do
            if part and part.Parent then
                part.CanCollide = can
                part.CanTouch   = true
            end
        end
    end
    local function zeroAssembly(m)
        for _,p in ipairs(allParts(m)) do
            p.Anchored = false
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
        end
    end

    -- Selection UI
    local function playerList()
        local t = {}
        for _,p in ipairs(Players:GetPlayers()) do if p ~= lp then t[#t+1] = p.Name end end
        table.sort(t); return t
    end
    local function setSelected(choice)
        local s = {}
        if type(choice) == "table" then
            for _,v in ipairs(choice) do if v and v~="" then s[v]=true end end
        elseif choice and choice~="" then
            s[choice] = true
        end
        selected = s
        uiStatus(("Selected %d players"):format((function() local c=0 for _ in pairs(s) do c=c+1 end; return c end)()))
    end
    local drop = tab:Dropdown({
        Title = "Select Players",
        Values = playerList(),
        Multi = true,
        AllowNone = true,
        Callback = setSelected
    })
    Players.PlayerAdded:Connect(function() if drop and drop.SetValues then drop:SetValues(playerList()) end end)
    Players.PlayerRemoving:Connect(function() if drop and drop.SetValues then drop:SetValues(playerList()) end end)

    -- Simple status label
    statusLabel = tab:Label({ Title = "Idle" })
    function statusLabel:SetText(t) self.Title = t end

    -- Log discovery
    local function collectLogs(center, radius, limit)
        local root = itemsRootOrNil()
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(center, radius, params) or {}
        local uniq, out = {}, {}
        for _,p in ipairs(parts) do
            local m = p:FindFirstAncestorOfClass("Model")
            if m and not uniq[m] and m.Parent and m.Name == "Log" then
                local mp = mainPart(m)
                if mp and (mp.Position - center).Magnitude <= radius then
                    uniq[m] = true
                    out[#out+1] = m
                    if limit and #out >= limit then break end
                end
            end
        end
        return out
    end

    local function targetsFromSelection()
        local t = {}
        for name,_ in pairs(selected) do
            local p = Players:FindFirstChild(name)
            if p and p.Character and hrp(p) then t[#t+1] = p end
        end
        return t
    end

    -- Ring positions above a player
    local function ringOffset(i)
        local a = i * 2.39996323
        local r = math.min(RING_MIN_R + (i-1)*RING_STEP_R, RING_MAX_R)
        return Vector3.new(math.cos(a)*r, 0, math.sin(a)*r)
    end

    -- Server-visible “rain”: rely on server drag, then physics
    local function rainOne(log, targetPlr, slotIndex)
        if not (log and log.Parent) then return end
        local root = hrp(targetPlr); if not root then return end

        -- Start server drag so the server takes ownership and replication
        local started = startDrag(log)

        -- Soften contacts while traveling
        local snap = setNoCollide(log)
        zeroAssembly(log)

        -- Choose a spawn point above the target, offset on a ring
        local head = targetPlr.Character and targetPlr.Character:FindFirstChild("Head")
        local base = head and head.Position or root.Position
        local y    = math.random(RAIN_MIN_Y*10, RAIN_MAX_Y*10) / 10
        local idx  = slotIndex or 1
        local offset = ringOffset(idx)
        local topPos = base + Vector3.new(0, y, 0) + offset

        -- Use only physics impulses. Avoid client CFrame teleports.
        -- Small upward nudge to encourage replication even if ownership flips.
        for _,p in ipairs(allParts(log)) do
            p.AssemblyAngularVelocity = Vector3.new(0, DROP_SPIN_AV, 0)
        end

        -- If we have a main part, set its position once via velocity impulses:
        local mp = mainPart(log)
        if mp then
            -- A tiny reposition via velocity toward topPos; do not set CFrame hard.
            local pos = mp.Position
            local toTop = topPos - pos
            local horiz = Vector3.new(toTop.X, 0, toTop.Z)
            -- Kick upward then let it fall
            mp.AssemblyLinearVelocity = Vector3.new(horiz.X, math.max(35, toTop.Y), horiz.Z)
        end

        -- Restore collisions shortly before impact
        task.delay(COLLIDE_RESTORE_S, function()
            if log and log.Parent then restoreCollide(log, snap) end
        end)

        -- Stop dragging after drop window
        task.delay(CLEAN_ATTRS_DELAY, function()
            if started and log and log.Parent then stopDrag(log) end
        end)
    end

    local activeJobs = {}

    local function stopAll()
        running = false
        for _,job in ipairs(activeJobs) do
            if job and job.log and job.log.Parent then
                pcall(stopDrag, job.log)
                -- safety restore
                restoreCollide(job.log, job.snap or {})
            end
        end
        activeJobs = {}
        uiStatus("Stopped")
    end

    local function startRain()
        if running then return end
        local myRoot = hrp(); if not myRoot then uiStatus("No HRP"); return end
        if not REM.StartDrag then uiStatus("StartDrag remote missing"); return end

        local targets = targetsFromSelection()
        if #targets == 0 then uiStatus("No targets selected"); return end

        running = true

        -- Pool logs
        local maxNeed = MAX_PER_TARGET * #targets
        local pool = collectLogs(myRoot.Position, DRAG_RADIUS, maxNeed)
        uiStatus(("Found %d logs, %d target(s)"):format(#pool, #targets))
        if #pool == 0 then running = false; return end

        -- Divide fairly
        local per = math.max(1, math.floor(#pool / #targets))
        per = math.min(per, MAX_PER_TARGET)

        -- Interleave per player
        local cursor = 1
        local slotIdx = {}
        for _,pl in ipairs(targets) do slotIdx[pl] = 1 end

        while running and cursor <= #pool do
            for _,pl in ipairs(targets) do
                for _=1,per do
                    local log = pool[cursor]; if not log then break end
                    local idx = slotIdx[pl] or 1
                    slotIdx[pl] = idx + 1
                    table.insert(activeJobs, {log=log})
                    rainOne(log, pl, idx)
                    cursor = cursor + 1
                    task.wait(BETWEEN_DROPS_S)
                    if cursor > #pool then break end
                end
                if cursor > #pool then break end
            end
        end

        task.delay(2.0, function()
            running = false
            activeJobs = {}
            uiStatus("Rain complete")
        end)
    end

    -- UI
    tab:Section({ Title = "Controls" })
    tab:Button({ Title = "Start Rain", Callback = startRain })
    tab:Button({ Title = "Stop",       Callback = stopAll })
end
