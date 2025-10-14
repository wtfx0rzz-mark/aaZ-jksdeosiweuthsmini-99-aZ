--=====================================================
-- 1337 Nights | Bring Module (Basic)
--=====================================================
-- Displays the text "Ready to go" on the Bring tab
--=====================================================

return function(C, R, UI)
    local Tabs = UI and UI.Tabs or {}
    local tab = Tabs.Bring
    assert(tab, "Bring tab not found in UI")

    tab:Label("Ready to go")
end
