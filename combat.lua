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
    C.Config.CHOP_SWING_DELAY     = C.Config.CHOP_SWING_DELAY     or 0.55
    C.Config.TREE_NAME            = C.Config.TREE_NAME            or "Small Tree"
    C.Config.UID_SUFFIX           = C.Config.UID_SUFFIX           or "0000000000"
    C.Config.ChopPrefer           = C.Config.ChopPrefer           or { "Chainsaw", "Strong Axe", "Good Axe", "Old Axe" }
    C.Config.MAX_TARGETS_PER_WAVE = C.Config.MAX_TARGETS_PER_WAVE or 80

    local running = { SmallTree = false, Character = false }

    local LoggerGui = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui") and game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("EdgeDebugLogger")
    if not LoggerGui then
        LoggerGui = Instance.new("ScreenGui")
        LoggerGui.Name = "EdgeDebugLogger"
        LoggerGui.ResetOnSpawn = false
        LoggerGui.IgnoreGuiInset = true
        LoggerGui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
        local Frame = Instance.new("Frame")
        Frame.Name = "Panel"
        Frame.AnchorPoint = Vector2.new(1,1)
        Frame.Position = UDim2.new(1,-12,1,-12)
        Frame.Size = UDim2.new(0,480,0,260)
        Frame.BackgroundColor3 = Color3.fromRGB(18,18,22)
        Frame.BackgroundTransparency = 0.1
        Frame.BorderSizePixel = 0
        Frame.Parent = LoggerGui
        local UICorner = Instance.new("UICorner", Frame)
        UICorner.CornerRadius = UDim.new(0,10)

        local Title = Instance.new("TextLabel")
        Title.Name = "Title"
        Title.Text = "1337 Nights • Combat Debug"
        Title.Font = Enum.Font.GothamMedium
        Title.TextSize = 14
        Title.TextColor3 = Color3.fromRGB(230,230,235)
        Title.BackgroundTransparency = 1
        Title.Size = UDim2.new(1, -120, 0, 24)
        Title.Position = UDim2.new(0, 12, 0, 8)
        Title.TextXAlignment = Enum.TextXAlignment.Left
        Title.Parent = Frame

        local Close = Instance.new("TextButton")
        Close.Name = "Close"
        Close.Text = "×"
        Close.Font = Enum.Font.GothamBold
        Close.TextSize = 18
        Close.TextColor3 = Color3.fromRGB(230,230,235)
        Close.BackgroundColor3 = Color3.fromRGB(45,45,55)
        Close.Size = UDim2.new(0,28,0,24)
        Close.Position = UDim2.new(1,-32,0,8)
        Close.Parent = Frame
        local CloseCorner = Instance.new("UICorner", Close)
        CloseCorner.CornerRadius = UDim.new(0,6)

        local Copy = Instance.new("TextButton")
        Copy.Name = "Copy"
        Copy.Text = "Copy"
        Copy.Font = Enum.Font.Gotham
        Copy.TextSize = 13
        Copy.TextColor3 = Color3.fromRGB(230,230,235)
        Copy.BackgroundColor3 = Color3.fromRGB(60,60,72)
        Copy.Size = UDim2.new(0,64,0,24)
        Copy.Position = UDim2.new(1,-100,0,8)
        Copy.Parent = Frame
        local CopyCorner = Instance.new("UICorner", Copy)
        CopyCorner.CornerRadius = UDim.new(0,6)

        local Clear = Instance.new("TextButton")
        Clear.Name = "Clear"
        Clear.Text = "Clear"
        Clear.Font = Enum.Font.Gotham
        Clear.TextSize = 13
        Clear.TextColor3 = Color3.fromRGB(230,230,235)
        Clear.BackgroundColor3 = Color3.fromRGB(60,60,72)
        Clear.Size = UDim2.new(0,64,0,24)
        Clear.Position = UDim2.new(1,-168,0,8)
        Clear.Parent = Frame
        local ClearCorner = Instance.new("UICorner", Clear)
        ClearCorner.CornerRadius = UDim.new(0,6)

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
        Scroll.Parent = Frame
        local ScrollCorner = Instance.new("UICorner", Scroll)
        ScrollCorner.CornerRadius = UDim.new(0,8)

        local LogBox = Instance.new("TextLabel")
        LogBox.Name = "Log"
        LogBox.Text = ""
        LogBox.TextWrapped = false
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
        HiddenCopy.Parent = Frame

        Close.MouseButton1Click:Connect(function()
            LoggerGui.Enabled = false
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
    local function ts()
        return string.format("[%0.2f]", os.clock() % 10000)
    end
    local function log(s)
        local prev = LogBox.Text
        local new = (prev == "" and (ts().." "..s)) or (prev.."\n"..ts().." "..s)
        LogBox.Text = new
        Panel.Scroll.CanvasPosition = Vector2.new(0, 1e9)
        local lines = (LogBox:GetAttribute("Lines") or 0) + 1
        if lines > 600 then
            local cut = string.find(new, "\n")
            if cut then
                LogBox.Text = string.sub(new, cut + 1)
            end
            lines = 600
        end
        LogBox:SetAttribute("Lines", lines)
    end
    local function showLogger(on)
        LoggerGui.Enabled = on and true or false
    end

    local TREE_NAMES = { ["Small Tree"]=true, ["Snowy Small Tree"]=true }

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
            if t and t.Name == wantedName then
                log("Tool already equipped: "..wantedName)
                return t
            end
        end
        local tool = findInInventory(wantedName)
        if tool then
            log("Equipping from inventory: "..wantedName)
            SafeEquip(tool)
            local deadline = os.clock() + 0.5
            repeat
                task.wait()
                ch = lp and lp.Character
                if ch then
                    local nowTool = ch:FindFirstChildOfClass("Tool")
                    if nowTool and nowTool.Name == wantedName then
                        log("Equipped confirmed: "..wantedName)
                        return nowTool
                    end
                end
            until os.clock() > deadline
            log("Equip not confirmed in time; proceeding with inventory ref")
            return tool
        else
            log("Tool not found in inventory: "..wantedName)
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
        if not dmg then
            log("ToolDamageObject missing")
            return
        end
        log("Invoke ToolDamageObject → model="..(targetModel and targetModel.Name or "?").." tool="..(tool and tool.Name or "?").." id="..tostring(hitId))
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

    local function chopWave(targetModels, swingDelay, hitPartGetter, isTree)
        local toolName
        for _, n in ipairs(C.Config.ChopPrefer) do
            if findInInventory(n) or (equippedToolName() == n) then
                toolName = n
                break
            end
        end
        if not toolName then
            log("No preferred tool available")
            task.wait(0.35)
            return
        end
        local tool = ensureEquipped(toolName)
        if not tool then
            log("Tool equip failed: "..toolName)
            task.wait(0.35)
            return
        end
        for _, mdl in ipairs(targetModels) do
            task.spawn(function()
                local hitPart = hitPartGetter(mdl)
                if not hitPart then
                    log("No hit part: "..(mdl and mdl.Name or "?"))
                    return
                end
                local ch = lp.Character
                local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                local dist = hrp and (hitPart.Position - hrp.Position).Magnitude or math.huge
                log(string.format("Hit %s at d=%.1f using %s", mdl.Name, dist, tool.Name))
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
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if not hrp then
                    log("No HRP (character aura)")
                    task.wait(0.2)
                    break
                end
                local origin = hrp.Position
                local radius = tonumber(C.State.AuraRadius) or 150
                local targets = collectCharactersInRadius(WS:FindFirstChild("Characters"), origin, radius)
                log("Characters in range: "..tostring(#targets))
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
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if not hrp then
                    log("No HRP (tree aura)")
                    task.wait(0.2)
                    break
                end
                local origin = hrp.Position
                local radius = tonumber(C.State.AuraRadius) or 150
                local roots = { WS, RS:FindFirstChild("Assets"), RS:FindFirstChild("CutsceneSets") }
                local allTrees = collectTreesInRadius(roots, origin, radius)
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

    local function stopSmallTreeAura()
        running.SmallTree = false
    end

    CombatTab:Toggle({
        Title = "Show Combat Debug",
        Value = C.State.Toggles.CombatDebug or true,
        Callback = function(on)
            C.State.Toggles.CombatDebug = on
            showLogger(on)
        end
    })

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
            log("Set AuraRadius to "..tostring(C.State.AuraRadius))
        end
    })

    showLogger(C.State.Toggles.CombatDebug ~= false)
    log("Logger ready")
end
