--=====================================================
-- 1337 Nights | Bring Module (mass bring, gather-style finder)
--=====================================================
return function(C, R, UI)
    -- Services
    local Players = (C and C.Services and C.Services.Players) or game:GetService("Players")
    local RS      = (C and C.Services and C.Services.RS)      or game:GetService("ReplicatedStorage")
    local WS      = (C and C.Services and C.Services.WS)      or game:GetService("Workspace")

    -- Tab
    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Bring
    assert(tab, "Bring tab not found in UI")

    -- Tunables
    local MAX_BRING       = 250      -- upper bound; bring as many as exist up to this
    local DEFAULT_RADIUS  = 120      -- search radius around player
    local GRID_COLS       = 10
    local GRID_H_GAP      = 0.35
    local GRID_V_GAP      = 0.15
    local DROP_UP         = 5
    local DROP_FORWARD    = 5

    -- Remotes (reuse gather’s)
    local RemoteFolder = RS:FindFirstChild("RemoteEvents")
    local StartDrag    = RemoteFolder and RemoteFolder:FindFirstChild("RequestStartDraggingItem")
    local StopDrag     = RemoteFolder and RemoteFolder:FindFirstChild("StopDraggingItem")

    -- State
    local lp = Players.LocalPlayer
    local resourceType = "Logs"
    local searchRadius = DEFAULT_RADIUS

    -- Helpers
    local function hrp()
        local ch = lp and (lp.Character or lp.CharacterAdded:Wait())
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local function clamp(v, lo, hi)
        v = tonumber(v) or lo
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end
    local function mainPart(m)
        if not m then return nil end
        if m:IsA("Model") then
            return m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
        elseif m:IsA("BasePart") then
            return m
        end
        return nil
    end
    local function ensurePrimary(m)
        if m and m:IsA("Model") and not m.PrimaryPart then
            local p = m:FindFirstChildWhichIsA("BasePart")
            if p then m.PrimaryPart = p end
        end
    end
    local function blacklist(m)
        local n = string.lower(m.Name or "")
        return n:find("trader",1,true) or n:find("shopkeeper",1,true) or n:find("campfire",1,true)
    end
    local function isLogName(name)
        local n = string.lower(name or "")
        -- Gather-style substring match, avoid common false-positives
        if n:find("dialog",1,true) or n:find("catalog",1,true) then return false end
        if resourceType == "Logs"    then return n:find("log",1,true) ~= nil end
        if resourceType == "Stone"   then return n:find("stone",1,true) or n:find("rock",1,true) end
        if resourceType == "Berries" then return n:find("berry",1,true) ~= nil end
        return false
    end
    local function groundYAt(pos)
        local rc = WS:Raycast(pos + Vector3.new(0, 100, 0), Vector3.new(0, -300, 0))
        return rc and rc.Position.Y or pos.Y
    end

    local function startDrag(m) if StartDrag and m then pcall(function() StartDrag:FireServer(m) end) end end
    local function stopDrag(m)  if StopDrag  and m then pcall(function() StopDrag:FireServer(m) end)  end end

    local function setNoCollide(m, on)
        local parts = m:IsA("Model") and m:GetDescendants() or {m}
        for _,d in ipairs(parts) do
            if d:IsA("BasePart") then
                d.CanCollide = not on
                d.Anchored = false
                if typeof(d.SetNetworkOwner) == "function" then
                    pcall(function() d:SetNetworkOwner(lp) end)
                end
            end
        end
    end
    local function anchorModel(m, anchored)
        local parts = m:IsA("Model") and m:GetDescendants() or {m}
        for _,d in ipairs(parts) do
            if d:IsA("BasePart") then
                d.Anchored = anchored
                d.CanCollide = true
                d.AssemblyLinearVelocity  = Vector3.new()
                d.AssemblyAngularVelocity = Vector3.new()
            end
        end
    end

    -- Finder: mirror gather’s scope and matching
    local function findTargets()
        local items = WS:FindFirstChild("Items")
        local root = hrp()
        if not items or not root then return {} end
        local origin = root.Position
        local out = {}
        for _,m in ipairs(items:GetChildren()) do
            if #out >= MAX_BRING then break end
            if m:IsA("Model") and not blacklist(m) and isLogName(m.Name) then
                local mp = mainPart(m)
                if mp and (mp.Position - origin).Magnitude <= searchRadius then
                    out[#out+1] = m
                end
            end
        end
        return out
    end

    -- Bring: mass move to a neat grid near player
    local function bringNow()
        local root = hrp(); if not root then return end
        local forward, right = root.CFrame.LookVector, root.CFrame.RightVector
        local basePos = root.Position + Vector3.new(0, DROP_UP, 0) + forward * DROP_FORWARD

        local targets = findTargets()
        if #targets == 0 then return end

        -- Estimate size from bounding boxes
        local function avgSize(list)
            local s, n = Vector3.new(), 0
            for _,m in ipairs(list) do
                if m and m.Parent then
                    local _, box = m:GetBoundingBox()
                    s += box; n += 1
                end
            end
            return n>0 and (s/n) or Vector3.new(3,2.5,3)
        end
        local s = avgSize(targets)
        local stepX = s.X + GRID_H_GAP
        local stepY = s.Y + GRID_V_GAP
        local halfCols = (GRID_COLS - 1) / 2

        for i, m in ipairs(targets) do
            if i > MAX_BRING then break end
            ensurePrimary(m)
            startDrag(m)
            setNoCollide(m, true)

            -- Grid position
            local col = (i-1) % GRID_COLS
            local row = math.floor((i-1) / GRID_COLS)
            local lateral = (col - halfCols) * stepX
            local height  = row * stepY
            local pos     = basePos + right * lateral + Vector3.new(0, height, 0)

            -- Ground it
            local gy = groundYAt(pos)
            pos = Vector3.new(pos.X, gy + s.Y/2, pos.Z)

            -- Face forward for generic items; logs still look fine here
            local cf = CFrame.new(pos, pos + forward)

            local mp = mainPart(m)
            if m:IsA("Model") and m.PrimaryPart then
                pcall(function() m:PivotTo(cf) end)
            elseif mp then
                pcall(function() mp.CFrame = cf end)
            end

            -- Lock in place and release
            anchorModel(m, true)
            setNoCollide(m, false)
            stopDrag(m)

            task.wait(0.005)
        end
    end

    -- UI
    tab:Section({ Title = "Bring" })

    tab:Dropdown({
        Title = "Resource Type",
        Values = { "Logs", "Stone", "Berries" },
        Multi = false,
        AllowNone = false,
        Callback = function(choice)
            if choice and choice ~= "" then resourceType = choice end
        end
    })

    tab:Slider({
        Title = "Search Radius",
        Value = { Min = 20, Max = 300, Default = DEFAULT_RADIUS },
        Callback = function(v) searchRadius = clamp(v, 10, 500) end
    })

    tab:Button({
        Title = "Bring Nearby",
        Callback = bringNow
    })

    tab:Section({ Title = "Max Bring: "..tostring(MAX_BRING) })
end
