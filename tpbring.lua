-- File: modules/tpbring.lua
return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.TPBring, "tpbring.lua: TPBring tab missing")

    local Players  = (C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C.Services and C.Services.Run)      or game:GetService("RunService")

    local lp = C.LocalPlayer or Players.LocalPlayer

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end
    local function humanoid()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChildOfClass("Humanoid")
    end
    local function mainPart(m)
        if not (m and m:IsA("Model")) then return nil end
        if m.PrimaryPart then return m.PrimaryPart end
        return m:FindFirstChildWhichIsA("BasePart")
    end
    local function zeroVel(inst)
        if not inst then return end
        if inst:IsA("BasePart") then
            inst.AssemblyLinearVelocity  = Vector3.new()
            inst.AssemblyAngularVelocity = Vector3.new()
        elseif inst:IsA("Model") then
            for _,p in ipairs(inst:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.AssemblyLinearVelocity  = Vector3.new()
                    p.AssemblyAngularVelocity = Vector3.new()
                end
            end
        end
    end
    local function snapshotCollideChar()
        local ch = lp.Character
        if not ch then return {} end
        local t = {}
        for _,d in ipairs(ch:GetDescendants()) do
            if d:IsA("BasePart") then t[d] = d.CanCollide end
        end
        return t
    end
    local function setCollideChar(on, snap)
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

    local function groundRay(fromPos, exclude)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = exclude or {}
        local hit = WS:Raycast(fromPos, Vector3.new(0, -10000, 0), params)
        return hit and hit.Position or fromPos
    end

    local function teleportClean(cf)
        local root = hrp(); if not root then return end
        local hum  = humanoid()
        local ch   = lp.Character
        local snap = snapshotCollideChar()

        if hum then
            pcall(function() hum.Sit = false end)
            pcall(function() hum.PlatformStand = true end)
        end

        setCollideChar(false)
        for _=1,6 do
            pcall(function() if ch then ch:PivotTo(cf) end end)
            pcall(function() root.CFrame = cf end)
            zeroVel(root)
            Run.Heartbeat:Wait()
        end
        setCollideChar(true, snap)

        if hum then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
            pcall(function() hum.PlatformStand = false end)
        end
        zeroVel(root)
    end

    local TREE_NAMES = { ["Small Tree"]=true, ["Snowy Small Tree"]=true, ["Small Webbed Tree"]=true }
    local function isSmallTreeModel(m) return m and m:IsA("Model") and TREE_NAMES[m.Name] == true end

    local function nearestSmallTree(origin)
        local best, bestD = nil, math.huge
        for _,d in ipairs(WS:GetDescendants()) do
            if isSmallTreeModel(d) then
                local part = mainPart(d)
                if part then
                    local dist = (part.Position - origin).Magnitude
                    if dist < bestD then bestD, best = dist, d end
                end
            end
        end
        return best
    end

    -- New: raycast from trunk downward; choose offset away from trunk toward player
    local function safeLandingCF(tree)
        local trunk = mainPart(tree); if not trunk then return nil end
        local trunkPos = trunk.Position

        local playerRoot = hrp()
        local towardPlayer = playerRoot and (playerRoot.Position - trunkPos) or (-trunk.CFrame.LookVector)
        if towardPlayer.Magnitude < 0.001 then towardPlayer = Vector3.new(1,0,0) end
        towardPlayer = Vector3.new(towardPlayer.X, 0, towardPlayer.Z).Unit

        local offsetDist = 5.5
        local standXZ = trunkPos + towardPlayer * offsetDist

        local groundFromTrunk = groundRay(trunkPos + Vector3.new(0, 200, 0), { lp.Character, tree })
        local groundAtStand   = groundRay(Vector3.new(standXZ.X, trunkPos.Y + 200, standXZ.Z), { lp.Character, tree })
        local groundY = groundAtStand.Y or groundFromTrunk.Y or trunkPos.Y

        local landing = Vector3.new(standXZ.X, groundY + 2.4, standXZ.Z)
        return CFrame.new(landing, trunkPos)
    end

    local function itemsFolder()
        return WS:FindFirstChild("Items")
    end
    local function getRemote(name)
        local f = RS:FindFirstChild("RemoteEvents")
        return f and f:FindFirstChild(name) or nil
    end

    -- Drag utilities
    local function startDragRemote(model)
        local re = RS:FindFirstChild("RemoteEvents")
        local r  = re and (re:FindFirstChild("RequestStartDraggingItem") or re:FindFirstChild("StartDraggingItem"))
        if r then pcall(function() r:FireServer(model) end) end
        return re and (re:FindFirstChild("StopDraggingItem") or re:FindFirstChild("RequestStopDraggingItem"))
    end
    local function stopDragRemote(stopEvt, model)
        if stopEvt then pcall(function() stopEvt:FireServer(model or Instance.new("Model")) end) end
    end
    local function getAllParts(target)
        local t = {}
        if not target then return t end
        if target:IsA("BasePart") then
            t[1] = target
        elseif target:IsA("Model") then
            for _,d in ipairs(target:GetDescendants()) do
                if d:IsA("BasePart") then t[#t+1] = d end
            end
        end
        return t
    end
    local function setCollide(model, on, snapshot)
        if on and snapshot then
            for p,can in pairs(snapshot) do if p and p.Parent then p.CanCollide = can end end
            return
        end
        local snap = {}
        for _,p in ipairs(getAllParts(model)) do snap[p]=p.CanCollide; p.CanCollide=false end
        return snap
    end
    local function setPivot(model, cf)
        if model:IsA("Model") then model:PivotTo(cf)
        else local p = mainPart(model); if p then p.CFrame = cf end end
    end
    local function bboxHeight(m)
        if m:IsA("Model") then
            local s = m:GetExtentsSize()
            return (s and s.Y) or 2
        end
        local p = mainPart(m)
        return (p and p.Size.Y) or 2
    end

    local DRAG_SPEED    = 18
    local STEP_WAIT     = 0.03
    local VERTICAL_MULT = 1.35

    local running = false -- checked inside movers for immediate cancel

    local function moveVerticalToY(model, targetY, lookDir, keepNoCollide)
        local snap = keepNoCollide and nil or setCollide(model, false)
        zeroVel(model)
        while running and model and model.Parent do
            local pivot = model:IsA("Model") and model:GetPivot() or (mainPart(model) and mainPart(model).CFrame)
            if not pivot then break end
            local pos = pivot.Position
            local dy = targetY - pos.Y
            if math.abs(dy) <= 0.4 then break end
            local stepY = math.sign(dy) * math.min(DRAG_SPEED * VERTICAL_MULT * STEP_WAIT, math.abs(dy))
            local newPos = Vector3.new(pos.X, pos.Y + stepY, pos.Z)
            setPivot(model, CFrame.new(newPos, newPos + (lookDir or Vector3.zAxis)))
            zeroVel(model)
            task.wait(STEP_WAIT)
        end
        if not keepNoCollide then setCollide(model, true, snap) end
    end

    local function moveHorizontalToXZ(model, destXZ, yFixed, keepNoCollide)
        local snap = keepNoCollide and nil or setCollide(model, false)
        zeroVel(model)
        while running and model and model.Parent do
            local pivot = model:IsA("Model") and model:GetPivot() or (mainPart(model) and mainPart(model).CFrame)
            if not pivot then break end
            local pos = pivot.Position
            local delta = Vector3.new(destXZ.X - pos.X, 0, destXZ.Z - pos.Z)
            local dist = delta.Magnitude
            if dist <= 1.0 then break end
            local step = math.min(DRAG_SPEED * STEP_WAIT, dist)
            local dir = delta.Unit
            local newPos = Vector3.new(pos.X, yFixed or pos.Y, pos.Z) + dir * step
            setPivot(model, CFrame.new(newPos, newPos + dir))
            zeroVel(model)
            task.wait(STEP_WAIT)
        end
        if not keepNoCollide then setCollide(model, true, snap) end
    end

    local function dropFromOrbSmooth(model, orbPos, H)
        zeroVel(model)
        local above = orbPos + Vector3.new(0, math.max(0.5, H * 0.25), 0)
        setPivot(model, CFrame.new(above))
        for _,p in ipairs(getAllParts(model)) do
            p.Anchored = false
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
        end
    end

    local function moveItemToOrb(model, orbCF)
        if not running then return end
        if not (model and model.Parent and orbCF) then return end
        local stopEvt = startDragRemote(model)
        Run.Heartbeat:Wait()
        local mp = mainPart(model); if not mp then stopDragRemote(stopEvt, model) return end
        local H = bboxHeight(model)
        local riserY = orbCF.Position.Y - 1.0 + math.clamp(H * 0.45, 0.8, 3.0)
        local lookDir = (Vector3.new(orbCF.Position.X, mp.Position.Y, orbCF.Position.Z) - mp.Position)
        lookDir = (lookDir.Magnitude > 0.001) and lookDir.Unit or Vector3.zAxis

        local snapOrig = setCollide(model, false)
        zeroVel(model)
        moveVerticalToY(model, riserY, lookDir, true); if not running then setCollide(model, true, snapOrig) stopDragRemote(stopEvt, model) return end
        moveHorizontalToXZ(model, Vector3.new(orbCF.Position.X, 0, orbCF.Position.Z), riserY, true); if not running then setCollide(model, true, snapOrig) stopDragRemote(stopEvt, model) return end
        setCollide(model, true, snapOrig)
        dropFromOrbSmooth(model, orbCF.Position, H)
        stopDragRemote(stopEvt, model)
    end

    local function waitTreeDestroyedAndFindLog(treeModel, timeout)
        local deadline = os.clock() + (timeout or 15)
        local treeGone = false
        local treePos = nil
        local mpT = mainPart(treeModel)
        if mpT then treePos = mpT.Position end
        local logFound = nil
        local items = itemsFolder()
        local nearby = {}
        local function consider(child)
            if not child or not child:IsA("Model") then return end
            if child.Name ~= "Log" then return end
            local pm = mainPart(child)
            if not pm then return end
            local p = pm.Position
            local ref = treePos or p
            if (p - ref).Magnitude <= 30 then
                nearby[#nearby+1] = child
            end
        end
        local addConn
        if items then
            addConn = items.ChildAdded:Connect(function(c) consider(c) end)
            for _,c in ipairs(items:GetChildren()) do consider(c) end
        end
        while running and os.clock() < deadline do
            if not treeGone then
                treeGone = (not treeModel) or (not treeModel.Parent)
            end
            if #nearby > 0 then
                for i=#nearby,1,-1 do
                    local m = nearby[i]
                    if m and m.Parent then
                        logFound = m; break
                    else
                        table.remove(nearby, i)
                    end
                end
            end
            if treeGone and logFound then break end
            Run.Heartbeat:Wait()
        end
        if addConn then addConn:Disconnect() end
        return logFound
    end

    local function groundBelow(pos)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local a = WS:Raycast(pos + Vector3.new(0, 5, 0), Vector3.new(0, -1000, 0), params)
        if a then return a.Position end
        local b = WS:Raycast(pos + Vector3.new(0, 200, 0), Vector3.new(0, -1000, 0), params)
        return (b and b.Position) or pos
    end
    local function createOrbAtPlayer()
        local root = hrp(); if not root then return nil end
        local p = Instance.new("Part")
        p.Name = "__LogOrb__"
        p.Shape = Enum.PartType.Ball
        p.Size = Vector3.new(2.4, 2.4, 2.4)
        p.Material = Enum.Material.Neon
        p.Color = Color3.fromRGB(80, 180, 255)
        p.Anchored = true
        p.CanCollide = false
        local pos = groundBelow(root.Position)
        p.CFrame = CFrame.new(Vector3.new(pos.X, pos.Y + 2.0, pos.Z))
        p.Parent = WS
        return p
    end

    local function ensureEdgeUi()
        local pg = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
        local edgeGui = pg:FindFirstChild("EdgeButtons")
        if not edgeGui then
            edgeGui = Instance.new("ScreenGui")
            edgeGui.Name = "EdgeButtons"
            edgeGui.ResetOnSpawn = false
            pcall(function() edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
            edgeGui.Parent = pg
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
        return edgeGui, stack
    end
    local function makeEdgeBtn(stack, name, label, order)
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

    local Conns = {}
    local function disconnectAll()
        for k,cn in pairs(Conns) do
            if cn and cn.Disconnect then cn:Disconnect() end
            Conns[k] = nil
        end
    end

    local orb, jobAnchorCF
    local stopBtnRef -- keep to hide instantly

    local function startJob()
        if running then return end
        running = true

        local _, stack = ensureEdgeUi()
        local stopBtn = makeEdgeBtn(stack, "StopLogsEdge", "STOP", 21)
        stopBtn.Visible = true
        stopBtnRef = stopBtn
        stopBtn.MouseButton1Click:Connect(function()
            -- Immediate cancel and UI hide
            running = false
            if stopBtnRef then stopBtnRef.Visible = false end
            disconnectAll()
        end)

        if orb then pcall(function() orb:Destroy() end) orb = nil end
        orb = createOrbAtPlayer()
        local orbCF = orb and orb.CFrame or nil

        -- Sticky fallback to job anchor while running
        if not Conns.guard then
            Conns.guard = Run.Heartbeat:Connect(function()
                if not running then return end
                if not jobAnchorCF then return end
                local r = hrp(); if not r then return end
                local d = (r.Position - jobAnchorCF.Position).Magnitude
                if d > 18 then
                    teleportClean(jobAnchorCF)
                end
            end)
        end

        task.spawn(function()
            while running do
                local r = hrp(); if not r then break end
                local tree = nearestSmallTree(r.Position)
                if not (tree and tree.Parent) then break end

                local landCF = safeLandingCF(tree)
                if not landCF then break end
                jobAnchorCF = landCF
                teleportClean(landCF)
                if not running then break end

                local logItem = waitTreeDestroyedAndFindLog(tree, 20)
                if not running then break end
                if logItem and logItem.Parent and orbCF then
                    moveItemToOrb(logItem, orbCF)
                    if not running then break end
                end

                Run.Heartbeat:Wait()
            end

            running = false
            jobAnchorCF = nil
            if stopBtnRef then stopBtnRef.Visible = false end
            disconnectAll()
        end)
    end

    local tab = UI.Tabs.TPBring
    tab:Section({ Title = "TP Bring" })
    tab:Button({
        Title = "Get Logs",
        Callback = function()
            startJob()
        end
    })

    Players.LocalPlayer.CharacterAdded:Connect(function()
        if orb and not orb.Parent then orb = nil end
        local _, stk = ensureEdgeUi()
        local sb = stk and stk:FindFirstChild("StopLogsEdge")
        if sb then sb.Visible = running end
    end)
end
