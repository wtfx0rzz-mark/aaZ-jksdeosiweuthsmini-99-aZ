return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Combat, "combat.lua: missing context or Combat tab")

    local RS = C.Services.RS
    local WS = C.Services.WS
    local lp = C.LocalPlayer
    local Run = C.Services.Run or game:GetService("RunService")
    local CombatTab = UI.Tabs.Combat

    C.State  = C.State or { AuraRadius = 150, Toggles = {} }
    C.Config = C.Config or {}

    local TUNE = C.Config
    TUNE.CHOP_SWING_DELAY       = TUNE.CHOP_SWING_DELAY       or 0.50
    TUNE.TREE_NAME              = TUNE.TREE_NAME              or "Small Tree"
    TUNE.UID_SUFFIX             = TUNE.UID_SUFFIX             or "0000000000"
    TUNE.ChopPrefer             = TUNE.ChopPrefer             or { "Chainsaw", "Strong Axe", "Ice Axe", "Good Axe", "Old Axe" }
    TUNE.MAX_TARGETS_PER_WAVE   = TUNE.MAX_TARGETS_PER_WAVE   or 20
    TUNE.CHAR_MAX_PER_WAVE      = TUNE.CHAR_MAX_PER_WAVE      or 20
    TUNE.CHAR_DEBOUNCE_SEC      = TUNE.CHAR_DEBOUNCE_SEC      or 0.4
    TUNE.CHAR_HIT_STEP_WAIT     = TUNE.CHAR_HIT_STEP_WAIT     or 0.02
    TUNE.CHAR_SORT              = (TUNE.CHAR_SORT ~= false)
    TUNE.SCAN_BUDGET_TREES      = TUNE.SCAN_BUDGET_TREES      or 250
    TUNE.SCAN_BUDGET_CHARS      = TUNE.SCAN_BUDGET_CHARS      or 120

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

    local function dist2(a, b)
        local v = a - b
        return v.X*v.X + v.Y*v.Y + v.Z*v.Z
    end

    local Index = {
        Trees = {}, TreePart = setmetatable({}, {__mode="k"}), TreeArr = {},
        Chars = {}, CharArr = {},
        treeCursor = 1, charCursor = 1
    }

    local function wantTreeName(n) return TREE_NAMES[n] or isBigTreeName(n) end

    local function addTree(m)
        if Index.Trees[m] then return end
        Index.Trees[m] = true
        Index.TreeArr[#Index.TreeArr+1] = m
    end
    local function remTree(m)
        if not Index.Trees[m] then return end
        Index.Trees[m] = nil
        Index.TreePart[m] = nil
    end

    local function addChar(m)
        if Index.Chars[m] then return end
        Index.Chars[m] = true
        Index.CharArr[#Index.CharArr+1] = m
    end
    local function remChar(m)
        if not Index.Chars[m] then return end
        Index.Chars[m] = nil
        hrpCache[m] = nil
    end

    local function seedTrees(root)
        if not root then return end
        for _,d in ipairs(root:GetDescendants()) do
            if d:IsA("Model") and wantTreeName(d.Name) then addTree(d) end
        end
    end

    local function hookTreeRoot(root)
        if not root then return end
        seedTrees(root)
        root.DescendantAdded:Connect(function(d)
            if d:IsA("Model") and wantTreeName(d.Name) then addTree(d) end
        end)
        root.DescendantRemoving:Connect(function(d)
            if d:IsA("Model") then remTree(d) end
        end)
    end

    local function ensureWatchers()
        hookTreeRoot(WS)
        hookTreeRoot(RS:FindFirstChild("Assets"))
        hookTreeRoot(RS:FindFirstChild("CutsceneSets"))
        local cf = WS:FindFirstChild("Characters")
        if cf then
            for _,ch in ipairs(cf:GetChildren()) do if ch:IsA("Model") then addChar(ch) end end
            cf.ChildAdded:Connect(function(m) if m:IsA("Model") then addChar(m) end end)
            cf.ChildRemoved:Connect(function(m) if m:IsA("Model") then remChar(m) end end)
        end
    end

    ensureWatchers()

    local function collectTreesInRadius(_, origin, radius)
        local includeBig = C.State.Toggles.BigTreeAura == true
        local r2 = radius*radius
        local out, taken, scanned = {}, 0, 0
        local N = #Index.TreeArr
        if N == 0 then return out end
        local cur = Index.treeCursor
        local budget = TUNE.SCAN_BUDGET_TREES
        while scanned < N and taken < TUNE.MAX_TARGETS_PER_WAVE and budget > 0 do
            local m = Index.TreeArr[cur]
            scanned = scanned + 1
            budget = budget - 1
            cur = cur + 1
            if cur > N then cur = 1 end
            if m and m.Parent and m:IsA("Model") then
                local nm = m.Name
                if TREE_NAMES[nm] or (includeBig and isBigTreeName(nm)) then
                    local part = Index.TreePart[m]
                    if not part or not part.Parent then
                        part = bestTreeHitPart(m)
                        Index.TreePart[m] = part
                    end
                    if part then
                        if dist2(part.Position, origin) <= r2 then
                            out[#out+1] = m
                            taken = taken + 1
                        end
                    end
                end
            end
        end
        Index.treeCursor = cur
        return out
    end

    local function collectCharactersInRadius(charsFolder, origin, radius)
        local r2 = radius*radius
        local out, taken, scanned = {}, 0, 0
        local arr = Index.CharArr
        local N = #arr
        if N == 0 then
            if charsFolder then
                for _,m in ipairs(charsFolder:GetChildren()) do
                    if m:IsA("Model") then addChar(m) end
                end
                arr = Index.CharArr
                N = #arr
            end
        end
        local cur = Index.charCursor
        local budget = TUNE.SCAN_BUDGET_CHARS
        while scanned < N and taken < TUNE.CHAR_MAX_PER_WAVE and budget > 0 do
            local mdl = arr[cur]
            scanned = scanned + 1
            budget = budget - 1
            cur = cur + 1
            if cur > N then cur = 1 end
            if mdl and mdl.Parent and mdl:IsA("Model") then
                local nameLower = (mdl.Name or ""):lower()
                if not string.find(nameLower, "horse", 1, true) then
                    local dp = charDistancePart(mdl)
                    if dp and dist2(dp.Position, origin) <= r2 then
                        out[#out+1] = mdl
                        taken = taken + 1
                    end
                end
            end
        end
        Index.charCursor = cur
        if TUNE.CHAR_SORT and #out > 1 then
            table.sort(out, function(a, b)
                local pa, pb = charDistancePart(a), charDistancePart(b)
                local da = pa and dist2(pa.Position, origin) or math.huge
                local db = pb and dist2(pb.Position, origin) or math.huge
                if da == db then return (a.Name or "") < (b.Name or "") end
                return da < db
            end)
        end
        return out
    end

    local lastHitAt = setmetatable({}, {__mode="k"})
    local function chopWave(targetModels, swingDelay, hitPartGetter, isTree)
        local toolName
        if isTree and C.State.Toggles.BigTreeAura then
            if hasStrongAxe() then
                toolName = "Strong Axe"
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
                local impactCF = computeImpactCFrame(mdl, hitPart)
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
                    local targets = collectCharactersInRadius(WS:FindFirstChild("Characters"), origin, radius)
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
                    local batch = collectTreesInRadius(nil, origin, radius)
                    if #batch > 0 then
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
        Title = "Big Trees (requires Strong Axe)",
        Value = C.State.Toggles.BigTreeAura or false,
        Callback = function(on)
            if on then
                if hasStrongAxe() then
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
            if C.State.Toggles.BigTreeAura and not hasStrongAxe() then
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
