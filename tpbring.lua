-- tpbring.lua
return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")

    local lp  = Players.LocalPlayer
    local tab = UI and UI.Tabs and (UI.Tabs.TPBring or UI.Tabs.Bring or UI.Tabs.Auto or UI.Tabs.Main)
    if not tab then return end

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
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

    local function setPivot(m, cf)
        if m:IsA("Model") then
            m:PivotTo(cf)
        else
            local p = mainPart(m)
            if p then p.CFrame = cf end
        end
    end

    local function zeroAssembly(m)
        for _,p in ipairs(allParts(m)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            p.RotVelocity             = Vector3.new()
            p.Velocity                = Vector3.new()
        end
    end

    local function snapshotCollide(m)
        local s = {}
        for _,p in ipairs(allParts(m)) do s[p] = p.CanCollide end
        return s
    end

    local function setCollideFromSnapshot(snap)
        for part,can in pairs(snap or {}) do
            if part and part.Parent then part.CanCollide = can end
        end
    end

    local function setAnchored(m, on)
        for _,p in ipairs(allParts(m)) do p.Anchored = on end
    end

    local function setNoCollide(m)
        local s = {}
        for _,p in ipairs(allParts(m)) do
            s[p] = p.CanCollide
            p.CanCollide = false
        end
        return s
    end

    ----------------------------------------------------------------
    -- Remotes
    ----------------------------------------------------------------
    local startDrag, stopDrag = nil, nil
    do
        local re = RS:FindFirstChild("RemoteEvents")
        if re then
            startDrag = re:FindFirstChild("RequestStartDraggingItem")
            stopDrag  = re:FindFirstChild("StopDraggingItem")
        end
    end

    ----------------------------------------------------------------
    -- EdgeButtons container (unchanged)
    ----------------------------------------------------------------
    local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
    local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
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
        stack.AnchorPoint = Vector2.new(1,0)
        stack.Position = UDim2.new(1,-6,0,6)
        stack.Size = UDim2.new(0,130,1,-12)
        stack.BackgroundTransparency = 1
        stack.Parent = edgeGui
        local list = Instance.new("UIListLayout")
        list.FillDirection = Enum.FillDirection.Vertical
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Padding = UDim.new(0,6)
        list.HorizontalAlignment = Enum.HorizontalAlignment.Right
        list.Parent = stack
    end

    ----------------------------------------------------------------
    -- CORE CONFIG
    ----------------------------------------------------------------
    local DRAG_SPEED       = 220
    local ORB_HEIGHT       = 10
    local MAX_CONCURRENT   = 40
    local START_STAGGER    = 0.01
    local STEP_WAIT        = 0.016

    local LAND_MIN         = 0.35
    local LAND_MAX         = 0.85
    local ARRIVE_EPS_H     = 0.9
    local STALL_SEC        = 0.6

    local HOVER_ABOVE_ORB  = 1.2
    local RELEASE_RATE_HZ  = 16
    local MAX_RELEASE_PER_TICK = 8

    local STAGE_TIMEOUT_S  = 1.5
    local ORB_UNSTICK_RAD  = 2.0
    local ORB_UNSTICK_HZ   = 10
    local STUCK_TTL        = 6.0

    local INFLT_ATTR = "OrbInFlightAt"
    local JOB_ATTR   = "OrbJob"
    local DONE_ATTR  = "OrbDelivered"

    local CURRENT_RUN_ID   = nil
    local CURRENT_MODE     = nil  -- "fuel" | "scrap" | "all" | "orbs" | nil

    local running      = false
    local hb           = nil
    local orb          = nil
    local orbPosVec    = nil
    local inflight     = {}
    local releaseQueue = {}
    local releaseAcc   = 0.0
    local activeCount  = 0

    ----------------------------------------------------------------
    -- ITEM DEFINITIONS (from Bring module)
    ----------------------------------------------------------------
    local junkItems = {
        "Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine",
        "UFO Junk","UFO Component"
    }
    local fuelItems = {"Log","Coal","Fuel Canister","Oil Barrel","Chair"}
    local foodItems = {
        "Morsel","Cooked Morsel","Steak","Cooked Steak","Ribs","Cooked Ribs","Cake","Berry","Carrot",
        "Chilli","Stew","Pumpkin","Hearty Stew","Corn","BBQ ribs","Apple","Mackerel"
    }
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {
        "Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe","Hammer",
        "Chainsaw","Crossbow","Katana","Kunai","Laser cannon","Laser sword","Morningstar","Riot shield","Spear","Tactical Shotgun","Wildfire",
        "Sword","Ice Axe"
    }
    local ammoMisc = {
        "Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling",
        "Basketball","Blueprint","Diamond","Forest Gem","Key","Flashlight","Taming flute","Cultist Gem","Tusk","Infernal Sack"
    }
    local pelts = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Scorpion Shell","Polar Bear Pelt","Arctic Fox Pelt"}

    local fuelSet, junkSet, cookSet, scrapAlso = {}, {}, {}, {}
    for _,n in ipairs(fuelItems) do fuelSet[n] = true end
    for _,n in ipairs(junkItems) do junkSet[n] = true end
    cookSet["Morsel"] = true; cookSet["Steak"] = true; cookSet["Ribs"] = true
    scrapAlso["Log"] = true;  scrapAlso["Chair"] = true

    local fuelModeSet = { ["Coal"] = true, ["Fuel Canister"] = true, ["Oil Barrel"] = true }
    local scrapModeSet = {}
    for k,v in pairs(junkSet)   do if v then scrapModeSet[k] = true end end
    for k,v in pairs(scrapAlso) do if v then scrapModeSet[k] = true end end

    local allModeSet = {}
    local function addListToSet(list, set)
        for _,n in ipairs(list) do set[n] = true end
    end
    local function addSetToSet(src, dst)
        for k,v in pairs(src) do if v then dst[k] = true end end
    end
    addSetToSet(junkSet, allModeSet)
    addSetToSet(fuelSet, allModeSet)
    addListToSet(foodItems, allModeSet)
    addListToSet(medicalItems, allModeSet)
    addListToSet(weaponsArmor, allModeSet)
    addListToSet(ammoMisc, allModeSet)
    addListToSet(pelts, allModeSet)

    local allItemNames = {}
    for name,_ in pairs(allModeSet) do
        allItemNames[#allItemNames+1] = name
    end
    table.sort(allItemNames)

    ----------------------------------------------------------------
    -- Shared item helpers (adapted from Bring)
    ----------------------------------------------------------------
    local function itemsRootOrNil()
        return WS:FindFirstChild("Items")
    end

    local function isWallVariant(m)
        if not (m and m:IsA("Model")) then return false end
        local n = (m.Name or ""):lower()
        return n == "logwall" or n == "log wall" or (n:find("log",1,true) and n:find("wall",1,true))
    end

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

    local function hasIceBlockTag(inst)
        if not inst then return false end
        for _,d in ipairs(inst:GetDescendants()) do
            local n = (d.Name or ""):lower()
            if n:find("iceblock",1,true) or n:find("ice block",1,true) then
                return true
            end
        end
        local cur = inst.Parent
        for _ = 1, 10 do
            if not cur then break end
            local n = (cur.Name or ""):lower()
            if n:find("iceblock",1,true) or n:find("ice block",1,true) then
                return true
            end
            cur = cur.Parent
        end
        return false
    end

    local function hasHumanoid(model)
        if not (model and model:IsA("Model")) then return false end
        return model:FindFirstChildOfClass("Humanoid") ~= nil
    end

    local function isExcludedModel(m)
        if not (m and m:IsA("Model")) then return false end
        local n = (m.Name or ""):lower()
        if n == "pelt trader" then return true end
        if n:find("trader",1,true) or n:find("shopkeeper",1,true) then return true end
        if isWallVariant(m) then return true end
        if isUnderLogWall(m) then return true end
        return false
    end

    local function isInsideTree(m)
        local cur = m and m.Parent
        while cur and cur ~= WS do
            local nm = (cur.Name or ""):lower()
            if nm:find("tree",1,true) then return true end
            if cur == itemsRootOrNil() then break end
            cur = cur.Parent
        end
        return false
    end

    local function nameMatches(selectedSet, m)
        local itemsFolder = itemsRootOrNil()
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then
            return false
        end

        local nm = m and m.Name or ""
        local l  = nm:lower()

        if nm == "Apple" and selectedSet["Apple"] then
            if itemsFolder and m.Parent ~= itemsFolder then return false end
            if isInsideTree(m) then return false end
            return true
        end

        if selectedSet[nm] then
            return true
        end

        if selectedSet["Mossy Coin"] and (nm == "Mossy Coin" or nm:match("^Mossy Coin%d+$")) then
            return true
        end

        if selectedSet["Cultist"] and m and m:IsA("Model") and l:find("cultist",1,true) and hasHumanoid(m) then
            return true
        end

        if selectedSet["Sapling"] and nm == "Sapling" then
            return true
        end

        if selectedSet["Alpha Wolf Pelt"] and l:find("alpha",1,true) and l:find("wolf",1,true) then
            return true
        end

        if selectedSet["Bear Pelt"] and l:find("bear",1,true) and not l:find("polar",1,true) then
            return true
        end

        if selectedSet["Wolf Pelt"] and nm == "Wolf Pelt" then
            return true
        end

        if selectedSet["Bunny Foot"] and nm == "Bunny Foot" then
            return true
        end

        if selectedSet["Polar Bear Pelt"] and nm == "Polar Bear Pelt" then
            return true
        end

        if selectedSet["Arctic Fox Pelt"] and nm == "Arctic Fox Pelt" then
            return true
        end

        if selectedSet["Spear"] and l:find("spear",1,true) and not hasHumanoid(m) then
            return true
        end

        if selectedSet["Sword"] and l:find("sword",1,true) and not hasHumanoid(m) then
            return true
        end

        if selectedSet["Crossbow"] and l:find("crossbow",1,true) and not l:find("cultist",1,true) and not hasHumanoid(m) then
            return true
        end

        if selectedSet["Blueprint"] and l:find("blueprint",1,true) then
            return true
        end

        if selectedSet["Flashlight"] and l:find("flashlight",1,true) and not hasHumanoid(m) then
            return true
        end

        if selectedSet["Cultist Gem"] and l:find("cultist",1,true) and l:find("gem",1,true) then
            return true
        end

        if selectedSet["Forest Gem"] and (l:find("forest gem",1,true) or (l:find("forest",1,true) and l:find("fragment",1,true))) then
            return true
        end

        if selectedSet["Tusk"] and l:find("tusk",1,true) then
            return true
        end

        return false
    end

    local function topModelUnderItems(part, itemsFolder)
        local cur = part
        local lastModel = nil
        while cur and cur ~= WS and cur ~= itemsFolder do
            if cur:IsA("Model") then lastModel = cur end
            cur = cur.Parent
        end
        if lastModel and lastModel.Parent == itemsFolder then
            return lastModel
        end
        return lastModel
    end

    local function nearestSelectedModelFromPart(part, selectedSet)
        if not part or not part:IsA("BasePart") then return nil end
        local itemsFolder = itemsRootOrNil()
        local m = topModelUnderItems(part, itemsFolder) or part:FindFirstAncestorOfClass("Model")
        if m and nameMatches(selectedSet, m) then return m end
        return nil
    end

    local function canPick(m, selectedSet, jobId)
        if not (m and m.Parent and m:IsA("Model")) then return false end
        local itemsFolder = itemsRootOrNil()
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then return false end
        if isExcludedModel(m) or isUnderLogWall(m) or hasIceBlockTag(m) then return false end

        local done = m:GetAttribute(DONE_ATTR)
        if CURRENT_MODE == "orbs" then
            if done ~= nil then
                return false
            end
        else
            if done and CURRENT_RUN_ID and tostring(done) == tostring(CURRENT_RUN_ID) then
                return false
            end
        end

        local tIn = m:GetAttribute(INFLT_ATTR)
        local jIn = m:GetAttribute(JOB_ATTR)
        if tIn and jIn and tostring(jIn) ~= tostring(jobId) and os.clock() - tIn < STUCK_TTL then
            return false
        end

        if not nameMatches(selectedSet, m) then
            return false
        end
        return true
    end

    local function currentSelectedSet()
        if CURRENT_MODE == "fuel" then
            return fuelModeSet
        elseif CURRENT_MODE == "scrap" then
            return scrapModeSet
        elseif CURRENT_MODE == "all" then
            return allModeSet
        end
        return nil
    end

    ----------------------------------------------------------------
    -- Orb-mode item mapping (Bring to Orbs)
    ----------------------------------------------------------------
    local CUSTOM_ORB_BASES = {
        Vector3.new(-27.85, 4.05 + ORB_HEIGHT, 50.82),
        Vector3.new( -6.68, 4.05 + ORB_HEIGHT, 47.66),
        Vector3.new( 14.50, 4.05 + ORB_HEIGHT, 44.50),
        Vector3.new( 35.67, 4.05 + ORB_HEIGHT, 41.33),
    }

    local orbItemSets = {
        {},
        {},
        {},
        {},
    }

    local orbUnionSet = {}

    local function recomputeOrbUnionSet()
        orbUnionSet = {}
        for i = 1, 4 do
            for name,_ in pairs(orbItemSets[i]) do
                orbUnionSet[name] = true
            end
        end
    end

    local function orbIndexForModel(m)
        for i = 1, 4 do
            local set = orbItemSets[i]
            if next(set) ~= nil and nameMatches(set, m) then
                return i
            end
        end
        return nil
    end

    ----------------------------------------------------------------
    -- Generic candidate collector
    ----------------------------------------------------------------
    local function collectCandidatesFromSet(selectedSet, jobId)
        if not selectedSet then return {} end
        local itemsFolder = itemsRootOrNil()
        if not itemsFolder then return {} end

        local uniq, out = {}, {}
        for _,d in ipairs(itemsFolder:GetDescendants()) do
            local m = nil
            if d:IsA("Model") then
                if nameMatches(selectedSet, d) then m = d end
            elseif d:IsA("BasePart") then
                m = nearestSelectedModelFromPart(d, selectedSet)
            end
            if m and not uniq[m] and canPick(m, selectedSet, jobId) then
                uniq[m] = true
                out[#out+1] = m
            end
        end
        return out
    end

    local function getCandidatesForCurrent(jobId)
        local selectedSet = currentSelectedSet()
        return collectCandidatesFromSet(selectedSet, jobId)
    end

    local function getCandidatesForOrbs(jobId)
        return collectCandidatesFromSet(orbUnionSet, jobId)
    end

    ----------------------------------------------------------------
    -- Orb + conveyor logic
    ----------------------------------------------------------------
    local function spawnOrbAt(pos, color)
        if orb then pcall(function() orb:Destroy() end) end
        local o = Instance.new("Part")
        o.Name = "tp_orb_fixed"
        o.Shape = Enum.PartType.Ball
        o.Size = Vector3.new(1.5,1.5,1.5)
        o.Material = Enum.Material.Neon
        o.Color = color or Color3.fromRGB(80,180,255)
        o.Anchored, o.CanCollide, o.CanTouch, o.CanQuery = true,false,false,false
        o.CFrame = CFrame.new(pos + Vector3.new(0, ORB_HEIGHT, 0))
        o.Parent = WS
        local l = Instance.new("PointLight")
        l.Range = 16
        l.Brightness = 2.5
        l.Parent = o
        orb = o
        orbPosVec = orb.Position
    end

    local function destroyOrb()
        if orb then pcall(function() orb:Destroy() end) end
        orb = nil
        orbPosVec = nil
    end

    local function hash01(s)
        local h = 131071
        for i = 1, #s do
            h = (h * 131 + string.byte(s, i)) % 1000003
        end
        return (h % 100000) / 100000
    end

    local function landingOffset(m, jobId)
        local key = (typeof(m.GetDebugId)=="function" and m:GetDebugId() or (m.Name or "")) .. tostring(jobId)
        local r1 = hash01(key .. "a")
        local r2 = hash01(key .. "b")
        local ang = r1 * math.pi * 2
        local rad = LAND_MIN + (LAND_MAX - LAND_MIN) * r2
        return Vector3.new(math.cos(ang)*rad, 0, math.sin(ang)*rad)
    end

    local function stageAtOrb(m, snap, tgt)
        setAnchored(m, true)
        for _,p in ipairs(allParts(m)) do
            p.CanCollide = false
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
        setPivot(m, CFrame.new(tgt))
        inflight[m].staged   = true
        inflight[m].stagedAt = os.clock()
        inflight[m].snap     = snap
        table.insert(releaseQueue, {model=m, pos=tgt})
    end

    local function releaseOne(rec)
        local m = rec and rec.model
        if not (m and m.Parent) then return end
        local info = inflight[m]
        local snap = info and info.snap or snapshotCollide(m)
        setAnchored(m, false)
        zeroAssembly(m)
        setCollideFromSnapshot(snap)
        for _,p in ipairs(allParts(m)) do
            p.AssemblyAngularVelocity = Vector3.new()
            p.AssemblyLinearVelocity  = Vector3.new()
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
        end
        pcall(function()
            m:SetAttribute(INFLT_ATTR, nil)
            m:SetAttribute(JOB_ATTR, nil)
            m:SetAttribute(DONE_ATTR, CURRENT_RUN_ID)
        end)
        inflight[m] = nil
    end

    local function startConveyor(m, jobId, destBaseVec)
        if not (running and m and m.Parent) then return end
        local mp = mainPart(m)
        if not mp then return end
        local off = landingOffset(m, jobId)
        local function target()
            local base = destBaseVec or orbPosVec or mp.Position
            return Vector3.new(base.X + off.X, base.Y + HOVER_ABOVE_ORB, base.Z + off.Z)
        end
        pcall(function() m:SetAttribute(INFLT_ATTR, os.clock()) end)
        pcall(function() m:SetAttribute(JOB_ATTR, jobId) end)
        local snap = setNoCollide(m)
        setAnchored(m, true)
        zeroAssembly(m)
        if startDrag then pcall(function() startDrag:FireServer(m) end) end
        local rec = { snap = snap, conn = nil, lastD = math.huge, lastT = os.clock(), staged = false }
        inflight[m] = rec

        rec.conn = Run.Heartbeat:Connect(function(dt)
            if not (running and m and m.Parent) then
                if rec.conn then rec.conn:Disconnect() end
                inflight[m] = nil
                return
            end
            if rec.staged then return end

            local pivot = m:IsA("Model") and m:GetPivot() or (mp and mp.CFrame)
            if not pivot then
                if rec.conn then rec.conn:Disconnect() end
                inflight[m] = nil
                return
            end

            local pos = pivot.Position
            local tgt = target()
            local flatDelta = Vector3.new(tgt.X - pos.X, 0, tgt.Z - pos.Z)
            local distH = flatDelta.Magnitude

            if distH <= ARRIVE_EPS_H and math.abs(tgt.Y - pos.Y) <= 1.0 then
                if stopDrag then pcall(function() stopDrag:FireServer(m) end) end
                stageAtOrb(m, snap, tgt)
                if rec.conn then rec.conn:Disconnect() end
                return
            end

            if distH >= rec.lastD - 0.02 then
                if os.clock() - rec.lastT >= STALL_SEC then
                    off = landingOffset(m, tostring(jobId) .. tostring(os.clock()))
                    rec.lastT = os.clock()
                end
            else
                rec.lastT = os.clock()
            end
            rec.lastD = distH

            local step = math.min(DRAG_SPEED * dt, math.max(0, distH))
            local dir  = distH > 1e-3 and (flatDelta / math.max(distH,1e-3)) or Vector3.new()
            local vy   = math.clamp((tgt.Y - pos.Y), -7, 7)
            local newPos = Vector3.new(pos.X, pos.Y + vy * dt * 10, pos.Z) + dir * step
            setPivot(m, CFrame.new(newPos, newPos + (dir.Magnitude>0 and dir or Vector3.new(0,0,1))))
        end)
    end

    local function flushStaleStaged()
        local now = os.clock()
        for m,info in pairs(inflight) do
            if info and info.staged and (now - (info.stagedAt or now)) >= STAGE_TIMEOUT_S then
                local queued = false
                for _,rec in ipairs(releaseQueue) do
                    if rec.model == m then
                        queued = true
                        break
                    end
                end
                if not queued then
                    table.insert(releaseQueue, {model=m, pos=mainPart(m) and mainPart(m).Position or orbPosVec})
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Unstick pass: force-drop anything stuck near orb
    ----------------------------------------------------------------
    do
        local acc = 0
        Run.Heartbeat:Connect(function(dt)
            if not (running and orbPosVec) then return end
            acc = acc + dt
            if acc < (1/ORB_UNSTICK_HZ) then return end
            acc = 0
            local items = itemsRootOrNil()
            if not items then return end

            local now = os.clock()
            for _,m in ipairs(items:GetChildren()) do
                if not m:IsA("Model") then continue end
                local mp = mainPart(m)
                if not mp then continue end
                if (mp.Position - orbPosVec).Magnitude <= ORB_UNSTICK_RAD then
                    local tIn  = m:GetAttribute(INFLT_ATTR)
                    local jIn  = m:GetAttribute(JOB_ATTR)
                    local info = inflight[m]
                    local age  = tIn and (now - tIn) or nil

                    local treatAsStuck = false

                    if not tIn or not jIn then
                        treatAsStuck = true
                    elseif not info then
                        treatAsStuck = true
                    elseif age and age >= STUCK_TTL then
                        treatAsStuck = true
                    end

                    if not treatAsStuck then
                        -- still in-flight and within TTL: leave it alone
                    else
                        inflight[m] = nil
                        pcall(function()
                            m:SetAttribute(INFLT_ATTR, nil)
                            m:SetAttribute(JOB_ATTR, nil)
                            m:SetAttribute(DONE_ATTR, CURRENT_RUN_ID)
                        end)
                        for _,p in ipairs(allParts(m)) do
                            p.Anchored = false
                            p.AssemblyAngularVelocity = Vector3.new()
                            p.AssemblyLinearVelocity  = Vector3.new()
                            p.CanCollide = true
                            pcall(function() p:SetNetworkOwner(nil) end)
                            pcall(function()
                                if p.SetNetworkOwnershipAuto then
                                    p:SetNetworkOwnershipAuto()
                                end
                            end)
                        end
                    end
                end
            end
        end)
    end

    ----------------------------------------------------------------
    -- Wave driver (mode-aware)
    ----------------------------------------------------------------
    local function wave()
        if not CURRENT_MODE then return end
        local jobId = tostring(os.clock())

        local list
        if CURRENT_MODE == "orbs" then
            list = getCandidatesForOrbs(jobId)
        else
            list = getCandidatesForCurrent(jobId)
        end

        for i = 1, #list do
            if not running then break end
            while running and activeCount >= MAX_CONCURRENT do
                Run.Heartbeat:Wait()
            end

            local m = list[i]
            if m and m.Parent and not inflight[m] then
                local destBaseVec = nil

                if CURRENT_MODE == "orbs" then
                    local idx = orbIndexForModel(m)
                    if idx and CUSTOM_ORB_BASES[idx] then
                        destBaseVec = CUSTOM_ORB_BASES[idx]
                    end
                else
                    destBaseVec = orbPosVec
                end

                if destBaseVec then
                    activeCount += 1
                    task.spawn(function()
                        startConveyor(m, jobId, destBaseVec)
                        task.delay(8, function()
                            activeCount = math.max(0, activeCount - 1)
                        end)
                    end)
                    task.wait(START_STAGGER)
                end
            end
        end
    end

    local function stopAll()
        running = false
        if hb then hb:Disconnect() hb = nil end

        for i = #releaseQueue, 1, -1 do
            local rec = releaseQueue[i]
            if rec and rec.model and rec.model.Parent then
                releaseOne(rec)
            end
            table.remove(releaseQueue, i)
        end

        for m,rec in pairs(inflight) do
            if rec and rec.conn then
                rec.conn:Disconnect()
            end
            if stopDrag then pcall(function() stopDrag:FireServer(m) end) end
            setAnchored(m, false)
            setCollideFromSnapshot(rec and rec.snap or snapshotCollide(m))
            zeroAssembly(m)
            inflight[m] = nil
        end

        activeCount = 0
        destroyOrb()
    end

    ----------------------------------------------------------------
    -- DESTINATION HELPERS
    ----------------------------------------------------------------
    local function campfireOrbPos()
        local fire = WS:FindFirstChild("Map")
                     and WS.Map:FindFirstChild("Campground")
                     and WS.Map.Campground:FindFirstChild("MainFire")
        if not fire then return nil end
        local mp = mainPart(fire)
        local cf = (mp and mp.CFrame) or fire:GetPivot()
        return cf.Position + Vector3.new(0, ORB_HEIGHT + 10, 0)
    end

    local function scrapperOrbPos()
        local scr = WS:FindFirstChild("Map")
                    and WS.Map:FindFirstChild("Campground")
                    and WS.Map.Campground:FindFirstChild("Scrapper")
        if not scr then return nil end
        local mp = mainPart(scr)
        local cf = (mp and mp.CFrame) or scr:GetPivot()
        return cf.Position + Vector3.new(0, ORB_HEIGHT + 10, 0)
    end

    local function noticeOrbPos()
        local map = WS:FindFirstChild("Map")
        if not map then return nil end
        local camp = map:FindFirstChild("Campground")
        if not camp then return nil end
        local board = camp:FindFirstChild("NoticeBoard")
        if not board then
            for _,d in ipairs(camp:GetDescendants()) do
                if d:IsA("Model") and d.Name == "NoticeBoard" then
                    board = d
                    break
                end
            end
        end
        if not board then return nil end

        local mp = mainPart(board)
        if not mp then
            local cf = board:GetPivot()
            return cf.Position + Vector3.new(0, ORB_HEIGHT + 4, 0)
        end
        local cf = mp.CFrame
        local forward = cf.LookVector
        local edgeOffset = (mp.Size.Z * 0.5) + 1.0
        local pos = cf.Position + forward * edgeOffset
        return pos + Vector3.new(0, ORB_HEIGHT + 1, 0)
    end

    ----------------------------------------------------------------
    -- MODE START/STOP
    ----------------------------------------------------------------
    local function startMode(mode)
        if mode == nil then
            CURRENT_MODE = nil
            stopAll()
            return
        end
        if not hrp() then return end

        if CURRENT_MODE == mode and running then
            return
        end

        stopAll()
        CURRENT_MODE = mode
        CURRENT_RUN_ID = tostring(os.clock())

        if mode == "fuel" or mode == "scrap" or mode == "all" then
            local pos, color

            if mode == "fuel" then
                pos   = campfireOrbPos()
                color = Color3.fromRGB(255,200,50)
            elseif mode == "scrap" then
                pos   = scrapperOrbPos()
                color = Color3.fromRGB(120,255,160)
            elseif mode == "all" then
                pos   = noticeOrbPos()
                color = Color3.fromRGB(100,200,255)
            end

            if not pos then
                CURRENT_MODE = nil
                return
            end

            spawnOrbAt(pos, color)
        elseif mode == "orbs" then
            local any = false
            for i = 1, 4 do
                if next(orbItemSets[i]) ~= nil then
                    any = true
                    break
                end
            end
            if not any then
                CURRENT_MODE = nil
                return
            end
            destroyOrb()
            orbPosVec = nil
        else
            CURRENT_MODE = nil
            return
        end

        running = true
        releaseQueue = {}
        releaseAcc   = 0

        if hb then hb:Disconnect() end
        hb = Run.Heartbeat:Connect(function(dt)
            if not running then return end
            wave()
            releaseAcc = releaseAcc + dt
            local interval = 1 / RELEASE_RATE_HZ
            local toRelease = math.min(MAX_RELEASE_PER_TICK, math.floor(releaseAcc / interval))
            if toRelease > 0 then
                releaseAcc = releaseAcc - toRelease * interval
                for i = 1, toRelease do
                    local rec = table.remove(releaseQueue, 1)
                    if not rec then break end
                    releaseOne(rec)
                end
            end
            flushStaleStaged()
            task.wait(STEP_WAIT)
        end)
    end

    ----------------------------------------------------------------
    -- UI TOGGLES
    ----------------------------------------------------------------
    tab:Toggle({
        Title = "Send Fuel to Campfire",
        Value = false,
        Callback = function(state)
            if state then
                startMode("fuel")
            else
                if CURRENT_MODE == "fuel" then
                    startMode(nil)
                end
            end
        end
    })

    tab:Toggle({
        Title = "Send Scrap to Scrapper",
        Value = false,
        Callback = function(state)
            if state then
                startMode("scrap")
            else
                if CURRENT_MODE == "scrap" then
                    startMode(nil)
                end
            end
        end
    })

    tab:Toggle({
        Title = "Send All Items to NoticeBoard",
        Value = false,
        Callback = function(state)
            if state then
                startMode("all")
            else
                if CURRENT_MODE == "all" then
                    startMode(nil)
                end
            end
        end
    })

    ----------------------------------------------------------------
    -- UI: Bring to Orbs (Level 4 Fire Edge)
    ----------------------------------------------------------------
    tab:Section({ Title = "Bring to Orbs (Level 4 Fire Edge)" })

    local function makeOrbDropdown(index)
        return tab:Dropdown({
            Title = ("Orb %d Items"):format(index),
            Values = allItemNames,
            Multi = true,
            AllowNone = true,
            Callback = function(selection)
                local set = {}
                if type(selection) == "table" then
                    for _,name in ipairs(selection) do
                        if name then
                            set[tostring(name)] = true
                        end
                    end
                elseif selection then
                    set[tostring(selection)] = true
                end
                orbItemSets[index] = set
                recomputeOrbUnionSet()
            end
        })
    end

    makeOrbDropdown(1)
    makeOrbDropdown(2)
    makeOrbDropdown(3)
    makeOrbDropdown(4)

    tab:Toggle({
        Title = "Bring Selected Items to Orbs",
        Value = false,
        Callback = function(state)
            if state then
                startMode("orbs")
            else
                if CURRENT_MODE == "orbs" then
                    startMode(nil)
                end
            end
        end
    })

    ----------------------------------------------------------------
    -- Respawn handling
    ----------------------------------------------------------------
    Players.LocalPlayer.CharacterAdded:Connect(function()
        if running and CURRENT_MODE then
            if CURRENT_MODE == "fuel" or CURRENT_MODE == "scrap" or CURRENT_MODE == "all" then
                local pos
                if CURRENT_MODE == "fuel" then
                    pos = campfireOrbPos()
                elseif CURRENT_MODE == "scrap" then
                    pos = scrapperOrbPos()
                elseif CURRENT_MODE == "all" then
                    pos = noticeOrbPos()
                end
                if pos then
                    local color = (CURRENT_MODE == "fuel" and Color3.fromRGB(255,200,50))
                                  or (CURRENT_MODE == "scrap" and Color3.fromRGB(120,255,160))
                                  or Color3.fromRGB(100,200,255)
                    spawnOrbAt(pos, color)
                end
            elseif CURRENT_MODE == "orbs" then
                destroyOrb()
                orbPosVec = nil
            end
        end
    end)
end
