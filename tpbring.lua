-- tpbring.lua
return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")

    local lp  = Players.LocalPlayer
    local tab = UI and UI.Tabs and (UI.Tabs.TPBring or UI.Tabs.Bring or UI.Tabs.Auto or UI.Tabs.Main)
    if not tab then return end

    ----------------------------------------------------------------
    -- Helpers
    ----------------------------------------------------------------
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

    local function jitter2D(pos, radius)
        if radius <= 0 then return pos end
        local ang = math.random() * math.pi * 2
        local r   = radius * math.random()
        return pos + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
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
    -- EdgeButtons container (shared by multiple modules)
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
    local ITEM_DELAY_BETWEEN     = 0.35  -- delay between items (seconds)
    local START_DRAG_DELAY       = 0.10  -- wait after startDrag
    local TELEPORT_SETTLE_DELAY  = 0.10  -- wait after teleport, before stopDrag

    local CAMPFIRE_DROP_Y_OFFSET = 8
    local SCRAPPER_DROP_Y_OFFSET = 8
    local NOTICE_DROP_Y_OFFSET   = 6
    local ORB_DROP_Y_OFFSET      = 6

    local DROP_JITTER_RADIUS     = 1.5   -- horizontal random jitter around target

    local INFLT_ATTR = "OrbInFlightAt"
    local JOB_ATTR   = "OrbJob"
    local DONE_ATTR  = "OrbDelivered"

    local CURRENT_RUN_ID = nil
    local CURRENT_MODE   = nil  -- "fuel" | "scrap" | "all" | "orbs" | nil
    local running        = false

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
    scrapAlso["Log"] = true

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

    local function canPick(m, selectedSet)
        if not (m and m.Parent and m:IsA("Model")) then return false end
        local itemsFolder = itemsRootOrNil()
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then return false end
        if isExcludedModel(m) or isUnderLogWall(m) or hasIceBlockTag(m) then return false end

        local done = m:GetAttribute(DONE_ATTR)
        if done and CURRENT_RUN_ID and tostring(done) == tostring(CURRENT_RUN_ID) then
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
        Vector3.new(-27.85, 4.05, 50.82),
        Vector3.new( -6.68, 4.05, 47.66),
        Vector3.new( 14.50, 4.05, 44.50),
        Vector3.new( 35.67, 4.05, 41.33),
    }

    local orbItemSets = { {}, {}, {}, {} }
    local orbEnabled  = { true, true, true, true }
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
    local function collectCandidatesFromSet(selectedSet)
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
            if m and not uniq[m] and canPick(m, selectedSet) then
                uniq[m] = true
                out[#out+1] = m
            end
        end
        return out
    end

    local function getCandidatesForCurrent()
        local selectedSet = currentSelectedSet()
        return collectCandidatesFromSet(selectedSet)
    end

    local function getCandidatesForOrbs()
        return collectCandidatesFromSet(orbUnionSet)
    end

    ----------------------------------------------------------------
    -- DESTINATION HELPERS (drop positions)
    ----------------------------------------------------------------
    local function campfireDropPos()
        local map = WS:FindFirstChild("Map")
        local camp = map and map:FindFirstChild("Campground")
        local fire = camp and camp:FindFirstChild("MainFire")
        if not fire then return nil end
        local mp  = mainPart(fire)
        local pos = (mp and mp.Position) or fire:GetPivot().Position
        return pos + Vector3.new(0, CAMPFIRE_DROP_Y_OFFSET, 0)
    end

    local function scrapperDropPos()
        local map = WS:FindFirstChild("Map")
        local camp = map and map:FindFirstChild("Campground")
        local scr = camp and camp:FindFirstChild("Scrapper")
        if not scr then return nil end
        local mp  = mainPart(scr)
        local pos = (mp and mp.Position) or scr:GetPivot().Position
        return pos + Vector3.new(0, SCRAPPER_DROP_Y_OFFSET, 0)
    end

    local function noticeDropPos()
        local map = WS:FindFirstChild("Map")
        local camp = map and map:FindFirstChild("Campground")
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
        local mp  = mainPart(board)
        local pos = (mp and mp.Position) or board:GetPivot().Position
        return pos + Vector3.new(0, NOTICE_DROP_Y_OFFSET, 0)
    end

    local function orbDropPos(index)
        local base = CUSTOM_ORB_BASES[index]
        if not base then return nil end
        return base + Vector3.new(0, ORB_DROP_Y_OFFSET, 0)
    end

    ----------------------------------------------------------------
    -- Process one item: ALWAYS use drag remote first
    ----------------------------------------------------------------
    local function processItemToDest(m, destPos)
        if not (m and m.Parent and destPos) then return end
        local mp = mainPart(m)
        if not mp then return end

        -- mark inflight for this run (optional, mainly informational)
        local now = os.clock()
        pcall(function()
            m:SetAttribute(INFLT_ATTR, now)
            m:SetAttribute(JOB_ATTR, CURRENT_RUN_ID)
        end)

        local snap = snapshotCollide(m)
        setAnchored(m, true)
        zeroAssembly(m)

        -- Always start drag first, regardless of item type
        if startDrag then
            pcall(function()
                startDrag:FireServer(m)
            end)
        end

        task.wait(START_DRAG_DELAY)

        -- Teleport just above the destination with jitter
        local target = jitter2D(destPos, DROP_JITTER_RADIUS)
        setPivot(m, CFrame.new(target))

        task.wait(TELEPORT_SETTLE_DELAY)

        -- Stop drag and restore physics so it drops naturally
        if stopDrag then
            pcall(function()
                stopDrag:FireServer(m)
            end)
        end

        setAnchored(m, false)
        zeroAssembly(m)
        setCollideFromSnapshot(snap)

        pcall(function()
            m:SetAttribute(DONE_ATTR, CURRENT_RUN_ID)
            m:SetAttribute(INFLT_ATTR, nil)
            m:SetAttribute(JOB_ATTR, nil)
        end)
    end

    ----------------------------------------------------------------
    -- Background pre-drag for rare / important items (unchanged)
    ----------------------------------------------------------------
    local PRECLAIM_DISTANCE    = 100
    local PRECLAIM_INTERVAL_S  = 2.5
    local preclaimAcc          = 0
    local preclaimEnabled      = false
    local preclaimConn         = nil

    local function campfireOrbPos_forPreclaim()
        local map = WS:FindFirstChild("Map")
        local camp = map and map:FindFirstChild("Campground")
        local fire = camp and camp:FindFirstChild("MainFire")
        if not fire then return nil end
        local mp  = mainPart(fire)
        local pos = (mp and mp.Position) or fire:GetPivot().Position
        return pos
    end

    local function setPreclaimEnabled(state)
        preclaimEnabled = state and true or false
        if preclaimEnabled then
            if preclaimConn then return end
            preclaimAcc = 0
            preclaimConn = game:GetService("RunService").Heartbeat:Connect(function(dt)
                preclaimAcc = preclaimAcc + dt
                if preclaimAcc < PRECLAIM_INTERVAL_S then return end
                preclaimAcc = 0

                if not preclaimEnabled then return end
                if not startDrag then return end

                local itemsFolder = itemsRootOrNil()
                if not itemsFolder then return end
                local campPos = campfireOrbPos_forPreclaim()
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
    -- MODE START/STOP + main loop
    ----------------------------------------------------------------
    local function stopAll()
        running        = false
        CURRENT_MODE   = nil
        CURRENT_RUN_ID = nil
    end

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
        CURRENT_MODE   = mode
        CURRENT_RUN_ID = tostring(os.clock())
        running        = true

        task.spawn(function()
            local myRunId = CURRENT_RUN_ID
            while running and CURRENT_RUN_ID == myRunId and CURRENT_MODE == mode do
                local itemsFolder = itemsRootOrNil()
                if not itemsFolder then
                    task.wait(0.5)
                    goto continue
                end

                local destProvider
                local candidates

                if mode == "fuel" then
                    destProvider = campfireDropPos
                    candidates   = getCandidatesForCurrent()
                elseif mode == "scrap" then
                    destProvider = scrapperDropPos
                    candidates   = getCandidatesForCurrent()
                elseif mode == "all" then
                    destProvider = noticeDropPos
                    candidates   = getCandidatesForCurrent()
                elseif mode == "orbs" then
                    destProvider = nil -- per-item via orbDropPos
                    candidates   = getCandidatesForOrbs()
                else
                    break
                end

                if not candidates or #candidates == 0 then
                    task.wait(0.5)
                    goto continue
                end

                for _,m in ipairs(candidates) do
                    if not (running and CURRENT_RUN_ID == myRunId and CURRENT_MODE == mode) then
                        break
                    end

                    local destPos = nil
                    if mode == "fuel" then
                        destPos = campfireDropPos()
                    elseif mode == "scrap" then
                        destPos = scrapperDropPos()
                    elseif mode == "all" then
                        destPos = noticeDropPos()
                    elseif mode == "orbs" then
                        local idx = orbIndexForModel(m)
                        if idx and orbEnabled[idx] then
                            destPos = orbDropPos(idx)
                        end
                    end

                    if destPos then
                        processItemToDest(m, destPos)
                        task.wait(ITEM_DELAY_BETWEEN)
                    end
                end

                ::continue::
            end
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
    -- Respawn handling (no special orb needed now, but keep hook)
    ----------------------------------------------------------------
    Players.LocalPlayer.CharacterAdded:Connect(function()
        -- processing loop is independent of character, so nothing to restart here.
        -- This hook is left in case you want to extend respawn behavior later.
    end)
end
