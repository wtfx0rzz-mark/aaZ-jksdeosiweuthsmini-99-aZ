-- File: modules/tpbring.lua
return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")
    local UIS      = (C and C.Services and C.Services.UIS)      or game:GetService("UserInputService")

    local lp = Players.LocalPlayer

    C.State = C.State or {}
    C.State.TpBringEnabled = C.State.TpBringEnabled or false
    C.State.TpBringRadius  = tonumber(C.State.TpBringRadius) or 100

    UI = UI or {}
    UI.Tabs = UI.Tabs or {}
    local bringTab = UI.Tabs.Bring
    assert(bringTab, "Bring tab not found")

    local section = (bringTab.Section and bringTab:Section("TP Bring")) or bringTab

    local toggleCtl = section:Toggle({
        Title = "TP Bring",
        Default = C.State.TpBringEnabled,
        Callback = function(v)
            C.State.TpBringEnabled = not not v
        end
    })

    section:Slider({
        Title = "Radius",
        Value = { Min = 5, Max = 200, Default = C.State.TpBringRadius },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then
                nv = v.Value or v.Current or v.CurrentValue or v.Default or v.min or v.max
            end
            nv = tonumber(nv)
            if nv then
                C.State.TpBringRadius = math.clamp(nv, 5, 200)
            end
        end
    })

    section:Button({
        Title = "Get Logs",
        Callback = function()
            -- no-op for now
        end
    })

    local Conns = {}
    local Running = false

    local function disconnectAll()
        for k,cn in pairs(Conns) do
            if cn and cn.Disconnect then cn:Disconnect() end
            Conns[k] = nil
        end
    end

    local function tickEnabled(dt)
    end

    local function start()
        if Running then return end
        Running = true
        Conns.heartbeat = Run.Heartbeat:Connect(function(dt)
            if not C.State.TpBringEnabled then return end
            local ch = lp.Character
            if not ch then return end
            tickEnabled(dt)
        end)
    end

    local function stop()
        Running = false
        disconnectAll()
    end

    if C.State.TpBringEnabled then start() end

    if toggleCtl and toggleCtl.Set then
        local last = C.State.TpBringEnabled
        Conns.sync = Run.Heartbeat:Connect(function()
            if C.State.TpBringEnabled ~= last then
                last = C.State.TpBringEnabled
                toggleCtl:Set(last)
                if last then start() else stop() end
            end
        end)
    else
        Conns.guard = Run.Heartbeat:Connect(function()
            if C.State.TpBringEnabled and not Running then start()
            elseif (not C.State.TpBringEnabled) and Running then stop() end
        end)
    end

    local M = {}
    function M.Stop()
        stop()
    end
    return M
end
