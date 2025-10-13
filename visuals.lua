--=====================================================
-- 1337 Nights | Visuals Module (Silhouette-Only Outlines)
--=====================================================
-- What this iteration changes:
--   • Replaces per-part SelectionBox/BoxHandleAdornment with a *dual-Highlight* technique
--     to produce a **single-body silhouette outline** (no internal cut lines).
--   • Uses an opaque fill to eliminate “torso/leg seam” lines entirely.
--   • Brighter outline with a yellow→orange tint for extra pop.
--
-- Notes:
--   • The dual-Highlight stack = (1) OUTLINE-ONLY + (2) OPAQUE-FILL (+ outline).
--     The opaque fill prevents internal part edges from showing through.
--   • DepthMode = AlwaysOnTop ensures the outline stays visible even behind world props.
--   • Trees use the same silhouette approach.
--
-- Project rules (persist for future iterations / continuation files):
--   • Always provide **full, top-to-bottom** code.
--   • Roblox/Lua code must include **helpful comments** throughout.
--=====================================================

return function(C, R, UI)
    -----------------------------------------------------
    -- Services & short-hands
    -----------------------------------------------------
    local Players    = C.Services.Players
    local RunService = C.Services.Run
    local WS         = C.Services.WS
    local LP         = C.LocalPlayer

    local VisualsTab = UI.Tabs.Visuals
    assert(VisualsTab, "Visuals tab missing from UI")

    -----------------------------------------------------
    -- Visual containers (easy mass-clean + GC-friendly)
    -----------------------------------------------------
    local rootFolder      = Instance.new("Folder"); rootFolder.Name = "__Visuals_Root__"; rootFolder.Parent = WS
    local teamFolder      = Instance.new("Folder"); teamFolder.Name = "__Team_Silhouette__"; teamFolder.Parent = rootFolder
    local treeFolder      = Instance.new("Folder"); treeFolder.Name = "__Tree_Silhouette__"; treeFolder.Parent = rootFolder

    -- We no longer create per-part adornments — silhouettes only.
    -- (No teamEdgeFolder / treeEdgeFolder necessary in this version)

    -----------------------------------------------------
    -- Styling (hint of orange added to bright yellow)
    -----------------------------------------------------
    -- Base “pop” color with a small orange push
    local SILH_FILL  = Color3.fromRGB(255, 208, 64)  -- yellow with orange hint
    local SILH_EDGE  = Color3.fromRGB(255, 232, 96)  -- brighter/yellower edge for contrast

    -- Outline/fill transparency:
    --  • FillTransparency = 0   → fully opaque interior (hides internal seams completely)
    --  • OutlineTransparency = 0 → maximum edge visibility
    local FILL_TRANSPARENCY   = 0
    local OUTLINE_TRANSPARENCY= 0

    -----------------------------------------------------
    -- Utilities
    -----------------------------------------------------

    -- Remove all children of a folder (fast reset each tick when needed)
    local function clearChildren(folder: Instance)
        for _,v in ipairs(folder:GetChildren()) do
            v:Destroy()
        end
    end

    -- Destroy any Highlight children on a Model we didn’t create (fresh start)
    local function nukeHighlightsOnModel(model: Model)
        for _,h in ipairs(model:GetChildren()) do
            if h:IsA("Highlight") then
                h:Destroy()
            end
        end
    end

    -- Build a *dual-Highlight* silhouette on a model.
    --   A) outlineHL: outline only (no fill) — punches a strong border
    --   B) fillHL:    solid fill + outline — kills internal seams and boosts brightness
    --
    -- We also store small marker Objects in parentFolder for quick mass cleanup.
    local function applySilhouette(model: Model, parentFolder: Instance)
        if not (model and model:IsA("Model")) then return end

        -- Clean any previous highlights on this model
        nukeHighlightsOnModel(model)

        -- (A) OUTLINE-ONLY highlight (thin “ink” pass)
        local outlineHL = Instance.new("Highlight")
        outlineHL.Name = "SilhouetteOutline"
        outlineHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        outlineHL.FillTransparency = 1                 -- no fill here
        outlineHL.OutlineTransparency = OUTLINE_TRANSPARENCY
        outlineHL.OutlineColor = SILH_EDGE
        outlineHL.Parent = model

        -- (B) OPAQUE FILL highlight (removes internal cut lines)
        local fillHL = Instance.new("Highlight")
        fillHL.Name = "SilhouetteFill"
        fillHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        fillHL.FillTransparency = FILL_TRANSPARENCY    -- solid body
        fillHL.FillColor = SILH_FILL
        fillHL.OutlineTransparency = OUTLINE_TRANSPARENCY
        fillHL.OutlineColor = SILH_EDGE
        fillHL.Parent = model

        -- Tokens to tie these to our folder for easy cleanup
        local t1 = Instance.new("ObjectValue"); t1.Name = "HL_TOKEN"; t1.Value = outlineHL; t1.Parent = parentFolder
        local t2 = Instance.new("ObjectValue"); t2.Name = "HL_TOKEN"; t2.Value = fillHL;    t2.Parent = parentFolder
    end

    -- Remove *our* silhouettes from a model
    local function removeSilhouette(model: Model)
        if not model then return end
        for _,h in ipairs(model:GetChildren()) do
            if h:IsA("Highlight") and (h.Name == "SilhouetteOutline" or h.Name == "SilhouetteFill") then
                h:Destroy()
            end
        end
    end

    -----------------------------------------------------
    -- TRACK TEAM (other players) — silhouettes only
    -----------------------------------------------------
    local trackEnabled = false
    local teamConns: {[any]: RBXScriptConnection} = {}

    local function applyTeamToCharacter(char: Model)
        if not char then return end
        applySilhouette(char, teamFolder)
    end

    local function startTrackTeam()
        -- existing players
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                if teamConns[plr] then teamConns[plr]:Disconnect(); teamConns[plr]=nil end

                -- initial apply if character is already present
                if plr.Character then
                    applyTeamToCharacter(plr.Character)
                end

                -- future spawns
                teamConns[plr] = plr.CharacterAdded:Connect(function(newChar)
                    task.wait(0.25)
                    if trackEnabled then applyTeamToCharacter(newChar) end
                end)
            end
        end

        -- roster changes
        if not teamConns["_PlayerAdded"] then
            teamConns["_PlayerAdded"] = Players.PlayerAdded:Connect(function(plr)
                if plr == LP then return end
                if teamConns[plr] then teamConns[plr]:Disconnect(); teamConns[plr]=nil end
                teamConns[plr] = plr.CharacterAdded:Connect(function(newChar)
                    task.wait(0.25)
                    if trackEnabled then applyTeamToCharacter(newChar) end
                end)
                if plr.Character then
                    task.wait(0.25)
                    if trackEnabled then applyTeamToCharacter(plr.Character) end
                end
            end)
        end

        if not teamConns["_PlayerRemoving"] then
            teamConns["_PlayerRemoving"] = Players.PlayerRemoving:Connect(function(plr)
                if teamConns[plr] then teamConns[plr]:Disconnect(); teamConns[plr]=nil end
                if plr.Character then removeSilhouette(plr.Character) end
            end)
        end
    end

    local function stopTrackTeam()
        -- disconnect all signals
        for k,conn in pairs(teamConns) do
            if typeof(conn) == "RBXScriptConnection" then
                conn:Disconnect()
            end
            teamConns[k] = nil
        end

        -- remove our visuals
        clearChildren(teamFolder)
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Character then
                removeSilhouette(plr.Character)
            end
        end
    end

    -----------------------------------------------------
    -- INVISIBLE (local player only)
    -----------------------------------------------------
    local function setSelfInvisible(state: boolean)
        local char = LP.Character
        if not char then return end
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") then
                -- Local-only transparency; does not affect server
                d.LocalTransparencyModifier = state and 1 or 0
            end
        end
    end

    -----------------------------------------------------
    -- TREE SILHOUETTES (within Aura radius)
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

    local function refreshTreeSilhouettes()
        -- Full refresh each tick (safe & simple; can add caching later if needed)
        clearChildren(treeFolder)

        local trees = collectTreesInAura()
        for _,t in ipairs(trees) do
            applySilhouette(t, treeFolder)
        end
    end

    local function startTreeHL()
        if treeHeartbeatConn then treeHeartbeatConn:Disconnect(); treeHeartbeatConn=nil end
        treeHLRunning = true

        -- Throttle to ~6–7 updates per second (enough responsiveness; avoids work every frame)
        treeHeartbeatConn = RunService.Heartbeat:Connect(function()
            if not treeHLRunning then return end
            local now = os.clock()
            if now - lastTreeTick >= 0.15 then
                lastTreeTick = now
                refreshTreeSilhouettes()
            end
        end)
    end

    local function stopTreeHL()
        treeHLRunning = false
        if treeHeartbeatConn then treeHeartbeatConn:Disconnect(); treeHeartbeatConn=nil end
        clearChildren(treeFolder)

        -- Best-effort removal on existing map trees (cleans any leftover)
        local map = WS:FindFirstChild("Map")
        if map then
            local function clean(folder: Instance?)
                if not folder then return end
                for _,m in ipairs(folder:GetChildren()) do
                    if m:IsA("Model") and m.Name == C.Config.TREE_NAME then
                        removeSilhouette(m)
                    end
                end
            end
            clean(map:FindFirstChild("Foliage"))
            clean(map:FindFirstChild("Landmarks"))
        end
    end

    -----------------------------------------------------
    -- UI Wiring
    -----------------------------------------------------
    VisualsTab:Section({ Title = "Visual Options" })

    -- Track Team (other players)
    VisualsTab:Toggle({
        Title = "Track Team (Silhouette)",
        Value = false,
        Callback = function(state)
            trackEnabled = state
            if state then startTrackTeam() else stopTrackTeam() end
        end
    })

    -- Invisible (self)
    VisualsTab:Toggle({
        Title = "Invisible (Local Only)",
        Value = false,
        Callback = function(state)
            setSelfInvisible(state)
        end
    })

    -- Highlight Trees In Aura
    local treeToggle
    treeToggle = VisualsTab:Toggle({
        Title = "Highlight Trees In Aura (Silhouette)",
        Value = false,
        Callback = function(state)
            -- Honor your existing guard: only when Small Tree Aura is active
            if state and not C.State.Toggles.SmallTreeAura then
                warn("[Visuals] Cannot highlight trees — Small Tree Aura is OFF")
                if treeToggle and treeToggle.Set then treeToggle:Set(false) end
                return
            end
            if state then startTreeHL() else stopTreeHL() end
        end
    })

    -- Auto-disable tree highlighting if aura turns off mid-run
    RunService.Heartbeat:Connect(function()
        if treeHLRunning and not C.State.Toggles.SmallTreeAura then
            stopTreeHL()
            if treeToggle and treeToggle.Set then treeToggle:Set(false) end
        end
    end)
end
