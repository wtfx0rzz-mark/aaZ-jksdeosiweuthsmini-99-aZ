-- File: modules/tpbring.lua
return function(C, R, UI)
    UI = UI or {}
    UI.Tabs = UI.Tabs or {}
    local bringTab = UI.Tabs.Bring
    assert(bringTab, "Bring tab not found")

    local section = bringTab:Section({ Title = "TP Bring" })

    section:Button({
        Title = "Get Logs",
        Callback = function() end
    })
end
