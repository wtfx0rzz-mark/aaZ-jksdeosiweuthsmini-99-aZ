return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local RS      = C.Services.RS
    local Run     = C.Services.Run or game:GetService("RunService")
    local lp      = Players.LocalPlayer

    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Bring
    assert(tab, "Bring tab not found in UI")

    local AMOUNT_TO_BRING   = 500
    local COLLIDE_OFF_SEC   = 0.22

    local DROP_ABOVE_HEAD_STUDS = 10
    local FALLBACK_UP       = 5
    local FALLBACK_AHEAD    = 2

    local PICK_RADIUS       = 15
    local ORB_OFFSET_Y      = 30
    local EXCLUDE_DROP_RADIUS = 0.9

    local IN_FLIGHT_MAX     = 8
    local LAUNCH_INTERVAL   = 0.10
    local LIFT_TIME         = 0.75
    local SLIDE_SPEED       = 22.0
    local ITEM_TIMEOUT      = 3.0
    local IDLE_TIMEOUT      = 1.6
    local RESCAN_INTERVAL   = 0.35
    local POST_DROP_HOLD    = 2.0

    local LINE_SPACING      = 1.35
    local LINE_SLOTS        = 14
    local LINE_BACK         = LINE_SPACING * LINE_SLOTS

    local CAMPFIRE_PATH = workspace.Map.Campground.MainFire
    local SCRAPPER_PATH = workspace.Map.Campground.Scrapper

    local junkItems    = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine","UFO Junk","UFO Component"}
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel","Biofuel"}
    local foodItems    = {"Morsel","Cooked Morsel","Steak","Cooked Steak","Ribs","Cooked Ribs","Cake","Berry","Carrot","Chilli","Stew","Pumpkin","Hearty Stew","Corn","BBQ ribs","Apple","Mackerel"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe","Chainsaw","Crossbow","Katana","Kunai","Laser cannon","Laser sword","Morningstar","Riot shield","Spear","Tactical Shotgun","Wildfire"}
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling","Basketball","Blueprint","Diamond","Forest Gem","Key","Flashlight","Taming flute"}
    local pelts        = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Polar Bear Pelt","Arctic Fox Pelt"}

    local fuelSet, junkSet, cookSet, scrapAlso = {}, {}, {}, {}
    for _,n in ipairs(fuelItems)  do fuelSet[n] = true end
    for _,n in ipairs(junkItems)  do junkSet[n] = true end
    cookSet["Morsel"] = true; cookSet["Steak"] = true; cookSet["Ribs"] = true
    scrapAlso["Log"] = true;  scrapAlso["Chair"] = true

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local function headPart()
        local ch = lp.Character
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

    local function itemsRoot()
        return WS:FindFirstChild("Items")
    end

    local function getRemote(...)
        local re = RS:FindFirstChild("RemoteEvents"); if not re then return nil end
        for _,n in ipairs({...}) do local x=re:FindFirstChild(n); if x then return x end end
        return nil
    end
    local function resolveRemotes()
        return {
            StartDrag = getRemote("RequestStartDraggingItem","StartDraggingItem"),
            CookItem  = getRemote("RequestCookItem","CookItem"),
            BurnItem  = getRemote("RequestBurnItem","BurnItem","RequestFireAdd"),
            ScrapItem = getRemote("RequestScrapItem","ScrapItem","RequestWorkbenchScrap"),
            StopDrag  = getRemote("StopDraggingItem","RequestStopDraggingItem"),
        }
    end
    local function startDragRemote(r, model)
        if r and r.StartDrag then pcall(function() r.StartDrag:FireServer(model) end) end
    end
    local function stopDragRemote(r)
        if r and r.StopDrag then pcall(function() r.StopDrag:FireServer(Instance.new("Model")) end) end
    end

    local function sortedFarthest(list)
        local r = hrp(); if not r then return list end
        table.sort(list, function(a,b)
            return (a.part.Position - r.Position).Magnitude > (b.part.Position - r.Position).Magnitude
        end)
        return list
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
    local function scrCenterCF(scr)
        local p = mainPart(scr) or scr.PrimaryPart
        return (p and p.CFrame) or scr:GetPivot()
    end

    local function groundCFAroundPlayer(model)
        local root = hrp(); if not root then return nil end
        local head = headPart()
        local basePos = head and head.Position or root.Position
        local mp = mainPart(model); if not mp then return nil end
        local pos = basePos
        local y = basePos.Y - 3
        local h = (mp.Size.Y > 0) and (mp.Size.Y * 0.5 + 0.05) or 0.6
        local final = Vector3.new(pos.X, y + h, pos.Z)
        local look = root.CFrame.LookVector
        return CFrame.lookAt(final, final + look)
    end
    local function dropNearPlayer(model)
        local r = resolveRemotes()
        startDragRemote(r, model)
        Run.Heartbeat:Wait()
        local cf = groundCFAroundPlayer(model) or computeForwardDropCF()
        moveModel(model, cf)
        stopDragRemote(r)
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

    local function alive(m)
        local root = itemsRoot()
        return m and m.Parent and root and m:IsA("Model") and m:IsDescendantOf(root)
    end

    local reservedUntil = setmetatable({}, {__mode="k"})
    local function isReserved(m)
        local t = reservedUntil[m]
        return t and (os.clock() < t)
    end
    local function reserve(m, seconds)
        reservedUntil[m] = os.clock() + (seconds or 2)
    end

    local function modelsNear(centerPos, radius, nameSet, excludeXY, excludeRadius)
        local out = {}
        local root = itemsRoot(); if not root then return out end
        for _,d in ipairs(root:GetDescendants()) do
            if d:IsA("Model") and not isExcludedModel(d) and nameSet[d.Name] and not isUnderLogWall(d) then
                if d.Name == "Log" and isWallVariant(d) then
                else
                    local mp = mainPart(d)
                    if mp then
                        local within = (mp.Position - centerPos).Magnitude <= radius
                        if within and excludeXY and excludeRadius then
                            local dxz = Vector3.new(mp.Position.X, 0, mp.Position.Z) - Vector3.new(excludeXY.X, 0, excludeXY.Z)
                            if dxz.Magnitude <= excludeRadius then
                                within = false
                            end
                        end
                        if within and not isReserved(d) then
                            out[#out+1] = d
                        end
                    end
                end
            end
        end
        return out
    end
    local function mergedSet(a, b)
        local t = {}; for k,v in pairs(a) do if v then t[k]=true end end; for k,v in pairs(b) do if v then t[k]=true end end; return t
    end

    local function easeOut(t) return 1 - (1 - t) * (1 - t) end
    local function liftTo(model, targetCF, duration)
        local t0 = os.clock()
        local start = model:GetPivot()
        local snap = setCollide(model, false)
        zeroAssembly(model)
        while alive(model) and (os.clock() - t0) < duration do
            local a = easeOut((os.clock() - t0) / duration)
            local pos = start.Position:Lerp(targetCF.Position, a)
            local cf = CFrame.lookAt(pos, pos + Vector3.new(0, -1, 0))
            if model:IsA("Model") then model:PivotTo(cf) else local p=mainPart(model); if p then p.CFrame=cf end end
            Run.Heartbeat:Wait()
        end
        setCollide(model, true, snap)
    end
    local function slideAlong(model, fromPos, toPos, speed)
        local dist = (toPos - fromPos).Magnitude
        local dur = math.max(0.01, dist / math.max(1, speed))
        local t0 = os.clock()
        while alive(model) and (os.clock() - t0) < dur do
            local a = (os.clock() - t0) / dur
            local pos = fromPos:Lerp(toPos, a)
            local cf = CFrame.lookAt(pos, pos + Vector3.new(0, -1, 0))
            if model:IsA("Model") then model:PivotTo(cf) else local p=mainPart(model); if p then p.CFrame=cf end end
            Run.Heartbeat:Wait()
        end
    end

    local function raiseConveyorAndDrop(model, orbPos, beltDir)
        local r = resolveRemotes()
        local t0 = os.clock()
        reserve(model, POST_DROP_HOLD)
        startDragRemote(r, model)
        Run.Heartbeat:Wait()
        if not alive(model) then stopDragRemote(r); return end

        local startBack = LINE_BACK + (math.random() * 0.75)
        local startPos  = orbPos - beltDir * startBack
        liftTo(model, CFrame.new(startPos), LIFT_TIME)
        if not alive(model) then stopDragRemote(r); return end

        slideAlong(model, startPos, orbPos, SLIDE_SPEED)
        if not alive(model) then stopDragRemote(r); return end

        for _,p in ipairs(getAllParts(model)) do p.AssemblyLinearVelocity = Vector3.new(0, -6, 0) end
        stopDragRemote(r)

        reserve(model, POST_DROP_HOLD)
        if os.clock() - t0 > ITEM_TIMEOUT then return end
    end

    local function beltDirFrom(targetPos)
        local h = hrp()
        local look = h and h.CFrame.LookVector or Vector3.new(0,0,-1)
        local dir  = -look
        if dir.Magnitude < 0.1 then dir = Vector3.new(0,0,-1) end
        return dir.Unit
    end

    local function processNearby(targets, targetCF)
        local h = hrp(); if not h then return end
        local scanCenter = h.Position
        local beltDir = beltDirFrom(targetCF.Position)

        local orbPick = makeOrb(CFrame.new(scanCenter), "orb_pick")
        local orbDrop = makeOrb(targetCF + Vector3.new(0, ORB_OFFSET_Y, 0), "orb_drop")

        local inflight = 0
        local queue = {}
        local lastActivity = os.clock()
        local lastLaunch = 0
        local lastScan = 0

        local function enqueue()
            local list = modelsNear(scanCenter, PICK_RADIUS, targets, orbDrop.Position, EXCLUDE_DROP_RADIUS)
            for i=1,#list do
                local m = list[i]
                if alive(m) and not isReserved(m) then
                    queue[#queue+1] = m
                    reserve(m, 1.0)
                end
            end
        end

        enqueue()

        while true do
            while inflight < IN_FLIGHT_MAX and #queue > 0 do
                if os.clock() - lastLaunch < LAUNCH_INTERVAL then break end
                local m = table.remove(queue, 1)
                if alive(m) then
                    inflight += 1
                    lastLaunch = os.clock()
                    task.spawn(function()
                        pcall(function() raiseConveyorAndDrop(m, orbDrop.Position, beltDir) end)
                        inflight -= 1
                        lastActivity = os.clock()
                    end)
                end
            end

            if os.clock() - lastScan >= RESCAN_INTERVAL then
                lastScan = os.clock()
                enqueue()
            end

            if #queue == 0 and inflight == 0 and (os.clock() - lastActivity) > IDLE_TIMEOUT then
                break
            end

            Run.Heartbeat:Wait()
        end

        task.delay(1, function() if orbPick then orbPick:Destroy() end if orbDrop then orbDrop:Destroy() end end)
    end

    local function burnNearby()
        local camp = CAMPFIRE_PATH; if not camp then return end
        local center = fireCenterCF(camp).Position
        local cf = CFrame.new(center)
        local targets = mergedSet(fuelSet, cookSet)
        processNearby(targets, cf)
    end

    local function scrapNearby()
        local scr = SCRAPPER_PATH; if not scr then return end
        local center = scrCenterCF(scr).Position
        local cf = CFrame.new(center)
        local targets = mergedSet(junkSet, scrapAlso)
        processNearby(targets, cf)
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
    local function nameMatches(selectedSet, m)
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
        return false
    end

    local function fastBringToGround(selectedSet)
        if not selectedSet or next(selectedSet) == nil then return end
        local perNameCount = {}
        local seenModel = {}
        local queue = {}
        local itemsFolder = itemsRoot(); if not itemsFolder then return end
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

    local selJunkMany, selFuelMany, selFoodMany, selMedicalMany, selWAMany, selMiscMany, selPeltMany =
        {},{},{},{},{},{},{}

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
    tab:Button({ Title = "Scrap Nearby Junk(+Log/Chair)",     Callback = scrapNearby })

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
end
