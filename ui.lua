local Players = game:GetService("Players")
local lp = Players.LocalPlayer

-- Load WindUI
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- Create the main window
local Window = WindUI:CreateWindow({
    Title = "1337 Nights",
    Icon = "moon",
    Author = "Mark",
    Folder = "99Nights",
    Size = UDim2.fromOffset(500, 350),
    Transparent = false,
    Theme = "Dark",
    Resizable = true,
    SideBarWidth = 150,
    HideSearchBar = false,
    ScrollBarEnabled = true,

    -- ✅ This enables and anchors the user badge inside the window (bottom-left)
    User = {
        Enabled = true,
        Anonymous = false,
        Callback = function()
            WindUI:Notify({
                Title = "User Info",
                Content = "Logged In As: " .. (lp.DisplayName or lp.Name) .. "",
                Duration = 3,
                Icon = "user"
            })
        end
    },
})

-- Allow toggling the window
Window:SetToggleKey(Enum.KeyCode.V)

-- Define your tabs
local Tabs = {
    Main   = Window:Tab({ Title = "Main",   Icon = "home",   Desc = "Main controls" }),
    Combat = Window:Tab({ Title = "Combat", Icon = "sword",  Desc = "Combat options" }),
    Auto   = Window:Tab({ Title = "Auto",   Icon = "cpu",    Desc = "Automation" }),
}

-- Optional: section examples
Tabs.Main:Section({ Title = "Main Settings", Icon = "settings" })
Tabs.Combat:Section({ Title = "Combat Tools", Icon = "crosshair" })
Tabs.Auto:Section({ Title = "Auto Features", Icon = "zap" })

-- Example toggle
Tabs.Main:Toggle({
    Title = "Example Toggle",
    Value = false,
    Callback = function(state)
        print("Example Toggle:", state)
    end
})

-- Example slider
Tabs.Combat:Slider({
    Title = "Damage Multiplier",
    Value = { Min = 1, Max = 10, Default = 3 },
    Callback = function(value)
        print("Damage Multiplier set to:", value)
    end
})

-- Example button
Tabs.Auto:Button({
    Title = "Run Auto Script",
    Callback = function()
        WindUI:Notify({
            Title = "Auto Script",
            Content = "Running automation...",
            Duration = 3,
            Icon = "zap"
        })
    end
})

-- Return references
return {
    Lib = WindUI,
    Window = Window,
    Tabs = Tabs
}
