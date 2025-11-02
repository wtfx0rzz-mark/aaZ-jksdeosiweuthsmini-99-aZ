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

    TUNE.RAY_FAN_RAYS         = TUNE.RAY_FAN_RAYS         or 72
    TUNE.RAY_MAX_HOPS         = TUNE.RAY_MAX_HOPS         or 1
    TUNE.RAY_HEIGHT           = TUNE.RAY_HEIGHT           or 2.5
    TUNE.RAY_EPS              = TUNE.RAY_EPS              or 0.01

    local running = { SmallTree = false, Character = false }

    local TREE_NAMES = { ["Small Tree"]=true, ["Snowy Small Tree"]=true, ["Small Webbed Tree"]=true }
    local BIG_TREE_NAMES = { TreeBig1=true, TreeBig2=true, TreeBig3=true }

    local function isBigTreeName(n)
        if BIG_TREE_NAMES[n] then return true end
        return type(n)=="string" and n:match("^WebbedTreeBig%d*$") ~= nil
    end

    local function findInInventory(name)
        local inv = lp and lp:FindFirstChild("Inventory")
        return inv and inv:FindFirstChild(name) or nil
    end
    local function hasStrongAxe() return findInInventory("Strong Axe") ~= nil end
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

    local hrpCache = setmetatable({}, {__mode="k"})
    local function bestCharacterHitPart(model)
        if not model or not model:IsA("Model") then return nil end
        local hrp = hrpCache[model]
        if hrp and hrp.Parent then return hrp end
        hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then hrpCache[model] = hrp return hrp end
        if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
        hrp = model:FindFirstChildWhichIsA("BasePart")
        if hrp then hrpCache[model] = hrp end
        return hrp
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

    local function ascendModel(inst)
        local cur = inst
        while cur and not cur:IsA("Model") do cur = cur.Parent end
        return cur
    end

    local function dist(a, b)
        return (a - b).Magnitude
    end

    local function fanRayCollect(origin, radius, fanRays, maxHops, predicate, getKeyPart)
        local resultSet, ordered = {}, {}
        local baseParams = RaycastParams.new()
        baseParams.FilterType = Enum.RaycastFilterType.Exclude
        baseParams.FilterDescendantsInstances = { lp.Character }
        baseParams.IgnoreWater = true
        local start = origin + Vector3.new(0, TUNE.RAY_HEIGHT, 0)
        local step = (2 * math.pi) / math.max(1, fanRays)
        for i = 1, fanRays do
            local theta = (i - 1) * step
            local dir = Vector3.new(math.cos(theta), 0, math.sin(theta)) * radius
            local remaining = dir
            local rayOrigin = start
            local hops = math.max(0, maxHops)
            local excluded = { lp.Character }
            while true do
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.IgnoreWater = baseParams.IgnoreWater
                params.FilterDescendantsInstances = excluded
                local hit = WS:Raycast(rayOrigin, remaining, params)
                if not hit then break end
                local mdl = ascendModel(hit.Instance)
                local accepted = false
                if mdl and predicate(mdl) then
                    local key = mdl
                    if not resultSet[key] then
                        local kp = getKeyPart(mdl)
                        if kp and dist(kp.Position, origin) <= radius + 1e-3 then
                            resultSet[key] = true
                            ordered[#ordered+1] = mdl
                        end
                    end
                    accepted = true
                end
                local traveled = (hit.Position - rayOrigin).Magnitude
                local leftover = remaining.Magnitude - traveled - TUNE.RAY_EPS
                if leftover <= 0 then break end
                rayOrigin = hit.Position + remaining.Unit * TUNE.RAY_EPS
                remaining = remaining.Unit * leftover
                if hops <= 0 then break end
                hops -= 1
                table.insert(excluded, hit.Instance)
                if mdl then table.insert(excluded, mdl) end
            end
        end
        return ordered
    end

    local function isTreeModel(m)
        if not (m and m:IsA("Model")) then return false end
        local n = m.Name or ""
        if TREE_NAMES[n] then return true end
        if C.State.Toggles.BigTreeAura and isBigTreeName(n) then return true end
        return false
    end

    local function collectTreesByRay(origin, radius)
        local fan = TUNE.RAY_FAN_RAYS
        local hops = TUNE.RAY_MAX_HOPS
        local list = fanRayCollect(
            origin, radius, fan, hops,
            function(m) return isTreeModel(m) end,
            function(m) return bestTreeHitPart(m) end
        )
        table.sort(list, function(a, b)
            local pa, pb = bestTreeHitPart(a), bestTreeHitPart(b)
            local da = pa and dist(pa.Position, origin) or math.huge
            local db = pb and dist(pb.Position, origin) or math.huge
            if da == db then return (a.Name or "") < (b.Name or "") end
            return da < db
        end)
        return list
    end

    local function collectCharactersByRay(charsFolder, origin, radius)
        if not charsFolder then return {} end
        local fan = TUNE.RAY_FAN_RAYS
        local hops = TUNE.RAY_MAX_HOPS
        local list = fanRayCollect(
            origin, radius, fan, hops,
            function(m)
                if not (m and m:IsA("Model")) then return false end
                if not m:IsDescendantOf(charsFolder) then return false end
                local n = (m.Name or ""):lower()
                if string.find(n, "horse", 1, true) then return false end
                return true
            end,
            function(m) return charDistancePart(m) end
        )
        if TUNE.CHAR_SORT then
            table.sort(list, function(a, b)
                local pa, pb = charDistancePart(a), charDistancePart(b)
                local da = pa and dist(pa.Position, origin) or math.huge
                local db = pb and dist(pb.Position, origin) or math.huge
                if da == db then return (a.Name or "") < (b.Name or "") end
                return da < db
            end)
        end
        return list
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
    local function chopWave(targetModels, swingDelay, hitPartGetter, isTree)
        local toolName
        if isTree and C.State.Toggles.BigTreeAura then
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

        if not isTree then
            local cap = math.min(#targetModels, TUNE.CHAR_MAX_PER_WAVE)
            for i = 1, cap do
                local mdl = targetModels[i]
                local t0 = lastHitAt[mdl] or 0
                if (tick() - t0) >= TUNE.CHAR_DEBOUNCE_SEC then
                    local hitPart = hitPartGetter(mdl)
                    if hitPart then
                        local impactCF = hitPart.CFrame
                        local hitId = tostring(tick()) .. "_" .. TUNE.UID_SUFFIX
                        HitTarget(mdl, tool, hitId, impactCF)
                        lastHitAt[mdl] = tick()
                        task.wait(TUNE.CHAR_HIT_STEP_WAIT)
                    end
                end
            end
            task.wait(swingDelay)
            return
        end

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
                    local targets = collectCharactersByRay(WS:FindFirstChild("Characters"), origin, radius)
                    if #targets > 0 then
                        chopWave(targets, TUNE.CHOP_SWING_DELAY, bestCharacterHitPart, false)
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
                    local allTrees = collectTreesByRay(origin, radius)
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
                        chopWave(batch, TUNE.CHOP_SWING_DELAY, bestTreeHitPart, true)
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
        Value = { Min = 0, Max = 500, Default = C.State.AuraRadius or 100 },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then
                nv = v.Value or v.Current or v.CurrentValue or v.Default or v.min or v.max
            end
            nv = tonumber(nv)
            if nv then
                C.State.AuraRadius = math.clamp(nv, 0, 500)
            end
        end
    })

    if C.State.Toggles.SmallTreeAura then startSmallTreeAura() end
end
