--=====================================================
-- 1337 Nights | Gather Module
--  • Captures targets within AuraRadius
--  • Hover carry: 5 studs above HRP, tight stack
--  • Place Down: moves 5 forward + 5 up, spreads, re-enables physics
--  • Auto-turn-off gather before drop
--=====================================================
return function(C, R, UI)
    local Players = C.Services.Players
    local RS      = C.Services.RS
    local WS      = C.Services.WS
    local Run     = C.Services.Run

    local lp  = Players.LocalPlayer
    local tab = UI.Tabs and (UI.Tabs.Gather or UI.Tabs.Auto)
    assert(tab, "Gather tab not found (use UI.Tabs.Gather or UI.Tabs.Auto)")

    local SELECT_VALUES = {"Log"}
    local selectedName  = SELECT_VALUES[1]

    local gatherOn      = false
    local hoverHeight   = 5
    local forwardDrop   = 5
    local upDrop        = 5

    local scanConn, hoverConn
    local gathered = {}      -- { [model]=true }
    local gatheredList = {}  -- array of models for ordering
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
                d.Massless   = on and true or d.Massless
                d.AssemblyLinearVelocity = Vector3.new()
                d.AssemblyAngularVelocity = Vector3.new()
            end
        end
    end
    local function setAnchoredModel(m, on)
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then
                d.Anchored = on and true or false
            end
        end
    end
    local function addGather(m)
        if gathered[m] then return end
        gathered[m] = true
        table.insert(gatheredList, m)
    end
    local function removeGather(m)
        if not gathered[m] then return end
        gathered[m] = nil
        for i=#gatheredList,1,-1 do
            if gatheredList[i] == m then table.remove(gatheredList, i) break end
        end
    end
    local function clearAll()
        for m,_ in pairs(gathered) do removeGather(m) end
    end

    local function nearAndNamed(m, name, origin, rad)
        if not (m and m:IsA("Model") and m.Parent) then return false end
        if m.Name ~= name then return false end
        local mp = mainPart(m)
        if not mp then return false end
        local d = (mp.Position - origin).Magnitude
        return d <= rad
    end

    local function pivotModel(m, cf)
        if m:IsA("Model") then m:PivotTo(cf)
        else
            local p = mainPart(m)
            if p then p.CFrame = cf end
        end
    end

    local function computeHoverCF(i, baseCF)
        return baseCF
    end

    local function computeSpreadCF(i, baseCF)
        local r = 2 + math.floor((i-1)/8)
        local idx = (i-1)%8
        local angle = (idx/8) * math.pi*2
        local offset = Vector3.new(math.cos(angle)*r, 0, math.sin(angle)*r)
        return baseCF + offset
    end

    local function captureIfNear()
        local root = hrp()
        if not root then return end
        local origin = root.Position
        local rad = auraRadius()

        local folders = {}
        local items = WS:FindFirstChild("Items")
        if items then table.insert(folders, items) else table.insert(folders, WS) end

        for _,rootNode in ipairs(folders) do
            for _,m in ipairs(rootNode:GetChildren()) do
                if nearAndNamed(m, selectedName, origin, rad) and not gathered[m] then
                    local mp = mainPart(m)
                    if mp and not mp.Anchored then
                        startDrag(m)
                        task.wait(0.02)
                        pcall(function() mp:SetNetworkOwner(lp) end)
                        setNoCollideModel(m, true)
                        setAnchoredModel(m, true)
                        addGather(m)
                        stopDrag(m)
                    end
                end
            end
        end
    end

    local function hoverFollow()
        local root = hrp()
        if not root then return end
        local forward = root.CFrame.LookVector
        local above = root.Position + Vector3.new(0, hoverHeight, 0)
        local cfBase = CFrame.lookAt(above, above + forward)
        for i,m in ipairs(gatheredList) do
            if m and m.Parent then
                local cf = computeHoverCF(i, cfBase)
                pivotModel(m, cf)
            else
                removeGather(m)
            end
        end
    end

    local function startGather()
        if scanConn then return end
        gatherOn = true
        scanConn = Run.Heartbeat:Connect(captureIfNear)
        hoverConn = Run.RenderStepped:Connect(hoverFollow)
    end
    local function stopGather()
        gatherOn = false
        if scanConn then pcall(function() scanConn:Disconnect() end) end
        if hoverConn then pcall(function() hoverConn:Disconnect() end) end
        scanConn, hoverConn = nil, nil
    end

    local function placeDown()
        local root = hrp()
        if not root then return end

        if GatherToggleCtrl and GatherToggleCtrl.Set then
            GatherToggleCtrl:Set(false)
        end
        stopGather()

        local forward = root.CFrame.LookVector
        local dropPos = root.Position + forward * forwardDrop + Vector3.new(0, upDrop, 0)
        local baseCF = CFrame.lookAt(dropPos, dropPos + forward)

        for i,m in ipairs(gatheredList) do
            if m and m.Parent then
                local cf = computeSpreadCF(i, baseCF)
                pivotModel(m, cf)
            end
        end

        task.wait(0.05)

        for _,m in ipairs(gatheredList) do
            if m and m.Parent then
                setAnchoredModel(m, false)
                setNoCollideModel(m, false)
            end
        end

        clearAll()
    end

    tab:Section({ Title = "Gather", Icon = "layers" })

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

        tab:Dropdown({
        Title = "Item",
        Values = SELECT_VALUES,
        Multi = false,
        AllowNone = false,
        Callback = function(v) if v and v ~= "" then selectedName = v end end
    })
end
