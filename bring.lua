return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local RS      = C.Services.RS
    local lp      = Players.LocalPlayer

    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Bring
    assert(tab, "Bring tab not found in UI")

    ----------------------------------------------------------------
    -- Natural workstation handoff (keeps gameplay feel)
    ----------------------------------------------------------------
    local NATURAL_HANDOFF_ENABLED = true
    local HANDOFF_PLAYER_RADIUS   = 7      -- you stand close to station
    local HANDOFF_ITEM_RADIUS     = 4      -- drop within this of station
    local SLOW_SPEED_MAX          = 2      -- studs/sec threshold
    local SLOW_TIME_MIN           = 0.30   -- must be slow for this long

    -- cache + helpers
    local campCache = nil
    local function findCase(parent, name)
        if not parent then return nil end
        local want = string.lower(name)
        for _,ch in ipairs(parent:GetChildren()) do
            if string.lower(ch.Name) == want then return ch end
        end
        return nil
    end
    local function findContains(parent, needle)
        if not parent then return nil end
        local want = string.lower(needle)
        for _,ch in ipairs(parent:GetChildren()) do
            if string.find(string.lower(ch.Name), want, 1, true) then return ch end
        end
        return nil
    end
    local function campground()
        if campCache and campCache.Parent then return campCache end
        local map = WS:FindFirstChild("Map") or WS:FindFirstChild("map") or WS
        campCache = findCase(map, "Campground") or findContains(map, "campground") or nil
        return campCache
    end
    local function craftingBench()
        local cg = campground()
        -- support upgraded/variant benches
        return findCase(cg, "CraftingBench") or findContains(cg, "craftingbench") or findContains(cg, "scrap")
    end
    local function mainFire()
        local cg = campground()
        return findCase(cg, "MainFire") or findContains(cg, "mainfire") or findContains(cg, "campfire")
    end
    local function pivotPos(model)
        if not model then return nil end
        local ok, cf = pcall(model.GetPivot, model)
        if ok and typeof(cf) == "CFrame" then return cf.Position end
        local p = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
        return p and p.Position or nil
    end

    -- player motion sampling (to detect “stance” at a station)
    local lastPos, lastT, slowSince = nil, nil, nil
    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local function sampleSpeed()
        local root = hrp(); if not root then return math.huge end
        local now, pos = os.clock(), root.Position
        local spd = math.huge
        if lastPos and lastT then
            local dt = now - lastT
            if dt > 0 then spd = (pos - lastPos).Magnitude / dt end
        end
        lastPos, lastT = pos, now
        if spd <= SLOW_SPEED_MAX then
            if not slowSince then slowSince = now end
        else
            slowSince = nil
        end
        local slowOk = slowSince and ((now - slowSince) >= SLOW_TIME_MIN) or false
        return spd, slowOk
    end

    ----------------------------------------------------------------
    -- UI lists (unchanged)
    ----------------------------------------------------------------
    local AMOUNT_TO_BRING = 100
    local DROP_FORWARD = 5
    local DROP_UP      = 5

    local junkItems    = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems    = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe"}
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling"}
    local pelts        = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Polar Bear Pelt"}

    local selJunk, selFuel, selFood, selMedical, selWA, selMisc, selPelt =
        junkItems[1], fuelItems[1], foodItems[1], medicalItems[1], weaponsArmor[1], ammoMisc[1], pelts[1]

    ----------------------------------------------------------------
    -- Core helpers
    ----------------------------------------------------------------
    local function auraRadius()
        return math.clamp(tonumber(C.State and C.State.AuraRadius) or 150, 0, 500)
    end
    local function withinRadius(pos)
        local root = hrp()
        if not root then return true end
        return (pos - root.Position).Magnitude <= auraRadius()
    end
    local function isExcludedModel(m)
        if not (m and m:IsA("Model")) then return false end
        local n = m.Name:lower()
        return n == "pelt trader" or n:find("trader",1,true) or n:find("shopkeeper",1,true)
    end
    local function hasHumanoid(model)
        return model and model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") ~= nil
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
        if target:IsA("BasePart") then
            t[1] = target
        elseif target:IsA("Model") then
            for _,d in ipairs(target:GetDescendants()) do
                if d:IsA("BasePart") then
                    t[#t+1] = d
                end
            end
        end
        return t
    end
    local function computeDropCF()
        local root = hrp()
        if not root then return nil, nil end
        local forward = root.CFrame.LookVector
        local ahead   = root.Position + forward * DROP_FORWARD
        local start   = ahead + Vector3.new(0, 500, 0)
        local rc      = WS:Raycast(start, Vector3.new(0, -2000, 0))
        local basePos = rc and rc.Position or ahead
        local dropPos = basePos + Vector3.new(0, DROP_UP, 0)
        return CFrame.lookAt(dropPos, dropPos + forward), forward
    end

    local function getRemoteEvent(n)
        local f = RS:FindFirstChild("RemoteEvents")
        local r = f and f:FindFirstChild(n)
        return (r and r:IsA("RemoteEvent")) and r or nil
    end
    local function getRemoteFunction(n)
        local f = RS:FindFirstChild("RemoteEvents")
        local r = f and f:FindFirstChild(n)
        return (r and r:IsA("RemoteFunction")) and r or nil
    end

    ----------------------------------------------------------------
    -- Station mapping + stance check
    ----------------------------------------------------------------
    local function itemGoesToBench(name)
        return name == "Log" or (table.find(junkItems, name) ~= nil)
    end
    local function itemGoesToFire(name)
        return name == "Log" or (table.find(fuelItems, name) ~= nil)
    end

    local function nearestStationToRoot()
        local root = hrp(); if not root then return nil, nil end
        local bench, fire = craftingBench(), mainFire()
        local rp = root.Position
        local bestModel, bestDist = nil, math.huge
        for _,m in ipairs({bench, fire}) do
            if m then
                local mp = pivotPos(m)
                if mp then
                    local d = (mp - rp).Magnitude
                    if d < bestDist then bestDist, bestModel = d, m end
                end
            end
        end
        return bestModel, bestDist
    end

    local function inHandoffStance()
        if not NATURAL_HANDOFF_ENABLED then return nil end
        local station, playerDist = nearestStationToRoot()
        if not station then return nil end
        if playerDist > HANDOFF_PLAYER_RADIUS then return nil end
        local _, slowOk = sampleSpeed()
        if not slowOk then return nil end
        return station
    end

    local function classifyDropForStation(dropPos, itemName)
        local station = inHandoffStance()
        if not station then return nil, nil end
        local sp = pivotPos(station); if not sp then return nil, nil end
        if (sp - dropPos).Magnitude > HANDOFF_ITEM_RADIUS then return nil, nil end
        local targetKind
        if itemGoesToBench(itemName) and station == craftingBench() then
            targetKind = "bench"
        elseif itemGoesToFire(itemName) and station == mainFire() then
            targetKind = "fire"
        end
        return targetKind, station
    end

    ----------------------------------------------------------------
    -- Bring core
    ----------------------------------------------------------------
    local function nudgeAsync(entry, forward)
        task.defer(function()
            if not (entry.model and entry.model.Parent and entry.part and entry.part.Parent) then return end
            local v = forward * 6 + Vector3.new(0, -24, 0)
            for _,p in ipairs(getAllParts(entry.model)) do
                p.AssemblyLinearVelocity = v
            end
        end)
    end

    local function teleportOne(entry)
        local root = hrp()
        if not (root and entry and entry.model and entry.part) then return false end
        if not entry.model.Parent or entry.part.Anchored then return false end
        if isExcludedModel(entry.model) then return false end

        local dropCF, forward = computeDropCF()
        if not dropCF then return false end

        -- Decide if we will handoff for server credit
        local handoffKind, station = classifyDropForStation(dropCF.Position, entry.model.Name)

        if handoffKind then
            -- local visual placement
            if entry.model:IsA("Model") then entry.model:PivotTo(dropCF)
            else entry.part.CFrame = dropCF end

            -- make sure physics won’t block station consume
            for _,p in ipairs(getAllParts(entry.model)) do
                p.Anchored = false
                p.CanCollide, p.CanQuery, p.CanTouch = true, true, true
                p.Massless = false
                p.AssemblyLinearVelocity = Vector3.new(0, -10, 0)
                p:SetNetworkOwner(nil)
            end

            -- server credit via official remotes (dummy pattern)
            local startDrag = getRemoteEvent("RequestStartDraggingItem")
            local stopDrag  = getRemoteEvent("StopDraggingItem")
            local burnEv    = getRemoteEvent("RequestBurnItem")
            local scrapFn   = getRemoteFunction("RequestScrapItem")
            local dummy = Instance.new("Model")

            pcall(function() if startDrag then startDrag:FireServer(dummy) end end)
            if handoffKind == "fire" then
                pcall(function() if burnEv and station then burnEv:FireServer(station, dummy) end end)
            else
                pcall(function() if scrapFn and station then scrapFn:InvokeServer(station, dummy) end end)
            end
            pcall(function() if stopDrag then stopDrag:FireServer(dummy) end end)

            return true
        end

        -- Normal bring path
        local startRE = getRemoteEvent("RequestStartDraggingItem")
        local stopRE  = getRemoteEvent("StopDraggingItem")
        if startRE then pcall(function() startRE:FireServer(entry.model) end) end
        task.wait(0.03)

        pcall(function() entry.part:SetNetworkOwner(lp) end)

        if entry.model:IsA("Model") then
            entry.model:PivotTo(dropCF)
        else
            entry.part.CFrame = dropCF
        end

        nudgeAsync(entry, forward)

        task.delay(0.08, function()
            if stopRE then pcall(function() stopRE:FireServer(entry.model) end) end
        end)

        return true
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
                    if mp and withinRadius(mp.Position) then
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
                    if mp and withinRadius(mp.Position) then
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
                    if mp and withinRadius(mp.Position) then
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
                if mp and withinRadius(mp.Position) then
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
                    if mp and withinRadius(mp.Position) then
                        n = n + 1
                        out[#out+1] = {model=m, part=mp}
                        if limit and n >= limit then break end
                    end
                end
            end
        end
        return sortedFarthest(out)
    end

    local function bringSelected(name, count)
        local want = tonumber(count) or 0
        if want <= 0 then return end
        local list = {}

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
        local brought = 0
        for _,entry in ipairs(list) do
            if brought >= want then break end
            if teleportOne(entry) then
                brought = brought + 1
                task.wait(0.12)
            end
        end
    end

    ----------------------------------------------------------------
    -- UI (unchanged)
    ----------------------------------------------------------------
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

    tab:Section({ Title = "Junk" })
    singleSelectDropdown({ title = "Select Junk Item", values = junkItems, setter = function(v) selJunk = v end })
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selJunk, AMOUNT_TO_BRING) end })

    tab:Section({ Title = "Fuel" })
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
