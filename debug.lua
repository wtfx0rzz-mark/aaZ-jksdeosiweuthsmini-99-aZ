return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")

    local tabs = UI and UI.Tabs
    local tab  = tabs and (tabs.Debug or tabs.TPBring or tabs.Auto or tabs.Main)
    assert(tab, "No suitable tab (Debug/TPBring/Auto/Main)")

    tab:Button({
        Title = "Debug Button",
        Callback = function()
            -- no-op
        end
    })
end
