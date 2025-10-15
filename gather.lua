--=====================================================
-- 1337 Nights | Gather Module (WindUI-safe)
--  • Switch + Place button at top
--  • WindUI-friendly selectors (no broken Dropdown API)
--  • Place pile 10 studs forward + 10 up
--=====================================================
return function(C, R, UI)
    local Players = C.Services.Players
    local lp      = Players.LocalPlayer

    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Gather
    assert(tab, "Gather tab not found")

    C.State       = C.State or {}
    C.State.Gather = C.State.Gather or { Enabled = false, Items = {}, Selected = {} }
    local G = C.State.Gather

    -- ===== catalogs =====
    local junkItems    = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems    = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe"}
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack"}

    -- ===== WindUI helpers (Title/Name variants) =====
    local function addLabel(text)
        if not pcall(function() tab:Label({ Title = text }) end) then
            pcall(function() tab:Label({ Name = text }) end)
        end
    end

    local function addToggle(title, default, cb)
        local w
        if not pcall(function() w = tab:Toggle({ Title = title, Default = default, Callback = cb }) end) or not w then
            pcall(function() w = tab:Toggle({ Name = title, Default = default, Callback = cb }) end)
        end
        return w
    end

    local function addButton(title, cb)
        if not pcall(function() tab:Button({ Title = title, Callback = cb }) end) then
            pcall(function() tab:Button({ Name = title, Callback = cb }) end)
        end
    end

    -- ===== WindUI-safe selector (button that cycles options) =====
    local function addSelector(title, list, default, onChange)
        local idx = table.find(list, default) or 1
        local function label() return ("%s: %s"):format(title, list[idx]) end
        addButton(label(), function()
            idx = (idx % #list) + 1
            onChange(list[idx])
        end)
        -- expose a tiny API if needed later
        return {
            Get = function() return list[idx] end,
            Set = function(v)
                local i = table.find(list, v); if i then idx = i; onChange(v) end
            end,
        }
    end

    -- ===== placement =====
    local function placeDown()
        local char = lp.Character; if not char then return end
        local hrp  = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end

        local basePos = hrp.Position + hrp.CFrame.LookVector * 10 + Vector3.new(0, 10, 0)

        for i, mdl in ipairs(G.Items) do
            if mdl and mdl.Parent then
                local pp = mdl.PrimaryPart or mdl:FindFirstChildWhichIsA("BasePart", true)
                if pp then
                    mdl.PrimaryPart = pp
                    for _, d in ipairs(mdl:GetDescendants()) do
                        if d:IsA("BasePart") then
                            d.Anchored = false
                            d.CanCollide = true
                            d.Massless = false
                            d.AssemblyLinearVelocity = Vector3.zero
                            d.AssemblyAngularVelocity = Vector3.zero
                        end
                    end
                    local offset = Vector3.new((i % 5) * 2, 0, math.floor(i / 5) * 2)
                    mdl:SetPrimaryPartCFrame(CFrame.new(basePos + offset))
                    pp.AssemblyLinearVelocity = Vector3.new(0, -10, 0)
                    task.wait()
                end
            end
        end

        -- auto-disable gather switch after placing
        G.Enabled = false
        if G._toggle and G._toggle.Set then pcall(function() G._toggle:Set(false) end) end
    end

    -- ===== controls at top =====
    G._toggle = addToggle("Enable Gather", G.Enabled, function(v) G.Enabled = v end)
    addButton("Place Items Now", placeDown)

    addLabel("Selections")

    -- ===== selectors (WindUI-safe) =====
    addSelector("Junk",          junkItems,    junkItems[1],    function(v) G.Selected.Junk    = v end)
    addSelector("Fuel",          fuelItems,    fuelItems[1],    function(v) G.Selected.Fuel    = v end)
    addSelector("Food",          foodItems,    foodItems[1],    function(v) G.Selected.Food    = v end)
    addSelector("Medical",       medicalItems, medicalItems[1], function(v) G.Selected.Medical = v end)
    addSelector("Weapons/Armor", weaponsArmor, weaponsArmor[1], function(v) G.Selected.WA      = v end)
    addSelector("Ammo/Misc",     ammoMisc,     ammoMisc[1],     function(v) G.Selected.Misc    = v end)

    addLabel("Gather Module Loaded")
end
