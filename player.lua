--=====================================================
-- 1337 Nights | Player Tab (ported from legacy script)
--=====================================================
return function(C, R, UI)
    local Players      = C.Services.Players
    local RunService   = C.Services.RunService or game:GetService("RunService")
    local UIS          = C.Services.UIS        or game:GetService("UserInputService")

    local lp = Players.LocalPlayer
    local tab = UI.Tabs and UI.Tabs.Player
    assert(tab, "Player tab not found in UI")

    -- State
    local flyEnabled       = false
    local mobileFlyEnabled = false
    local FLYING           = false
    local flySpeed         = 3    -- default startup value
    local walkSpeedValue   = 24   -- default startup value

    -- Force Fly state (UI-free engine)
    local forceFlyEnabled  = false
    local forceFlyConn     = nil
    local forceDesiredPos  = nil
    local forceLastFaceDir = nil

    -- Connections / instances for cleanup
    local keyDownConn, keyUpConn, jumpConn, noclipConn, renderConn
    local mobileAddedConn, mobileRenderConn
    local bodyGyro, bodyVelocity

    -- Keep references to toggle controls so we can programmatically switch them
    local EnableFlyToggleCtrl, ForceFlyToggleCtrl

    -- Utilities
    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end
    local function humanoid()
        local ch = lp.Character
        return ch and ch:FindFirstChildOfClass("Humanoid")
    end
    local function clearInstance(x) if x then pcall(function() x:Destroy() end) end end
    local function disconnectConn(c) if c then pcall(function() c:Disconnect() end) end end

    --========================
    -- Desktop Fly (WASD+QE)
    --========================
    local function startDesktopFly()
        if FLYING then return end
        local root = hrp()
        local hum  = humanoid()
        if not root or not hum then return end

        FLYING = true

        bodyGyro     = Instance.new("BodyGyro")
        bodyVelocity = Instance.new("BodyVelocity")
        bodyGyro.P = 9e4
        bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        bodyGyro.CFrame = root.CFrame
        bodyGyro.Parent = root

        bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        bodyVelocity.Velocity = Vector3.new()
        bodyVelocity.Parent = root

        local CONTROL = {F=0,B=0,L=0,R=0,Q=0,E=0}
        local LAST    = {F=0,B=0,L=0,R=0}

        keyDownConn = UIS.InputBegan:Connect(function(input, gpe)
            if gpe or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            local k = input.KeyCode
            if k == Enum.KeyCode.W then CONTROL.F =  flySpeed
            elseif k == Enum.KeyCode.S then CONTROL.B = -flySpeed
            elseif k == Enum.KeyCode.A then CONTROL.L = -flySpeed
            elseif k == Enum.KeyCode.D then CONTROL.R =  flySpeed
            elseif k == Enum.KeyCode.E then CONTROL.Q =  flySpeed * 2
            elseif k == Enum.KeyCode.Q then CONTROL.E = -flySpeed * 2
            end
        end)
        keyUpConn = UIS.InputEnded:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            local k = input.KeyCode
            if k == Enum.KeyCode.W then CONTROL.F = 0
            elseif k == Enum.KeyCode.S then CONTROL.B = 0
            elseif k == Enum.KeyCode.A then CONTROL.L = 0
            elseif k == Enum.KeyCode.D then CONTROL.R = 0
            elseif k == Enum.KeyCode.E then CONTROL.Q = 0
            elseif k == Enum.KeyCode.Q then CONTROL.E = 0
            end
        end)

        renderConn = RunService.RenderStepped:Connect(function()
            local cam = workspace.CurrentCamera
            if not cam or not root then return end
            hum.PlatformStand = true
            bodyGyro.CFrame = cam.CFrame

            local moveVec = Vector3.new()
            if CONTROL.F ~= 0 or CONTROL.B ~= 0 then
                moveVec += cam.CFrame.LookVector * (CONTROL.F + CONTROL.B)
            end
            if CONTROL.L ~= 0 or CONTROL.R ~= 0 then
                moveVec += cam.CFrame.RightVector * (CONTROL.R + CONTROL.L)
            end
            if CONTROL.Q ~= 0 or CONTROL.E ~= 0 then
                moveVec += cam.CFrame.UpVector * (CONTROL.Q + CONTROL.E)
            end
            if moveVec.Magnitude > 0 then
                bodyVelocity.Velocity = moveVec.Unit * (flySpeed * 50)
                LAST = {F=CONTROL.F,B=CONTROL.B,L=CONTROL.L,R=CONTROL.R}
            else
                bodyVelocity.Velocity = Vector3.new()
            end
        end)
    end

    local function stopDesktopFly()
        FLYING = false
        disconnectConn(renderConn); renderConn = nil
        disconnectConn(keyDownConn); keyDownConn = nil
        disconnectConn(keyUpConn);   keyUpConn   = nil
        local hum = humanoid()
        if hum then hum.PlatformStand = false end
        clearInstance(bodyVelocity); bodyVelocity = nil
        clearInstance(bodyGyro);     bodyGyro     = nil
    end

    --========================
    -- Mobile Fly (thumbstick)
    --========================
    local function startMobileFly()
        if FLYING then return end
        local root = hrp()
        local hum  = humanoid()
        if not root or not hum then return end

        FLYING = true

        bodyGyro     = Instance.new("BodyGyro")
        bodyVelocity = Instance.new("BodyVelocity")
        bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        bodyGyro.P = 1000
        bodyGyro.D = 50
        bodyGyro.Parent = root

        bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        bodyVelocity.Velocity = Vector3.new()
        bodyVelocity.Parent = root

        -- keep BG/BV across respawn
        mobileAddedConn = Players.LocalPlayer.CharacterAdded:Connect(function()
            root = hrp()
            if not root then return end
            clearInstance(bodyGyro); clearInstance(bodyVelocity)
            bodyGyro = Instance.new("BodyGyro")
            bodyVelocity = Instance.new("BodyVelocity")
            bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            bodyGyro.P = 1000
            bodyGyro.D = 50
            bodyGyro.Parent = root
            bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            bodyVelocity.Velocity = Vector3.new()
            bodyVelocity.Parent = root
        end)

        mobileRenderConn = RunService.RenderStepped:Connect(function()
            root = hrp()
            local cam = workspace.CurrentCamera
            if not root or not cam then return end
            hum.PlatformStand = true
            bodyGyro.CFrame = cam.CFrame

            -- Use Roblox PlayerModule move vector (safe fallback to UIS if absent)
            local move = Vector3.new()
            local ok, controlModule = pcall(function()
                return require(lp.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))
            end)
            if ok and controlModule and controlModule.GetMoveVector then
                move = controlModule:GetMoveVector()
            end

            local vel = Vector3.new()
            vel += cam.CFrame.RightVector * (move.X * (flySpeed * 50))
            vel += -cam.CFrame.LookVector * (move.Z * (flySpeed * 50))
            bodyVelocity.Velocity = vel
        end)
    end

    local function stopMobileFly()
        disconnectConn(mobileRenderConn); mobileRenderConn = nil
        disconnectConn(mobileAddedConn);  mobileAddedConn  = nil
        local hum = humanoid()
        if hum then hum.PlatformStand = false end
        clearInstance(bodyVelocity); bodyVelocity = nil
        clearInstance(bodyGyro);     bodyGyro     = nil
        FLYING = false
    end

    local function startFly()
        if UIS.TouchEnabled then
            mobileFlyEnabled = true
            startMobileFly()
        else
            mobileFlyEnabled = false
            startDesktopFly()
        end
    end
    local function stopFly()
        if mobileFlyEnabled then stopMobileFly() else stopDesktopFly() end
    end

    --========================
    -- Force Fly (UI-free, camera + MoveDirection)
    --========================
    local PITCH_DEADZONE = 0.22
    local function startForceFly()
        if forceFlyConn then return end
        local root = hrp()
        local hum  = humanoid()
        if not root or not hum then return end

        forceFlyEnabled  = true
        forceDesiredPos  = root.Position
        forceLastFaceDir = root.CFrame.LookVector

        forceFlyConn = RunService.RenderStepped:Connect(function(dt)
            local r = hrp()
            local h = humanoid()
            local cam = workspace.CurrentCamera
            if not r or not h or not cam then return end

            h.PlatformStand = true

            -- planar based on Humanoid.MoveDirection (normalized)
            local move = h.MoveDirection
            local planar = Vector3.new(move.X,0,move.Z)
            local mag = planar.Magnitude
            if mag > 1e-3 then planar = planar / mag else planar = Vector3.zero end

            -- vertical from camera pitch when moving
            local lookY = cam.CFrame.LookVector.Y
            local vert = 0
            if mag > 1e-3 then
                local a = math.abs(lookY)
                if a > PITCH_DEADZONE then
                    local t = (a - PITCH_DEADZONE) / (1 - PITCH_DEADZONE)
                    vert = (lookY > 0 and 1 or -1) * t * (flySpeed * 50)
                end
            end

            local delta = Vector3.zero
            if mag > 1e-3 then delta += planar * (flySpeed * 50 * dt) end
            if vert ~= 0 then delta += Vector3.new(0, vert * dt, 0) end

            forceDesiredPos = (forceDesiredPos or r.Position) + delta

            -- zero physics and set CFrame to desired
            r.AssemblyLinearVelocity  = Vector3.new()
            r.AssemblyAngularVelocity = Vector3.new()

            if mag > 1e-3 then forceLastFaceDir = planar end
            local face = forceLastFaceDir or r.CFrame.LookVector
            local faceAt = forceDesiredPos + Vector3.new(face.X, 0, face.Z)
            r.CFrame = CFrame.new(forceDesiredPos, Vector3.new(faceAt.X, forceDesiredPos.Y, faceAt.Z))
        end)
    end

    local function stopForceFly()
        if not forceFlyConn then
            forceFlyEnabled = false
            return
        end
        disconnectConn(forceFlyConn); forceFlyConn = nil
        forceFlyEnabled  = false
        forceDesiredPos  = nil
        forceLastFaceDir = nil
        local h = humanoid()
        if h then h.PlatformStand = false end
        local r = hrp()
        if r then
            r.AssemblyLinearVelocity  = Vector3.new()
            r.AssemblyAngularVelocity = Vector3.new()
        end
    end

    --========================
    -- Walk Speed
    --========================
    local function setWalkSpeed(val)
        local hum = humanoid()
        if hum then hum.WalkSpeed = val end
    end

    --========================
    -- Noclip
    --========================
    local function startNoclip()
        disconnectConn(noclipConn)
        noclipConn = RunService.Stepped:Connect(function()
            local ch = lp.Character
            if not ch then return end
            for _, part in ipairs(ch:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end)
    end
    local function stopNoclip()
        disconnectConn(noclipConn); noclipConn = nil
    end

    --========================
    -- Infinite Jump
    --========================
    local function startInfJump()
        disconnectConn(jumpConn)
        jumpConn = UIS.JumpRequest:Connect(function()
            local hum = humanoid()
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    end
    local function stopInfJump()
        disconnectConn(jumpConn); jumpConn = nil
    end

    --========================
    -- UI Controls
    --========================
    tab:Section({ Title = "Player • Movement", Icon = "activity" })

    -- Apply A: set slider defaults to desired startup values (3 and 24)
    tab:Slider({
        Title = "Fly Speed",
        Value = { Min = 1, Max = 20, Default = 3 }, -- was 1
        Callback = function(v)
            flySpeed = tonumber(v) or flySpeed
        end
    })

    -- Keep a handle so we can programmatically flip it off
    EnableFlyToggleCtrl = tab:Toggle({
        Title = "Enable Fly",
        Value = false,
        Callback = function(state)
            -- mutual exclusion with Force Fly
            if state and forceFlyEnabled then
                stopForceFly()
                if ForceFlyToggleCtrl and ForceFlyToggleCtrl.Set then
                    ForceFlyToggleCtrl:Set(false)
                end
            end
            flyEnabled = state
            if flyEnabled then startFly() else stopFly() end
        end
    })

    tab:Divider()
    tab:Section({ Title = "Walk Speed", Icon = "walk" })

    tab:Slider({
        Title = "Speed",
        Value = { Min = 16, Max = 150, Default = 24 }, -- was 16
        Callback = function(v)
            walkSpeedValue = tonumber(v) or walkSpeedValue
        end
    })

    tab:Toggle({
        Title = "Enable Speed",
        Value = false,
        Callback = function(state)
            if state then setWalkSpeed(walkSpeedValue) else setWalkSpeed(16) end
        end
    })

    tab:Divider()
    tab:Section({ Title = "Utilities", Icon = "tool" })

    tab:Toggle({
        Title = "Noclip",
        Value = false,
        Callback = function(state)
            if state then startNoclip() else stopNoclip() end
        end
    })

    tab:Toggle({
        Title = "Infinite Jump",
        Value = false,
        Callback = function(state)
            if state then startInfJump() else stopInfJump() end
        end
    })

    -- New toggle at the very bottom: Force Fly
    ForceFlyToggleCtrl = tab:Toggle({
        Title = "Force Fly",
        Value = false,
        Callback = function(state)
            -- mutual exclusion with normal Fly
            if state and flyEnabled then
                flyEnabled = false
                stopFly()
                if EnableFlyToggleCtrl and EnableFlyToggleCtrl.Set then
                    EnableFlyToggleCtrl:Set(false)
                end
            end
            if state then
                startForceFly()
            else
                stopForceFly()
            end
        end
    })

    -- Optional: safety cleanup if character resets while flying
    lp.CharacterAdded:Connect(function()
        if flyEnabled then
            task.defer(function()
                stopFly()
                startFly()
            end)
        end
        if forceFlyEnabled then
            task.defer(function()
                stopForceFly()
                startForceFly()
            end)
        end
    end)
end
