-- troll.lua
return function(C, R, UI)
    local Players  = C.Services.Players
    local RS       = C.Services.RS
    local WS       = C.Services.WS
    local Run      = C.Services.Run
    local lp       = Players.LocalPlayer

    local tab = UI and UI.Tabs and UI.Tabs.Troll
    assert(tab, "Troll tab not found")

    local DRAG_RADIUS        = 200
    local MAX_PER_TARGET     = 20
    local RAIN_MIN_Y         = 18
    local RAIN_MAX_Y         = 35
    local RING_MIN_R         = 0.5
    private = private or {}
    local RING_MAX_R         = 3.2
    local RING_STEP_R        = 0.11
    local DROP_SPIN_AV       = 8
    local RESTORE_COLLIDE_AT = 0.25
    local CLEAN_ATTRS_DELAY  = 0.5

    local running = false
    local selected = {}
    local drop

    local function hrp(p)
        local pl = p or lp
        local ch = pl.Character or pl.CharacterAdded:Wait()
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
    local function itemsRootOrNil() return WS:FindFirstChild("Items") end

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
            pcall(function() REM.StartDrag:FireServer(model) end)
            return true
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

    local function setNoCollide(m)
        local snap = {}
        for _,p in ipairs(allParts(m)) do snap[p]=p.CanCollide; p.CanCollide=false; p.CanTouch=false end
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
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            p.Anchored = false
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
        end
    end
    local function pivot(m, cf)
        if not (m and m.Parent) then return end
        if m:IsA("Model") then m:PivotTo(cf) else local p=mainPart(m); if p then p.CFrame = cf end end
    end

    local function playerList()
        local t = {}
        for _,p in ipairs(Players:GetPlayers()) do if p ~= lp then t[#t+1] = p.Name end end
        table.sort(t); return t
    end
    local function setSelected(choice)
        local s = {}
        if type(choice) == "table" then for _,v in ipairs(choice) do if v and v~="" then s[v]=true end end
        elseif choice and choice~="" then s[choice]=true end
        selected = s
    end
    local function refreshDropdown()
        local vals = playerList()
        if drop and drop.SetValues then drop:SetValues(vals) end
    end
    Players.PlayerAdded:Connect(refreshDropdown)
    Players.PlayerRemoving:Connect(refreshDropdown)

    local function collectLogs(center, radius, limit)
        local items = itemsRootOrNil(); if not items then return {} end
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(center, radius, params) or {}
        local uniq, out = {}, {}
        for _,p in ipairs(parts) do
            local m = p:FindFirstAncestorOfClass("Model")
            if m and not uniq[m] and m.Parent == items and m.Name == "Log" then
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
            if p and p.Character and p.Character.Parent and hrp(p) then
                t[#t+1] = p
            end
        end
        return t
    end

    local function rainOne(log, targetPlr, slotIndex)
        if not (log and log.Parent) then return end
        local root = hrp(targetPlr); if not root then return end

        local started = startDrag(log)
        local snap = setNoCollide(log)
        zeroAssembly(log)

        local head = targetPlr.Character and targetPlr.Character:FindFirstChild("Head")
        local base = head and head.Position or root.Position
        local y    = math.random(RAIN_MIN_Y*10, RAIN_MAX_Y*10) / 10
        local rIdx = slotIndex or 1
        local ring = math.min(RING_MIN_R + (rIdx-1)*RING_STEP_R, RING_MAX_R)
        local ang  = rIdx * 2.39996323
        local offset = Vector3.new(math.cos(ang)*ring, 0, math.sin(ang)*ring)

        local topPos = base + Vector3.new(0, y, 0) + offset
        local look   = (root.CFrame.LookVector.Magnitude > 0) and root.CFrame.LookVector or Vector3.new(0,0,-1)
        pivot(log, CFrame.lookAt(topPos, topPos + look))

        for _,p in ipairs(allParts(log)) do
            p.AssemblyLinearVelocity  = Vector3.new(0, -DROP_SPIN_AV*1.5, 0)
            p.AssemblyAngularVelocity = Vector3.new(0, DROP_SPIN_AV, 0)
        end

        task.delay(RESTORE_COLLIDE_AT, function()
            if log and log.Parent then restoreCollide(log, snap) end
        end)
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
                restoreCollide(job.log, job.snap or {})
            end
        end
        activeJobs = {}
    end

    local function startRain()
        if running then return end
        local myRoot = hrp(); if not myRoot then return end
        local targets = targetsFromSelection()
        if #targets == 0 then return end

        running = true
        local maxNeed = MAX_PER_TARGET * #targets
        local pool = collectLogs(myRoot.Position, DRAG_RADIUS, maxNeed)

        if #pool == 0 then running=false; return end

        local per = math.max(1, math.floor(#pool / #targets))
        per = math.min(per, MAX_PER_TARGET)

        local cursor = 1
        local slotIdx = {}
        for _,pl in ipairs(targets) do slotIdx[pl] = 1 end

        while running and cursor <= #pool do
            for _,pl in ipairs(targets) do
                for i=1,per do
                    local log = pool[cursor]; if not log then break end
                    local idx = slotIdx[pl] or 1
                    slotIdx[pl] = idx + 1
                    table.insert(activeJobs, {log=log})
                    rainOne(log, pl, idx)
                    cursor = cursor + 1
                    task.wait(0.07)
                    if cursor > #pool then break end
                end
                if cursor > #pool then break end
            end
        end

        task.delay(2.0, function() running = false; activeJobs = {} end)
    end

    tab:Section({ Title = "Targets" })
    drop = tab:Dropdown({
        Title = "Select Players",
        Values = playerList(),
        Multi = true,
        AllowNone = true,
        Callback = setSelected
    })

    tab:Section({ Title = "Controls" })
    tab:Button({ Title = "Start Rain", Callback = startRain })
    tab:Button({ Title = "Stop",       Callback = stopAll })
end
