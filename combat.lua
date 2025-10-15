-- combat.lua — Aura-respecting "server-near" chop: teleport HRP next to each tree for the hit,
-- then snap back to the ORIGINAL position so the aura radius never "grows" while chopping.
-- Includes on-screen logger with Copy/Clear and strict revalidation against the ORIGINAL origin.
return function(C, R, UI)
    --------------------------------------------------------------------
    -- Context
    --------------------------------------------------------------------
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Combat, "combat.lua: missing context or Combat tab")

    local Players = game:GetService("Players")
    local lp      = C.LocalPlayer or Players.LocalPlayer
    local RS      = C.Services.RS
    local WS      = C.Services.WS
    local CombatTab = UI.Tabs.Combat

    C.State  = C.State or { AuraRadius = 150, Toggles = {} }
    C.Config = C.Config or {}

    --------------------------------------------------------------------
    -- Tunables / Features
    --------------------------------------------------------------------
    -- General
    C.Config.CHOP_SWING_DELAY       = C.Config.CHOP_SWING_DELAY       or 0.55
    C.Config.UID_SUFFIX             = C.Config.UID_SUFFIX             or "0000000000"
    C.Config.ChopPrefer             = C.Config.ChopPrefer             or { "Chainsaw", "Strong Axe", "Good Axe", "Old Axe" }
    C.Config.MAX_TARGETS_PER_WAVE   = C.Config.MAX_TARGETS_PER_WAVE   or 80
    C.Config.RANGE_EPS              = C.Config.RANGE_EPS              or 0.25
    C.Config.WORKSPACE_ONLY         = (C.Config.WORKSPACE_ONLY ~= false) -- hard-limit to Workspace trees

    -- Server-near (HRP blink) — ON by default
    C.Config.SERVER_NEAR_ENABLE     = (C.Config.SERVER_NEAR_ENABLE ~= false)
    C.Config.SERVER_NEAR_UP         = C.Config.SERVER_NEAR_UP         or 2.0   -- HRP height above target
    C.Config.SERVER_NEAR_BACK       = C.Config.SERVER_NEAR_BACK       or 0.75  -- offset back from the trunk
    C.Config.SERVER_NEAR_WAIT_BEFORE= C.Config.SERVER_NEAR_WAIT_BEFORE or 0.02 -- yield after blink before Invoke
    C.Config.SERVER_NEAR_WAIT_AFTER = C.Config.SERVER_NEAR_WAIT_AFTER  or 0.03 -- yield after Invoke before return
    C.Config.SERVER_NEAR_SERIAL     = (C.Config.SERVER_NEAR_SERIAL ~= false)  -- process sequentially per wave

    -- Logging
    C.Config.LOG_MAX_LINES          = C.Config.LOG_MAX_LINES or 1000

    local running = { SmallTree = false, Character = false }

    --------------------------------------------------------------------
    -- On-screen Logger (Copy / Clear / Show-Hide)
    --------------------------------------------------------------------
    local LoggerGui = lp:FindFirstChild("PlayerGui") and lp.PlayerGui:FindFirstChild("EdgeDebugLogger")
    if not LoggerGui then
        LoggerGui = Instance.new("ScreenGui")
        LoggerGui.Name = "EdgeDebugLogger"
        LoggerGui.ResetOnSpawn = false
        LoggerGui.IgnoreGuiInset = true
        LoggerGui.Parent = lp:WaitForChild("PlayerGui")

        local Panel = Instance.new("Frame")
        Panel.Name = "Panel"
        Panel.AnchorPoint = Vector2.new(1,1)
        Panel.Position = UDim2.new(1,-12,1,-12)
        Panel.Size = UDim2.new(0,560,0,300)
        Panel.BackgroundColor3 = Color3.fromRGB(18,18,22)
        Panel.BackgroundTransparency = 0.1
        Panel.BorderSizePixel = 0
        Panel.Parent = LoggerGui
        Instance.new("UICorner", Panel).CornerRadius = UDim.new(0,10)

        local Title = Instance.new("TextLabel")
        Title.Name = "Title"
        Title.Text = "1337 Nights • Combat Debug"
        Title.Font = Enum.Font.GothamMedium
        Title.TextSize = 14
        Title.TextColor3 = Color3.fromRGB(230,230,235)
        Title.BackgroundTransparency = 1
        Title.Size = UDim2.new(1, -220, 0, 24)
        Title.Position = UDim2.new(0, 12, 0, 8)
        Title.TextXAlignment = Enum.TextXAlignment.Left
        Title.Parent = Panel

        local ToggleBtn = Instance.new("TextButton")
        ToggleBtn.Name = "Toggle"
        ToggleBtn.Text = "Hide"
        ToggleBtn.Font = Enum.Font.Gotham
        ToggleBtn.TextSize = 13
        ToggleBtn.TextColor3 = Color3.fromRGB(230,230,235)
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(60,60,72)
        ToggleBtn.Size = UDim2.new(0,64,0,24)
        ToggleBtn.Position = UDim2.new(1,-248,0,8)
        ToggleBtn.Parent = Panel
        Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0,6)

        local Clear = Instance.new("TextButton")
        Clear.Name = "Clear"
        Clear.Text = "Clear"
        Clear.Font = Enum.Font.Gotham
        Clear.TextSize = 13
        Clear.TextColor3 = Color3.fromRGB(230,230,235)
        Clear.BackgroundColor3 = Color3.fromRGB(60,60,72)
        Clear.Size = UDim2.new(0,64,0,24)
        Clear.Position = UDim2.new(1,-176,0,8)
        Clear.Parent = Panel
        Instance.new("UICorner", Clear).CornerRadius = UDim.new(0,6)

        local Copy = Instance.new("TextButton")
        Copy.Name = "Copy"
        Copy.Text = "Copy"
        Copy.Font = Enum.Font.Gotham
        Copy.TextSize = 13
        Copy.TextColor3 = Color3.fromRGB(230,230,235)
        Copy.BackgroundColor3 = Color3.fromRGB(60,60,72)
        Copy.Size = UDim2.new(0,64,0,24)
        Copy.Position = UDim2.new(1,-104,0,8)
        Copy.Parent = Panel
        Instance.new("UICorner", Copy).CornerRadius = UDim.new(0,6)

        local Scroll = Instance.new("ScrollingFrame")
        Scroll.Name = "Scroll"
        Scroll.BackgroundTransparency = 0.2
        Scroll.BackgroundColor3 = Color3.fromRGB(28,28,34)
        Scroll.BorderSizePixel = 0
        Scroll.Position = UDim2.new(0, 12, 0, 40)
        Scroll.Size = UDim2.new(1, -24, 1, -52)
        Scroll.ScrollBarThickness = 6
        Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        Scroll.CanvasSize = UDim2.new()
        Scroll.Parent = Panel
        Instance.new("UICorner", Scroll).CornerRadius = UDim.new(0,8)

        local LogBox = Instance.new("TextLabel")
        LogBox.Name = "Log"
        LogBox.Text = ""
        LogBox.Font = Enum.Font.Code
        LogBox.TextXAlignment = Enum.TextXAlignment.Left
        LogBox.TextYAlignment = Enum.TextYAlignment.Top
        LogBox.TextColor3 = Color3.fromRGB(220,220,230)
        LogBox.TextSize = 14
        LogBox.BackgroundTransparency = 1
        LogBox.Size = UDim2.new(1,-12,0,0)
        LogBox.AutomaticSize = Enum.AutomaticSize.Y
        LogBox.Parent = Scroll

        local HiddenCopy = Instance.new("TextBox")
        HiddenCopy.Name = "HiddenCopy"
        HiddenCopy.TextEditable = false
        HiddenCopy.Visible = false
        HiddenCopy.Parent = Panel

        ToggleBtn.MouseButton1Click:Connect(function()
            local s = Scroll.Visible
            Scroll.Visible = not s
            ToggleBtn.Text = Scroll.Visible and "Hide" or "Show"
        end)
        Clear.MouseButton1Click:Connect(function()
            LogBox.Text = ""
            LogBox:SetAttribute("Lines", 0)
        end)
        Copy.MouseButton1Click:Connect(function()
            local txt = LogBox.Text or ""
            if typeof(getgenv) == "function" and typeof(getgenv().setclipboard) == "function" then
                getgenv().setclipboard(txt)
            elseif typeof(setclipboard) == "function" then
                setclipboard(txt)
            else
                HiddenCopy.Text = txt
                HiddenCopy:CaptureFocus()
                HiddenCopy:ReleaseFocus(true)
            end
        end)
    end
    local Panel = LoggerGui.Panel
    local LogBox = Panel.Scroll.Log
    local function ts() return string.format("[%0.2f]", os.clock() % 10000) end
    local function log(s)
        local prev = LogBox.Text
        local new = (prev == "" and (ts().." "..s)) or (prev.."\n"..ts().." "..s)
        LogBox.Text = new
        Panel.Scroll.CanvasPosition = Vector2.new(0, 1e9)
        local lines = (LogBox:GetAttribute("Lines") or 0) + 1
        if lines > C.Config.LOG_MAX_LINES then
            local cut = string.find(new, "\n")
            if cut then LogBox.Text = string.sub(new, cut + 1) end
            lines = C.Config.LOG_MAX_LINES
        end
        LogBox:SetAttribute("Lines", lines)
    end
    local function showLogger(on) LoggerGui.Enabled = on and true or false end
    showLogger(C.State.Toggles.CombatDebug ~= false)
    log(("Logger ready (server_near=%s)"):format(tostring(C.Config.SERVER_NEAR_ENABLE)))

    --------------------------------------------------------------------
    -- Tree catalog / helpers
    --------------------------------------------------------------------
    local TREE_NAMES = { ["Small Tree"]=true, ["Snowy Small Tree"]=true }

    local function findInInventory(name)
        local inv = lp and lp:FindFirstChild("Inventory")
        return inv and inv:FindFirstChild(name) or nil
    end

    local function equippedToolInstance()
        local ch = lp and lp.Character
        return ch and ch:FindFirstChildOfClass("Tool") or nil
    end

    local function SafeEquip(tool)
        if not tool then return end
        local ev = RS:FindFirstChild("RemoteEvents")
        ev = ev and ev:FindFirstChild("EquipItemHandle")
        if ev then
            log("EquipItemHandle -> "..tool.Name)
            ev:FireServer("FireAllClients", tool)
        else
            log("EquipItemHandle missing")
        end
    end

    local function ensureEquipped(wantedName)
        if not wantedName then return nil end
        local ch = lp and lp.Character
        if ch then
            local t = ch:FindFirstChildOfClass("Tool")
            if t and t.Name == wantedName then return t end
        end
        local tool = findInInventory(wantedName)
        if tool then
            SafeEquip(tool)
            local deadline = os.clock() + 0.5
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
        if outward.Magnitude == 0 then return hitPart.CFrame end
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
        if not dmg then
            log("ToolDamageObject missing")
            return
        end
        log(("Invoke ToolDamageObject → model=%s tool=%s id=%s"):format(targetModel and targetModel.Name or "?", tool and tool.Name or "?", tostring(hitId)))
        dmg:InvokeServer(targetModel, tool, hitId, impactCF)
    end

    -- Per-tree attributes for next hit id
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
    -- Range helpers (ALWAYS relative to ORIGINAL origin per wave)
    --------------------------------------------------------------------
    local function withinRadius(pos, origin, radius)
        return (pos - origin).Magnitude <= (radius + C.Config.RANGE_EPS)
    end

    local function collectTreesInRadius_WorkspaceOnly(origin, radius)
        local out, n = {}, 0
        local ok, children = pcall(WS.GetDescendants, WS)
        if not ok or not children then return out end
        for _, node in ipairs(children) do
            repeat
                if not (node:IsA("Model") and TREE_NAMES[node.Name]) then break end
                local trunk = bestTreeHitPart(node)
                if not trunk then break end
                if not withinRadius(trunk.Position, origin, radius) then break end
                n += 1
                out[n] = node
            until true
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
    -- Server-near: move HRP to the tree for a tick, hit, return
    --------------------------------------------------------------------
    local function getHRP()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end

    local function serverNearHit(hrp, originCF, targetModel, hitPart, tool, hitId, impactCF)
        -- Build a placement CFrame right "at" the tree but slightly above & offset back
        local targetPos = hitPart.Position
        local lookCF    = CFrame.lookAt(targetPos + Vector3.new(0, C.Config.SERVER_NEAR_UP, 0), targetPos)
        local placeCF   = lookCF * CFrame.new(0, 0, C.Config.SERVER_NEAR_BACK) -- back along -LookVector

        -- Freeze character a moment to avoid physics tug-of-war
        local humanoid = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
        local oldPS = humanoid and humanoid.PlatformStand
        local oldVel = hrp.AssemblyLinearVelocity
        local oldRotVel = hrp.AssemblyAngularVelocity

        pcall(function()
            if humanoid then humanoid.PlatformStand = true end
            hrp.AssemblyLinearVelocity = Vector3.new()
            hrp.AssemblyAngularVelocity = Vector3.new()
        end)

        -- Blink next to tree → small wait → hit → small wait → snap back
        hrp.CFrame = placeCF
        task.wait(C.Config.SERVER_NEAR_WAIT_BEFORE)
        HitTarget(targetModel, tool, hitId, impactCF)
        task.wait(C.Config.SERVER_NEAR_WAIT_AFTER)
        hrp.CFrame = originCF

        pcall(function()
            hrp.AssemblyLinearVelocity = oldVel
            hrp.AssemblyAngularVelocity = oldRotVel
            if humanoid then humanoid.PlatformStand = oldPS end
        end)
    end

    --------------------------------------------------------------------
    -- Wave executor
    -- IMPORTANT: We capture originCF/pos ONCE and validate/limit strictly against it.
    --------------------------------------------------------------------
    local function chopWave(targetModels, swingDelay, hitPartGetter, isTree)
        -- Tool
        local toolName
        do
            local eq = equippedToolInstance()
            for _, n in ipairs(C.Config.ChopPrefer) do
                if (eq and eq.Name == n) or findInInventory(n) then toolName = n break end
            end
        end
        if not toolName then
            log("No preferred tool available")
            task.wait(0.35); return
        end
        local tool = ensureEquipped(toolName)
        if not tool then
            log("Tool equip failed: "..toolName)
            task.wait(0.35); return
        end

        -- Capture ORIGINAL origin once
        local hrp = getHRP()
        if not hrp then log("No HRP"); task.wait(0.25); return end
        local originCF  = hrp.CFrame
        local originPos = originCF.Position
        local radius    = tonumber(C.State.AuraRadius) or 150

        -- Strictly filter targets vs ORIGINAL origin (before any movement)
        local filtered = {}
        for _, mdl in ipairs(targetModels) do
            local hitPart = hitPartGetter(mdl)
            if hitPart and withinRadius(hitPart.Position, originPos, radius) then
                filtered[#filtered+1] = mdl
            end
        end
        if #filtered == 0 then
            log(("No targets within radius=%.1f"):format(radius))
            task.wait(0.2); return
        end

        -- Execute hits — SERIAL if blinking HRP, otherwise parallel is fine
        local function doOne(mdl)
            local hitPart = hitPartGetter(mdl)
            if not hitPart then
                log("No hit part: "..(mdl and mdl.Name or "?"))
                return
            end

            -- Revalidate AGAIN vs ORIGINAL origin (in case it moved)
            local d = (hitPart.Position - originPos).Magnitude
            if d > (radius + C.Config.RANGE_EPS) then
                log(string.format("SKIP out-of-range %s d=%.1f > r=%.1f", mdl.Name, d, radius))
                return
            end

            -- Build hitId and impact
            local impactCF = computeImpactCFrame(mdl, hitPart)
            local hitId
            if isTree then
                hitId = nextPerTreeHitId(mdl)
                pcall(function()
                    local bucket = attrBucket(mdl); if bucket then bucket:SetAttribute(hitId, true) end
                end)
            else
                hitId = tostring(tick()) .. "_" .. C.Config.UID_SUFFIX
            end

            if C.Config.SERVER_NEAR_ENABLE then
                log(string.format("SERVER-NEAR %s d=%.1f (r=%.1f) using %s", mdl.Name, d, radius, tool.Name))
                serverNearHit(hrp, originCF, mdl, hitPart, tool, hitId, impactCF)
            else
                log(string.format("Hit %s at d=%.1f (r=%.1f) using %s", mdl.Name, d, radius, tool.Name))
                HitTarget(mdl, tool, hitId, impactCF)
            end
        end

        if C.Config.SERVER_NEAR_ENABLE and C.Config.SERVER_NEAR_SERIAL then
            for _, mdl in ipairs(filtered) do
                doOne(mdl)
                task.wait(0.01) -- tiny spacing to avoid replication hitching
            end
        else
            for _, mdl in ipairs(filtered) do
                task.spawn(doOne, mdl)
            end
        end

        task.wait(swingDelay)
    end

    --------------------------------------------------------------------
    -- Collectors (Workspace-only) and Auras
    --------------------------------------------------------------------
    local function collectTreesInRadius_WorkspaceOnly(origin, radius)
        local out, n = {}, 0
        local ok, children = pcall(WS.GetDescendants, WS)
        if not ok or not children then return out end
        for _, node in ipairs(children) do
            repeat
                if not (node:IsA("Model") and TREE_NAMES[node.Name]) then break end
                local trunk = bestTreeHitPart(node); if not trunk then break end
                if not withinRadius(trunk.Position, origin, radius) then break end
                n += 1; out[n] = node
            until true
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
                local hit = bestCharacterHitPart(mdl); if not hit then break end
                if not withinRadius(hit.Position, origin, radius) then break end
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

    local function startCharacterAura()
        if running.Character then return end
        running.Character = true
        task.spawn(function()
            while running.Character do
                local ch = lp.Character or lp.CharacterAdded:Wait()
                local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                if not hrp then log("No HRP (character aura)"); task.wait(0.2); continue end
                local origin = hrp.Position
                local radius = tonumber(C.State.AuraRadius) or 150
                local targets = collectCharactersInRadius(WS:FindFirstChild("Characters"), origin, radius)
                log("Characters in range: "..tostring(#targets))
                if #targets > 0 then
                    local batch = targets
                    if C.Config.MAX_TARGETS_PER_WAVE and #batch > C.Config.MAX_TARGETS_PER_WAVE then
                        local trimmed = {}
                        for i=1, C.Config.MAX_TARGETS_PER_WAVE do trimmed[i] = batch[i] end
                        batch = trimmed
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
                local ch = lp.Character or lp.CharacterAdded:Wait()
                local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                if not hrp then log("No HRP (tree aura)"); task.wait(0.2); continue end

                local origin = hrp.Position
                local radius = tonumber(C.State.AuraRadius) or 150
                local allTrees = collectTreesInRadius_WorkspaceOnly(origin, radius)
                local total = #allTrees
                log("Trees in range: "..tostring(total).." (radius="..tostring(radius)..")")

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
        Title = "Show Combat Debug",
        Value = C.State.Toggles.CombatDebug or true,
        Callback = function(on) C.State.Toggles.CombatDebug = on; showLogger(on) end
    })

    CombatTab:Toggle({
        Title = "Character Aura",
        Value = C.State.Toggles.CharacterAura or false,
        Callback = function(on) C.State.Toggles.CharacterAura = on; if on then startCharacterAura() else stopCharacterAura() end
    })

    CombatTab:Toggle({
        Title = "Small Tree Aura",
        Value = C.State.Toggles.SmallTreeAura or false,
        Callback = function(on) C.State.Toggles.SmallTreeAura = on; if on then startSmallTreeAura() else stopSmallTreeAura() end
    })

    CombatTab:Slider({
        Title = "Distance",
        Value = { Min = 0, Max = 1000, Default = C.State.AuraRadius or 150 },
        Callback = function(v)
            C.State.AuraRadius = math.clamp(tonumber(v) or 150, 0, 1000)
            log("Set AuraRadius to "..tostring(C.State.AuraRadius))
        end
    })
end
