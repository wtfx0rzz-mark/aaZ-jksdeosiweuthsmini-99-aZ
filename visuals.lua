--=====================================================
-- 1337 Nights | Visuals Module 
--=====================================================
-- Visuals tab:
--   • Track Team — bold outline + per-part boxes on other players
--   • Invisible  — local player invisibility (LocalTransparencyModifier)
--   • Highlight Trees In Aura — bold outline + per-part boxes on trees within aura
--=====================================================

return function(C, R, UI)
    -- Services / refs
    local Players     = C.Services.Players
    local RunService  = C.Services.Run
    local WS          = C.Services.WS
    local LP          = C.LocalPlayer
    local VisualsTab  = UI.Tabs.Visuals
    assert(VisualsTab, "Visuals tab missing from UI")

    -- Storage folders for all visuals this module creates
    local rootFolder = Instance.new("Folder"); rootFolder.Name = "__Visuals_Root__"; rootFolder.Parent = WS
    local teamHLFolder = Instance.new("Folder"); teamHLFolder.Name = "__Team_HL__"; teamHLFolder.Parent = rootFolder
    local teamBoxFolder = Instance.new("Folder"); teamBoxFolder.Name = "__Team_Boxes__"; teamBoxFolder.Parent = rootFolder
    local treeHLFolder = Instance.new("Folder"); treeHLFolder.Name = "__Tree_HL__"; treeHLFolder.Parent = rootFolder
    local treeBoxFolder = Instance.new("Folder"); treeBoxFolder.Name = "__Tree_Boxes__"; treeBoxFolder.Parent = rootFolder

    -- Colors / style
    local OUTLINE = Color3.fromRGB(255, 255, 80)   -- bright yellow
    local BOXCLR  = Color3.fromRGB(255, 255, 80)   -- same tone as outline
    local BOXTRANS = 0.25                          -- bold but see-through

    ----------------------------------------------------------------
    -- Utilities
    ----------------------------------------------------------------
    local function clearChildren(folder)
        for _,v in ipairs(folder:GetChildren()) do v:Destroy() end
    end

    -- Create/refresh a Highlight on a Model (outline only, no fill)
    local function ensureHighlightOnModel(model: Model, parentFolder: Instance, color: Color3)
        if not (model and model:IsA("Model")) then return nil end
        -- Remove any existing Highlight under model we don’t control (we’ll recreate clean)
        local existing = model:FindFirstChildOfClass("Highlight")
        if existing then existing:Destroy() end

        local hl = Instance.new("Highlight")
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillTransparency = 1
        hl.OutlineTransparency = 0
        hl.OutlineColor = color or OUTLINE
        hl.FillColor = Color3.new(0,0,0) -- irrelevant; fully transparent fill
        hl.Parent = model

        -- Keep a pointer in our folder so we can mass-clear quickly
        local token = Instance.new("ObjectValue")
        token.Name = "HL_TOKEN"
        token.Value = hl
        token.Parent = parentFolder
        return hl
    end

    -- Create/refresh a BoxHandleAdornment for a BasePart
    local function ensureBoxForPart(part: BasePart, parentFolder: Instance, color: Color3)
        if not (part and part.Parent) then return nil end
        local tag = "HB_" .. part:GetDebugId()
        local adorn = parentFolder:FindFirstChild(tag)
        if not adorn then
            adorn = Instance.new("BoxHandleAdornment")
            adorn.Name = tag
            adorn.ZIndex = 0
            adorn.AlwaysOnTop = true
            adorn.Adornee = part
            adorn.Size = part.Size
            adorn.Color3 = color or BOXCLR
            adorn.Transparency = BOXTRANS
            adorn.Parent = parentFolder
        else
            adorn.Adornee = part
            adorn.Size = part.Size
            adorn.AlwaysOnTop = true
            adorn.Color3 = color or BOXCLR
            adorn.Transparency = BOXTRANS
        end
        adorn.Visible = true
        return adorn
    end

    local function removeVisualsForModel(model: Model, boxFolder: Instance)
        if model then
            local hl = model:FindFirstChildOfClass("Highlight")
            if hl then hl:Destroy() end
            for _,d in ipairs(model:GetDescendants()) do
                if d:IsA("BasePart") then
                    local tag = "HB_" .. d:GetDebugId()
                    local adorn = boxFolder:FindFirstChild(tag)
                    if adorn then adorn:Destroy() end
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Track Team (other players)
    ----------------------------------------------------------------
    local trackEnabled = false
    local teamConns = {} -- per-player CharacterAdded connections

    local function applyTeamVisualsToCharacter(char: Model)
        if not char then return end
        -- Outline on whole model
        ensureHighlightOnModel(char, teamHLFolder, OUTLINE)
        -- Per-part boxes (robust visibility)
        for _,d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") then
                ensureBoxForPart(d, teamBoxFolder, OUTLINE)
            end
        end
    end

    local function startTrackTeam()
        -- existing players
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                if teamConns[plr] then teamConns[plr]:Disconnect(); teamConns[plr]=nil end
                if plr.Character then
                    applyTeamVisualsToCharacter(plr.Character)
                end
                teamConns[plr] = plr.CharacterAdded:Connect(function(newChar)
                    task.wait(0.5)
                    if trackEnabled then applyTeamVisualsToCharacter(newChar) end
                end)
            end
        end
        -- keep up with roster
        if not teamConns["_PlayerAdded"] then
            teamConns["_PlayerAdded"] = Players.PlayerAdded:Connect(function(plr)
                if plr == LP then return end
                if teamConns[plr] then teamConns[plr]:Disconnect(); teamConns[plr]=nil end
                teamConns[plr] = plr.CharacterAdded:Connect(function(newChar)
                    task.wait(0.5)
                    if trackEnabled then applyTeamVisualsToCharacter(newChar) end
                end)
                if plr.Character then
                    task.wait(0.5)
                    if trackEnabled then applyTeamVisualsToCharacter(plr.Character) end
                end
            end)
        end
        if not teamConns["_PlayerRemoving"] then
            teamConns["_PlayerRemoving"] = Players.PlayerRemoving:Connect(function(plr)
                if teamConns[plr] then teamConns[plr]:Disconnect(); teamConns[plr]=nil end
                if plr.Character then removeVisualsForModel(plr.Character, teamBoxFolder) end
            end)
        end
    end

    local function stopTrackTeam()
        -- disconnect signals
        for k,conn in pairs(teamConns) do
            if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
            teamConns[k] = nil
        end
        -- clear visuals
        clearChildren(teamHLFolder)
        clearChildren(teamBoxFolder)
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Character then
                removeVisualsForModel(plr.Character, teamBoxFolder)
            end
        end
    end

    ----------------------------------------------------------------
    -- Invisible (self)
    ----------------------------------------------------------------
    local function setSelfInvisible(state: boolean)
        local char = LP.Character
        if not char then return end
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") then
                d.LocalTransparencyModifier = state and 1 or 0
            end
        end
    end

    ----------------------------------------------------------------
    -- Highlight Trees in Aura
    ----------------------------------------------------------------
    local treeHLRunning = false
    local treeHeartbeatConn

    local function collectTreesInAura()
        local out = {}
        local char = LP.Character
        if not char then return out end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return out end
        local origin = hrp.Position
        local radius = tonumber(C.State.AuraRadius) or 150

        local map = WS:FindFirstChild("Map")
        if not map then return out end

        local function scan(folder)
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

    local function applyTreeVisuals(model: Model)
        if not model then return end
        ensureHighlightOnModel(model, treeHLFolder, OUTLINE)
        for _,d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                ensureBoxForPart(d, treeBoxFolder, OUTLINE)
            end
        end
    end

    local function refreshTreeVisuals()
        clearChildren(treeHLFolder)
        -- do NOT clear boxes first; we’ll update/replace boxes as needed per-part
        -- but for simplicity & correctness, we’ll hard clear boxes per tick:
        clearChildren(treeBoxFolder)

        local trees = collectTreesInAura()
        for _,t in ipairs(trees) do
            applyTreeVisuals(t)
        end
    end

    local function startTreeHL()
        if treeHeartbeatConn then treeHeartbeatConn:Disconnect(); treeHeartbeatConn=nil end
        treeHLRunning = true
        -- Update ~every frame; if heavy, change to stepped throttling
        treeHeartbeatConn = RunService.Heartbeat:Connect(function()
            if not treeHLRunning then return end
            refreshTreeVisuals()
        end)
    end

    local function stopTreeHL()
        treeHLRunning = false
        if treeHeartbeatConn then treeHeartbeatConn:Disconnect(); treeHeartbeatConn=nil end
        clearChildren(treeHLFolder)
        clearChildren(treeBoxFolder)
        -- best-effort remove any highlights lingering on map models
        local map = WS:FindFirstChild("Map")
        if map then
            local function clean(folder)
                if not folder then return end
                for _,m in ipairs(folder:GetChildren()) do
                    if m:IsA("Model") and m.Name == C.Config.TREE_NAME then
                        removeVisualsForModel(m, treeBoxFolder)
                    end
                end
            end
            clean(map:FindFirstChild("Foliage"))
            clean(map:FindFirstChild("Landmarks"))
        end
    end

    ----------------------------------------------------------------
    -- UI
    ----------------------------------------------------------------
    VisualsTab:Section({ Title = "Visual Options" })

    -- Track Team
    VisualsTab:Toggle({
        Title = "Track Team",
        Value = false,
        Callback = function(state)
            trackEnabled = state
            if state then startTrackTeam() else stopTrackTeam() end
        end
    })

    -- Invisible (self)
    VisualsTab:Toggle({
        Title = "Invisible",
        Value = false,
        Callback = function(state)
            setSelfInvisible(state)
        end
    })

    -- Highlight Trees In Aura (requires Small Tree Aura running)
    local treeToggle
    treeToggle = VisualsTab:Toggle({
        Title = "Highlight Trees In Aura",
        Value = false,
        Callback = function(state)
            if state and not C.State.Toggles.SmallTreeAura then
                warn("[Visuals] Cannot highlight trees — Small Tree Aura is OFF")
                if treeToggle and treeToggle.Set then treeToggle:Set(false) end
                return
            end
            if state then startTreeHL() else stopTreeHL() end
        end
    })

    -- Auto-disable tree highlighting if aura turns off
    RunService.Heartbeat:Connect(function()
        if treeHLRunning and not C.State.Toggles.SmallTreeAura then
            stopTreeHL()
            if treeToggle and treeToggle.Set then treeToggle:Set(false) end
        end
    end)
end
