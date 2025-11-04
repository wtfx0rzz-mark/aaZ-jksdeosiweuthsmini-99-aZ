-- File: modules/tpbring.lua
return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(UI and UI.Tabs and UI.Tabs.TPBring, "tpbring.lua: TPBring tab missing")

    local tab = UI.Tabs.TPBring
    tab:Section({ Title = "TP Bring" })
    tab:Button({
        Title = "Get Logs",
        Callback = function() end
    })
end
