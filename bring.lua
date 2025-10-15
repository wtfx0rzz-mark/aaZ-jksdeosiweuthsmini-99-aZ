return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local RS      = C.Services.RS
    local lp      = Players.LocalPlayer

    local tab = (UI and UI.Tabs and UI.Tabs.Bring) or error("Bring tab not found")

    local AMOUNT_TO_BRING = 50
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

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    local function isExcludedModel(m)
        if not (m and m:IsA("Model")) then return false end
        local n = m.Name:lower()
        return n == "pelt trader" or n:find("trader", 1, true) or n:find("shopkeeper", 1, true)
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
            return obj:FindFirstChild("Main") or obj:FindFirstChildWhichIsA("BasePart")
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

    local function setPhysics(model, collide)
        for _,p in ipairs(getAllParts(model)) do
            p.Anchored = false
            p.CanCollide = collide
            p.Massless = false
            p.AssemblyLinearVelocity = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
    end

    local function pattEscape(s)
        return (s:gsub("([^%w])","%%%1"))
    end

    local function computeDropCF()
        local root = hrp()
        if not root then return nil, nil end
        local forward = root.CFrame.LookVector
        local ahead   = root.Position + forward * DROP_FORWARD
        local start   = ahead + Vector3.new(0, 300, 0)
        local rc      = WS:Raycast(start, Vector3.new(0, -1000, 0))
        local basePos = rc and rc.Position or ahead
        local dropPos = basePos + Vector3.new(0, DROP_UP, 0)
        return CFrame.lookAt(dropPos, dropPos + forward), forward
    end

    local function getRemote(n)
        local f = RS:FindFirstChild("RemoteEvents")
        return f and f:FindFirstChild(n) or nil
    end

    local function nudgeAsync(entry, forward)
        task.defer(function()
            if not (entry.model and entry.model.Parent and entry.part and entry.part.Parent) then return end
            local v = forward * 4 + Vector3.new(0, -12, 0)
            for _,p in ipairs(getAllParts(entry.model)) do
                p.AssemblyLinearVelocity = v
            end
        end)
    end

    local function teleportOne(entry)
        local root = hrp()
        if not (root and entry and entry.model and entry.part) then return false end
        if not entry.model.Parent then return false end
        if entry.part.Anchored then entry.part.Anchored = false end
        if isExcludedModel(entry.model) then return false end

        local dropCF, forward = computeDropCF()
        if not dropCF then return false end

        local startRE = getRemote("RequestStartDraggingItem")
        local stopRE  = getRemote("StopDraggingItem")

        if startRE then pcall(function() startRE:FireServer(entry.model) end) end
        task.wait(0.05)

        setPhysics(entry.model, true)
        pcall(function() entry.part:SetNetworkOwner(lp) end)

        if entry.model:IsA("Model") then
            entry.model:PivotTo(dropCF)
        else
            entry.part.CFrame = dropCF
        end

        nudgeAsync(entry, forward)

        task.wait(0.08)
        pcall(function() entry.part:SetNetworkOwner(nil) end)
        task.delay(0.35, function()
            if not (entry.model and entry.model.Parent) then return end
            if stopRE then pcall(function() stopRE:FireServer(entry.model) end) end
            setPhysics(entry.model, true)
        end)

        task.delay(0.45, function()
            if entry and entry.model then setPhysics(entry.model, true) end
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

    local function modelFrom(candidate)
        if not candidate then return nil end
        if candidate:IsA("Model") then return candidate end
        if candidate:IsA("BasePart") then return candidate:FindFirstAncestorOfClass("Model") end
        return nil
    end

    local function matchesFuzzy(modelNameLower, targetLower)
        if modelNameLower == targetLower then return true end
        if modelNameLower:find(targetLower, 1, true) then return true end
        local base = pattEscape(targetLower)
        if modelNameLower:match("^"..base.." ?%d+$") then return true end
        if targetLower == "log" then
            if modelNameLower:match("fallen%s*log") then return true end
            if modelNameLower:match("cut%s*log") then return true end
            if modelNameLower:match("wood%s*log") then return true end
            if modelNameLower:match("^log[s]?$") then return true end
        end
        return false
    end

    local function tryAdd(found, m, limit, nref)
        if isExcludedModel(m) then return false end
        local mp = mainPart(m)
        if not mp then return false end
        found[#found+1] = {model=m, part=mp}
        nref.count = nref.count + 1
        if limit and nref.count >= limit then return true end
        return false
    end

    local function scanContainer(container, targetLower, limit)
        local out, n = {}, {count = 0}
        if not container then return out end
        for _,d in ipairs(container:GetDescendants()) do
            if limit and n.count >= limit then break end
            if d:IsA("Model") or d:IsA("BasePart") then
                local m = modelFrom(d)
                if m and m.Parent and not hasHumanoid(m) then
                    local nm = m.Name:lower()
                    if matchesFuzzy(nm, targetLower) then
                        if tryAdd(out, m, limit, n) and limit and n.count >= limit then break end
                    end
                end
            end
        end
        return out
    end

    local function collectByNameFuzzy(name, limit)
        local targetLower = name:lower()
        local itemsFolder = WS:FindFirstChild("Items")
        local list = {}

        if itemsFolder then
            for _,e in ipairs(scanContainer(itemsFolder, targetLower, limit)) do
                list[#list+1] = e
            end
        end
        if (not limit) or (#list < limit) then
            local remain = limit and (limit - #list) or nil
            for _,e in ipairs(scanContainer(WS, targetLower, remain)) do
                list[#list+1] = e
            end
        end
        return sortedFarthest(list)
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
        if items then
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
        end
        if limit and n >= limit then
            return sortedFarthest(out)
        end
        for _,m in ipairs(WS:GetDescendants()) do
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
                local l  = nm:lower()
                local ok =
                    (which == "Bunny Foot" and nm == "Bunny Foot") or
                    (which == "Wolf Pelt" and nm == "Wolf Pelt") or
                    (which == "Alpha Wolf Pelt" and l:find("alpha", 1, true) and l:find("wolf", 1, true)) or
                    (which == "Bear Pelt" and l:find("bear", 1, true) and not l:find("polar", 1, true)) or
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
            list = collectByNameFuzzy(name, want)
        end

        if #list == 0 then return end
        local brought = 0
        for _,entry in ipairs(list) do
            if brought >= want then break end
            if teleportOne(entry) then
                brought = brought + 1
                task.wait(0.14)
            end
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
