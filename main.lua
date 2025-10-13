--=====================================================
-- 1337 Nights | main.lua (Main Tab)
--=====================================================
-- IMPORTANT NOTES (persist across iterations & carryover files)
--   • This file is designed for Roblox **LocalScript** (client-side, Luau).
--   • Integration w/ GPT workflow:
--       - Always deliver **full, top-to-bottom code** (no diffs/patches).
--       - Roblox/Lua scripts must include **helpful comments** throughout.
--       - When generating continuation context files, include:
--           · Current module baselines & toggles
--           · Active color/outline/aura rules relevant to features
--           · These IMPORTANT NOTES (so the next session is seamless)
--   • Performance & behavior:
--       - Aura loops are throttled via swing delays to avoid RPC spam.
--       - Target scans respect a shared **Aura Radius** slider (C.State.AuraRadius).
--       - Tree and NPC auras run as **independent** loops that read the same radius.
--   • Tooling & damage flow (mirrors your existing tree logic):
--       1) Equip tool via:
--            ReplicatedStorage.RemoteEvents.EquipItemHandle:FireServer("FireAllClients", toolInstance)
--       2) Apply hit via:
--            ReplicatedStorage.RemoteEvents.ToolDamageObject:InvokeServer(targetModel, toolInstance, damageIdString, impactCFrame)
--=====================================================

