return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Combat, "combat.lua: missing context or Combat tab")

    local Services = C.Services or {}
    local RS       = Services.RS       or game:GetService("ReplicatedStorage")
    local WS       = Services.WS       or game:GetService("Workspace")
    local Players  = Services.Players  or game:GetService("Players")
    local lp       = C.LocalPlayer     or Players.LocalPlayer

    local CombatTab = UI.Tabs.Combat

    C.State  = C.State  or { AuraRadius = 150, Toggles = {} }
    C.Config = C.Config or {}

    local TUNE = C.Config
    TUNE.CHOP_SWING_DELAY     = TUNE.CHOP_SWING_DELAY     or 0.50
    TUNE.TREE_NAME            = TUNE.TREE_NAME            or "Small Tree"
    TUNE.UID_SUFFIX           = TUNE.UID_SUFFIX           or "0000000000"
    TUNE.ChopPrefer           = TUNE.ChopPrefer           or { "Chainsaw", "Strong Axe", "Ice Axe", "Good Axe", "Old Axe" }
    TUNE.MAX_TARGETS_PER_WAVE = TUNE.MAX_TARGETS_PER_WAVE or 20
    TUNE.CHAR_MAX_PER_WAVE    = TUNE.CHAR_MAX_PER_WAVE    or 20
    TUNE.CHAR_DEBOUNCE_SEC    = TUNE.CHAR_DEBOUNCE_SEC    or 0.4
    TUNE.CHAR_HIT_STEP_WAIT   = TUNE.CHAR_HIT_STEP_WAIT   or 0.02
    TUNE.CHAR_SORT            = (TUNE.CHAR_SORT ~= false)
    TUNE.RAY_MAX_HOPS_CHAR    = TUNE.RAY_MAX_HOPS_CHAR    or 3
    TUNE.RAY_MAX_HOPS_TREE    = TUNE.RAY_MAX_HOPS_TREE    or 1
    TUNE.CHAR_CLOSE_FAILSAFE  = TUNE.CHAR_CLOSE_FAILSAFE  or 24
    TUNE.VIS_THROUGH_WALLS    = (TUNE.VIS_THROUGH_WALLS ~= false)

    local running = { SmallTree = false, Character = false, TrapAura = false }

    local TREE_NAMES = { ["Small Tree"] = true, ["Snowy Small Tree"] = true, ["Small Webbed Tree"] = true }
    local BIG_TREE_NAMES = { TreeBig1 = true, TreeBig2 = true, TreeBig3 = true }
    local CLOSE_FAILSAFE = 18

    local TRAP_MAX_RADIUS = 20 -- studs: hard cap for trap aura range

    --------------------------------------------------------------------
    -- INVENTORY / TOOL HELPERS
    --------------------------------------------------------------------

    local function isBigTreeName(n)
        if BIG_TREE_NAMES[n] then return true end
        return type(n) == "string" and n:match("^WebbedTreeBig%d*$") ~= nil
    end

    local function findInInventory(name)
        local inv = lp and lp:FindFirstChild("Inventory")
        return inv and inv:FindFirstChild(name) or nil
    end

    local function hasStrongAxe()
        return findInInventory("Strong Axe") ~= nil
    end

    local function hasChainsaw()
        return findInInventory("Chainsaw") ~= nil
    end

    local function hasBigTreeTool()
        if hasChainsaw() then return "Chainsaw" end
        if hasStrongAxe() then return "Strong Axe" end
        return nil
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
        if tool then
            SafeEquip(tool)
            local t0 = os.clock()
            while os.clock() - t0 < 0.25 do
                if equippedToolName() == wantedName then break end
                task.wait(0.02)
            end
        end
        return tool
    end

    --------------------------------------------------------------------
    -- TREE HELPERS
    --------------------------------------------------------------------

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

    local function getRayOriginFromChar(ch)
        if not ch then return nil end
        local head = ch:FindFirstChild("Head")
        if head and head:IsA("BasePart") then return head.Position end
        local r = ch:FindFirstChild("HumanoidRootPart")
        if r and r:IsA("BasePart") then return r.Position + Vector3.new(0, 2.5, 0) end
        return nil
    end

    local function isSmallTreeModel(model)
        if not (model and model:IsA("Model")) then return false end
        local name = model.Name
        if TREE_NAMES[name] then
            return bestTreeHitPart(model) ~= nil
        end
        if type(name) ~= "string" then return false end
        local lower = name:lower()
        if lower:find("small", 1, true) and lower:find("tree", 1, true) then
            return bestTreeHitPart(model) ~= nil
        end
        return false
    end

    local function attrBucket(treeModel)
        local hr = treeModel and treeModel:FindFirstChild("HitRegisters")
        return (hr and hr:IsA("Instance")) and hr or treeModel
    end

    local function parseHitAttrKey(k)
        local n = string.match(k or "", "^(%d+)_" .. TUNE.UID_SUFFIX .. "$")
        return n and tonumber(n) or nil
    end

    local function nextPerTreeHitId(treeModel)
        local bucket = attrBucket(treeModel)
        local maxN = 0
        local attrs = bucket and bucket:GetAttributes() or nil
        if attrs then
            for k, _ in pairs(attrs) do
                local n = parseHitAttrKey(k)
                if n and n > maxN then maxN = n end
            end
        end
        local nextN = maxN + 1
        return tostring(nextN) .. "_" .. TUNE.UID_SUFFIX
    end

    local function collectTreesInRadius(roots, origin, radius)
        local includeBig = C.State.Toggles.BigTreeAura == true
        local out, n = {}, 0

        local function walk(node)
            if not node then return end
            if node:IsA("Model") and (isSmallTreeModel(node) or (includeBig and isBigTreeName(node.Name))) then
                local trunk = bestTreeHitPart(node)
                if trunk then
                    local d = (trunk.Position - origin).Magnitude
                    if d <= radius then
                        n = n + 1
                        out[n] = node
                    end
                end
            end
            local ok, children = pcall(node.GetChildren, node)
            if ok and children then
                for _, ch in ipairs(children) do
                    walk(ch)
                end
            end
        end

        for _, root in ipairs(roots) do
            walk(root)
        end

        table.sort(out, function(a, b)
            local pa, pb = bestTreeHitPart(a), bestTreeHitPart(b)
            local da = pa and (pa.Position - origin).Magnitude or math.huge
            local db = pb and (pb.Position - origin).Magnitude or math.huge
            if da == db then return (a.Name or "") < (b.Name or "") end
            return da < db
        end)

        return out
    end

    --------------------------------------------------------------------
    -- VISIBILITY / CHARACTER HELPERS
    --------------------------------------------------------------------

    local function characterHeadPart(model)
        if not (model and model:IsA("Model")) then return nil end
        local head = model:FindFirstChild("Head")
        if head and head:IsA("BasePart") then return head end
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then return hrp end
        if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
        return model:FindFirstChildWhichIsA("BasePart")
    end

    local function charDistancePart(m)
        if not (m and m:IsA("Model")) then return nil end
        local hrp = m:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then return hrp end
        local pp = m.PrimaryPart
        if pp and pp:IsA("BasePart") then return pp end
        return nil
    end

    local function computeImpactCFrame(model, hitPart)
        if not (model and hitPart and hitPart:IsA("BasePart")) then
            return hitPart and CFrame.new(hitPart.Position) or CFrame.new()
        end
        local outward = hitPart.CFrame.LookVector
        if outward.Magnitude == 0 then outward = Vector3.new(0, 0, -1) end
        outward = outward.Unit
        local origin = hitPart.Position + outward * 1.0
        local dir = -outward * 5.0
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances = { model }
        local rc = WS:Raycast(origin, dir, params)
        local pos = rc and (rc.Position + rc.Normal * 0.02) or (origin + dir * 0.6)
        local rot = hitPart.CFrame - hitPart.CFrame.Position
        return CFrame.new(pos) * rot
    end

    local function modelOf(inst)
        if not inst then return nil end
        if inst:IsA("Model") then return inst end
        return inst:FindFirstAncestorOfClass("Model")
    end

    local function isCharacterModel(m)
        return m and m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") ~= nil
    end

    local function treeModelOf(inst)
        local current = inst
        while current do
            if current:IsA("Model") then
                local name = current.Name
                if isSmallTreeModel(current) or isBigTreeName(name) then
                    return current
                end
            end
            current = current.Parent
        end
        return nil
    end

    local function visibleTreeFromHRP(hrp, treeModel, maxHops, targetPart)
        if TUNE.VIS_THROUGH_WALLS then return true end
        if not (hrp and treeModel) then return false end
        targetPart = targetPart or bestTreeHitPart(treeModel)
        if not targetPart then return false end
        local ch = lp.Character
        local start = getRayOriginFromChar(ch) or hrp.Position
        local dest = targetPart.Position
        local excluded = {}
        if ch then excluded[#excluded + 1] = ch end
        local hops = math.max(0, tonumber(maxHops) or 0)

        while true do
            local dir = dest - start
            if dir.Magnitude < 0.1 then return true end
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = excluded
            local hit = WS:Raycast(start, dir, params)
            if not hit then return true end
            local inst = hit.Instance
            if inst:IsDescendantOf(treeModel) then return true end
            local blockingTree = treeModelOf(inst)
            if blockingTree and hops > 0 then
                excluded[#excluded + 1] = blockingTree
                local mag = dir.Magnitude
                if mag <= 0 then return false end
                start = hit.Position + (dir / mag) * 0.05
                hops = hops - 1
            else
                return false
            end
        end
    end

    local function visibleFromHRP(hrp, targetPart, maxHops, excludeSelf)
        if TUNE.VIS_THROUGH_WALLS then return true end
        if not (hrp and targetPart) then return false end
        local ch = lp.Character
        local start = getRayOriginFromChar(ch) or hrp.Position
        local dest = targetPart.Position
        local dir = dest - start
        if dir.Magnitude < 0.1 then return true end
        local excluded = { excludeSelf }
        local hops = math.max(0, tonumber(maxHops) or 0)

        while true do
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = excluded
            local hit = WS:Raycast(start, dir, params)
            if not hit then return true end
            local hInst = hit.Instance
            if hInst:IsDescendantOf(targetPart.Parent) then return true end
            local m = modelOf(hInst)
            if isCharacterModel(m) and hops > 0 then
                table.insert(excluded, m)
                start = hit.Position + dir.Unit * 0.05
                dir = dest - start
                hops = hops - 1
            else
                return false
            end
        end
    end

    local function collectCharactersInRadius(charsFolder, origin, radius)
        local out = {}
        if not charsFolder then return out end
        for _, mdl in ipairs(charsFolder:GetChildren()) do
            repeat
                if not mdl:IsA("Model") then break end
                local n = mdl.Name or ""
                local nameLower = n:lower()
                if string.find(nameLower, "horse", 1, true) then break end
                if n == "Deer" or n == "Ram" or n == "Owl" or n == "Pelt Trader" or n == "Furniture Trader" or n == "Horse" then break end
                local distPart = charDistancePart(mdl)
                if not distPart then break end
                if (distPart.Position - origin).Magnitude > radius then break end
                out[#out + 1] = mdl
            until true
        end
        if TUNE.CHAR_SORT then
            table.sort(out, function(a, b)
                local pa, pb = charDistancePart(a), charDistancePart(b)
                local da = pa and (pa.Position - origin).Magnitude or math.huge
                local db = pb and (pb.Position - origin).Magnitude or math.huge
                if da == db then return (a.Name or "") < (b.Name or "") end
                return da < db
            end)
        end
        return out
    end

    --------------------------------------------------------------------
    -- DAMAGE / HITS
    --------------------------------------------------------------------

    local function HitTarget(targetModel, tool, hitId, impactCF)
        local evs = RS:FindFirstChild("RemoteEvents")
        local dmg = evs and evs:FindFirstChild("ToolDamageObject")
        if not dmg then return end
        dmg:InvokeServer(targetModel, tool, hitId, impactCF)
    end

    local TreeImpactCF = setmetatable({}, { __mode = "k" })
    local TreeHitSeed  = setmetatable({}, { __mode = "k" })

    local function jittered(cf, k)
        local r = 0.05 + 0.015 * (k % 5)
        local ang = k * 2.3999632297
        local off = Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
        local rot = cf - cf.Position
        return CFrame.new(cf.Position + off) * rot
    end

    local function impactCFForTree(treeModel, hitPart)
        local base = TreeImpactCF[treeModel]
        if not base then
            base = computeImpactCFrame(treeModel, hitPart)
            TreeImpactCF[treeModel] = base
        end
        local k = (TreeHitSeed[treeModel] or 0) + 1
        TreeHitSeed[treeModel] = k
        return jittered(base, k)
    end

    local lastHitAt = setmetatable({}, { __mode = "k" })

    local function canHitWithWeapon(target, weaponName, cooldownSec)
        if not target then return false, nil end
        local cd = tonumber(cooldownSec) or TUNE.CHAR_DEBOUNCE_SEC
        local bucket = lastHitAt[target]
        if not bucket or type(bucket) ~= "table" then return true, nil end
        local t = bucket[weaponName]
        if not t then return true, nil end
        local elapsed = tick() - t
        if elapsed >= cd then
            return true, nil
        end
        return false, cd - elapsed
    end

    local function markHitWithWeapon(target, weaponName)
        if not (target and weaponName) then return end
        local bucket = lastHitAt[target]
        if type(bucket) ~= "table" then
            bucket = {}
            lastHitAt[target] = bucket
        end
        bucket[weaponName] = tick()
    end

    local CHAR_WEAPON_PREF = {
        { "Cultist King Mace", 1.0 },
        { "Morningstar",       1.0 },
        { "Obsidiron Hammer",  1.0 },
        { "Infernal Sword",    0.51 },
        { "Ice Sword",         0.5 },
        { "Laser Sword",       0.5 },
        { "Katana",            0.4 },
        { "Trident",           0.6 },
        { "Poison Spear",      0.5 },
        { "Spear",             0.5 },
        { "Strong Axe",        0.5 },
        { "Chainsaw",          0.5 },
        { "Ice Axe",           0.5 },
        { "Good Axe",          0.5 },
        { "Old Axe",           0.5 },
    }

    local function collectAvailableCharWeapons()
        local available = {}
        for idx, pair in ipairs(CHAR_WEAPON_PREF) do
            local name, cd = pair[1], pair[2]
            if findInInventory(name) then
                available[#available + 1] = { name = name, cd = cd or TUNE.CHOP_SWING_DELAY, order = idx }
            end
        end
        table.sort(available, function(a, b) return a.order < b.order end)
        if #available == 0 then
            for _, n in ipairs(TUNE.ChopPrefer) do
                if findInInventory(n) then
                    available[#available + 1] = { name = n, cd = TUNE.CHOP_SWING_DELAY, order = math.huge }
                    break
                end
            end
        end
        return available
    end

    local lastSwingAtByWeapon = {}
    local characterHitSeq = 0

    local function nextCharacterHitId()
        characterHitSeq += 1
        return tostring(characterHitSeq) .. "_" .. TUNE.UID_SUFFIX
    end

    local function chopWave(targetModels, swingDelay, hitPartGetter, isTree)
        if not isTree then
            local availableWeapons = collectAvailableCharWeapons()
            if #availableWeapons == 0 then
                task.wait(0.2)
                return
            end

            local now = os.clock()
            local earliestReady = math.huge
            local anyHit = false

            for _, weapon in ipairs(availableWeapons) do
                local toolName = weapon.name
                local cd       = weapon.cd
                local lastSwing = lastSwingAtByWeapon[toolName] or 0
                local since = now - lastSwing

                if since < cd then
                    local remaining = cd - since
                    if remaining < earliestReady then
                        earliestReady = remaining
                    end
                else
                    local tool = ensureEquipped(toolName)
                    if tool then
                        local cap = math.min(#targetModels, TUNE.CHAR_MAX_PER_WAVE)
                        local didHitWithThis = false
                        local nextTry = math.huge

                        for i = 1, cap do
                            local mdl = targetModels[i]
                            local head = hitPartGetter(mdl)
                            if head then
                                local ch = lp.Character
                                local hrp = ch and ch:FindFirstChild("HumanoidRootPart") or nil
                                local origin = getRayOriginFromChar(ch) or (hrp and hrp.Position) or nil
                                local dist = origin and (head.Position - origin).Magnitude or math.huge
                                local los = false
                                if hrp then
                                    los = visibleFromHRP(hrp, head, tonumber(TUNE.RAY_MAX_HOPS_CHAR) or 0, ch)
                                end
                                if los or dist <= TUNE.CHAR_CLOSE_FAILSAFE then
                                    local canHit, waitFor = canHitWithWeapon(mdl, toolName, cd)
                                    if canHit then
                                        local impactCF = computeImpactCFrame(mdl, head)
                                        local hitId = nextCharacterHitId()
                                        HitTarget(mdl, tool, hitId, impactCF)
                                        markHitWithWeapon(mdl, toolName)
                                        didHitWithThis = true
                                        anyHit = true
                                        task.wait(TUNE.CHAR_HIT_STEP_WAIT)
                                    elseif waitFor and waitFor < nextTry then
                                        nextTry = waitFor
                                    end
                                end
                            end
                        end

                        if didHitWithThis then
                            lastSwingAtByWeapon[toolName] = os.clock()
                        elseif nextTry < math.huge then
                            if nextTry < earliestReady then
                                earliestReady = nextTry
                            end
                        end
                    end
                end
            end

            if not anyHit and earliestReady < math.huge then
                task.wait(math.max(0.01, earliestReady))
            end

            return
        end

        -- Tree mode
        local toolName
        if C.State.Toggles.BigTreeAura then
            local bt = hasBigTreeTool()
            if bt then
                toolName = bt
            else
                C.State.Toggles.BigTreeAura = false
            end
        end
        if not toolName then
            for _, n in ipairs(TUNE.ChopPrefer) do
                if findInInventory(n) then toolName = n break end
            end
        end
        if not toolName then task.wait(0.35) return end
        local tool = ensureEquipped(toolName)
        if not tool then task.wait(0.35) return end

        for _, mdl in ipairs(targetModels) do
            task.spawn(function()
                local hitPart = hitPartGetter(mdl)
                if not hitPart then return end
                local impactCF = impactCFForTree(mdl, hitPart)
                local hitId = nextPerTreeHitId(mdl)
                pcall(function()
                    local bucket = attrBucket(mdl)
                    if bucket then bucket:SetAttribute(hitId, true) end
                end)
                HitTarget(mdl, tool, hitId, impactCF)
            end)
        end
        task.wait(swingDelay)
    end

    --------------------------------------------------------------------
    -- CHARACTER AURA
    --------------------------------------------------------------------

    local function startCharacterAura()
        if running.Character then return end
        running.Character = true
        task.spawn(function()
            while running.Character do
                local ch = lp.Character or lp.CharacterAdded:Wait()
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if not hrp then
                    task.wait(0.2)
                else
                    local origin = (getRayOriginFromChar(ch) or hrp.Position)
                    local radius = tonumber(C.State.AuraRadius) or 150
                    local targets = collectCharactersInRadius(WS:FindFirstChild("Characters"), origin, radius)
                    if #targets > 0 then
                        local hopsChar = tonumber(TUNE.RAY_MAX_HOPS_CHAR) or 0
                        local filtered = {}
                        for _, mdl in ipairs(targets) do
                            local head = characterHeadPart(mdl)
                            if head then
                                local dist = (head.Position - origin).Magnitude
                                local los = visibleFromHRP(hrp, head, hopsChar, ch)
                                if los or dist <= TUNE.CHAR_CLOSE_FAILSAFE then
                                    filtered[#filtered + 1] = mdl
                                end
                            end
                        end
                        if #filtered > 0 then
                            chopWave(filtered, TUNE.CHOP_SWING_DELAY, characterHeadPart, false)
                        else
                            task.wait(0.3)
                        end
                    else
                        task.wait(0.3)
                    end
                end
            end
        end)
    end

    local function stopCharacterAura()
        running.Character = false
    end

    --------------------------------------------------------------------
    -- SMALL TREE AURA
    --------------------------------------------------------------------

    C.State._treeCursor = C.State._treeCursor or 1

    local function startSmallTreeAura()
        if running.SmallTree then return end
        running.SmallTree = true
        task.spawn(function()
            while running.SmallTree do
                local ch = lp.Character or lp.CharacterAdded:Wait()
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if not hrp then
                    task.wait(0.2)
                else
                    local origin = (getRayOriginFromChar(ch) or hrp.Position)
                    local radius = tonumber(C.State.AuraRadius) or 150
                    local roots = { WS, RS:FindFirstChild("Assets"), RS:FindFirstChild("CutsceneSets") }
                    local allTrees = collectTreesInRadius(roots, origin, radius)
                    local total = #allTrees
                    if total > 0 then
                        local batchSize = math.min(TUNE.MAX_TARGETS_PER_WAVE, total)
                        if C.State._treeCursor > total then C.State._treeCursor = 1 end
                        local batch = table.create(batchSize)
                        for i = 1, batchSize do
                            local idx = ((C.State._treeCursor + i - 2) % total) + 1
                            batch[i] = allTrees[idx]
                        end
                        C.State._treeCursor = C.State._treeCursor + batchSize
                        local hopsTree = math.max(0, tonumber(TUNE.RAY_MAX_HOPS_TREE) or 0)
                        local filtered = {}
                        for _, tree in ipairs(batch) do
                            local hitPart = bestTreeHitPart(tree)
                            if hitPart then
                                local dist = (hitPart.Position - origin).Magnitude
                                local los = visibleTreeFromHRP(hrp, tree, hopsTree, hitPart)
                                if los or dist <= CLOSE_FAILSAFE then
                                    filtered[#filtered + 1] = tree
                                end
                            end
                        end
                        if #filtered > 0 then
                            chopWave(filtered, TUNE.CHOP_SWING_DELAY, bestTreeHitPart, true)
                        else
                            task.wait(0.3)
                        end
                    else
                        task.wait(0.3)
                    end
                end
            end
        end)
    end

    local function stopSmallTreeAura()
        running.SmallTree = false
    end

    --------------------------------------------------------------------
    -- TRAP AURA (NO LOGGER, RANGE CAPPED TO 20 STUDS)
    --------------------------------------------------------------------

    local function trapsRoot()
        return WS:FindFirstChild("Structures") or WS:FindFirstChild("structures") or WS
    end

    local TRAP_REMOTES = { StartDrag = nil, StopDrag = nil, SetTrap = nil }
    local trapCache, trapCacheAt = nil, 0

    local function resolveTrapRemotes()
        local re = RS:FindFirstChild("RemoteEvents")
        if not re then return end
        if not TRAP_REMOTES.StartDrag then
            TRAP_REMOTES.StartDrag =
                re:FindFirstChild("RequestStartDraggingItem") or
                re:FindFirstChild("StartDraggingItem")
        end
        if not TRAP_REMOTES.StopDrag then
            TRAP_REMOTES.StopDrag =
                re:FindFirstChild("RequestStopDraggingItem") or
                re:FindFirstChild("StopDraggingItem")
        end
        if not TRAP_REMOTES.SetTrap then
            TRAP_REMOTES.SetTrap =
                re:FindFirstChild("RequestSetTrap") or
                re:FindFirstChild("SetTrap")
        end
    end

    local function getTrapPart(trap)
        if trap:IsA("Model") then
            return trap.PrimaryPart or trap:FindFirstChildWhichIsA("BasePart")
        elseif trap:IsA("BasePart") then
            return trap
        end
        return nil
    end

    local function getAllBearTraps()
        local now = os.clock()
        if trapCache and (now - trapCacheAt) < 2.0 then
            return trapCache
        end
        trapCacheAt = now
        trapCache = {}

        local root = trapsRoot()
        if not root then
            return trapCache
        end

        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("Model") and d.Name == "Bear Trap" then
                trapCache[#trapCache + 1] = d
            end
        end
        return trapCache
    end

    local function moveTrapToCF(trap, cf, setNow)
        if not trap or not trap.Parent or not cf then return end
        resolveTrapRemotes()

        task.spawn(function()
            if TRAP_REMOTES.StartDrag then
                pcall(function() TRAP_REMOTES.StartDrag:FireServer(trap) end)
            end
            task.wait(0.03)
            pcall(function()
                if trap:IsA("Model") then
                    trap:PivotTo(cf)
                else
                    local bp = trap:FindFirstChildWhichIsA("BasePart")
                    if bp then bp.CFrame = cf end
                end
            end)
            if TRAP_REMOTES.StopDrag then
                pcall(function() TRAP_REMOTES.StopDrag:FireServer(trap) end)
            end
            if setNow and TRAP_REMOTES.SetTrap then
                pcall(function() TRAP_REMOTES.SetTrap:FireServer(trap) end)
            end
        end)
    end

    local trapCooldownSec = 2.0
    local charCooldownSec = 2.0
    local lastTrapUse = {}
    local lastCharSnap = {}

    local function moveTrapUnderCharacter(trap, mdl)
        if not trap or not mdl or not mdl.Parent then return end
        local root = charDistancePart(mdl)
        if not root then return end

        local now = os.clock()
        local lt = lastTrapUse[trap] or 0
        if now - lt < trapCooldownSec then
            return
        end
        local lc = lastCharSnap[mdl] or 0
        if now - lc < charCooldownSec then
            return
        end

        lastTrapUse[trap] = now
        lastCharSnap[mdl] = now

        local targetCF = root.CFrame * CFrame.new(0, -3, 0)
        moveTrapToCF(trap, targetCF, true)
    end

    local function lockTrapsAroundPlayer(traps, hrp)
        if not hrp then return end
        local n = #traps
        if n == 0 then return end
        local center = hrp.Position
        local radius = 6
        local height = 2
        for i, trap in ipairs(traps) do
            if trap and trap.Parent then
                local t = (i - 1) / n * math.pi * 2
                local offset = Vector3.new(math.cos(t) * radius, height, math.sin(t) * radius)
                local pos = center + offset
                local cf = CFrame.new(pos, center)
                moveTrapToCF(trap, cf, false)
            end
        end
    end

    local function startTrapAura()
        if running.TrapAura then return end
        running.TrapAura = true

        task.spawn(function()
            resolveTrapRemotes()
            while running.TrapAura do
                local ch = lp.Character or lp.CharacterAdded:Wait()
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if not hrp then
                    task.wait(0.25)
                else
                    local traps = getAllBearTraps()
                    if #traps == 0 then
                        task.wait(1.5)
                    else
                        local origin = getRayOriginFromChar(ch) or hrp.Position
                        -- Trap aura radius is capped to TRAP_MAX_RADIUS
                        local configured = tonumber(C.State.AuraRadius) or 150
                        local radius = math.min(configured, TRAP_MAX_RADIUS)

                        local charsFolder = WS:FindFirstChild("Characters")
                        local targets = collectCharactersInRadius(charsFolder, origin, radius)
                        if #targets > 0 then
                            local idx = 1
                            for _, trap in ipairs(traps) do
                                if idx > #targets then break end
                                local mdl = targets[idx]
                                idx = idx + 1
                                moveTrapUnderCharacter(trap, mdl)
                            end
                            task.wait(0.25)
                        else
                            lockTrapsAroundPlayer(traps, hrp)
                            task.wait(0.4)
                        end
                    end
                end
            end
        end)
    end

    local function stopTrapAura()
        running.TrapAura = false
    end

    --------------------------------------------------------------------
    -- MANUAL TRAP CONTROL PANEL
    --------------------------------------------------------------------

    local trapPanelGui
    local selectedTrap
    local trapLabel

    local function destroyTrapPanel()
        if trapPanelGui then
            trapPanelGui:Destroy()
            trapPanelGui = nil
            trapLabel = nil
            selectedTrap = nil
        end
    end

    local function updateTrapLabel()
        if not trapLabel then return end
        if selectedTrap and selectedTrap.Parent then
            local txt = "Selected trap: Bear Trap"
            local tp = getTrapPart(selectedTrap)
            local ch = lp.Character
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
            if tp and hrp then
                local d = (tp.Position - hrp.Position).Magnitude
                txt = string.format("Selected trap: Bear Trap (%.0f studs)", d)
            end
            trapLabel.Text = txt
        else
            trapLabel.Text = "Selected trap: <none>"
        end
    end

    local function selectNearestTrap()
        local traps = getAllBearTraps()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        local hrp = ch:FindFirstChild("HumanoidRootPart")
        if not hrp or #traps == 0 then
            selectedTrap = nil
            updateTrapLabel()
            return
        end
        local best, bestDist
        for _, t in ipairs(traps) do
            local tp = getTrapPart(t)
            if tp then
                local d = (tp.Position - hrp.Position).Magnitude
                if not bestDist or d < bestDist then
                    bestDist = d
                    best = t
                end
            end
        end
        selectedTrap = best
        updateTrapLabel()
    end

    local function bringTrapToPlayer()
        if not (selectedTrap and selectedTrap.Parent) then
            selectNearestTrap()
        end
        if not (selectedTrap and selectedTrap.Parent) then return end
        local ch = lp.Character or lp.CharacterAdded:Wait()
        local hrp = ch:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local cf = hrp.CFrame * CFrame.new(0, -2, -3)
        moveTrapToCF(selectedTrap, cf, false)
        updateTrapLabel()
    end

    local function sendTrapToNearestCharacter()
        if not (selectedTrap and selectedTrap.Parent) then
            selectNearestTrap()
        end
        if not (selectedTrap and selectedTrap.Parent) then return end

        local ch = lp.Character or lp.CharacterAdded:Wait()
        local hrp = ch:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local origin = getRayOriginFromChar(ch) or hrp.Position
        local charsFolder = WS:FindFirstChild("Characters")
        if not charsFolder then return end

        -- Use same capped radius for manual send
        local targets = collectCharactersInRadius(charsFolder, origin, TRAP_MAX_RADIUS)
        if #targets == 0 then return end

        moveTrapUnderCharacter(selectedTrap, targets[1])
        updateTrapLabel()
    end

    local function setTrapNow()
        if not (selectedTrap and selectedTrap.Parent) then
            selectNearestTrap()
        end
        if not (selectedTrap and selectedTrap.Parent) then return end
        resolveTrapRemotes()
        if TRAP_REMOTES.SetTrap then
            pcall(function()
                TRAP_REMOTES.SetTrap:FireServer(selectedTrap)
            end)
        end
    end

    local function createTrapPanel()
        destroyTrapPanel()

        local player = lp or Players.LocalPlayer
        if not player then return end
        local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
        if not playerGui then return end

        trapPanelGui = Instance.new("ScreenGui")
        trapPanelGui.Name = "TrapManualControls"
        trapPanelGui.ResetOnSpawn = false
        trapPanelGui.Parent = playerGui

        local frame = Instance.new("Frame")
        frame.Name = "TrapPanel"
        frame.Parent = trapPanelGui
        frame.Size = UDim2.new(0, 220, 0, 150)
        frame.Position = UDim2.new(1, -230, 1, -170)
        frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        frame.BackgroundTransparency = 0.25
        frame.BorderSizePixel = 0
        frame.Active = true
        frame.Draggable = true

        trapLabel = Instance.new("TextLabel")
        trapLabel.Name = "TrapLabel"
        trapLabel.Parent = frame
        trapLabel.Size = UDim2.new(1, -8, 0, 24)
        trapLabel.Position = UDim2.new(0, 4, 0, 4)
        trapLabel.BackgroundTransparency = 1
        trapLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        trapLabel.TextSize = 14
        trapLabel.Font = Enum.Font.SourceSansBold
        trapLabel.TextXAlignment = Enum.TextXAlignment.Left
        trapLabel.Text = "Selected trap: <none>"

        local function makeButton(yOffset, text, callback)
            local btn = Instance.new("TextButton")
            btn.Parent = frame
            btn.Size = UDim2.new(1, -8, 0, 26)
            btn.Position = UDim2.new(0, 4, 0, yOffset)
            btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.TextSize = 13
            btn.Font = Enum.Font.SourceSansBold
            btn.Text = text
            btn.AutoButtonColor = true
            btn.MouseButton1Click:Connect(function()
                callback()
            end)
            return btn
        end

        local baseY = 32
        makeButton(baseY,      "Select nearest trap", selectNearestTrap)
        makeButton(baseY + 30, "Bring trap to me",    bringTrapToPlayer)
        makeButton(baseY + 60, "Send to nearest",     sendTrapToNearestCharacter)
        makeButton(baseY + 90, "Set trap now",        setTrapNow)

        updateTrapLabel()
    end

    --------------------------------------------------------------------
    -- UI WIRING
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
        Title = "Trap Aura (Bear Traps, max 20 studs)",
        Value = C.State.Toggles.TrapAura or false,
        Callback = function(on)
            C.State.Toggles.TrapAura = on
            if on then startTrapAura() else stopTrapAura() end
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

    local bigToggle
    bigToggle = CombatTab:Toggle({
        Title = "Big Trees (Strong Axe or Chainsaw)",
        Value = C.State.Toggles.BigTreeAura or false,
        Callback = function(on)
            if on then
                local bt = hasBigTreeTool()
                if bt then
                    C.State.Toggles.BigTreeAura = true
                else
                    C.State.Toggles.BigTreeAura = false
                    pcall(function() if bigToggle and bigToggle.Set then bigToggle:Set(false) end end)
                    pcall(function() if bigToggle and bigToggle.SetValue then bigToggle:SetValue(false) end end)
                end
            else
                C.State.Toggles.BigTreeAura = false
            end
        end
    })

    -- Keep BigTreeAura honest if tools disappear
    task.spawn(function()
        local inv = lp:WaitForChild("Inventory", 10)
        if not inv then return end
        local function check()
            if C.State.Toggles.BigTreeAura and not hasBigTreeTool() then
                C.State.Toggles.BigTreeAura = false
                pcall(function() if bigToggle and bigToggle.Set then bigToggle:Set(false) end end)
                pcall(function() if bigToggle and bigToggle.SetValue then bigToggle:SetValue(false) end end)
            end
        end
        inv.ChildRemoved:Connect(check)
        while true do
            task.wait(2.0)
            check()
        end
    end)

    CombatTab:Slider({
        Title = "Distance",
        Value = { Min = 0, Max = 200, Default = 100 },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then
                nv = v.Value or v.Current or v.CurrentValue or v.Default or v.min or v.max
            end
            nv = tonumber(nv)
            if nv then
                C.State.AuraRadius = math.clamp(nv, 0, 200)
            end
        end
    })

    CombatTab:Toggle({
        Title = "Trap Manual Controls",
        Value = C.State.Toggles.TrapManualControls or false,
        Callback = function(on)
            C.State.Toggles.TrapManualControls = on
            if on then
                createTrapPanel()
            else
                destroyTrapPanel()
            end
        end
    })

    -- Restore running states if toggles were on
    if C.State.Toggles.SmallTreeAura then startSmallTreeAura() end
    if C.State.Toggles.TrapAura then startTrapAura() end
    if C.State.Toggles.CharacterAura then startCharacterAura() end
    if C.State.Toggles.TrapManualControls then createTrapPanel() end
end
