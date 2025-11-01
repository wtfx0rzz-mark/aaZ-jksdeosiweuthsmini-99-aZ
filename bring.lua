return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local RS      = C.Services.RS
    local Run     = C.Services.Run or game:GetService("RunService")
    local lp      = Players.LocalPlayer

    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Bring
    assert(tab, "Bring tab not found in UI")

    local AMOUNT_TO_BRING       = 500
    local CONVEYOR_MAX_ACTIVE   = 25
    local PER_ITEM_DELAY        = 1.0
    local COLLIDE_OFF_SEC       = 0.22

    local DROP_ABOVE_HEAD_STUDS = 10
    local FALLBACK_UP           = 5
    local FALLBACK_AHEAD        = 2
    local NEARBY_RADIUS         = 20
    local ORB_OFFSET_Y          = 20

    local CLUSTER_RADIUS_MIN  = 0.75
    local CLUSTER_RADIUS_STEP = 0.04
    local CLUSTER_RADIUS_MAX  = 2.25

    local CAMPFIRE_PATH = workspace.Map.Campground.MainFire
    local SCRAPPER_PATH = workspace.Map.Campground.Scrapper

    local junkItems    = {
        "Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine",
        "UFO Junk","UFO Component"
    }
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems    = {
        "Morsel","Cooked Morsel","Steak","Cooked Steak","Ribs","Cooked Ribs","Cake","Berry","Carrot",
        "Chilli","Stew","Pumpkin","Hearty Stew","Corn","BBQ ribs","Apple","Mackerel"
    }
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {
        "Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe",
        "Chainsaw","Crossbow","Katana","Kunai","Laser cannon","Laser sword","Morningstar","Riot shield","Spear","Tactical Shotgun","Wildfire",
        "Sword"
    }
    local ammoMisc     = {
        "Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling",
        "Basketball","Blueprint","Diamond","Forest Gem","Key","Flashlight","Taming flute","Cultist Gem","Tusk"
    }
    local pelts        = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Polar Bear Pelt","Arctic Fox Pelt"}

    local fuelSet, junkSet, cookSet, scrapAlso = {}, {}, {}, {}
    for _,n in ipairs(fuelItems) do fuelSet[n] = true end
    for _,n in ipairs(junkItems) do junkSet[n] = true end
    cookSet["Morsel"] = true; cookSet["Steak"] = true; cookSet["Ribs"] = true
    scrapAlso["Log"] = true;  scrapAlso["Chair"] = true

    local RAW_TO_COOKED = { ["Morsel"]="Cooked Morsel", ["Steak"]="Cooked Steak", ["Ribs"]="Cooked Ribs" }

    local function hrp()
        local ch = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local function headPart()
        local ch = Players.LocalPlayer.Character
        return ch and ch:FindFirstChild("Head")
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
    local function mainPart(obj)
        if not obj or not obj.Parent then return nil end
        if obj:IsA("BasePart") then return obj end
        if obj:IsA("Model") then
            if obj.PrimaryPart then return obj.PrimaryPart end
            return obj:FindFirstChildWhichIsA("BasePart")
        end
        return nil
    end
    local function getAllParts(target)
        local t = {}
        if not target then return t end
        if target:IsA("BasePart") then
            t[1] = target
        elseif target:IsA("Model") then
            for _,d in ipairs(target:GetDescendants()) do
                if d:IsA("BasePart") then t[#t+1] = d end
            end
        end
        return t
    end

    local function getRemote(...)
        local re = RS:FindFirstChild("RemoteEvents"); if not re then return nil end
        for _,n in ipairs({...}) do local x=re:FindFirstChild(n); if x then return x end end
        return nil
    end
    local function resolveRemotes()
        return {
            StartDrag = getRemote("RequestStartDraggingItem","StartDraggingItem"),
            BurnItem  = getRemote("RequestBurnItem","BurnItem","RequestFireAdd"),
            CookItem  = getRemote("RequestCookItem","CookItem"),
            ScrapItem = getRemote("RequestScrapItem","ScrapItem","RequestWorkbenchScrap"),
            StopDrag  = getRemote("StopDraggingItem","RequestStopDraggingItem"),
        }
    end

    local function startDragRemote(r, model)
        if r.StartDrag then
            pcall(function() r.StartDrag:FireServer(model) end)
            pcall(function() r.StartDrag:FireServer(Instance.new("Model")) end)
        end
    end
    local function stopDragRemote(r)
        if r.StopDrag then
            pcall(function() r.StopDrag:FireServer(Instance.new("Model")) end)
        end
    end

    local function startDragGround(model)
        local r = resolveRemotes()
        if r and r.StartDrag then pcall(function() r.StartDrag:FireServer(model) end) end
        return r
    end
    local function stopDragGround(r, model)
        if r and r.StopDrag then
            pcall(function() r.StopDrag:FireServer(model) end)
            pcall(function() r.StopDrag:FireServer(Instance.new("Model")) end)
        end
    end

    local function setCollide(model, on, snapshot)
        local parts = getAllParts(model)
        if on and snapshot then
            for part,can in pairs(snapshot) do
                if part and part.Parent then part.CanCollide = can end
            end
            return
        end
        local snap = {}
        for _,p in ipairs(parts) do snap[p]=p.CanCollide; p.CanCollide=false end
        return snap
    end
    local function zeroAssembly(model)
        for _,p in ipairs(getAllParts(model)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
    end
    local function sortedFarthest(list)
        local r = hrp(); if not r then return list end
        table.sort(list, function(a,b)
            return (a.part.Position - r.Position).Magnitude > (b.part.Position - r.Position).Magnitude
        end)
        return list
    end

    local function itemsRoot()
        return WS:FindFirstChild("Items")
    end

    local function collectByNameLoose(name, limit)
        local found, n = {}, 0
        local root = itemsRoot(); if not root then return found end
        for _,d in ipairs(root:GetDescendants()) do
            if (d:IsA("Model") or d:IsA("BasePart")) and d.Name == name then
                local model = d:IsA("Model") and d or d.Parent
                if model and model:IsA("Model") and not isExcludedModel(model) and not isUnderLogWall(model) then
                    if name == "Log" and isWallVariant(model) then
                    else
                        local mp = mainPart(model)
                        if mp then
                            n += 1
                            found[#found+1] = {model=model, part=mp}
                            if limit and n >= limit then break end
                        end
                    end
                end
            end
        end
        return sortedFarthest(found)
    end
    private = nil
    local function collectMossyCoins(limit)
        local out, n = {}, 0
        local root = itemsRoot(); if not root then return out end
        for _,m in ipairs(root:GetDescendants()) do
            if m:IsA("Model") and not isExcludedModel(m) and not isUnderLogWall(m) then
                local nm = m.Name
                if nm == "Mossy Coin" or nm:match("^Mossy Coin%d+$") then
                    local mp = m:FindFirstChild("Main") or m:FindFirstChildWhichIsA("BasePart")
                    if mp then
                        n += 1
                        out[#out+1] = {model=m, part=mp}
                        if limit and n >= limit then break end
                    end
                end
            end
        end
        return sortedFarthest(out)
    end
    local function collectCultists(limit)
        local out, n = {}, 0
        local root = itemsRoot(); if not root then return out end
        for _,m in ipairs(root:GetDescendants()) do
            if m:IsA("Model") and m.Name:lower():find("cultist",1,true) and not isExcludedModel(m) and not isUnderLogWall(m) then
                if hasHumanoid(m) then
                    local mp = mainPart(m)
                    if mp then
                        n += 1
                        out[#out+1] = {model=m, part=mp}
                        if limit and n >= limit then break end
                    end
                end
            end
        end
        return sortedFarthest(out)
    end
    local function collectSaplings(limit)
        local out, n = {}, 0
        local root = itemsRoot(); if not root then return out end
        for _,m in ipairs(root:GetChildren()) do
            if m:IsA("Model") and m.Name == "Sapling" and not isExcludedModel(m) and not isUnderLogWall(m) then
                local mp = mainPart(m)
                if mp then
                    n += 1
                    out[#out+1] = {model=m, part=mp}
                    if limit and n >= limit then break end
                end
            end
        end
        return sortedFarthest(out)
    end
    local function collectPelts(which, limit)
        local out, n = {}, 0
        local root = itemsRoot(); if not root then return out end
        for _,m in ipairs(root:GetDescendants()) do
            if m:IsA("Model") and not isExcludedModel(m) and not isUnderLogWall(m) then
                local nm, ok = m.Name, false
                ok = ok or (which=="Bunny Foot" and nm=="Bunny Foot")
                ok = ok or (which=="Wolf Pelt" and nm=="Wolf Pelt")
                ok = ok or (which=="Alpha Wolf Pelt" and nm:lower():find("alpha",1,true) and nm:lower():find("wolf",1,true))
                ok = ok or (which=="Bear Pelt" and nm:lower():find("bear",1,true) and not nm:lower():find("polar",1,true))
                ok = ok or (which=="Polar Bear Pelt" and nm=="Polar Bear Pelt")
                ok = ok or (which=="Arctic Fox Pelt" and nm=="Arctic Fox Pelt")
                if ok then
                    local mp = mainPart(m)
                    if mp then
                        n += 1
                        out[#out+1] = {model=m, part=mp}
                        if limit and n >= limit then break end
                    end
                end
            end
        end
        return sortedFarthest(out)
    end

    local function computeForwardDropCF()
        local root = hrp(); if not root then return nil end
        local head = headPart()
        local basePos = head and head.Position or (root.Position + Vector3.new(0,4,0))
        local look = root.CFrame.LookVector
        local center = basePos + Vector3.new(0, DROP_ABOVE_HEAD_STUDS, 0) + look * FALLBACK_AHEAD
        return CFrame.lookAt(center, center + look)
    end

    local function pivotOverTarget(model, target)
        local mp = mainPart(target); if not mp then return end
        local above = mp.CFrame + Vector3.new(0, FALLBACK_UP, 0)
        local snap = setCollide(model, false)
        zeroAssembly(model)
        if model:IsA("Model") then model:PivotTo(above) else local p=mainPart(model); if p then p.CFrame=above end end
        for _,p in ipairs(getAllParts(model)) do p.AssemblyLinearVelocity = Vector3.new(0,-8,0) end
        task.delay(COLLIDE_OFF_SEC, function() setCollide(model, true, snap) end)
    end

    local function moveModel(model, cf)
        local snap = setCollide(model, false)
        zeroAssembly(model)
        if model:IsA("Model") then model:PivotTo(cf) else local p=mainPart(model); if p then p.CFrame=cf end end
        setCollide(model, true, snap)
    end

    local function fireCenterCF(fire)
        local p = fire:FindFirstChild("Center") or fire:FindFirstChild("InnerTouchZone") or mainPart(fire) or fire.PrimaryPart
        return (p and p.CFrame) or fire:GetPivot()
    end
    local function fireHandoffCF(fire) return fireCenterCF(fire) + Vector3.new(0, 1.5, 0) end

    local function nudgeModelOut(model, fromPos)
        local mp = mainPart(model); if not mp then return end
        local dir = (mp.Position - fromPos)
        if dir.Magnitude < 0.1 then dir = (mp.CFrame.LookVector) end
        dir = Vector3.new(dir.X, 0, dir.Z).Unit
        local offset = dir * 1.5 + Vector3.new(0, 0.35, 0)
        local vel    = dir * 16 + Vector3.new(0, 7, 0)
        local snap = setCollide(model, false)
        if model:IsA("Model") then model:PivotTo((model:GetPivot() + offset)) else mp.CFrame = mp.CFrame + offset end
        for _,p in ipairs(getAllParts(model)) do p.AssemblyLinearVelocity = vel end
        task.delay(0.15, function() setCollide(model, true, snap) end)
    end

    local function findCookedNearFire(fire, cookedName)
        local center = fireCenterCF(fire).Position
        local best, bestD
        for _,m in ipairs(WS:GetDescendants()) do
            if m:IsA("Model") and m.Name == cookedName and not isExcludedModel(m) and not isUnderLogWall(m) then
                local mp = mainPart(m)
                if mp then
                    local d = (mp.Position - center).Magnitude
                    if d <= 10 and (not bestD or d < bestD) then best, bestD = m, d end
                end
            end
        end
        return best
    end

    local DRAG_SETTLE  = 0.06
    local ACTION_HOLD  = 0.12
    local CONSUME_WAIT = 1.0

    local function awaitConsumedOrMoved(model, timeout)
        local t0 = os.clock()
        local p0 = model and model.Parent or nil
        while os.clock() - t0 < (timeout or 1) do
            if not model or not model.Parent then return true end
            if model.Parent ~= p0 then return true end
            if model:GetAttribute("Consumed") == true then return true end
            Run.Heartbeat:Wait()
        end
        return false
    end

    local function burnFlow(model, campfire)
        local r = resolveRemotes()
        startDragRemote(r, model)
        Run.Heartbeat:Wait()
        task.wait(DRAG_SETTLE)
        pivotOverTarget(model, campfire)
        task.wait(ACTION_HOLD)
        if r.BurnItem then pcall(function() r.BurnItem:FireServer(campfire, Instance.new("Model")) end) end
        local _ = awaitConsumedOrMoved(model, CONSUME_WAIT)
        stopDragRemote(r)
    end
    local function cookFlow(model, campfire)
        local r = resolveRemotes()
        startDragRemote(r, model)
        Run.Heartbeat:Wait()
        task.wait(DRAG_SETTLE)
        moveModel(model, fireHandoffCF(campfire))
        local ok = false
        if r.CookItem then ok = pcall(function() r.CookItem:FireServer(campfire, Instance.new("Model")) end) end
        if not ok then pivotOverTarget(model, campfire) end
        task.wait(ACTION_HOLD)
        local cookedName = RAW_TO_COOKED[model.Name]
        local _ = awaitConsumedOrMoved(model, CONSUME_WAIT)
        stopDragRemote(r)
        task.delay(0.15, function()
            if cookedName then
                local cooked = findCookedNearFire(campfire, cookedName)
                if cooked then nudgeModelOut(cooked, fireCenterCF(campfire).Position) end
            end
        end)
    end
    local function scrCenterCF(scr)
        local p = mainPart(scr) or scr.PrimaryPart
        return (p and p.CFrame) or scr:GetPivot()
    end
    local function scrapFlow(model, scrapper)
        local r = resolveRemotes()
        startDragRemote(r, model)
        Run.Heartbeat:Wait()
        task.wait(DRAG_SETTLE)
        moveModel(model, scrCenterCF(scrapper) + Vector3.new(0, 1.5, 0))
        local ok = false
        if r.ScrapItem then ok = pcall(function() r.ScrapItem:FireServer(scrapper, Instance.new("Model")) end) end
        if not ok then pivotOverTarget(model, scrapper) end
        task.wait(ACTION_HOLD)
        local _ = awaitConsumedOrMoved(model, CONSUME_WAIT)
        stopDragRemote(r)
    end

    local dropCounter = 0
    local function ringOffset()
        dropCounter += 1
        local i = dropCounter
        local a = i * 2.399963229728653
        local r = math.min(CLUSTER_RADIUS_MIN + CLUSTER_RADIUS_STEP * (i - 1), CLUSTER_RADIUS_MAX)
        return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
    end

    local function groundCFAroundPlayer(model)
        local root = hrp(); if not root then return nil end
        local head = headPart()
        local basePos = head and head.Position or root.Position
        local mp = mainPart(model); if not mp then return nil end

        local offset = ringOffset()
        local castFrom = basePos + offset

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local itemsFolder = WS:FindFirstChild("Items")
        if itemsFolder then
            params.FilterDescendantsInstances = { lp.Character, model, itemsFolder }
        else
            params.FilterDescendantsInstances = { lp.Character, model }
        end

        local res = WS:Raycast(castFrom, Vector3.new(0, -2000, 0), params)
        local y = res and res.Position.Y or (root.Position.Y - 3)
        local h = (mp.Size.Y > 0) and (mp.Size.Y * 0.5 + 0.05) or 0.6
        local pos = Vector3.new(castFrom.X, y + h, castFrom.Z)
        local look = root.CFrame.LookVector
        return CFrame.lookAt(pos, pos + look)
    end

    local function dropNearPlayer(model)
        local r = startDragGround(model)
        Run.Heartbeat:Wait()
        local cf = groundCFAroundPlayer(model) or computeForwardDropCF()
        local snap = setCollide(model, false)
        zeroAssembly(model)
        if model:IsA("Model") then
            model:PivotTo(cf)
        else
            local p = mainPart(model); if p then p.CFrame = cf end
        end
        setCollide(model, true, snap)
        stopDragGround(r, model)
    end

    local function makeOrb(cf, name)
        local part = Instance.new("Part")
        part.Name = name; part.Shape = Enum.PartType.Ball; part.Size = Vector3.new(1.5,1.5,1.5)
        part.Material = Enum.Material.Neon; part.Color = Color3.fromRGB(255,200,50)
        part.Anchored = true; part.CanCollide = false; part.CanTouch = false; part.CanQuery = false
        part.CFrame = cf; part.Parent = WS
        local light = Instance.new("PointLight"); light.Range = 16; light.Brightness = 3; light.Parent = part
        return part
    end

    local function mergedSet(a, b)
        local t = {}; for k,v in pairs(a) do if v then t[k]=true end end; for k,v in pairs(b) do if v then t[k]=true end end; return t
    end

    local DRAG_SPEED      = 18
    local VERTICAL_MULT   = 1.35
    local STEP_WAIT       = 0.03
    local PICK_RADIUS     = 10
    local START_STAGGER   = 0.5
    local STUCK_TTL       = 6.0

    local ORB_PICK_RADIUS = 40
    local RISE_SPEED      = 12
    local RUN_SPEED       = 28

    local INFLT_ATTR = "OrbInFlightAt"
    local DELIVER_ATTR = "DeliveredAtOrb"
    local JOB_ATTR = "OrbJob"

    local delivered = setmetatable({}, { __mode = "k" })

    local function setPivot(model, cf)
        if model:IsA("Model") then
            model:PivotTo(cf)
        else
            local p = mainPart(model); if p then p.CFrame = cf end
        end
    end

    local function moveVerticalToY(model, targetY, lookDir)
        local snap = setCollide(model, false)
        zeroAssembly(model)
        while model and model.Parent do
            local pivot = model:IsA("Model") and model:GetPivot() or (mainPart(model) and mainPart(model).CFrame)
            if not pivot then break end
            local pos = pivot.Position
            local dy = targetY - pos.Y
            if math.abs(dy) <= 0.4 then break end
            local stepY = math.sign(dy) * math.min(DRAG_SPEED * VERTICAL_MULT * STEP_WAIT, math.abs(dy))
            local newPos = Vector3.new(pos.X, pos.Y + stepY, pos.Z)
            setPivot(model, CFrame.new(newPos, newPos + (lookDir or Vector3.zAxis)))
            for _,p in ipairs(getAllParts(model)) do
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end
            task.wait(STEP_WAIT)
        end
        setCollide(model, true, snap)
    end

    local function moveHorizontalToXZ(model, destXZ, yFixed)
        local snap = setCollide(model, false)
        zeroAssembly(model)
        while model and model.Parent do
            local pivot = model:IsA("Model") and model:GetPivot() or (mainPart(model) and mainPart(model).CFrame)
            if not pivot then break end
            local pos = pivot.Position
            local delta = Vector3.new(destXZ.X - pos.X, 0, destXZ.Z - pos.Z)
            local dist = delta.Magnitude
            if dist <= 1.0 then break end
            local step = math.min(DRAG_SPEED * STEP_WAIT, dist)
            local dir = delta.Unit
            local newPos = Vector3.new(pos.X, yFixed or pos.Y, pos.Z) + dir * step
            setPivot(model, CFrame.new(newPos, newPos + dir))
            for _,p in ipairs(getAllParts(model)) do
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end
            task.wait(STEP_WAIT)
        end
        setCollide(model, true, snap)
    end

    local function dropVerticalInto(model, topPos, jobId)
        if not model or not model.Parent then return end
        local snap = setCollide(model, false)
        zeroAssembly(model)
        setPivot(model, CFrame.new(topPos))
        for _,p in ipairs(getAllParts(model)) do
            p.AssemblyLinearVelocity  = Vector3.new(0, -40, 0)
            p.AssemblyAngularVelocity = Vector3.new()
        end
        setCollide(model, true, snap)
        pcall(function()
            model:SetAttribute(INFLT_ATTR, nil)
            model:SetAttribute(JOB_ATTR, nil)
            model:SetAttribute(DELIVER_ATTR, tostring(jobId))
        end)
    end

    local function itemsRootOrNil() return WS:FindFirstChild("Items") end

    local function canPick(m, center, radius, nameSet, jobId)
        if not (m and m.Parent and m:IsA("Model")) then return false end
        local itemsFolder = itemsRootOrNil()
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then return false end
        if isExcludedModel(m) or isUnderLogWall(m) then return false end
        if m.Name == "Log" and isWallVariant(m) then return false end

        local del = m:GetAttribute(DELIVER_ATTR)
        if del and tostring(del) == tostring(jobId) then return false end

        local tIn = m:GetAttribute(INFLT_ATTR)
        local jIn = m:GetAttribute(JOB_ATTR)
        if tIn then
            if jIn and tostring(jIn) ~= tostring(jobId) then
                if os.clock() - tIn >= STUCK_TTL then
                    pcall(function() m:SetAttribute(INFLT_ATTR, nil); m:SetAttribute(JOB_ATTR, nil) end)
                else
                    return false
                end
            elseif os.clock() - tIn < STUCK_TTL then
                return false
            else
                pcall(function() m:SetAttribute(INFLT_ATTR, nil); m:SetAttribute(JOB_ATTR, nil) end)
            end
        end

        local nm = m.Name or ""
        local l  = nm:lower()

        if nameSet[nm] then
        else
            if nameSet["Mossy Coin"] and (nm == "Mossy Coin" or nm:match("^Mossy Coin%d+$")) then
            elseif nameSet["Cultist"] and hasHumanoid(m) and l:find("cultist",1,true) then
            elseif nameSet["Sapling"] and nm == "Sapling" then
            elseif nameSet["Alpha Wolf Pelt"] and l:find("alpha",1,true) and l:find("wolf",1,true) then
            elseif nameSet["Bear Pelt"] and l:find("bear",1,true) and not l:find("polar",1,true) then
            elseif nameSet["Wolf Pelt"] and nm == "Wolf Pelt" then
            elseif nameSet["Bunny Foot"] and nm == "Bunny Foot" then
            elseif nameSet["Polar Bear Pelt"] and nm == "Polar Bear Pelt" then
            elseif nameSet["Arctic Fox Pelt"] and nm == "Arctic Fox Pelt" then
            elseif nameSet["Spear"] and l:find("spear",1,true) then
            elseif nameSet["Sword"] and l:find("sword",1,true) then
            elseif nameSet["Crossbow"] and l:find("crossbow",1,true) then
            elseif nameSet["Blueprint"] and l:find("blueprint",1,true) then
            elseif nameSet["Cultist Gem"] and l:find("cultist",1,true) and l:find("gem",1,true) then
            elseif nameSet["Tusk"] and l:find("tusk",1,true) then
            else
                return false
            end
        end

        local mp = mainPart(m); if not mp then return false end
        return (mp.Position - center).Magnitude <= radius
    end

    local function getCandidates(center, radius, nameSet, jobId)
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(center, radius, params) or {}
        local uniq, out = {}, {}
        for _,part in ipairs(parts) do
            local m = part:FindFirstAncestorOfClass("Model")
            if m and not uniq[m] and canPick(m, center, radius, nameSet, jobId) then
                uniq[m] = true
                out[#out+1] = m
            end
        end
        return out
    end

    local function capPerName(models, perLimit)
        if not perLimit or perLimit <= 0 then return models end
        local cnt, out = {}, {}
        for _,m in ipairs(models) do
            local nm = m.Name or ""
            cnt[nm] = (cnt[nm] or 0) + 1
            if cnt[nm] <= perLimit then out[#out+1] = m end
        end
        return out
    end

    local function startConveyor(model, orbPos, jobId)
        if not model or not model.Parent then return end
        pcall(function()
            model:SetAttribute(INFLT_ATTR, os.clock())
            model:SetAttribute(JOB_ATTR, tostring(jobId))
        end)
        local mp = mainPart(model); if not mp then return end
        local riserY = orbPos.Y - 1.0
        local lookDir = (Vector3.new(orbPos.X, mp.Position.Y, orbPos.Z) - mp.Position)
        lookDir = (lookDir.Magnitude > 0.001) and lookDir.Unit or Vector3.zAxis
        local snap = setCollide(model, false)
        zeroAssembly(model)
        while model and model.Parent do
            local pivot = model:IsA("Model") and model:GetPivot() or (mainPart(model) and mainPart(model).CFrame)
            if not pivot then break end
            local pos = pivot.Position
            local dy = riserY - pos.Y
            if math.abs(dy) <= 0.4 then break end
            local stepY = math.sign(dy) * math.min(RISE_SPEED * VERTICAL_MULT * STEP_WAIT, math.abs(dy))
            local newPos = Vector3.new(pos.X, pos.Y + stepY, pos.Z)
            setPivot(model, CFrame.new(newPos, newPos + (lookDir or Vector3.zAxis)))
            for _,p in ipairs(getAllParts(model)) do
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end
            task.wait(0.03)
        end
        setCollide(model, true, snap)
        local snap2 = setCollide(model, false)
        zeroAssembly(model)
        while model and model.Parent do
            local pivot = model:IsA("Model") and model:GetPivot() or (mainPart(model) and mainPart(model).CFrame)
            if not pivot then break end
            local pos = pivot.Position
            local delta = Vector3.new(orbPos.X - pos.X, 0, orbPos.Z - pos.Z)
            local dist = delta.Magnitude
            if dist <= 1.0 then break end
            local step = math.min(RUN_SPEED * 0.03, dist)
            local dir = delta.Unit
            local newPos = Vector3.new(pos.X, riserY, pos.Z) + dir * step
            setPivot(model, CFrame.new(newPos, newPos + dir))
            for _,p in ipairs(getAllParts(model)) do
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end
            task.wait(0.03)
        end
        setCollide(model, true, snap2)
        if model and model.Parent then
            local snap3 = setCollide(model, false)
            zeroAssembly(model)
            for _,p in ipairs(getAllParts(model)) do
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end
            setPivot(model, CFrame.new(orbPos))
            for _,p in ipairs(getAllParts(model)) do
                p.AssemblyLinearVelocity  = Vector3.new(0, -40, 0)
                p.AssemblyAngularVelocity = Vector3.new()
            end
            setCollide(model, true, snap3)
            pcall(function()
                model:SetAttribute(INFLT_ATTR, nil)
                model:SetAttribute(JOB_ATTR, nil)
                model:SetAttribute(DELIVER_ATTR, tostring(jobId))
            end)
        end
    end

    local function runConveyorWave(centerPos, orbPos, targets, jobId)
        local picked = getCandidates(centerPos, ORB_PICK_RADIUS, targets, jobId)
        if #picked == 0 then return 0 end
        picked = capPerName(picked, AMOUNT_TO_BRING)
        local active = 0
        local function spawnOne(m)
            if m and m.Parent then
                active += 1
                task.spawn(function()
                    startConveyor(m, orbPos, jobId)
                    active -= 1
                end)
            end
        end
        for i = 1, #picked do
            while active >= CONVEYOR_MAX_ACTIVE do Run.Heartbeat:Wait() end
            spawnOne(picked[i])
            task.wait(START_STAGGER)
        end
        local deadline = os.clock() + math.max(5, START_STAGGER * #picked + 5)
        while active > 0 and os.clock() < deadline do
            Run.Heartbeat:Wait()
        end
        return #picked
    end

    local function runConveyorJob(centerPos, orbPos, targets, jobId)
        while true do
            local moved = runConveyorWave(centerPos, orbPos, targets, jobId)
            if moved == 0 then break end
        end
    end

    local function burnNearby()
        local camp = CAMPFIRE_PATH; if not camp then return end
        local root = hrp(); if not root then return end
        local jobId = ("%d-%d"):format(os.time(), math.random(1,1e6))
        local orb2 = makeOrb(root.CFrame, "orb2")
        local campCenter = (mainPart(camp) and mainPart(camp).CFrame or camp:GetPivot())
        local orb1 = makeOrb(campCenter + Vector3.new(0, ORB_OFFSET_Y + 10, 0), "orb1")
        local targets = mergedSet(fuelSet, cookSet)
        runConveyorJob(orb2.Position, orb1.Position, targets, jobId)
        if orb1 then orb1:Destroy() end
        if orb2 then orb2:Destroy() end
    end

    local function scrapNearby()
        local scr = SCRAPPER_PATH; if not scr then return end
        local root = hrp(); if not root then return end
        local jobId = ("%d-%d"):format(os.time(), math.random(1,1e6))
        local orb2 = makeOrb(root.CFrame, "orb2")
        local scrCenter = (mainPart(scr) and mainPart(scr).CFrame or scr:GetPivot())
        local orb1 = makeOrb(scrCenter + Vector3.new(0, ORB_OFFSET_Y + 10, 0), "orb1")
        local targets = mergedSet(junkSet, scrapAlso)
        runConveyorJob(orb2.Position, orb1.Position, targets, jobId)
        if orb1 then orb1:Destroy() end
        if orb2 then orb2:Destroy() end
    end

    local function setFromChoice(choice)
        local s = {}
        if type(choice) == "table" then
            for _,v in ipairs(choice) do if v and v ~= "" then s[v]=true end end
        elseif choice and choice ~= "" then
            s[choice] = true
        end
        return s
    end

    local selJunkMany, selFuelMany, selFoodMany, selMedicalMany, selWAMany, selMiscMany, selPeltMany =
        {},{},{},{},{},{},{}

    local function itemsRootOrNil2() return WS:FindFirstChild("Items") end

    local function nameMatches(selectedSet, m)
        local itemsFolder = itemsRootOrNil2()
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then return false end
        local nm = m and m.Name or ""
        if selectedSet[nm] then return true end
        local l = nm:lower()
        if selectedSet["Mossy Coin"] and (nm == "Mossy Coin" or nm:match("^Mossy Coin%d+$")) then return true end
        if selectedSet["Cultist"] and m and m:IsA("Model") and l:find("cultist",1,true) and hasHumanoid(m) then return true end
        if selectedSet["Sapling"] and nm == "Sapling" then return true end
        if selectedSet["Alpha Wolf Pelt"] and l:find("alpha",1,true) and l:find("wolf",1,true) then return true end
        if selectedSet["Bear Pelt"] and l:find("bear",1,true) and not l:find("polar",1,true) then return true end
        if selectedSet["Wolf Pelt"] and nm == "Wolf Pelt" then return true end
        if selectedSet["Bunny Foot"] and nm == "Bunny Foot" then return true end
        if selectedSet["Polar Bear Pelt"] and nm == "Polar Bear Pelt" then return true end
        if selectedSet["Arctic Fox Pelt"] and nm == "Arctic Fox Pelt" then return true end
        if selectedSet["Spear"] and l:find("spear",1,true) then return true end
        if selectedSet["Sword"] and l:find("sword",1,true) then return true end
        if selectedSet["Crossbow"] and l:find("crossbow",1,true) then return true end
        if selectedSet["Blueprint"] and l:find("blueprint",1,true) then return true end
        if selectedSet["Cultist Gem"] and l:find("cultist",1,true) and l:find("gem",1,true) then return true end
        if selectedSet["Tusk"] and l:find("tusk",1,true) then return true end
        return false
    end

    local function fastBringToGround(selectedSet)
        if not selectedSet or next(selectedSet) == nil then return end
        dropCounter = 0
        local perNameCount, seenModel, queue = {}, {}, {}
        local itemsFolder = itemsRootOrNil2(); if not itemsFolder then return end

        for _,d in ipairs(itemsFolder:GetDescendants()) do
            local m
            if d:IsA("Model") then
                m = d
            elseif d:IsA("BasePart") and d.Parent and d.Parent:IsA("Model") then
                m = d.Parent
            end
            if m and not seenModel[m] then
                seenModel[m] = true
                if not isExcludedModel(m) and not isUnderLogWall(m) then
                    local nm = m.Name
                    if not (nm == "Log" and isWallVariant(m)) then
                        if nameMatches(selectedSet, m) then
                            perNameCount[nm] = (perNameCount[nm] or 0) + 1
                            if perNameCount[nm] <= AMOUNT_TO_BRING then
                                local mp = mainPart(m)
                                if mp then queue[#queue+1] = m end
                            end
                        end
                    end
                end
            end
        end

        for i=1,#queue do
            dropNearPlayer(queue[i])
            if i % 25 == 0 then Run.Heartbeat:Wait() end
        end
    end

    local function multiSelectDropdown(args)
        return tab:Dropdown({
            Title = args.title,
            Values = args.values,
            Multi = true,
            AllowNone = true,
            Callback = function(choice) args.setter(setFromChoice(choice)) end
        })
    end

    tab:Section({ Title = "Actions" })
    tab:Button({ Title = "Burn/Cook Nearby (Fuel + Raw Food)", Callback = burnNearby })
    tab:Button({ Title = "Scrap Nearby Junk(+Log/Chair)",      Callback = scrapNearby })

    tab:Section({ Title = "Junk → Ground (Multi)" })
    multiSelectDropdown({ title = "Select Junk Items", values = junkItems, setter = function(s) selJunkMany = s end })
    tab:Button({ Title = "Bring Selected (Fast)", Callback = function() fastBringToGround(selJunkMany) end })

    tab:Section({ Title = "Fuel → Ground (Multi)" })
    multiSelectDropdown({ title = "Select Fuel Items", values = fuelItems, setter = function(s) selFuelMany = s end })
    tab:Button({ Title = "Bring Selected (Fast)", Callback = function() fastBringToGround(selFuelMany) end })

    tab:Section({ Title = "Food → Ground (Multi)" })
    multiSelectDropdown({ title = "Select Food Items", values = foodItems, setter = function(s) selFoodMany = s end })
    tab:Button({ Title = "Bring Selected (Fast)", Callback = function() fastBringToGround(selFoodMany) end })

    tab:Section({ Title = "Medical → Ground (Multi)" })
    multiSelectDropdown({ title = "Select Medical Items", values = medicalItems, setter = function(s) selMedicalMany = s end })
    tab:Button({ Title = "Bring Selected (Fast)", Callback = function() fastBringToGround(selMedicalMany) end })

    tab:Section({ Title = "Weapons/Armor → Ground (Multi)" })
    multiSelectDropdown({ title = "Select Weapons/Armor", values = weaponsArmor, setter = function(s) selWAMany = s end })
    tab:Button({ Title = "Bring Selected (Fast)", Callback = function() fastBringToGround(selWAMany) end })

    tab:Section({ Title = "Ammo & Misc → Ground (Multi)" })
    multiSelectDropdown({ title = "Select Ammo/Misc", values = ammoMisc, setter = function(s) selMiscMany = s end })
    tab:Button({ Title = "Bring Selected (Fast)", Callback = function() fastBringToGround(selMiscMany) end })

    tab:Section({ Title = "Pelts → Ground (Multi)" })
    multiSelectDropdown({ title = "Select Pelts", values = pelts, setter = function(s) selPeltMany = s end })
    tab:Button({ Title = "Bring Selected (Fast)", Callback = function() fastBringToGround(selPeltMany) end })

    do
        local ORB_RADIUS     = 2.2
        local ORB_STUCK_SECS = 0.9
        local ORB_FALL_DELTA = 2.5
        local ORB_MAX_KICKS  = 2
        local ORB_RESET_UP   = 1.2
        local ORB_KICK_VY    = -60
        local GUARD_HZ       = 12

        local function campOrbPos()
            local camp = CAMPFIRE_PATH
            if not camp then return nil end
            local c = (mainPart(camp) and mainPart(camp).CFrame or camp:GetPivot()).Position
            return Vector3.new(c.X, c.Y + ORB_OFFSET_Y + 10, c.Z)
        end
        local function scrapOrbPos()
            local scr = SCRAPPER_PATH
            if not scr then return nil end
            local c = (mainPart(scr) and mainPart(scr).CFrame or scr:GetPivot()).Position
            return Vector3.new(c.X, c.Y + ORB_OFFSET_Y + 10, c.Z)
        end
        local function liveOrb1Pos()
            local o = WS:FindFirstChild("orb1")
            return o and o:IsA("BasePart") and o.Position or nil
        end

        local function kickDown(m, orbY)
            local mp = mainPart(m); if not mp then return end
            pcall(function() mp.Anchored = false end)
            pcall(function() mp.AssemblyLinearVelocity  = Vector3.new(0, ORB_KICK_VY, 0) end)
            pcall(function() mp.AssemblyAngularVelocity = Vector3.new() end)
            pcall(function() mp:SetNetworkOwner(nil) end)
            pcall(function() if mp.SetNetworkOwnershipAuto then mp:SetNetworkOwnershipAuto() end end)
            pcall(function()
                local p = mp.Position
                mp.CFrame = CFrame.new(Vector3.new(p.X, orbY + ORB_RESET_UP, p.Z))
            end)
        end

        local watched = setmetatable({}, {__mode="k"})
        local acc = 0
        Run.Heartbeat:Connect(function(dt)
            acc += dt
            if acc < (1 / GUARD_HZ) then return end
            acc = 0

            local positions = {}
            local pLive = liveOrb1Pos(); if pLive then positions[#positions+1] = pLive end
            local pCamp = campOrbPos();  if pCamp then positions[#positions+1] = pCamp end
            local pScr  = scrapOrbPos(); if pScr  then positions[#positions+1] = pScr  end
            if #positions == 0 then return end

            local items = WS:FindFirstChild("Items"); if not items then return end
            for _,m in ipairs(items:GetChildren()) do
                if not m:IsA("Model") then continue end
                local mp = mainPart(m); if not mp then continue end

                local nearest, orbY = nil, nil
                local pos = mp.Position
                for _,o in ipairs(positions) do
                    local d = (pos - o).Magnitude
                    if d <= ORB_RADIUS then nearest, orbY = true, o.Y; break end
                end

                if nearest then
                    local rec = watched[m]
                    if not rec then
                        watched[m] = {t=os.clock(), y0=pos.Y, kicks=0}
                    else
                        local fell = (rec.y0 - pos.Y) >= ORB_FALL_DELTA or pos.Y < (orbY - ORB_FALL_DELTA)
                        if fell then
                            watched[m] = nil
                        elseif (os.clock() - rec.t) >= ORB_STUCK_SECS then
                            if rec.kicks < ORB_MAX_KICKS then
                                rec.kicks += 1
                                rec.t = os.clock()
                                rec.y0 = pos.Y
                                kickDown(m, orbY)
                            else
                                watched[m] = nil
                            end
                        end
                    end
                else
                    watched[m] = nil
                end
            end
        end)
    end
end
