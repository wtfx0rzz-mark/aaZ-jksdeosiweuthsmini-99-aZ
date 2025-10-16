--=====================================================
-- 1337 Nights | memory.lua  • Client-side memory guard + janitor
--  - Janitor: one-call cleanup for connections/instances
--  - Track(): tag temp instances, optional auto-remove via Debris
--  - Loop scheduler with safe cancel
--  - Periodic audit: remove orphaned Highlights/BillboardGuis,
--    dedupe EdgeButtons ScreenGui, trim runaway counts
--  - Optional tiny HUD for client memory (Stats service)
--=====================================================
return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and C.Services, "memory.lua: missing context")

    local Players = C.Services.Players or game:GetService("Players")
    local Debris  = game:GetService("Debris")
    local Run     = C.Services.Run     or game:GetService("RunService")
    local Stats   = game:GetService("Stats")
    local WS      = C.Services.WS      or game:GetService("Workspace")
    local RS      = C.Services.RS      or game:GetService("ReplicatedStorage")

    local lp = Players.LocalPlayer

    ----------------------------------------------------------------------
    -- Janitor utility
    ----------------------------------------------------------------------
    local Janitor = {}
    Janitor.__index = Janitor

    function Janitor.new()
        return setmetatable({
            _tasks = setmetatable({}, {__mode="v"}) -- weak values to allow GC
        }, Janitor)
    end

    -- Add(obj [, methodNameOrFunc])
    function Janitor:Add(obj, method)
        local entry = {obj = obj, method = method}
        table.insert(self._tasks, entry)
        return obj
    end

    function Janitor:Cleanup()
        local t = self._tasks
        for i = #t, 1, -1 do
            local e = t[i]
            local o = e and e.obj
            local m = e and e.method
            if o then
                pcall(function()
                    if type(m) == "function" then
                        m(o)
                    elseif type(m) == "string" and o[m] then
                        o[m](o)
                    elseif typeof(o) == "RBXScriptConnection" then
                        o:Disconnect()
                    elseif typeof(o) == "Instance" and o.Destroy then
                        o:Destroy()
                    end
                end)
            end
            t[i] = nil
        end
    end

    ----------------------------------------------------------------------
    -- MemoryGuard API
    ----------------------------------------------------------------------
    local MemoryGuard = {}
    local _tracked = setmetatable({}, {__mode="kv"}) -- [instance] = expireAt or false
    local _conns   = setmetatable({}, {__mode="v"})
    local _loops   = {} -- name -> {running=true, thread=task}

    -- Track an instance with optional lifetime (seconds). Uses Debris if ttl given.
    function MemoryGuard.Track(inst, ttl)
        if not inst or typeof(inst) ~= "Instance" then return end
        if type(ttl) == "number" and ttl > 0 then
            Debris:AddItem(inst, ttl)
            _tracked[inst] = (os.clock() + ttl)
        else
            _tracked[inst] = false
        end
    end

    -- Track a connection for bulk cleanup
    function MemoryGuard.Connect(conn)
        if typeof(conn) == "RBXScriptConnection" then
            table.insert(_conns, conn)
        end
        return conn
    end

    -- Start a safe loop that can be cancelled via StopLoop(name)
    function MemoryGuard.StartLoop(name, intervalSec, fn)
        MemoryGuard.StopLoop(name)
        local alive = true
        _loops[name] = {running = true}
        task.spawn(function()
            while alive do
                local ok, err = pcall(fn)
                if not ok then warn("[MemoryGuard] Loop '"..tostring(name).."' error:", err) end
                task.wait(intervalSec)
                local slot = _loops[name]
                alive = slot and slot.running == true
            end
        end)
    end

    function MemoryGuard.StopLoop(name)
        local slot = _loops[name]
        if slot then slot.running = false end
        _loops[name] = nil
    end

    -- Bulk cleanup now
    function MemoryGuard.CleanupAll()
        -- connections
        for i = #_conns, 1, -1 do
            local c = _conns[i]
            if c then pcall(function() c:Disconnect() end) end
            _conns[i] = nil
        end
        -- tracked instances (destroy only if still valid and no Debris TTL)
        for inst, expire in pairs(_tracked) do
            if inst and inst.Parent and (not expire) then
                pcall(function() inst:Destroy() end)
            end
            _tracked[inst] = nil
        end
    end

    ----------------------------------------------------------------------
    -- Orphan auditor (targets common leak-prone visuals/util GUIs)
    ----------------------------------------------------------------------
    local PLAYER_HL_NAME = "__PlayerTrackerHL__"
    local TREE_HL_NAME   = "__TreeAuraHL__"
    local CHAR_HL_NAME   = "__CharAuraHL__"
    local ESP_BB_NAME    = "ESPText"
    local EDGE_GUI_NAME  = "EdgeButtons"
    local PLACE_BTN_NAME = "PlaceEdge"

    local MAX_HIGHLIGHTS = 1000  -- hard cap to prevent runaway
    local MAX_BILLBOARDS = 1000

    local function isOrphanHighlight(h)
        if not (h and h:IsA("Highlight")) then return false end
        local adornee = h.Adornee
        return (not adornee) or (not adornee.Parent)
    end

    local function isOrphanBillboard(bb)
        if not (bb and bb:IsA("BillboardGui")) then return false end
        local adornee = bb.Adornee
        -- also consider if parent part is gone
        return (not adornee) or (not adornee.Parent) or (not bb.Parent)
    end

    local function dedupeEdgeButtons()
        local pg = lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return end
        local list = {}
        for _, gui in ipairs(pg:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Name == EDGE_GUI_NAME then
                table.insert(list, gui)
            end
        end
        if #list > 1 then
            -- keep the earliest one; destroy others
            for i = 2, #list do
                pcall(function() list[i]:Destroy() end)
            end
        end
        -- ensure only one PlaceEdge under it
        local edge = pg:FindFirstChild(EDGE_GUI_NAME)
        if edge then
            local btns = {}
            for _, ch in ipairs(edge:GetChildren()) do
                if ch:IsA("TextButton") and ch.Name == PLACE_BTN_NAME then
                    table.insert(btns, ch)
                end
            end
            if #btns > 1 then
                for i = 2, #btns do pcall(function() btns[i]:Destroy() end) end
            end
        end
    end

    local function auditOnce()
        -- Highlights
        local hlCount = 0
        for _, inst in ipairs(WS:GetDescendants()) do
            if inst:IsA("Highlight") then
                local n = inst.Name
                if n == PLAYER_HL_NAME or n == TREE_HL_NAME or n == CHAR_HL_NAME then
                    if isOrphanHighlight(inst) then
                        pcall(function() inst:Destroy() end)
                    else
                        hlCount += 1
                    end
                end
            end
        end
        -- Cap highlights if somehow leaked
        if hlCount > MAX_HIGHLIGHTS then
            local trimmed = 0
            for _, inst in ipairs(WS:GetDescendants()) do
                if trimmed >= (hlCount - MAX_HIGHLIGHTS) then break end
                if inst:IsA("Highlight") then
                    local n = inst.Name
                    if n == TREE_HL_NAME or n == CHAR_HL_NAME then
                        pcall(function() inst:Destroy() end)
                        trimmed += 1
                    end
                end
            end
        end

        -- Billboard GUIs (ESP)
        local bbCount = 0
        for _, inst in ipairs(WS:GetDescendants()) do
            if inst:IsA("BillboardGui") and inst.Name == ESP_BB_NAME then
                if isOrphanBillboard(inst) then
                    pcall(function() inst:Destroy() end)
                else
                    bbCount += 1
                end
            end
        end
        if bbCount > MAX_BILLBOARDS then
            local trimmed = 0
            for _, inst in ipairs(WS:GetDescendants()) do
                if trimmed >= (bbCount - MAX_BILLBOARDS) then break end
                if inst:IsA("BillboardGui") and inst.Name == ESP_BB_NAME then
                    pcall(function() inst:Destroy() end)
                    trimmed += 1
                end
            end
        end

        -- Dedupe shared UI
        dedupeEdgeButtons()

        -- Drop invalid tracked references
        local now = os.clock()
        for inst, expire in pairs(_tracked) do
            if (not inst) or (typeof(inst) ~= "Instance") or (not inst.Parent) then
                _tracked[inst] = nil
            elseif expire and now >= expire then
                -- Debris should remove it; clear our entry
                _tracked[inst] = nil
            end
        end
    end

    -- Run auditor at low cadence
    MemoryGuard.StartLoop("__mem_audit__", 5.0, auditOnce)

    ----------------------------------------------------------------------
    -- Optional HUD (toggle with C.Config.MemHUD = true)
    ----------------------------------------------------------------------
    local function makeHud()
        local pg = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
        local gui = Instance.new("ScreenGui")
        gui.Name = "__MemHUD__"
        gui.ResetOnSpawn = false
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.Parent = pg

        local label = Instance.new("TextLabel")
        label.Name = "Stats"
        label.Size = UDim2.new(0, 220, 0, 46)
        label.Position = UDim2.new(0, 8, 0, 8)
        label.BackgroundTransparency = 0.2
        label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        label.TextColor3 = Color3.new(1,1,1)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Top
        label.Font = Enum.Font.Code
        label.TextSize = 14
        label.BorderSizePixel = 0
        label.Parent = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = label

        MemoryGuard.StartLoop("__mem_hud__", 1.0, function()
            local tm  = Stats:GetTotalMemoryUsageMb()
            local lu  = Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.LuaHeap)
            local ins = Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Instances)
            local tex = Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Texture)
            label.Text = string.format("Mem: %.1f MB\nLua: %.1f | Inst: %.1f | Tex: %.1f", tm, lu, ins, tex)
        end)
        return gui
    end

    local function destroyHud()
        MemoryGuard.StopLoop("__mem_hud__")
        local pg = lp:FindFirstChildOfClass("PlayerGui")
        local hud = pg and pg:FindFirstChild("__MemHUD__")
        if hud then pcall(function() hud:Destroy() end) end
    end

    -- Expose API
    C.Util          = C.Util or {}
    C.Util.Janitor  = Janitor
    C.Util.MemGuard = MemoryGuard
    C.Util.ToggleMemHUD = function(on)
        if on then makeHud() else destroyHud() end
    end

    -- Honor config flag if present
    if C.Config and C.Config.MemHUD then
        makeHud()
    end

    -- Safety: clean per-respawn UI duplicates and stale visuals
    MemoryGuard.Connect(lp.CharacterAdded:Connect(function()
        task.delay(2.0, function()
            auditOnce()
        end)
    end))
end
