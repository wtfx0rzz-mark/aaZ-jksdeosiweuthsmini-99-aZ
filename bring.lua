return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local RS      = C.Services.RS
    local Run     = C.Services.Run
    local lp      = Players.LocalPlayer

    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Bring
    assert(tab, "Bring tab not found in UI")

    -- Tunables
    local AMOUNT_TO_BRING = 50
    local APPROACH_DIST   = 2.0   -- how close we "hop" to the item before starting drag
    local RETURN_HB       = 3     -- heartbeats after hop (to let server see you near item / back home)
    local DRAG_HB         = 3     -- heartbeats while drag is active before hopping back
    local BETWEEN_HB      = 2     -- small pause between items

    -- Catalogs
    local junkItems    = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems    = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe"}
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling"}
    local pelts        = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Polar Bear Pelt"}

    local selJunk, selFuel, selFood, selMedical, selWA, selMisc, selPelt =
        junkItems[1], fuelItems[1], foodItems[1], medicalItems[1], weaponsArmor[1], ammoMisc[1], pelts[1]

    -- ========= Utils =========
    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    local function isExcludedModel(m)
        if not (m and m:IsA("Model")) then return false end
        local n = (m.Name or ""):lower()
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

    local function groundAt(pos)
        local start = pos + Vector3.new(0, 500, 0)
        local rc = WS:Raycast(start, Vector3.new(0, -2000, 0))
        return rc and rc.Position or pos
    end

    local function waitHeartbeats(n)
        for _=1,(n or 1) do Run.Heartbeat:Wait() end
    end

    local function getRemote(n)
        local f = RS:FindFirstChild("RemoteEvents")
        return f and f:FindFirstChild(n) or nil
    end

    local function startDrag(model)
        local re = getRemote("RequestStartDraggingItem")
        if re then pcall(function() re:FireServer(model) end) end
    end
    local function stopDrag(model)
        local re = getRemote("StopDraggingItem")
        if re then pcall(function() re:FireServer(model) end) end
    end

    local function hopPlayer(toCF)
        local root = hrp()
        if not (root and toCF) then return end
        root.AssemblyLinearVelocity  = Vector3.new()
        root.AssemblyAngularVelocity = Vector3.new()
        root.CFrame = toCF
    end

    local function approachCFForPart(part, homePos)
        local p = part.Position
        local dir = (homePos and (homePos - p).Unit) or Vector3.new(1,0,0)
        if dir.Magnitude == 0 then dir = Vector3.new(1,0,0) end
        local flatDir = Vector3.new(dir.X, 0, dir.Z)
        if flatDir.Magnitude == 0 then flatDir = Vector3.new(1,0,0) end
        flatDir = flatDir.Unit
        local target = p + flatDir * APPROACH_DIST
        local gp = groundAt(target) + Vector3.new(0, 3, 0)
        local look = CFrame.lookAt(gp, Vector3.new(p.X, gp.Y, p.Z))
        return look
    end

    -- ========= Farthest-first sorter =========
    local function sortedFarthest(list)
        local root = hrp()
        if not root then return list end
        table.sort(list, function(a,b)
            return (a.part.Position - root.Position).Magnitude > (b.part.Position - root.Position).Magnitude
        end)
        return list
    end

    -- ========= Collectors (return farthest-first) =========
    local function collectByNameLoose(name, limit)
        local found, n = {}, 0
        for _,d in ipairs(WS:GetDescendants()) do
            if (d:IsA("Model") or d:IsA("BasePart")) and d.Name == name then
                local model = d:IsA("Model") and d or d.Parent
                if model and model:IsA("Model") and not isExcludedModel(model) then
                    local mp = mainPart(model)
                    if mp then
                        n += 1
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
        for _,m in ipairs(WS:GetDescendants()) do
            if m:IsA("Model") and m.Name:lower():find("cultist", 1, true) and not isExcludedModel(m) then
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
        local items = WS:FindFirstChild("Items")
        if not items then return out end
        for _,m in ipairs(items:GetChildren()) do
            if m:IsA("Model") and m.Name == "Sapling" and not isExcludedModel(m) then
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
                        n += 1
                        out[#out+1] = {model=m, part=mp}
                        if limit and n >= limit then break end
                    end
                end
            end
        end
        return sortedFarthest(out)
    end

    -- ========= Drag-hop move =========
    local function dragHopBring(entry)
        local root = hrp()
        if not (root and entry and entry.model and entry.part) then return false end
        if not entry.model.Parent then return false end
        if isExcludedModel(entry.model) then return false end

        local homeCF = root.CFrame
        local approachCF = approachCFForPart(entry.part, homeCF.Position)

        hopPlayer(approachCF)
        waitHeartbeats(RETURN_HB)

        startDrag(entry.model)
        waitHeartbeats(DRAG_HB)

        hopPlayer(homeCF)
        waitHeartbeats(RETURN_HB)

        stopDrag(entry.model)

        waitHeartbeats(BETWEEN_HB)
        return true
    end

    -- ========= Dispatcher =========
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

        local brought = 0
        for _,entry in ipairs(list) do
            if brought >= want then break end
            if dragHopBring(entry) then
                brought = brought + 1
            end
        end
    end

    -- ========= UI =========
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
