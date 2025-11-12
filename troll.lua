-- troll.lua
return function(C, R, UI)
    local Players = (C and C.Services and C.Services.Players) or game:GetService("Players")
    local RS      = (C and C.Services and C.Services.RS)      or game:GetService("ReplicatedStorage")
    local WS      = (C and C.Services and C.Services.WS)      or game:GetService("Workspace")
    local Run     = (C and C.Services and C.Services.Run)     or game:GetService("RunService")

    local lp = Players.LocalPlayer
    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Troll or Tabs.Main
    if not tab then return end

    local RE = RS:WaitForChild("RemoteEvents")
    local StartDrag = RE:FindFirstChild("RequestStartDraggingItem") or RE:WaitForChild("RequestStartDraggingItem")
    local StopDrag  = RE:FindFirstChild("StopDraggingItem")

    local function hrp(plr)
        local c = plr and plr.Character
        return c and c:FindFirstChild("HumanoidRootPart")
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
    local function setNoCollide(m)
        local snap = {}
        for _,p in ipairs(allParts(m)) do snap[p]=p.CanCollide; p.CanCollide=false end
        return snap
    end
    local function restoreCollide(snap)
        for p,v in pairs(snap or {}) do
            if p and p.Parent then p.CanCollide = v end
        end
    end
    local function zeroAssembly(m)
        for _,p in ipairs(allParts(m)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
    end
    local function pivot(m, cf)
        if m:IsA("Model") then m:PivotTo(cf) else local p=mainPart(m); if p then p.CFrame = cf end end
    end

    local STATE = {
        PerTarget = (C and C.State and C.State.TrollLogsPer) or 20,
        PickRadius = 200,
        OrbitSpeed = 0.7,
        BaseRadius = 1.15,
        RadiusStep = 0.12,
        BaseHeight = 1.1,
        HeightStep = 0.45,
        RingSlots = 10,
        Leash = 60,
        TightenSnap = 6,
        RefreshH = 1/60,
    }

    local selectedNames = {}
    local function listPlayers()
        local vals = {}
        for _,p in ipairs(Players:GetPlayers()) do
            if p ~= lp then vals[#vals+1] = p.Name end
        end
        table.sort(vals)
        return vals
    end
    local TargetsDropdown
    local function getSelectedPlayers()
        local map = {}
        for _,p in ipairs(Players:GetPlayers()) do
            if p ~= lp and selectedNames[p.Name] then
                map[p.UserId] = p
            end
        end
        return map
    end

    TargetsDropdown = tab:Dropdown({
        Title = "Targets",
        Values = listPlayers(),
        Multi = true,
        AllowNone = true,
        Callback = function(choice)
            selectedNames = {}
            if type(choice) == "table" then
                for _,n in ipairs(choice) do selectedNames[n] = true end
            elseif type(choice) == "string" and choice ~= "" then
                selectedNames[choice] = true
            end
        end
    })

    tab:Slider({
        Title = "Logs per Target",
        Value = { Min = 1, Max = 50, Default = STATE.PerTarget },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then nv = v.Value or v.Current or v.Default end
            nv = tonumber(nv)
            if nv then
                STATE.PerTarget = math.clamp(nv, 1, 50)
                if C and C.State then C.State.TrollLogsPer = STATE.PerTarget end
            end
        end
    })

    local running = false
    local hbConn  = nil

    local controllers = {}
    local assigned = setmetatable({}, {__mode="k"})

    local function findNearbyLogs(center, limit)
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(center, STATE.PickRadius, params) or {}
        local uniq, out = {}, {}
        for _,p in ipairs(parts) do
            local m = p:FindFirstAncestorOfClass("Model")
            if m and not uniq[m] and m.Name == "Log" and not assigned[m] then
                local mp = mainPart(m)
                if mp then uniq[m]=true; out[#out+1]=m end
                if limit and #out >= limit then break end
            end
        end
        return out
    end

    local function takeControl(m)
        pcall(function() StartDrag:FireServer(m) end)
        local snap = setNoCollide(m)
        zeroAssembly(m)
        for _,p in ipairs(allParts(m)) do
            p.Anchored = false
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
        end
        return snap
    end

    local function releaseControl(m, snap)
        if StopDrag then pcall(function() StopDrag:FireServer(m) end) end
        restoreCollide(snap)
        zeroAssembly(m)
        assigned[m] = nil
    end

    local function assignLogsForTargets(targetMap)
        local root = hrp(lp); if not root then return end
        local needed = 0
        for uid,_ in pairs(targetMap) do
            local ctrl = controllers[uid]
            local have = 0
            if ctrl and ctrl.logs then have = #ctrl.logs end
            local want = STATE.PerTarget
            if have < want then needed = needed + (want - have) end
        end
        if needed <= 0 then return end
        local pool = findNearbyLogs(root.Position, needed)
        local idx = 1
        for uid,plr in pairs(targetMap) do
            local ctrl = controllers[uid]
            if not ctrl then
                ctrl = { plr = plr, logs = {}, snaps = {}, layout = {}, t0 = os.clock(), basePhase = math.random() * math.pi * 2 }
                controllers[uid] = ctrl
            end
            local want = STATE.PerTarget
            while #ctrl.logs < want and idx <= #pool do
                local m = pool[idx]; idx += 1
                if m and m.Parent then
                    assigned[m] = true
                    local snap = takeControl(m)
                    table.insert(ctrl.logs, m)
                    ctrl.snaps[m] = snap
                end
            end
        end
    end

    local function refreshControllers(targetMap)
        for uid,ctrl in pairs(controllers) do
            if not targetMap[uid] then
                if ctrl.logs then
                    for _,m in ipairs(ctrl.logs) do
                        if m and m.Parent then releaseControl(m, ctrl.snaps[m]) end
                    end
                end
                controllers[uid] = nil
            end
        end
        assignLogsForTargets(targetMap)
    end

    local function ensureLayout(ctrl)
        local n = #ctrl.logs
        ctrl.layout = ctrl.layout or {}
        if #ctrl.layout == n then return end
        local perRing = STATE.RingSlots
        local layout = {}
        for i=1,n do
            local layer = math.floor((i-1)/perRing)
            local idx   = (i-1) % perRing
            local ang   = (2*math.pi/perRing) * idx + math.random()*0.25
            layout[i] = { layer = layer, ang0 = ang }
        end
        ctrl.layout = layout
    end

    local function updateOne(m, tgtPos, ang, rad, y)
        if not (m and m.Parent) then return end
        local mp = mainPart(m); if not mp then return end
        local dest = Vector3.new(tgtPos.X + math.cos(ang)*rad, tgtPos.Y + y, tgtPos.Z + math.sin(ang)*rad)
        local pos  = mp.Position
        local d    = (pos - dest).Magnitude
        if d > STATE.TightenSnap then
            pivot(m, CFrame.new(dest, dest + (dest - pos).Unit))
        else
            pivot(m, CFrame.new(dest, dest + Vector3.new(0,0,1)))
        end
        for _,p in ipairs(allParts(m)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
        local leashC = (pos - tgtPos).Magnitude
        if leashC > STATE.Leash then
            pivot(m, CFrame.new(dest))
        end
    end

    local function heartbeat(dt)
        if not running then return end
        local targetMap = getSelectedPlayers()
        refreshControllers(targetMap)
        for uid,ctrl in pairs(controllers) do
            local h = hrp(ctrl.plr)
            if not h then continue end
            ensureLayout(ctrl)
            local t = os.clock() - ctrl.t0
            local base = h.Position
            for i,m in ipairs(ctrl.logs) do
                if not (m and m.Parent) then continue end
                local cell = ctrl.layout[i]
                if not cell then continue end
                local layer = cell.layer
                local ang   = cell.ang0 + ctrl.basePhase + t * STATE.OrbitSpeed * (1 + layer*0.07) * ((layer%2==0) and 1 or -1)
                local rad   = STATE.BaseRadius + STATE.RadiusStep * layer
                local y     = STATE.BaseHeight + STATE.HeightStep * layer
                updateOne(m, base, ang, rad, y)
            end
        end
    end

    local function start()
        if running then return end
        running = true
        if hbConn then hbConn:Disconnect() end
        hbConn = Run.Heartbeat:Connect(heartbeat)
    end

    local function stop()
        running = false
        if hbConn then hbConn:Disconnect(); hbConn=nil end
        for uid,ctrl in pairs(controllers) do
            if ctrl.logs then
                for _,m in ipairs(ctrl.logs) do
                    if m and m.Parent then releaseControl(m, ctrl.snaps[m]) end
                end
            end
            controllers[uid] = nil
        end
    end

    tab:Section({ Title = "Controls" })
    tab:Button({ Title = "Start", Callback = start })
    tab:Button({ Title = "Stop",  Callback = stop })

    Players.PlayerAdded:Connect(function()
        if TargetsDropdown and TargetsDropdown.SetValues then
            TargetsDropdown:SetValues(listPlayers())
        end
    end)
    Players.PlayerRemoving:Connect(function()
        if TargetsDropdown and TargetsDropdown.SetValues then
            TargetsDropdown:SetValues(listPlayers())
        end
    end)
end
