--=====================================================
-- 1337 Nights | memory.lua • Performance logger (no UI)
--  • Toggle in tab → emits snapshots to your logger
--  • Tracks FPS, memory tags, instance counts
--  • Adds focused metrics for "Log" items in Workspace.Items
--  • Near-zero overhead when off
--=====================================================
return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and C.Services and UI and UI.Tabs, "memory.lua: missing context or UI")

    local Players = C.Services.Players or game:GetService("Players")
    local Run     = C.Services.Run     or game:GetService("RunService")
    local Stats   = game:GetService("Stats")
    local WS      = C.Services.WS      or game:GetService("Workspace")

    -- ---- host tab (prefer a Memory tab if present) ----
    local hostTab = (UI.Tabs.Memory or UI.Tabs.Main or UI.Tabs.Auto or UI.Tabs.Player or UI.Tabs.Visuals)
    assert(hostTab, "memory.lua: no suitable tab found")

    -- ---- logger adapter: call your logger if present, else print ----
    local function emit(line)
        -- Common patterns: R.Logger.Append, R.Logger.Log, R.Log, C.Log, _G.Logger.Log, _G.Log
        local ok =
            (R and R.Logger and typeof(R.Logger.Append)=="function" and pcall(R.Logger.Append, line)) or
            (R and R.Logger and typeof(R.Logger.Log)   =="function" and pcall(R.Logger.Log,    line)) or
            (R and typeof(R.Log)=="function"                       and pcall(R.Log,             line)) or
            (C and typeof(C.Log)=="function"                       and pcall(C.Log,             line)) or
            (_G and _G.Logger and typeof(_G.Logger.Log)=="function"and pcall(_G.Logger.Log,    line)) or
            (_G and typeof(_G.Log)=="function"                     and pcall(_G.Log,            line))
        if not ok then
            print(line)
        end
    end

    -- ---- FPS sampler ring ----
    local ring = table.create(240, 1/60) -- ~4s
    local head, count = 0, 0
    local function pushDt(dt)
        head = (head % #ring) + 1
        ring[head] = dt
        if count < #ring then count += 1 end
    end
    local function avgFps()
        if count == 0 then return 0 end
        local s = 0; for i=1,count do s += ring[i] end
        return 1 / (s / count)
    end
    local function fpsPercentile(pWorst) -- pWorst in [0..1], e.g. 0.01 for 1% low
        if count == 0 then return 0 end
        local t, n = table.create(count), 0
        for i=1,count do n+=1; t[n]=ring[i] end
        table.sort(t) -- ascending dt (worst at end)
        local idx = math.clamp(math.max(1, math.floor((1 - pWorst) * n)), 1, n)
        return 1 / t[idx]
    end

    -- ---- safe memory tag read ----
    local function mem(tag)
        local ok, v = pcall(function() return Stats:GetMemoryUsageMbForTag(tag) end)
        return ok and v or 0
    end

    -- ---- counts ----
    local function countFolderChildren(path)
        local cur = WS
        for _,n in ipairs(path) do
            cur = cur and cur:FindFirstChild(n)
        end
        if cur and cur.GetChildren then
            local ok, kids = pcall(cur.GetChildren, cur)
            return (ok and kids and #kids) or 0
        end
        return 0
    end

    local function countLogs()
        local items = WS:FindFirstChild("Items")
        if not items then return 0,0,0 end
        local models, parts, anchored = 0, 0, 0
        for _, m in ipairs(items:GetChildren()) do
            if m:IsA("Model") and m.Name == "Log" then
                models += 1
                for _, d in ipairs(m:GetDescendants()) do
                    if d:IsA("BasePart") then
                        parts += 1
                        if d.Anchored then anchored += 1 end
                    end
                end
            end
        end
        return models, parts, anchored
    end

    local function fmt(n, d) return string.format("%."..(d or 1).."f", n) end

    local updating, hbConn, tickConn = false, nil, nil

    local function startLogger()
        if updating then return end
        updating = true
        -- reset ring
        for i=1,#ring do ring[i]=1/60 end
        head, count = 0, 0

        hbConn   = Run.Heartbeat:Connect(pushDt)
        tickConn = task.spawn(function()
            while updating do
                local fps    = avgFps()
                local fps1   = fpsPercentile(0.01)
                local total  = Stats:GetTotalMemoryUsageMb()
                local luaH   = mem(Enum.DeveloperMemoryTag.LuaHeap)
                local inst   = mem(Enum.DeveloperMemoryTag.Instances)
                local tex    = mem(Enum.DeveloperMemoryTag.Texture)
                local gui    = mem(Enum.DeveloperMemoryTag.Gui)
                local phys   = mem(Enum.DeveloperMemoryTag.Physics)
                local net    = mem(Enum.DeveloperMemoryTag.Network)

                local itemsN = countFolderChildren({"Items"})
                local charsN = countFolderChildren({"Characters"})
                local logN, logParts, logAnch = countLogs()

                local toggles = {}
                local ts = (C.State and C.State.Toggles) or {}
                for k,v in pairs(ts) do if v then toggles[#toggles+1]=k end end
                table.sort(toggles)

                local line = (
                    "FPS %s | 1%% %s | Mem %.1fMB [Lua %.1f Inst %.1f Tex %.1f Gui %.1f Phys %.1f Net %.1f] | Items %d, Chars %d | Logs %d (parts %d, anchored %d) | Toggles [%s]"
                ):format(
                    fmt(fps,1), fmt(fps1,1), total, luaH, inst, tex, gui, phys, net,
                    itemsN, charsN, logN, logParts, logAnch, table.concat(toggles, ", ")
                )

                emit(line)
                task.wait(0.5)
            end
        end)
    end

    local function stopLogger()
        updating = false
        if hbConn   then pcall(function() hbConn:Disconnect() end)   end; hbConn   = nil
        if tickConn then pcall(function() task.cancel(tickConn) end) end; tickConn = nil
    end

    hostTab:Section({ Title = "Diagnostics", Icon = "activity" })
    local ToggleCtrl = hostTab:Toggle({
        Title = "Performance Logger",
        Value = false,
        Callback = function(on) if on then startLogger() else stopLogger() end end
    })

    Players.LocalPlayer.CharacterAdded:Connect(function()
        if updating then task.defer(function() stopLogger(); startLogger() end) end
    end)
end
