return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Combat, "combat.lua: missing context or Combat tab")

    local RS = C.Services.RS
    local WS = C.Services.WS
    local lp = C.LocalPlayer
    local CombatTab = UI.Tabs.Combat

    C.State  = C.State or { AuraRadius = 150, Toggles = {} }
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
    TUNE.CHAR_CLOSE_FAILSAFE  = TUNE.CHAR_CLOSE_FAILSAFE  or 18

    local running = { SmallTree = false, Character = false }

    local TREE_NAMES = { ["Small Tree"]=true, ["Snowy Small Tree"]=true, ["Small Webbed Tree"]=true }
    local BIG_TREE_NAMES = { TreeBig1=true, TreeBig2=true, TreeBig3=true }
    local CLOSE_FAILSAFE = 12

    local function isBigTreeName(n)
        if BIG_TREE_NAMES[n] then return true end
        return type(n)=="string" and n:match("^WebbedTreeBig%d*$") ~= nil
    end

    local function findInInventory(name)
        local inv = lp and lp:FindFirstChild("Inventory")
        return inv and inv:FindFirstChild(name) or nil
    end
    local function hasStrongAxe() return findInInventory("Strong Axe") ~= nil end
    private = nil
    local function hasChainsaw() return findInInventory("Chainsaw") ~= nil end
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

    local hrpCache = setmetatable({}, {__mode="k"})
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
            for k,_ in pairs(attrs) do
                local n = parseHitAttrKey(k)
                if n and n > maxN then maxN = n end
            end
        end
        local nextN = maxN + 1
        return tostring(nextN) .. "_" .. TUNE.UID_SUFFIX
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

    local TreeImpactCF = setmetatable({}, {__mode="k"})
    local TreeHitSeed  = setmetatable({}, {__mode="k"})

    local function jittered(cf, k)
        local r = 0.05 + 0.015 * (k % 5)
        local ang = k * 2.3999632297
        local off = Vector3.new(math.cos(ang)*r, 0, math.sin(ang)*r)
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

    local lastHitAt = setmetatable({}, {__mode="k"})
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
        if not (hrp and treeModel) then return false end
        targetPart = targetPart or bestTreeHitPart(treeModel)
        if not targetPart then return false end
        local start = hrp.Position
        local dest = targetPart.Position
        local excluded = {}
        if lp.Character then
            excluded[#excluded+1] = lp.Character
        end
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
                excluded[#excluded+1] = blockingTree
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
        if not (hrp and targetPart) then return false end
        local start = hrp.Position
        local dest  = targetPart.Position
        local dir   = dest - start
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
                dir   = dest - start
                hops  = hops - 1
            else
                return false
            end
        end
    end

    local CHAR_WEAPON_PREF = {
        { "Cultist King Mace", 1.0 },
        { "Morningstar",       1.0 },
        { "Obsidiron Hammer",  1.0 },
        { "Infernal Sword",    0.6 },
        { "Ice Sword",         0.5 },
        { "Laser Sword",       0.5 },
        { "Katana",            0.4 },
        { "Trident",           0.6 },
        { "Poison Spear",      0.5 },
        { "Spear",             0.5 },
        { "Strong Axe",        nil },
        { "Chainsaw",          nil },
        { "Ice Axe",           nil },
        { "Good Axe",          nil },
        { "Old Axe",           nil },
    }

    local function collectAvailableCharWeapons()
        local available = {}
        for idx, pair in ipairs(CHAR_WEAPON_PREF) do
            local name, cd = pair[1], pair[2]
            if findInInventory(name) then
                available[#available+1] = {
                    name = name,
                    cd = cd or TUNE.CHOP_SWING_DELAY,
                    order = idx,
                }
            end
        end
        table.sort(available, function(a, b)
            if a.cd ~= b.cd then
                return a.cd < b.cd
            end
            return a.order < b.order
        end)
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
                for _, n in ipairs(TUNE.ChopPrefer) do
                    if findInInventory(n) then
                        availableWeapons[#availableWeapons+1] = {
                            name = n,
                            cd = swingDelay,
                            order = math.huge,
                        }
                        break
                    end
                end
            end
            if #availableWeapons == 0 then
                task.wait(0.2)
                return
            end

            for _, weapon in ipairs(availableWeapons) do
                local toolName = weapon.name
                local cd = weapon.cd
                local lastSwing = lastSwingAtByWeapon[toolName] or 0
                local now = os.clock()
                local remaining = cd - (now - lastSwing)
                if remaining > 0 then
                    task.wait(remaining)
                    now = os.clock()
                end
                local tool = ensureEquipped(toolName)
                if tool then
                    local cap = math.min(#targetModels, TUNE.CHAR_MAX_PER_WAVE)
                    local didHit = false
                    local nextTry = math.huge
                    for i = 1, cap do
                        local mdl = targetModels[i]
                        local head = hitPartGetter(mdl)
                        if head then
                            local origin = (lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")) and lp.Character.HumanoidRootPart.Position or nil
                            local dist = origin and (head.Position - origin).Magnitude or math.huge
                            local los = false
                            if lp.Character and lp.Character:FindFirstChild("HumanoidRootPart") then
                                los = visibleFromHRP(lp.Character.HumanoidRootPart, head, tonumber(TUNE.RAY_MAX_HOPS_CHAR) or 0, lp.Character)
                            end
                            if los or dist <= TUNE.CHAR_CLOSE_FAILSAFE then
                                local canHit, waitFor = canHitWithWeapon(mdl, toolName, cd)
                                if canHit then
                                    local impactCF = computeImpactCFrame(mdl, head)
                                    local hitId = nextCharacterHitId()
                                    HitTarget(mdl, tool, hitId, impactCF)
                                    markHitWithWeapon(mdl, toolName)
                                    didHit = true
                                    task.wait(TUNE.CHAR_HIT_STEP_WAIT)
                                elseif waitFor and waitFor < nextTry then
                                    nextTry = waitFor
                                end
                            end
                        end
                    end
                    if didHit then
                        lastSwingAtByWeapon[toolName] = os.clock()
                    elseif nextTry < math.huge then
                        task.wait(math.max(0.01, nextTry))
                    end
                end
            end
            return
        end

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

    local function collectCharactersInRadius(charsFolder, origin, radius)
        local out = {}
        if not charsFolder then return out end
        for _, mdl in ipairs(charsFolder:GetChildren()) do
            repeat
                if not mdl:IsA("Model") then break end
                local n = mdl.Name or ""
                local nameLower = n:lower()
                if string.find(nameLower, "horse", 1, true) then break end
                local distPart = charDistancePart(mdl)
                if not distPart then break end
                if (distPart.Position - origin).Magnitude > radius then break end
                out[#out+1] = mdl
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
                    local origin = hrp.Position
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
                                    filtered[#filtered+1] = mdl
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
    local function stopCharacterAura() running.Character = false end

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
                    local origin = hrp.Position
                    local radius = tonumber(C.State.AuraRadius) or 150
                    local roots = {
                        WS,
                        RS:FindFirstChild("Assets"),
                        RS:FindFirstChild("CutsceneSets"),
                    }
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
                                    filtered[#filtered+1] = tree
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
    local function stopSmallTreeAura() running.SmallTree = false end

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
        while true do task.wait(2.0) check() end
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

    if C.State.Toggles.SmallTreeAura then startSmallTreeAura() end
end
