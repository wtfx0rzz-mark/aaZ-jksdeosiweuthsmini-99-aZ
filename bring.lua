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
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack"}

    local selJunk, selFuel, selFood, selMedical, selWA, selMisc =
        junkItems[1], fuelItems[1], foodItems[1], medicalItems[1], weaponsArmor[1], ammoMisc[1]

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
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
        local parts = {}
        if target:IsA("BasePart") then
            parts[1] = target
        elseif target:IsA("Model") then
            for _,d in ipairs(target:GetDescendants()) do
                if d:IsA("BasePart") then
                    parts[#parts+1] = d
                end
            end
        end
        return parts
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

    local function collectByName(name, limit)
        local items = WS:FindFirstChild("Items")
        if not items then return {} end
        local root = hrp()
        if not root then return {} end
        local found = {}
        for _,d in ipairs(items:GetDescendants()) do
            if d:IsA("Model") or d:IsA("BasePart") then
                if d.Name == name then
                    local mp = mainPart(d)
                    if mp then
                        local model = d:IsA("Model") and d or d.Parent
                        if model and model:IsA("Model") then
                            found[#found+1] = {model=model, part=mp, dist=(mp.Position - root.Position).Magnitude}
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

    local function getRemote(name)
        local reFolder = RS:FindFirstChild("RemoteEvents")
        if not reFolder then return nil end
        return reFolder:FindFirstChild(name)
    end

    local function dragDropTry(model, dropPos)
        local ok = false
        local startRE = getRemote("RequestStartDraggingItem")
        local plantRF = getRemote("RequestPlantItem")
        local stopRE  = getRemote("StopDraggingItem")
        if not (startRE and stopRE) then return false end
        pcall(function() startRE:FireServer(model) end)
        if plantRF and typeof(plantRF) == "Instance" and plantRF.ClassName == "RemoteFunction" then
            local successA = pcall(function() return plantRF:InvokeServer(model, dropPos) end)
            ok = successA or ok
            if not successA then
                pcall(function() plantRF:InvokeServer(dropPos) end)
            end
        end
        pcall(function() stopRE:FireServer(model) end)
        return ok
    end

    local function dropOne(entry)
        local root = hrp()
        if not (root and entry and entry.model and entry.part) then return false end
        if not entry.model.Parent then return false end
        if entry.part.Anchored then return false end

        local dropCF, forward = computeDropCF()
        if not dropCF then return false end
        local dropPos = dropCF.Position

        pcall(function() entry.part:SetNetworkOwner(lp) end)

        if entry.model:IsA("Model") then
            entry.model:PivotTo(dropCF)
        else
            entry.part.CFrame = dropCF
        end

        task.wait(0.1)

        local v = forward * 1 + Vector3.new(0, -30, 0)
        for _,p in ipairs(getAllParts(entry.model)) do
            p.AssemblyLinearVelocity = v
        end

        dragDropTry(entry.model, dropPos)

        return true
    end

    local function bringSelected(name, count)
        local want = tonumber(count) or 0
        if want <= 0 then return end
        local list = collectByName(name, want)
        if #list == 0 then return end

        local brought = 0
        for _,entry in ipairs(list) do
            if brought >= want then break end
            local ok = dropOne(entry)
            if ok then
                brought = brought + 1
                task.wait(0.3)
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
end
