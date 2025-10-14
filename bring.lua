return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
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

    local function groundDropCF()
        local root = hrp()
        if not root then return nil, nil end
        local forward = root.CFrame.LookVector
        local ahead2  = root.Position + forward * 2
        local rc = WS:Raycast(ahead2 + Vector3.new(0, 200, 0), Vector3.new(0, -1000, 0))
        local dropPos = (rc and rc.Position or ahead2) + Vector3.new(0, 5, 0)
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
                        table.insert(found, {model=(d:IsA("Model") and d or d.Parent), part=mp, dist=(mp.Position - root.Position).Magnitude})
                    end
                end
            end
        end
        table.sort(found, function(a,b) return a.dist < b.dist end)
        local out, n = {}, math.min(limit or #found, #found)
        for i=1,n do out[i] = found[i] end
        return out
    end

    local function stepwisePivot(modelOrPart, targetCF, steps, waitS)
        steps = steps or 12
        waitS = waitS or 0.03
        if modelOrPart:IsA("Model") then
            for i=1,steps do
                local cf = modelOrPart:GetPivot()
                local pos = cf.Position:Lerp(targetCF.Position, i/steps)
                local look = (targetCF.LookVector)
                modelOrPart:PivotTo(CFrame.lookAt(pos, pos + look))
                task.wait(waitS)
            end
        else
            for i=1,steps do
                local cf = modelOrPart.CFrame
                local pos = cf.Position:Lerp(targetCF.Position, i/steps)
                local look = (targetCF.LookVector)
                modelOrPart.CFrame = CFrame.lookAt(pos, pos + look)
                task.wait(waitS)
            end
        end
    end

    local function tetherBring(part, root, duration)
        duration = duration or 1.2
        if not (part and part:IsA("BasePart") and root and root:IsA("BasePart")) then return false end
        if part.Anchored then return false end
        pcall(function() part:SetNetworkOwner(lp) end)

        local att0 = Instance.new("Attachment")
        att0.Name = "__BringA0"
        att0.Parent = part

        local att1 = Instance.new("Attachment")
        att1.Name = "__BringA1"
        att1.Parent = root
        att1.Position = Vector3.new(0, 3, -3)

        local ap = Instance.new("AlignPosition")
        ap.Name = "__BringAP"
        ap.Mode = Enum.PositionAlignmentMode.OneAttachment
        ap.Attachment0 = att0
        ap.Responsiveness = 200
        ap.MaxForce = 1e9
        ap.MaxVelocity = 1e9
        ap.ApplyAtCenterOfMass = true
        ap.RigidityEnabled = false
        ap.Parent = part

        local ao = Instance.new("AlignOrientation")
        ao.Name = "__BringAO"
        ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
        ao.Attachment0 = att0
        ao.Responsiveness = 200
        ao.MaxAngularVelocity = 1e9
        ao.MaxTorque = 1e9
        ao.PrimaryAxisOnly = false
        ao.RigidityEnabled = false
        ao.Parent = part

        local t0 = os.clock()
        local ok = false
        while os.clock() - t0 < duration do
            if not part.Parent or not root.Parent then break end
            att1.CFrame = CFrame.new(Vector3.new(0, 3, -3))
            if (part.Position - (root.CFrame * Vector3.new(0,3,-3))).Magnitude < 6 then
                ok = true
                break
            end
            task.wait()
        end

        ap:Destroy()
        ao:Destroy()
        att0:Destroy()
        att1:Destroy()
        return ok
    end

    local function bringOne(entry, dropCF)
        if not (entry and entry.model and entry.part and entry.model.Parent) then return false end
        if entry.part.Anchored then return false end
        local root = hrp()
        if not root then return false end
        local ok = tetherBring(entry.part, root, 1.4)
        if ok then return true end
        stepwisePivot(entry.model, dropCF, 14, 0.03)
        return true
    end

    local function bringSelected(name, count)
        local c = tonumber(count) or 0
        if c <= 0 then return end
        local list = collectByName(name, 9999)
        if #list == 0 then return end
        local dropCF = select(1, groundDropCF())
        if not dropCF then return end
        local brought = 0
        for _,entry in ipairs(list) do
            if brought >= c then break end
            if bringOne(entry, dropCF) then
                brought = brought + 1
                task.wait(0.08)
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
