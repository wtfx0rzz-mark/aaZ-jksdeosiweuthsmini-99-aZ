return function(C, R, UI)
    local Tabs = UI and UI.Tabs or {}
    local tab = Tabs.Gather
    if not tab then return end

    tab:Section({ Title = "Gather", Icon = "pickaxe" })

    tab:Toggle({
        Title = "Enable Gathering",
        Value = false,
        Callback = function(_) end
    })

    tab:Button({
        Title = "Gather Now",
        Callback = function() end
    })

    tab:Dropdown({
        Title = "Resource Type",
        Values = { "Logs", "Stone", "Berries" },
        Multi = false,
        AllowNone = true,
        Callback = function(_) end
    })

    tab:Slider({
        Title = "Max Range",
        Value = { Min = 10, Max = 300, Default = 50 },
        Callback = function(_) end
    })
end
