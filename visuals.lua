-- visuals.lua — Visuals tab (Player Tracker / Invisible / Highlight Trees In Aura)

return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Visuals, "visuals.lua: Visuals tab missing")

    local Players = C.Services.Players
    local WS      = C.Services.WS
    local Run     = C.Services.Run
    local lp      = C.LocalPlayer
    local VisualsTab = UI.Tabs.Visuals

    C.State = C.State or { AuraRadius = 150, Toggles = {} }

    -- ---------- helpers ----------
    local function auraRadius()
        return math.clamp(tonumber(C.State.AuraRadius) or 150, 0, 1_000_000)
    end

    local TREE_NAMES = { ["Small Tree"]=true, ["Snowy Small Tree"]=true }

    local function bestPart(model)
        if not model or not model:IsA("Model") then return nil end
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then return hrp end
        local trunk = model:FindFirstChild("Trunk")
        if trunk and trunk:IsA("BasePart") then return trunk end
        if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
        return model:FindFirstChildWhichIsA("BasePart")
    end

    local function collectTreesInRadius(origin, radius, maxCount)
        local out, n = {}, 0
        local roots = {
            WS,
            (C.Services.RS and C.Services.RS:FindFirstChild("Assets")) or nil,
            (C.Services.RS and C.Services.RS:FindFirstChild("CutsceneSets")) or nil,
        }
        local function walk(node)
            if not node or n >= maxCount then return end
            if node:IsA("Model") and TREE_NAMES[node.Name] then
                local p = bestPart(node)
                if p and (p.Position - origin).Magnitude <= radius then
                    n += 1
                    out[n] = node
                end
            end
            local ok, children = pcall(node.GetChildren, node)
            if not ok then return end
            for _, ch in ipairs(children) do
                if n >= maxCount then break end
                walk(ch)
            end
        end
        for _, r in ipairs(roots) do if r then walk(r) end end
        return out
    end

    local function ensureHighlight(parent, name)
        local hl = parent:FindFirstChild(name)
        if hl and hl:IsA("Highlight") then return hl end
        hl = Instance.new("Highlight")
        hl.Name = name
        hl.Adornee = parent
        hl.FillTransparency = 1
        hl.OutlineTransparency = 0
        hl.OutlineColor = Color3.fromRGB(0, 0, 0) -- darker/bolder outline
        hl.DepthMode = Enum.HighlightDepthMode.Occluded
        hl.Parent = parent
        return hl
    end

    local function clearHighlight(parent, name)
        local hl = parent and parent:FindFirstChild(name)
        if hl and hl:IsA("Highlight") then hl:Destroy() end
    end

    -- ---------- Player Tracker ----------
    local runningPlayers = false
    local PLAYER_HL_NAME = "__PlayerTrackerHL__"

    local function startPlayerTracker()
        if runningPlayers then return end
        runningPlayers = true
        task.spawn(function()
            while runningPlayers do
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= lp then
                        local ch = plr.Character
                        if ch then
                            ensureHighlight(ch, PLAYER_HL_NAME).Enabled = true
                        end
                    end
                end
                task.wait(0.5)
            end
            -- turn off when stopped
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= lp and plr.Character then
                    clearHighlight(plr.Character, PLAYER_HL_NAME)
                end
            end
        end)
    end

    local function stopPlayerTracker()
        runningPlayers = false
    end

    -- ---------- Invisible (local only) ----------
    local invisibleOn = false
    local function setLocalInvisible(state)
        invisibleOn = state
        local ch = lp and lp.Character
        if not ch then return end
        for _, d in ipairs(ch:GetDescendants()) do
            if d:IsA("BasePart") then
                d.LocalTransparencyModifier = state and 1 or 0
            elseif d:IsA("Decal") then
                d.Transparency = state and 1 or 0
            end
        end
    end

    -- ---------- Highlight Trees In Aura (radius-gated) ----------
    local runningTrees = false
    local TREE_HL_NAME = "__TreeAuraHL__"

    local function startTreeHighlight()
        if runningTrees then return end
        runningTrees = true
        task.spawn(function()
            while runningTrees do
                local ch = lp.Character or lp.CharacterAdded:Wait()
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if not hrp then task.wait(0.2) break end

                local r = auraRadius()
                local trees = collectTreesInRadius(hrp.Position, r, 256)
                local seen = {}

                for _, m in ipairs(trees) do
                    seen[m] = true
                    ensureHighlight(m, TREE_HL_NAME).Enabled = true
                end

                -- disable highlights on trees no longer in range
                for _, root in ipairs({WS}) do
                    for _, model in ipairs(root:GetDescendants()) do
                        if model:IsA("Model") and TREE_NAMES[model.Name] then
                            local hl = model:FindFirstChild(TREE_HL_NAME)
                            if hl and not seen[model] then
                                hl.Enabled = false
                                hl:Destroy()
                            end
                        end
                    end
                end

                task.wait(0.35)
            end

            -- cleanup when toggle goes off
            for _, root in ipairs({WS}) do
                for _, model in ipairs(root:GetDescendants()) do
                    if model:IsA("Model") and TREE_NAMES[model.Name] then
                        clearHighlight(model, TREE_HL_NAME)
                    end
                end
            end
        end)
    end

    local function stopTreeHighlight()
        runningTrees = false
    end

    -- ---------- UI ----------
    VisualsTab:Section({ Title = "Player Tracker" })
    VisualsTab:Toggle({
        Title = "Player Tracker",
        Value = C.State.Toggles.PlayerTracker or false,
        Callback = function(on)
            C.State.Toggles.PlayerTracker = on
            if on then startPlayerTracker() else stopPlayerTracker() end
        end
    })

    VisualsTab:Section({ Title = "Invisible" })
    VisualsTab:Toggle({
        Title = "Invisible",
        Value = C.State.Toggles.Invisible or false,
        Callback = function(on)
            C.State.Toggles.Invisible = on
            setLocalInvisible(on)
        end
    })

    VisualsTab:Section({ Title = "Highlight Trees In Aura" })
    VisualsTab:Toggle({
        Title = "Highlight Trees In Aura",
        Value = C.State.Toggles.HighlightTrees or false,
        Callback = function(on)
            C.State.Toggles.HighlightTrees = on
            if on then startTreeHighlight() else stopTreeHighlight() end
        end
    })
end
