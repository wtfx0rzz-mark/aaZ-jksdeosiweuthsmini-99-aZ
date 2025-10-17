--=====================================================
-- 1337 Nights | Gather Module (Multi-select + One "Gather Items" button)
--  • Top [Bring] and on-screen [Place] drop items in a compact pile
--  • Category dropdowns support MULTI select with tap-to-toggle entries
--  • One global "Gather Items" button captures union of selections
--  • Pattern matches in Misc: Blueprint, Forest Gem(+Fragment), Key variants,
--    Flashlight (old|strong), Taming flute (old|good|strong)
--=====================================================
return function(C, R, UI)
    local Players = C.Services.Players
    local RS      = C.Services.RS
    local WS      = C.Services.WS
    local Run     = C.Services.Run

    local lp  = Players.LocalPlayer
    local tab = UI.Tabs and (UI.Tabs.Gather or UI.Tabs.Auto)
    assert(tab, "Gather tab not found")

    -- Bring taxonomy
    local junkItems    = {
        "Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine",
        "UFO Junk","UFO Component"
    }
    local fuelItems    = {
        "Log","Chair","Coal","Fuel Canister","Oil Barrel","Biofuel"
    }
    local foodItems    = {
        "Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot",
        "Chilli","Stew","Ribs","Pumpkin","Hearty Stew","Cooked Ribs","Corn","BBQ ribs","Apple","Mackerel"
    }
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {
        "Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe",
        "Chainsaw","Crossbow","Katana","Kunai","Laser cannon","Laser sword","Morningstar","Riot shield","Spear","Tactical Shotgun","Wildfire"
    }
    local ammoMisc     = {
        "Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling",
        "Basketball","Blueprint","Diamond","Forest Gem","Key","Flashlight","Taming flute"
    }
    local pelts        = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Polar Bear Pelt","Arctic Fox Pelt"}

    -- Multi-select state per category (sets)
    local Selected = {
        Junk = {}, Fuel = {}, Food = {}, Medical = {}, WA = {}, Misc = {}, Pelts = {}
    }
    -- Specials/patterns from Misc
    local wantMossy, wantCultist, wantSapling = false, false, false
    local wantBlueprint, wantForestGem, wantKey, wantFlashlight, wantTamingFlute = false, false, false, false, false

    -- Tunables
    local hoverHeight    = 5
    local forwardDrop    = 10
    local upDrop         = 5
    local scanInterval   = 0.1

    -- Pile drop tuning
    local PILE_RADIUS    = 1.25
    local LAYER_SIZE     = 14
    local LAYER_HEIGHT   = 0.35
    local UNANCHOR_BATCH = 6
    local UNANCHOR_STEP  = 0.03
    local NUDGE_DOWN     = 4

    -- Runtime
    local gatherOn = false
    local scanConn, hoverConn = nil, nil
    local gathered, list = {}, {}

    -- Hold dropdown refs so we can reset them
    local DD = { Junk=nil, Fuel=nil, Food=nil, Medical=nil, WA=nil, Misc=nil, Pelts=nil }

    ----------------------------------------------------------------------
    -- Helpers
    ----------------------------------------------------------------------
    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local function auraRadius()
        return math.clamp(tonumber(C.State and C.State.AuraRadius) or 150, 0, 500)
    end
    local function mainPart(obj)
        if not obj then return nil end
        if obj:IsA("BasePart") then return obj end
        if obj:IsA("Model") then
            if obj.PrimaryPart then return obj.PrimaryPart end
            return obj:FindFirstChildWhichIsA("BasePart")
        end
        return nil
    end
    local function modelOf(x) return x and (x:IsA("Model") and x or x:FindFirstAncestorOfClass("Model")) or nil end
    local function isExcludedModel(m)
        if not (m and m:IsA("Model")) then return true end
        local n = (m.Name or ""):lower()
        return n == "pelt trader" or n:find("trader",1,true) or n:find("shopkeeper",1,true)
    end
    local function hasHumanoid(m) return m and m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") ~= nil end

    -- Remotes
    local function getRemote(n) local f=RS:FindFirstChild("RemoteEvents"); return f and f:FindFirstChild(n) or nil end
    local function startDrag(m) local re=getRemote("RequestStartDraggingItem"); if re then pcall(function() re:FireServer(m) end) end end
    local function stopDrag(m)  local re=getRemote("StopDraggingItem");        if re then pcall(function() re:FireServer(m) end) end end

    -- Physics toggles
    local function setNoCollideModel(m, on)
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then
                d.CanCollide = not on
                d.CanQuery   = not on
                d.CanTouch   = not on
                d.Massless   = on and true or false
                d.AssemblyLinearVelocity  = Vector3.new()
                d.AssemblyAngularVelocity = Vector3.new()
            end
        end
    end
    local function setAnchoredModel(m, on)
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then d.Anchored = on end
        end
    end

    -- Track set
    local function addGather(m) if not gathered[m] then gathered[m]=true; list[#list+1]=m end end
    local function removeGather(m)
        if not gathered[m] then return end
        gathered[m]=nil
        for i=#list,1,-1 do if list[i]==m then table.remove(list,i) break end end
    end
    local function clearAll() for m,_ in pairs(gathered) do gathered[m]=nil end; table.clear(list) end

    local function anySelection()
        if wantMossy or wantCultist or wantSapling or wantBlueprint or wantForestGem or wantKey or wantFlashlight or wantTamingFlute then
            return true
        end
        for _,set in pairs(Selected) do
            for _ in pairs(set) do return true end
        end
        return false
    end

    ----------------------------------------------------------------------
    -- Matching (union of all selected sets + specials)
    ----------------------------------------------------------------------
    local function isSelectedModel(m)
        if not m or not m:IsA("Model") then return false end
        local name = m.Name or ""
        local nl   = name:lower()

        -- specials
        if wantMossy and (name == "Mossy Coin" or name:match("^Mossy Coin%d+$")) then return true end
        if wantCultist and nl:find("cultist",1,true) and hasHumanoid(m) then return true end
        if wantSapling and name == "Sapling" then return true end

        -- pattern selections
        if wantBlueprint and nl:find("blueprint", 1, true) then return true end
        if wantForestGem and (name == "Forest Gem" or nl:find("forest gem fragment", 1, true)) then return true end
        if wantKey then
            if nl:find(" key", 1, true) then
                if nl:find("blue key",1,true) or nl:find("yellow key",1,true) or nl:find("red key",1,true)
                or nl:find("gray key",1,true) or nl:find("grey key",1,true) or nl:find("frog key",1,true) then
                    return true
                end
            end
        end
        if wantFlashlight and nl:find("flashlight",1,true) and (nl:find("old",1,true) or nl:find("strong",1,true)) then
            return true
        end
        if wantTamingFlute and nl:find("taming flute",1,true) and (nl:find("old",1,true) or nl:find("good",1,true) or nl:find("strong",1,true)) then
            return true
        end

        -- regular category membership (exact)
        return Selected.Junk[name] or Selected.Fuel[name] or Selected.Food[name]
            or Selected.Medical[name] or Selected.WA[name] or Selected.Misc[name]
            or Selected.Pelts[name] or false
    end

    ----------------------------------------------------------------------
    -- Capture + Hover
    ----------------------------------------------------------------------
    local lastScan = 0
    local function captureIfNear()
        local now = os.clock()
        if now - lastScan < scanInterval then return end
        lastScan = now
        if not gatherOn then return end
        if not anySelection() then return end

        local root = hrp(); if not root then return end
        local origin = root.Position
        local rad = auraRadius()
        local pool = WS:FindFirstChild("Items") or WS

        for _,d in ipairs(pool:GetDescendants()) do
            repeat
                if not (d:IsA("Model") or d:IsA("BasePart")) then break end
                local m = modelOf(d); if not m then break end
                if gathered[m] or isExcludedModel(m) or not isSelectedModel(m) then break end
                local mp = mainPart(m); if not mp then break end
                if (mp.Position - origin).Magnitude > rad then break end

                startDrag(m)
                task.wait(0.02)
                pcall(function() mp:SetNetworkOwner(lp) end)
                setNoCollideModel(m, true)
                setAnchoredModel(m, true)
                addGather(m)
                stopDrag(m)
            until true
        end
    end

    local function pivotModel(m, cf)
        if m:IsA("Model") then m:PivotTo(cf) else local p=mainPart(m); if p then p.CFrame=cf end end
    end

    local function hoverFollow()
        if not gatherOn then return end
        local root = hrp(); if not root then return end
        local forward = root.CFrame.LookVector
        local above   = root.Position + Vector3.new(0, hoverHeight, 0)
        local baseCF  = CFrame.lookAt(above, above + forward)
        for _,m in ipairs(list) do
            if m and m.Parent then pivotModel(m, baseCF) else removeGather(m) end
        end
    end

    local function startGather()
        if gatherOn then return end
        gatherOn = true
        scanConn  = Run.Heartbeat:Connect(captureIfNear)
        hoverConn = Run.RenderStepped:Connect(hoverFollow)
        if _G._PlaceEdgeBtn then _G._PlaceEdgeBtn.Visible = true end
    end
    local function stopGather()
        gatherOn = false
        if scanConn  then pcall(function() scanConn:Disconnect()  end) end; scanConn=nil
        if hoverConn then pcall(function() hoverConn:Disconnect() end) end; hoverConn=nil
    end

    ----------------------------------------------------------------------
    -- Placement
    ----------------------------------------------------------------------
    local function groundAheadCF()
        local root = hrp(); if not root then return nil end
        local forward = root.CFrame.LookVector
        local ahead   = root.Position + forward * forwardDrop + Vector3.new(0, 40, 0)
        local params  = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {lp.Character}
        local rc = WS:Raycast(ahead, Vector3.new(0, -200, 0), params)
        local hitPos = rc and rc.Position or (root.Position + forward * forwardDrop)
        local drop   = hitPos + Vector3.new(0, upDrop, 0)
        return CFrame.lookAt(drop, drop + forward)
    end

    local function pileCF(i, baseCF)
        local idx0   = i - 1
        local layer  = math.floor(idx0 / LAYER_SIZE)
        local inLayer= idx0 % LAYER_SIZE

        local angle  = (inLayer / LAYER_SIZE) * math.pi * 2
        local r      = (0.25 + (inLayer % 7) * 0.07) * PILE_RADIUS
        local x      = math.cos(angle) * r + (math.random() - 0.5) * 0.12
        local z      = math.sin(angle) * r + (math.random() - 0.5) * 0.12
        local y      = layer * LAYER_HEIGHT

        return baseCF * CFrame.new(x, y, z)
    end

    local function finalizePileDrop(items)
        for _,m in ipairs(items) do
            if m and m.Parent then
                setNoCollideModel(m, false)
                for _,p in ipairs(m:GetDescendants()) do
                    if p:IsA("BasePart") then
                        p.AssemblyLinearVelocity  = Vector3.new()
                        p.AssemblyAngularVelocity = Vector3.new()
                    end
                end
            end
        end

        for _,m in ipairs(items) do
            if m and m.Parent and m.Name == "Morsel" then
                local mp = mainPart(m)
                if mp then
                    pcall(function() mp:SetNetworkOwner(nil) end)
                    pcall(function() if mp.SetNetworkOwnershipAuto then mp:SetNetworkOwnershipAuto() end end)
                end
                for _,p in ipairs(m:GetDescendants()) do
                    if p:IsA("BasePart") then
                        p.CollisionGroupId = 0
                        p.CanCollide = true; p.CanTouch = true; p.CanQuery = true
                        p.Massless   = false
                    end
                end
            end
        end

        local n = #items
        local i = 1
        while i <= n do
            for j = i, math.min(i + UNANCHOR_BATCH - 1, n) do
                local m = items[j]
                if m and m.Parent then
                    setAnchoredModel(m, false)
                    for _,p in ipairs(m:GetDescendants()) do
                        if p:IsA("BasePart") then
                            p.AssemblyLinearVelocity  = Vector3.new(0, -NUDGE_DOWN, 0)
                            p.AssemblyAngularVelocity = Vector3.new()
                        end
                    end
                end
            end
            task.wait(UNANCHOR_STEP)
            i = i + UNANCHOR_BATCH
        end
    end

    local function placeDown()
        local baseCF = groundAheadCF(); if not baseCF then return end

        if _G._PlaceEdgeBtn then _G._PlaceEdgeBtn.Visible = false end
        stopGather()

        for i,m in ipairs(list) do
            if m and m.Parent then
                startDrag(m)
                setAnchoredModel(m, true)
                setNoCollideModel(m, true)
                pivotModel(m, pileCF(i, baseCF))
                stopDrag(m)
            end
        end

        task.wait(0.03)
        finalizePileDrop(list)
        clearAll()
    end

    -- Export small API
    C.Gather = C.Gather or {}
    C.Gather.IsOn      = function() return gatherOn end
    C.Gather.PlaceDown = placeDown

    ----------------------------------------------------------------------
    -- UI
    ----------------------------------------------------------------------
    tab:Section({ Title = "Bring", Icon = "box" })
    tab:Button({ Title = "Drop Items", Callback = function() placeDown() end })
    tab:Divider()

    -- Clear Selections
    local function clearSelectionsUI()
        for _,set in pairs(Selected) do for k in pairs(set) do set[k] = nil end end
        wantMossy, wantCultist, wantSapling = false, false, false
        wantBlueprint, wantForestGem, wantKey, wantFlashlight, wantTamingFlute = false, false, false, false, false
        stopGather()
        clearAll()
        local function reset(w)
            if not w then return end
            pcall(function() if w.Set then w:Set({}) end end)
            pcall(function() if w.SetValue then w:SetValue({}) end end)
            pcall(function() if w.SetValues then w:SetValues({}) end end)
            pcall(function() if w.Clear then w:Clear() end end)
        end
        for _,w in pairs(DD) do reset(w) end
    end

    tab:Button({ Title = "Clear Selections", Callback = clearSelectionsUI })

    tab:Button({
        Title = "Gather Items",
        Callback = function()
            if anySelection() then
                clearAll()
                startGather()
            end
        end
    })
    tab:Divider()

    local function dropdownMulti(args)
        local widget = tab:Dropdown({
            Title = args.title,
            Values = args.values,
            Multi = true,
            AllowNone = true,
            Callback = function(options)
                local set = args.set
                for k,_ in pairs(set) do set[k] = nil end
                if args.kind == "Misc" then
                    wantMossy, wantCultist, wantSapling = false, false, false
                    wantBlueprint, wantForestGem, wantKey, wantFlashlight, wantTamingFlute = false, false, false, false, false
                    for _,v in ipairs(options) do
                        if v == "Mossy Coin" then
                            wantMossy = true
                        elseif v == "Cultist" then
                            wantCultist = true
                        elseif v == "Sapling" then
                            wantSapling = true
                        elseif v == "Blueprint" then
                            wantBlueprint = true
                        elseif v == "Forest Gem" then
                            wantForestGem = true
                        elseif v == "Key" then
                            wantKey = true
                        elseif v == "Flashlight" then
                            wantFlashlight = true
                        elseif v == "Taming flute" then
                            wantTamingFlute = true
                        else
                            set[v] = true
                        end
                    end
                else
                    for _,v in ipairs(options) do set[v] = true end
                end
            end
        })
        return widget
    end

    tab:Section({ Title = "Junk" })
    DD.Junk = dropdownMulti({ title="Select Junk Items", values=junkItems, set=Selected.Junk, kind="Junk" })

    tab:Section({ Title = "Fuel" })
    DD.Fuel = dropdownMulti({ title="Select Fuel Items", values=fuelItems, set=Selected.Fuel, kind="Fuel" })

    tab:Section({ Title = "Food" })
    DD.Food = dropdownMulti({ title="Select Food Items", values=foodItems, set=Selected.Food, kind="Food" })

    tab:Section({ Title = "Medical" })
    DD.Medical = dropdownMulti({ title="Select Medical Items", values=medicalItems, set=Selected.Medical, kind="Medical" })

    tab:Section({ Title = "Weapons & Armor" })
    DD.WA = dropdownMulti({ title="Select Weapon/Armor", values=weaponsArmor, set=Selected.WA, kind="WA" })

    tab:Section({ Title = "Ammo & Misc." })
    DD.Misc = dropdownMulti({ title="Select Ammo/Misc", values=ammoMisc, set=Selected.Misc, kind="Misc" })

    tab:Section({ Title = "Pelts" })
    DD.Pelts = dropdownMulti({ title="Select Pelts", values=pelts, set=Selected.Pelts, kind="Pelts" })

    ----------------------------------------------------------------------
    -- Edge "Place" button (shared screen GUI)
    ----------------------------------------------------------------------
    local function ensurePlaceEdge()
        local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
        local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
        if not edgeGui then
            edgeGui = Instance.new("ScreenGui")
            edgeGui.Name = "EdgeButtons"
            edgeGui.ResetOnSpawn = false
            edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            edgeGui.Parent = playerGui
        end
        local btn = edgeGui:FindFirstChild("PlaceEdge")
        if not btn then
            btn = Instance.new("TextButton")
            btn.Name = "PlaceEdge"
            btn.AnchorPoint = Vector2.new(1, 0)
            btn.Position    = UDim2.new(1, -6, 0, 6)
            btn.Size        = UDim2.new(0, 120, 0, 30)
            btn.Text        = "Place"
            btn.TextSize    = 12
            btn.Font        = Enum.Font.GothamBold
            btn.BackgroundColor3 = Color3.fromRGB(30,30,35)
            btn.TextColor3  = Color3.new(1,1,1)
            btn.BorderSizePixel = 0
            btn.Visible     = false
            btn.Parent      = edgeGui
            local corner  = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 8)
            corner.Parent = btn
        end
        return btn
    end

    _G._PlaceEdgeBtn = ensurePlaceEdge()
    _G._PlaceEdgeBtn.MouseButton1Click:Connect(function()
        _G._PlaceEdgeBtn.Visible = false
        placeDown()
    end)

    lp.CharacterAdded:Connect(function()
        if _G._PlaceEdgeBtn then _G._PlaceEdgeBtn.Visible = false end
        if gatherOn then task.defer(function() stopGather(); startGather() end) end
    end)
end
