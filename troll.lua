-- troll.lua
return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")

    local lp = Players.LocalPlayer
    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Troll
    assert(tab, "Troll tab not found in UI")

    local DRAG_RADIUS       = 200
    local MAX_LOGS_PER_USER = 20
    local UPDATE_HZ         = 30
    local PART_MIN_SIZE     = 0.35

    local drop
    local selectedNames = {}

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local function mainPart(m)
        if not (m and m:IsA("Model")) then return nil end
        return m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
    end
    local function partsOf(obj)
        local t = {}
        if not obj then return t end
        if obj:IsA("Model") then
            for _,d in ipairs(obj:GetDescendants()) do
                if d:IsA("BasePart") then t[#t+1] = d end
            end
        end
        return t
    end
    local function itemsRootOrNil() return WS:FindFirstChild("Items") end

    local function resolveRemotes()
        local re = RS:FindFirstChild("RemoteEvents"); if not re then return {} end
        local function pick(...) for _,n in ipairs({...}) do local x=re:FindFirstChild(n); if x then return x end end end
        return {
            StartDrag = pick("RequestStartDraggingItem","StartDraggingItem"),
            StopDrag  = pick("StopDraggingItem","RequestStopDraggingItem"),
        }
    end
    local REM = resolveRemotes()

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

    local function playerList()
        local t = {}
        for _,p in ipairs(Players:GetPlayers()) do
            if p ~= lp then t[#t+1] = p.Name end
        end
        table.sort(t)
        return t
    end
    local function setSelectedFromDropdown(choice)
        local set = {}
        if type(choice) == "table" then
            for _,v in ipairs(choice) do if v and v ~= "" then set[v] = true end end
        elseif choice and choice ~= "" then
            set[choice] = true
        end
        selectedNames = set
    end
    local function refreshDropdown()
        local vals = playerList()
        if drop and drop.SetValues then drop:SetValues(vals) end
    end
    Players.PlayerAdded:Connect(refreshDropdown)
    Players.PlayerRemoving:Connect(refreshDropdown)

    local function pickTargetParts(char)
        local parts = {}
        for _,bp in ipairs(partsOf(char)) do
            if bp.Name ~= "HumanoidRootPart" then
                local s = bp.Size
                if s.X >= PART_MIN_SIZE or s.Y >= PART_MIN_SIZE or s.Z >= PART_MIN_SIZE then
                    parts[#parts+1] = bp
                end
            end
        end
        if #parts == 0 then
            local p = char and char:FindFirstChild("HumanoidRootPart")
            if p then parts[#parts+1] = p end
        end
        return parts
    end

    local function golden(i) return i * 2.399963229728653 end

    local function ensureDragOwnership(model)
        for _,p in ipairs(partsOf(model)) do
            p.Anchored = false
            p.CanCollide = false
            p.CanTouch = false
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            pcall(function() p:SetNetworkOwner(lp) end)
        end
    end
    local function placeAt(model, cf)
        if not model or not model.Parent then return end
        if model:IsA("Model") then
            model:PivotTo(cf)
        else
            local mp = mainPart(model)
            if mp then mp.CFrame = cf end
        end
    end

    local function nearbyLogs(center, radius, excludeSet)
        local items = itemsRootOrNil(); if not items then return {} end
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(center, radius, params) or {}
        local uniq, out = {}, {}
        for _,p in ipairs(parts) do
            local m = p:FindFirstAncestorOfClass("Model")
            if m and not uniq[m] and m.Parent == items and m.Name == "Log" and not excludeSet[m] then
                local mp = mainPart(m)
                if mp and (mp.Position - center).Magnitude <= radius then
                    uniq[m] = true; out[#out+1] = m
                end
            end
        end
        return out
    end

    local attachments = {}                   -- uid -> { entries = { {model, part, idx, ω, r, h, φ} }, conn }
    local claimed     = setmetatable({}, {__mode="k"}) -- model -> true

    local function detachForUserId(uid)
        local pack = attachments[uid]
        if not pack then return end
        for i=#pack.entries,1,-1 do
            local e = pack.entries[i]
            if e.model and e.model.Parent then
                stopDrag(e.model)
                for _,p in ipairs(partsOf(e.model)) do
                    p.CanCollide = true
                    p.CanTouch = true
                end
            end
            claimed[e.model] = nil
            table.remove(pack.entries, i)
        end
        if pack.conn then pack.conn:Disconnect(); pack.conn = nil end
        attachments[uid] = nil
    end

    local function ensureFollowLoop(uid, char)
        local pack = attachments[uid]; if not pack then return end
        if pack.conn then return end
        local acc, tickDt = 0, 1/UPDATE_HZ
        pack.conn = Run.Heartbeat:Connect(function(dt)
            acc += dt
            if acc < tickDt then return end
            acc = 0
            if not char or not char.Parent then detachForUserId(uid); return end
            local now = os.clock()
            for i=#pack.entries,1,-1 do
                local e = pack.entries[i]
                local model, part = e.model, e.part
                if not (model and model.Parent and part and part.Parent) then
                    claimed[model] = nil
                    table.remove(pack.entries, i)
                else
                    ensureDragOwnership(model)
                    local ang = e.φ + now * e.ω
                    local x = math.cos(ang) * e.r
                    local z = math.sin(ang) * e.r
                    local y = e.h
                    local cf = part.CFrame * CFrame.new(x, y, z)
                    placeAt(model, cf)
                end
            end
            if #pack.entries == 0 then
                if pack.conn then pack.conn:Disconnect(); pack.conn=nil end
                attachments[uid] = nil
            end
        end)
    end

    local function attachLogsToPlayer(plr)
        if not plr or plr == lp then return end
        local char = plr.Character
        if not (char and char.Parent) then return end
        local uid = tostring(plr.UserId)
        attachments[uid] = attachments[uid] or { entries = {}, conn = nil }
        local pack = attachments[uid]

        local need = math.max(0, MAX_LOGS_PER_USER - #pack.entries)
        if need <= 0 then ensureFollowLoop(uid, char); return end

        local root = hrp(); if not root then return end
        local pool = nearbyLogs(root.Position, DRAG_RADIUS, claimed)
        if #pool == 0 then ensureFollowLoop(uid, char); return end

        local targets = pickTargetParts(char); if #targets == 0 then return end

        local added = 0
        local baseIdx = #pack.entries
        for i=1,#pool do
            if added >= need then break end
            local m = pool[i]
            if m and m.Parent and not claimed[m] then
                local ok = startDrag(m)
                claimed[m] = true
                ensureDragOwnership(m)
                local idx = baseIdx + added + 1
                local part = targets[((idx - 1) % #targets) + 1]
                local ω = 1.2 + (idx % 5) * 0.15
                local r = 1.0 + (idx % 7) * 0.08
                local h = -0.2 + ((idx * 0.37) % 1.0) * 0.9
                local φ = golden(idx)
                pack.entries[#pack.entries+1] = { model=m, part=part, idx=idx, ω=ω, r=r, h=h, φ=φ }
                added += 1
            end
        end
        ensureFollowLoop(uid, char)
    end

    local function addSelectedPlayers()
        for name,_ in pairs(selectedNames) do
            local plr = Players:FindFirstChild(name)
            if plr and plr:IsA("Player") then attachLogsToPlayer(plr) end
        end
    end
    local function stopForUnselected()
        local keep = {}
        for name,_ in pairs(selectedNames) do keep[name] = true end
        for uid,_ in pairs(attachments) do
            local plr = Players:GetPlayerByUserId(tonumber(uid) or 0)
            if not (plr and keep[plr.Name]) then detachForUserId(uid) end
        end
    end

    tab:Section({ Title = "Target Players" })
    drop = tab:Dropdown({
        Title = "Select Players",
        Values = playerList(),
        Multi = true,
        AllowNone = true,
        Callback = setSelectedFromDropdown
    })

    tab:Section({ Title = "Controls" })
    tab:Button({ Title = "Start", Callback = addSelectedPlayers })
    tab:Button({ Title = "Stop",  Callback = stopForUnselected })
end
