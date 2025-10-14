--=====================================================
-- 1337 Nights | Bring Module (UI Setup)
--=====================================================
-- Creates:
--   • Text "Amount" with textbox (default 20)
--   • Dropdowns for each category:
--       Junk, Fuel, Food, Medical, Weapons/Armor, Ammo/Misc
--=====================================================

return function(C, R, UI)
    local Players = C.Services.Players
    local WS = C.Services.WS
    local lp = Players.LocalPlayer

    local Tabs = UI and UI.Tabs or {}
    local tab = Tabs.Bring
    assert(tab, "Bring tab not found in UI")

    -----------------------------------------------------
    --  Dropdown item lists
    -----------------------------------------------------
    local junkItems    = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems    = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe"}
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack"}

    -----------------------------------------------------
    --  UI controls
    -----------------------------------------------------

    -- Amount input
    tab:Label("Amount")
    local amountBox = tab:Textbox({
        Title = "Amount",
        Placeholder = "Enter amount",
        Default = "20",
        Callback = function(val)
            print("[Bring] Amount set to:", val)
        end
    })

    -- Dropdowns per category
    local dropdowns = {}

    dropdowns.Junk = tab:Dropdown({
        Title = "Junk Items",
        Values = junkItems,
        Multi = false,
        Default = junkItems[1],
        Callback = function(v)
            print("[Bring] Selected Junk Item:", v)
        end
    })

    dropdowns.Fuel = tab:Dropdown({
        Title = "Fuel Items",
        Values = fuelItems,
        Multi = false,
        Default = fuelItems[1],
        Callback = function(v)
            print("[Bring] Selected Fuel Item:", v)
        end
    })

    dropdowns.Food = tab:Dropdown({
        Title = "Food Items",
        Values = foodItems,
        Multi = false,
        Default = foodItems[1],
        Callback = function(v)
            print("[Bring] Selected Food Item:", v)
        end
    })

    dropdowns.Medical = tab:Dropdown({
        Title = "Medical Items",
        Values = medicalItems,
        Multi = false,
        Default = medicalItems[1],
        Callback = function(v)
            print("[Bring] Selected Medical Item:", v)
        end
    })

    dropdowns.WeaponsArmor = tab:Dropdown({
        Title = "Weapons & Armor",
        Values = weaponsArmor,
        Multi = false,
        Default = weaponsArmor[1],
        Callback = function(v)
            print("[Bring] Selected Weapon/Armor:", v)
        end
    })

    dropdowns.AmmoMisc = tab:Dropdown({
        Title = "Ammo / Misc Items",
        Values = ammoMisc,
        Multi = false,
        Default = ammoMisc[1],
        Callback = function(v)
            print("[Bring] Selected Ammo/Misc:", v)
        end
    })

    -----------------------------------------------------
    --  Expose UI elements for later logic use
    -----------------------------------------------------
    return {
        AmountBox = amountBox,
        Dropdowns = dropdowns
    }
end
