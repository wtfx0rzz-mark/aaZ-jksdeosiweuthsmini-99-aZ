--=====================================================
-- 1337 Nights | Main Module
--=====================================================
-- Adds: 
--   • “Small Tree Aura” toggle on Main tab
--   • “Aura Distance” slider to control range (0–1000)
--   • Automatic tool selection (Chainsaw → Strong Axe → Good Axe → Old Axe)
--   • Tree-chopping logic extracted cleanly from Combat module
--=====================================================

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
local C = {}
C.Services = {
    Players = game:GetService("Players"),
    RS      = game:GetService("ReplicatedStorage"),
    WS      = game:GetService("Workspace"),
    Run     = game:GetService("RunService"),
}
C.LocalPlayer = C.Services.Players.LocalPlayer

C.Config = {
    CHOP_SWING_DELAY = 0.55,                 -- Delay between tree hits
    TREE_NAME        = "Small Tree",         -- Model name to detect
    UID_SUFFIX       = "0000000000",         -- Unique ID suffix for hit tracking
    ChopPrefer       = { "Chainsaw", "Strong Axe", "Good Axe", "Old Axe" }, -- Tool priority
}

C.State = C.State or { AuraRadius = 150, Toggles = {} }

-------------------------------------------------------
-- Helper Functions
-------------------------------------------------------

-- Incremental hit ID for RPC calls
local _hitCounter = 0
local function nextHitId()
    _hitCounter += 1
    return tostring(_hitCounter) .. "_" .. C.Config.UID_SUFFIX
end

-- Locate a tool in the player's Inventory
local function findInInventory(name)
    local inv = C.LocalPlayer and C.LocalPlayer:FindFirstChild("Inventory")
    return inv and inv:FindFirstChild(name) or nil
end

-- Return currently equipped tool name
local function equippedToolName()
    local ch = C.LocalPlayer and C.LocalPlayer.Character
    if not ch then return nil end
    local t = ch:FindFirstChildOfClass("Tool")
    return t and t.Name or nil
end

-- Safely equip a tool by firing server event
local function SafeEquip(tool)
    if not tool then return end
    local ev = C.Services.RS:FindFirstChild("RemoteEvents")
    ev = ev and ev:FindFirstChild("EquipItemHandle")
    if ev then ev:FireServer("FireAllClients", tool) end
end

-- Ensure the correct tool is equipped
local function ensureEquipped(wantedName)
    if not wantedName then return nil end
    if equippedToolName() == wantedName then
        return findInInventory(wantedName)
    end
    local tool = findInInventory(wantedName)
    if tool then SafeEquip(tool) end
    return tool
end

-- Find the best BasePart on the tree to hit
local function bestTreeHitPart(tree)
    if not tree or not tree:IsA("Model") then return nil end
    local hr = tree:FindFirstChild("HitRegisters")
    if hr then
        local t = hr:FindFirstChild("Trunk")
        if t and t:IsA("BasePart") then return t end
        local any = hr:FindFirstChildWhichIsA("BasePart")
        if any then return any end
    end
    local t2 = tree:FindFirstChild("Trunk")
    if t2 and t2:IsA("BasePart") then return t2 end
    return tree.PrimaryPart or tree:FindFirstChildWhichIsA("BasePart")
end

-- Compute impact position + rotation for RPC call
local function computeImpactCFrame(model, hitPart)
    if not (model and hitPart and hitPart:IsA("BasePart")) then
        return hitPart and CFrame.new(hitPart.Position) or CFrame.new()
    end
    local outward = hitPart.CFrame.LookVector
    if outward.Magnitude == 0 then outward = Vector3.new(0,0,-1) end
    outward = outward.Unit
    local origin  = hitPart.Position + outward * 1.0
    local dir     = -outward * 5.0
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {model}
    local rc = C.Services.WS:Raycast(origin, dir, params)
    local pos = rc and (rc.Position + rc.Normal*0.02) or (origin + dir*0.6)
    local rot = hitPart.CFrame - hitPart.CFrame.Position
    return CFrame.new(pos) * rot
