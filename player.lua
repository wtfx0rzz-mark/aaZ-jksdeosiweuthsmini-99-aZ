--=====================================================
-- 1337 Nights | Player Tab (with Force Position toggle)
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
    local flySpeed         = 1
    local walkSpeedValue   = 16
    local forcePosEnabled  = true   -- << NEW: toggle controls snap-back behavior

    -- Connections / instances
    local keyDownConn, keyUpConn, jumpConn, noclipConn, renderConn
    local mobileAddedConn, mobileRenderConn
    local bodyGyro, bodyVelocity

    -- Utility
    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end
    local function humanoid()
        local ch = lp.Character
        return ch and ch:FindFirstChildOfClass("Humanoid")
    end
    local function clear(x) if x then pcall(function() x:Destroy() end) end end
    local function disc(c) if c then pcall(function() c:Disconnect() end) end end

    ----------------------------------------------------------------
    -- Desktop Fly (WASD + QE)
    ----------------------------------------------------------------
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
        local desiredPos = root.Position
        local lastFaceDir = root.CFrame.LookVector

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

        renderConn = RunService.RenderStepped:Connect(function(dt)
            local cam = workspace.CurrentCamera
            local h   = humanoid()
            local r   = hrp()
            if not cam or not h or not r then return end

            h.PlatformStand = true
            bodyGyro.CFrame = cam.CFrame

            -- Build desired motion
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

            if forcePosEnabled then
                -- SNAP-BACK MODE: enforce exact position/orientation via CFrame
                local mv = moveVec.Magnitude > 0 and moveVec.Unit or Vector3.zero
                desiredPos = desiredPos + mv * (flySpeed * 50) * dt
                r.AssemblyLinearVelocity  = Vector3.zero
                r.AssemblyAngularVelocity = Vector3.zero
                if mv.Magnitude > 0 then lastFaceDir = Vector3.new(mv.X,0,mv.Z) end
                local faceDir = (lastFaceDir.Magnitude > 1e-3) and lastFaceDir.Unit or r.CFrame.LookVector
                local faceAt  = desiredPos + Vector3.new(faceDir.X,0,faceDir.Z)
                r.CFrame = CFrame.new(desiredPos, Vector3.new(faceAt.X, desiredPos.Y, faceAt.Z))
                bodyVelocity.Velocity = Vector3.new() -- keep BV inert when forcing position
            else
                -- VELOCITY MODE: smooth, no hard snap-back
                if moveVec.Magnitude > 0 then
                    bodyVelocity.Velocity = moveVec.Unit * (flySpeed * 50)
                else
                    bodyVelocity.Velocity = Vector3.zero
                end
            end
        end)
    end

    local function stopDesktopFly()
        FLYING = false
        disc(renderConn); renderConn = nil
        disc(keyDownConn); keyDownConn = nil
        disc(keyUpConn);   keyUpConn   = nil
        local h = humanoid()
        if h then h.PlatformStand = false end
        clear(bodyVelocity); bodyVelocity = nil
        clear(bodyGyro);     bodyGyro     = nil
    end

    ----------------------------------------------------------------
    -- Mobile Fly (thumbstick) – also respects Force Position
    ----------------------------------------------------------------
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

        local desiredPos = root.Position
        local lastFaceDir = root.CFrame.LookVector

        mobileAddedConn = Players.LocalPlayer.CharacterAdded:Connect(function()
            root = hrp()
            if not root then return end
            clear(bodyGyro); clear(bodyVelocity)
            bodyGyro = Instance.new("BodyGyro")
            bodyVelocity = Instance.new("BodyVelocity")
            bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            bodyGyro.P = 1000
            bodyGyro.D = 50
            bodyGyro.Parent = root
            bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            bodyVelocity.Velocity = Vector3.new()
            bodyVelocity.Parent = root
            desiredPos = root.Position
            lastFaceDir = root.CFrame.LookVector
        end)

        mobileRenderConn = RunService.RenderStepped:Connect(function(dt)
            root = hrp()
            local cam = workspace.CurrentCamera
            local h = humanoid()
            if not root or not cam or not h then return end

            h.PlatformStand = true
            bodyGyro.CFrame = cam.CFrame

            -- get thumbstick move vector
            local move = Vector3.new()
            local ok, controlModule = pcall(function()
                return require(lp.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))
            end)
            if ok and controlModule and controlModule.GetMoveVector then
                move = controlModule:GetMoveVector()
            end

            if forcePosEnabled then
                local mv = move.Magnitude > 0 and move.Unit or Vector3.zero
                desiredPos = desiredPos + (cam.CFrame.RightVector * mv.X + -cam.CFrame.LookVector * mv.Z) * (flySpeed * 50) * dt
                root.AssemblyLinearVelocity  = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                if mv.Magnitude > 0 then lastFaceDir = Vector3.new(mv.X,0,mv.Z) end
                local faceDir = (lastFaceDir.Magnitude > 1e-3) and lastFaceDir.Unit or root.CFrame.LookVector
                local faceAt  = desiredPos + Vector3.new(faceDir.X, 0, faceDir.Z)
                root.CFrame = CFrame.new(desiredPos, Vector3.new(faceAt.X, desiredPos.Y, faceAt.Z))
                bodyVelocity.Velocity = Vector3.new()
            else
                local vel = Vector3.new()
                vel += cam.CFrame.RightVector * (move.X * (flySpeed * 50))
                vel += -cam.CFrame.LookVector * (move.Z * (flySpeed * 50))
                bodyVelocity.Velocity = vel
            end
        end)
    end

    local function stopMobileFly()
        disc(mobileRenderConn); mobileRenderConn = nil
        disc(mobileAddedConn);  mobileAddedConn  = nil
        local h = humanoid()
        if h then h.PlatformStand = false end
        clear(bodyVelocity); bodyVelocity = nil
        clear(bodyGyro);     bodyGyro     = nil
        FLYING = false
    end

    local function startFly()
        if UIS.TouchEnabled then mobileFlyEnabled = true; startMobileFly()
        else mobileFlyEnabled = false; startDesktopFly() end
    end
    local function stopFly()
        if mobileFlyEnabled then stopMobileFly() else stopDesktopFly() end
    end

    ----------------------------------------------------------------
    -- Walk Speed / Noclip / Inf Jump (unchanged)
    ----------------------------------------------------------------
    local function setWalkSpeed(v)
        local h = humanoid(); if h then h.WalkSpeed = v end
    end

    local function startNoclip()
        disc(noclipConn)
        noclipConn = RunService.Stepped:Connect(function()
            local ch = lp.Character
            if not ch then return end
            for _, part in ipairs(ch:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = false end
            end
        end)
    end
    local function stopNoclip()
        disc(noclipConn); noclipConn = nil
    end

    local function startInfJump()
        disc(jumpConn)
        jumpConn = UIS.JumpRequest:Connect(function()
            local h = humanoid()
            if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    end
    local function stopInfJump()
        disc(jumpConn); jumpConn = nil
    end

    ----------------------------------------------------------------
    -- UI
    ----------------------------------------------------------------
    tab:Section({ Title = "Player • Movement", Icon = "activity" })

    tab:Slider({
        Title = "Fly Speed",
        Value = { Min = 1, Max = 20, Default = 1 },
        Callback = function(v) flySpeed = tonumber(v) or flySpeed end
    })

    tab:Toggle({
        Title = "Enable Fly",
        Value = false,
        Callback = function(state)
            flyEnabled = state
            if flyEnabled then startFly() else stopFly() end
        end
    })

    tab:Divider()
    tab:Section({ Title = "Walk Speed", Icon = "walk" })

    tab:Slider({
        Title = "Speed",
        Value = { Min = 16, Max = 150, Default = 16 },
        Callback = function(v) walkSpeedValue = tonumber(v) or walkSpeedValue end
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
        Callback = function(state) if state then startNoclip() else stopNoclip() end end
    })

    tab:Toggle({
        Title = "Infinite Jump",
        Value = false,
        Callback = function(state) if state then startInfJump() else stopInfJump() end end
    })

    -- ============================
    -- NEW: Force Position switch
    -- ============================
    tab:Divider()
    tab:Section({ Title = "Flight Safety", Icon = "target" })

    tab:Toggle({
        Title = "Force Position",
        Desc  = "When ON, fly enforces exact position each frame (snap-back). When OFF, uses velocity only.",
        Value = true,
        Callback = function(state)
            forcePosEnabled = state
        end
    })

    -- Auto-restart fly after respawn (keeps current mode)
    lp.CharacterAdded:Connect(function()
        if flyEnabled then
            task.defer(function()
                stopFly()
                startFly()
            end)
        end
    end)
end
