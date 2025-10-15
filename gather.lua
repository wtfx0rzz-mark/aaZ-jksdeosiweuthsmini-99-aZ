--=====================================================
-- 1337 Nights | Gather Module (Bring-style UI)
--  • Top: [Bring] button drops all gathered items
--  • Bring tab dropdowns replicated here
--  • One selection per dropdown (native single-select)
--  • Per-category "Gather <Category>" button starts gather
--  • Last Gather button clicked wins (switches target)
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
    local junkItems    = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems    = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe"}
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling"}
    local pelts        = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Polar Bear Pelt"}

    -- Current dropdown choices (per category)
    local pick = {
        Junk = junkItems[1], Fuel = fuelItems[1], Food = foodItems[1],
        Medical = medicalItems[1], WA = weaponsArmor[1], Misc = ammoMisc[1], Pelts = pelts[1],
    }

    -- Active gather target (global). Set by the last "Gather <Category>" click.
    local sel = { name=nil, special=nil }  -- special ∈ {"mossy","cultist","sapling"} or nil

    -- Tunables
    local hoverHeight, forwardDrop, upDrop = 0, 10, 5
    local scanInterval = 0.1

    -- Runtime
    local gatherOn = false
    local scanConn, hoverConn = nil, nil
    local gathered, list = {}, {}

    -------------------------------- Helpers ------------------------------
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

    -------------------------------- Matching ------------------------------
    local function isSelectedModel(m)
        if not sel.name and not sel.special then return false end
        if sel.special == "mossy" then
            return (m.Name == "Mossy Coin" or m.Name:match("^Mossy Coin%d+$"))
        elseif sel.special == "cultist" then
            local nl=(m.Name or ""):lower(); return nl:find("cultist",1,true) and hasHumanoid(m)
        elseif sel.special == "sapling" then
            return m.Name == "Sapling"
        else
            return m.Name == sel.name
        end
    end

    -------------------------------- Capture + Hover ------------------------------
    local lastScan = 0
    local function captureIfNear()
        local now = os.clock()
        if now - lastScan < scanInterval then return end
        lastScan = now

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
    end
    local function stopGather()
        gatherOn = false
        if scanConn  then pcall(function() scanConn:Disconnect()  end) end; scanConn=nil
        if hoverConn then pcall(function() hoverConn:Disconnect() end) end; hoverConn=nil
    end

    -------------------------------- Placement ------------------------------
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
    local function spreadCF(i, baseCF)
        local r   = 2 + math.floor((i-1)/8)
        local idx = (i-1) % 8
        local ang = (idx/8) * math.pi*2
        return baseCF + Vector3.new(math.cos(ang)*r, 0, math.sin(ang)*r)
    end

    local function placeDown()
        local baseCF = groundAheadCF(); if not baseCF then return end
        stopGather() -- avoid immediate re-capture

        for i,m in ipairs(list) do
            if m and m.Parent then
                startDrag(m)
                pivotModel(m, spreadCF(i, baseCF))
                stopDrag(m)
            end
        end

        task.wait(0.05)
        for _,m in ipairs(list) do
            if m and m.Parent then
                setAnchoredModel(m, false)
                setNoCollideModel(m, false)
                for _,p in ipairs(m:GetDescendants()) do
                    if p:IsA("BasePart") then p.AssemblyLinearVelocity = Vector3.new(0, -25, 0) end
                end
            end
        end
        clearAll()
    end

    -------------------------------- UI ------------------------------
    tab:Section({ Title = "Bring", Icon = "box" })
    tab:Button({ Title = "Bring", Callback = placeDown })
    tab:Divider()

    local function dropdownSingle(args)
        return tab:Dropdown({
            Title = args.title,
            Values = args.values,
            Multi = false,
            AllowNone = false,
            Callback = function(v) if v and v ~= "" then pick[args.key] = v end end
        })
    end

    local function gatherButton(label, resolver)
        tab:Button({
            Title = label,
            Callback = function()
                local name, special = resolver()
                sel.name, sel.special = name, special
                clearAll()
                startGather()
            end
        })
    end

    -- Junk
    tab:Section({ Title = "Junk" })
    dropdownSingle({ title="Select Junk Item", values=junkItems, key="Junk" })
    gatherButton("Gather Junk", function() return pick.Junk, nil end)

    -- Fuel
    tab:Section({ Title = "Fuel" })
    dropdownSingle({ title="Select Fuel Item", values=fuelItems, key="Fuel" })
    gatherButton("Gather Fuel", function() return pick.Fuel, nil end)

    -- Food
    tab:Section({ Title = "Food" })
    dropdownSingle({ title="Select Food Item", values=foodItems, key="Food" })
    gatherButton("Gather Food", function() return pick.Food, nil end)

    -- Medical
    tab:Section({ Title = "Medical" })
    dropdownSingle({ title="Select Medical Item", values=medicalItems, key="Medical" })
    gatherButton("Gather Medical", function() return pick.Medical, nil end)

    -- Weapons & Armor
    tab:Section({ Title = "Weapons & Armor" })
    dropdownSingle({ title="Select Weapon/Armor", values=weaponsArmor, key="WA" })
    gatherButton("Gather Weapons & Armor", function() return pick.WA, nil end)

    -- Ammo & Misc (handle specials)
    tab:Section({ Title = "Ammo & Misc." })
    dropdownSingle({ title="Select Ammo/Misc", values=ammoMisc, key="Misc" })
    gatherButton("Gather Ammo & Misc", function()
        local v = pick.Misc
        if v == "Mossy Coin" then return nil, "mossy"
        elseif v == "Cultist" then return nil, "cultist"
        elseif v == "Sapling" then return nil, "sapling"
        else return v, nil end
    end)

    -- Pelts
    tab:Section({ Title = "Pelts" })
    dropdownSingle({ title="Select Pelt", values=pelts, key="Pelts" })
    gatherButton("Gather Pelts", function() return pick.Pelts, nil end)

    -- Safety: persist across respawn if mid-gather
    lp.CharacterAdded:Connect(function()
        if gatherOn then task.defer(function() stopGather(); startGather() end) end
    end)
end
