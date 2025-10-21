--=====================================================
-- 1337 Nights | Auto Tab • Edge Buttons + Lost Child Toggle + Instant Interact
--  • Hard-stick teleports to ensure server-side position commit
--  • Teleport + Campfire use noclip dive-under workaround before TP
--  • Load Defense: force any "DataHasLoaded" flag TRUE continuously
--=====================================================
return function(C, R, UI)
    local Players = (C and C.Services and C.Services.Players) or game:GetService("Players")
    local RS      = (C and C.Services and C.Services.RS)      or game:GetService("ReplicatedStorage")
    local WS      = (C and C.Services and C.Services.WS)      or game:GetService("Workspace")
    local PPS     = game:GetService("ProximityPromptService")
    local Run     = (C and C.Services and C.Services.Run)     or game:GetService("RunService")

    local lp = Players.LocalPlayer
    local Tabs = (UI and UI.Tabs) or {}
    local tab  = Tabs.Auto
    if not tab then
        warn("[Auto] Auto tab not found in UI")
        return
    end

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local function getHumanoid()
        local ch = lp.Character
        return ch and ch:FindFirstChildOfClass("Humanoid")
    end
    local function mainPart(model)
        if not (model and model:IsA("Model")) then return nil end
        if model.PrimaryPart then return model.PrimaryPart end
        return model:FindFirstChildWhichIsA("BasePart")
    end
    local function getRemote(name)
        local f = RS:FindFirstChild("RemoteEvents")
        return f and f:FindFirstChild(name) or nil
    end
    local function zeroAssembly(root)
        if not root then return end
        root.AssemblyLinearVelocity  = Vector3.new(0,0,0)
        root.AssemblyAngularVelocity = Vector3.new(0,0,0)
    end

    local STICK_DURATION    = 0.35
    local STICK_EXTRA_FR    = 2
    local STICK_CLEAR_VEL   = true
    local TELEPORT_UP_NUDGE = 0.05

    local function snapshotCollide()
        local ch = lp.Character
        if not ch then return {} end
        local t = {}
        for _,d in ipairs(ch:GetDescendants()) do
            if d:IsA("BasePart") then t[d] = d.CanCollide end
        end
        return t
    end
    local function setCollideAll(on, snapshot)
        local ch = lp.Character
        if not ch then return end
        if on and snapshot then
            for part,can in pairs(snapshot) do
                if part and part.Parent then part.CanCollide = can end
            end
        else
            for _,d in ipairs(ch:GetDescendants()) do
                if d:IsA("BasePart") then d.CanCollide = false end
            end
        end
    end
    local function isNoclipNow()
        local ch = lp.Character
        if not ch then return false end
        local total, off = 0, 0
        for _,d in ipairs(ch:GetDescendants()) do
            if d:IsA("BasePart") then
                total += 1
                if d.CanCollide == false then off += 1 end
            end
        end
        return (total > 0) and ((off / total) >= 0.9) or false
    end

    local function teleportSticky(cf)
        local root = hrp(); if not root then return end
        local ch   = lp.Character
        local targetCF = cf + Vector3.new(0, TELEPORT_UP_NUDGE, 0)

        local hadNoclip = isNoclipNow()
        local snap
        if not hadNoclip then
            snap = snapshotCollide()
            setCollideAll(false)
        end

        if ch then pcall(function() ch:PivotTo(targetCF) end) end
        pcall(function() root.CFrame = targetCF end)
        if STICK_CLEAR_VEL then zeroAssembly(root) end

        local t0 = os.clock()
        while (os.clock() - t0) < STICK_DURATION do
            if ch then pcall(function() ch:PivotTo(targetCF) end) end
            pcall(function() root.CFrame = targetCF end)
            if STICK_CLEAR_VEL then zeroAssembly(root) end
            Run.Heartbeat:Wait()
        end
        for _=1,STICK_EXTRA_FR do
            if ch then pcall(function() ch:PivotTo(targetCF) end) end
            pcall(function() root.CFrame = targetCF end)
            if STICK_CLEAR_VEL then zeroAssembly(root) end
            Run.Heartbeat:Wait()
        end

        if not hadNoclip then
            setCollideAll(true, snap)
        end
        if STICK_CLEAR_VEL then zeroAssembly(root) end
    end

    local function diveBelowGround(depth, frames)
        local root = hrp(); if not root then return end
        local ch = lp.Character
        local look = root.CFrame.LookVector
        local dest = root.Position + Vector3.new(0, -math.abs(depth), 0)
        for _=1,(frames or 4) do
            local cf = CFrame.new(dest, dest + look)
            if ch then pcall(function() ch:PivotTo(cf) end) end
            pcall(function() root.CFrame = cf end)
            zeroAssembly(root)
            Run.Heartbeat:Wait()
        end
    end
    local function waitUntilGroundedOrMoving(timeout)
        local h = getHumanoid()
        local t0 = os.clock()
        local groundedFrames = 0
        while os.clock() - t0 < (timeout or 3) do
            if h then
                local grounded = (h.FloorMaterial ~= Enum.Material.Air)
                if grounded then groundedFrames += 1 else groundedFrames = 0 end
                if groundedFrames >= 5 then
                    local t1 = os.clock()
                    while os.clock() - t1 < 0.35 do
                        if h.MoveDirection.Magnitude > 0.05 then return true end
                        Run.Heartbeat:Wait()
                    end
                    return true
                end
            end
            Run.Heartbeat:Wait()
        end
        return false
    end
    local DIVE_DEPTH = 200
    local function teleportWithDive(targetCF)
        local root = hrp(); if not root then return end
        local snap = snapshotCollide()
        setCollideAll(false)
        diveBelowGround(DIVE_DEPTH, 4)
        teleportSticky(targetCF)
        waitUntilGroundedOrMoving(3)
        setCollideAll(true, snap)
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
