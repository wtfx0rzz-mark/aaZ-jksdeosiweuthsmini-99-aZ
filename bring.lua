return function(C, R, UI)
    local Tabs = UI and UI.Tabs or {}
    local tab = Tabs.Bring or Tabs.br or Tabs.Main
    assert(tab, "Bring tab not found in UI")

    tab:Section({ Title = "Bring Module Loaded ✓" })
    tab:Label({ Title = "This is a test placeholder for the Bring tab." })
    tab:Label({ Title = "If you see this text, the tab loaded successfully." })
end

--[[return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local RS      = C.Services.RS
    local lp      = Players.LocalPlayer

    local Tabs    = UI and UI.Tabs or {}
    local tab     = Tabs.br or Tabs.Bring or Tabs.Main

    local amountToBring = 20

    local junkItems       = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
    local fuelItems       = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems       = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
    local medicalItems    = {"Bandage","MedKit"}
    local weaponsArmor    = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe"}
    local ammoMisc        = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack"}

    local selJunk, selFuel, selFood, selMedical, selWA, selMisc = junkItems[1], fuelItems[1], foodItems[1], medicalItems[1], weaponsArmor[1], ammoMisc[1]

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end

    local function berryPart(m)
        if not m or not m:IsA("Model") then return nil end
        if m.Name ~= "Berry" then return nil end
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
            if obj.Name == "Berry" then
                return berryPart(obj)
            end
            if obj.PrimaryPart then return obj.PrimaryPart end
            return obj:FindFirstChildWhichIsA("BasePart")
        end
        return nil
    end

    local function groundDropCF()
        local root = hrp()
        if not root then return nil end
        local forward = root.CFrame.LookVector
        local ahead2  = root.Position + forward * 2
        local start   = ahead2 + Vector3.new(0, 200, 0)
        local rayDir  = Vector3.new(0, -1000, 0)
        local rc = WS:Raycast(start, rayDir)
        local dropPos
        if rc and rc.Position then
            dropPos = rc.Position + Vector3.new(0, 5, 0)
        else
            dropPos = ahead2 + Vector3.new(0, 5, 0)
        end
        local look  = CFrame.lookAt(dropPos, dropPos + forward)
        return look
    end

    local function nudge(modelOrPart, forward)
        local parts = {}
        if modelOrPart:IsA("Model") then
            for _,d in ipairs(modelOrPart:GetDescendants()) do
                if d:IsA("BasePart") then parts[#parts+1] = d end
            end
        else
            if modelOrPart:IsA("BasePart") then parts[1] = modelOrPart end
        end
        for _,p in ipairs(parts) do
            p.AssemblyLinearVelocity = Vector3.new(forward.X*1, -30, forward.Z*1)
        end
    end

    local function pivotTo(modelOrPart, cf)
        if modelOrPart:IsA("Model") then
            modelOrPart:PivotTo(cf)
        elseif modelOrPart:IsA("BasePart") then
            modelOrPart.CFrame = cf
        end
    end

    local function collectByNameOnce(name, limit)
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
        local out = {}
        for i=1, math.min(limit or #found, #found) do out[i] = found[i] end
        return out
    end

    local function bringSelected(name, count)
        local c = tonumber(count) or 0
        if c <= 0 then return end
        local list = collectByNameOnce(name, 9999)
        if #list == 0 then return end

        local root = hrp()
        if not root then return end
        local forward = root.CFrame.LookVector
        local dropCF = groundDropCF()
        if not dropCF then return end

        local brought = 0
        for _,entry in ipairs(list) do
            if brought >= c then break end
            if entry.model and entry.model.Parent then
                pivotTo(entry.model, dropCF)
                nudge(entry.model, forward)
                brought += 1
                task.wait(0.2)
            end
        end
    end

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
]]
    singleSelectDropdown({ title = "Select Ammo/Misc", values = ammoMisc, setter = function(v) selMisc = v end })
    tab:Button({ Title = "Bring", Callback = function() bringSelected(selMisc, amountToBring) end })
end
