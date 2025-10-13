-- main.lua
repeat task.wait() until game:IsLoaded()
print("[99 Nights] Game loaded, initializing...")

local httpget = function(url)
    return game:HttpGet(url)
end

-- Load the UI module (WindUI-based)
local success, UI = pcall(function()
    return loadstring(httpget("https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/ui.lua"))()
end)

if not success or not UI then
    warn("[99 Nights] Failed to load UI module:", UI)
    return
end

print("[99 Nights] UI module loaded successfully.")

-- Optionally reference tabs
local Tabs = UI.Tabs
print("[99 Nights] Available Tabs:", Tabs and table.concat({"Main","Combat","Auto"}, ", ") or "None")

-- Example placeholder for future modules
-- local Combat = loadstring(httpget("https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/combat.lua"))()
-- local Auto   = loadstring(httpget("https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/auto.lua"))()

print("[99 Nights] Initialization complete.")
