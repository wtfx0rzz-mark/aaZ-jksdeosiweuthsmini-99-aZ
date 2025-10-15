-- 1337 Nights | Gather Module (UI fix: robust dropdowns, controls at top, drop 10 forward & 10 up)
return function(C, R, UI)
    local Players = C.Services.Players
    local lp = Players.LocalPlayer
    local Tabs = UI and UI.Tabs or {}
    local tab = Tabs.Gather
    assert(tab, "Gather tab not found")

    C.State = C.State or {}
    C.State.Gather = C.State.Gather or { Enabled = false, Items = {}, Selected = {} }
    local G = C.State.Gather

    -- Catalogs
    local junkItems    = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems    = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe"}
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack"}

    -- ---------- UI helpers (resilient across libs) ----------
    local function addLabel(text)
        local ok = pcall(function() tab:Label({ Title = text }) end)
        if not ok then pcall(function() tab:AddLabel({ Title = text }) end) end
    end

    local function addToggle(title, default, cb)
        local widget
        local ok = pcall(function()
            widget = tab:Toggle({ Title = title, Default = default, Callback = cb })
        end)
        if not ok or not widget then
            ok = pcall(function()
                widget = tab:AddToggle({ Title = title, Default = default, Callback = cb })
            end)
        end
        -- Rayfield-style fallback
        if (not ok or not widget) then
            ok = pcall(function()
                widget = tab:Toggle({
                    Name = title, Default = default,
                    Callback = cb
                })
            end)
        end
        return widget
    end

    local function addButton(title, cb)
        local ok = pcall(function() tab:Button({ Title = title, Callback = cb }) end)
        if not ok then
            ok = pcall(function() tab:AddButton({ Title = title, Callback = cb }) end)
        end
        if not ok then
            pcall(function()
                tab:Button({ Name = title, Callback = cb })
            end)
        end
    end

    -- Dropdown that tries multiple APIs; degrades to a cycling button if needed
    local function addDropdown(title, list, defaultValue, onChange)
        assert(type(list) == "table" and #list > 0, "empty list for "..title)
        local current = defaultValue or list[1]
        G.Selected = G.Selected or {}
        onChange = onChange or function(_) end

        -- Try common variants
        local ok, widget = pcall(function()
            return tab:Dropdown({
                Title = title,
                Options = list,
                Default = current,
                Callback = function(val) current = val; onChange(val) end
            })
        end)
        if not ok or not widget then
            ok, widget = pcall(function()
                return tab:AddDropdown({
                    Title = title,
                    Options = list,
                    Default = current,
                    Callback = function(val) current = val; onChange(val) end
                })
            end)
        end
        if not ok or not widget then
            ok, widget = pcall(function()
                return tab:Dropdown({
                    Name = title,
                    Options = list,
                    CurrentOption = current,
                    Multi = false,
                    Callback = function(val) current = val; onChange(val) end
                })
            end)
        end

        -- Degrade to a simple cycling button if all dropdown constructors fail
        if not ok or not widget then
            local idx = table.find(list, current) or 1
            local function redrawLabel()
                return title .. ": " .. tostring(list[idx])
            end
            addButton(redrawLabel(), function()
                idx = (idx % #list) + 1
                current = list[idx]
                onChange(current)
            end)
            -- Return a lightweight shim so callers can .Set(...)
            return {
                Set = function(_, val)
                    local i = table.find(list, val)
                    if i then idx = i; current = val; onChange(val) end
                end,
                Get = function() return current end,
            }
        end

        -- Normalize Set for differing libs
        if widget and not widget.Set then
            widget.Set = function(_, val)
                local i = table.find(list, val)
                if i then
                    current = val
                    pcall(function() widget:Refresh(list, val) end)
                    pcall(function() widget:Set(val) end)
                    onChange(val)
                end
            end
        end

        return widget
    end

    -- ---------- Placement logic ----------
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
                            d.Massless = false
                            d.AssemblyLinearVelocity = Vector3.zero
                            d.AssemblyAngularVelocity = Vector3.zero
                        end
                    end
                    -- light scatter so boxes don’t interpenetrate too aggressively
                    local offset = Vector3.new((i % 5) * 2, 0, math.floor(i / 5) * 2)
                    mdl:SetPrimaryPartCFrame(CFrame.new(basePos + offset))
                    pp.AssemblyLinearVelocity = Vector3.new(0, -12, 0)
                    task.wait()
                end
            end
        end

        -- auto-disable gather
        G.Enabled = false
        if G._toggle and G._toggle.Set then pcall(function() G._toggle:Set(false) end) end
    end

    -- ---------- Controls at top ----------
    G._toggle = addToggle("Enable Gather", G.Enabled, function(v) G.Enabled = v end)
    addButton("Place Items Now", placeDown)

    addLabel("Selections")

    -- ---------- Dropdowns (fixed) ----------
    addDropdown("Junk",          junkItems,    junkItems[1],    function(v) G.Selected.Junk = v end)
    addDropdown("Fuel",          fuelItems,    fuelItems[1],    function(v) G.Selected.Fuel = v end)
    addDropdown("Food",          foodItems,    foodItems[1],    function(v) G.Selected.Food = v end)
    addDropdown("Medical",       medicalItems, medicalItems[1], function(v) G.Selected.Medical = v end)
    addDropdown("Weapons/Armor", weaponsArmor, weaponsArmor[1], function(v) G.Selected.WA = v end)
    addDropdown("Ammo/Misc",     ammoMisc,     ammoMisc[1],     function(v) G.Selected.Misc = v end)

    addLabel("Gather Module Loaded")
end
