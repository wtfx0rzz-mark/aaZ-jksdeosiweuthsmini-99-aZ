return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")
    local CS       = game:GetService("CollectionService")

    local lp  = Players.LocalPlayer
    local tabs = UI and UI.Tabs
    local tab  = tabs and (tabs.Debug or tabs.TPBring or tabs.Auto or tabs.Main)
    assert(tab, "No tab")

    local RADIUS = 20

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
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
    local function getRemote(...)
        local f = RS:FindFirstChild("RemoteEvents"); if not f then return nil end
        for i=1,select("#", ...) do
            local n = select(i, ...)
            local x = f:FindFirstChild(n)
            if x then return x end
        end
        return nil
    end

    local RF_Start = getRemote("RequestStartDraggingItem","StartDraggingItem")
    local RF_Stop  = getRemote("RequestStopDraggingItem","StopDraggingItem","StopDraggingItemRemote")

    local function itemsFolder() return WS:FindFirstChild("Items") or WS end
    local function nearbyItems()
        local out, root = {}, hrp(); if not root then return out end
        local origin = root.Position
        for _,d in ipairs(itemsFolder():GetDescendants()) do
            local m = d:IsA("Model") and d or d:IsA("BasePart") and d:FindFirstAncestorOfClass("Model") or nil
            if m and m.Parent then
                local p = mainPart(m)
                if p and (p.Position - origin).Magnitude <= RADIUS then
                    out[#out+1] = m
                end
            end
        end
        return out
    end

    local function setPhysicsRestore(m)
        for _,p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then
                p.Anchored = false
                p.CanCollide = true
                p.CanTouch = true
                p.CanQuery = true
                p.Massless = false
                p.AssemblyLinearVelocity = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
                p.CollisionGroupId = 0
                pcall(function() p:SetNetworkOwner(nil) end)
                pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
            end
        end
        for _,pp in ipairs(m:GetDescendants()) do
            if pp:IsA("ProximityPrompt") then pp.Enabled = true end
        end
        m:SetAttribute("Dragging", nil)
        m:SetAttribute("PickedUp", nil)
    end

    local function snapshotCollision(m)
        local t = {}
        for _,p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then
                t[p] = {CanCollide=p.CanCollide, CanQuery=p.CanQuery, CanTouch=p.CanTouch}
            end
        end
        return t
    end
    local function setCollisionOff(m)
        for _,p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CanCollide = false
                p.CanQuery   = false
                p.CanTouch   = false
            end
        end
    end
    local function restoreCollision(m, snap)
        if not snap then return end
        for part,st in pairs(snap) do
            if part and part.Parent then
                part.CanCollide = st.CanCollide
                part.CanQuery   = st.CanQuery
                part.CanTouch   = st.CanTouch
            end
        end
    end

    local function ownAll()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            if RF_Start then pcall(function() RF_Start:FireServer(m) end) end
            local p = mainPart(m)
            if p then
                pcall(function() p:SetNetworkOwner(lp) end)
                for _,bp in ipairs(m:GetDescendants()) do
                    if bp:IsA("BasePart") then
                        bp.Anchored = true
                        bp.CanTouch = true
                        bp.CanQuery = true
                    end
                end
            end
        end
    end
    local function disownAll()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            if RF_Stop then pcall(function() RF_Stop:FireServer(m) end) end
            setPhysicsRestore(m)
        end
    end
    local function startDragAll()
        if not RF_Start then return end
        local list = nearbyItems()
        for _,m in ipairs(list) do
            pcall(function() RF_Start:FireServer(m) end)
            Run.Heartbeat:Wait()
        end
    end
    local function stopDragAll()
        if not RF_Stop then return end
        local list = nearbyItems()
        for _,m in ipairs(list) do
            pcall(function() RF_Stop:FireServer(m) end)
            Run.Heartbeat:Wait()
        end
    end

    local function wakeGentle()
        local list = nearbyItems()
        local lin, ang = 0.05, 0.05
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") and not p.Anchored then
                    local lv, av = p.AssemblyLinearVelocity, p.AssemblyAngularVelocity
                    if lv.Magnitude < 0.02 and av.Magnitude < 0.02 then
                        p.AssemblyLinearVelocity  = lv + Vector3.new((math.random()-0.5)*lin, (math.random()-0.5)*lin, (math.random()-0.5)*lin)
                        p.AssemblyAngularVelocity = av + Vector3.new((math.random()-0.5)*ang, (math.random()-0.5)*ang, (math.random()-0.5)*ang)
                    end
                end
            end
        end
    end
    local function deoverlap()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            local p = mainPart(m)
            if p and not p.Anchored then
                local cf = (m:IsA("Model") and m:GetPivot()) or p.CFrame
                local jitter = 0.03
                local dx, dz = (math.random()-0.5)*jitter, (math.random()-0.5)*jitter
                if m:IsA("Model") then m:PivotTo(cf + Vector3.new(dx, 0, dz)) else p.CFrame = cf + Vector3.new(dx, 0, dz) end
            end
        end
    end
    local function nudgeAll()
        local list = nearbyItems()
        for _,m in ipairs(list) do setPhysicsRestore(m) end
        Run.Heartbeat:Wait()
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") and not p.Anchored then
                    p.AssemblyLinearVelocity  = p.AssemblyLinearVelocity  + Vector3.new(0, 0.6, 0)
                    p.AssemblyAngularVelocity = p.AssemblyAngularVelocity + Vector3.new(0, 0.3*(math.random()-0.5), 0)
                end
            end
        end
    end
    local function mineOwnership()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.Anchored = false
                    pcall(function() p:SetNetworkOwner(lp) end)
                end
            end
        end
    end
    local function serverOwnership()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.Anchored = false
                    pcall(function() p:SetNetworkOwner(nil) end)
                    pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
                end
            end
        end
    end

    local function groundBelow(pos)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local ex = { lp.Character }
        local map = WS:FindFirstChild("Map")
        if map then
            local fol = map:FindFirstChild("Foliage")
            if fol then table.insert(ex, fol) end
        end
        local items = WS:FindFirstChild("Items"); if items then table.insert(ex, items) end
        params.FilterDescendantsInstances = ex
        local start = pos + Vector3.new(0, 5, 0)
        local hit = WS:Raycast(start, Vector3.new(0, -1000, 0), params)
        if hit then return hit.Position end
        hit = WS:Raycast(pos + Vector3.new(0, 200, 0), Vector3.new(0, -1000, 0), params)
        return (hit and hit.Position) or pos
    end
    local function zeroAssembly(root)
        if not root then return end
        root.AssemblyLinearVelocity  = Vector3.new()
        root.AssemblyAngularVelocity = Vector3.new()
    end

    local function allBodyModels()
        local out = {}
        local chars = WS:FindFirstChild("Characters") or WS
        for _,m in ipairs(chars:GetChildren()) do
            if m:IsA("Model") and m.Name:match("%sBody$") and mainPart(m) then
                out[#out+1] = m
            end
        end
        return out
    end
    local function findNearestBody()
        local root = hrp(); if not root then return nil end
        local best, bestD = nil, math.huge
        for _,m in ipairs(allBodyModels()) do
            local p = mainPart(m)
            local d = (p.Position - root.Position).Magnitude
            if d < bestD then bestD, best = d, m end
        end
        return best
    end

    local function tpPlayerToBody()
        local m = findNearestBody(); if not m then return end
        local p = mainPart(m); if not p then return end
        local g = groundBelow(p.Position)
        local dest = Vector3.new(p.Position.X, g.Y + 2.5, p.Position.Z)
        local root = hrp(); if not root then return end
        local look = (p.Position - root.Position); if look.Magnitude < 1e-3 then look = root.CFrame.LookVector end
        local cf = CFrame.new(dest, dest + look.Unit)
        pcall(function() (lp.Character or {}).PrimaryPart.CFrame = cf end)
        pcall(function() root.CFrame = cf end)
        zeroAssembly(root)
    end

    local function bringBodiesFast()
        local root = hrp(); if not root then return end
        local bodies = allBodyModels(); if #bodies == 0 then return end
        local targetPos = groundBelow(root.Position + root.CFrame.LookVector * 2)
        local cf = CFrame.new(Vector3.new(targetPos.X, targetPos.Y + 1.5, targetPos.Z), root.Position)

        for _,m in ipairs(bodies) do
            local snap = snapshotCollision(m)
            setCollisionOff(m)
            if RF_Start then pcall(function() RF_Start:FireServer(m) end) end
            Run.Heartbeat:Wait()
            pcall(function() m:PivotTo(cf) end)
            Run.Heartbeat:Wait()
            restoreCollision(m, snap)
            if RF_Stop then pcall(function() RF_Stop:FireServer(m) end) end
            setPhysicsRestore(m)
            Run.Heartbeat:Wait()
        end
    end

    local function releaseBody()
        local m = findNearestBody(); if not m then return end
        if RF_Stop then pcall(function() RF_Stop:FireServer(m) end) end
        setPhysicsRestore(m)
    end

    local CAMP_CACHE = nil
    local function fireCenterPart(fire)
        if not fire then return nil end
        local c = fire:FindFirstChild("Center")
            or fire:FindFirstChild("InnerTouchZone")
            or fire:FindFirstChildWhichIsA("BasePart")
            or fire.PrimaryPart
        if c and c:IsA("BasePart") then return c end
        return nil
    end
    local function resolveCampfireModel()
        if CAMP_CACHE and CAMP_CACHE.Parent then return CAMP_CACHE end
        local function nameHit(n)
            n = (n or ""):lower()
            if n == "mainfire" then return true end
            if n == "campfire" or n == "camp fire" then return true end
            if n:find("main") and n:find("fire") then return true end
            if n:find("camp") and n:find("fire") then return true end
            return false
        end
        local map = WS:FindFirstChild("Map")
        local cg  = map and map:FindFirstChild("Campground")
        local mf  = cg and (cg:FindFirstChild("MainFire") or cg:FindFirstChild("Campfire") or cg:FindFirstChild("CampFire"))
        if mf then CAMP_CACHE = mf return mf end
        if map then
            for _,d in ipairs(map:GetDescendants()) do
                if d:IsA("Model") and nameHit(d.Name) then CAMP_CACHE = d return d end
            end
        end
        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") and nameHit(d.Name) then CAMP_CACHE = d return d end
        end
        return nil
    end
    local function campTargetCF()
        local fire = resolveCampfireModel(); if not fire then return nil end
        local c = fireCenterPart(fire); if not c then return nil end
        local size = Vector3.new()
        pcall(function()
            local min, max = fire:GetBoundingBox()
            size = (max - min)
        end)
        local pad = math.max(size.X, size.Z)
        if pad == 0 then
            local zone = fire:FindFirstChild("InnerTouchZone")
            if zone and zone:IsA("BasePart") then pad = math.max(zone.Size.X, zone.Size.Z) end
        end
        if pad == 0 then pad = 6 end
        local posAhead = c.Position + c.CFrame.LookVector * (pad * 0.5 + 2)
        local g = groundBelow(posAhead)
        local pos = Vector3.new(posAhead.X, g.Y + 1.5, posAhead.Z)
        return CFrame.new(pos, c.Position)
    end
    local function sendBodiesToCamp()
        local bodies = allBodyModels(); if #bodies == 0 then return end
        local cf = campTargetCF(); if not cf then return end
        for _,m in ipairs(bodies) do
            local snap = snapshotCollision(m)
            setCollisionOff(m)
            if RF_Start then pcall(function() RF_Start:FireServer(m) end) end
            Run.Heartbeat:Wait()
            pcall(function() m:PivotTo(cf) end)
            Run.Heartbeat:Wait()
            restoreCollision(m, snap)
            if RF_Stop then pcall(function() RF_Stop:FireServer(m) end) end
            setPhysicsRestore(m)
            Run.Heartbeat:Wait()
        end
    end

    local SAP_Enable = false
    local sap_seen = setmetatable({}, {__mode="k"})
    local sap_conns = {}

    local function isSapling(m)
        if not m or not m.Parent then return false end
        if m:IsA("Model") then
            local n = (m.Name or ""):lower()
            if n:find("sapling") then return true end
            if CS:HasTag(m, "Sapling") then return true end
            if m:GetAttribute("IsSapling") == true then return true end
        end
        return false
    end
    local function tryStartDragSapling(m)
        if not SAP_Enable then return end
        if not m or not m.Parent then return end
        if not isSapling(m) then return end
        if sap_seen[m] then return end
        sap_seen[m] = true
        if RF_Start then pcall(function() RF_Start:FireServer(m) end) end
    end
    local function bindSaplingWatcher(items)
        for _,c in ipairs(sap_conns) do c:Disconnect() end
        table.clear(sap_conns)
        if not SAP_Enable then table.clear(sap_seen) return end
        if not items or not items.Parent then items = itemsFolder() end
        for _,d in ipairs(items:GetDescendants()) do
            local m = d:IsA("Model") and d or d:FindFirstAncestorOfClass("Model")
            if m then tryStartDragSapling(m) end
        end
        sap_conns[#sap_conns+1] = items.DescendantAdded:Connect(function(d)
            local m = d:IsA("Model") and d or d:FindFirstAncestorOfClass("Model")
            if m then tryStartDragSapling(m) end
        end)
        sap_conns[#sap_conns+1] = WS.ChildAdded:Connect(function(ch)
            if ch.Name == "Items" or ch == items then
                task.defer(function() bindSaplingWatcher(itemsFolder()) end)
            end
        end)
    end

    tab:Section({ Title = "Item Recovery" })
    tab:Button({ Title = "Own All Items",       Callback = function() ownAll() end })
    tab:Button({ Title = "Disown All Items",    Callback = function() disownAll() end })
    tab:Button({ Title = "Wake (Gentle)",       Callback = function() wakeGentle() end })
    tab:Button({ Title = "De-overlap",          Callback = function() deoverlap() end })
    tab:Button({ Title = "Nudge Items",         Callback = function() nudgeAll() end })
    tab:Button({ Title = "Mine Ownership",      Callback = function() mineOwnership() end })
    tab:Button({ Title = "Server Ownership",    Callback = function() serverOwnership() end })

    tab:Section({ Title = "Drag Remotes" })
    tab:Button({ Title = "Start Drag Nearby",   Callback = function() startDragAll() end })
    tab:Button({ Title = "Stop Drag Nearby",    Callback = function() stopDragAll() end })

    tab:Section({ Title = "Body Tests" })
    tab:Button({ Title = "TP To Body",                 Callback = function() tpPlayerToBody() end })
    tab:Button({ Title = "Bring Body (Fast Drag)",     Callback = function() bringBodiesFast() end })
    tab:Button({ Title = "Release Body",               Callback = function() releaseBody() end })
    tab:Button({ Title = "Send All Bodies To Camp",    Callback = function() sendBodiesToCamp() end })

    tab:Section({ Title = "Protection" })
    if tab.Toggle then
        tab:Toggle({
            Title = "Sapling Protection",
            Default = false,
            Callback = function(v)
                SAP_Enable = v and true or false
                bindSaplingWatcher(itemsFolder())
            end
        })
    else
        tab:Button({
            Title = "Sapling Protection: OFF",
            Callback = function(btn)
                SAP_Enable = not SAP_Enable
                if btn and btn.SetTitle then btn:SetTitle("Sapling Protection: " .. (SAP_Enable and "ON" or "OFF")) end
                bindSaplingWatcher(itemsFolder())
            end
        })
    end

    local PULL_TAG = "__PulledOnceDebug"
    local PULL_ATTR = "PulledOnce"
    local PULL_RADIUS = 15
    local PULL_HEIGHT_UP = 4
    local JUNK = {"Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine","UFO Junk","UFO Component"}
    local FUEL = {"Log","Coal","Fuel Canister","Oil Barrel","Chair"}
    local FOOD = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot","Chilli","Stew","Ribs","Pumpkin","Hearty Stew","Cooked Ribs","Corn","BBQ ribs","Apple","Mackerel"}
    local MED  = {"Bandage","MedKit"}
    local WA   = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe","Hammer","Chainsaw","Crossbow","Katana","Kunai","Laser cannon","Laser sword","Morningstar","Riot shield","Spear","Tactical Shotgun","Wildfire","Sword","Ice Axe"}
    local MISC = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling","Basketball","Blueprint","Diamond","Forest Gem","Key","Flashlight","Taming flute","Cultist Gem","Tusk","Infernal Sack"}
    local PELT = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Polar Bear Pelt","Arctic Fox Pelt"}

    local lookup = {}
    for _,n in ipairs(JUNK) do lookup[n]=true end
    for _,n in ipairs(FUEL) do lookup[n]=true end
    for _,n in ipairs(FOOD) do lookup[n]=true end
    for _,n in ipairs(MED)  do lookup[n]=true end
    for _,n in ipairs(WA)   do lookup[n]=true end
    for _,n in ipairs(MISC) do lookup[n]=true end
    for _,n in ipairs(PELT) do lookup[n]=true end

    local function isKeyName(nl)
        if not nl then return false end
        if not nl:find(" key",1,true) then return false end
        if nl:find("blue key",1,true) or nl:find("yellow key",1,true) or nl:find("red key",1,true)
        or nl:find("gray key",1,true) or nl:find("grey key",1,true) or nl:find("frog key",1,true) then
            return true
        end
        return false
    end
    local function isMossy(n) return n=="Mossy Coin" or (n and n:match("^Mossy Coin%d+$")~=nil) end
    local function isChestLike(n) return type(n)=="string" and (n:match("Chest%d*$") or n:match("Chest$")) end

    local function wantModel(m)
        if not m or not m:IsA("Model") then return false end
        local n = m.Name or ""
        local nl = n:lower()
        if n == "Coin Stack" then return true end
        if isMossy(n) then return true end
        if n == "Sapling" or nl:find("sapling",1,true) then return true end
        if nl:find("blueprint",1,true) then return true end
        if n == "Forest Gem" or nl:find("forest gem fragment",1,true) then return true end
        if isKeyName(nl) then return true end
        if nl:find("flashlight",1,true) and (nl:find("old",1,true) or nl:find("strong",1,true)) then return true end
        if nl:find("taming flute",1,true) and (nl:find("old",1,true) or nl:find("good",1,true) or nl:find("strong",1,true)) then return true end
        if lookup[n] then return true end
        if isChestLike(n) then return false end
        local p = mainPart(m)
        if not p then return false end
        return false
    end

    local function groundAround(center, r)
        local theta = math.random() * math.pi * 2
        local dist = math.sqrt(math.random()) * r
        local offset = Vector3.new(math.cos(theta)*dist, 0, math.sin(theta)*dist)
        local target = center + offset + Vector3.new(0, PULL_HEIGHT_UP, 0)
        local g = groundBelow(target)
        return Vector3.new(target.X, g.Y + 0.5, target.Z)
    end

    local function moveOnceToRing(m, center)
        local mp = mainPart(m); if not mp then return end
        local pos = groundAround(center, PULL_RADIUS)
        local cf = CFrame.new(pos, pos + Vector3.new(0,0,-1))
        local snap = snapshotCollision(m)
        setCollisionOff(m)
        if RF_Start then pcall(function() RF_Start:FireServer(m) end) end
        Run.Heartbeat:Wait()
        pcall(function()
            if m:IsA("Model") then m:PivotTo(cf) else mp.CFrame = cf end
        end)
        Run.Heartbeat:Wait()
        restoreCollision(m, snap)
        if RF_Stop then pcall(function() RF_Stop:FireServer(m) end) end
        setPhysicsRestore(m)
        pcall(function() CS:AddTag(m, PULL_TAG) end)
        pcall(function() m:SetAttribute(PULL_ATTR, true) end)
    end

    local pulling = false
    local pullLoopConn, itemsAddedConn, itemsFolderConn
    local SCAN_INTERVAL = 0.25
    local accum = 0

    local function scanAndPull(center)
        local items = itemsFolder()
        local seen = {}
        for _,d in ipairs(items:GetDescendants()) do
            local m = d:IsA("Model") and d or d:IsA("BasePart") and d:FindFirstAncestorOfClass("Model") or nil
            repeat
                if not m or not m.Parent then break end
                if seen[m] then break end
                seen[m] = true
                if CS:HasTag(m, PULL_TAG) then break end
                if m:GetAttribute(PULL_ATTR) == true then break end
                if not wantModel(m) then break end
                moveOnceToRing(m, center)
            until true
        end
    end

    local function bindItemsAdded()
        if itemsAddedConn then itemsAddedConn:Disconnect() end
        if itemsFolderConn then itemsFolderConn:Disconnect() end
        local items = itemsFolder()
        if items then
            itemsAddedConn = items.DescendantAdded:Connect(function(d)
                if not pulling then return end
                local root = hrp(); if not root then return end
                local m = d:IsA("Model") and d or d:FindFirstAncestorOfClass("Model")
                if not m or not m.Parent then return end
                if CS:HasTag(m, PULL_TAG) or m:GetAttribute(PULL_ATTR) == true then return end
                if wantModel(m) then moveOnceToRing(m, root.Position) end
            end)
            itemsFolderConn = WS.ChildAdded:Connect(function(ch)
                if ch.Name == "Items" or ch == items then
                    task.defer(bindItemsAdded)
                end
            end)
        end
    end

    local function enablePull()
        if pulling then return end
        pulling = true
        bindItemsAdded()
        if pullLoopConn then pullLoopConn:Disconnect() end
        pullLoopConn = Run.Heartbeat:Connect(function(dt)
            accum = accum + dt
            if accum < SCAN_INTERVAL then return end
            accum = 0
            local root = hrp(); if not root then return end
            scanAndPull(root.Position)
        end)
    end

    local function disablePull()
        pulling = false
        if pullLoopConn then pcall(function() pullLoopConn:Disconnect() end) pullLoopConn = nil end
        if itemsAddedConn then pcall(function() itemsAddedConn:Disconnect() end) itemsAddedConn = nil end
        if itemsFolderConn then pcall(function() itemsFolderConn:Disconnect() end) itemsFolderConn = nil end
        for _,inst in ipairs(CS:GetTagged(PULL_TAG)) do
            pcall(function() inst:SetAttribute(PULL_ATTR, nil) end)
            pcall(function() CS:RemoveTag(inst, PULL_TAG) end)
        end
    end

    local function addToggleLike(tabRef, title, default, cb)
        if tabRef.Toggle then
            return tabRef:Toggle({ Title = title, Default = default, Callback = cb })
        end
        local state = default and true or false
        return tabRef:Button({
            Title = title .. (state and " (ON)" or " (OFF)"),
            Callback = function(self)
                state = not state
                cb(state)
                if self and self.SetTitle then
                    self:SetTitle(title .. (state and " (ON)" or " (OFF)"))
                end
            end
        })
    end

    tab:Section({ Title = "Pull Items" })
    addToggleLike(tab, "Pull Items", false, function(v)
        if v then enablePull() else disablePull() end
    end)
end
