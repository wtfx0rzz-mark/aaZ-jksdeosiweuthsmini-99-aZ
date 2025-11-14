-- nudge.lua
return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI

    local Players = (C and C.Services and C.Services.Players) or game:GetService("Players")
    local WS      = (C and C.Services and C.Services.WS)      or game:GetService("Workspace")
    local Run     = (C and C.Services and C.Services.Run)     or game:GetService("RunService")

    local lp   = Players.LocalPlayer
    local Tabs = (UI and UI.Tabs) or {}
    local tab  = Tabs.Nudge or Tabs.Troll or Tabs.Bring or Tabs.Main or Tabs.Auto
    if not tab then return end

    C.State       = C.State or {}
    C.State.Nudge = C.State.Nudge or {}
    local S       = C.State.Nudge

    local distance = S.Distance or 80
    local height   = S.Height   or 30
    local radius   = S.Radius   or 15
    local applyChars  = (S.ApplyChars  ~= false)
    local applyItems  = (S.ApplyItems  ~= false)
    local edgeEnabled = (S.EdgeButton  == true)
    local autoEnabled = (S.AutoNudge   == true)

    local function hrp(p)
        p = p or lp
        local ch = p.Character or p.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end

    local function mainPart(m)
        if not m or not m.Parent then return nil end
        if m:IsA("BasePart") then return m end
        if m:IsA("Model") then
            if m.PrimaryPart and m.PrimaryPart:IsA("BasePart") then return m.PrimaryPart end
            return m:FindFirstChildWhichIsA("BasePart")
        end
        return nil
    end

    local function isCharacterModel(m)
        return m and m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") ~= nil
    end

    local function isItemModel(m)
        if not (m and m:IsA("Model")) then return false end
        if isCharacterModel(m) then return false end
        local items = WS:FindFirstChild("Items")
        if items and m:IsDescendantOf(items) then
            return true
        end
        return false
    end

    local function unitOr(v, fallback)
        local mag = v.Magnitude
        if mag > 1e-3 then
            return v / mag
        end
        return fallback
    end

    local function ensureEdgeGui()
        local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
        local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
        if not edgeGui then
            edgeGui = Instance.new("ScreenGui")
            edgeGui.Name = "EdgeButtons"
            edgeGui.ResetOnSpawn = false
            pcall(function() edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
            edgeGui.Parent = playerGui
        elseif edgeGui.Parent ~= playerGui then
            edgeGui.Parent = playerGui
        end

        local stack = edgeGui:FindFirstChild("EdgeStack")
        if not stack then
            stack = Instance.new("Frame")
            stack.Name = "EdgeStack"
            stack.AnchorPoint = Vector2.new(1, 0)
            stack.Position = UDim2.new(1, -6, 0, 6)
            stack.Size = UDim2.new(0, 130, 1, -12)
            stack.BackgroundTransparency = 1
            stack.BorderSizePixel = 0
            stack.Parent = edgeGui
            local list = Instance.new("UIListLayout")
            list.Name = "VList"
            list.FillDirection = Enum.FillDirection.Vertical
            list.SortOrder = Enum.SortOrder.LayoutOrder
            list.Padding = UDim.new(0, 6)
            list.HorizontalAlignment = Enum.HorizontalAlignment.Right
            list.Parent = stack
        end

        return edgeGui, stack
    end

    local function makeEdgeBtn(stack, name, label, order)
        local b = stack:FindFirstChild(name)
        if not b then
            b = Instance.new("TextButton")
            b.Name = name
            b.Size = UDim2.new(1, 0, 0, 30)
            b.Text = label
            b.TextSize = 12
            b.Font = Enum.Font.GothamBold
            b.BackgroundColor3 = Color3.fromRGB(30,30,35)
            b.TextColor3 = Color3.new(1,1,1)
            b.BorderSizePixel = 0
            b.Visible = false
            b.LayoutOrder = order or 1
            b.Parent = stack
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 8)
            c.Parent = b
        else
            b.Text = label
            if order then b.LayoutOrder = order end
        end
        return b
    end

    local edgeGui, edgeStack = ensureEdgeGui()
    local nudgeEdgeBtn = makeEdgeBtn(edgeStack, "NudgeEdge", "Nudge", 25)
    nudgeEdgeBtn.Visible = edgeEnabled

    local function nudgeImpulseCharacter(m, origin)
        if not applyChars then return end
        if not isCharacterModel(m) then return end
        if Players:GetPlayerFromCharacter(m) == lp then return end
        local root = m:FindFirstChild("HumanoidRootPart") or mainPart(m)
        if not (root and root:IsA("BasePart")) then return end

        local pos  = root.Position
        local away = Vector3.new(pos.X - origin.X, 0, pos.Z - origin.Z)
        if away.Magnitude < 1e-3 then return end

        local dir   = unitOr(away, Vector3.new(0,0,1))
        local horiz = math.clamp(distance, 0, 400)
        local up    = math.clamp(height,   0, 300)

        pcall(function()
            root.AssemblyAngularVelocity = Vector3.new()
            root.AssemblyLinearVelocity  = dir * horiz + Vector3.new(0, up, 0)
        end)
    end

    local function nudgeImpulseItem(m, origin)
        if not applyItems then return end
        if not isItemModel(m) then return end

        local mp = mainPart(m)
        if not mp then return end
        if mp.Anchored then return end

        local pos  = mp.Position
        local away = Vector3.new(pos.X - origin.X, 0, pos.Z - origin.Z)
        if away.Magnitude < 1e-3 then return end

        local dir   = unitOr(away, Vector3.new(0,0,1))
        local horiz = math.clamp(distance, 0, 400)
        local up    = math.clamp(height,   0, 300)

        pcall(function()
            mp.AssemblyAngularVelocity = Vector3.new()
            mp.AssemblyLinearVelocity  = dir * horiz + Vector3.new(0, up, 0)
        end)
    end

    local function runNudge(center)
        local r = math.max(0, math.min(radius, 80))
        if r <= 0.5 then return end

        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }

        local parts = WS:GetPartBoundsInRadius(center, r, params) or {}
        local seen  = {}

        for _,part in ipairs(parts) do
            if not part:IsA("BasePart") then
                continue
            end
            local m = part:FindFirstAncestorOfClass("Model") or part
            if seen[m] then
                continue
            end
            seen[m] = true

            if m:IsDescendantOf(lp.Character) then
                continue
            end

            if isCharacterModel(m) then
                nudgeImpulseCharacter(m, center)
            elseif isItemModel(m) then
                nudgeImpulseItem(m, center)
            end
        end
    end

    nudgeEdgeBtn.MouseButton1Click:Connect(function()
        local r = hrp()
        if not r then return end
        runNudge(r.Position)
    end)

    local autoConn

    local function setAuto(on)
        on = (on == true)
        if autoConn then
            autoConn:Disconnect()
            autoConn = nil
        end
        autoEnabled = on
        S.AutoNudge = on
        if not on then return end

        autoConn = Run.Heartbeat:Connect(function()
            if not autoEnabled then return end
            local r = hrp()
            if not r then return end
            runNudge(r.Position)
        end)
    end

    tab:Section({ Title = "Nudge" })

    tab:Toggle({
        Title = "Nudge Button",
        Value = edgeEnabled,
        Callback = function(state)
            edgeEnabled = (state == true)
            S.EdgeButton = edgeEnabled
            local _, stack = ensureEdgeGui()
            nudgeEdgeBtn = stack:FindFirstChild("NudgeEdge") or makeEdgeBtn(stack, "NudgeEdge", "Nudge", 25)
            nudgeEdgeBtn.Visible = edgeEnabled
        end
    })

    tab:Toggle({
        Title = "Auto Nudge",
        Value = autoEnabled,
        Callback = function(state)
            setAuto(state)
        end
    })

    tab:Slider({
        Title = "Nudge Distance",
        Value = { Min = 5, Max = 200, Default = distance },
        Callback = function(v)
            local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
            if not n then return end
            n = math.clamp(math.floor(n + 0.5), 5, 200)
            distance = n
            S.Distance = n
        end
    })

    tab:Slider({
        Title = "Nudge Height",
        Value = { Min = 0, Max = 200, Default = height },
        Callback = function(v)
            local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
            if not n then return end
            n = math.clamp(math.floor(n + 0.5), 0, 200)
            height = n
            S.Height = n
        end
    })

    tab:Slider({
        Title = "Nudge Radius",
        Value = { Min = 5, Max = 80, Default = radius },
        Callback = function(v)
            local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
            if not n then return end
            n = math.clamp(math.floor(n + 0.5), 5, 80)
            radius = n
            S.Radius = n
        end
    })

    tab:Toggle({
        Title = "Apply to Characters",
        Value = applyChars,
        Callback = function(state)
            applyChars = (state == true)
            S.ApplyChars = applyChars
        end
    })

    tab:Toggle({
        Title = "Apply to Items",
        Value = applyItems,
        Callback = function(state)
            applyItems = (state == true)
            S.ApplyItems = applyItems
        end
    })

    if autoEnabled then
        setAuto(true)
    end

    Players.LocalPlayer.CharacterAdded:Connect(function()
        edgeGui, edgeStack = ensureEdgeGui()
        nudgeEdgeBtn = edgeStack:FindFirstChild("NudgeEdge") or makeEdgeBtn(edgeStack, "NudgeEdge", "Nudge", 25)
        nudgeEdgeBtn.Visible = edgeEnabled
    end)
end
