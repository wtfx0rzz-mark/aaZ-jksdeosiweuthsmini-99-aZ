return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")
    local LogService = game:GetService("LogService")

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

    local function nudgeAll()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            setPhysicsRestore(m)
        end
        Run.Heartbeat:Wait()
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.AssemblyLinearVelocity = p.AssemblyLinearVelocity + Vector3.new(0, 4, 0)
                end
            end
        end
    end

    local function clearConsole()
        local pg = lp:FindFirstChildOfClass("PlayerGui")
        if pg then
            local cg = pg:FindFirstChild("ConsoleGui")
            if cg then
                local frame = cg:FindFirstChild("ConsoleFrame")
                local area  = frame and frame:FindFirstChild("ConsoleArea")
                local text  = area and area:FindFirstChild("ConsoleText")
                if text and text:IsA("TextLabel") then text.Text = "" end
            end
        end
        local ok, rc = pcall(function() return getgenv and getgenv().rconsoleclear end)
        if ok and type(rc)=="function" then pcall(rc) end
    end

    tab:Button({ Title = "Own All Items",    Callback = function() ownAll() end })
    tab:Button({ Title = "Disown All Items", Callback = function() disownAll() end })
    tab:Button({ Title = "Nudge Items",      Callback = function() nudgeAll() end })
    tab:Button({ Title = "Clear console logs", Callback = function() clearConsole() end })
end
