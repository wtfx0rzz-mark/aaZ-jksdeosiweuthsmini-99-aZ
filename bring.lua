-- 1337 Nights | Bring Tab Module
-- Note: Full file provided; only change is replacing `brought += 1` with `brought = brought + 1`
-- (Luau does not support the `+=` augmented assignment operator.)

return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local lp      = Players.LocalPlayer

    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Bring
    assert(tab, "Bring tab not found in UI")

    local amountToBring = 20

    local junkItems    = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems    = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe"}
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack"}

    local selJunk, selFuel, selFood, selMedical, selWA, selMisc =
        junkItems[1], fuelItems[1], foodItems[1], medicalItems[1], weaponsArmor[1], ammoMisc[1]

    -- HRP helper
    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end

    -- Special-case resolver for Berry model
    local function berryPart(m)
        if not (m and m:IsA("Model") and m.Name == "Berry") then return nil end
        local p = m:FindFirstChild("Part")
        if p and p:IsA("BasePart") then return p end
        local h = m:FindFirstChild("Handle")
        if h and h:IsA("BasePart") then return h end
        return m:FindFirstChildWhichIsA("BasePart")
    end

    -- Get main part for a model or part
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

    -- Choose a ground drop CFrame slightly ahead of player
    local function groundDropCF()
        local root = hrp()
        if not root then return nil end
        local forward = root.CFrame.LookVector
        local ahead2  = root.Position + forward * 2
        local start   = ahead2 + Vector3.new(0, 200, 0)
        local rc = WS:Raycast(start, Vector3.new(0, -1000, 0))
        local dropPos = (rc and rc.Position or ahead2) + Vector3.new(0, 5, 0)
        return CFrame.lookAt(dropPos, dropPos + forward), forward
    end

    -- Nudge physics so items settle instead of floating
    local function nudge(modelOrPart, forward)
        local parts = {}
        if modelOrPart:IsA("Model") then
            for _,d in ipairs(modelOrPart:GetDescendants()) do
                if d:IsA("BasePart") then parts[#parts+1] = d end
            end
        elseif modelOrPart:IsA("BasePart") then
            parts[1] = modelOrPart
        end
        for _,p in ipairs(parts) do
            p.AssemblyLinearVelocity = Vector3.new(forward.X * 1, -30, forward.Z * 1)
        end
    end

    -- Move model or part to CFrame
    local function pivotTo(modelOrPart, cf)
        if modelOrPart:IsA("Model") then
            modelOrPart:PivotTo(cf)
        elseif modelOrPart:IsA("BasePart") then
            modelOrPart.CFrame = cf
        end
    end

    -- Find items by name in Workspace.Items, nearest first
    local function collectByName(name, limit)
        local items = WS:FindFirstChild("Items")
        if not items then return {} end
        local root = hrp()
        if not root then return {} end
        local found = {}
        for _,obj in ipairs(items:GetChildren()) do
            if obj.Name == name then
                local mp = mainPart(obj)
                if mp then
                    found[#found+1] = {model=obj, part=mp, dist=(mp.Position - root.Position).Magnitude}
                end
            end
        end
        table.sort(found, function(a,b) return a.dist < b.dist end)
        local out, n = {}, math.min(limit or #found, #found)
        for i=1,n do out[i] = found[i] end
        return out
    end

    -- Bring N of the selected item to a ground point in front of player
    local function bringSelected(name, count)
        local c = tonumber(count) or 0
        if c <= 0 then return end
        local list = collectByName(name, 9999)
        if #list == 0 then return end
        local dropCF, forward = groundDropCF()
        if not dropCF then return end
        local brought = 0
        for _,entry in ipairs(list) do
            if brought >= c then break end
            if entry.model and entry.model.Parent then
                pivotTo(entry.model, dropCF)
                nudge(entry.model, forward)
                brought = brought + 1    -- FIX: Luau does not support `+=`
                task.wait(0.2)
            end
        end
    end

    --------------------------------------------------
    -- UI Elements
    --------------------------------------------------
    tab:Section({ Title = "Amount To Bring" })
    tab:Textbox({
        Title = "Amount",
        Default = "20",
        Callback = function(v)
            local n = tonumber(v)
            if n and n >= 0 then amountToBring = math.floor(n) end
        end
    })

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
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selJunk, amountToBring) end })

    tab:Section({ Title = "Fuel" })
    singleSelectDropdown({ title = "Select Fuel Item", values = fuelItems, setter = function(v) selFuel = v end })
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selFuel, amountToBring) end })

    tab:Section({ Title = "Food" })
    singleSelectDropdown({ title = "Select Food Item", values = foodItems, setter = function(v) selFood = v end })
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selFood, amountToBring) end })

    tab:Section({ Title = "Medical" })
    singleSelectDropdown({ title = "Select Medical Item", values = medicalItems, setter = function(v) selMedical = v end })
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selMedical, amountToBring) end })

    tab:Section({ Title = "Weapons and Armor" })
    singleSelectDropdown({ title = "Select Weapon/Armor", values = weaponsArmor, setter = function(v) selWA = v end })
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selWA, amountToBring) end })

    tab:Section({ Title = "Ammo and Misc." })
    singleSelectDropdown({ title = "Select Ammo/Misc", values = ammoMisc, setter = function(v) selMisc = v end })
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selMisc, amountToBring) end })
end
