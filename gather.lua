-- 1337 Nights | Gather Module (switch + place button at top, drop 10 forward & 10 up)
return function(C, R, UI)
    local Players = C.Services.Players
    local lp = Players.LocalPlayer
    local Tabs = UI and UI.Tabs or {}
    local tab = Tabs.Gather
    assert(tab, "Gather tab not found")

    C.State = C.State or {}
    C.State.Gather = C.State.Gather or { Enabled = false, Items = {}, Selected = {} }
    local G = C.State.Gather

    local junkItems    = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems    = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe"}
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack"}

    local function addLabel(text)
        local ok = pcall(function() tab:Label({ Title = text }) end)
        if not ok then pcall(function() tab:AddLabel({ Title = text }) end) end
    end

    local function addToggle(title, default, cb)
        local ok, widget = pcall(function()
            return tab:Toggle({ Title = title, Default = default, Callback = cb })
        end)
        if ok and widget then return widget end
        ok, widget = pcall(function()
            return tab:AddToggle({ Title = title, Default = default, Callback = cb })
        end)
        if ok then return widget end
        addLabel(title .. ": unavailable")
        return nil
    end

    local function addButton(title, cb)
        local ok = pcall(function() tab:Button({ Title = title, Callback = cb }) end)
        if not ok then pcall(function() tab:AddButton({ Title = title, Callback = cb }) end) end
    end

    local function addDropdown(title, list, default, cb)
        local ok = pcall(function()
            tab:Dropdown({ Title = title, Options = list, Default = default, Callback = cb })
        end)
        if not ok then
            pcall(function()
                tab:AddDropdown({ Title = title, Options = list, Default = default, Callback = cb })
            end)
        end
    end

    local toggleWidget

    local function placeDown()
        local char = lp.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local basePos = hrp.Position + hrp.CFrame.LookVector * 10 + Vector3.new(0, 10, 0)
        for i, mdl in ipairs(G.Items) do
            if mdl and mdl.Parent then
                local pp = mdl.PrimaryPart
                if not pp then
                    pp = mdl:FindFirstChildWhichIsA("BasePart", true)
                    if pp then mdl.PrimaryPart = pp end
                end
                if pp then
                    for _, d in ipairs(mdl:GetDescendants()) do
                        if d:IsA("BasePart") then
                            d.Anchored = false
                            d.CanCollide = true
                        end
                    end
                    local offset = Vector3.new((i % 5) * 2, 0, math.floor(i / 5) * 2)
                    mdl:SetPrimaryPartCFrame(CFrame.new(basePos + offset))
                    pp.AssemblyLinearVelocity = Vector3.new(0, -5, 0)
                    task.wait()
                end
            end
        end
        G.Enabled = false
        if toggleWidget and toggleWidget.Set then pcall(function() toggleWidget:Set(false) end) end
    end

    toggleWidget = addToggle("Enable Gather", G.Enabled, function(v) G.Enabled = v end)
    addButton("Place Items Now", placeDown)

    addLabel("Selections")

    addDropdown("Junk", junkItems, junkItems[1], function(v) G.Selected.Junk = v end)
    addDropdown("Fuel", fuelItems, fuelItems[1], function(v) G.Selected.Fuel = v end)
    addDropdown("Food", foodItems, foodItems[1], function(v) G.Selected.Food = v end)
    addDropdown("Medical", medicalItems, medicalItems[1], function(v) G.Selected.Medical = v end)
    addDropdown("Weapons/Armor", weaponsArmor, weaponsArmor[1], function(v) G.Selected.WA = v end)
    addDropdown("Ammo/Misc", ammoMisc, ammoMisc[1], function(v) G.Selected.Misc = v end)

    addLabel("Gather Module Loaded")
end
