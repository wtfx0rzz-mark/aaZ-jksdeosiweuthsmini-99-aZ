--=====================================================
-- 1337 Nights | Bring Tab (workspace-wide, NPC-safe + Morsel drop fix)
--  • Farthest-first
--  • Re-enable physics and gravity properly for all items
--=====================================================
return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local RS      = C.Services.RS
    local lp      = Players.LocalPlayer

    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Bring
    assert(tab, "Bring tab not found in UI")

    local AMOUNT_TO_BRING = 50
    local DROP_FORWARD = 5
    local DROP_UP      = 5

    local junkItems = {
        "Tire","Bolt","Broken Fan","Broken Microwave","Sheet Metal",
        "Old Radio","Washing Machine","Old Car Engine","UFO Junk","UFO Component"
    }
    local foodItems = {
        "Morsel","Cooked Morsel","Steak","Cooked Steak","Cake","Berry","Carrot"
    }

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end

    local function mainPart(model)
        if not model then return nil end
        if model.PrimaryPart then return model.PrimaryPart end
        return model:FindFirstChildWhichIsA("BasePart")
    end

    local function getRemote(name)
        local r = RS:FindFirstChild("RemoteEvents")
        return r and r:FindFirstChild(name) or nil
    end

    local function distance(a, b)
        return (a.Position - b.Position).Magnitude
    end

    local function releasePhysics(m)
        if not m then return end
        for _,p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then
                p.Anchored = false
                p.CanCollide = true
                p.AssemblyLinearVelocity = Vector3.zero
                p.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end

    local function dropModelNearPlayer(m)
        local root = hrp()
        if not (root and m) then return end
        local mp = mainPart(m)
        if not mp then return end

        -- place gently in air then re-enable gravity
        local dropCF = CFrame.new(root.Position + root.CFrame.LookVector * DROP_FORWARD + Vector3.new(0, DROP_UP, 0))
        pcall(function() mp.CFrame = dropCF end)

        task.wait(0.05)
        releasePhysics(m)
        task.wait(0.05)

        -- force a small downward impulse to break float state
        pcall(function()
            mp.AssemblyLinearVelocity = Vector3.new(0, -25, 0)
        end)
    end

    local function findCandidateItems(list)
        local t = {}
        local root = hrp(); if not root then return t end
        local items = WS:FindFirstChild("Items"); if not items then return t end
        for _,m in ipairs(items:GetChildren()) do
            if m:IsA("Model") then
                for _,n in ipairs(list) do
                    if m.Name == n then
                        local mp = mainPart(m)
                        if mp then table.insert(t, {m=m, dist=distance(root, mp)}) end
                    end
                end
            end
        end
        table.sort(t, function(a,b) return a.dist > b.dist end)
        return t
    end

    local function bringItems(list)
        local dragRemote = getRemote("RequestStartDraggingItem")
        local stopRemote = getRemote("StopDraggingItem")
        if not dragRemote or not stopRemote then return end

        local all = findCandidateItems(list)
        local count = 0
        for _,entry in ipairs(all) do
            if count >= AMOUNT_TO_BRING then break end
            local m = entry.m
            local mp = mainPart(m)
            if m and mp then
                pcall(function() dragRemote:FireServer(m) end)
                task.wait(0.05)
                dropModelNearPlayer(m)
                pcall(function() stopRemote:FireServer(m) end)
                count += 1
                task.wait(0.1)
            end
        end
    end

    tab:Section({ Title = "Bring Items", Icon = "box" })

    tab:Button({
        Title = "Bring Junk",
        Callback = function() bringItems(junkItems) end
    })
    tab:Button({
        Title = "Bring Food (fix)",
        Callback = function() bringItems(foodItems) end
    })
end
