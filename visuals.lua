--=====================================================
-- 1337 Nights | Visuals Module
--=====================================================
-- Adds toggles to the Visuals tab:
--   • "Track Team" — highlights other players' characters
--   • "Invisible"  — toggles local player invisibility
--   • "Highlight Trees In Aura" — outlines trees within aura distance
--=====================================================

return function(C, R, UI)
    -----------------------------------------------------
    -- Services and state
    -----------------------------------------------------
    local Players = C.Services.Players
    local RunService = C.Services.Run
    local WS = C.Services.WS
    local LocalPlayer = C.LocalPlayer

    local VisualsTab = UI.Tabs.Visuals
    local highlightFolder = Instance.new("Folder")
    highlightFolder.Name = "__VisualHighlights__"
    highlightFolder.Parent = WS

    local treeFolder = Instance.new("Folder")
    treeFolder.Name = "__TreeHighlights__"
    treeFolder.Parent = WS

    local trackTeamEnabled = false
    local invisibleSelfEnabled = false
    local highlightTreesEnabled = false

    -----------------------------------------------------
    -- Helpers
    -----------------------------------------------------
    local OUTLINE_COLOR = Color3.fromRGB(255, 255, 100)
    local TREE_COLOR = Color3.fromRGB(0, 255, 100)

    local function ensureHighlight(model, color)
        if not model or not model:IsA("Model") then return end
        local hl = model:FindFirstChildOfClass("Highlight")
        if not hl then
            hl = Instance.new("Highlight")
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.FillTransparency = 0.8
            hl.OutlineTransparency = 0
            hl.Parent = model
        end
        hl.FillColor = color or OUTLINE_COLOR
        hl.OutlineColor = color or OUTLINE_COLOR
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
    -- Track Team (Show Hitboxes)
    -----------------------------------------------------
    local function applyTrackTeam()
        clearFolder(highlightFolder)
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local c = plr.Character
                local hl = ensureHighlight(c, OUTLINE_COLOR)
                if hl then hl.Parent = highlightFolder end
            end
        end
    end

    local function removeTrackTeam()
        clearFolder(highlightFolder)
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                removeHighlight(plr.Character)
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
    local auraConnection
    local function highlightTreesInRange()
        clearFolder(treeFolder)
        if not LocalPlayer.Character then return end
        local hrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local origin = hrp.Position
        local radius = tonumber(C.State.AuraRadius) or 150

        local map = WS:FindFirstChild("Map")
        if not map then return end

        local function scan(folder)
            if not folder then return end
            for _, obj in ipairs(folder:GetChildren()) do
                if obj:IsA("Model") and obj.Name == C.Config.TREE_NAME then
                    local trunk = obj:FindFirstChild("Trunk") or obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                    if trunk and (trunk.Position - origin).Magnitude <= radius then
                        local hl = ensureHighlight(obj, TREE_COLOR)
                        if hl then hl.Parent = treeFolder end
                    else
                        removeHighlight(obj)
                    end
                end
            end
        end

        scan(map:FindFirstChild("Foliage"))
        scan(map:FindFirstChild("Landmarks"))
    end

    local function startTreeAura()
        if auraConnection then auraConnection:Disconnect() end
        auraConnection = RunService.Heartbeat:Connect(function(dt)
            highlightTreesInRange()
        end)
    end

    local function stopTreeAura()
        if auraConnection then auraConnection:Disconnect(); auraConnection = nil end
        clearFolder(treeFolder)
        local map = WS:FindFirstChild("Map")
        if map then
            local function clean(folder)
                if not folder then return end
                for _, obj in ipairs(folder:GetChildren()) do
                    if obj:IsA("Model") and obj.Name == C.Config.TREE_NAME then
                        removeHighlight(obj)
                    end
                end
            end
            clean(map:FindFirstChild("Foliage"))
            clean(map:FindFirstChild("Landmarks"))
        end
    end

    -----------------------------------------------------
    -- UI Setup
    -----------------------------------------------------
    VisualsTab:Section({ Title = "Visual Options" })

    -- Track Team toggle
    VisualsTab:Toggle({
        Title = "Track Team",
        Value = false,
        Callback = function(state)
            trackTeamEnabled = state
            if state then
                applyTrackTeam()
                Players.PlayerAdded:Connect(function(plr)
                    task.wait(1)
                    if trackTeamEnabled and plr.Character then
                        ensureHighlight(plr.Character, OUTLINE_COLOR)
                    end
                end)
            else
                removeTrackTeam()
            end
        end
    })

    -- Invisible toggle
    VisualsTab:Toggle({
        Title = "Invisible",
        Value = false,
        Callback = function(state)
            invisibleSelfEnabled = state
            setSelfInvisible(state)
        end
    })

    -- Highlight Trees toggle
    VisualsTab:Toggle({
        Title = "Highlight Trees In Aura",
        Value = false,
        Callback = function(state)
            highlightTreesEnabled = state
            if state then
                startTreeAura()
            else
                stopTreeAura()
            end
        end
    })
end
