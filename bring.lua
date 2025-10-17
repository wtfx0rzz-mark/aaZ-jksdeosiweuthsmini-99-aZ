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
    local BATCH_SIZE            = 25
    local MAX_PASSES            = 8

    local CAMPFIRE_PATH = workspace.Map.Campground.MainFire
    local SCRAPPER_PATH = workspace.Map.Campground.Scrapper

    local junkItems    = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems    = {"Morsel","Cooked Morsel","Steak","Cooked Steak","Ribs","Cooked Ribs","Cake","Cooked Steak","Cooked Morsel","Berry","Carrot"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe"}
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling"}
    local pelts        = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Polar Bear Pelt"}

    local selJunk, selFuel, selFood, selMedical, selWA, selMisc, selPelt =
        junkItems[1], fuelItems[1], foodItems[1], medicalItems[1], weaponsArmor[1], ammoMisc[1], pelts[1]

    local fuelSet, junkSet, cookSet, scrapAlso = {}, {}, {}, {}
    for _,n in ipairs(fuelItems) do fuelSet[n] = true end
    for _,n in ipairs(junkItems) do junkSet[n] = true end
    cookSet["Morsel"] = true
    cookSet["Steak"]  = true
    cookSet["Ribs"]   = true
    scrapAlso["Log"]   = true
    scrapAlso["Chair"] = true

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

    local RequestStartDraggingItem, RequestBurnItem, RequestScrapItem, StopDraggingItem
    local function resolveRemotes()
        RequestStartDraggingItem = RequestStartDraggingItem or getRemote("RequestStartDraggingItem","StartDraggingItem")
        RequestBurnItem          = RequestBurnItem          or getRemote("RequestBurnItem","BurnItem","RequestFireAdd")
        RequestScrapItem         = RequestScrapItem         or getRemote("RequestScrapItem","ScrapItem","RequestWorkbenchScrap")
        StopDraggingItem         = StopDraggingItem         or getRemote("StopDraggingItem","RequestStopDraggingItem")
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
        local root = hrp()
        if not root then return list end
        table.sort(list, function(a,b)
            return (a.part.Position - root.Position).Magnitude > (b.part.Position - root.Position).Magnitude
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
            if m:IsA("Model") and m.Name:lower():find("cultist", 1, true) and not isExcludedModel(m) then
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
                local nm = m.Name
                local ok =
                    (which == "Bunny Foot" and nm == "Bunny Foot") or
                    (which == "Wolf Pelt" and nm == "Wolf Pelt") or
                    (which == "Alpha Wolf Pelt" and nm:lower():find("alpha") and nm:lower():find("wolf")) or
                    (which == "Bear Pelt" and nm:lower():find("bear") and not nm:lower():find("polar")) or
                    (which == "Polar Bear Pelt" and nm == "Polar Bear Pelt")
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
        local basePos = head and head.Position or (root.Position + Vector3.new(0, 4, 0))
        local look = root.CFrame.LookVector
        local center = basePos + Vector3.new(0, DROP_ABOVE_HEAD_STUDS, 0) + look * FALLBACK_AHEAD
        return CFrame.lookAt(center, center + look)
    end

    local function pivotOverTarget(model, target)
        local mp = mainPart(target)
        if not mp then return end
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
            p.AssemblyLinearVelocity = Vector3.new(0, -8, 0)
        end
        task.delay(COLLIDE_OFF_SEC, function()
            setCollide(model, true, snap)
        end)
    end

    local function startDrag(model)
        resolveRemotes()
        if RequestStartDraggingItem then
            pcall(function() RequestStartDraggingItem:FireServer(model) end)
        end
    end
    local function stopDrag(model)
        resolveRemotes()
        if StopDraggingItem then
            pcall(function() StopDraggingItem:FireServer(model or Instance.new("Model")) end)
        end
    end
    local function burnFlow(model, campfire)
        resolveRemotes()
        local ok = false
        startDrag(model)
        if RequestBurnItem then
            ok = pcall(function()
                RequestBurnItem:FireServer(campfire, Instance.new("Model"))
            end)
        end
        if not ok then pivotOverTarget(model, campfire) end
        stopDrag(model)
    end
    local function scrapFlow(model, scrapper)
        resolveRemotes()
        local ok = false
        startDrag(model)
        if RequestScrapItem then
            ok = pcall(function()
                RequestScrapItem:FireServer(scrapper, Instance.new("Model"))
            end)
        end
        if not ok then pivotOverTarget(model, scrapper) end
        stopDrag(model)
    end
    local function dropNearPlayer(model)
        local cf = computeForwardDropCF()
        if not cf then return end
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
        task.delay(COLLIDE_OFF_SEC, function()
            setCollide(model, true, snap)
        end)
    end

    local function makeOrb(cf, name)
        local part = Instance.new("Part")
        part.Name = name
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(1.5,1.5,1.5)
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(255, 200, 50)
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

    local function moveToCF(model, cf)
        local snap = setCollide(model, false)
        zeroAssembly(model)
        if model:IsA("Model") then
            model:PivotTo(cf)
        else
            local p = mainPart(model)
            if p then p.CFrame = cf end
        end
        task.delay(COLLIDE_OFF_SEC, function()
            setCollide(model, true, snap)
        end)
    end

    local function modelsNear(pos, radius, nameSet, maxCount, seen)
        local out = {}
        local c = 0
        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") and not isExcludedModel(d) and nameSet[d.Name] and not seen[d] then
                local mp = mainPart(d)
                if mp and (mp.Position - pos).Magnitude <= radius then
                    out[#out+1] = d
                    seen[d] = true
                    c = c + 1
                    if maxCount and c >= maxCount then break end
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
        local camp = CAMPFIRE_PATH
        if not camp then return end
        local root = hrp(); if not root then return end
        local baseCF = root.CFrame
        local orb2 = makeOrb(baseCF, "orb2")
        local campCF = (mainPart(camp) and mainPart(camp).CFrame or camp:GetPivot()) + Vector3.new(0,10,0)
        local orb1 = makeOrb(campCF, "orb1")

        local burned = 0
        local seen = {}
        local targets = mergedSet(fuelSet, cookSet)
        for pass=1,MAX_PASSES do
            if burned >= AMOUNT_TO_BRING then break end
            local need = math.min(BATCH_SIZE, AMOUNT_TO_BRING - burned)
            local list = modelsNear(orb2.Position, NEARBY_RADIUS, targets, need, seen)
            if #list == 0 then break end
            for _,m in ipairs(list) do
                moveToCF(m, orb1.CFrame)
                burnFlow(m, camp)
                burned = burned + 1
                if burned >= AMOUNT_TO_BRING then break end
                task.wait(PER_ITEM_DELAY)
            end
            task.wait(0.05)
        end
        task.delay(1.0, function() if orb1 then orb1:Destroy() end if orb2 then orb2:Destroy() end end)
    end

    local function scrapNearby()
        local scr = SCRAPPER_PATH
        if not scr then return end
        local root = hrp(); if not root then return end
        local baseCF = root.CFrame
        local orb2 = makeOrb(baseCF, "orb2")
        local scrCF = (mainPart(scr) and mainPart(scr).CFrame or scr:GetPivot()) + Vector3.new(0,10,0)
        local orb1 = makeOrb(scrCF, "orb1")

        local scrapped = 0
        local seen = {}
        local targets = mergedSet(junkSet, scrapAlso)
        for pass=1,MAX_PASSES do
            if scrapped >= AMOUNT_TO_BRING then break end
            local need = math.min(BATCH_SIZE, AMOUNT_TO_BRING - scrapped)
            local list = modelsNear(orb2.Position, NEARBY_RADIUS, targets, need, seen)
            if #list == 0 then break end
            for _,m in ipairs(list) do
                moveToCF(m, orb1.CFrame)
                scrapFlow(m, scr)
                scrapped = scrapped + 1
                if scrapped >= AMOUNT_TO_BRING then break end
                task.wait(PER_ITEM_DELAY)
            end
            task.wait(0.05)
        end
        task.delay(1.0, function() if orb1 then orb1:Destroy() end if orb2 then orb2:Destroy() end end)
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
        local doBurn = fuelSet[name] or cookSet[name]
        local doScrap = junkSet[name] or scrapAlso[name]
        for i,entry in ipairs(list) do
            if i > want then break end
            local model = entry.model
            if doBurn then
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
    tab:Slider({ Title = "Nearby Radius", Min = 6, Max = 60, Default = NEARBY_RADIUS, Callback = function(v) NEARBY_RADIUS = v end })
    tab:Slider({ Title = "Max To Process", Min = 10, Max = 200, Default = AMOUNT_TO_BRING, Callback = function(v) AMOUNT_TO_BRING = v end })
    tab:Button({ Title = "Burn Nearby Fuel/Food", Callback = burnNearby })
    tab:Button({ Title = "Scrap Nearby Junk(+Log/Chair)", Callback = scrapNearby })

    tab:Section({ Title = "Junk → Scrapper" })
    singleSelectDropdown({ title = "Select Junk Item", values = junkItems, setter = function(v) selJunk = v end })
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selJunk, AMOUNT_TO_BRING) end })

    tab:Section({ Title = "Fuel → Campfire" })
    singleSelectDropdown({ title = "Select Fuel Item", values = fuelItems, setter = function(v) selFuel = v end })
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selFuel, AMOUNT_TO_BRING) end })

    tab:Section({ Title = "Food (cookable included)", TitleRight = "" })
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
