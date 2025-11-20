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
            if d:IsA("BasePart") then
                t[#t+1] = d
            end
        end
        return t
    end

    local function setPivot(m, cf)
        if m:IsA("Model") then
            m:PivotTo(cf)
        else
            local p = mainPart(m)
            if p then
                p.CFrame = cf
            end
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
        for _,p in ipairs(allParts(m)) do
            s[p] = p.CanCollide
        end
        return s
    end

    local function setCollideFromSnapshot(snap)
        for part,can in pairs(snap or {}) do
            if part and part.Parent then
                part.CanCollide = can
            end
        end
    end

    local function setAnchored(m, on)
        for _,p in ipairs(allParts(m)) do
            p.Anchored = on
        end
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
    -- EdgeButtons container
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
    local DRAG_SPEED              = 220
    local ORB_HEIGHT              = 10
    local GROUND_ORB_DROP_HEIGHT  = 6
    local MAX_CONCURRENT          = 40
    local START_STAGGER           = 0.01
    local STEP_WAIT               = 0.016

    local LAND_MIN                = 0.35
    local LAND_MAX                = 0.85
    local ARRIVE_EPS_H            = 0.9
    local STALL_SEC               = 0.6

    local HOVER_ABOVE_ORB         = 1.2
    local RELEASE_RATE_HZ         = 16
    local MAX_RELEASE_PER_TICK    = 8

    local STAGE_TIMEOUT_S         = 1.5
    local ORB_UNSTICK_RAD         = 2.0
    local ORB_UNSTICK_HZ          = 10
    local STUCK_TTL               = 6.0

    -- Periodic catch-up: every 3 minutes pause waves for 20s and clean floaters
    local RESYNC_INTERVAL             = 180   -- seconds of normal running
    local RESYNC_DURATION             = 20    -- seconds of catch-up window
    local RESYNC_MAX_RELEASE_PER_TICK = 2     -- very gentle release during catch-up

    local INFLT_ATTR = "OrbInFlightAt"
    local JOB_ATTR   = "OrbJob"
    local DONE_ATTR  = "OrbDelivered"

    local CURRENT_RUN_ID   = nil
    local CURRENT_MODE     = nil  -- "fuel" | "scrap" | "all" | "orbs" | nil

    local running      = false
    local hb           = nil

    -- Main orb (over campfire/scrapper/notice)
    local orb, orbPosVec = nil, nil

    -- Stage orb (10 studs away, staging point)
    local orbStage, orbStagePosVec = nil, nil

    local inflight     = {}
    local releaseQueue = {}
    local releaseAcc   = 0.0
    local activeCount  = 0
    local unstickConn  = nil
    local preclaimConn = nil
    local waveAcc      = 0.0

    local resyncTimer     = 0
    local inResync        = false
    local resyncRemaining = 0

    -- Only one item at a time may travel from stage orb -> main orb
    local stageBusy       = false

    ----------------------------------------------------------------
    -- ITEM DEFINITIONS
    ----------------------------------------------------------------
    local junkItems = {
        "Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine",
        "UFO Junk","UFO Component"
    }
    local fuelItems = {"Log","Coal","Fuel Canister","Oil Barrel"}
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
    scrapAlso["Log"] = true;

    local fuelModeSet = { ["Coal"] = true, ["Fuel Canister"] = true, ["Oil Barrel"] = true }
    local scrapModeSet = {}
    for k,v in pairs(junkSet)   do if v then scrapModeSet[k] = true end end
    for k,v in pairs(scrapAlso) do if v then scrapModeSet[k] = true end end

    local allModeSet = {}
    local function addListToSet(list, set)
        for _,n in ipairs(list) do
            set[n] = true
        end
    end
    local function addSetToSet(src, dst)
        for k,v in pairs(src) do
            if v then
                dst[k] = true
            end
        end
    end
    addSetToSet(junkSet, allModeSet)
    addSetToSet(fuelSet, allModeSet)
    addListToSet(foodItems, allModeSet)
    addListToSet(medicalItems, allModeSet)
    addListToSet(weaponsArmor, allModeSet)
    addListToSet(ammoMisc, allModeSet)
    addListToSet(pelts, allModeSet)

    local preDragImportantSet = {}
    addListToSet(weaponsArmor, preDragImportantSet)

    addListToSet({
        "Giant Sack","Good Sack",
        "Blueprint","Forest Gem","Key","Flashlight","Strong Flashlight","Taming flute","Cultist Gem","Tusk","Infernal Sack"
    }, preDragImportantSet)

    local alwaysGrabNames = {}
    for name,_ in pairs(preDragImportantSet) do
        alwaysGrabNames[#alwaysGrabNames+1] = name
    end
    table.sort(alwaysGrabNames)

    local groupedItemValues = {}
    local function appendListIntoGrouped(list)
        for _,name in ipairs(list) do
            if allModeSet[name] then
                groupedItemValues[#groupedItemValues+1] = name
            end
        end
    end
    appendListIntoGrouped(junkItems)
    appendListIntoGrouped(fuelItems)
    appendListIntoGrouped(foodItems)
    appendListIntoGrouped(medicalItems)
    appendListIntoGrouped(weaponsArmor)
    appendListIntoGrouped(ammoMisc)
    appendListIntoGrouped(pelts)

    local function cloneArray(src)
        local t = {}
        for i,v in ipairs(src) do
            t[i] = v
        end
        return t
    end

    ----------------------------------------------------------------
    -- Shared item helpers
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
        if selectedSet["Strong Flashlight"] and l:find("flashlight",1,true) and not hasHumanoid(m) then
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

    local function isPreDragImportantModel(m)
        return nameMatches(preDragImportantSet, m)
    end

    local function topModelUnderItems(part, itemsFolder)
        local cur = part
        local lastModel = nil
        while cur and cur ~= WS and cur ~= itemsFolder do
            if cur:IsA("Model") then
                lastModel = cur
            end
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
        if m and nameMatches(selectedSet, m) then
            return m
        end
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

    private_selectedSet = nil

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
        Vector3.new(-27.85, 4.05 + GROUND_ORB_DROP_HEIGHT, 50.82),
        Vector3.new( -6.68, 4.05 + GROUND_ORB_DROP_HEIGHT, 47.66),
        Vector3.new( 14.50, 4.05 + GROUND_ORB_DROP_HEIGHT, 44.50),
        Vector3.new( 35.67, 4.05 + GROUND_ORB_DROP_HEIGHT, 41.33),
    }

    local orbItemSets = {
        {},
        {},
        {},
        {},
    }

    local orbEnabled = { true, true, true, true }

    local orbUnionSet = {}

    local function recomputeOrbUnionSet()
        orbUnionSet = {}
        for i = 1, 4 do
            if orbEnabled[i] then
                for name,_ in pairs(orbItemSets[i]) do
                    orbUnionSet[name] = true
                end
            end
        end
    end

    local function orbIndexForModel(m)
        for i = 1, 4 do
            local set = orbItemSets[i]
            if orbEnabled[i] and next(set) ~= nil and nameMatches(set, m) then
                return i
            end
        end
        return nil
    end

    local orbDropdownValues = {
        cloneArray(groupedItemValues),
        cloneArray(groupedItemValues),
        cloneArray(groupedItemValues),
        cloneArray(groupedItemValues),
    }

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
                if nameMatches(selectedSet, d) then
                    m = d
                end
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
    local function destroyOrb()
        if orb then
            pcall(function() orb:Destroy() end)
        end
        if orbStage then
            pcall(function() orbStage:Destroy() end)
        end
        orb = nil
        orbPosVec = nil
        orbStage = nil
        orbStagePosVec = nil
    end

    local function spawnOrbAt(mainPos, color, stagePos)
        destroyOrb()

        -- main orb (over campfire/scrapper/notice)
        local mainWorld = mainPos + Vector3.new(0, ORB_HEIGHT, 0)
        local o = Instance.new("Part")
        o.Name = "tp_orb_fixed_main"
        o.Shape = Enum.PartType.Ball
        o.Size = Vector3.new(1.5,1.5,1.5)
        o.Material = Enum.Material.Neon
        o.Color = color or Color3.fromRGB(80,180,255)
        o.Anchored, o.CanCollide, o.CanTouch, o.CanQuery = true,false,false,false
        o.CFrame = CFrame.new(mainWorld)
        o.Parent = WS
        local l = Instance.new("PointLight")
        l.Range = 16
        l.Brightness = 2.5
        l.Parent = o
        orb = o
        orbPosVec = o.Position

        -- stage orb (10 studs away), if requested
        if stagePos then
            local stageWorld = stagePos + Vector3.new(0, ORB_HEIGHT, 0)
            local s = Instance.new("Part")
            s.Name = "tp_orb_fixed_stage"
            s.Shape = Enum.PartType.Ball
            s.Size = Vector3.new(1.5,1.5,1.5)
            s.Material = Enum.Material.Neon
            s.Color = Color3.fromRGB(255,255,255)
            s.Anchored, s.CanCollide, s.CanTouch, s.CanQuery = true,false,false,false
            s.CFrame = CFrame.new(stageWorld)
            s.Parent = WS
            local l2 = Instance.new("PointLight")
            l2.Range = 12
            l2.Brightness = 1.5
            l2.Parent = s
            orbStage = s
            orbStagePosVec = s.Position
        end
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

    local function stageAtOrb(m, snap, tgt, phase)
        local info = inflight[m]
        if not info then
            info = {}
            inflight[m] = info
        end

        setAnchored(m, true)
        for _,p in ipairs(allParts(m)) do
            p.CanCollide = false
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
        setPivot(m, CFrame.new(tgt))

        info.staged      = true
        info.stagedAt    = os.clock()
        info.snap        = snap
        info.stagePhase  = phase or "final"

        -- arriving at the main orb in final phase frees the "stageBusy" gate
        if (CURRENT_MODE == "fuel" or CURRENT_MODE == "scrap" or CURRENT_MODE == "all") and orbStagePosVec and info.stagePhase == "final" then
            stageBusy = false
        end

        table.insert(releaseQueue, {model=m, pos=tgt, phase=info.stagePhase})
    end

    function campfireOrbPos()
        local fire = WS:FindFirstChild("Map")
                     and WS.Map:FindFirstChild("Campground")
                     and WS.Map.Campground:FindFirstChild("MainFire")
        if not fire then return nil end
        local mp = mainPart(fire)
        local cf = (mp and mp.CFrame) or fire:GetPivot()
        return cf.Position + Vector3.new(0, ORB_HEIGHT + 10, 0)
    end

    local function releaseOne(rec)
        local m = rec and rec.model
        if not (m and m.Parent) then return end
        local info  = inflight[m]
        local phase = info and info.stagePhase or rec.phase or "final"

        -- Stage -> Main orb hop (one item at a time)
        if (CURRENT_MODE == "fuel" or CURRENT_MODE == "scrap" or CURRENT_MODE == "all")
            and orbStagePosVec and orbPosVec
            and phase == "stage"
        then
            -- if another item is already doing stage->main, requeue this one
            if stageBusy then
                table.insert(releaseQueue, rec)
                return
            end

            stageBusy = true

            if info then
                info.staged   = false
                info.stagedAt = nil
            end

            local job2 = tostring(os.clock())
            pcall(function() m:SetAttribute(INFLT_ATTR, os.clock()) end)
            pcall(function() m:SetAttribute(JOB_ATTR, job2) end)

            -- second leg goes from stage area to main orb (final phase)
            local snap = info and info.snap or snapshotCollide(m)
            -- let startConveyor own the new inflight record
            inflight[m] = nil
            -- second leg (final)
            local _ = startDrag -- just to keep intent clear
            local function safeStart()
                -- use orbPosVec as base for final landing
                local destBaseVec = orbPosVec
                if destBaseVec then
                    -- start second conveyor with "final" phase
                    -- this will call stageAtOrb again and then we genuinely drop
                    startConveyor(m, job2, destBaseVec, "final")
                else
                    -- fallback: if no main orb, just drop now
                    local snap2 = snap or snapshotCollide(m)
                    setAnchored(m, false)
                    zeroAssembly(m)
                    setCollideFromSnapshot(snap2)
                    for _,p in ipairs(allParts(m)) do
                        p.AssemblyAngularVelocity = Vector3.new()
                        p.AssemblyLinearVelocity  = Vector3.new()
                        pcall(function() p:SetNetworkOwner(nil) end)
                        pcall(function()
                            if p.SetNetworkOwnershipAuto then
                                p:SetNetworkOwnershipAuto()
                            end
                        end)
                    end
                    pcall(function()
                        m:SetAttribute(INFLT_ATTR, nil)
                        m:SetAttribute(JOB_ATTR, nil)
                        m:SetAttribute(DONE_ATTR, CURRENT_RUN_ID)
                    end)
                    inflight[m] = nil
                    stageBusy = false
                end
            end
            safeStart()
            return
        end

        -- Final drop from main orb (or generic drop)
        local snap = (info and info.snap) or snapshotCollide(m)
        setAnchored(m, false)
        zeroAssembly(m)
        setCollideFromSnapshot(snap)
        for _,p in ipairs(allParts(m)) do
            p.AssemblyAngularVelocity = Vector3.new()
            p.AssemblyLinearVelocity  = Vector3.new()
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function()
                if p.SetNetworkOwnershipAuto then
                    p:SetNetworkOwnershipAuto()
                end
            end)
        end

        local mp2 = mainPart(m)
        if mp2 and stopDrag and isPreDragImportantModel(m) then
            local campPos = campfireOrbPos()
            if campPos and (mp2.Position - campPos).Magnitude <= 30 then
                pcall(function()
                    stopDrag:FireServer(m)
                end)
            end
        end

        pcall(function()
            m:SetAttribute(INFLT_ATTR, nil)
            m:SetAttribute(JOB_ATTR, nil)
            m:SetAttribute(DONE_ATTR, CURRENT_RUN_ID)
        end)
        inflight[m] = nil
    end

    -- startConveyor now takes a "phase" for stage vs final
    local function startConveyor(m, jobId, destBaseVec, phase)
        if not (running and m and m.Parent) then return end
        local mp = mainPart(m)
        if not mp then return end

        local off  = landingOffset(m, jobId)
        local base = destBaseVec or orbPosVec or mp.Position

        if CURRENT_MODE == "orbs" then
            local tgt = Vector3.new(base.X + off.X, base.Y + HOVER_ABOVE_ORB, base.Z + off.Z)

            pcall(function() m:SetAttribute(INFLT_ATTR, os.clock()) end)
            pcall(function() m:SetAttribute(JOB_ATTR, jobId) end)

            local snap = setNoCollide(m)
            setAnchored(m, true)
            zeroAssembly(m)

            if startDrag then
                pcall(function()
                    startDrag:FireServer(m)
                end)
            end

            local rec = { snap = snap, conn = nil, lastD = 0, lastT = os.clock(), staged = false, stagePhase = "final" }
            inflight[m] = rec

            stageAtOrb(m, snap, tgt, "final")

            if stopDrag then
                pcall(function()
                    stopDrag:FireServer(m)
                end)
            end

            return
        end

        local function target()
            local baseNow = destBaseVec or orbPosVec or mp.Position
            return Vector3.new(baseNow.X + off.X, baseNow.Y + HOVER_ABOVE_ORB, baseNow.Z + off.Z)
        end
        pcall(function() m:SetAttribute(INFLT_ATTR, os.clock()) end)
        pcall(function() m:SetAttribute(JOB_ATTR, jobId) end)
        local snap = setNoCollide(m)
        setAnchored(m, true)
        zeroAssembly(m)
        if startDrag then
            pcall(function() startDrag:FireServer(m) end)
        end
        local rec = { snap = snap, conn = nil, lastD = math.huge, lastT = os.clock(), staged = false, stagePhase = phase or "final" }
        inflight[m] = rec

        rec.conn = Run.Heartbeat:Connect(function(dt)
            if not (running and m and m.Parent) then
                if rec.conn then
                    rec.conn:Disconnect()
                end
                inflight[m] = nil
                return
            end
            if rec.staged then return end

            local pivot = m:IsA("Model") and m:GetPivot() or (mp and mp.CFrame)
            if not pivot then
                if rec.conn then
                    rec.conn:Disconnect()
                end
                inflight[m] = nil
                return
            end

            local pos = pivot.Position
            local tgt = target()
            local flatDelta = Vector3.new(tgt.X - pos.X, 0, tgt.Z - pos.Z)
            local distH = flatDelta.Magnitude

            if distH <= ARRIVE_EPS_H and math.abs(tgt.Y - pos.Y) <= 1.0 then
                if stopDrag then
                    pcall(function() stopDrag:FireServer(m) end)
                end
                stageAtOrb(m, snap, tgt, rec.stagePhase or phase or "final")
                if rec.conn then
                    rec.conn:Disconnect()
                end
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
                    table.insert(releaseQueue, {
                        model = m,
                        pos   = mainPart(m) and mainPart(m).Position or orbPosVec,
                        phase = info.stagePhase or "final"
                    })
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Aggressive float-fix during periodic resync
    ----------------------------------------------------------------
    local function resyncFloaters()
        local itemsFolder = itemsRootOrNil()
        if not itemsFolder then return end

        local centers = {}
        if CURRENT_MODE == "orbs" then
            for i = 1, 4 do
                if orbEnabled[i] and CUSTOM_ORB_BASES[i] then
                    centers[#centers+1] = CUSTOM_ORB_BASES[i]
                end
            end
        else
            if orbPosVec then
                centers[#centers+1] = orbPosVec
            end
            if orbStagePosVec then
                centers[#centers+1] = orbStagePosVec
            end
        end
        if #centers == 0 then return end

        local ORB_RESYNC_RAD = ORB_UNSTICK_RAD * 2

        local function nearAnyCenter(pos)
            for _,c in ipairs(centers) do
                if (pos - c).Magnitude <= ORB_RESYNC_RAD then
                    return true
                end
            end
            return false
        end

        local seen = {}
        for _,m in ipairs(itemsFolder:GetChildren()) do
            if m:IsA("Model") and not seen[m] then
                local mp = mainPart(m)
                if mp and nearAnyCenter(mp.Position) then
                    seen[m] = true
                    local parts = allParts(m)
                    local looksStuck = false
                    for _,p in ipairs(parts) do
                        if p.Anchored or not p.CanCollide then
                            looksStuck = true
                            break
                        end
                    end
                    if not looksStuck then
                        if inflight[m] or m:GetAttribute(INFLT_ATTR) or m:GetAttribute(JOB_ATTR) then
                            looksStuck = true
                        end
                    end
                    if looksStuck then
                        local alreadyQueued = false
                        for _,rec in ipairs(releaseQueue) do
                            if rec.model == m then
                                alreadyQueued = true
                                break
                            end
                        end
                        if not alreadyQueued then
                            table.insert(releaseQueue, {
                                model = m,
                                pos   = mp.Position,
                                phase = (inflight[m] and inflight[m].stagePhase) or "final"
                            })
                        end
                    end
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Unstick pass using raycasts from player position
    ----------------------------------------------------------------
    local function setUnstickEnabled(on)
        if on then
            if unstickConn then return end
            local acc = 0
            unstickConn = Run.Heartbeat:Connect(function(dt)
                if not (running and orbPosVec) then return end
                acc = acc + dt
                if acc < (1 / ORB_UNSTICK_HZ) then return end
                acc = 0

                local itemsFolder = itemsRootOrNil()
                if not itemsFolder then return end

                local ch = lp.Character
                local root = ch and ch:FindFirstChild("HumanoidRootPart")
                if not root then return end

                local originBase = root.Position + Vector3.new(0, 5, 0)
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Whitelist
                rp.FilterDescendantsInstances = {itemsFolder}
                rp.IgnoreWater = true

                local directions = {
                    Vector3.new(1,0,0),
                    Vector3.new(-1,0,0),
                    Vector3.new(0,0,1),
                    Vector3.new(0,0,-1),
                    Vector3.new(1,0,1).Unit,
                    Vector3.new(-1,0,1).Unit,
                    Vector3.new(1,0,-1).Unit,
                    Vector3.new(-1,0,-1).Unit,
                }
                local RAY_DISTANCE = 200

                local seen = {}
                local now  = os.clock()

                local function handleHit(result)
                    if not result then return end
                    local inst = result.Instance
                    if not inst then return end

                    local m = inst:FindFirstAncestorOfClass("Model")
                    if not m or seen[m] then return end
                    seen[m] = true

                    local mp = mainPart(m)
                    if not mp then return end
                    if (mp.Position - orbPosVec).Magnitude > ORB_UNSTICK_RAD then
                        return
                    end

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

                    if not treatAsStuck then return end

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

                for _,dir in ipairs(directions) do
                    local result = WS:Raycast(originBase, dir * RAY_DISTANCE, rp)
                    if result then
                        handleHit(result)
                    end
                end
            end)
        else
            if unstickConn then
                unstickConn:Disconnect()
                unstickConn = nil
            end
        end
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

            local m = list[i]
            if m and m.Parent and not inflight[m] then
                if CURRENT_MODE == "orbs" and activeCount >= MAX_CONCURRENT then
                    if startDrag then
                        pcall(function()
                            startDrag:FireServer(m)
                        end)
                    end
                else
                    while running and activeCount >= MAX_CONCURRENT do
                        Run.Heartbeat:Wait()
                    end

                    local destBaseVec, phase = nil, "final"

                    if CURRENT_MODE == "orbs" then
                        local idx = orbIndexForModel(m)
                        if idx and CUSTOM_ORB_BASES[idx] then
                            destBaseVec = CUSTOM_ORB_BASES[idx]
                        end
                    else
                        -- fuel/scrap/all: first leg goes to stage orb if present
                        if CURRENT_MODE == "fuel" or CURRENT_MODE == "scrap" or CURRENT_MODE == "all" then
                            if orbStagePosVec then
                                destBaseVec = orbStagePosVec
                                phase       = "stage"
                            else
                                destBaseVec = orbPosVec
                                phase       = "final"
                            end
                        else
                            destBaseVec = orbPosVec
                            phase       = "final"
                        end
                    end

                    if destBaseVec then
                        activeCount = activeCount + 1
                        task.spawn(function()
                            startConveyor(m, jobId, destBaseVec, phase)
                            task.delay(8, function()
                                activeCount = math.max(0, activeCount - 1)
                            end)
                        end)
                        task.wait(START_STAGGER)
                    end
                end
            end
        end
    end

    local function stopAll()
        running = false
        if hb then
            hb:Disconnect()
            hb = nil
        end

        setUnstickEnabled(false)

        resyncTimer     = 0
        inResync        = false
        resyncRemaining = 0
        stageBusy       = false

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
            if stopDrag then
                pcall(function() stopDrag:FireServer(m) end)
            end
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

    -- Stage orb positions (10 studs away from main)
    local function computeCampfireStagePos(campPos)
        local scrPos = scrapperOrbPos()
        if scrPos then
            local dir = scrPos - campPos
            local flat = Vector3.new(dir.X, 0, dir.Z)
            if flat.Magnitude > 1e-3 then
                local away = -flat.Unit
                return campPos + away * 10
            end
        end
        return campPos + Vector3.new(10, 0, 0)
    end

    local function computeScrapperStagePos(scrPos)
        local campPos = campfireOrbPos()
        if campPos then
            local dir = campPos - scrPos
            local flat = Vector3.new(dir.X, 0, dir.Z)
            if flat.Magnitude > 1e-3 then
                local away = -flat.Unit
                return scrPos + away * 10
            end
        end
        return scrPos + Vector3.new(10, 0, 0)
    end

    local function computeNoticeStagePos(noticePos)
        -- Simple sideways offset; doesn't need to be perfect
        return noticePos + Vector3.new(10, 0, 0)
    end

    ----------------------------------------------------------------
    -- Background pre-drag for rare / important items
    ----------------------------------------------------------------
    local PRECLAIM_DISTANCE    = 100
    local PRECLAIM_INTERVAL_S  = 2.5
    local preclaimAcc          = 0
    local preclaimEnabled      = false

    local function setPreclaimEnabled(state)
        preclaimEnabled = state and true or false
        if preclaimEnabled then
            if preclaimConn then return end
            preclaimAcc = 0
            preclaimConn = Run.Heartbeat:Connect(function(dt)
                preclaimAcc = preclaimAcc + dt
                if preclaimAcc < PRECLAIM_INTERVAL_S then return end
                preclaimAcc = 0

                if not preclaimEnabled then return end
                if not startDrag then return end

                local itemsFolder = itemsRootOrNil()
                if not itemsFolder then return end
                local campPos = campfireOrbPos()
                if not campPos then return end

                local ch = lp.Character
                local root = ch and ch:FindFirstChild("HumanoidRootPart")
                if not root then return end

                local originBase = root.Position + Vector3.new(0, 5, 0)
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Whitelist
                rp.FilterDescendantsInstances = {itemsFolder}
                rp.IgnoreWater = true

                local directions = {
                    Vector3.new(1,0,0),
                    Vector3.new(-1,0,0),
                    Vector3.new(0,0,1),
                    Vector3.new(0,0,-1),
                    Vector3.new(1,0,1).Unit,
                    Vector3.new(-1,0,1).Unit,
                    Vector3.new(1,0,-1).Unit,
                    Vector3.new(-1,0,-1).Unit,
                }
                local RAY_DISTANCE = 200

                local seen = {}

                local function handleHit(result)
                    if not result then return end
                    local inst = result.Instance
                    if not inst then return end

                    local m = inst:FindFirstAncestorOfClass("Model")
                    if not m or seen[m] then return end
                    seen[m] = true

                    if not m.Parent then return end
                    if isExcludedModel(m) or hasIceBlockTag(m) then return end
                    if not isPreDragImportantModel(m) then return end

                    local mp = mainPart(m)
                    if not mp then return end
                    if (mp.Position - campPos).Magnitude <= PRECLAIM_DISTANCE then
                        return
                    end

                    pcall(function()
                        startDrag:FireServer(m)
                    end)
                end

                for _,dir in ipairs(directions) do
                    local result = WS:Raycast(originBase, dir * RAY_DISTANCE, rp)
                    if result then
                        handleHit(result)
                    end
                end
            end)
        else
            if preclaimConn then
                preclaimConn:Disconnect()
                preclaimConn = nil
            end
        end
    end

    ----------------------------------------------------------------
    -- MODE START/STOP
    ----------------------------------------------------------------
    local function startMode(mode)
        if mode == nil then
            CURRENT_MODE = nil
            setPreclaimEnabled(false)
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
            local pos, color, stagePos

            if mode == "fuel" then
                pos   = campfireOrbPos()
                color = Color3.fromRGB(255,200,50)
                if pos then
                    stagePos = computeCampfireStagePos(pos)
                end
            elseif mode == "scrap" then
                pos   = scrapperOrbPos()
                color = Color3.fromRGB(120,255,160)
                if pos then
                    stagePos = computeScrapperStagePos(pos)
                end
            elseif mode == "all" then
                pos   = noticeOrbPos()
                color = Color3.fromRGB(100,200,255)
                if pos then
                    stagePos = computeNoticeStagePos(pos)
                end
            end

            if not pos then
                CURRENT_MODE = nil
                return
            end

            spawnOrbAt(pos, color, stagePos)
        elseif mode == "orbs" then
            local any = false
            for i = 1, 4 do
                if orbEnabled[i] and next(orbItemSets[i]) ~= nil then
                    any = true
                    break
                end
            end
            if not any then
                CURRENT_MODE = nil
                return
            end
            destroyOrb()
            orbPosVec      = nil
            orbStagePosVec = nil
        else
            CURRENT_MODE = nil
            return
        end

        running          = true
        releaseQueue     = {}
        releaseAcc       = 0
        waveAcc          = 0
        resyncTimer      = 0
        inResync         = false
        resyncRemaining  = 0
        stageBusy        = false

        if hb then
            hb:Disconnect()
            hb = nil
        end

        if mode == "fuel" or mode == "scrap" or mode == "all" then
            setUnstickEnabled(true)
        else
            setUnstickEnabled(false)
        end

        hb = Run.Heartbeat:Connect(function(dt)
            if not running then return end

            -- periodic catch-up window scheduler (every 3 minutes for 20s)
            resyncTimer = resyncTimer + dt
            if not inResync and resyncTimer >= RESYNC_INTERVAL then
                inResync        = true
                resyncRemaining = RESYNC_DURATION
                resyncTimer     = 0
            end
            if inResync then
                resyncRemaining = resyncRemaining - dt
                if resyncRemaining <= 0 then
                    inResync        = false
                    resyncRemaining = 0
                end
            end

            -- main wave driver (paused during resync to let physics catch up)
            if not inResync then
                waveAcc = waveAcc + dt
                if waveAcc >= STEP_WAIT then
                    waveAcc = waveAcc - STEP_WAIT
                    wave()
                end
            else
                -- during catch-up, aggressively de-stick floaters near orb(s)
                resyncFloaters()
            end

            -- controlled release of staged items
            releaseAcc = releaseAcc + dt
            local interval   = 1 / RELEASE_RATE_HZ
            local maxPerTick = inResync and RESYNC_MAX_RELEASE_PER_TICK or MAX_RELEASE_PER_TICK
            local toRelease  = math.min(maxPerTick, math.floor(releaseAcc / interval))
            if toRelease > 0 then
                releaseAcc = releaseAcc - toRelease * interval
                for i = 1, toRelease do
                    local rec = table.remove(releaseQueue, 1)
                    if not rec then break end
                    releaseOne(rec)
                end
            end

            flushStaleStaged()
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

    tab:Section({ Title = "Bring to Orbs (Level 4 Fire Edge)" })

    local function makeOrbDropdown(index)
        return tab:Dropdown({
            Title = ("Orb %d Items"):format(index),
            Values = orbDropdownValues[index],
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
        Title = "Orb 1 Enabled",
        Value = true,
        Callback = function(state)
            orbEnabled[1] = state and true or false
            recomputeOrbUnionSet()
        end
    })

    tab:Toggle({
        Title = "Orb 2 Enabled",
        Value = true,
        Callback = function(state)
            orbEnabled[2] = state and true or false
            recomputeOrbUnionSet()
        end
    })

    tab:Toggle({
        Title = "Orb 3 Enabled",
        Value = true,
        Callback = function(state)
            orbEnabled[3] = state and true or false
            recomputeOrbUnionSet()
        end
    })

    tab:Toggle({
        Title = "Orb 4 Enabled",
        Value = true,
        Callback = function(state)
            orbEnabled[4] = state and true or false
            recomputeOrbUnionSet()
        end
    })

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

    tab:Section({ Title = "Background Utilities" })

    tab:Toggle({
        Title = "Background Grab Important Items",
        Value = false,
        Callback = function(state)
            setPreclaimEnabled(state)
        end
    })

    ----------------------------------------------------------------
    -- Respawn handling
    ----------------------------------------------------------------
    Players.LocalPlayer.CharacterAdded:Connect(function()
        if running and CURRENT_MODE then
            if CURRENT_MODE == "fuel" or CURRENT_MODE == "scrap" or CURRENT_MODE == "all" then
                local pos, color, stagePos
                if CURRENT_MODE == "fuel" then
                    pos   = campfireOrbPos()
                    color = Color3.fromRGB(255,200,50)
                    if pos then
                        stagePos = computeCampfireStagePos(pos)
                    end
                elseif CURRENT_MODE == "scrap" then
                    pos   = scrapperOrbPos()
                    color = Color3.fromRGB(120,255,160)
                    if pos then
                        stagePos = computeScrapperStagePos(pos)
                    end
                elseif CURRENT_MODE == "all" then
                    pos   = noticeOrbPos()
                    color = Color3.fromRGB(100,200,255)
                    if pos then
                        stagePos = computeNoticeStagePos(pos)
                    end
                end
                if pos then
                    spawnOrbAt(pos, color, stagePos)
                end
            elseif CURRENT_MODE == "orbs" then
                destroyOrb()
                orbPosVec      = nil
                orbStagePosVec = nil
            end
        end
    end)
end
