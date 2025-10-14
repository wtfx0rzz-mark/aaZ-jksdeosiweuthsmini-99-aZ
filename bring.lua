--=====================================================
-- 1337 Nights | Bring Tab (workspace-wide, stream-aware collectors)
--=====================================================
return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local RS      = C.Services.RS
    local lp      = Players.LocalPlayer

    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Bring
    assert(tab, "Bring tab not found in UI")

    local AMOUNT_TO_BRING = 50

    -- Catalogs
    local junkItems    = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems    = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe"}
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack", "Mossy Coin", "Cultist"}
    local pelts        = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Polar Bear Pelt"}

    local selJunk, selFuel, selFood, selMedical, selWA, selMisc, selPelt =
        junkItems[1], fuelItems[1], foodItems[1], medicalItems[1], weaponsArmor[1], ammoMisc[1], pelts[1]

    --========================
    -- Utilities
    --========================
    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    local function hasHumanoid(model)
        if not (model and model:IsA("Model")) then return false end
        return model:FindFirstChildOfClass("Humanoid") ~= nil
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

    --========================
    -- Workspace-wide collectors (streamed-in only)
    --========================
    local function sortedNear(list)
        local root = hrp()
        if not root then return list end
        table.sort(list, function(a,b)
            return (a.part.Position - root.Position).Magnitude < (b.part.Position - root.Position).Magnitude
        end)
        return list
    end

    -- generic finder by exact top-level model name (anywhere in Workspace)
    local function collectByNameLoose(name, limit)
        local root = hrp()
        if not root then return {} end
        local found, n = {}, 0
        for _,d in ipairs(WS:GetDescendants()) do
            if (d:IsA("Model") or d:IsA("BasePart")) and d.Name == name then
                local model = d:IsA("Model") and d or d.Parent
                if model and model:IsA("Model") then
                    local mp = mainPart(model)
                    if mp then
                        n += 1
                        found[#found+1] = {model = model, part = mp}
                        if limit and n >= limit then break end
                    end
                end
            end
        end
        return sortedNear(found)
    end

    -- Mossy Coin: matches “Mossy Coin” and “Mossy Coin<number>”, and prefers the inner “Main”/mesh base
    local function isMossyCoinModel(m)
        if not (m and m:IsA("Model")) then return false end
        local nm = tostring(m.Name)
        if nm == "Mossy Coin" then return true end
        local base, num = nm:match("^(Mossy Coin)(%d+)$")
        return base ~= nil and tonumber(num) ~= nil
    end
    local function collectMossyCoins(limit)
        local root = hrp()
        if not root then return {} end
        local out, n = {}, 0
        for _,m in ipairs(WS:GetDescendants()) do
            if m:IsA("Model") and isMossyCoinModel(m) then
                -- Prefer a child named "Main" if present; otherwise any BasePart
                local mp = m:FindFirstChild("Main")
                if not (mp and mp:IsA("BasePart")) then
                    mp = m:FindFirstChildWhichIsA("BasePart")
                end
                if mp then
                    n += 1
                    out[#out+1] = {model = m, part = mp}
                    if limit and n >= limit then break end
                end
            end
        end
        return sortedNear(out)
    end

    -- Cultist: require a Humanoid so we don’t grab “cultist” items
    local function collectCultists(limit)
        local root = hrp()
        if not root then return {} end
        local out, n = {}, 0
        for _,m in ipairs(WS:GetDescendants()) do
            if m:IsA("Model") and m.Name:lower():find("cultist", 1, true) then
                if hasHumanoid(m) then
                    local mp = mainPart(m)
                    if mp then
                        n += 1
                        out[#out+1] = {model = m, part = mp}
                        if limit and n >= limit then break end
                    end
                end
            end
        end
        return sortedNear(out)
    end

    -- Pelts: fuzzy helpers for Alpha/Bear using available examples
    local function isAlphaWolfPeltName(nm)
        nm = nm:lower()
        return nm == "alpha wolf pelt" or nm == "wolf pelt alpha" or nm:find("alpha") and nm:find("wolf") and nm:find("pelt")
    end
    local function isBearPeltName(nm)
        nm = nm:lower()
        return (nm == "bear pelt") or (nm:find("bear") and nm:find("pelt") and not nm:find("polar"))
    end

    local function collectPelts(which, limit)
        local root = hrp()
        if not root then return {} end
        local out, n = {}, 0
        for _,m in ipairs(WS:GetDescendants()) do
            if m:IsA("Model") then
                local ok = false
                local nm = m.Name
                if which == "Bunny Foot"        then ok = (nm == "Bunny Foot")
                elseif which == "Wolf Pelt"     then ok = (nm == "Wolf Pelt")
                elseif which == "Alpha Wolf Pelt" then ok = isAlphaWolfPeltName(nm) or (nm == "Wolf Pelt" and m:FindFirstChild("Main") and (m.Main.Color and m.Main.Color.G < 0.4)) -- heuristic
                elseif which == "Bear Pelt"     then ok = isBearPeltName(nm) or (nm == "Polar Bear Pelt") -- allow fallback if devs reuse asset
                elseif which == "Polar Bear Pelt" then ok = (nm == "Polar Bear Pelt")
                end
                if ok then
                    local mp = mainPart(m)
                    if mp then
                        n += 1
                        out[#out+1] = {model = m, part = mp}
                        if limit and n >= limit then break end
                    end
                end
            end
        end
        return sortedNear(out)
    end

    --========================
    -- Dispatcher
    --========================
    local function bringSelected(name, count)
        local want = tonumber(count) or 0
        if want <= 0 then return end

        local list = {}
        if name == "Mossy Coin" then
            list = collectMossyCoins(want)
        elseif name == "Cultist" then
            list = collectCultists(want)
        elseif name == "Bunny Foot" or name == "Wolf Pelt" or name == "Alpha Wolf Pelt"
            or name == "Bear Pelt" or name == "Polar Bear Pelt" then
            list = collectPelts(name, want)
        else
            -- generic
            list = collectByNameLoose(name, want)
        end

        if #list == 0 then return end
        local brought = 0
        for _,entry in ipairs(list) do
            if brought >= want then break end
            if teleportOne(entry) then
                brought += 1
                task.wait(0.12)
            end
        end
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

    -- NOTE: StreamingEnabled means only streamed-in instances are visible to the client.
    -- If you want an experimental auto-scan that briefly moves the player to stream chunks,
    -- we can add that here on demand.
end
