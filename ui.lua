-- ui.lua
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
local Window = WindUI:CreateWindow({ Title = "99 Nights" })

local Tabs = {
    Main   = Window:Tab({ Title = "Main" }),
    Combat = Window:Tab({ Title = "Combat" }),
    Auto   = Window:Tab({ Title = "Auto" }),
}

return {
    Lib = WindUI,
    Window = Window,
    Tabs = Tabs,
}
