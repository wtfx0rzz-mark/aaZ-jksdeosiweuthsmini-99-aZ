repeat task.wait() until game:IsLoaded()

-------------------------------------------------------
-- Load UI (WindUI wrapper)
-------------------------------------------------------
local function httpget(u) return game:HttpGet(u) end

local UI = (function()
    local ok, ret = pcall(function()
        return loadstring(httpget("https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/ui.lua"))()
    end)
    if ok and type(ret) == "table" then return ret end
    error("ui.lua failed to load")
end)()

-------------------------------------------------------
-- Environment + Config
-------------------------------------------------------
local C = _G.C or {}
C.Services = C.Services or {
    Players = game:GetService("Players"),
    RS      = game:GetService("ReplicatedStorage"),
    WS      = game:GetService("Workspace"),
    Run     = game:GetService("RunService"),
}
C.LocalPlayer = C.Services.Players.LocalPlayer

C.Config = C.Config or {
    CHOP_SWING_DELAY = 0.55,                 -- Delay between tree hits
    TREE_NAME        = "Small Tree",         -- Model name to detect
    UID_SUFFIX       = "0000000000",         -- Unique ID suffix for hit tracking
    ChopPrefer       = { "Chainsaw", "Strong Axe", "Good Axe", "Old Axe" }, -- Tool priority
}

C.State = C.State or { AuraRadius = 150, Toggles = {} }

-- expose to global env for other modules
_G.C  = C
_G.R  = _G.R or {}
_G.UI = UI

-------------------------------------------------------
-- 🔧 MODULE LOADER SECTION
-------------------------------------------------------
-- Each module attaches its features to the corresponding tab
-- defined in ui.lua (Tabs.Main, Tabs.Combat, Tabs.Bring, Tabs.Auto, Tabs.Visuals)

local paths = {
    Combat  = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/combat.lua",
    Bring   = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/bring.lua",
    Player   = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/player.lua",
    Auto    = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/auto.lua",
    Visuals = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/visuals.lua",
}

for name, url in pairs(paths) do
    local ok, mod = pcall(function()
        return loadstring(game:HttpGet(url))()
    end)
    if ok and type(mod) == "function" then
        pcall(mod, _G.C, _G.R, _G.UI)
    else
        warn(("Failed to load module %s from %s"):format(name, url))
    end
end
