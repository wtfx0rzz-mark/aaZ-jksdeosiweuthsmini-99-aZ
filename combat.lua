--=====================================================
-- 1337 Nights | Combat Module
--=====================================================
-- Adds to Combat tab:
--   • Character Aura (NPCs under Workspace.Characters, excludes *horse*)
--   • Small Tree Aura (targets "Small Tree" and "Snowy Small Tree")
--   • Shared Aura Distance slider
--   • Per-tree hit attributes under Model.HitRegisters:
--       1_0000000000, 2_0000000000, 3_0000000000, ...
--   • Round-robin batches so ALL trees in range get processed over time
--   • TEST MODES:
--       - Use Camera Origin (spoofs from camera with adjustable offset)
--       - Use Spoof Marker (draggable neon sphere as custom origin)
--=====================================================
--[[====================================================================
 🧠 GPT INTEGRATION NOTE
 ----------------------------------------------------------------------
 Runs inside the unified 1337 Nights runtime:

     _G.C  → Global Config, State, Services, Shared tables
     _G.R  → Shared runtime helpers
     _G.UI → WindUI instance (window + tabs)

 • Do not return C/R/UI; main.lua owns setup and loading.
 • Each aura runs in its own thread; both honor: C.State.AuraRadius
 • NPCs whose name contains "horse" (case-insensitive) are excluded.
====================================================================]]

