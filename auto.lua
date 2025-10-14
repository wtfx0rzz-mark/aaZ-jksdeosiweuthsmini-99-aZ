return function(C, R, UI)
    local Tabs = UI and UI.Tabs or {}
    local tab = Tabs.Auto or Tabs.auto or Tabs.Main
    assert(tab, "Auto tab not found in UI")

    tab:Section({ Title = "Auto Module Loaded ✓" })
    tab:Label({ Title = "This is a test placeholder for the Auto tab." })
    tab:Label({ Title = "If you see this text, the Auto tab loaded successfully." })
end
