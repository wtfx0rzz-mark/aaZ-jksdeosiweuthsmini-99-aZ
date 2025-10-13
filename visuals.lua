-- 1337 Nights | Visuals Module (Edge-Only Outlines)

return function(C, R, UI)
    local Players    = C.Services.Players
    local RunService = C.Services.Run
    local WS         = C.Services.WS
    local LP         = C.LocalPlayer
    local VisualsTab = UI.Tabs.Visuals
    assert(VisualsTab, "Visuals tab missing")

    local rootFolder      = Instance.new("Folder"); rootFolder.Name = "__Visuals_Root__"; rootFolder.Parent = WS
    local teamHLFolder    = Instance.new("Folder"); teamHLFolder.Name = "__Team_HL__"; teamHLFolder.Parent = rootFolder
    local teamEdgeFolder  = Instance.new("Folder"); teamEdgeFolder.Name = "__Team_Edges__"; teamEdgeFolder.Parent = rootFolder
    local treeHLFolder    = Instance.new("Folder"); treeHLFolder.Name = "__Tree_HL__"; treeHLFolder.Parent = rootFolder
    local treeEdgeFolder  = Instance.new("Folder"); treeEdgeFolder.Name = "__Tree_Edges__"; treeEdgeFolder.Parent = rootFolder

    local EDGE_COLOR      = Color3.fromRGB(255, 255, 80)
    local OUTLINE_COLOR   = EDGE_COLOR
    local EDGE_THICKNESS  = 0.08

    local function clearChildren(folder)
        for _,v in ipairs(folder:GetChildren()) do v:Destroy() end
    end

    local function ensureHighlight(model: Model, parentFolder: Instance, color: Color3)
        if not (model and model:IsA("Model")) then return nil end
        local existing = model:FindFirstChildOfClass("Highlight")
        if existing then existing:Destroy() end
        local hl = Instance.new("Highlight")
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillTransparency = 1
        hl.OutlineTransparency = 0
        hl.OutlineColor = color or OUTLINE_COLOR
        hl.Parent = model
        local token = Instance.new("ObjectValue")
        token.Name = "HL_TOKEN"
        token.Value = hl
        token.Parent = parentFolder
        return hl
    end

    local function ensureEdgeForPart(part: BasePart, parentFolder: Instance, color: Color3, thickness: number)
        if not (part and part.Parent) then return nil end
        local tag = "EDGE_" .. part:GetDebugId()
        local sb = parentFolder:FindFirstChild(tag)
        if not sb then
            sb = Instance.new("SelectionBox")
            sb.Name = tag
            sb.Adornee = part
            sb.LineThickness = thickness or EDGE_THICKNESS
            sb.Color3 = color or EDGE_COLOR
            sb.SurfaceTransparency = 1
            sb.Parent = parentFolder
        else
            sb.Adornee = part
            sb.LineThickness = thickness or EDGE_THICKNESS
            sb.Color3 = color or EDGE_COLOR
            sb.SurfaceTransparency = 1
        end
        sb.Visible = true
        return sb
    end

    local function removeVisualsForModel(model: Model, edgeFolder: Instance)
        if model then
            local hl = model:FindFirstChildOfClass("Highlight")
            if hl then hl:Destroy() end
            for _,d in ipairs(model:GetDescendants()) do
                if d:IsA("BasePart") then
                    local tag = "EDGE_" .. d:GetDebugId()
                    local sb = edgeFolder:FindFirstChild(tag)
                    if sb then sb:Destroy() end
                end
            end
        end
    end

    local trackEnabled = false
    local teamConns = {}

    local function applyTeamVisualsToCharacter(char: Model)
        if not char then return end
        ensureHighlight(char, teamHLFolder, OUTLINE_COLOR)
        for _,d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") then
                ensureEdgeForPart(d, teamEdgeFolder, EDGE_COLOR, EDGE_THICKNESS)
            end
        end
    end

    local function startTrackTeam()
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                if teamConns[plr] then teamConns[plr]:Disconnect(); teamConns[plr]=nil end
                if plr.Character then
                    applyTeamVisualsToCharacter(plr.Character)
                end
                teamConns[plr] = plr.CharacterAdded:Connect(function(newChar)
                    task.wait(0.4)
                    if trackEnabled then applyTeamVisualsToCharacter(newChar) end
                end)
            end
        end
        if not teamConns["_PlayerAdded"] then
            teamConns["_PlayerAdded"] = Players.PlayerAdded:Connect(function(plr)
                if plr == LP then return end
                if teamConns[plr] then teamConns[plr]:Disconnect(); teamConns[plr]=nil end
                teamConns[plr] = plr.CharacterAdded:Connect(function(newChar)
                    task.wait(0.4)
                    if trackEnabled then applyTeamVisualsToCharacter(newChar) end
                end)
                if plr.Character then
                    task.wait(0.4)
                    if trackEnabled then applyTeamVisualsToCharacter(plr.Character) end
                end
            end)
        end
        if not teamConns["_PlayerRemoving"] then
            teamConns["_PlayerRemoving"] = Players.PlayerRemoving:Connect(function(plr)
                if teamConns[plr] then teamConns[plr]:Disconnect(); teamConns[plr]=nil end
                if plr.Character then removeVisualsForModel(plr.Character, teamEdgeFolder) end
            end)
        end
    end

    local function stopTrackTeam()
        for k,conn in pairs(teamConns) do
            if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
            teamConns[k] = nil
        end
        clearChildren(teamHLFolder)
        clearChildren(teamEdgeFolder)
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Character then
                removeVisualsForModel(plr.Character, teamEdgeFolder)
            end
        end
    end

    local function setSelfInvisible(state: boolean)
        local char = LP.Character
        if not char then return end
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") then
                d.LocalTransparencyModifier = state and 1 or 0
            end
        end
    end

    local treeHLRunning = false
    local treeHeartbeatConn
    local lastTreeTick = 0

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
        ensureHighlight(model, treeHLFolder, OUTLINE_COLOR)
        for _,d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                ensureEdgeForPart(d, treeEdgeFolder, EDGE_COLOR, EDGE_THICKNESS)
            end
        end
    end

    local function refreshTreeVisuals()
        clearChildren(treeHLFolder)
        clearChildren(treeEdgeFolder)
        local trees = collectTreesInAura()
        for _,t in ipairs(trees) do
            applyTreeVisuals(t)
        end
    end

    local function startTreeHL()
        if treeHeartbeatConn then treeHeartbeatConn:Disconnect(); treeHeartbeatConn=nil end
        treeHLRunning = true
        treeHeartbeatConn = RunService.Heartbeat:Connect(function()
            if not treeHLRunning then return end
            local now = os.clock()
            if now - lastTreeTick >= 0.15 then
                lastTreeTick = now
                refreshTreeVisuals()
            end
        end)
    end

    local function stopTreeHL()
        treeHLRunning = false
        if treeHeartbeatConn then treeHeartbeatConn:Disconnect(); treeHeartbeatConn=nil end
        clearChildren(treeHLFolder)
        clearChildren(treeEdgeFolder)
        local map = WS:FindFirstChild("Map")
        if map then
            local function clean(folder)
                if not folder then return end
                for _,m in ipairs(folder:GetChildren()) do
                    if m:IsA("Model") and m.Name == C.Config.TREE_NAME then
                        removeVisualsForModel(m, treeEdgeFolder)
                    end
                end
            end
            clean(map:FindFirstChild("Foliage"))
            clean(map:FindFirstChild("Landmarks"))
        end
    end

    VisualsTab:Section({ Title = "Visual Options" })

    VisualsTab:Toggle({
        Title = "Track Team",
        Value = false,
        Callback = function(state)
            trackEnabled = state
            if state then startTrackTeam() else stopTrackTeam() end
        end
    })

    VisualsTab:Toggle({
        Title = "Invisible",
        Value = false,
        Callback = function(state)
            setSelfInvisible(state)
        end
    })

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

    RunService.Heartbeat:Connect(function()
        if treeHLRunning and not C.State.Toggles.SmallTreeAura then
            stopTreeHL()
            if treeToggle and treeToggle.Set then treeToggle:Set(false) end
        end
    end)
end
