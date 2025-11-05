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
        local f = RS:FindFirstChild("RemoteEvents")
        if not f then return nil end
        for i=1,select("#", ...) do
            local n = select(i, ...)
            local x = f:FindFirstChild(n)
            if x then return x end
        end
        return nil
    end

    local RF_Start = getRemote("RequestStartDraggingItem","StartDraggingItem")
    local RF_Stop  = getRemote("RequestStopDraggingItem","StopDraggingItem","StopDraggingItemRemote")

    local function itemsFolder()
        return WS:FindFirstChild("Items") or WS
    end

    local function nearbyItems()
        local out = {}
        local root = hrp(); if not root then return out end
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
            if pp:IsA("ProximityPrompt") then
                pp.Enabled = true
            end
        end
        m:SetAttribute("Dragging", nil)
        m:SetAttribute("PickedUp", nil)
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

    -- Gentle wake for likely-sleeping assemblies (near-zero motion)
    local function wakeGentle()
        local list = nearbyItems()
        local lin = 0.05
        local ang = 0.05
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") and not p.Anchored then
                    local lv = p.AssemblyLinearVelocity
                    local av = p.AssemblyAngularVelocity
                    if lv.Magnitude < 0.02 and av.Magnitude < 0.02 then
                        p.AssemblyLinearVelocity  = lv + Vector3.new((math.random()-0.5)*lin, (math.random()-0.5)*lin, (math.random()-0.5)*lin)
                        p.AssemblyAngularVelocity = av + Vector3.new((math.random()-0.5)*ang, (math.random()-0.5)*ang, (math.random()-0.5)*ang)
                    end
                end
            end
        end
    end

    -- Very small lateral offsets to break perfect contacts
    local function deoverlap()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            local p = mainPart(m)
            if p and not p.Anchored then
                local cf = (m:IsA("Model") and m:GetPivot()) or p.CFrame
                local jitter = 0.03
                local dx = (math.random()-0.5)*jitter
                local dz = (math.random()-0.5)*jitter
                if m:IsA("Model") then
                    m:PivotTo(cf + Vector3.new(dx, 0, dz))
                else
                    p.CFrame = cf + Vector3.new(dx, 0, dz)
                end
            end
        end
    end

    -- Subtle nudge for all items (smaller than before)
    local function nudgeAll()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            setPhysicsRestore(m)
        end
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

    -- Take client ownership without drag
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

    -- Hand ownership back to server without drag
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

    tab:Section({ Title = "Item Recovery" })
    tab:Button({ Title = "Own All Items",       Callback = function() ownAll() end })
    tab:Button({ Title = "Disown All Items",    Callback = function() disownAll() end })
    tab:Button({ Title = "Wake (Gentle)",       Callback = function() wakeGentle() end })
    tab:Button({ Title = "De-overlap",          Callback = function() deoverlap() end })
    tab:Button({ Title = "Nudge Items",         Callback = function() nudgeAll() end })
    tab:Button({ Title = "Mine Ownership",      Callback = function() mineOwnership() end })
    tab:Button({ Title = "Server Ownership",    Callback = function() serverOwnership() end })
end
