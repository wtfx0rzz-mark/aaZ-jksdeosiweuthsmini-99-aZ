return function(C, R, UI)
    local function run()
        -- Services
        local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
        local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
        local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
        local PPS      = game:GetService("ProximityPromptService")
        local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")
        local UIS      = game:GetService("UserInputService")
        local Lighting = (C and C.Services and C.Services.Lighting) or game:GetService("Lighting")
        local VIM      = game:GetService("VirtualInputManager")

        -- Tab
        local lp   = Players.LocalPlayer
        local Tabs = (UI and UI.Tabs) or {}
        local tab  = Tabs.Auto
        if not (lp and tab) then return end

        -- Small utils
        local function hrp()
            local ch = lp.Character or lp.CharacterAdded:Wait()
            return ch and ch:FindFirstChild("HumanoidRootPart")
        end
        local function hum()
            local ch = lp.Character
            return ch and ch:FindFirstChildOfClass("Humanoid")
        end
        local function mainPart(m)
            if not m then return nil end
            if m:IsA("BasePart") then return m end
            if m:IsA("Model") then
                if m.PrimaryPart then return m.PrimaryPart end
                return m:FindFirstChildWhichIsA("BasePart")
            end
            return nil
        end
        local function getRemote(name)
            local f = RS:FindFirstChild("RemoteEvents")
            return f and f:FindFirstChild(name) or nil
        end
        local function zeroAssembly(root)
            if not root then return end
            root.AssemblyLinearVelocity  = Vector3.new()
            root.AssemblyAngularVelocity = Vector3.new()
        end

        -- Collide helpers
        local function snapshotCollide()
            local ch = lp.Character
            if not ch then return {} end
            local t = {}
            for _,d in ipairs(ch:GetDescendants()) do
                if d:IsA("BasePart") then t[d] = d.CanCollide end
            end
            return t
        end
        local function setCollideAll(on, snap)
            local ch = lp.Character
            if not ch then return end
            if on and snap then
                for part,can in pairs(snap) do
                    if part and part.Parent then part.CanCollide = can end
                end
            else
                for _,d in ipairs(ch:GetDescendants()) do
                    if d:IsA("BasePart") then d.CanCollide = false end
                end
            end
        end
        local function isNoclipNow()
            local ch = lp.Character
            if not ch then return false end
            local total, off = 0, 0
            for _,d in ipairs(ch:GetDescendants()) do
                if d:IsA("BasePart") then
                    total += 1
                    if d.CanCollide == false then off += 1 end
                end
            end
            return (total > 0) and ((off / total) >= 0.9) or false
        end

        -- Streaming + ground
        local STREAM_TIMEOUT = 6.0
        local function requestStreamAt(pos, timeout)
            local p = typeof(pos) == "CFrame" and pos.Position or pos
            pcall(function() WS:RequestStreamAroundAsync(p, timeout or STREAM_TIMEOUT) end)
        end
        local function prefetchRing(cf, r)
            local base = typeof(cf)=="CFrame" and cf.Position or cf
            r = r or 80
            local o = {
                Vector3.new( 0,0, 0),
                Vector3.new( r,0, 0), Vector3.new(-r,0, 0),
                Vector3.new( 0,0, r), Vector3.new( 0,0,-r),
                Vector3.new( r,0, r), Vector3.new( r,0,-r),
                Vector3.new(-r,0, r), Vector3.new(-r,0,-r),
            }
            for i=1,#o do requestStreamAt(base + o[i]) end
        end
        local function waitGameplayResumed(timeout)
            local t0 = os.clock()
            while lp and lp.GameplayPaused do
                if os.clock() - t0 > (timeout or STREAM_TIMEOUT) then break end
                Run.Heartbeat:Wait()
            end
        end
        local function groundBelow(pos)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            local ex = { lp.Character }
            local map = WS:FindFirstChild("Map")
            if map then
                local fol = map:FindFirstChild("Foliage")
                if fol then table.insert(ex, fol) end
            end
            local items = WS:FindFirstChild("Items");      if items then table.insert(ex, items) end
            local chars = WS:FindFirstChild("Characters"); if chars then table.insert(ex, chars) end
            params.FilterDescendantsInstances = ex
            local start = pos + Vector3.new(0, 5, 0)
            local hit = WS:Raycast(start, Vector3.new(0, -1000, 0), params)
            if hit then return hit.Position end
            hit = WS:Raycast(pos + Vector3.new(0, 200, 0), Vector3.new(0, -1000, 0), params)
            return (hit and hit.Position) or pos
        end

        -- Teleport
        local TELEPORT_UP_NUDGE = 0.05
        local STICK_DURATION    = 0.35
        local STICK_EXTRA_FR    = 2
        local STICK_CLEAR_VEL   = true
        local SAFE_DROP_UP      = 4.0

        local function teleportSticky(cf, dropMode)
            local root = hrp(); if not root then return end
            local ch   = lp.Character
            local targetCF = cf + Vector3.new(0, TELEPORT_UP_NUDGE, 0)

            prefetchRing(targetCF)
            requestStreamAt(targetCF)
            waitGameplayResumed(1.0)

            local hadNoclip = isNoclipNow()
            local snap
            if not hadNoclip then
                snap = snapshotCollide()
                setCollideAll(false)
            end

            if ch then pcall(function() ch:PivotTo(targetCF) end) end
            pcall(function() root.CFrame = targetCF end)
            if STICK_CLEAR_VEL then zeroAssembly(root) end

            if dropMode then
                if not hadNoclip then setCollideAll(true, snap) end
                waitGameplayResumed(1.0)
                return
            end

            local t0 = os.clock()
            while (os.clock() - t0) < STICK_DURATION do
                if ch then pcall(function() ch:PivotTo(targetCF) end) end
                pcall(function() root.CFrame = targetCF end)
                if STICK_CLEAR_VEL then zeroAssembly(root) end
                Run.Heartbeat:Wait()
            end
            for _=1,STICK_EXTRA_FR do
                if ch then pcall(function() ch:PivotTo(targetCF) end) end
                pcall(function() root.CFrame = targetCF end)
                if STICK_CLEAR_VEL then zeroAssembly(root) end
                Run.Heartbeat:Wait()
            end

            if not hadNoclip then setCollideAll(true, snap) end
            if STICK_CLEAR_VEL then zeroAssembly(root) end
            waitGameplayResumed(1.0)
        end

        local function diveBelowGround(depth, frames)
            local root = hrp(); if not root then return end
            local ch = lp.Character
            local look = root.CFrame.LookVector
            local dest = root.Position + Vector3.new(0, -math.abs(depth), 0)
            for _=1,(frames or 4) do
                local cf = CFrame.new(dest, dest + look)
                if ch then pcall(function() ch:PivotTo(cf) end) end
                pcall(function() root.CFrame = cf end)
                zeroAssembly(root)
                Run.Heartbeat:Wait()
            end
        end
        local function teleportWithDive(targetCF)
            local upCF = targetCF + Vector3.new(0, SAFE_DROP_UP, 0)
            prefetchRing(upCF)
            requestStreamAt(upCF)
            waitGameplayResumed(1.0)
            local root = hrp(); if not root then return end
            local snap = snapshotCollide()
            setCollideAll(false)
            diveBelowGround(200, 4)
            teleportSticky(upCF, true)
            local h = hum(); local t0 = os.clock()
            while os.clock() - t0 < 3 do
                if h and h.FloorMaterial ~= Enum.Material.Air then break end
                Run.Heartbeat:Wait()
            end
            setCollideAll(true, snap)
            waitGameplayResumed(1.0)
        end

        -- Edge buttons container (safe)
        local function ensureEdgeStack()
            local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
            local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
            if not edgeGui then
                edgeGui = Instance.new("ScreenGui")
                edgeGui.Name = "EdgeButtons"
                edgeGui.ResetOnSpawn = false
                pcall(function() edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
                edgeGui.Parent = playerGui
            end
            local stack = edgeGui:FindFirstChild("EdgeStack")
            if not stack then
                stack = Instance.new("Frame")
                stack.Name = "EdgeStack"
                stack.AnchorPoint = Vector2.new(1, 0)
                stack.Position = UDim2.new(1, -6, 0, 6)
                stack.Size = UDim2.new(0, 130, 1, -12)
                stack.BackgroundTransparency = 1
                stack.BorderSizePixel = 0
                stack.Parent = edgeGui
                local list = Instance.new("UIListLayout")
                list.Name = "VList"
                list.FillDirection = Enum.FillDirection.Vertical
                list.SortOrder = Enum.SortOrder.LayoutOrder
                list.Padding = UDim.new(0, 6)
                list.HorizontalAlignment = Enum.HorizontalAlignment.Right
                list.Parent = stack
            end
            return stack
        end
        local stack = ensureEdgeStack()
        local function makeEdgeBtn(name, label, order)
            local b = stack:FindFirstChild(name)
            if not b then
                b = Instance.new("TextButton")
                b.Name = name
                b.Size = UDim2.new(1, 0, 0, 30)
                b.Text = label
                b.TextSize = 12
                b.Font = Enum.Font.GothamBold
                b.BackgroundColor3 = Color3.fromRGB(30,30,35)
                b.TextColor3 = Color3.new(1,1,1)
                b.BorderSizePixel = 0
                b.Visible = false
                b.LayoutOrder = order or 1
                b.Parent = stack
                local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = b
            else
                b.Text = label
                b.LayoutOrder = order or b.LayoutOrder
                b.Visible = false
            end
            return b
        end

        -- Simple utilities
        local function itemsFolder() return WS:FindFirstChild("Items") end
        local function groundBelowSimple(pos)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { lp.Character, WS:FindFirstChild("Items") }
            local start = pos + Vector3.new(0, 5, 0)
            local hit = WS:Raycast(start, Vector3.new(0, -1000, 0), params)
            if hit then return hit.Position end
            hit = WS:Raycast(pos + Vector3.new(0, 200, 0), Vector3.new(0, -1000, 0), params)
            return (hit and hit.Position) or pos
        end

        ----------------------------------------------------------------
        -- 1) FIND UNOPENED CHESTS
        ----------------------------------------------------------------
        local nextChestBtn = makeEdgeBtn("NextChestEdge", "Nearest Unopened Chest", 6)

        local function openedAttrName() return tostring(lp.UserId) .. "Opened" end
        local function isChestName(n)
            if type(n) ~= "string" then return false end
            return n:match("Chest%d*$") ~= nil or n:match("Chest$") ~= nil
        end
        local function isSnowChestName(n)
            if type(n) ~= "string" then return false end
            return (n == "Snow Chest") or (n:match("^Snow Chest%d+$") ~= nil)
        end
        local function isHalloweenChestName(n)
            if type(n) ~= "string" then return false end
            return (n == "Halloween Chest") or (n:match("^Halloween Chest%d+$") ~= nil)
        end
        local function chestOpened(m)
            if not m then return false end
            return m:GetAttribute(openedAttrName()) == true
        end
        local function mainPart2(m)
            if not m then return nil end
            if m:IsA("BasePart") then return m end
            if m:IsA("Model") then
                if m.PrimaryPart then return m.PrimaryPart end
                return m:FindFirstChildWhichIsA("BasePart")
            end
            return nil
        end
        local function chestPos(m)
            local mp = mainPart2(m)
            if mp then return mp.Position end
            local ok, cf = pcall(function() return m:GetPivot() end)
            return ok and cf.Position or nil
        end
        local function findUnopenedChestsSorted()
            local items = itemsFolder(); if not items then return {} end
            local root  = hrp(); if not root then return {} end
            local list = {}
            for _,m in ipairs(items:GetChildren()) do
                if m:IsA("Model") and isChestName(m.Name) then
                    if not isHalloweenChestName(m.Name) and not isSnowChestName(m.Name) then
                        if not chestOpened(m) then
                            local p = chestPos(m)
                            if p then list[#list+1] = {m=m, pos=p} end
                        end
                    end
                end
            end
            table.sort(list, function(a,b)
                local rp = root.Position
                local da = (a.pos - rp).Magnitude
                local db = (b.pos - rp).Magnitude
                return da < db
            end)
            return list
        end
        local function teleportNearChest(m)
            local mp = mainPart2(m); if not mp then return end
            local chestCenter = mp.Position
            -- Try to stand in front of the opening side if hinges exist; else face the chest
            local hingePos = nil
            for _,d in ipairs(m:GetDescendants()) do
                if d.Name == "Hinge" then
                    local p = (d:IsA("BasePart") and d.Position) or (d:IsA("Model") and mainPart2(d) and mainPart2(d).Position) or nil
                    if p then hingePos = hingePos and (hingePos + p)/2 or p end
                end
            end
            local dir
            if hingePos then
                dir = (chestCenter - hingePos)
                if dir.Magnitude < 1e-3 then dir = -mp.CFrame.LookVector end
                dir = dir.Unit
            else
                local root = hrp()
                if root then
                    local vec = root.Position - chestCenter
                    dir = (vec.Magnitude > 0.001 and -vec.Unit) or (-mp.CFrame.LookVector).Unit
                else
                    dir = (-mp.CFrame.LookVector).Unit
                end
            end
            local desired = chestCenter + dir * 4.0
            local groundP = groundBelowSimple(desired)
            local standPos = Vector3.new(desired.X, groundP.Y + 2.5, desired.Z)
            teleportSticky(CFrame.new(standPos, chestCenter), true)
        end
        local chestFinderOn = false
        nextChestBtn.MouseButton1Click:Connect(function()
            local list = findUnopenedChestsSorted()
            if #list == 0 then
                nextChestBtn.Text = "Nearest Unopened Chest"
                nextChestBtn.Visible = false
                return
            end
            teleportNearChest(list[1].m)
            task.delay(0.5, function()
                local l2 = findUnopenedChestsSorted()
                nextChestBtn.Visible = chestFinderOn and (#l2 > 0)
                if #l2 > 0 then
                    nextChestBtn.Text = ("Nearest Unopened Chest (%d)"):format(#l2)
                else
                    nextChestBtn.Text = "Nearest Unopened Chest"
                end
            end)
        end)
        local function refreshChestBtn()
            local list = findUnopenedChestsSorted()
            nextChestBtn.Visible = chestFinderOn and (#list > 0)
            if #list > 0 then
                nextChestBtn.Text = ("Nearest Unopened Chest (%d)"):format(#list)
            else
                nextChestBtn.Text = "Nearest Unopened Chest"
            end
        end
        local cfHB, addCF, remCF
        local function enableChestFinder()
            if chestFinderOn then return end
            chestFinderOn = true
            nextChestBtn.Visible = false
            local items = itemsFolder()
            if items then
                addCF = items.ChildAdded:Connect(function(_) refreshChestBtn() end)
                remCF = items.ChildRemoved:Connect(function(_) refreshChestBtn() end)
            end
            cfHB = Run.Heartbeat:Connect(refreshChestBtn)
            refreshChestBtn()
        end
        local function disableChestFinder()
            chestFinderOn = false
            if cfHB then cfHB:Disconnect() cfHB = nil end
            if addCF then addCF:Disconnect() addCF = nil end
            if remCF then remCF:Disconnect() remCF = nil end
            nextChestBtn.Visible = false
        end
        tab:Toggle({
            Title = "Find Unopened Chests",
            Value = false,
            Callback = function(state)
                if state then enableChestFinder() else disableChestFinder() end
            end
        })

        ----------------------------------------------------------------
        -- 2) DELETE CHESTS AFTER OPENING
        ----------------------------------------------------------------
        do
            local deleteOn = false
            local addConn, remConn, sweepHB
            local tracked   = setmetatable({}, { __mode = "k" })
            local deleteExcl = setmetatable({}, { __mode = "k" })
            local DIAMOND_PAIR_DIST = 9.8
            local DIAMOND_PAIR_TOL  = 2.0

            local function locateDiamondAndNeighbor()
                deleteExcl = setmetatable({}, { __mode = "k" })
                local items = itemsFolder(); if not items then return end
                local diamond, dpos = nil, nil
                local all = {}
                for _,m in ipairs(items:GetChildren()) do
                    if m:IsA("Model") and isChestName(m.Name) then
                        all[#all+1] = m
                        if m.Name == "Stronghold Diamond Chest" then
                            diamond = m
                            local mp = mainPart2(m)
                            dpos = (mp and mp.Position) or (m:GetPivot().Position)
                        end
                    end
                end
                if not (diamond and dpos) then return end
                deleteExcl[diamond] = true
                local bestM, bestD = nil, math.huge
                for _,m in ipairs(all) do
                    if m ~= diamond then
                        local mp = mainPart2(m)
                        local p = (mp and mp.Position) or (m:GetPivot().Position)
                        if p then
                            local dist = (p - dpos).Magnitude
                            if math.abs(dist - DIAMOND_PAIR_DIST) <= DIAMOND_PAIR_TOL then
                                deleteExcl[m] = true
                            end
                            if dist < bestD then bestD, bestM = dist, m end
                        end
                    end
                end
                if not next(deleteExcl) and bestM then deleteExcl[bestM] = true end
            end

            local function safeHideThenDestroy(m)
                if not (m and m.Parent) then return end
                for _,d in ipairs(m:GetDescendants()) do
                    if d:IsA("ProximityPrompt") then
                        pcall(function() d.Enabled = false end)
                    elseif d:IsA("ClickDetector") then
                        pcall(function() d.MaxActivationDistance = 0 end)
                    elseif d:IsA("BasePart") then
                        pcall(function()
                            d.CanCollide = false
                            d.CanTouch   = false
                            d.CanQuery   = false
                            d.Anchored   = true
                            d.Transparency = 1
                        end)
                    end
                end
                task.delay(0.7, function()
                    if m and m.Parent then pcall(function() m:Destroy() end) end
                end)
            end

            local function deleteIfOpenedNow(m)
                if not deleteOn then return end
                if not (m and m.Parent) then return end
                if not isChestName(m.Name) then return end
                if deleteExcl[m] then return end
                if isHalloweenChestName(m.Name) or isSnowChestName(m.Name) then return end
                if chestOpened(m) then safeHideThenDestroy(m) end
            end

            local function watchChest(m)
                if not (m and m:IsA("Model") and isChestName(m.Name)) then return end
                if tracked[m] then return end
                tracked[m] = true
                -- Attribute binding uses per-user key
                local attr = openedAttrName()
                m:GetAttributeChangedSignal(attr):Connect(function() deleteIfOpenedNow(m) end)
                m.AncestryChanged:Connect(function(_, parent) if not parent then tracked[m] = nil end end)
                deleteIfOpenedNow(m)
            end

            local function scanAll()
                local items = itemsFolder(); if not items then return end
                for _,child in ipairs(items:GetChildren()) do watchChest(child) end
            end
            local function sweepDeleteOpened()
                if not deleteOn then return end
                local items = itemsFolder(); if not items then return end
                for _,m in ipairs(items:GetChildren()) do
                    if m:IsA("Model") and isChestName(m.Name) then deleteIfOpenedNow(m) end
                end
            end

            local function enableDelete()
                if deleteOn then return end
                deleteOn = true
                locateDiamondAndNeighbor()
                scanAll()
                sweepDeleteOpened()
                local items = itemsFolder()
                if items then
                    addConn = items.ChildAdded:Connect(function(m)
                        if m and m:IsA("Model") then
                            if m.Name == "Stronghold Diamond Chest" or isChestName(m.Name) then
                                locateDiamondAndNeighbor()
                            end
                            watchChest(m)
                        end
                    end)
                    remConn = items.ChildRemoved:Connect(function(m)
                        tracked[m] = nil
                        if m and (m.Name == "Stronghold Diamond Chest" or isChestName(m.Name)) then
                            task.defer(locateDiamondAndNeighbor)
                        end
                    end)
                end
                if sweepHB then sweepHB:Disconnect() end
                sweepHB = Run.Heartbeat:Connect(sweepDeleteOpened)
            end

            local function disableDelete()
                deleteOn = false
                if addConn then addConn:Disconnect() addConn = nil end
                if remConn then remConn:Disconnect() remConn = nil end
                if sweepHB then sweepHB:Disconnect() sweepHB = nil end
            end

            tab:Toggle({
                Title = "Delete Chests After Opening",
                Value = false,
                Callback = function(state) if state then enableDelete() else disableDelete() end end
            })
        end

        ----------------------------------------------------------------
        -- 3) DELETE ALL BIG TREES
        ----------------------------------------------------------------
        do
            -- Adjust names to match your place
            local BIG_TREE_NAMES = { TreeBig1=true, TreeBig2=true, TreeBig3=true }
            local function isBigTreeName(n)
                if BIG_TREE_NAMES[n] then return true end
                return type(n)=="string" and n:match("^WebbedTreeBig%d*$") ~= nil
            end

            local delBigOn, addConn
            local function deleteBigTree(m)
                if not (m and m.Parent and m:IsA("Model")) then return end
                if not isBigTreeName(m.Name) then return end
                for _,d in ipairs(m:GetDescendants()) do
                    if d:IsA("BasePart") then
                        pcall(function()
                            d.CanCollide=false; d.CanTouch=false; d.CanQuery=false; d.Anchored=true; d.Transparency=1
                        end)
                    end
                end
                task.delay(0.25, function() if m and m.Parent then pcall(function() m:Destroy() end) end end)
            end

            local function sweep()
                if not delBigOn then return end
                for _,d in ipairs(WS:GetDescendants()) do
                    if d:IsA("Model") and isBigTreeName(d.Name) then deleteBigTree(d) end
                end
            end

            local function enableBigDelete()
                if delBigOn then return end
                delBigOn = true
                sweep()
                addConn = WS.DescendantAdded:Connect(function(d)
                    if delBigOn and d and d:IsA("Model") and isBigTreeName(d.Name) then deleteBigTree(d) end
                end)
            end
            local function disableBigDelete()
                delBigOn = false
                if addConn then addConn:Disconnect() addConn=nil end
            end

            tab:Toggle({
                Title = "Delete All Big Trees",
                Value = false,
                Callback = function(state) if state then enableBigDelete() else disableBigDelete() end end
            })
        end

        ----------------------------------------------------------------
        -- Stability helpers and small QoL
        ----------------------------------------------------------------
        tab:Section({ Title = "Status" })
        tab:Button({
            Title = "Force Disable Streaming Pause",
            Callback = function() pcall(function() WS.StreamingPauseMode = Enum.StreamingPauseMode.Disabled end) end
        })

        Players.LocalPlayer.CharacterAdded:Connect(function()
            -- Reparent EdgeButtons if Studio respawn shuffled GUIs
            local gui = lp:WaitForChild("PlayerGui")
            local eg  = gui:FindFirstChild("EdgeButtons")
            if eg and eg.Parent ~= gui then eg.Parent = gui end
            pcall(function() WS.StreamingPauseMode = Enum.StreamingPauseMode.Disabled end)
        end)
    end

    local ok, err = xpcall(run, function(e)
        warn("[Auto] module error: " .. tostring(e))
        return e
    end)
    if not ok then warn("[Auto] failed: " .. tostring(err)) end
end
