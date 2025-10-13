--=====================================================
-- 1337 Nights | Visuals Module (Outline-Only, Bolder/Darker Edge)
--=====================================================
-- Goals
--   • Single, clean OUTLINE around whole player models and tree models (no internal seams).
--   • Player/Tree surfaces remain fully visible (no silhouette fill).
--   • Edge looks darker and a bit “bolder”.
--
-- How we achieve the look
--   • We use *only* Roblox Highlight objects (NO SelectionBox/BoxHandleAdornment).
--   • FillTransparency = 1 (no fill) so the normal colors are fully visible.
--   • To make the outline appear “bolder”, we stack TWO Highlights per model:
--       - Base HL (Occluded)   → helps darken the edge where it intersects world geometry.
--       - Top  HL (AlwaysOnTop)→ guarantees a strong visible outline in front.
--     While Roblox doesn’t expose a true “line thickness” for Highlight, this layering
--     increases perceived edge weight/contrast without causing per-part seam lines.
--
-- Requested color
--   • Use a *single* outline color = (255, 255, 100) for both players and trees.
--
-- UI
--   • Visuals → Track Team (outlines other players only; excludes local player)
--   • Visuals → Invisible (local-only transparency via LocalTransparencyModifier)
--   • Visuals → Highlight Trees In Aura (outlines “Small Tree” models within aura radius)
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
    -- Requested outline color (players & trees)
    local OUTLINE_COLOR = Color3.fromRGB(255, 255, 100)

    -- No fill at all (so body/tree colors are fully visible)
    local FILL_TRANSPARENCY     = 1
    local OUTLINE_TRANSPARENCY  = 0

    -- When true, we place TWO Highlights on each model:
    --   1) Occluded (behind geometry) to deepen/darken intersections
    --   2) AlwaysOnTop to ensure a strong edge in front
    -- This increases perceived boldness without adding per-part seams.
    local USE_DOUBLE_EDGE = true

    -----------------------------------------------------
    -- Utilities
    -----------------------------------------------------

    -- Remove all children (used to clear our folders)
    local function clearChildren(folder: Instance)
        for _,v in ipairs(folder:GetChildren()) do
            v:Destroy()
        end
    end

    -- Remove only our Highlights on a model (identified by Name prefix)
    local function removeOurOutlines(model: Model)
        if not model then return end
        for _,h in ipairs(model:GetChildren()) do
            if h:IsA("Highlight") and (h.Name == "ModelOutline_TOP" or h.Name == "ModelOutline_OCC") then
                h:Destroy()
            end
        end
    end

    -- Ensure one or two Highlights (based on USE_DOUBLE_EDGE) on the supplied model.
    --   • Both are outline-only (FillTransparency=1).
    --   • Same color for consistency (dark/strong look).
    --   • Different DepthMode pairing to enhance perceived boldness:
    --        - Occluded first, then AlwaysOnTop.
    local function ensureModelOutline(model: Model, parentFolder: Instance)
        if not (model and model:IsA("Model")) then return end

        -- Clean any prior outline we created to avoid duplicates
        removeOurOutlines(model)

        -- (A) Occluded layer (deepens/darkens edge behind geometry)
        if USE_DOUBLE_EDGE then
            local occ = Instance.new("Highlight")
            occ.Name = "ModelOutline_OCC"
            occ.DepthMode = Enum.HighlightDepthMode.Occluded
            occ.FillTransparency = FILL_TRANSPARENCY     -- no fill (fully see-through body)
            occ.OutlineTransparency = OUTLINE_TRANSPARENCY
            occ.OutlineColor = OUTLINE_COLOR
            occ.Parent = model
            local tO = Instance.new("ObjectValue"); tO.Name = "HL_TOKEN"; tO.Value = occ; tO.Parent = parentFolder
        end

        -- (B) Always-on-top layer (frontmost clean edge)
        local top = Instance.new("Highlight")
        top.Name = "ModelOutline_TOP"
        top.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        top.FillTransparency = FILL_TRANSPARENCY         -- no fill (fully see-through body)
        top.OutlineTransparency = OUTLINE_TRANSPARENCY
        top.OutlineColor = OUTLINE_COLOR
        top.Parent = model
        local tT = Instance.new("ObjectValue"); tT.Name = "HL_TOKEN"; tT.Value = top; tT.Parent = parentFolder
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
                if plr.Character then removeOurOutlines(plr.Character) end
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
                removeOurOutlines(plr.Character)
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

        -- Read shared aura radius (falls back to 150 if not set)
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
                        removeOurOutlines(m)
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
        Title = "Track Team (Outline Only, Darker/Bolder)",
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
