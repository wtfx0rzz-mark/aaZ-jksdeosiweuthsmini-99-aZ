local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

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
    User = {
        Enabled = true,
        Anonymous = false,
        Callback = function()
            WindUI:Notify({
                Title = "User Info",
                Content = "Logged In As: " .. (lp.DisplayName or lp.Name),
                Duration = 3,
                Icon = "user"
            })
        end
    },
})

Window:SetToggleKey(Enum.KeyCode.V)

local Tabs = {
    Main   = Window:Tab({ Title = "Main",   Icon = "home",  Desc = "Main controls" }),
    Combat = Window:Tab({ Title = "Combat", Icon = "sword", Desc = "Combat options" }),
    Bring   = Window:Tab({ Title = "Bring",   Icon = "backpack",   Desc = "Bring Items" }),
    Gather   = Window:Tab({ Title = "Gather",   Icon = "eye",   Desc = "Gather" }),
    Player   = Window:Tab({ Title = "Player",   Icon = "activity",   Desc = "Player options" }),
    Auto   = Window:Tab({ Title = "Auto",   Icon = "cpu",   Desc = "Automation" }),
    Visuals   = Window:Tab({ Title = "Visuals",   Icon = "eye",   Desc = "Visuals" }),
}

return {
    Lib = WindUI,
    Window = Window,
    Tabs = Tabs
}