return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Combat, "combat.lua: missing context or Combat tab")

    local RS   = C.Services.RS
    local WS   = C.Services.WS
    local Run  = C.Services.Run
    local lp   = C.LocalPlayer
    local UIS  = game:GetService("UserInputService")
    local CAS  = game:GetService("ContextActionService")
    local CombatTab = UI.Tabs.Combat

    C.State  = C.State or { AuraRadius = 150, Toggles = {} }
    C.State.Test = C.State.Test or {
        UseCameraOrigin = false,
        CamOffset       = 0,
        UseSpoofMarker  = false,
    }
    C.Config = C.Config or {}
    -- Tunables
    C.Config.CHOP_SWING_DELAY     = C.Config.CHOP_SWING_DELAY     or 0.55
    C.Config.TREE_NAME            = C.Config.TREE_NAME            or "Small Tree"
    C.Config.UID_SUFFIX           = C.Config.UID_SUFFIX           or "0000000000"
    C.Config.ChopPrefer           = C.Config.ChopPrefer           or { "Chainsaw", "Strong Axe", "Good Axe", "Old Axe" }
    C.Config.MAX_TARGETS_PER_WAVE = C.Config.MAX_TARGETS_PER_WAVE or 80 -- how many we hit per wave

    local running = { SmallTree = false, Character = false }
    local TREE_NAMES = { ["Small Tree"]=true, ["Snowy Small Tree"]=true }

    --------------------------------------------------------------------
    -- Spoof Origin Marker (create/drag/cleanup)
    --------------------------------------------------------------------
    local markerConn = { began=nil, ended=nil, stepped=nil, action=nil }
    local markerDragging = false

    local function getMouse()
        -- works on LocalScript contexts
        return lp and lp:GetMouse()
    end

    local function ensureMarker()
        local mk = WS:FindFirstChild("AuraOriginMarker")
        if mk and mk:IsA("BasePart") then return mk end

        mk = Instance.new("Part")
        mk.Name = "AuraOriginMarker"
        mk.Anchored = true
        mk.CanCollide = false
        mk.Material = Enum.Material.Neon
        mk.Shape = Enum.PartType.Ball
        mk.Color = Color3.fromRGB(255, 255, 0) -- yellow
        mk.Size = Vector3.new(2, 2, 2)
        mk.Transparency = 0.15
        mk.TopSurface = Enum.SurfaceType.Smooth
        mk.BottomSurface = Enum.SurfaceType.Smooth

        local light = Instance.new("PointLight")
        light.Brightness = 2
        light.Range = 16
        light.Color = mk.Color
        light.Parent = mk

        -- drop at current aura origin
        local origin = Vector3.new()
        local ch = lp and lp.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        origin = (hrp and hrp.Position) or (WS.CurrentCamera and WS.CurrentCamera.CFrame.Position) or origin

        mk.CFrame = CFrame.new(origin)
        mk.Parent = WS
        return mk
    end

    local function destroyMarker()
        local mk = WS:FindFirstChild("AuraOriginMarker")
        if mk then mk:Destroy() end
    end

    local function disconnectMarkerConns()
        for k,conn in pairs(markerConn) do
            if typeof(conn) == "RBXScriptConnection" then
                conn:Disconnect()
            end
            markerConn[k] = nil
        end
        markerDragging = false
    end

    local function startMarkerDragSystem()
        disconnectMarkerConns()
        local mk = ensureMarker()
        local mouse = getMouse()
        if not mouse then return end

        -- Hold LMB to drag marker to mouse.Hit
        markerConn.began = UIS.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                markerDragging = true
            end
        end)
        markerConn.ended = UIS.InputEnded:Connect(function(input, gpe)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                markerDragging = false
            end
        end)

        markerConn.stepped = Run.RenderStepped:Connect(function()
            if not mk.Parent then
                mk = ensureMarker()
            end
            if markerDragging then
                local hit = mouse.Hit
                if hit then
                    -- place slightly above surface to avoid z-fighting
                    local p = hit.p + Vector3.new(0, mk.Size.Y * 0.5, 0)
                    mk.CFrame = CFrame.new(p)
                end
            end
        end)
    end

    local function stopMarkerDragSystem()
        disconnectMarkerConns()
        destroyMarker()
    end

    --------------------------------------------------------------------
    -- Aura origin (Marker > Camera test > Player)
    --------------------------------------------------------------------
    local function getAuraOrigin()
        if C.State.Test.UseSpoofMarker then
            local mk = WS:FindFirstChild("AuraOriginMarker")
            if mk and mk:IsA("BasePart") then
                return mk.Position
            end
        end
        if C.State.Test.UseCameraOrigin then
            local cam = WS.CurrentCamera
            if cam then
                local pos = cam.CFrame.Position + cam.CFrame.LookVector * (tonumber(C.State.Test.CamOffset) or 0)
                return pos
            end
        end
        local ch = lp.Character
        if ch then
            local hrp = ch:FindFirstChild("HumanoidRootPart")
            if hrp then return hrp.Position end
        end
        return Vector3.new()
    end

    --------------------------------------------------------------------
    -- Inventory / tool helpers
    --------------------------------------------------------------------
    local function findInInventory(name)
        local inv = lp and lp:FindFirstChild("Inventory")
        return inv and inv:FindFirstChild(name) or nil
    end

    private = nil
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

    --------------------------------------------------------------------
    -- Target part finders
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

    local function bestCharacterHitPart(model)
        if not model or not model:IsA("Model") then return nil end
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then return hrp end
        if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
        return model:FindFirstChildWhichIsA("BasePart")
    end

    --------------------------------------------------------------------
    -- Impact & damage
    --------------------------------------------------------------------
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
    -- Attribute helpers (per-tree sequencing)
    --------------------------------------------------------------------
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

    --------------------------------------------------------------------
    -- Collectors + sorting
    --------------------------------------------------------------------
    local function collectTreesInRadius(roots, origin, radius)
        local out, n = {}, 0
        local function walk(node)
            if not node then return end
            if node:IsA("Model") and TREE_NAMES[node.Name] then
                local trunk = bestTreeHitPart(node)
                if trunk then
                    local d = (trunk.Position - origin).Magnitude
                    if d <= radius then
                        n += 1
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

    --------------------------------------------------------------------
    -- Wave executor
    --------------------------------------------------------------------
    local function findInInventoryAny(prefer)
        for _, name in ipairs(prefer) do
            local t = findInInventory(name)
            if t then return t end
        end
    end

    local function chopWave(targetModels, swingDelay, hitPartGetter, isTree)
        local toolInInv = findInInventoryAny(C.Config.ChopPrefer)
        if not toolInInv then task.wait(0.35) return end
        local tool = ensureEquipped(toolInInv.Name)
        if not tool then task.wait(0.35) return end

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

        task.wait(swingDelay) -- between waves
    end

    --------------------------------------------------------------------
    -- Auras
    --------------------------------------------------------------------
    local function startCharacterAura()
        if running.Character then return end
        running.Character = true
        task.spawn(function()
            while running.Character do
                local origin = getAuraOrigin()
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
    local function stopCharacterAura() running.Character = false end

    C.State._treeCursor = C.State._treeCursor or 1
    local function startSmallTreeAura()
        if running.SmallTree then return end
        running.SmallTree = true
        task.spawn(function()
            while running.SmallTree do
                local origin = getAuraOrigin()
                local radius = tonumber(C.State.AuraRadius) or 150

                local roots = {
                    WS,                                     -- Map, Foliage, Landmarks, FakeForest, etc.
                    RS:FindFirstChild("Assets"),            -- ReplicatedStorage.Assets (CutsceneSets.*.Decor.*)
                    RS:FindFirstChild("CutsceneSets"),      -- fallback if Assets nests differently
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
    local function stopSmallTreeAura() running.SmallTree = false end

    --------------------------------------------------------------------
    -- UI
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

    CombatTab:Slider({
        Title = "Distance",
        Value = { Min = 0, Max = 1000, Default = C.State.AuraRadius or 150 },
        Callback = function(v)
            C.State.AuraRadius = math.clamp(tonumber(v) or 150, 0, 1000)
        end
    })

    -- ===== Test controls =====
    CombatTab:Toggle({
        Title = "Use Camera Origin (Test)",
        Value = C.State.Test.UseCameraOrigin or false,
        Callback = function(on)
            C.State.Test.UseCameraOrigin = on and true or false
        end
    })
    CombatTab:Slider({
        Title = "Camera Offset (Test)",
        Value = { Min = -1000, Max = 1000, Default = C.State.Test.CamOffset or 0 },
        Callback = function(v)
            C.State.Test.CamOffset = math.clamp(tonumber(v) or 0, -1000, 1000)
        end
    })
    CombatTab:Toggle({
        Title = "Use Spoof Marker (Test)",
        Value = C.State.Test.UseSpoofMarker or false,
        Callback = function(on)
            C.State.Test.UseSpoofMarker = on and true or false
            if on then
                startMarkerDragSystem()
            else
                stopMarkerDragSystem() -- removes marker & resets drag
            end
        end
    })
end
