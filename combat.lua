--=====================================================
-- 1337 Nights | Combat Module
--=====================================================
-- Adds to Combat tab:
--   • “Small Tree Aura” toggle
--   • “Aura Distance” slider (shared radius for combat auras)
--   • Full chop-aura implementation for Small Trees
--=====================================================
--[[====================================================================
 🧠 GPT INTEGRATION NOTE
 ----------------------------------------------------------------------
 Assumes _G.C, _G.R, _G.UI already exist (set by main.lua).
 This module does not return context; it binds to UI.Tabs.Combat directly.
====================================================================]]

return function(C, R, UI)
    -- ---------- guards ----------
    C = C or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Combat, "combat.lua: missing context or Combat tab")

    local Players = C.Services.Players
    local RS      = C.Services.RS
    local WS      = C.Services.WS
    local Run     = C.Services.Run
    local lp      = C.LocalPlayer

    local CombatTab = UI.Tabs.Combat

    -- ---------- shared state ----------
    C.State = C.State or { AuraRadius = 150, Toggles = {} }
    C.Config = C.Config or {
        CHOP_SWING_DELAY = 0.55,
        TREE_NAME        = "Small Tree",
        UID_SUFFIX       = "0000000000",
        ChopPrefer       = { "Chainsaw", "Strong Axe", "Good Axe", "Old Axe" },
    }

    local running = running or {}
    running.SmallTree = running.SmallTree or false

    -- ---------- helpers ----------
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

    local function HitTree(tree, tool, hitId, impactCF)
        local evs = RS:FindFirstChild("RemoteEvents")
        local dmg = evs and evs:FindFirstChild("ToolDamageObject")
        if not dmg then return end
        dmg:InvokeServer(tree, tool, hitId, impactCF)
    end

    -- ---------- core aura logic ----------
    local function chopWaveForTrees(trees, swingDelay)
        local toolName
        for _, n in ipairs(C.Config.ChopPrefer) do
            if findInInventory(n) then toolName = n break end
        end
        if not toolName then task.wait(0.35) return end
        local tool = ensureEquipped(toolName)
        if not tool then task.wait(0.35) return end

        for _, tree in ipairs(trees) do
            task.spawn(function()
                local hitPart = bestTreeHitPart(tree)
                if hitPart then
                    local impactCF = computeImpactCFrame(tree, hitPart)
                    local hitId = nextHitId()
                    HitTree(tree, tool, hitId, impactCF)
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
                local character = lp.Character or lp.CharacterAdded:Wait()
                local hrp = character:FindFirstChild("HumanoidRootPart")
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
                    chopWaveForTrees(trees, C.Config.CHOP_SWING_DELAY)
                else
                    task.wait(0.3)
                end
            end
        end)
    end

    local function stopSmallTreeAura()
        running.SmallTree = false
    end

    -- ---------- UI (Combat tab) ----------
    CombatTab:Section({ Title = "Aura (Trees)" })
    CombatTab:Toggle({
        Title = "Small Tree Aura",
        Value = C.State.Toggles.SmallTreeAura or false,
        Callback = function(on)
            C.State.Toggles.SmallTreeAura = on
            if on then startSmallTreeAura() else stopSmallTreeAura() end
        end
    })

    CombatTab:Section({ Title = "Aura Distance" })
    CombatTab:Slider({
        Title = "Distance",
        Value = { Min = 0, Max = 1000, Default = C.State.AuraRadius or 150 },
        Callback = function(v)
            C.State.AuraRadius = math.clamp(tonumber(v) or 150, 0, 1000)
        end
    })
end
