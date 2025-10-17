return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local RS      = C.Services.RS
    local lp      = Players.LocalPlayer

    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Bring
    assert(tab, "Bring tab not found in UI")

    local AMOUNT_TO_BRING       = 100
    local PER_ITEM_DELAY        = 0.06
    local COLLIDE_OFF_SEC       = 0.22
    local DROP_ABOVE_HEAD_STUDS = 5
    local FALLBACK_UP           = 5
    local FALLBACK_AHEAD        = 2
    local NEARBY_RADIUS         = 24
    local ORB_OFFSET_Y          = 15
    local HANDOFF_UP            = 0.6
    local HANDOFF_MARGIN        = 1.25
    local EJECT_OFFSET          = 1.2
    local EJECT_SPEED           = 10
    local COOK_FIND_R           = 8
    local COOK_FIND_DELAY       = 0.12

    local CAMPFIRE_PATH = workspace.Map.Campground.MainFire
    local SCRAPPER_PATH = workspace.Map.Campground.Scrapper

    local junkItems    = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems    = {"Morsel","Cooked Morsel","Steak","Cooked Steak","Ribs","Cooked Ribs","Cake","Berry","Carrot"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe"}
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling"}
    local pelts        = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Polar Bear Pelt"}

    local selJunk, selFuel, selFood, selMedical, selWA, selMisc, selPelt =
        junkItems[1], fuelItems[1], foodItems[1], medicalItems[1], weaponsArmor[1], ammoMisc[1], pelts[1]

    local fuelSet, junkSet, cookSet, scrapAlso = {}, {}, {}, {}
    for _,n in ipairs(fuelItems) do fuelSet[n] = true end
    for _,n in ipairs(junkItems) do junkSet[n] = true end
    cookSet["Morsel"] = true; cookSet["Steak"] = true; cookSet["Ribs"] = true
    scrapAlso["Log"] = true; scrapAlso["Chair"] = true

    local RAW_TO_COOKED = { ["Morsel"]="Cooked Morsel", ["Steak"]="Cooked Steak", ["Ribs"]="Cooked Ribs" }

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local function headPart()
        local ch = lp.Character
        return ch and ch:FindFirstChild("Head")
    end
    local function isExcludedModel(m)
        if not (m and m:IsA("Model")) then return false end
        local n = m.Name:lower()
        if n == "pelt trader" then return true end
        if n:find("trader") or n:find("shopkeeper") then return true end
        return false
    end
    local function hasHumanoid(model)
        if not (model and model:IsA("Model")) then return false end
        return model:FindFirstChildOfClass("Humanoid") ~= nil
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
        local re = RS:FindFirstChild("RemoteEvents")
        if not re then return nil end
        for _,n in ipairs({...}) do
            local x = re:FindFirstChild(n)
            if x then return x end
        end
        return nil
    end

    local StartDrag, BurnItem, CookItem, ScrapItem, StopDrag
    local function resolveRemotes()
        StartDrag = StartDrag or getRemote("RequestStartDraggingItem","StartDraggingItem")
        BurnItem  = BurnItem  or getRemote("RequestBurnItem","BurnItem","RequestFireAdd")
        CookItem  = CookItem  or getRemote("RequestCookItem","CookItem")
        ScrapItem = ScrapItem or getRemote("RequestScrapItem","ScrapItem","RequestWorkbenchScrap")
        StopDrag  = StopDrag  or getRemote("StopDraggingItem","RequestStopDraggingItem")
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
        for _,p in ipairs(parts) do
            snap[p] = p.CanCollide
            p.CanCollide = false
        end
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

    local function collectByNameLoose(name, limit)
        local found, n = {}, 0
        for _,d in ipairs(WS:GetDescendants()) do
            if (d:IsA("Model") or d:IsA("BasePart")) and d.Name == name then
                local model = d:IsA("Model") and d or d.Parent
                if model and model:IsA("Model") and not isExcludedModel(model) then
                    local mp = mainPart(model)
                    if mp then
                        n = n + 1
                        found[#found+1] = {model=model, part=mp}
                        if limit and n >= limit then break end
                    end
                end
            end
        end
        return sortedFarthest(found)
    end
    local function collectMossyCoins(limit)
        local out, n = {}, 0
        for _,m in ipairs(WS:GetDescendants()) do
            if m:IsA("Model") and not isExcludedModel(m) then
                local nm = m.Name
                if nm == "Mossy Coin" or nm:match("^Mossy Coin%d+$") then
                    local mp = m:FindFirstChild("Main") or m:FindFirstChildWhichIsA("BasePart")
                    if mp then
                        n = n + 1
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
        for _,m in ipairs(WS:GetDescendants()) do
            if m:IsA("Model") and m.Name:lower():find("cultist",1,true) and not isExcludedModel(m) then
                if hasHumanoid(m) then
                    local mp = mainPart(m)
                    if mp then
                        n = n + 1
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
        local items = WS:FindFirstChild("Items")
        if not items then return out end
        for _,m in ipairs(items:GetChildren()) do
            if m:IsA("Model") and m.Name == "Sapling" and not isExcludedModel(m) then
                local mp = mainPart(m)
                if mp then
                    n = n + 1
                    out[#out+1] = {model=m, part=mp}
                    if limit and n >= limit then break end
                end
            end
        end
        return sortedFarthest(out)
    end
    local function collectPelts(which, limit)
        local out, n = {}, 0
        for _,m in ipairs(WS:GetDescendants()) do
            if m:IsA("Model") and not isExcludedModel(m) then
                local nm, ok = m.Name, false
                ok = ok or (which=="Bunny Foot" and nm=="Bunny Foot")
                ok = ok or (which=="Wolf Pelt" and nm=="Wolf Pelt")
                ok = ok or (which=="Alpha Wolf Pelt" and nm:lower():find("alpha") and nm:lower():find("wolf"))
                ok = ok or (which=="Bear Pelt" and nm:lower():find("bear") and not nm:lower():find("polar"))
                ok = ok or (which=="Polar Bear Pelt" and nm=="Polar Bear Pelt")
                if ok then
                    local mp = mainPart(m)
                    if mp then
                        n = n + 1
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
        if model:IsA("Model") then
            model:PivotTo(above)
        else
            local p = mainPart(model)
            if p then p.CFrame = above end
        end
        for _,p in ipairs(getAllParts(model)) do
            p.AssemblyLinearVelocity = Vector3.new(0,-8,0)
        end
        task.delay(COLLIDE_OFF_SEC, function() setCollide(model, true, snap) end)
    end

    local function startDrag(model)
        resolveRemotes()
        if StartDrag then pcall(function() StartDrag:FireServer(model) end) end
    end
    local function stopDrag()
        resolveRemotes()
        if StopDrag then pcall(function() StopDrag:FireServer(Instance.new("Model")) end) end
    end

    local function moveModel(model, cf)
        local snap = setCollide(model, false)
        zeroAssembly(model)
        if model:IsA("Model") then
            model:PivotTo(cf)
        else
            local p = mainPart(model)
            if p then p.CFrame = cf end
        end
        task.delay(COLLIDE_OFF_SEC, function() setCollide(model, true, snap) end)
    end

    local function fireCenterCF(fire)
        local p = fire:FindFirstChild("Center") or fire:FindFirstChild("InnerTouchZone") or mainPart(fire) or fire.PrimaryPart
        return (p and p.CFrame) or fire:GetPivot()
    end
    local function edgeHandoffCF(fire)
        local centerCF = fireCenterCF(fire)
        local center = centerCF.Position
        local dirXZ = Vector3.new(0,0,0)
        local r = hrp()
        if r then
            local toPlayer = r.Position - center
            dirXZ = Vector3.new(toPlayer.X,0,toPlayer.Z)
        end
        if dirXZ.Magnitude < 0.01 then dirXZ = Vector3.new(1,0,0) end
        dirXZ = dirXZ.Unit
        local size = Vector3.new(4,4,4)
        if fire:IsA("Model") then
            pcall(function() size = fire:GetExtentsSize() end)
        elseif fire:IsA("BasePart") then
            size = fire.Size
        end
        local halfX, halfZ, halfY = size.X*0.5, size.Z*0.5, size.Y*0.5
        local edge = center + Vector3.new(dirXZ.X*(math.max(halfX,1)-HANDOFF_MARGIN), halfY + HANDOFF_UP, dirXZ.Z*(math.max(halfZ,1)-HANDOFF_MARGIN))
        return CFrame.lookAt(edge, edge + dirXZ)
    end

    local function nudgeModelOut(model, fromPos)
        local mp = mainPart(model); if not mp then return end
        local dir = Vector3.new(mp.Position.X-fromPos.X, 0, mp.Position.Z-fromPos.Z)
        if dir.Magnitude < 0.01 then dir = Vector3.new(1,0,0) end
        dir = dir.Unit
        local snap = setCollide(model, false)
        if model:IsA("Model") then
            model:PivotTo(model:GetPivot() + dir*EJECT_OFFSET + Vector3.new(0,0.25,0))
        else
            mp.CFrame = mp.CFrame + CFrame.new(dir*EJECT_OFFSET + Vector3.new(0,0.25,0)).Position
        end
        for _,p in ipairs(getAllParts(model)) do
            p.AssemblyLinearVelocity = dir*EJECT_SPEED + Vector3.new(0,5,0)
        end
        task.delay(0.12, function() setCollide(model, true, snap) end)
    end

    local function findCookedNearFire(fire, cookedName)
        local cpos = fireCenterCF(fire).Position
        local best, bestD
        for _,m in ipairs(WS:GetDescendants()) do
            if m:IsA("Model") and m.Name == cookedName and not isExcludedModel(m) then
                local mp = mainPart(m)
                if mp then
                    local d = (mp.Position - cpos).Magnitude
                    if d <= COOK_FIND_R and (not bestD or d < bestD) then best, bestD = m, d end
                end
            end
        end
        return best
    end

    local function burnFlow(model, campfire)
        resolveRemotes()
        startDrag(model)
        moveModel(model, edgeHandoffCF(campfire))
        local ok = false
        if BurnItem then ok = pcall(function() BurnItem:FireServer(campfire, Instance.new("Model")) end) end
        if not ok then pivotOverTarget(model, campfire) end
        stopDrag()
    end

    local function cookFlow(model, campfire)
        resolveRemotes()
        local cookedName = RAW_TO_COOKED[model.Name]
        startDrag(model)
        moveModel(model, edgeHandoffCF(campfire))
        local ok = false
        if CookItem then ok = pcall(function() CookItem:FireServer(campfire, Instance.new("Model")) end) end
        if not ok then pivotOverTarget(model, campfire) end
        stopDrag()
        task.delay(COOK_FIND_DELAY, function()
            if cookedName then
                local cooked = findCookedNearFire(campfire, cookedName)
                if cooked then nudgeModelOut(cooked, fireCenterCF(campfire).Position) end
            end
        end)
    end

    local function scrapFlow(model, scrapper)
        resolveRemotes()
        startDrag(model)
        local ok = false
        if ScrapItem then ok = pcall(function() ScrapItem:FireServer(scrapper, Instance.new("Model")) end) end
        if not ok then pivotOverTarget(model, scrapper) end
        stopDrag()
    end

    local function dropNearPlayer(model)
        local cf = computeForwardDropCF(); if not cf then return end
        local snap = setCollide(model, false)
        zeroAssembly(model)
        if model:IsA("Model") then
            model:PivotTo(cf)
        else
            local p = mainPart(model)
            if p then p.CFrame = cf end
        end
        for _,p in ipairs(getAllParts(model)) do
            p.AssemblyLinearVelocity = Vector3.new(0, -6, 0)
        end
        task.delay(COLLIDE_OFF_SEC, function() setCollide(model, true, snap) end)
    end

    local function makeOrb(cf, name)
        local part = Instance.new("Part")
        part.Name = name
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(1.5,1.5,1.5)
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(255,200,50)
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CFrame = cf
        part.Parent = WS
        local light = Instance.new("PointLight")
        light.Range = 16
        light.Brightness = 3
        light.Parent = part
        return part
    end

    local function modelsNear(pos, radius, nameSet, seen)
        local out = {}
        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") and not isExcludedModel(d) and nameSet[d.Name] and not seen[d] then
                local mp = mainPart(d)
                if mp and (mp.Position - pos).Magnitude <= radius then
                    out[#out+1] = d
                    seen[d] = true
                end
            end
        end
        return out
    end

    local function mergedSet(a, b)
        local t = {}
        for k,v in pairs(a) do if v then t[k] = true end end
        for k,v in pairs(b) do if v then t[k] = true end end
        return t
    end

    local function burnNearby()
        local camp = CAMPFIRE_PATH; if not camp then return end
        local root = hrp(); if not root then return end
        local orb2 = makeOrb(root.CFrame, "orb2")
        local orb1 = makeOrb((mainPart(camp) and mainPart(camp).CFrame or camp:GetPivot()) + Vector3.new(0, ORB_OFFSET_Y, 0), "orb1")
        local seen, targets = {}, mergedSet(fuelSet, cookSet)
        while true do
            local list = modelsNear(orb2.Position, NEARBY_RADIUS, targets, seen)
            if #list == 0 then break end
            for _,m in ipairs(list) do
                if cookSet[m.Name] then cookFlow(m, camp) else burnFlow(m, camp) end
                task.wait(PER_ITEM_DELAY)
            end
            task.wait(0.05)
        end
        task.delay(1, function() if orb1 then orb1:Destroy() end if orb2 then orb2:Destroy() end end)
    end

    local function scrapNearby()
        local scr = SCRAPPER_PATH; if not scr then return end
        local root = hrp(); if not root then return end
        local orb2 = makeOrb(root.CFrame, "orb2")
        local orb1 = makeOrb((mainPart(scr) and mainPart(scr).CFrame or scr:GetPivot()) + Vector3.new(0, ORB_OFFSET_Y, 0), "orb1")
        local seen, targets = {}, mergedSet(junkSet, scrapAlso)
        while true do
            local list = modelsNear(orb2.Position, NEARBY_RADIUS, targets, seen)
            if #list == 0 then break end
            for _,m in ipairs(list) do
                scrapFlow(m, scr)
                task.wait(PER_ITEM_DELAY)
            end
            task.wait(0.05)
        end
        task.delay(1, function() if orb1 then orb1:Destroy() end if orb2 then orb2:Destroy() end end)
    end

    local function bringSelected(name, count)
        local want = tonumber(count) or 0
        if want <= 0 then return end
        local list
        if name == "Mossy Coin" then
            list = collectMossyCoins(want)
        elseif name == "Cultist" then
            list = collectCultists(want)
        elseif name == "Sapling" then
            list = collectSaplings(want)
        elseif table.find(pelts, name) then
            list = collectPelts(name, want)
        else
            list = collectByNameLoose(name, want)
        end
        if #list == 0 then return end
        local doCook = cookSet[name]
        local doBurn = fuelSet[name]
        local doScrap = junkSet[name] or scrapAlso[name]
        for i,entry in ipairs(list) do
            if i > want then break end
            local model = entry.model
            if doCook then
                cookFlow(model, CAMPFIRE_PATH)
            elseif doBurn then
                burnFlow(model, CAMPFIRE_PATH)
            elseif doScrap then
                scrapFlow(model, SCRAPPER_PATH)
            else
                dropNearPlayer(model)
            end
            task.wait(PER_ITEM_DELAY)
        end
    end

    local function singleSelectDropdown(args)
        return tab:Dropdown({
            Title = args.title,
            Values = args.values,
            Multi = false,
            AllowNone = false,
            Callback = function(choice)
                if choice and choice ~= "" then args.setter(choice) end
            end
        })
    end

    tab:Section({ Title = "Actions" })
    tab:Button({ Title = "Burn/Cook Nearby (Fuel + Raw Food)", Callback = burnNearby })
    tab:Button({ Title = "Scrap Nearby Junk(+Log/Chair)", Callback = scrapNearby })

    tab:Section({ Title = "Junk → Scrapper" })
    singleSelectDropdown({ title = "Select Junk Item", values = junkItems, setter = function(v) selJunk = v end })
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selJunk, AMOUNT_TO_BRING) end })

    tab:Section({ Title = "Fuel → Campfire" })
    singleSelectDropdown({ title = "Select Fuel Item", values = fuelItems, setter = function(v) selFuel = v end })
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selFuel, AMOUNT_TO_BRING) end })

    tab:Section({ Title = "Food" })
    singleSelectDropdown({ title = "Select Food Item", values = foodItems, setter = function(v) selFood = v end })
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selFood, AMOUNT_TO_BRING) end })

    tab:Section({ Title = "Medical" })
    singleSelectDropdown({ title = "Select Medical Item", values = medicalItems, setter = function(v) selMedical = v end })
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selMedical, AMOUNT_TO_BRING) end })

    tab:Section({ Title = "Weapons and Armor" })
    singleSelectDropdown({ title = "Select Weapon/Armor", values = weaponsArmor, setter = function(v) selWA = v end })
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selWA, AMOUNT_TO_BRING) end })

    tab:Section({ Title = "Ammo and Misc." })
    singleSelectDropdown({ title = "Select Ammo/Misc", values = ammoMisc, setter = function(v) selMisc = v end })
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selMisc, AMOUNT_TO_BRING) end })

    tab:Section({ Title = "Pelts" })
    singleSelectDropdown({ title = "Select Pelt", values = pelts, setter = function(v) selPelt = v end })
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selPelt, AMOUNT_TO_BRING) end })
end
