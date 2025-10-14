--=====================================================
-- 1337 Nights | Combat Module
--=====================================================
-- Adds to Combat tab:
--   • Character Aura (NPCs under Workspace.Characters, excludes *horse*)
--   • Small Tree Aura (targets "Small Tree" and "Snowy Small Tree")
--   • Shared Aura Distance slider
--   • Common damage pipeline (priority equip → impact CFrame → InvokeServer)
--   • Writes per-hit attributes on trees: "N_<UID_SUFFIX>" (e.g., 1_0000000000)
--=====================================================
--[[====================================================================
 🧠 GPT INTEGRATION NOTE
 ----------------------------------------------------------------------
 Runs inside the unified 1337 Nights runtime:

     _G.C  → Global Config, State, Services, Shared tables
     _G.R  → Shared runtime helpers
     _G.UI → WindUI instance (window + tabs)

 • Do not return C/R/UI; main.lua owns setup and loading.
 • Each aura runs in its own thread; no cyclic requires.
 • Both auras honor the same distance: C.State.AuraRadius
 • NPCs whose name contains "horse" (case-insensitive) are excluded.
====================================================================]]

return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Combat, "combat.lua: missing context or Combat tab")

    local RS = C.Services.RS
    local WS = C.Services.WS
    local lp = C.LocalPlayer
    local CombatTab = UI.Tabs.Combat

    C.State  = C.State or { AuraRadius = 150, Toggles = {} }
    C.Config = C.Config or {
        CHOP_SWING_DELAY = 0.55,
        TREE_NAME        = "Small Tree",
        UID_SUFFIX       = "0000000000",
        ChopPrefer       = { "Chainsaw", "Strong Axe", "Good Axe", "Old Axe" },
    }

    local running = { SmallTree = false, Character = false }

    --------------------------------------------------------------------
    -- Hit counter + initialization from existing attributes
    --------------------------------------------------------------------
    local _hitCounter = 0
    local _counterPrimed = false
    local TREE_NAMES = { ["Small Tree"]=true, ["Snowy Small Tree"]=true }

    local function parseHitAttr(attrName)
        local pat = "^(%d+)_" .. C.Config.UID_SUFFIX .. "$"
        local n = string.match(attrName, pat)
        return n and tonumber(n) or nil
    end

    local function primeCounterFromWorld()
        if _counterPrimed then return end
        _counterPrimed = true
        local maxSeen = 0

        local function scanModel(m)
            if not (m and m:IsA("Model") and TREE_NAMES[m.Name]) then return end
            local attrs = m:GetAttributes()
            for k, _ in pairs(attrs) do
                local n = parseHitAttr(k)
                if n and n > maxSeen then maxSeen = n end
            end
        end

        local function walk(node)
            if not node then return end
            if node:IsA("Model") then scanModel(node) end
            local ok, children = pcall(node.GetChildren, node)
            if not ok then return end
            for _, ch in ipairs(children) do walk(ch) end
        end

        -- Check common roots (Workspace + some ReplicatedStorage paths where trees appear)
        walk(WS)
        local assets = RS:FindFirstChild("Assets")
        if assets then walk(assets) end
        local cuts = RS:FindFirstChild("CutsceneSets")
        if cuts then walk(cuts) end

        _hitCounter = math.max(_hitCounter, maxSeen)
    end

    local function nextHitId()
        _hitCounter += 1
        return tostring(_hitCounter) .. "_" .. C.Config.UID_SUFFIX
    end

    --------------------------------------------------------------------
    -- Inventory, equip, hit part helpers
    --------------------------------------------------------------------
    local function findInInventory(name)
        local inv = lp and lp:FindFirstChild("Inventory")
        return inv and inv:FindFirstChild(name) or nil
    end

    local function equippedToolName()
        local ch = lp and lp.Character
        if not ch then return nil end
        local t = ch:FindFirstChildOfClass("Tool")
        return t and t.Name or nil
    end

    local function SafeEquip(tool)
        if not tool then return end
        local ev = RS:FindFirstChild("RemoteEvents")
        ev = ev and ev:FindFirstChild("EquipItemHandle")
        if ev then ev:FireServer("FireAllClients", tool) end
    end

    local function ensureEquipped(wantedName)
        if not wantedName then return nil end
        if equippedToolName() == wantedName then
            return findInInventory(wantedName)
        end
        local tool = findInInventory(wantedName)
        if tool then SafeEquip(tool) end
        return tool
    end

    local function bestTreeHitPart(tree)
        if not tree or not tree:IsA("Model") then return nil end
        local hr = tree:FindFirstChild("HitRegisters")
        if hr then
            local t = hr:FindFirstChild("Trunk")
            if t and t:IsA("BasePart") then return t end
            local any = hr:FindFirstChildWhichIsA("BasePart")
            if any then return any end
        end
        local t2 = tree:FindFirstChild("Trunk")
        if t2 and t2:IsA("BasePart") then return t2 end
        return tree.PrimaryPart or tree:FindFirstChildWhichIsA("BasePart")
    end

    local function bestCharacterHitPart(model)
        if not model or not model:IsA("Model") then return nil end
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then return hrp end
        if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
        return model:FindFirstChildWhichIsA("BasePart")
    end

    local function computeImpactCFrame(model, hitPart)
        if not (model and hitPart and hitPart:IsA("BasePart")) then
            return hitPart and CFrame.new(hitPart.Position) or CFrame.new()
        end
        local outward = hitPart.CFrame.LookVector
        if outward.Magnitude == 0 then outward = Vector3.new(0,0,-1) end
        outward = outward.Unit
        local origin  = hitPart.Position + outward * 1.0
        local dir     = -outward * 5.0
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances = {model}
        local rc = WS:Raycast(origin, dir, params)
        local pos = rc and (rc.Position + rc.Normal*0.02) or (origin + dir*0.6)
        local rot = hitPart.CFrame - hitPart.CFrame.Position
        return CFrame.new(pos) * rot
    end

    local function HitTarget(targetModel, tool, hitId, impactCF)
        local evs = RS:FindFirstChild("RemoteEvents")
        local dmg = evs and evs:FindFirstChild("ToolDamageObject")
        if not dmg then return end
        dmg:InvokeServer(targetModel, tool, hitId, impactCF)
    end

    --------------------------------------------------------------------
    -- Collectors (trees recursive, characters flat) + deterministic order
    --------------------------------------------------------------------
    local function collectTreesInRadius(roots, origin, radius, maxCount)
        local out, n = {}, 0
        local function walk(node)
            if n >= maxCount then return end
            if not node then return end
            if node:IsA("Model") and TREE_NAMES[node.Name] then
                local trunk = bestTreeHitPart(node)
                if trunk then
                    local d = (trunk.Position - origin).Magnitude
                    if d <= radius then
                        n += 1
                        out[n] = node
                        if n >= maxCount then return end
                    end
                end
            end
            local ok, children = pcall(node.GetChildren, node)
            if ok and children then
                for _, ch in ipairs(children) do
                    if n >= maxCount then break end
                    walk(ch)
                end
            end
        end
        for _, root in ipairs(roots) do
            if n >= maxCount then break end
            walk(root)
        end
        -- stable deterministic ordering: nearest first, then by name
        table.sort(out, function(a, b)
            local pa, pb = bestTreeHitPart(a), bestTreeHitPart(b)
            local da = pa and (pa.Position - origin).Magnitude or math.huge
            local db = pb and (pb.Position - origin).Magnitude or math.huge
            if da == db then return (a.Name or "") < (b.Name or "") end
            return da < db
        end)
        return out
    end

    local function collectCharactersInRadius(charsFolder, origin, radius)
        local out = {}
        if not charsFolder then return out end
        for _, mdl in ipairs(charsFolder:GetChildren()) do
            repeat
                if not mdl:IsA("Model") then break end
                local nameLower = string.lower(mdl.Name or "")
                if string.find(nameLower, "horse", 1, true) then break end
                local hit = bestCharacterHitPart(mdl)
                if not hit then break end
                if (hit.Position - origin).Magnitude > radius then break end
                out[#out+1] = mdl
            until true
        end
        table.sort(out, function(a, b)
            local pa, pb = bestCharacterHitPart(a), bestCharacterHitPart(b)
            local da = pa and (pa.Position - origin).Magnitude or math.huge
            local db = pb and (pb.Position - origin).Magnitude or math.huge
            if da == db then return (a.Name or "") < (b.Name or "") end
            return da < db
        end)
        return out
    end

    --------------------------------------------------------------------
    -- Wave executor (now also tags hit attributes on trees)
    --------------------------------------------------------------------
    local function chopWave(targetModels, swingDelay, hitPartGetter, tagAttributesOnModels)
        local toolName
        for _, n in ipairs(C.Config.ChopPrefer) do
            if findInInventory(n) then toolName = n break end
        end
        if not toolName then task.wait(0.35) return end
        local tool = ensureEquipped(toolName)
        if not tool then task.wait(0.35) return end

        for _, mdl in ipairs(targetModels) do
            task.spawn(function()
                local hitPart = hitPartGetter(mdl)
                if hitPart then
                    local impactCF = computeImpactCFrame(mdl, hitPart)

                    -- Assign ordered ID and (optionally) write attribute to the model
                    local hitId = nextHitId()
                    if tagAttributesOnModels then
                        -- Store as boolean true for visibility; key encodes the order.
                        pcall(function()
                            mdl:SetAttribute(hitId, true)
                        end)
                    end

                    HitTarget(mdl, tool, hitId, impactCF)
                end
            end)
        end

        task.wait(swingDelay)
    end

    --------------------------------------------------------------------
    -- Auras
    --------------------------------------------------------------------
    -- Character Aura
    local function startCharacterAura()
        if running.Character then return end
        running.Character = true
        task.spawn(function()
            while running.Character do
                local ch = lp.Character or lp.CharacterAdded:Wait()
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if not hrp then task.wait(0.2) break end

                local origin = hrp.Position
                local radius = tonumber(C.State.AuraRadius) or 150
                local targets = collectCharactersInRadius(WS:FindFirstChild("Characters"), origin, radius)

                if #targets > 0 then
                    -- Characters: no attribute tagging needed
                    chopWave(targets, C.Config.CHOP_SWING_DELAY, bestCharacterHitPart, false)
                else
                    task.wait(0.3)
                end
            end
        end)
    end
    local function stopCharacterAura() running.Character = false end

    -- Small Tree Aura (includes Snowy Small Tree)
    local function startSmallTreeAura()
        if running.SmallTree then return end
        running.SmallTree = true
        task.spawn(function()
            primeCounterFromWorld() -- make numbering continue if attributes already exist

            while running.SmallTree do
                local ch = lp.Character or lp.CharacterAdded:Wait()
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if not hrp then task.wait(0.2) break end

                local origin = hrp.Position
                local radius = tonumber(C.State.AuraRadius) or 150

                local roots = {
                    WS,                                     -- covers Map, Foliage, Landmarks, FakeForest, etc.
                    RS:FindFirstChild("Assets"),            -- ReplicatedStorage.Assets (CutsceneSets.*.Decor.*)
                    RS:FindFirstChild("CutsceneSets"),      -- fallback if Assets nests differently
                }

                local trees = collectTreesInRadius(roots, origin, radius, 64)
                if #trees > 0 then
                    -- Trees: tag attributes on the *model* to reflect the hit order
                    chopWave(trees, C.Config.CHOP_SWING_DELAY, bestTreeHitPart, true)
                else
                    task.wait(0.3)
                end
            end
        end)
    end
    local function stopSmallTreeAura() running.SmallTree = false end

    --------------------------------------------------------------------
    -- UI (Character first, then Small Tree; shared slider)
    --------------------------------------------------------------------
    CombatTab:Toggle({
        Title = "Character Aura",
        Value = C.State.Toggles.CharacterAura or false,
        Callback = function(on)
            C.State.Toggles.CharacterAura = on
            if on then startCharacterAura() else stopCharacterAura() end
        end
    })

    CombatTab:Toggle({
        Title = "Small Tree Aura",
        Value = C.State.Toggles.SmallTreeAura or false,
        Callback = function(on)
            C.State.Toggles.SmallTreeAura = on
            if on then startSmallTreeAura() else stopSmallTreeAura() end
        end
    })

    -- Saving this as an example for later just incase: CombatTab:Section({ Title = "Aura Distance" })
    CombatTab:Slider({
        Title = "Distance",
        Value = { Min = 0, Max = 1000, Default = C.State.AuraRadius or 150 },
        Callback = function(v)
            C.State.AuraRadius = math.clamp(tonumber(v) or 150, 0, 1000)
        end
    })
end
