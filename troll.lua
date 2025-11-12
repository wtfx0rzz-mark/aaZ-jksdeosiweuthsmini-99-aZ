-- troll.lua
return function(C, R, UI)
    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Troll
    assert(tab, "Troll tab not found in UI")

    tab:Section({ Title = "Troll" })
    tab:Button({ Title = "Coming soon", Callback = function() end })
end
