repeat task.wait() until game:IsLoaded()
print("[99 Nights] Game loaded, initializing...")

local ok, UI = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/main/ui.lua"))()
end)

if not ok or not UI then
    warn("[99 Nights] Failed to load UI module:", UI)
    return
end

print("[99 Nights] UI module loaded successfully.")
local Tabs = UI.Tabs
print("[99 Nights] Available Tabs:", Tabs and table.concat({"Main","Combat","Auto"}, ", ") or "None")
print("[99 Nights] Initialization complete.")
