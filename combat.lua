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

    C.Config.CHOP_SWING_DELAY       = C.Config.CHOP_SWING_DELAY       or 0.55
    C.Config.TREE_NAME              = C.Config.TREE_NAME              or "Small Tree"
    C.Config.UID_SUFFIX             = C.Config.UID_SUFFIX             or "0000000000"
    C.Config.ChopPrefer             = C.Config.ChopPrefer             or { "Chainsaw", "Strong Axe", "Good Axe", "Old Axe" }
    C.Config.MAX_TARGETS_PER_WAVE   = C.Config.MAX_TARGETS_PER_WAVE   or 80

    C.Config.STREAM_ENABLE          = (C.Config.STREAM_ENABLE ~= false)
    C.Config.STREAM_TIMEOUT         = C.Config.STREAM_TIMEOUT         or 0.9
    C.Config.STREAM_BIN_SIZE        = C.Config.STREAM_BIN_SIZE        or 96
    C.Config.STREAM_STRIDE          = C.Config.STREAM_STRIDE          or 24

    local running = { SmallTree = false, Character = false }

    local TREE_NAMES = { ["Small Tree"]=true, ["Snowy Small Tree"]=true }

    local function isTreeName(n)
        if not n then return false end
        if TREE_NAMES[n] then return true end
        local nl = string.lower(n)
        return string.find(nl, "small tree", 1, true) ~= nil
    end

    local function findInInventory(name)
        local inv = lp and lp:FindFirstChild("Inventory")
        return inv and inv:FindFirstChild(name) or nil
    end

    local function equippedTool()
        local ch = lp and lp.Character
        if not ch then return nil end
        return ch:FindFirstChildOfClass("Tool")
    end

    local function equippedToolName()
        local t = equippedTool()
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
        local ch = lp and lp.Character
        if ch then
            local t = ch:FindFirstChildOfClass("Tool")
            if t and t.Name == wantedName then
                return t
            end
        end
        local tool = findInInventory(wantedName)
        if tool then
            SafeEquip(tool)
            local deadline = os.clock() + 0.35
            repeat
                task.wait()
                ch = lp and lp.Character
                if ch then
                    local nowTool = ch:FindFirstChildOfClass("Tool")
                    if nowTool and nowTool.Name == wantedName then
                        return nowTool
                    end
                end
            until os.clock() > deadline
            return tool
        end
        return nil
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
        if tree.PrimaryPart and tree.PrimaryPart:IsA("BasePart") then return tree.PrimaryPart end
        return tree:FindFirstChildWhichIsA("BasePart")
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
        if outward.Magnitude == 0 then
            return hitPart.CFrame
        end
        outward = outward.Unit
        local origin  = hitPart.Position + outward * 1.0
        local dir     = -outward * 5.0
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances = {model}
        local rc = WS:Raycast(origin, dir, params)
        if rc then
            local pos = rc.Position + rc.Normal*0.02
            local rot = hitPart.CFrame - hitPart.CFrame.Position
            return CFrame.new(pos) * rot
        else
            return hitPart.CFrame
        end
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
        local n = string.match(k or "", "^(%d+)_" .. C.Config.UID_SUFFIX .. "$")
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
        return tostring(nextN) .. "_" .. C.Config.UID_SUFFIX
    end

    local function binKeyFromPos(pos)
        local s = C.Config.STREAM_BIN_SIZE
        local bx = math.floor(pos.X / s)
        local by = math.floor(pos.Y / s)
        local bz = math.floor(pos.Z / s)
        return string.format("%d,%d,%d", bx, by, bz)
    end

    local function prefetchPositions(positions)
        if not C.Config.STREAM_ENABLE or not positions or #positions == 0 then return end
        local seen, dedup = {}, {}
        for _,p in ipairs(positions) do
            local key = binKeyFromPos(p)
            if not seen[key] then
                seen[key] = true
                dedup[#dedup+1] = p
            end
        end
        local stride = C.Config.STREAM_STRIDE
        local i, n = 1, #dedup
        while i <= n do
            local j = math.min(i + stride - 1, n)
            for k=i, j do
                local pos = dedup[k]
                pcall(function() WS:RequestStreamAroundAsync(pos) end)
                pcall(function() lp:RequestStreamAroundAsync(pos) end)
            end
            task.wait()
            i = j + 1
        end
        task.wait(C.Config.STREAM_TIMEOUT)
    end

    local function prefetchForModels(models, hitPartGetter)
        if not C.Config.STREAM_ENABLE or not models or #models == 0 then return end
        local positions = table.create(#models)
        local idx = 0
        for _,m in ipairs(models) do
            local hit = hitPartGetter(m)
            if hit then
                idx = idx + 1
                positions[idx] = hit.Position
            end
        end
        if idx > 0 then
            if idx < #positions then
                for i=idx+1,#positions do positions[i] = nil end
            end
            prefetchPositions(positions)
        end
    end

    local function collectTreesInRadius(roots, origin, radius)
        local out, n = {}, 0
        local function walk(node)
            if not node then return end
            if node:IsA("Model") and isTreeName(node.Name) then
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

    local function chopWave(targetModels, swingDelay, hitPartGetter, isTree)
        local toolName
        for _, n in ipairs(C.Config.ChopPrefer) do
            if findInInventory(n) or (equippedToolName() == n) then
                toolName = n
                break
            end
        end
        if not toolName then
            task.wait(0.35)
            return
        end
        local tool = ensureEquipped(toolName)
        if not tool then
            task.wait(0.35)
            return
        end

        prefetchForModels(targetModels, hitPartGetter)

        for _, mdl in ipairs(targetModels) do
            task.spawn(function()
                local hitPart = hitPartGetter(mdl)
                if not hitPart then return end
                local impactCF = computeImpactCFrame(mdl, hitPart)
                local hitId
                if isTree then
                    hitId = nextPerTreeHitId(mdl)
                    pcall(function()
                        local bucket = attrBucket(mdl)
                        if bucket then bucket:SetAttribute(hitId, true) end
                    end)
                else
                    hitId = tostring(tick()) .. "_" .. C.Config.UID_SUFFIX
                end
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
                local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                if not hrp then
                    task.wait(0.2)
                    continue
                end
                local origin = hrp.Position
                local radius = tonumber(C.State.AuraRadius) or 150
                local targets = collectCharactersInRadius(WS:FindFirstChild("Characters"), origin, radius)
                if #targets > 0 then
                    local batch = targets
                    if C.Config.MAX_TARGETS_PER_WAVE and #batch > C.Config.MAX_TARGETS_PER_WAVE then
                        batch = {}
                        for i = 1, C.Config.MAX_TARGETS_PER_WAVE do
                            batch[i] = targets[i]
                        end
                    end
                    chopWave(batch, C.Config.CHOP_SWING_DELAY, bestCharacterHitPart, false)
                else
                    task.wait(0.3)
                end
            end
        end)
    end

    local function stopCharacterAura()
        running.Character = false
    end

    C.State._treeCursor = C.State._treeCursor or 1

    local function startSmallTreeAura()
        if running.SmallTree then return end
        running.SmallTree = true
        task.spawn(function()
            while running.SmallTree do
                local ch = lp.Character or lp.CharacterAdded:Wait()
                local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                if not hrp then
                    task.wait(0.2)
                    continue
                end

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
                    local batchSize = math.min(C.Config.MAX_TARGETS_PER_WAVE, total)
                    if C.State._treeCursor > total then C.State._treeCursor = 1 end
                    local batch = table.create(batchSize)
                    for i = 1, batchSize do
                        local idx = ((C.State._treeCursor + i - 2) % total) + 1
                        batch[i] = allTrees[idx]
                    end
                    C.State._treeCursor = C.State._treeCursor + batchSize
                    chopWave(batch, C.Config.CHOP_SWING_DELAY, bestTreeHitPart, true)
                else
                    task.wait(0.3)
                end
            end
        end)
    end

    local function stopSmallTreeAura()
        running.SmallTree = false
    end

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

    CombatTab:Slider({
        Title = "Distance",
        Value = { Min = 0, Max = 1000, Default = C.State.AuraRadius or 150 },
        Callback = function(v)
            C.State.AuraRadius = math.clamp(tonumber(v) or 150, 0, 1000)
        end
    })
end
