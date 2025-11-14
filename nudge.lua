-- nudge.lua
return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs, "nudge.lua: missing context or UI")

    local Players = (C.Services and C.Services.Players) or game:GetService("Players")
    local WS      = (C.Services and C.Services.WS)      or game:GetService("Workspace")

    local lp   = Players.LocalPlayer
    local Tabs = UI.Tabs or {}
    local tab  = Tabs.Nudge or Tabs.Main or Tabs.Auto
    if not tab then return end

    C.Config        = C.Config or {}
    C.Config.Nudge  = C.Config.Nudge or {}
    C.State         = C.State or {}
    C.State.Nudge   = C.State.Nudge or {}

    local CFG   = C.Config.Nudge
    local STATE = C.State.Nudge

    CFG.UpPower   = CFG.UpPower   or 80
    CFG.AwayPower = CFG.AwayPower or 80
    CFG.Radius    = CFG.Radius    or 80

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    local function isNPC(model)
        if not (model and model:IsA("Model")) then return false end
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hum then return false end
        if Players:GetPlayerFromCharacter(model) then return false end
        local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
        return root ~= nil
    end

    local function isInteractableItem(inst)
        local m = inst
        if m:IsA("BasePart") then
            m = m.Parent
        end
        if not (m and m:IsA("Model")) then
            return false
        end
        if m:FindFirstChildWhichIsA("ProximityPrompt", true) then
            return true
        end
        if m:FindFirstChildWhichIsA("ClickDetector", true) then
            return true
        end
        if m:GetAttribute("Interactable") == true then
            return true
        end
        return false
    end

    local function mainPartFromInstance(inst)
        if inst:IsA("BasePart") then
            return inst
        end
        local m = inst
        if not m:IsA("Model") then
            m = inst.Parent
        end
        if not (m and m:IsA("Model")) then
            return nil
        end
        return m.PrimaryPart
            or m:FindFirstChild("HumanoidRootPart")
            or m:FindFirstChildWhichIsA("BasePart")
    end

    local function getCandidates(origin, radius)
        local out = {}
        for _, inst in ipairs(WS:GetDescendants()) do
            local model

            if inst:IsA("Model") and isNPC(inst) then
                model = inst
            elseif inst:IsA("BasePart") or inst:IsA("Model") then
                if isInteractableItem(inst) then
                    if inst:IsA("Model") then
                        model = inst
                    else
                        model = inst.Parent
                    end
                end
            end

            if model then
                local part = mainPartFromInstance(model)
                if part and not part.Anchored then
                    local pos = part.Position
                    local d = (Vector3.new(pos.X, origin.Y, pos.Z) - Vector3.new(origin.X, origin.Y, origin.Z)).Magnitude
                    if d <= radius and d > 0.1 then
                        table.insert(out, part)
                    end
                end
            end
        end
        return out
    end

    local function applyNudge()
        local root = hrp()
        if not root then return end

        local origin = root.Position
        local up     = CFG.UpPower   or 80
        local away   = CFG.AwayPower or 80
        local radius = CFG.Radius    or 80

        local list = getCandidates(origin, radius)
        for _, part in ipairs(list) do
            local offset    = part.Position - origin
            local horizontal = Vector3.new(offset.X, 0, offset.Z)
            local mag       = horizontal.Magnitude

            local dir
            if mag < 1e-3 then
                dir = Vector3.new(1, 0, 0)
            else
                dir = horizontal / mag
            end

            local v = dir * away + Vector3.new(0, up, 0)
            local assemblyRoot = part.AssemblyRootPart or part
            assemblyRoot.AssemblyLinearVelocity = v
        end
    end

    local edgeScreenGui
    local edgeButton

    local function destroyEdge()
        if edgeButton then
            edgeButton:Destroy()
            edgeButton = nil
        end
        if edgeScreenGui then
            edgeScreenGui:Destroy()
            edgeScreenGui = nil
        end
    end

    local function ensureEdge()
        if edgeButton and edgeButton.Parent then
            return
        end

        destroyEdge()

        local pg = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")

        edgeScreenGui = Instance.new("ScreenGui")
        edgeScreenGui.Name = "NudgeEdgeGui"
        edgeScreenGui.ResetOnSpawn = false
        edgeScreenGui.Parent = pg

        edgeButton = Instance.new("TextButton")
        edgeButton.Name = "NudgeButton"
        edgeButton.Size = UDim2.new(0, 120, 0, 32)
        edgeButton.AnchorPoint = Vector2.new(1, 0.5)
        edgeButton.Position = UDim2.new(1, -10, 0.5, 0)
        edgeButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        edgeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        edgeButton.TextScaled = true
        edgeButton.Text = "NUDGE"
        edgeButton.Parent = edgeScreenGui

        edgeButton.MouseButton1Click:Connect(applyNudge)
    end

    tab:Section({ Title = "Nudge" })

    tab:Toggle({
        Title = "Enable Nudge Edge Button",
        Default = STATE.EdgeEnabled or false,
        Callback = function(on)
            STATE.EdgeEnabled = on
            if on then
                ensureEdge()
            else
                destroyEdge()
            end
        end
    })

    tab:Slider({
        Title = "Upward Power",
        Value = { Min = 0, Max = 200, Default = CFG.UpPower or 80 },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then
                nv = v.Value or v.Current or v.CurrentValue or v.Default or v.min or v.max
            end
            nv = tonumber(nv)
            if nv then
                CFG.UpPower = math.clamp(nv, 0, 500)
            end
        end
    })

    tab:Slider({
        Title = "Outward Power",
        Value = { Min = 0, Max = 200, Default = CFG.AwayPower or 80 },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then
                nv = v.Value or v.Current or v.CurrentValue or v.Default or v.min or v.max
            end
            nv = tonumber(nv)
            if nv then
                CFG.AwayPower = math.clamp(nv, 0, 500)
            end
        end
    })

    tab:Slider({
        Title = "Effect Radius",
        Value = { Min = 0, Max = 300, Default = CFG.Radius or 80 },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then
                nv = v.Value or v.Current or v.CurrentValue or v.Default or v.min or v.max
            end
            nv = tonumber(nv)
            if nv then
                CFG.Radius = math.clamp(nv, 0, 500)
            end
        end
    })
end
