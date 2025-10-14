--=====================================================
-- 1337 Nights | Player Tab (Force Position = hard snap)
--=====================================================
return function(C, R, UI)
    local Players      = C.Services.Players
    local RunService   = C.Services.RunService or game:GetService("RunService")
    local UIS          = C.Services.UIS        or game:GetService("UserInputService")

    local lp  = Players.LocalPlayer
    local tab = UI.Tabs and UI.Tabs.Player
    assert(tab, "Player tab not found in UI")

    -- State
    local flyEnabled, mobileFly, FLYING = false, false, false
    local flySpeed, walkSpeedValue      = 1, 16
    local forcePosEnabled               = true

    -- Flight internals
    local bodyGyro, bodyVelocity
    local keyDownConn, keyUpConn, jumpConn, noclipConn
    local renderConn, mobileAddedConn, mobileRenderConn

    -- NEW: global desired pose tracked by fly loops + enforced by guardian
    local desiredCF = nil

    -- ========= Utilities =========
    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local function hum() local ch = lp.Character; return ch and ch:FindFirstChildOfClass("Humanoid") end
    local function disc(c) if c then pcall(function() c:Disconnect() end) end end
    local function clear(x) if x then pcall(function() x:Destroy() end) end end

    -- ========= Force-Position Guardian (high priority render step) =========
    local GUARD_NAME = "ForcePosGuard_1337"
    local function bindGuardian()
        RunService:UnbindFromRenderStep(GUARD_NAME)
        if not forcePosEnabled then return end
        RunService:BindToRenderStep(GUARD_NAME, Enum.RenderPriority.Camera.Value + 10, function()
            if not FLYING then return end
            local r = hrp()
            if not r or not desiredCF then return end
            -- take network ownership to minimize server corrections
            pcall(function() r:SetNetworkOwner(lp) end)
            -- zero velocities then hard-set pose
            r.AssemblyLinearVelocity  = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
            r.CFrame = desiredCF
        end)
    end
    local function unbindGuardian()
        RunService:UnbindFromRenderStep(GUARD_NAME)
    end

    -- ========= Desktop Fly =========
    local function startDesktopFly()
        if FLYING then return end
        local r, h = hrp(), hum()
        if not r or not h then return end
        FLYING = true

        bodyGyro     = Instance.new("BodyGyro");     bodyGyro.P = 9e4; bodyGyro.MaxTorque = Vector3.new(9e9,9e9,9e9); bodyGyro.CFrame = r.CFrame; bodyGyro.Parent = r
        bodyVelocity = Instance.new("BodyVelocity"); bodyVelocity.MaxForce = Vector3.new(9e9,9e9,9e9); bodyVelocity.Velocity = Vector3.new();    bodyVelocity.Parent = r

        local CONTROL = {F=0,B=0,L=0,R=0,Q=0,E=0}
        local lastFaceDir = r.CFrame.LookVector
        desiredCF = r.CFrame   -- initialize target
        pcall(function() r:SetNetworkOwner(lp) end)

        keyDownConn = UIS.InputBegan:Connect(function(i,g)
            if g or i.UserInputType ~= Enum.UserInputType.Keyboard then return end
            local k = i.KeyCode
            if k==Enum.KeyCode.W then CONTROL.F =  flySpeed
            elseif k==Enum.KeyCode.S then CONTROL.B = -flySpeed
            elseif k==Enum.KeyCode.A then CONTROL.L = -flySpeed
            elseif k==Enum.KeyCode.D then CONTROL.R =  flySpeed
            elseif k==Enum.KeyCode.E then CONTROL.Q =  flySpeed*2
            elseif k==Enum.KeyCode.Q then CONTROL.E = -flySpeed*2 end
        end)
        keyUpConn = UIS.InputEnded:Connect(function(i)
            if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
            local k = i.KeyCode
            if k==Enum.KeyCode.W then CONTROL.F = 0
            elseif k==Enum.KeyCode.S then CONTROL.B = 0
            elseif k==Enum.KeyCode.A then CONTROL.L = 0
            elseif k==Enum.KeyCode.D then CONTROL.R = 0
            elseif k==Enum.KeyCode.E then CONTROL.Q = 0
            elseif k==Enum.KeyCode.Q then CONTROL.E = 0 end
        end)

        renderConn = RunService.RenderStepped:Connect(function(dt)
            local cam = workspace.CurrentCamera
            r, h = hrp(), hum()
            if not cam or not r or not h then return end
            h.PlatformStand = true
            bodyGyro.CFrame = cam.CFrame

            local mv = Vector3.new()
            if CONTROL.F ~= 0 or CONTROL.B ~= 0 then mv += cam.CFrame.LookVector  * (CONTROL.F + CONTROL.B) end
            if CONTROL.L ~= 0 or CONTROL.R ~= 0 then mv += cam.CFrame.RightVector * (CONTROL.R + CONTROL.L) end
            if CONTROL.Q ~= 0 or CONTROL.E ~= 0 then mv += cam.CFrame.UpVector    * (CONTROL.Q + CONTROL.E) end

            if forcePosEnabled then
                -- compute new desiredCF; guardian will enforce *after* everything else
                local step = (mv.Magnitude > 0) and mv.Unit * (flySpeed * 50) * dt or Vector3.zero
                local pos  = desiredCF and desiredCF.Position or r.Position
                local newPos = pos + step
                if mv.Magnitude > 0 then lastFaceDir = Vector3.new(mv.X,0,mv.Z).Magnitude>1e-3 and Vector3.new(mv.X,0,mv.Z).Unit or lastFaceDir end
                local faceAt = newPos + Vector3.new(lastFaceDir.X,0,lastFaceDir.Z)
                desiredCF = CFrame.new(newPos, Vector3.new(faceAt.X, newPos.Y, faceAt.Z))
                bodyVelocity.Velocity = Vector3.zero
            } else
                -- velocity mode (no snap-back)
                bodyVelocity.Velocity = (mv.Magnitude > 0) and mv.Unit * (flySpeed * 50) or Vector3.zero
                desiredCF = nil -- disable guardian enforcement
            end
        end)

        bindGuardian()
    end

    local function stopDesktopFly()
        FLYING = false
        disc(renderConn); renderConn = nil
        disc(keyDownConn); keyDownConn = nil
        disc(keyUpConn);   keyUpConn   = nil
        local h = hum(); if h then h.PlatformStand = false end
        clear(bodyVelocity); bodyVelocity = nil
        clear(bodyGyro);     bodyGyro     = nil
        desiredCF = nil
        unbindGuardian()
    end

    -- ========= Mobile Fly (mirrors desktop, sets desiredCF) =========
    local function startMobileFly()
        if FLYING then return end
        local r, h = hrp(), hum()
        if not r or not h then return end
        FLYING = true

        bodyGyro     = Instance.new("BodyGyro");     bodyGyro.MaxTorque = Vector3.new(9e9,9e9,9e9); bodyGyro.P = 1000; bodyGyro.D = 50; bodyGyro.Parent = r
        bodyVelocity = Instance.new("BodyVelocity"); bodyVelocity.MaxForce = Vector3.new(9e9,9e9,9e9); bodyVelocity.Parent = r

        local lastFaceDir = r.CFrame.LookVector
        desiredCF = r.CFrame
        pcall(function() r:SetNetworkOwner(lp) end)

        mobileAddedConn = lp.CharacterAdded:Connect(function()
            r = hrp()
            clear(bodyGyro); clear(bodyVelocity)
            bodyGyro     = Instance.new("BodyGyro");     bodyGyro.MaxTorque = Vector3.new(9e9,9e9,9e9); bodyGyro.P = 1000; bodyGyro.D = 50; bodyGyro.Parent = r
            bodyVelocity = Instance.new("BodyVelocity"); bodyVelocity.MaxForce = Vector3.new(9e9,9e9,9e9); bodyVelocity.Parent = r
            desiredCF = r and r.CFrame or desiredCF
        end)

        mobileRenderConn = RunService.RenderStepped:Connect(function(dt)
            r, h = hrp(), hum()
            local cam = workspace.CurrentCamera
            if not r or not h or not cam then return end
            h.PlatformStand = true
            bodyGyro.CFrame = cam.CFrame

            local move = Vector3.new()
            local ok, controlModule = pcall(function()
                return require(lp.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))
            end)
            if ok and controlModule and controlModule.GetMoveVector then
                move = controlModule:GetMoveVector()
            end

            if forcePosEnabled then
                local dir = move.Magnitude > 0 and move.Unit or Vector3.zero
                local step = (cam.CFrame.RightVector*dir.X + -cam.CFrame.LookVector*dir.Z) * (flySpeed * 50) * dt
                local pos  = desiredCF and desiredCF.Position or r.Position
                local newPos = pos + step
                if dir.Magnitude > 0 then lastFaceDir = Vector3.new(dir.X,0,dir.Z) end
                local faceAt = newPos + Vector3.new(lastFaceDir.X,0,lastFaceDir.Z)
                desiredCF = CFrame.new(newPos, Vector3.new(faceAt.X, newPos.Y, faceAt.Z))
                bodyVelocity.Velocity = Vector3.zero
            else
                local vel = Vector3.new()
                vel += cam.CFrame.RightVector * (move.X * (flySpeed * 50))
                vel += -cam.CFrame.LookVector * (move.Z * (flySpeed * 50))
                bodyVelocity.Velocity = vel
                desiredCF = nil
            end
        end)

        bindGuardian()
    end

    local function stopMobileFly()
        FLYING = false
        disc(mobileRenderConn); mobileRenderConn = nil
        disc(mobileAddedConn);  mobileAddedConn  = nil
        local h = hum(); if h then h.PlatformStand = false end
        clear(bodyVelocity); bodyVelocity = nil
        clear(bodyGyro);     bodyGyro     = nil
        desiredCF = nil
        unbindGuardian()
    end

    local function startFly()
        if UIS.TouchEnabled then mobileFly = true;  startMobileFly()
        else                     mobileFly = false; startDesktopFly() end
    end
    local function stopFly()
        if mobileFly then stopMobileFly() else stopDesktopFly() end
    end

    -- ========= Speed / Noclip / Inf Jump (same as before) =========
    local function setWalkSpeed(v) local h = hum(); if h then h.WalkSpeed = v end end
    local function startNoclip()
        disc(noclipConn)
        noclipConn = RunService.Stepped:Connect(function()
            local ch = lp.Character
            if not ch then return end
            for _,p in ipairs(ch:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end)
    end
    local function stopNoclip() disc(noclipConn); noclipConn = nil end
    local function startInfJump()
        disc(jumpConn)
        jumpConn = UIS.JumpRequest:Connect(function()
            local h = hum(); if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    end
    local function stopInfJump() disc(jumpConn); jumpConn = nil end

    -- ========= UI =========
    tab:Section({ Title = "Player • Movement", Icon = "activity" })
    tab:Slider({
        Title = "Fly Speed",
        Value = { Min = 1, Max = 20, Default = 1 },
        Callback = function(v) flySpeed = tonumber(v) or flySpeed end
    })
    tab:Toggle({
        Title = "Enable Fly",
        Value = false,
        Callback = function(state) flyEnabled = state; if state then startFly() else stopFly() end end
    })

    tab:Divider()
    tab:Section({ Title = "Walk Speed", Icon = "walk" })
    tab:Slider({ Title = "Speed", Value = { Min = 16, Max = 150, Default = 16 }, Callback = function(v) walkSpeedValue = tonumber(v) or walkSpeedValue end })
    tab:Toggle({ Title = "Enable Speed", Value = false, Callback = function(s) if s then setWalkSpeed(walkSpeedValue) else setWalkSpeed(16) end end })

    tab:Divider()
    tab:Section({ Title = "Utilities", Icon = "tool" })
    tab:Toggle({ Title = "Noclip",        Value = false, Callback = function(s) if s then startNoclip() else stopNoclip() end end })
    tab:Toggle({ Title = "Infinite Jump", Value = false, Callback = function(s) if s then startInfJump() else stopInfJump() end end })

    -- NEW: Force Position switch (hard snap-back)
    tab:Divider()
    tab:Section({ Title = "Flight Safety", Icon = "target" })
    tab:Toggle({
        Title = "Force Position",
        Desc  = "When ON, a high-priority loop re-applies the target CFrame every frame.",
        Value = true,
        Callback = function(state)
            forcePosEnabled = state
            if FLYING then
                if state then bindGuardian() else unbindGuardian() end
            end
        end
    })

    -- Auto-reapply after respawn
    lp.CharacterAdded:Connect(function()
        if flyEnabled then task.defer(function() stopFly(); startFly() end) end
    end)
end
