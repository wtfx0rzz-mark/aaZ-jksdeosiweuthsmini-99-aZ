--========================
-- Bring Lost Child (HRP hop fix)
--========================
local Run = C.Services.Run or game:GetService("RunService")

local APPROACH_DIST = 2.0        -- how close to appear next to the child
local HOP_HB_NEAR   = 3          -- heartbeats to wait after hopping near child
local HOP_HB_BACK   = 3          -- heartbeats to wait after hopping back home
local MAX_RETRIES   = 3          -- how many invisible hop attempts if child didn't attach

local function waitHeartbeats(n)
    for _=1,(n or 1) do Run.Heartbeat:Wait() end
end

local function groundAt(pos)
    local start = pos + Vector3.new(0, 500, 0)
    local rc = WS:Raycast(start, Vector3.new(0, -2000, 0))
    return rc and rc.Position or pos
end

local function approachCFForPart(part, homePos)
    local p = part.Position
    local dir = (homePos and (homePos - p).Unit) or Vector3.new(1,0,0)
    if dir.Magnitude == 0 then dir = Vector3.new(1,0,0) end
    local flatDir = Vector3.new(dir.X, 0, dir.Z)
    if flatDir.Magnitude == 0 then flatDir = Vector3.new(1,0,0) end
    flatDir = flatDir.Unit
    local target = p + flatDir * APPROACH_DIST
    local gp = groundAt(target) + Vector3.new(0, 3, 0)
    return CFrame.lookAt(gp, Vector3.new(p.X, gp.Y, p.Z))
end

local function hopHRPOnce(targetPart)
    local root = hrp()
    if not (root and targetPart) then return end
    local homeCF = root.CFrame
    -- hop near child
    local nearCF = approachCFForPart(targetPart, homeCF.Position)
    root.AssemblyLinearVelocity  = Vector3.new()
    root.AssemblyAngularVelocity = Vector3.new()
    root.CFrame = nearCF
    waitHeartbeats(HOP_HB_NEAR)
    -- hop back home
    root.AssemblyLinearVelocity  = Vector3.new()
    root.AssemblyAngularVelocity = Vector3.new()
    root.CFrame = homeCF
    waitHeartbeats(HOP_HB_BACK)
end

local function findNearestLostChild()
    local chars = WS:FindFirstChild("Characters")
    if not chars then return nil end
    local root = hrp()
    if not root then return nil end
    local nearest, best = nil, math.huge
    for _,m in ipairs(chars:GetChildren()) do
        if m:IsA("Model") then
            local n = m.Name or ""
            -- Matches: "Lostchild" or "Lostchild 123"
            if n == "Lostchild" or n:match("^Lostchild%s*%d+$") then
                local mp = mainPart(m)
                if mp then
                    local d = (mp.Position - root.Position).Magnitude
                    if d < best then
                        best = d
                        nearest = m
                    end
                end
            end
        end
    end
    return nearest
end

local function bringLostChild_HRPHop()
    local child = findNearestLostChild()
    if not child then return end
    local mp = mainPart(child)
    if not mp then return end

    -- Try up to MAX_RETRIES invisible hops until the child is close enough
    for i=1,MAX_RETRIES do
        hopHRPOnce(mp)
        -- if child already close enough, stop early
        local root = hrp()
        if root and mp and (mp.Position - root.Position).Magnitude <= 12 then
            break
        end
    end
end

-- Button: Bring Lost Child (HRP hop)
tab:Button({
    Title = "Bring Lost Child",
    Callback = function()
        bringLostChild_HRPHop()
    end
})
