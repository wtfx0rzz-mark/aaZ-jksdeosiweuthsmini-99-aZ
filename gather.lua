return function(C, R, UI)
    local Players = C.Services.Players
    local RS      = C.Services.RS
    local WS      = C.Services.WS
    local Run     = C.Services.Run

    local lp  = Players.LocalPlayer
    local tab = UI.Tabs and (UI.Tabs.Gather or UI.Tabs.Auto)
    assert(tab, "Gather tab not found")

    local junkItems    = {"Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
    local fuelItems    = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
    local foodItems    = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe"}
    local ammoMisc     = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling"}
    local pelts        = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Polar Bear Pelt"}

    local sel = { name=nil, special=nil }
    local hoverHeight, forwardDrop, upDrop = 5, 10, 5
    local scanInterval = 0.1

    local gatherOn, scanConn, hoverConn = false, nil, nil
    local gathered, list = {}, {}
    local GatherToggleCtrl

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local function humanoid()
        local ch = lp.Character
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
    local function modelOf(x)
        if not x then return nil end
        return x:IsA("Model") and x or x:FindFirstAncestorOfClass("Model")
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
        for m,_ in pairs(gathered) do gathered[m]=nil end
        table.clear(list)
    end

    local function isSelectedModel(m)
        if not sel.name then return false end
        if sel.special == "mossy" then
            return (m.Name == "Mossy Coin" or m.Name:match("^Mossy Coin%d+$"))
        elseif sel.special == "cultist" then
            local nl = (m.Name or ""):lower()
            return nl:find("cultist",1,true) and hasHumanoid(m)
        elseif sel.special == "sapling" then
            return m.Name == "Sapling"
        else
            return m.Name == sel.name
        end
    end

    local lastScan = 0
    local function captureIfNear()
        local now = os.clock()
        if now - lastScan < scanInterval then return end
        lastScan = now

        local root = hrp(); if not root then return end
        local origin = root.Position
        local rad = auraRadius()

        local pools = {}
        local items = WS:FindFirstChild("Items")
        if items then pools[#pools+1] = items else pools[#pools+1] = WS end

        for _,pool in ipairs(pools) do
            for _,d in ipairs(pool:GetDescendants()) do
                repeat
                    if not (d:IsA("Model") or d:IsA("BasePart")) then break end
                    local m = modelOf(d); if not m then break end
                    if gathered[m] then break end
                    if isExcludedModel(m) then break end
                    if not isSelectedModel(m) then break end
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
        for _,m in ipairs(list) do
            if m and m.Parent then
                pivotModel(m, baseCF)
            else
                removeGather(m)
            end
        end
    end

    local function startGather()
        if scanConn then return end
        gatherOn  = true
        scanConn  = Run.Heartbeat:Connect(captureIfNear)
        hoverConn = Run.RenderStepped:Connect(hoverFollow)
    end
    local function stopGather()
        gatherOn = false
        if scanConn  then pcall(function() scanConn:Disconnect()  end) end; scanConn  = nil
        if hoverConn then pcall(function() hoverConn:Disconnect() end) end; hoverConn = nil
    end

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

    local function placeDown()
        local baseCF = groundAheadCF(); if not baseCF then return end
        if GatherToggleCtrl and GatherToggleCtrl.Set then GatherToggleCtrl:Set(false) end
        stopGather()

        for i,m in ipairs(list) do
            if m and m.Parent then
                startDrag(m)
                pivotModel(m, baseCF + Vector3.new((i%6)*2, 0, math.floor(i/6)*2))
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

    local function selectOnly(name, special)
        sel.name, sel.special = name, special
        clearAll()
    end
    local function clearOtherDropdowns(skip)
        if skip ~= "Junk"    and _G._JunkSet    then _G._JunkSet({}) end
        if skip ~= "Fuel"    and _G._FuelSet    then _G._FuelSet({}) end
        if skip ~= "Food"    and _G._FoodSet    then _G._FoodSet({}) end
        if skip ~= "Medical" and _G._MedSet     then _G._MedSet({}) end
        if skip ~= "WA"      and _G._WASet      then _G._WASet({}) end
        if skip ~= "Misc"    and _G._MiscSet    then _G._MiscSet({}) end
        if skip ~= "Pelts"   and _G._PeltsSet   then _G._PeltsSet({}) end
    end

    tab:Section({ Title = "Gather • Single selection", Icon = "layers" })

    _G._JunkSet = tab:Dropdown({
        Title = "Junk",
        Values = junkItems,
        Multi = false,
        AllowNone = true,
        Callback = function(v)
            clearOtherDropdowns("Junk")
            if v and v ~= "" then selectOnly(v, nil) else selectOnly(nil, nil) end
        end
    }).Set

    _G._FuelSet = tab:Dropdown({
        Title = "Fuel",
        Values = fuelItems,
        Multi = false,
        AllowNone = true,
        Callback = function(v)
            clearOtherDropdowns("Fuel")
            if v and v ~= "" then selectOnly(v, nil) else selectOnly(nil, nil) end
        end
    }).Set

    _G._FoodSet = tab:Dropdown({
        Title = "Food",
        Values = foodItems,
        Multi = false,
        AllowNone = true,
        Callback = function(v)
            clearOtherDropdowns("Food")
            if v and v ~= "" then selectOnly(v, nil) else selectOnly(nil, nil) end
        end
    }).Set

    _G._MedSet = tab:Dropdown({
        Title = "Medical",
        Values = medicalItems,
        Multi = false,
        AllowNone = true,
        Callback = function(v)
            clearOtherDropdowns("Medical")
            if v and v ~= "" then selectOnly(v, nil) else selectOnly(nil, nil) end
        end
    }).Set

    _G._WASet = tab:Dropdown({
        Title = "Weapons & Armor",
        Values = weaponsArmor,
        Multi = false,
        AllowNone = true,
        Callback = function(v)
            clearOtherDropdowns("WA")
            if v and v ~= "" then selectOnly(v, nil) else selectOnly(nil, nil) end
        end
    }).Set

    _G._MiscSet = tab:Dropdown({
        Title = "Ammo & Misc",
        Values = ammoMisc,
        Multi = false,
        AllowNone = true,
        Callback = function(v)
            clearOtherDropdowns("Misc")
            if v == "Mossy Coin" then selectOnly(nil, "mossy")
            elseif v == "Cultist" then selectOnly(nil, "cultist")
            elseif v == "Sapling" then selectOnly(nil, "sapling")
            elseif v and v ~= "" then selectOnly(v, nil)
            else selectOnly(nil, nil) end
        end
    }).Set

    _G._PeltsSet = tab:Dropdown({
        Title = "Pelts",
        Values = pelts,
        Multi = false,
        AllowNone = true,
        Callback = function(v)
            clearOtherDropdowns("Pelts")
            if v and v ~= "" then selectOnly(v, nil) else selectOnly(nil, nil) end
        end
    }).Set

    tab:Divider()

    GatherToggleCtrl = tab:Toggle({
        Title = "Enable Gather",
        Value = false,
        Callback = function(state)
            if state then
                startGather()
            else
                stopGather()
                clearAll()
            end
        end
    })

    tab:Button({
        Title = "Place Down",
        Callback = placeDown
    })

    lp.CharacterAdded:Connect(function()
        if gatherOn then
            task.defer(function()
                stopGather()
                startGather()
            end)
        end
    end)
end
