return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local RS      = C.Services.RS
    local Run     = C.Services.Run or game:GetService("RunService")
    local lp      = Players.LocalPlayer

    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Bring
    assert(tab, "TPBring tab not found in UI")


    local section = bringTab:Section({ Title = "TP Bring" })

    section:Button({
        Title = "Get Logs",
        Callback = function() end
    })
end