end

-- Send hit request to the server
local function HitTree(tree, tool, hitId, impactCF)
    local evs = C.Services.RS:FindFirstChild("RemoteEvents")
    local dmg = evs and evs:FindFirstChild("ToolDamageObject")
    if not dmg then return end
    dmg:InvokeServer(tree, tool, hitId, impactCF)
end

-------------------------------------------------------
-- Core Logic
-------------------------------------------------------

local running = { SmallTree=false }

-- Perform one chop "wave" across all nearby trees
local function chopWaveForTrees(trees, swingDelay)
    local toolName
    for _, n in ipairs(C.Config.ChopPrefer) do
        if findInInventory(n) then toolName = n break end
    end
    if not toolName then task.wait(0.35) return end
    local tool = ensureEquipped(toolName)
    if not tool then task.wait(0.35) return end

    for _, tree in ipairs(trees) do
        task.spawn(function()
            local hitPart = bestTreeHitPart(tree)
            if hitPart then
                local impactCF = computeImpactCFrame(tree, hitPart)
                local hitId = nextHitId()
                HitTree(tree, tool, hitId, impactCF)
            end
        end)
    end

    task.wait(swingDelay)
end

-- Main chop loop
local function startSmallTreeAura()
    if running.SmallTree then return end
    running.SmallTree = true
    task.spawn(function()
        while running.SmallTree do
            local character = C.LocalPlayer.Character or C.LocalPlayer.CharacterAdded:Wait()
            local hrp = character:FindFirstChild("HumanoidRootPart")
            if not hrp then task.wait(0.2) break end
            local origin = hrp.Position
            local radius = tonumber(C.State.AuraRadius) or 150
            local trees = {}
            local map = C.Services.WS:FindFirstChild("Map")

            local function scan(folder)
                if not folder then return end
                for _, obj in ipairs(folder:GetChildren()) do
                    if obj:IsA("Model") and obj.Name == C.Config.TREE_NAME then
                        local trunk = bestTreeHitPart(obj)
                        if trunk and (trunk.Position - origin).Magnitude <= radius then
                            trees[#trees+1] = obj
                        end
                    end
                end
            end

            if map then
                scan(map:FindFirstChild("Foliage"))
                scan(map:FindFirstChild("Landmarks"))
            end

            if #trees > 0 then
                chopWaveForTrees(trees, C.Config.CHOP_SWING_DELAY)
            else
                task.wait(0.3)
            end
        end
    end)
end

-- Stop loop
local function stopSmallTreeAura()
    running.SmallTree = false
end

-------------------------------------------------------
-- UI Binding
-------------------------------------------------------

local Main = UI and UI.Tabs and UI.Tabs.Main
if not Main then error("Main tab unavailable") end

-- Main toggle
Main:Section({ Title = "Small Tree Aura" })
Main:Toggle({
    Title = "Small Tree Aura",
    Value = false,
    Callback = function(on)
        C.State.Toggles.SmallTreeAura = on
        if on then startSmallTreeAura() else stopSmallTreeAura() end
    end
})

-- Aura distance slider
Main:Section({ Title = "Aura Distance" })
Main:Slider({
    Title = "Distance",
    Value = { Min = 0, Max = 1000, Default = C.State.AuraRadius or 150 },
    Callback = function(v)
        C.State.AuraRadius = math.clamp(tonumber(v) or 150, 0, 1000)
    end
})

-------------------------------------------------------
-- 🔧 MODULE LOADER SECTION
-- Use this area to include additional modules such as Visuals, Combat, etc.

-- Apply both lines for each new tab. 
local Visuals = loadstring(game:HttpGet("https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/visuals.lua"))()
Visuals(C, R, UI)

-------------------------------------------------------

