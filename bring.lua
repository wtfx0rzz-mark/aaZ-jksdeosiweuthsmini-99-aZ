--=====================================================
-- 1337 Nights | Bring Tab (workspace-wide, NPC-safe + Sapling)
--  • Farthest-first + unique models + Cultist Items
--  • BATCH STREAMING: prefetch all targets once, then rapid bring
--=====================================================
return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local RS      = C.Services.RS
    local lp      = Players.LocalPlayer

    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Bring
    assert(tab, "Bring tab not found in UI")

    --========================
    -- Tunables
    --========================
    local AMOUNT_TO_BRING    = 50
    local DROP_FORWARD       = 5
    local DROP_UP            = 5

    -- Batch streaming knobs
    local STREAM_BATCH       = true          -- enable prefetch-all
    local STREAM_TIMEOUT     = 4.0           -- seconds to wait once after all requests
    local STREAM_BIN_SIZE    = 96            -- studs; dedupe requests by ~cell
    local STREAM_STRIDE      = 16            -- requests per frame to avoid hitching

    -- Bring loop delay between items
    local BRING_DELAY_SEC    = 0.035         -- small; was 0.12 previously

    local junkItems    = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems    = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe"}
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling","Cultist Items"}
    local pelts        = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Polar Bear Pelt"}

    local selJunk, selFuel, selFood, selMedical, selWA, selMisc, selPelt =
        junkItems[1], fuelItems[1], foodItems[1], medicalItems[1], weaponsArmor[1], ammoMisc[1], pelts[1]

    --========================
    -- Utility
    --========================
    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    local function isExcludedModel(m)
        if not (m and m:IsA("Model")) then return false end
        local n = m.Name:lower()
        return n == "pelt trader" or n:find("trader") or n:find("shopkeeper")
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

    --========================
    -- Drop positioning
    --========================
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

    local function getRemote(n)
        local f = RS:FindFirstChild("RemoteEvents")
        return f and f:FindFirstChild(n) or nil
    end

    local function quickDrag(model)
        local startRE = getRemote("RequestStartDraggingItem")
        local stopRE  = getRemote("StopDraggingItem")
        if not (startRE and stopRE) then return end
        pcall(function() startRE:FireServer(model) end)
        task.wait(0.03)
        pcall(function() stopRE:FireServer(model) end)
    end

    local function dropAndNudgeAsync(entry, dropCF, forward)
        task.defer(function()
            if not (entry.model and entry.model.Parent and entry.part and entry.part.Parent) then return end
            quickDrag(entry.model)
            task.wait(0.05)
            local v = forward * 6 + Vector3.new(0, -30, 0)
            for _,p in ipairs(getAllParts(entry.model)) do
                p.AssemblyLinearVelocity = v
            end
        end)
    end

    --========================
    -- Streaming helpers (BATCH)
    --========================
    local function binKeyFromPos(pos)
        local bx = math.floor(pos.X / STREAM_BIN_SIZE)
        local by = math.floor(pos.Y / STREAM_BIN_SIZE)
        local bz = math.floor(pos.Z / STREAM_BIN_SIZE)
        return string.format("%d,%d,%d", bx, by, bz)
    end

    local function prefetchForEntries(entries)
        if not STREAM_BATCH or not entries or #entries == 0 then return end
        local seenBins, binPositions = {}, {}
        for _,e in ipairs(entries) do
            local p = e.part and e.part.Position
            if p then
                local key = binKeyFromPos(p)
                if not seenBins[key] then
                    seenBins[key] = true
                    binPositions[#binPositions+1] = p
                end
            end
        end
        -- Issue requests in small bursts to avoid hitching
        local i, n = 1, #binPositions
        while i <= n do
            local j = math.min(i + STREAM_STRIDE - 1, n)
            for k = i, j do
                local pos = binPositions[k]
                pcall(function() WS:RequestStreamAroundAsync(pos) end)
                pcall(function() lp:RequestStreamAroundAsync(pos) end)
            end
            task.wait() -- yield one frame between bursts
            i = j + 1
        end
        -- single grace wait after all requests
        task.wait(STREAM_TIMEOUT)
    end

    --========================
    -- Teleport one (no per-item streaming; we stream in batch)
    --========================
    local function teleportOne(entry)
        local root = hrp()
        if not (root and entry and entry.model and entry.part) then return false end
        if not entry.model.Parent or entry.part.Anchored then return false end
        if isExcludedModel(entry.model) then return false end

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
    -- Collectors (UNIQUE models, farthest-first)
    --========================
    local function sortedFarthest(list)
        local root = hrp()
        if not root then return list end
        table.sort(list, function(a,b)
            return (a.part.Position - root.Position).Magnitude > (b.part.Position - root.Position).Magnitude
        end)
        return list
    end

    local function collectByNameLoose(name, limit)
        local found, seen, unique = {}, {}, 0
        for _,d in ipairs(WS:GetDescendants()) do
            if (d:IsA("Model") or d:IsA("BasePart")) and d.Name == name then
                local model = d:IsA("Model") and d or d.Parent
                if model and model:IsA("Model") and not isExcludedModel(model) and not seen[model] then
                    local mp = mainPart(model)
                    if mp then
                        seen[model] = true
                        unique += 1
                        found[#found+1] = {model=model, part=mp}
                        if limit and unique >= limit then break end
                    end
                end
            end
        end
        return sortedFarthest(found)
    end

    local function collectMossyCoins(limit)
        local out, seen, unique = {}, {}, 0
        for _,m in ipairs(WS:GetDescendants()) do
            if m:IsA("Model") and not isExcludedModel(m) then
                local nm = m.Name
                if nm == "Mossy Coin" or nm:match("^Mossy Coin%d+$") then
                    if not seen[m] then
                        local mp = m:FindFirstChild("Main") or m:FindFirstChildWhichIsA("BasePart")
                        if mp then
                            seen[m] = true
                            unique += 1
                            out[#out+1] = {model=m, part=mp}
                            if limit and unique >= limit then break end
                        end
                    end
                end
            end
        end
        return sortedFarthest(out)
    end

    local function collectCultists(limit)
        local out, seen, unique = {}, {}, 0
        for _,m in ipairs(WS:GetDescendants()) do
            if m:IsA("Model") and m.Name:lower():find("cultist", 1, true) and not isExcludedModel(m) then
                if hasHumanoid(m) then
                    if not seen[m] then
                        local mp = mainPart(m)
                        if mp then
                            seen[m] = true
                            unique += 1
                            out[#out+1] = {model=m, part=mp}
                            if limit and unique >= limit then break end
                        end
                    end
                end
            end
        end
        return sortedFarthest(out)
    end

    local function collectSaplings(limit)
        local out, seen, unique = {}, {}, 0
        local items = WS:FindFirstChild("Items")
        if not items then return out end
        for _,m in ipairs(items:GetChildren()) do
            if m:IsA("Model") and m.Name == "Sapling" and not isExcludedModel(m) and not seen[m] then
                local mp = mainPart(m)
                if mp then
                    seen[m] = true
                    unique += 1
                    out[#out+1] = {model=m, part=mp}
                    if limit and unique >= limit then break end
                end
            end
        end
        return sortedFarthest(out)
    end

    local function collectCultistItems(limit)
        local out, seen, unique = {}, {}, 0
        local items = WS:FindFirstChild("Items")
        if not items then return out end
        for _,d in ipairs(items:GetDescendants()) do
            if d:IsA("Model") and not isExcludedModel(d) and not seen[d] then
                local nm = (d.Name or ""):lower()
                if (nm:find("cultist", 1, true) or nm:find("totem", 1, true)) and not hasHumanoid(d) then
                    local mp = mainPart(d)
                    if mp then
                        seen[d] = true
                        unique += 1
                        out[#out+1] = {model=d, part=mp}
                        if limit and unique >= limit then break end
                    end
                end
            end
        end
        return sortedFarthest(out)
    end

    local function collectPelts(which, limit)
        local out, seen, unique = {}, {}, 0
        for _,m in ipairs(WS:GetDescendants()) do
            if m:IsA("Model") and not isExcludedModel(m) and not seen[m] then
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
                        seen[m] = true
                        unique += 1
                        out[#out+1] = {model=m, part=mp}
                        if limit and unique >= limit then break end
                    end
                end
            end
        end
        return sortedFarthest(out)
    end

    --========================
    -- Dispatcher (with batch streaming)
    --========================
    local function bringSelected(name, count)
        local want = tonumber(count) or 0
        if want <= 0 then return end
        local list

        if name == "Mossy Coin" then
            list = collectMossyCoins(want)
        elseif name == "Cultist" then
            list = collectCultists(want)       -- NPCs
        elseif name == "Cultist Items" then
            list = collectCultistItems(want)   -- Items (incl. totems), not NPCs
        elseif name == "Sapling" then
            list = collectSaplings(want)
        elseif table.find(pelts, name) then
            list = collectPelts(name, want)
        else
            list = collectByNameLoose(name, want)
        end

        if not list or #list == 0 then return end

        -- NEW: pre-stream all targets once
        prefetchForEntries(list)

        local brought = 0
        for _,entry in ipairs(list) do
            if brought >= want then break end
            if teleportOne(entry) then
                brought += 1
                if BRING_DELAY_SEC > 0 then
                    task.wait(BRING_DELAY_SEC)
                else
                    task.wait() -- yield one frame
                end
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
end
