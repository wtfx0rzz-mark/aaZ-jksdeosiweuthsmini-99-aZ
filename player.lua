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

    local flyEnabled       = false
    local mobileFlyEnabled = false
    local FLYING           = false
    local flySpeed         = 3
    local walkSpeedValue   = 24
    local speedEnabled     = false

    local forceFlyEnabled  = false
    local forceFlyConn     = nil
    local forceDesiredPos  = nil
    local forceLastFaceDir = nil

    local keyDownConn, keyUpConn, jumpConn, noclipConn, renderConn
    local mobileAddedConn, mobileRenderConn
    local speedPropConn, speedTickConn
    local bodyGyro, bodyVelocity

    local EnableFlyToggleCtrl, ForceFlyToggleCtrl

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
    -- Desktop Fly
    --========================
    local function startDesktopFly()
        if FLYING then return end
        local root = hrp()
        local hum  = humanoid()
        if not root or not hum then return end

        FLYING = true
        hum.PlatformStand = true

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
            local r = hrp()
            if not r then return end
            bodyGyro.CFrame = workspace.CurrentCamera.CFrame

            local vel = Vector3.new()
            vel = vel + workspace.CurrentCamera.CFrame.LookVector * (CONTROL.F + CONTROL.B)
            vel = vel + workspace.CurrentCamera.CFrame.RightVector * (CONTROL.R + CONTROL.L)
            vel = vel + Vector3.new(0, CONTROL.Q + CONTROL.E, 0)

            bodyVelocity.Velocity = vel * 50
            if vel.Magnitude < 1e-3 then
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
    -- Mobile Fly
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
        bodyGyro.P = 9e4
        bodyGyro.CFrame = root.CFrame
        bodyGyro.Parent = root

        bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        bodyVelocity.Parent = root

        local StarterGui = game:GetService("StarterGui")
        StarterGui:SetCore("ResetButtonCallback", true)

        local controlModule = nil
        mobileAddedConn = lp.CharacterAdded:Connect(function(char)
            local plrScripts = char:FindFirstChildOfClass("LocalScript")
            if plrScripts and plrScripts.Name == "PlayerScripts" then
                local p = plrScripts:FindFirstChild("ControlScript", true)
                if p then controlModule = require(p) end
            end
        end)

        mobileRenderConn = RunService.RenderStepped:Connect(function()
            local r = hrp()
            local hum = humanoid()
            if not r or not hum then return end
            bodyGyro.CFrame = workspace.CurrentCamera.CFrame

            local move = Vector3.new()
            if controlModule and controlModule.GetMoveVector then
                move = controlModule:GetMoveVector()
            end

            local vel = Vector3.new()
            vel = vel + workspace.CurrentCamera.CFrame.RightVector * (move.X * (flySpeed * 50))
            vel = vel - workspace.CurrentCamera.CFrame.LookVector  * (move.Z * (flySpeed * 50))
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
    -- Force Fly (Position Hold)
    --========================
    local function startForceFly()
        if forceFlyConn then return end
        forceFlyEnabled = true
        local r = hrp()
        if not r then return end
        forceDesiredPos = r.Position
        forceLastFaceDir = r.CFrame.LookVector

        forceFlyConn = RunService.RenderStepped:Connect(function(dt)
            local r = hrp()
            if not r then return end
            local cam = workspace.CurrentCamera
            local look = cam.CFrame.LookVector
            local right = cam.CFrame.RightVector

            local planar = Vector3.new(0, 0, 0)
            local vert = 0
            if UIS:IsKeyDown(Enum.KeyCode.W) then planar = planar + Vector3.new(look.X, 0, look.Z) end
            if UIS:IsKeyDown(Enum.KeyCode.S) then planar = planar - Vector3.new(look.X, 0, look.Z) end
            if UIS:IsKeyDown(Enum.KeyCode.D) then planar = planar + Vector3.new(right.X, 0, right.Z) end
            if UIS:IsKeyDown(Enum.KeyCode.A) then planar = planar - Vector3.new(right.X, 0, right.Z) end
            if UIS:IsKeyDown(Enum.KeyCode.E) then vert =  flySpeed * 2 end
            if UIS:IsKeyDown(Enum.KeyCode.Q) then vert = -flySpeed * 2 end

            local mag = planar.Magnitude
            if mag > 1e-3 then planar = planar.Unit * (flySpeed * 50) end

            local delta = Vector3.zero
            if mag > 1e-3 then delta = delta + planar * (flySpeed * 50 * dt) end
            if vert ~= 0 then delta = delta + Vector3.new(0, vert * dt, 0) end

            forceDesiredPos = (forceDesiredPos or r.Position) + delta

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

    local function unbindSpeedWatchers()
        disconnectConn(speedPropConn); speedPropConn = nil
        disconnectConn(speedTickConn); speedTickConn = nil
    end

    local function bindSpeedWatchers()
        unbindSpeedWatchers()
        local hum = humanoid()
        if not hum then return end
        speedPropConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if speedEnabled and hum and hum.WalkSpeed ~= walkSpeedValue then
                hum.WalkSpeed = walkSpeedValue
            end
        end)
        local acc = 0
        speedTickConn = RunService.Heartbeat:Connect(function(dt)
            acc = acc + dt
            if acc < 0.25 then return end
            acc = 0
            if not speedEnabled then return end
            local h = humanoid()
            if h and h.WalkSpeed ~= walkSpeedValue then
                h.WalkSpeed = walkSpeedValue
            end
        end)
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
        local ch = lp.Character
        if not ch then return end
        for _, part in ipairs(ch:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end

    --========================
    -- Infinite Jump
    --========================
    local infJumpEnabled = false
    local function startInfJump()
        if jumpConn then jumpConn:Disconnect() end
        infJumpEnabled = true
        jumpConn = UIS.JumpRequest:Connect(function()
            if not infJumpEnabled then return end
            local hum = humanoid()
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    end
    local function stopInfJump()
        infJumpEnabled = false
        disconnectConn(jumpConn); jumpConn = nil
    end

    --========================
    -- UI
    --========================
    tab:Section({ Title = "Fly", Icon = "activity" })

    tab:Slider({
        Title = "Fly Speed",
        Value = { Min = 1, Max = 20, Default = 3 },
        Callback = function(v)
            flySpeed = tonumber(v) or flySpeed
        end
    })

    EnableFlyToggleCtrl = tab:Toggle({
        Title = "Enable Fly",
        Value = false,
        Callback = function(state)
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
        Value = { Min = 16, Max = 150, Default = 24 },
        Callback = function(v)
            walkSpeedValue = tonumber(v) or walkSpeedValue
            if speedEnabled then setWalkSpeed(walkSpeedValue) end
        end
    })

    tab:Toggle({
        Title = "Enable Speed",
        Value = false,
        Callback = function(state)
            speedEnabled = state
            if state then
                setWalkSpeed(walkSpeedValue)
                bindSpeedWatchers()
            else
                unbindSpeedWatchers()
                setWalkSpeed(16)
            end
        end
    })

    tab:Divider()
    tab:Section({ Title = "Noclip / Jump", Icon = "zap" })

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

    ForceFlyToggleCtrl = tab:Toggle({
        Title = "Force Fly",
        Value = false,
        Callback = function(state)
            if state and flyEnabled then
                stopFly()
                if EnableFlyToggleCtrl and EnableFlyToggleCtrl.Set then
                    EnableFlyToggleCtrl:Set(false)
                end
            end
            if state then startForceFly() else stopForceFly() end
        end
    })

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
        if speedEnabled then
            task.defer(function()
                setWalkSpeed(walkSpeedValue)
                bindSpeedWatchers()
            end)
        end
    end)
end