return function(C, R, UI)
    -----------------------------------------------------
    -- Services / Context
    -----------------------------------------------------
    local Players = C.Services.Players
    local RS      = C.Services.RS
    local WS      = C.Services.WS
    local Run     = C.Services.Run
    local LP      = C.LocalPlayer

    local MainTab = UI.Tabs.Main
    assert(MainTab, "main.lua: Main tab missing")

    -----------------------------------------------------
    -- Config / Tunables (prefer C.Config, fall back otherwise)
    -----------------------------------------------------
    -- Tree identity used elsewhere in your project
    local TREE_NAME             = C.Config.TREE_NAME or "Small Tree"

    -- Cadence (kept aligned with your baseline)
    local AURA_SWING_DELAY      = C.Config.AURA_SWING_DELAY or 0.55
    local CHOP_SWING_DELAY      = C.Config.CHOP_SWING_DELAY or 0.55

    -- Tool used for both tree and NPC auras unless you override
    local TOOL_NAME             = C.Config.AXE_NAME or "Old Axe"

    -- Shared radius (both auras read the same control)
    local function getAuraRadius()
        return tonumber(C.State.AuraRadius) or 150
    end

    -----------------------------------------------------
    -- Remotes (mirror baseline)
    -----------------------------------------------------
    local RemoteEvents      = RS:WaitForChild("RemoteEvents")
    local EquipItemHandle   = RemoteEvents:WaitForChild("EquipItemHandle")
    local ToolDamageObject  = RemoteEvents:WaitForChild("ToolDamageObject")

    -----------------------------------------------------
    -- Helpers (generic & reusable)
    -----------------------------------------------------

    -- Get LocalPlayer’s HRP, waiting on first run if needed
    local function getHRP()
        local ch = LP.Character or LP.CharacterAdded:Wait()
        return ch:WaitForChild("HumanoidRootPart")
    end

    -- Find a tool by name under LocalPlayer.Inventory
    local function findTool(name: string)
        local inv = LP:FindFirstChild("Inventory")
        if not inv then return nil end
        return inv:FindFirstChild(name)
    end

    -- Ensure a tool is server-equipped before invoking damage
    local function ensureEquipped(toolInstance: Instance)
        if not toolInstance then return false end
        -- Mirrors your working tree flow
        EquipItemHandle:FireServer("FireAllClients", toolInstance)
        return true
    end

    -- Stable damage id string (same as tree flow)
    local function makeDamageId()
        return "1_0000000000"
    end

    -- Compute a reasonable impact CFrame for either a tree or NPC model
    local function computeImpactCFrameFor(model: Model): CFrame
        -- Prefer PrimaryPart if set
        if model.PrimaryPart then
            return model.PrimaryPart.CFrame
        end
        -- NPCs usually have HRP
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then
            return hrp.CFrame
        end
        -- Trees may have "Trunk"
        local trunk = model:FindFirstChild("Trunk")
        if trunk and trunk:IsA("BasePart") then
            return trunk.CFrame
        end
        -- Fallback: first BasePart we can find
        for _,d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                return d.CFrame
            end
        end
        -- Last resort: player location (keeps call valid)
        return getHRP().CFrame
    end

    -- Quick radius check using model pivot (robust across model types)
    local function withinRadius(model: Model, origin: Vector3, r: number): boolean
        local pos = model:GetPivot().Position
        return (pos - origin).Magnitude <= r
    end

    -----------------------------------------------------
    -- TREE CHOP (existing behavior retained)
    -----------------------------------------------------
    local lastHitAt_Tree: {[Instance]: number} = {}  -- per-target throttling

    local function chopTree(treeModel: Model)
        if not treeModel then return end

        -- Per-target throttle
        local now = os.clock()
        local last = lastHitAt_Tree[treeModel] or 0
        if (now - last) < CHOP_SWING_DELAY then
            return
        end

        -- Equip tool
        local tool = findTool(TOOL_NAME)
        if not ensureEquipped(tool) then return end

        -- Build/Invoke
        local dmgId  = makeDamageId()
        local impact = computeImpactCFrameFor(treeModel)
        ToolDamageObject:InvokeServer(treeModel, tool, dmgId, impact)

        lastHitAt_Tree[treeModel] = now
    end

    -----------------------------------------------------
    -- NPC CHOP (NEW — mirrors tree logic 1:1, target = NPC)
    -----------------------------------------------------
    local lastHitAt_NPC: {[Instance]: number} = {}

    local function npcChop(npcModel: Model)
        if not npcModel then return end

        -- Per-target throttle
        local now = os.clock()
        local last = lastHitAt_NPC[npcModel] or 0
        if (now - last) < CHOP_SWING_DELAY then
            return
        end

        -- Equip tool (same tool as trees unless replaced)
        local tool = findTool(TOOL_NAME)
        if not ensureEquipped(tool) then return end

        -- Build/Invoke (same remote/signature as trees)
        local dmgId  = makeDamageId()
        local impact = computeImpactCFrameFor(npcModel)
        ToolDamageObject:InvokeServer(npcModel, tool, dmgId, impact)

        lastHitAt_NPC[npcModel] = now
    end

    -----------------------------------------------------
    -- SCANNERS (discover targets within shared Aura radius)
    -----------------------------------------------------

    -- Trees: find exact-name matches of TREE_NAME under Map.{Foliage,Landmarks}
    local function collectTreesInAura(): {Model}
        local out = {}

        local ch  = LP.Character; if not ch  then return out end
        local hrp = ch:FindFirstChild("HumanoidRootPart"); if not hrp then return out end

        local origin = hrp.Position
        local radius = getAuraRadius()

        local map = WS:FindFirstChild("Map"); if not map then return out end

        local function scan(folder: Instance?)
            if not folder then return end
            for _,m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") and m.Name == TREE_NAME then
                    if withinRadius(m, origin, radius) then
                        table.insert(out, m)
                    end
                end
            end
        end

        scan(map:FindFirstChild("Foliage"))
        scan(map:FindFirstChild("Landmarks"))
        return out
    end

    -- NPCs: under Workspace → Characters (exclude names containing "horse")
    local function collectNPCsInAura(): {Model}
        local out = {}

        local ch  = LP.Character; if not ch  then return out end
        local hrp = ch:FindFirstChild("HumanoidRootPart"); if not hrp then return out end

        local origin = hrp.Position
        local radius = getAuraRadius()

        local characters = WS:FindFirstChild("Characters")
        if not characters then return out end

        for _,m in ipairs(characters:GetChildren()) do
            repeat
                if not m:IsA("Model") then break end
                -- Exclude anything with "horse" (case-insensitive)
                if string.find(string.lower(m.Name), "horse", 1, true) then break end

                -- Optional “alive” validation if NPCs have Humanoids
                local hum = m:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health <= 0 then break end

                if not withinRadius(m, origin, radius) then break end
                table.insert(out, m)
            until true
        end

        return out
    end

    -----------------------------------------------------
    -- AURA LOOPS (independent toggles, shared radius)
    -----------------------------------------------------
    local smallTreeAura_On = false
    local npcAura_On       = false

    local auraConn_Tree: RBXScriptConnection? = nil
    local auraConn_NPC:  RBXScriptConnection? = nil

    -- Small Tree Aura runner (unchanged)
    local function startSmallTreeAura()
        if auraConn_Tree then auraConn_Tree:Disconnect(); auraConn_Tree = nil end
        smallTreeAura_On = true

        local lastTick = 0
        auraConn_Tree = Run.Heartbeat:Connect(function()
            if not smallTreeAura_On then return end
            local now = os.clock()
            if (now - lastTick) < AURA_SWING_DELAY then return end
            lastTick = now

            for _,t in ipairs(collectTreesInAura()) do
                chopTree(t)
            end
        end)
    end

    local function stopSmallTreeAura()
        smallTreeAura_On = false
        if auraConn_Tree then auraConn_Tree:Disconnect(); auraConn_Tree = nil end
    end

    -- NEW: NPC Aura runner (mirrors tree aura behavior)
    local function startNPCAura()
        if auraConn_NPC then auraConn_NPC:Disconnect(); auraConn_NPC = nil end
        npcAura_On = true

        local lastTick = 0
        auraConn_NPC = Run.Heartbeat:Connect(function()
            if not npcAura_On then return end
            local now = os.clock()
            if (now - lastTick) < AURA_SWING_DELAY then return end
            lastTick = now

            for _,n in ipairs(collectNPCsInAura()) do
                npcChop(n)
            end
        end)
    end

    local function stopNPCAura()
        npcAura_On = false
        if auraConn_NPC then auraConn_NPC:Disconnect(); auraConn_NPC = nil end
    end

    -----------------------------------------------------
    -- UI (NPC Aura placed directly below Small Tree Aura)
    -----------------------------------------------------
    MainTab:Section({ Title = "Aura" })

    MainTab:Toggle({
        Title   = "Small Tree Aura",
        Value   = false,
        Callback= function(state)
            if state then startSmallTreeAura() else stopSmallTreeAura() end
        end
    })

    MainTab:Toggle({
        Title   = "NPC Aura",
        Value   = false,
        Callback= function(state)
            if state then startNPCAura() else stopNPCAura() end
        end
    })

    -----------------------------------------------------
    -- Optional: stop loops on character reset (re-enable if desired)
    -----------------------------------------------------
    LP.CharacterAdded:Connect(function()
        -- Remove these if you want auras to persist across deaths/respawns
        if smallTreeAura_On then stopSmallTreeAura() end
        if npcAura_On then stopNPCAura() end
    end)
end
