--=====================================================
-- 1337 Nights | Gather Module (Multi-select, Bring-parity)
--  • Uses same item taxonomy as Bring
--  • Captures any selected items within AuraRadius
--  • Hover carry: 5 studs above HRP, tight stack (no collide, anchored)
--  • Place Down: +5f/+5u, radial spread, re-enable physics, auto toggle OFF
--=====================================================
return function(C, R, UI)
    local Players = C.Services.Players
    local RS      = C.Services.RS
    local WS      = C.Services.WS
    local Run     = C.Services.Run

    local lp  = Players.LocalPlayer
    local tab = UI.Tabs and (UI.Tabs.Gather or UI.Tabs.Auto)
    assert(tab, "Gather tab not found (use UI.Tabs.Gather or UI.Tabs.Auto)")

    -----------------------------------------------------
    -- Bring taxonomy (mirrored)
    -----------------------------------------------------
    local junkItems    = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems    = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe"}
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling"}
    local pelts        = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Polar Bear Pelt"}

    -----------------------------------------------------
    -- Selection state (multi)
    -----------------------------------------------------
    local sel = {
        simple = {},           -- exact-name items across categories (excludes the 3 specials)
        pelts  = {},           -- exact pelts
        wantMossyCoin = false,
        wantCultist   = false,
        wantSapling   = false,
    }
    local function clearTable(t) for k in pairs(t) do t[k]=nil end end

    -----------------------------------------------------
    -- Tunables and runtime
    -----------------------------------------------------
    local hoverHeight = 5
    local forwardDrop = 5
    local upDrop      = 5

    local gatherOn    = false
    local scanConn, hoverConn
    local gathered    = {}   -- set: [Model]=true
    local list        = {}   -- array of Models (stable order)
    local GatherToggleCtrl

    -----------------------------------------------------
    -- Helpers
    -----------------------------------------------------
    local function hrp()
        local ch = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local function humanoid()
        local ch = Players.LocalPlayer.Character
        return ch and ch:FindFirstChildOfClass("Humanoid")
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
    local function isExcludedModel(m)
        if not (m and m:IsA("Model")) then return true end
        local n = (m.Name or ""):lower()
        return n == "pelt trader" or n:find("trader",1,true) or n:find("shopkeeper",1,true)
    end
    local function hasHumanoid(m)
        return m and m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") ~= nil
    end
    local function getRemote(n)
        local f = RS:FindFirstChild("RemoteEvents")
        return f and f:FindFirstChild(n) or nil
    end
    local function startDrag(m)
        local re = getRemote("RequestStartDraggingItem")
        if re then pcall(function() re:FireServer(m) end) end
    end
    local function stopDrag(m)
        local re = getRemote("StopDraggingItem")
        if re then pcall(function() re:FireServer(m) end) end
    end
    local function setNoCollideModel(m, on)
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then
                d.CanCollide = not on and true or false
                d.CanQuery   = not on and true or false
                d.CanTouch   = not on and true or false
                if on then d.Massless = true end
                d.AssemblyLinearVelocity  = Vector3.new()
                d.AssemblyAngularVelocity = Vector3.new()
            end
        end
    end
    local function setAnchoredModel(m, on)
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then d.Anchored = on and true or false end
        end
    end
    local function addGather(m)
        if gathered[m] then return end
        gathered[m] = true
        list[#list+1] = m
    end
    local function removeGather(m)
        if not gathered[m] then return end
        gathered[m] = nil
        for i=#list,1,-1 do
            if list[i] == m then table.remove(list, i) break end
        end
    end
    local function clearAll()
        for m,_ in pairs(gathered) do gathered[m] = nil end
        table.clear(list)
    end

    -----------------------------------------------------
    -- Matching logic (Bring-parity)
    -----------------------------------------------------
    local simpleCache = {}  -- k=name -> true
    local function rebuildSimpleCache()
        clearTable(simpleCache)
        for k,v in pairs(sel.simple) do if v then simpleCache[k]=true end end
        for k,v in pairs(sel.pelts)  do if v then simpleCache[k]=true end end
    end

    local function isSelectedModel(m)
        if not (m and m:IsA("Model") and m.Parent) then return false end
        if isExcludedModel(m) then return false end
        local name = m.Name

        -- Special: Mossy Coin (exact or numbered suffix)
        if sel.wantMossyCoin and (name == "Mossy Coin" or name:match("^Mossy Coin%d+$")) then
            return true
        end

        -- Special: Cultist (name contains "cultist" and has Humanoid)
        if sel.wantCultist then
            local nl = (name or ""):lower()
            if nl:find("cultist",1,true) and hasHumanoid(m) then
                return true
            end
        end

        -- Special: Sapling (exact name)
        if sel.wantSapling and name == "Sapling" then
            return true
        end

        -- Simple exact-name match (across all non-specials + pelts)
        if simpleCache[name] then
            return true
        end

        return false
    end

    -----------------------------------------------------
    -- Hover follow and capture
    -----------------------------------------------------
    local lastScan = 0
    local function captureIfNear()
        local now = os.clock()
        if now - lastScan < 0.2 then return end  -- throttle deep scan
        lastScan = now

        local root = hrp()
        if not root then return end
        local origin = root.Position
        local rad = auraRadius()

        -- Prefer Items folder when present, else scan Workspace
        local pools = {}
        local items = WS:FindFirstChild("Items")
        if items then pools[#pools+1] = items else pools[#pools+1] = WS end

        for _,pool in ipairs(pools) do
            for _,m in ipairs(pool:GetDescendants()) do
                repeat
                    if not m:IsA("Model") then break end
                    if gathered[m] then break end
                    if not isSelectedModel(m) then break end
                    local mp = mainPart(m); if not mp then break end
                    if (mp.Position - origin).Magnitude > rad then break end

                    -- Capture: drag, local authority, noclip+anchor, add to set
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
    end

    local function pivotModel(m, cf)
        if m:IsA("Model") then m:PivotTo(cf)
        else
            local p = mainPart(m)
            if p then p.CFrame = cf end
        end
    end

    local function hoverFollow()
        local root = hrp(); if not root then return end
        local forward = root.CFrame.LookVector
        local above   = root.Position + Vector3.new(0, hoverHeight, 0)
        local baseCF  = CFrame.lookAt(above, above + forward)

        for i,m in ipairs(list) do
            if m and m.Parent then
                pivotModel(m, baseCF) -- tight stack: all same CFrame
            else
                removeGather(m)
            end
        end
    end

    local function startGather()
        if scanConn then return end
        scanConn  = Run.Heartbeat:Connect(captureIfNear)
        hoverConn = Run.RenderStepped:Connect(hoverFollow)
        gatherOn  = true
    end
    local function stopGather()
        gatherOn = false
        if scanConn  then pcall(function() scanConn:Disconnect()  end) end; scanConn  = nil
        if hoverConn then pcall(function() hoverConn:Disconnect() end) end; hoverConn = nil
    end

    -----------------------------------------------------
    -- Place Down
    -----------------------------------------------------
    local function computeSpreadCF(i, baseCF)
        -- ring spread: 8 per ring, radius grows by 2 studs each ring
        local r    = 2 + math.floor((i-1)/8)
        local idx  = (i-1) % 8
        local ang  = (idx/8) * math.pi*2
        local off  = Vector3.new(math.cos(ang)*r, 0, math.sin(ang)*r)
        return baseCF + off
    end

    local function placeDown()
        local root = hrp(); if not root then return end

        -- Turn OFF gather before we drop to avoid immediate re-capture
        if GatherToggleCtrl and GatherToggleCtrl.Set then
            GatherToggleCtrl:Set(false)
        end
        stopGather()

        local forward = root.CFrame.LookVector
        local dropPos = root.Position + forward * forwardDrop + Vector3.new(0, upDrop, 0)
        local baseCF  = CFrame.lookAt(dropPos, dropPos + forward)

        -- Spread apart at target
        for i,m in ipairs(list) do
            if m and m.Parent then
                pivotModel(m, computeSpreadCF(i, baseCF))
            end
        end

        task.wait(0.05)

        -- Re-enable physics and collisions, then clear tracking
        for _,m in ipairs(list) do
            if m and m.Parent then
                setAnchoredModel(m, false)
                setNoCollideModel(m, false)
            end
        end
        clearAll()
    end

    -----------------------------------------------------
    -- UI
    -----------------------------------------------------
    tab:Section({ Title = "Gather • Select Items (multi)", Icon = "layers" })

    local function onMultiSelect(values, specialsMap, intoSet)
        -- values: array of strings returned by Multi dropdown
        -- specialsMap: table of special flags to watch
        -- intoSet: which destination set to write (sel.simple or sel.pelts)
        -- Reset current selections in the target set
        clearTable(intoSet)
        -- Reset specials referenced by this dropdown
        for flag,_ in pairs(specialsMap or {}) do sel[flag] = false end

        local mark = {}
        for _,v in ipairs(values or {}) do mark[v] = true end

        -- Handle specials that live in ammoMisc
        if specialsMap then
            if mark["Mossy Coin"] then sel.wantMossyCoin = true end
            if mark["Cultist"]   then sel.wantCultist   = true end
            if mark["Sapling"]   then sel.wantSapling   = true end
        end

        -- Write non-specials into the target exact-match set
        for name,_ in pairs(mark) do
            repeat
                if specialsMap and (name == "Mossy Coin" or name == "Cultist" or name == "Sapling") then
                    break
                end
                intoSet[name] = true
            until true
        end

        rebuildSimpleCache()
    end

    -- Junk
    tab:Dropdown({
        Title = "Junk",
        Values = junkItems,
        Multi = true,
        AllowNone = true,
        Callback = function(vals) onMultiSelect(vals, nil, sel.simple) end
    })
    -- Fuel
    tab:Dropdown({
        Title = "Fuel",
        Values = fuelItems,
        Multi = true,
        AllowNone = true,
        Callback = function(vals) onMultiSelect(vals, nil, sel.simple) end
    })
    -- Food
    tab:Dropdown({
        Title = "Food",
        Values = foodItems,
        Multi = true,
        AllowNone = true,
        Callback = function(vals) onMultiSelect(vals, nil, sel.simple) end
    })
    -- Medical
    tab:Dropdown({
        Title = "Medical",
        Values = medicalItems,
        Multi = true,
        AllowNone = true,
        Callback = function(vals) onMultiSelect(vals, nil, sel.simple) end
    })
    -- Weapons & Armor
    tab:Dropdown({
        Title = "Weapons & Armor",
        Values = weaponsArmor,
        Multi = true,
        AllowNone = true,
        Callback = function(vals) onMultiSelect(vals, nil, sel.simple) end
    })
    -- Ammo & Misc (contains specials)
    tab:Dropdown({
        Title = "Ammo & Misc",
        Values = ammoMisc,
        Multi = true,
        AllowNone = true,
        Callback = function(vals)
            onMultiSelect(vals, {wantMossyCoin=true, wantCultist=true, wantSapling=true}, sel.simple)
        end
    })
    -- Pelts (exact-name class)
    tab:Dropdown({
        Title = "Pelts",
        Values = pelts,
        Multi = true,
        AllowNone = true,
        Callback = function(vals) onMultiSelect(vals, nil, sel.pelts) end
    })

    tab:Divider()

    GatherToggleCtrl = tab:Toggle({
        Title = "Enable Gather",
        Value = false,
        Callback = function(state)
            if state then startGather() else stopGather() end
        end
    })

    tab:Button({
        Title = "Place Down",
        Callback = placeDown
    })

    Players.LocalPlayer.CharacterAdded:Connect(function()
        if gatherOn then
            task.defer(function()
                stopGather()
                startGather()
            end)
        end
    end)
end
