return function(C, R, UI)
    local Tabs = UI and UI.Tabs or {}
    local tab = Tabs.Bring or Tabs.br or Tabs.Main
    assert(tab, "Bring tab not found in UI")

    tab:Section({ Title = "Bring Module Loaded ✓" })
    tab:Label({ Title = "This is a test placeholder for the Bring tab." })
    tab:Label({ Title = "If you see this text, the tab loaded successfully." })
end
