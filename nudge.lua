-- nudge.lua
return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI

    local Players = (C and C.Services and C.Services.Players) or game:GetService("Players")
    local WS      = (C and C.Services and C.Services.WS)      or game:GetService("Workspace")
    local Run     = (C and C.Services and C.Services.Run)     or game:GetService("RunService")

    local lp      = Players.LocalPlayer
    local Tabs    = (UI and UI.Tabs) or {}
    local tab     = Tabs.Nudge or Tabs.Troll or Tabs.Main or Tabs.Auto
    if not tab then return end

    C.State         = C.State or {}
    C.State.Toggles = C.State.Toggles or {}
    C.State.Nudge   = C.State.Nudge   or {}

    local Nudge = {
        Distance        = C.State.Nudge.Distance        or 50,
        Height          = C.State.Nudge.Height          or 20,
        Radius          = C.State.Nudge.Radius          or 15,
        ApplyCharacters = (C.State.Nudge.ApplyCharacters ~= false),
        ApplyItems      = (C.State.Nudge.ApplyItems      ~= false),
    }

    local AutoNudgeOn = C.State.Toggles.NudgeAuto or false
    local showNudgeEdge = C.State.Toggles.NudgeButton or false

    local function hrp(p)
        p = p or lp
        local ch = p.Character or p.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    local function mainPart(obj)
        if not obj or not obj.Parent then return nil end
        if obj:IsA("BasePart") then return obj end
        if obj:IsA("Model") then
            if obj.PrimaryPart and obj.PrimaryPart:IsA("BasePart") then
                return obj.PrimaryPart
            end
            return obj:FindFirstChildWhichIsA("BasePart")
        end
        return nil
    end

    local function getParts(target)
        local t = {}
        if not target then return t end
        if target:IsA("BasePart") then
            t[1] = target
        elseif target:IsA("Model") then
            for _,d in ipairs(target:GetDescendants()) do
                if d:IsA("BasePart") then
                    t[#t+1] = d
                end
            end
        end
        return t
    end

    local function itemsRoot()
        return WS:FindFirstChild("Items")
    end

    local function hasHumanoid(model)
        return model and model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") ~= nil
    end

    local function isWallVariant(m)
        if not (m and m:IsA("Model")) then return false end
        local n = (m.Name or ""):lower()
        if n == "logwall" or n == "log wall" then return true end
        if n:find("log", 1, true) and n:find("wall", 1, true) then return true end
        return false
    end

    local function isUnderLogWall(inst)
        local cur = inst
        while cur and cur ~= WS do
            local nm = (cur.Name or ""):lower()
            if nm == "logwall" or nm == "log wall" or (nm:find("log",1,true) and nm:find("wall",1,true)) then
                return true
            end
            cur = cur.Parent
        end
        return false
    end

    local function isExcludedModel(m)
        if not (m and m:IsA("Model")) then return true end
        local n = (m.Name or ""):lower()
        if n == "pelt trader" then return true end
        if n:find("trader",1,true) or n:find("shopkeeper",1,true) then return true end
        if isWallVariant(m) then return true end
        if isUnderLogWall(m) then return true end
        return false
    end

    local function isCharacterModel(m)
        return hasHumanoid(m)
    end

    local function isItemModel(m)
        local root = itemsRoot()
        if not (root and m and m:IsDescendantOf(root)) then
            return false
        end
        if isCharacterModel(m) then
            return false
        end
        if isExcludedModel(m) then
            return false
        end
        return true
    end

    local function unitOr(v, fallback)
        local mag = v.Magnitude
        if mag > 1e-3 then
            return v / mag
        end
        return fallback
    end

    local function impulseItem(model, origin)
        if not Nudge.ApplyItems then return end
        if not isItemModel(model) then return end

        local mp = mainPart(model)
        if not mp then return end
        if mp.Anchored then return end

        local pos  = mp.Position
        local away = Vector3.new(pos.X - origin.X, 0, pos.Z - origin.Z)
        if away.Magnitude < 1e-3 then return end

        local dir   = unitOr(away, Vector3.new(0, 0, 1))
        local horiz = math.clamp(Nudge.Distance, 0, 300)
        local up    = math.clamp(Nudge.Height,   0, 300)

        pcall(function()
            mp.AssemblyAngularVelocity = Vector3.new()
            mp.AssemblyLinearVelocity  = dir * horiz + Vector3.new(0, up, 0)
        end)
    end

    local function impulseCharacter(model, origin)
        if not Nudge.ApplyCharacters then return end
        if not isCharacterModel(model) then return end
        if Players:GetPlayerFromCharacter(model) == lp then
            return
        end
        if isExcludedModel(model) then
            return
        end

        local root = model:FindFirstChild("HumanoidRootPart") or mainPart(model)
        if not root or not root:IsA("BasePart") then return end

        local pos  = root.Position
        local away = Vector3.new(pos.X - origin.X, 0, pos.Z - origin.Z)
        if away.Magnitude < 1e-3 then return end

        local dir   = unitOr(away, Vector3.new(0, 0, 1))
        local horiz = math.clamp(Nudge.Distance, 0, 300)
        local up    = math.clamp(Nudge.Height,   0, 300)

        pcall(function()
            root.AssemblyAngularVelocity = Vector3.new()
            root.AssemblyLinearVelocity  = dir * horiz + Vector3.new(0, up, 0)
        end)
    end

    local function nudgeShockwave(origin, radius)
        radius = radius or Nudge.Radius
        if radius <= 0 then return end

        local excludes = { lp.Character }
        if WS:FindFirstChild("Terrain") then
            table.insert(excludes, WS.Terrain)
        end

        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = excludes

        local parts = WS:GetPartBoundsInRadius(origin, radius, params) or {}
        local seen  = {}

        for _,part in ipairs(parts) do
            if not part:IsA("BasePart") then
                continue
            end

            local model = part:FindFirstAncestorOfClass("Model") or part
            if seen[model] then
                continue
            end
            seen[model] = true

            if model == lp.Character then
                continue
            end

            if isCharacterModel(model) then
                impulseCharacter(model, origin)
            elseif isItemModel(model) then
                impulseItem(model, origin)
            end
        end
    end

    local function ensureEdgeGui()
        local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
        local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
        if not edgeGui then
            edgeGui = Instance.new("ScreenGui")
            edgeGui.Name = "EdgeButtons"
            edgeGui.ResetOnSpawn = false
            pcall(function()
                edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            end)
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
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 8)
            corner.Parent = b
        else
            b.Text = label
            b.LayoutOrder = order or b.LayoutOrder
        end
        return b
    end

    local edgeGui, edgeStack = ensureEdgeGui()
    local nudgeBtn = makeEdgeBtn(edgeStack, "NudgeEdge", "Nudge", 50)
    nudgeBtn.Visible = showNudgeEdge

    nudgeBtn.MouseButton1Click:Connect(function()
        local r = hrp()
        if r then
            nudgeShockwave(r.Position, Nudge.Radius)
        end
    end)

    local autoConn

    local function updateAutoNudge()
        if autoConn then
            autoConn:Disconnect()
            autoConn = nil
        end

        if not AutoNudgeOn then
            return
        end

        autoConn = Run.Heartbeat:Connect(function()
            if not AutoNudgeOn then return end
            local r = hrp()
            if not r then return end
            nudgeShockwave(r.Position, Nudge.Radius)
        end)
    end

    tab:Section({ Title = "Nudge" })

    tab:Toggle({
        Title = "Nudge Button",
        Value = showNudgeEdge,
        Callback = function(on)
            on = (on == true)
            showNudgeEdge = on
            C.State.Toggles.NudgeButton = on
            local _, stack = ensureEdgeGui()
            local btn = stack:FindFirstChild("NudgeEdge") or makeEdgeBtn(stack, "NudgeEdge", "Nudge", 50)
            btn.Visible = on
        end
    })

    tab:Toggle({
        Title = "Auto Nudge",
        Value = AutoNudgeOn,
        Callback = function(on)
            on = (on == true)
            AutoNudgeOn = on
            C.State.Toggles.NudgeAuto = on
            updateAutoNudge()
        end
    })

    tab:Slider({
        Title = "Nudge Distance",
        Value = { Min = 5, Max = 200, Default = Nudge.Distance },
        Callback = function(v)
            local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
            if not n then return end
            n = math.clamp(math.floor(n + 0.5), 5, 200)
            Nudge.Distance = n
            C.State.Nudge.Distance = n
        end
    })

    tab:Slider({
        Title = "Nudge Height",
        Value = { Min = 0, Max = 200, Default = Nudge.Height },
        Callback = function(v)
            local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
            if not n then return end
            n = math.clamp(math.floor(n + 0.5), 0, 200)
            Nudge.Height = n
            C.State.Nudge.Height = n
        end
    })

    tab:Slider({
        Title = "Nudge Radius",
        Value = { Min = 5, Max = 80, Default = Nudge.Radius },
        Callback = function(v)
            local n = tonumber(type(v) == "table" and (v.Value or v.Current or v.Default) or v)
            if not n then return end
            n = math.clamp(math.floor(n + 0.5), 5, 80)
            Nudge.Radius = n
            C.State.Nudge.Radius = n
        end
    })

    tab:Toggle({
        Title = "Apply to Characters",
        Value = (C.State.Nudge.ApplyCharacters ~= false),
        Callback = function(on)
            on = (on == true)
            Nudge.ApplyCharacters = on
            C.State.Nudge.ApplyCharacters = on
        end
    })

    tab:Toggle({
        Title = "Apply to Items",
        Value = (C.State.Nudge.ApplyItems ~= false),
        Callback = function(on)
            on = (on == true)
            Nudge.ApplyItems = on
            C.State.Nudge.ApplyItems = on
        end
    })

    updateAutoNudge()

    Players.LocalPlayer.CharacterAdded:Connect(function()
        edgeGui, edgeStack = ensureEdgeGui()
        nudgeBtn = edgeStack:FindFirstChild("NudgeEdge") or makeEdgeBtn(edgeStack, "NudgeEdge", "Nudge", 50)
        nudgeBtn.Visible = showNudgeEdge
        nudgeBtn.MouseButton1Click:Connect(function()
            local r = hrp()
            if r then
                nudgeShockwave(r.Position, Nudge.Radius)
            end
        end)
        updateAutoNudge()
    end)
end
