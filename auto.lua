-- Patch: teleport + campfire now do a noclip “dive”, then TP, then re-enable collisions after landing/walking.

-- Add near the other locals/util:
local function getHumanoid()
    local ch = Players.LocalPlayer.Character
    return ch and ch:FindFirstChildOfClass("Humanoid")
end

local function diveBelowGround(depth, frames)
    local root = hrp(); if not root then return end
    local ch = Players.LocalPlayer.Character
    local look = root.CFrame.LookVector
    local dest = root.Position + Vector3.new(0, -math.abs(depth), 0)
    for i=1,(frames or 3) do
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
                -- also wait a short moment for movement or settle
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

-- Wrapper that performs the dive + sticky TP + restore collisions
local DIVE_DEPTH = 200
local function teleportWithDive(targetCF)
    local root = hrp(); if not root then return end

    -- Turn noclip ON (snapshot to restore)
    local snapshot = snapshotCollide()
    setCollideAll(false)

    -- Dive under terrain to avoid “loading” damage checks
    diveBelowGround(DIVE_DEPTH, 4)

    -- Perform sticky teleport
    teleportSticky(targetCF)

    -- Stay noclip until we’re grounded or moving again
    waitUntilGroundedOrMoving(3)

    -- Restore collisions
    setCollideAll(true, snapshot)
end

-- Replace the two button callbacks:

-- Phase 10 stays the same (no dive requested)

-- Teleport button (mark-to-teleport)
tpBtn.MouseButton1Click:Connect(function()
    if suppressClick then suppressClick = false return end
    if not markedCF then return end
    teleportWithDive(markedCF)
end)

-- Campfire button
campBtn.MouseButton1Click:Connect(function()
    local cf = campfireTeleportCF()
    if cf then teleportWithDive(cf) end
end)
