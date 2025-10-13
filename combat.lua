--=====================================================
-- 1337 Nights | Combat Module
--=====================================================
-- Adds to Combat tab:
--   • “Small Tree Aura” toggle + distance slider
--   • “Character Aura” toggle + distance slider
--   • Both loops use the same damage pipeline:
--       - Tool priority equip (Chainsaw → Strong Axe → Good Axe → Old Axe)
--       - Computes best hit part (Trunk or HRP)
--       - Performs InvokeServer() hits at fixed swing delay
--=====================================================
--[[====================================================================
 🧠 GPT INTEGRATION NOTE
 ----------------------------------------------------------------------
 This module runs within the unified 1337 Nights global runtime, shared
 by all modules (main.lua, visuals.lua, player.lua, etc.):

     _G.C  → Global Config, State, Services, Shared tables
     _G.R  → Shared runtime helpers
     _G.UI → WindUI instance (window + tabs)

 ✅ EXPECTED BEHAVIOR:
   • Never return `UI`, `C`, or `R` from this module
   • All references should assume these exist globally
   • Each aura or feature should run in its own thread loop
   • Avoid cyclic dependencies or direct requires — main.lua handles loading

 ⚙️ DESIGN GOALS:
   • Keep Tree and Character Aura isolated (independent toggles)
   • Maintain shared equip + impact logic for RPC consistency
   • Honor per-aura distance sliders (C.State.AuraRadius / CharacterAuraRadius)
   • Exclude NPCs whose name contains "horse" (case-insensitive)
====================================================================]]
return function(C, R, UI)
    C = C or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Combat, "combat.lua: missing context")

    local RS  = C.Services.RS
    local WS  = C.Services.WS
    local lp  = C.LocalPlayer

    C.State  = C.State or { AuraRadius = 150, CharacterAuraRadius = 150, Toggles = {} }
    C.Config = C.Config or {
        CHOP_SWING_DELAY = 0.55,
        TREE_NAME        = "Small Tree",
        UID_SUFFIX       = "0000000000",
        ChopPrefer       = { "Chainsaw", "Strong Axe", "Good Axe", "Old Axe" },
    }

    local CombatTab = UI.Tabs.Combat
    local running = running or {}
    running.SmallTree = running.SmallTree or false
    running.Character = running.Character or false

    local _hitCounter = 0
    local function nextHitId()
        _hitCounter += 1
        return tostring(_hitCounter) .. "_" .. C.Config.UID_SUFFIX
    end

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

    local function chopWave(tModels, swingDelay, hitPartGetter)
        local toolName
        for _, n in ipairs(C.Config.ChopPrefer) do
            if findInInventory(n) then toolName = n break end
        end
        if not toolName then task.wait(0.35) return end
        local tool = ensureEquipped(toolName)
        if not tool then task.wait(0.35) return end

        for _, mdl in ipairs(tModels) do
            task.spawn(function()
                local hitPart = hitPartGetter(mdl)
                if hitPart then
                    local impactCF = computeImpactCFrame(mdl, hitPart)
                    local hitId = nextHitId()
                    HitTarget(mdl, tool, hitId, impactCF)
                end
            end)
        end

        task.wait(swingDelay)
    end

    local function startSmallTreeAura()
        if running.SmallTree then return end
        running.SmallTree = true
        task.spawn(function()
            while running.SmallTree do
                local ch = lp.Character or lp.CharacterAdded:Wait()
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if not hrp then task.wait(0.2) break end

                local origin = hrp.Position
                local radius = tonumber(C.State.AuraRadius) or 150
                local trees = {}
                local map = WS:FindFirstChild("Map")

                local function scan(folder)
                    if not folder then return end
                    for _, obj in ipairs(folder:GetChildren()) do
                        if obj:IsA("Model") and obj.Name == C.Config.TREE_NAME then
                            local trunk = bestTreeHitPart(obj)
                            if trunk and (trunk.Position - origin).Magnitude <= radius then
                                trees[#trees+1] = obj
                            end
                        end
                    end
                end

                if map then
                    scan(map:FindFirstChild("Foliage"))
                    scan(map:FindFirstChild("Landmarks"))
                end

                if #trees > 0 then
                    chopWave(trees, C.Config.CHOP_SWING_DELAY, bestTreeHitPart)
                else
                    task.wait(0.3)
                end
            end
        end)
    end

    local function stopSmallTreeAura() running.SmallTree = false end

    local function startCharacterAura()
        if running.Character then return end
        running.Character = true
        task.spawn(function()
            while running.Character do
                local ch = lp.Character or lp.CharacterAdded:Wait()
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if not hrp then task.wait(0.2) break end

                local origin = hrp.Position
                local radius = tonumber(C.State.CharacterAuraRadius) or 150
                local targets = {}
                local charsFolder = WS:FindFirstChild("Characters")

                if charsFolder then
                    for _, obj in ipairs(charsFolder:GetChildren()) do
                        repeat
                            if not obj:IsA("Model") then break end
                            local nameLower = string.lower(obj.Name or "")
                            if string.find(nameLower, "horse", 1, true) then break end
                            local hit = bestCharacterHitPart(obj)
                            if not hit then break end
                            if (hit.Position - origin).Magnitude > radius then break end
                            targets[#targets+1] = obj
                        until true
                    end
                end

                if #targets > 0 then
                    chopWave(targets, C.Config.CHOP_SWING_DELAY, bestCharacterHitPart)
                else
                    task.wait(0.3)
                end
            end
        end)
    end

    local function stopCharacterAura() running.Character = false end

    -- UI: Trees
    CombatTab:Section({ Title = "Aura (Trees)" })
    CombatTab:Toggle({
        Title = "Small Tree Aura",
        Value = C.State.Toggles.SmallTreeAura or false,
        Callback = function(on)
            C.State.Toggles.SmallTreeAura = on
            if on then startSmallTreeAura() else stopSmallTreeAura() end
        end
    })
    CombatTab:Section({ Title = "Aura Distance (Trees)" })
    CombatTab:Slider({
        Title = "Distance",
        Value = { Min = 0, Max = 1000, Default = C.State.AuraRadius or 150 },
        Callback = function(v)
            C.State.AuraRadius = math.clamp(tonumber(v) or 150, 0, 1000)
        end
    })

    -- UI: Characters (NPCs)
    CombatTab:Section({ Title = "Character Aura" })
    CombatTab:Toggle({
        Title = "Character Aura",
        Value = C.State.Toggles.CharacterAura or false,
        Callback = function(on)
            C.State.Toggles.CharacterAura = on
            if on then startCharacterAura() else stopCharacterAura() end
        end
    })
    CombatTab:Section({ Title = "Aura Distance (Characters)" })
    CombatTab:Slider({
        Title = "Distance",
        Value = { Min = 0, Max = 1000, Default = C.State.CharacterAuraRadius or (C.State.AuraRadius or 150) },
        Callback = function(v)
            C.State.CharacterAuraRadius = math.clamp(tonumber(v) or 150, 0, 1000)
        end
    })
end
