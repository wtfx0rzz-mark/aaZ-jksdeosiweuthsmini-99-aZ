return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local RS      = C.Services.RS
    local lp      = Players.LocalPlayer

    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Bring
    assert(tab, "Bring tab not found in UI")

    local AMOUNT_TO_BRING = 50

    local junkItems    = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems    = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe"}

    -- Includes new options
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist"}

    -- New Pelts section
    local pelts        = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Polar Bear Pelt"}

    local selJunk, selFuel, selFood, selMedical, selWA, selMisc, selPelt =
        junkItems[1], fuelItems[1], foodItems[1], medicalItems[1], weaponsArmor[1], ammoMisc[1], pelts[1]

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    local function berryPart(m)
        if not (m and m:IsA("Model") and m.Name == "Berry") then return nil end
        local p = m:FindFirstChild("Part")
        if p and p:IsA("BasePart") then return p end
        local h = m:FindFirstChild("Handle")
        if h and h:IsA("BasePart") then return h end
        return m:FindFirstChildWhichIsA("BasePart")
    end

    local function mainPart(obj)
        if not obj or not obj.Parent then return nil end
        if obj:IsA("BasePart") then return obj end
        if obj:IsA("Model") then
            if obj.Name == "Berry" then return berryPart(obj) end
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
        local ahead   = root.Position + forward * 2
        local start   = ahead + Vector3.new(0, 500, 0)
        local rc      = WS:Raycast(start, Vector3.new(0, -2000, 0))
        local basePos = rc and rc.Position or ahead
        local dropPos = basePos + Vector3.new(0, 5, 0)
        return CFrame.lookAt(dropPos, dropPos + forward), forward
    end

    --========================
    -- Collect helpers
    --========================

    local function collectByNameStrictTop(name, limit)
        local items = WS:FindFirstChild("Items")
        if not items then return {} end
        local root = hrp()
        if not root then return {} end
        local found = {}
        for _,m in ipairs(items:GetChildren()) do
            if m:IsA("Model") and m.Name == name then
                local mp = mainPart(m)
                if mp then
                    found[#found+1] = {model=m, part=mp, dist=(mp.Position - root.Position).Magnitude}
                end
            end
        end
        table.sort(found, function(a,b) return a.dist < b.dist end)
        local out, n = {}, math.min(limit or #found, #found)
        for i=1,n do out[i] = found[i] end
        return out
    end

    -- Detect whether a model looks like a humanoid/NPC
    local function hasHumanoidBits(model)
        if not (model and model:IsA("Model")) then return false end
        if model:FindFirstChildOfClass("Humanoid") then return true end
        if model:FindFirstChild("HumanoidRootPart") then return true end
        local limbNames = { "Head","Torso","UpperTorso","LowerTorso","Left Arm","Right Arm","Left Leg","Right Leg",
                            "LeftHand","RightHand","LeftFoot","RightFoot","LeftUpperArm","RightUpperArm","LeftLowerArm","RightLowerArm",
                            "LeftUpperLeg","RightUpperLeg","LeftLowerLeg","RightLowerLeg" }
        for _,n in ipairs(limbNames) do
            if model:FindFirstChild(n) then return true end
        end
        return false
    end

    -- Descendant search with name matcher and optional filter on the *top-level* model under Items
    local function collectByMatcherLoose(limit, matcher, filterFn)
        local items = WS:FindFirstChild("Items")
        if not items then return {} end
        local root = hrp()
        if not root then return {} end
        local found = {}
        for _,d in ipairs(items:GetDescendants()) do
            if (d:IsA("Model") or d:IsA("BasePart")) and d.Parent then
                local model = d:IsA("Model") and d or d.Parent
                if model and model:IsA("Model") then
                    local top = model
                    while top.Parent and top.Parent ~= items do
                        top = top.Parent
                    end
                    if top.Parent == items and top:IsA("Model") then
                        if matcher(top.Name) and (not filterFn or filterFn(top)) then
                            local mp = mainPart(top)
                            if mp then
                                found[#found+1] = {model=top, part=mp, dist=(mp.Position - root.Position).Magnitude}
                            end
                        end
                    end
                end
            end
        end
        table.sort(found, function(a,b) return a.dist < b.dist end)
        local out, n = {}, math.min(limit or #found, #found)
        for i=1,n do out[i] = found[i] end
        return out
    end

    -- Match helpers
    local function exactMatcher(target)
        return function(name) return name == target end
    end
    local function containsMatcher(fragment)
        local f = string.lower(fragment)
        return function(name) return string.find(string.lower(name), f, 1, true) ~= nil end
    end
    local function prefixMatcher(prefix)
        local p = "^" .. prefix:gsub("(%W)","%%%1") .. "%d*$" -- allow trailing digits
        return function(name) return string.match(name, p) ~= nil end
    end
    local function anyOfMatcher(matchers)
        return function(name)
            for _,m in ipairs(matchers) do if m(name) then return true end end
            return false
        end
    end

    --========================
    -- Teleport & drop
    --========================
    local function getRemote(n)
        local f = RS:FindFirstChild("RemoteEvents")
        return f and f:FindFirstChild(n) or nil
    end

    local function quickDrag(model)
        local startRE = getRemote("RequestStartDraggingItem")
        local stopRE  = getRemote("StopDraggingItem")
        if not (startRE and stopRE) then return end
        pcall(function() startRE:FireServer(model) end)
        task.wait(0.04)
        pcall(function() stopRE:FireServer(model) end)
    end

    local function dropAndNudgeAsync(entry, dropCF, forward)
        task.defer(function()
            if not (entry.model and entry.model.Parent and entry.part and entry.part.Parent) then return end
            quickDrag(entry.model)
            task.wait(0.08)
            local v = forward * 1 + Vector3.new(0, -30, 0)
            for _,p in ipairs(getAllParts(entry.model)) do
                p.AssemblyLinearVelocity = v
            end
        end)
    end

    local function teleportOne(entry)
        local root = hrp()
        if not (root and entry and entry.model and entry.part) then return false end
        if not entry.model.Parent then return false end
        if entry.part.Anchored then return false end
        local dropCF, forward = computeDropCF()
        if not dropCF then return false end
        pcall(function() entry.part:SetNetworkOwner(lp) end)
        if entry.model:IsA("Model") then
            entry.model:PivotTo(dropCF)
        else
            entry.part.CFrame = dropCF
        end
        dropAndNudgeAsync(entry, dropCF, forward)
        return true
    end

    local function bringFromList(list, want)
        if #list == 0 then return end
        local brought, goal = 0, math.max(0, tonumber(want) or 0)
        for _,entry in ipairs(list) do
            if brought >= goal then break end
            if teleportOne(entry) then
                brought += 1
                task.wait(0.12)
            end
        end
    end

    local function bringSelected(name, count)
        local want = tonumber(count) or 0
        if want <= 0 then return end

        local matcher, filterFn = nil, nil

        if name == "Mossy Coin" then
            matcher = prefixMatcher("Mossy Coin") -- Mossy Coin, Mossy Coin2, ...
        elseif name == "Cultist" then
            matcher  = containsMatcher("cultist")  -- Crossbow Cultist, etc.
            filterFn = hasHumanoidBits             -- ensure it's an NPC-like model
        elseif name == "Alpha Wolf Pelt" then
            matcher = anyOfMatcher({ exactMatcher("Alpha Wolf Pelt"), containsMatcher("Wolf Pelt") })
        elseif name == "Bear Pelt" then
            matcher = anyOfMatcher({ exactMatcher("Bear Pelt"), exactMatcher("Polar Bear Pelt"), containsMatcher("Bear Pelt") })
        else
            matcher = exactMatcher(name)
        end

        local list
        if name == "Bolt" then
            list = collectByNameStrictTop(name, want)
        else
            list = collectByMatcherLoose(want, matcher, filterFn)
        end

        bringFromList(list, want)
    end

    --========================
    -- UI
    --========================
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
