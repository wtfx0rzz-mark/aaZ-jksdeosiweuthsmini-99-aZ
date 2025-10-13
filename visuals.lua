--=====================================================
-- 1337 Nights | Visuals Module (Clean OUTLINE-Only)
--=====================================================
-- Goal
--   • Draw a single, clean outline around whole player models and tree models.
--   • NO per-part boxes, NO silhouette fill, NO internal seam lines.
--
-- Key Technique
--   • Use exactly ONE Highlight per Model:
--       - FillTransparency = 1 (no fill at all)
--       - OutlineTransparency = 0 (fully visible outline)
--       - DepthMode = AlwaysOnTop (keeps outline visible through props)
--   • DO NOT add SelectionBox / BoxHandleAdornment — those cause per-part seams.
--
-- UI
--   • Visuals → Track Team (outlines other players only; excludes local player)
--   • Visuals → Invisible (local-only transparency via LocalTransparencyModifier)
--   • Visuals → Highlight Trees In Aura (outlines trees within aura radius)
--
-- Project rules (persisting):
--   • Always provide full, top-to-bottom code.
--   • Roblox/Lua code must include helpful comments throughout.
--=====================================================

return function(C, R, UI)
    -----------------------------------------------------
    -- Services / Short-hands
    -----------------------------------------------------
    local Players    = C.Services.Players
    local RunService = C.Services.Run
    local WS         = C.Services.WS
    local LP         = C.LocalPlayer

    local VisualsTab = UI.Tabs.Visuals
    assert(VisualsTab, "Visuals tab missing from UI")

    -----------------------------------------------------
    -- Visual Containers (for easy cleanup)
    -----------------------------------------------------
    local rootFolder = Instance.new("Folder")
    rootFolder.Name = "__Visuals_Root__"
    rootFolder.Parent = WS

    local teamFolder = Instance.new("Folder")
    teamFolder.Name = "__Team_Outlines__"
    teamFolder.Parent = rootFolder

    local treeFolder = Instance.new("Folder")
    treeFolder.Name = "__Tree_Outlines__"
    treeFolder.Parent = rootFolder

    -----------------------------------------------------
    -- Style
    -----------------------------------------------------
    -- Requested color: (255, 255, 100)
    local OUTLINE_COLOR = Color3.fromRGB(255, 255, 100)

    -----------------------------------------------------
    -- Utilities
    -----------------------------------------------------

    -- Remove all children (used to clear our folders)
    local function clearChildren(folder: Instance)
        for _,v in ipairs(folder:GetChildren()) do
            v:Destroy()
        end
    end

    -- Remove any Highlights on a model that we previously added
    local function removeOurOutline(model: Model)
        if not model then return end
        for _,h in ipairs(model:GetChildren()) do
            if h:IsA("Highlight") and h.Name == "ModelOutline" then
                h:Destroy()
            end
        end
    end

    -- Ensure exactly one clean outline Highlight on the supplied model.
    -- No fill, only a bright outline, always on top.
    local function ensureModelOutline(model: Model, parentFolder: Instance)
        if not (model and model:IsA("Model")) then return end

        -- Nuke any prior outline we created to avoid duplicates
        removeOurOutline(model)

        -- Create a single Highlight that adorns the entire model as one unit
        local hl = Instance.new("Highlight")
        hl.Name = "ModelOutline"
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillTransparency = 1                 -- NO FILL (prevents silhouette effect)
        hl.OutlineTransparency = 0              -- fully visible outline
        hl.OutlineColor = OUTLINE_COLOR
        hl.Parent = model

        -- Token in our folder (helps with mass cleanup if needed)
        local token = Instance.new("ObjectValue")
        token.Name = "HL_TOKEN"
        token.Value = hl
        token.Parent = parentFolder
    end

    -----------------------------------------------------
    -- Track Team (players other than local player)
    -----------------------------------------------------
    local trackEnabled = false
    local teamConns: {[any]: RBXScriptConnection} = {}

    local function applyTeamOutlineToCharacter(char: Model)
        if not char then return end
        ensureModelOutline(char, teamFolder)
    end

    local function startTrackTeam()
        -- Apply to existing players (excluding local)
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                -- (Re)connect CharacterAdded; apply immediately if spawned
                if teamConns[plr] then teamConns[plr]:Disconnect() end
                teamConns[plr] = plr.CharacterAdded:Connect(function(newChar)
                    task.wait(0.25)
                    if trackEnabled then applyTeamOutlineToCharacter(newChar) end
                end)
                if plr.Character then
                    applyTeamOutlineToCharacter(plr.Character)
                end
            end
        end

        -- Handle roster changes
        if not teamConns["_PlayerAdded"] then
            teamConns["_PlayerAdded"] = Players.PlayerAdded:Connect(function(plr)
                if plr == LP then return end
                if teamConns[plr] then teamConns[plr]:Disconnect() end
                teamConns[plr] = plr.CharacterAdded:Connect(function(newChar)
                    task.wait(0.25)
                    if trackEnabled then applyTeamOutlineToCharacter(newChar) end
                end)
                if plr.Character then
                    task.wait(0.25)
                    if trackEnabled then applyTeamOutlineToCharacter(plr.Character) end
                end
            end)
        end

        if not teamConns["_PlayerRemoving"] then
            teamConns["_PlayerRemoving"] = Players.PlayerRemoving:Connect(function(plr)
                if teamConns[plr] then teamConns[plr]:Disconnect() end
                if plr.Character then removeOurOutline(plr.Character) end
            end)
        end
    end

    local function stopTrackTeam()
        -- Disconnect all signals
        for k,conn in pairs(teamConns) do
            if typeof(conn) == "RBXScriptConnection" then
                conn:Disconnect()
            end
            teamConns[k] = nil
        end

        -- Remove visuals
        clearChildren(teamFolder)
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Character then
                removeOurOutline(plr.Character)
            end
        end
    end

    -----------------------------------------------------
    -- Invisible (local player only)
    -----------------------------------------------------
    local function setSelfInvisible(state: boolean)
        local char = LP.Character
        if not char then return end
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") then
                -- LocalTransparencyModifier is client-only; server won’t see it.
                d.LocalTransparencyModifier = state and 1 or 0
            end
        end
    end

    -----------------------------------------------------
    -- Tree Outlines (within Aura radius)
    -----------------------------------------------------
    local treeHLRunning = false
    local treeHeartbeatConn: RBXScriptConnection? = nil
    local lastTreeTick = 0

    -- Collect all “Small Tree” models within the current Aura radius of the local player
    local function collectTreesInAura(): {Model}
        local out = {}

        local char = LP.Character; if not char then return out end
        local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then return out end
        local origin = hrp.Position

        -- Read your shared aura radius (falls back to 150 if not set)
        local radius = tonumber(C.State.AuraRadius) or 150

        local map = WS:FindFirstChild("Map"); if not map then return out end

        local function scan(folder: Instance?)
            if not folder then return end
            for _,m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") and m.Name == C.Config.TREE_NAME then
                    local trunk = m:FindFirstChild("Trunk") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
                    if trunk and (trunk.Position - origin).Magnitude <= radius then
                        table.insert(out, m)
                    end
                end
            end
        end

        scan(map:FindFirstChild("Foliage"))
        scan(map:FindFirstChild("Landmarks"))
        return out
    end

    local function refreshTreeOutlines()
        -- Simple full refresh (safe & robust). If needed, we can cache later.
        clearChildren(treeFolder)

        local trees = collectTreesInAura()
        for _,t in ipairs(trees) do
            ensureModelOutline(t, treeFolder)
        end
    end

    local function startTreeHL()
        if treeHeartbeatConn then treeHeartbeatConn:Disconnect(); treeHeartbeatConn=nil end
        treeHLRunning = true

        -- Throttle refresh to reduce work while staying responsive.
        treeHeartbeatConn = RunService.Heartbeat:Connect(function()
            if not treeHLRunning then return end
            local now = os.clock()
            if now - lastTreeTick >= 0.20 then
                lastTreeTick = now
                refreshTreeOutlines()
            end
        end)
    end

    local function stopTreeHL()
        treeHLRunning = false
        if treeHeartbeatConn then treeHeartbeatConn:Disconnect(); treeHeartbeatConn=nil end
        clearChildren(treeFolder)

        -- Defensive cleanup on map trees (if any lingering)
        local map = WS:FindFirstChild("Map")
        if map then
            local function clean(folder: Instance?)
                if not folder then return end
                for _,m in ipairs(folder:GetChildren()) do
                    if m:IsA("Model") and m.Name == C.Config.TREE_NAME then
                        removeOurOutline(m)
                    end
                end
            end
            clean(map:FindFirstChild("Foliage"))
            clean(map:FindFirstChild("Landmarks"))
        end
    end

    -----------------------------------------------------
    -- UI
    -----------------------------------------------------
    VisualsTab:Section({ Title = "Visual Options" })

    -- Track Team (other players)
    VisualsTab:Toggle({
        Title = "Track Team (Outline Only)",
        Value = false,
        Callback = function(state)
            trackEnabled = state
            if state then startTrackTeam() else stopTrackTeam() end
        end
    })

    -- Invisible (self only)
    VisualsTab:Toggle({
        Title = "Invisible (Local Only)",
        Value = false,
        Callback = function(state)
            setSelfInvisible(state)
        end
    })

    -- Highlight Trees In Aura (outline only)
    local treeToggle
    treeToggle = VisualsTab:Toggle({
        Title = "Highlight Trees In Aura (Outline Only)",
        Value = false,
        Callback = function(state)
            -- Honor your existing dependency: requires Small Tree Aura to be ON
            if state and not C.State.Toggles.SmallTreeAura then
                warn("[Visuals] Cannot highlight trees — Small Tree Aura is OFF")
                if treeToggle and treeToggle.Set then treeToggle:Set(false) end
                return
            end
            if state then startTreeHL() else stopTreeHL() end
        end
    })

    -- Auto-disable if aura gets turned off elsewhere
    RunService.Heartbeat:Connect(function()
        if treeHLRunning and not C.State.Toggles.SmallTreeAura then
            stopTreeHL()
            if treeToggle and treeToggle.Set then treeToggle:Set(false) end
        end
    end)
end
