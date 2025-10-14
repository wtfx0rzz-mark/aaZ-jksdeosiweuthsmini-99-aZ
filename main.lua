--=====================================================
-- 1337 Nights | Main Module
--=====================================================
-- Loader + global context. Combat/Visuals modules attach to WindUI tabs.
--=====================================================
--[[====================================================================
 🧠 GPT INTEGRATION NOTE
 ----------------------------------------------------------------------
 All modules in this project (main.lua, visuals.lua, combat.lua, etc.)
 share a unified global environment:
     _G.C  → Global Config, State, Services, Shared tables
     _G.R  → Shared runtime helpers (functions used across modules)
     _G.UI → WindUI instance (window + tabs)

 Modules should assume these exist and avoid returning UI/context.
====================================================================]]

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
local Visuals = loadstring(game:HttpGet("https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/visuals.lua"))()
Visuals(C, _G.R, UI)

local Combat  = loadstring(game:HttpGet("https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/combat.lua"))()
Combat(C, _G.R, UI)

local Bring  = loadstring(game:HttpGet("https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/bring.lua"))()
Bring(C, _G.R, UI)

--local Auto  = loadstring(game:HttpGet("https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/combat.lua"))()
--Auto(C, _G.R, UI)
