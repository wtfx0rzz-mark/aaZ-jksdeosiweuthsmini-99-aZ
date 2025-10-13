--=====================================================
-- 1337 Nights | Visuals Module (Outline Only)
--=====================================================
-- Adds toggles to the Visuals tab:
--   • "Track Team" — bright yellow outline for other players
--   • "Invisible"  — toggles local player invisibility
--   • "Highlight Trees In Aura" — outlines nearby trees (aura-based)
--=====================================================

return function(C, R, UI)
    -----------------------------------------------------
    -- Services and shared state
    -----------------------------------------------------
    local Players = C.Services.Players
    local RunService = C.Services.Run
    local WS = C.Services.WS
    local LocalPlayer = C.LocalPlayer

    local VisualsTab = UI.Tabs.Visuals
    assert(VisualsTab, "Visuals tab missing from UI")

    -----------------------------------------------------
    -- Folders for highlight management
    -----------------------------------------------------
    local teamFolder = Instance.new("Folder")
    teamFolder.Name = "__TeamHighlights__"
    teamFolder.Parent = WS

    local treeFolder = Instance.new("Folder")
    treeFolder.Name = "__TreeHighlights__"
    treeFolder.Parent = WS

    -----------------------------------------------------
    -- Highlight helpers (outline-only)
    -----------------------------------------------------
    local COLOR_OUTLINE = Color3.fromRGB(255, 255, 80) -- bright yellow

    local function ensureHighlight(model)
        if not model or not model:IsA("Model") then return nil end
        local hl = model:FindFirstChildOfClass("Highlight")
        if not hl then
            hl = Instance.new("Highlight")
            hl.Parent = model
        end

        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillTransparency = 1          -- fully transparent center
        hl.OutlineTransparency = 0       -- solid outline
        hl.OutlineColor = COLOR_OUTLINE  -- bright bold outline
        hl.FillColor = Color3.new(0, 0, 0) -- irrelevant (hidden)
        return hl
    end

    local function removeHighlight(model)
        if not model or not model:IsA("Model") then return end
        local hl = model:FindFirstChildOfClass("Highlight")
        if hl then hl:Destroy() end
    end

    local function clearFolder(folder)
        for _,v in ipairs(folder:GetChildren()) do
            v:Destroy()
        end
    end

    -----------------------------------------------------
    -- Track Team (player highlights)
    -----------------------------------------------------
    local trackEnabled = false
    local teamConnAdd, teamConnChar

    local function applyTrackHighlights()
        clearFolder(teamFolder)
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local hl = ensureHighlight(plr.Character)
                if hl then hl.Parent = teamFolder end
            end
        end
    end

    local function stopTrackHighlights()
        clearFolder(teamFolder)
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                removeHighlight(plr.Character)
            end
        end
        if teamConnAdd then teamConnAdd:Disconnect() teamConnAdd=nil end
        if teamConnChar then teamConnChar:Disconnect() teamConnChar=nil end
    end

    local function startTrackHighlights()
        applyTrackHighlights()
        teamConnAdd = Players.PlayerAdded:Connect(function(plr)
            if plr ~= LocalPlayer then
                plr.CharacterAdded:Connect(function(char)
                    task.wait(1)
                    if trackEnabled then
                        ensureHighlight(char)
                    end
                end)
            end
        end)
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                plr.CharacterAdded:Connect(function(char)
                    task.wait(1)
                    if trackEnabled then
                        ensureHighlight(char)
                    end
                end)
            end
        end
    end

    -----------------------------------------------------
    -- Invisible (self)
    -----------------------------------------------------
    local function setSelfInvisible(state)
        local char = LocalPlayer.Character
        if not char then return end
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") then
                d.LocalTransparencyModifier = state and 1 or 0
            end
        end
    end

    -----------------------------------------------------
    -- Highlight Trees in Aura
    -----------------------------------------------------
    local highlightTreesEnabled = false
    local auraConnection

    local function getTreesInAura()
        local results = {}
        local char = LocalPlayer.Character
        if not char then return results end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return results end
        local origin = hrp.Position
        local radius = tonumber(C.State.AuraRadius) or 150

        local map = WS:FindFirstChild("Map")
        if not map then return results end

        local function scan(folder)
            if not folder then return end
            for _, obj in ipairs(folder:GetChildren()) do
                if obj:IsA("Model") and obj.Name == C.Config.TREE_NAME then
                    local trunk = obj:FindFirstChild("Trunk") or obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                    if trunk and (trunk.Position - origin).Magnitude <= radius then
                        table.insert(results, obj)
                    end
                end
            end
        end

        scan(map:FindFirstChild("Foliage"))
        scan(map:FindFirstChild("Landmarks"))
        return results
    end

    local function updateTreeHighlights()
        clearFolder(treeFolder)
        local trees = getTreesInAura()
        for _,tree in ipairs(trees) do
            local hl = ensureHighlight(tree)
            if hl then hl.Parent = treeFolder end
        end
    end

    local function startTreeHighlight()
        if auraConnection then auraConnection:Disconnect() end
        auraConnection = RunService.Heartbeat:Connect(function()
            updateTreeHighlights()
        end)
    end

    local function stopTreeHighlight()
        if auraConnection then auraConnection:Disconnect(); auraConnection=nil end
        clearFolder(treeFolder)
        local map = WS:FindFirstChild("Map")
        if not map then return end
        local function clean(folder)
            if not folder then return end
            for _,obj in ipairs(folder:GetChildren()) do
                if obj:IsA("Model") and obj.Name == C.Config.TREE_NAME then
                    removeHighlight(obj)
                end
            end
        end
        clean(map:FindFirstChild("Foliage"))
        clean(map:FindFirstChild("Landmarks"))
    end

    -----------------------------------------------------
    -- UI: Visuals tab toggles
    -----------------------------------------------------
    VisualsTab:Section({ Title = "Visual Options" })

    -- Track Team
    VisualsTab:Toggle({
        Title = "Track Team",
        Value = false,
        Callback = function(state)
            trackEnabled = state
            if state then
                startTrackHighlights()
            else
                stopTrackHighlights()
            end
        end
    })

    -- Invisible
    VisualsTab:Toggle({
        Title = "Invisible",
        Value = false,
        Callback = function(state)
            setSelfInvisible(state)
        end
    })

    -- Highlight Trees In Aura
    local treeToggle
    treeToggle = VisualsTab:Toggle({
        Title = "Highlight Trees In Aura",
        Value = false,
        Callback = function(state)
            -- Prevent enabling if aura is off
            if state and not C.State.Toggles.SmallTreeAura then
                warn("[Visuals] Cannot highlight trees — Small Tree Aura is OFF")
                if treeToggle and treeToggle.Set then
                    treeToggle:Set(false)
                end
                return
            end

            highlightTreesEnabled = state
            if state then
                startTreeHighlight()
            else
                stopTreeHighlight()
            end
        end
    })

    -----------------------------------------------------
    -- Auto-disable tree highlight if aura stops
    -----------------------------------------------------
    RunService.Heartbeat:Connect(function()
        if highlightTreesEnabled and not C.State.Toggles.SmallTreeAura then
            highlightTreesEnabled = false
            stopTreeHighlight()
            if treeToggle and treeToggle.Set then
                treeToggle:Set(false)
            end
        end
    end)
end
