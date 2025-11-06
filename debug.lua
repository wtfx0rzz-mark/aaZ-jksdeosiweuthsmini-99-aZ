return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")

    local lp  = Players.LocalPlayer
    local tabs = UI and UI.Tabs
    local tab  = tabs and (tabs.Debug or tabs.TPBring or tabs.Auto or tabs.Main)
    assert(tab, "No tab")

    local RADIUS = 20

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local function mainPart(m)
        if not m then return nil end
        if m:IsA("BasePart") then return m end
        if m:IsA("Model") then
            if m.PrimaryPart then return m.PrimaryPart end
            return m:FindFirstChildWhichIsA("BasePart")
        end
        return nil
    end
    local function getRemote(...)
        local f = RS:FindFirstChild("RemoteEvents"); if not f then return nil end
        for i=1,select("#", ...) do
            local n = select(i, ...)
            local x = f:FindFirstChild(n)
            if x then return x end
        end
        return nil
    end

    local RF_Start = getRemote("RequestStartDraggingItem","StartDraggingItem")
    local RF_Stop  = getRemote("RequestStopDraggingItem","StopDraggingItem","StopDraggingItemRemote")

    local function itemsFolder() return WS:FindFirstChild("Items") or WS end
    local function nearbyItems()
        local out, root = {}, hrp(); if not root then return out end
        local origin = root.Position
        for _,d in ipairs(itemsFolder():GetDescendants()) do
            local m = d:IsA("Model") and d or d:IsA("BasePart") and d:FindFirstAncestorOfClass("Model") or nil
            if m and m.Parent then
                local p = mainPart(m)
                if p and (p.Position - origin).Magnitude <= RADIUS then
                    out[#out+1] = m
                end
            end
        end
        return out
    end

    local function setPhysicsRestore(m)
        for _,p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then
                p.Anchored = false
                p.CanCollide = true
                p.CanTouch = true
                p.CanQuery = true
                p.Massless = false
                p.AssemblyLinearVelocity = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
                p.CollisionGroupId = 0
                pcall(function() p:SetNetworkOwner(nil) end)
                pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
            end
        end
        for _,pp in ipairs(m:GetDescendants()) do
            if pp:IsA("ProximityPrompt") then pp.Enabled = true end
        end
        m:SetAttribute("Dragging", nil)
        m:SetAttribute("PickedUp", nil)
    end

    local function snapshotCollision(m)
        local t = {}
        for _,p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then
                t[p] = {CanCollide=p.CanCollide, CanQuery=p.CanQuery, CanTouch=p.CanTouch}
            end
        end
        return t
    end
    local function setCollisionOff(m)
        for _,p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CanCollide = false
                p.CanQuery   = false
                p.CanTouch   = false
            end
        end
    end
    local function restoreCollision(m, snap)
        if not snap then return end
        for part,st in pairs(snap) do
            if part and part.Parent then
                part.CanCollide = st.CanCollide
                part.CanQuery   = st.CanQuery
                part.CanTouch   = st.CanTouch
            end
        end
    end

    local function ownAll()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            if RF_Start then pcall(function() RF_Start:FireServer(m) end) end
            local p = mainPart(m)
            if p then
                pcall(function() p:SetNetworkOwner(lp) end)
                for _,bp in ipairs(m:GetDescendants()) do
                    if bp:IsA("BasePart") then
                        bp.Anchored = true
                        bp.CanTouch = true
                        bp.CanQuery = true
                    end
                end
            end
        end
    end
    local function disownAll()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            if RF_Stop then pcall(function() RF_Stop:FireServer(m) end) end
            setPhysicsRestore(m)
        end
    end
    local function startDragAll()
        if not RF_Start then return end
        local list = nearbyItems()
        for _,m in ipairs(list) do
            pcall(function() RF_Start:FireServer(m) end)
            Run.Heartbeat:Wait()
        end
    end
    local function stopDragAll()
        if not RF_Stop then return end
        local list = nearbyItems()
        for _,m in ipairs(list) do
            pcall(function() RF_Stop:FireServer(m) end)
            Run.Heartbeat:Wait()
        end
    end

    local function wakeGentle()
        local list = nearbyItems()
        local lin, ang = 0.05, 0.05
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") and not p.Anchored then
                    local lv, av = p.AssemblyLinearVelocity, p.AssemblyAngularVelocity
                    if lv.Magnitude < 0.02 and av.Magnitude < 0.02 then
                        p.AssemblyLinearVelocity  = lv + Vector3.new((math.random()-0.5)*lin, (math.random()-0.5)*lin, (math.random()-0.5)*lin)
                        p.AssemblyAngularVelocity = av + Vector3.new((math.random()-0.5)*ang, (math.random()-0.5)*ang, (math.random()-0.5)*ang)
                    end
                end
            end
        end
    end
    local function deoverlap()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            local p = mainPart(m)
            if p and not p.Anchored then
                local cf = (m:IsA("Model") and m:GetPivot()) or p.CFrame
                local jitter = 0.03
                local dx, dz = (math.random()-0.5)*jitter, (math.random()-0.5)*jitter
                if m:IsA("Model") then m:PivotTo(cf + Vector3.new(dx, 0, dz)) else p.CFrame = cf + Vector3.new(dx, 0, dz) end
            end
        end
    end
    local function nudgeAll()
        local list = nearbyItems()
        for _,m in ipairs(list) do setPhysicsRestore(m) end
        Run.Heartbeat:Wait()
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") and not p.Anchored then
                    p.AssemblyLinearVelocity  = p.AssemblyLinearVelocity  + Vector3.new(0, 0.6, 0)
                    p.AssemblyAngularVelocity = p.AssemblyAngularVelocity + Vector3.new(0, 0.3*(math.random()-0.5), 0)
                end
            end
        end
    end
    local function mineOwnership()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.Anchored = false
                    pcall(function() p:SetNetworkOwner(lp) end)
                end
            end
        end
    end
    local function serverOwnership()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.Anchored = false
                    pcall(function() p:SetNetworkOwner(nil) end)
                    pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
                end
            end
        end
    end

    local function groundBelow(pos)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local ex = { lp.Character }
        local map = WS:FindFirstChild("Map")
        if map then
            local fol = map:FindFirstChild("Foliage")
            if fol then table.insert(ex, fol) end
        end
        local items = WS:FindFirstChild("Items"); if items then table.insert(ex, items) end
        params.FilterDescendantsInstances = ex
        local start = pos + Vector3.new(0, 5, 0)
        local hit = WS:Raycast(start, Vector3.new(0, -1000, 0), params)
        if hit then return hit.Position end
        hit = WS:Raycast(pos + Vector3.new(0, 200, 0), Vector3.new(0, -1000, 0), params)
        return (hit and hit.Position) or pos
    end
    local function zeroAssembly(root)
        if not root then return end
        root.AssemblyLinearVelocity  = Vector3.new()
        root.AssemblyAngularVelocity = Vector3.new()
    end

    local function allBodyModels()
        local out = {}
        local chars = WS:FindFirstChild("Characters") or WS
        for _,m in ipairs(chars:GetChildren()) do
            if m:IsA("Model") and m.Name:match("%sBody$") and mainPart(m) then
                out[#out+1] = m
            end
        end
        return out
    end
    local function findNearestBody()
        local root = hrp(); if not root then return nil end
        local best, bestD = nil, math.huge
        for _,m in ipairs(allBodyModels()) do
            local p = mainPart(m)
            local d = (p.Position - root.Position).Magnitude
            if d < bestD then bestD, best = d, m end
        end
        return best
    end

    local function tpPlayerToBody()
        local m = findNearestBody(); if not m then return end
        local p = mainPart(m); if not p then return end
        local g = groundBelow(p.Position)
        local dest = Vector3.new(p.Position.X, g.Y + 2.5, p.Position.Z)
        local root = hrp(); if not root then return end
        local look = (p.Position - root.Position); if look.Magnitude < 1e-3 then look = root.CFrame.LookVector end
        local cf = CFrame.new(dest, dest + look.Unit)
        pcall(function() (lp.Character or {}).PrimaryPart.CFrame = cf end)
        pcall(function() root.CFrame = cf end)
        zeroAssembly(root)
    end

    local function bringBodiesFast()
        local root = hrp(); if not root then return end
        local bodies = allBodyModels(); if #bodies == 0 then return end
        local targetPos = groundBelow(root.Position + root.CFrame.LookVector * 2)
        local cf = CFrame.new(Vector3.new(targetPos.X, targetPos.Y + 1.5, targetPos.Z), root.Position)

        for _,m in ipairs(bodies) do
            local snap = snapshotCollision(m)
            setCollisionOff(m)
            if RF_Start then pcall(function() RF_Start:FireServer(m) end) end
            Run.Heartbeat:Wait()
            pcall(function() m:PivotTo(cf) end)
            Run.Heartbeat:Wait()
            restoreCollision(m, snap)
            if RF_Stop then pcall(function() RF_Stop:FireServer(m) end) end
            setPhysicsRestore(m)
            Run.Heartbeat:Wait()
        end
    end

    local function releaseBody()
        local m = findNearestBody(); if not m then return end
        if RF_Stop then pcall(function() RF_Stop:FireServer(m) end) end
        setPhysicsRestore(m)
    end

    local function fireCenterPart(fire)
        return fire:FindFirstChild("Center")
            or fire:FindFirstChild("InnerTouchZone")
            or mainPart(fire)
            or fire.PrimaryPart
    end
    local function resolveCampfireModel()
        local map = WS:FindFirstChild("Map")
        local cg  = map and map:FindFirstChild("Campground")
        local mf  = cg and cg:FindFirstChild("MainFire")
        if mf then return mf end
        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") then
                local n = (d.Name or ""):lower()
                if n == "mainfire" or n == "campfire" or n == "camp fire" then return d end
            end
        end
        return nil
    end
    local function sendBodyToCamp()
        local m = findNearestBody(); if not m then return end
        local fire = resolveCampfireModel(); if not fire then return end
        local c = fireCenterPart(fire); if not c then return end
        local look = c.CFrame.LookVector
        local zone = fire:FindFirstChild("InnerTouchZone")
        local offset = 4
        if zone and zone:IsA("BasePart") then offset = math.max(zone.Size.X, zone.Size.Z) * 0.5 + 2 end
        local target = c.Position + look * offset
        local g = groundBelow(target)
        local pos = Vector3.new(target.X, g.Y + 1.5, target.Z)
        local cf = CFrame.new(pos, c.Position)

        local snap = snapshotCollision(m)
        setCollisionOff(m)
        if RF_Start then pcall(function() RF_Start:FireServer(m) end) end
        Run.Heartbeat:Wait()
        pcall(function() m:PivotTo(cf) end)
        Run.Heartbeat:Wait()
        restoreCollision(m, snap)
        if RF_Stop then pcall(function() RF_Stop:FireServer(m) end) end
        setPhysicsRestore(m)
    end

    tab:Section({ Title = "Item Recovery" })
    tab:Button({ Title = "Own All Items",       Callback = function() ownAll() end })
    tab:Button({ Title = "Disown All Items",    Callback = function() disownAll() end })
    tab:Button({ Title = "Wake (Gentle)",       Callback = function() wakeGentle() end })
    tab:Button({ Title = "De-overlap",          Callback = function() deoverlap() end })
    tab:Button({ Title = "Nudge Items",         Callback = function() nudgeAll() end })
    tab:Button({ Title = "Mine Ownership",      Callback = function() mineOwnership() end })
    tab:Button({ Title = "Server Ownership",    Callback = function() serverOwnership() end })

    tab:Section({ Title = "Drag Remotes" })
    tab:Button({ Title = "Start Drag Nearby",   Callback = function() startDragAll() end })
    tab:Button({ Title = "Stop Drag Nearby",    Callback = function() stopDragAll() end })

    tab:Section({ Title = "Body Tests" })
    tab:Button({ Title = "TP To Body",             Callback = function() tpPlayerToBody() end })
    tab:Button({ Title = "Bring Body (Fast Drag)", Callback = function() bringBodiesFast() end })
    tab:Button({ Title = "Release Body",           Callback = function() releaseBody() end })
    tab:Button({ Title = "Send Body To Camp",      Callback = function() sendBodyToCamp() end })
end
