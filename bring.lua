-- add near other locals at top-level inside the module:
local RETURN_DELAY_SEC = 20
local DIAMOND_SKIP_RADIUS = 5
local broughtOnce    = setmetatable({}, {__mode="k"}) -- chests already brought at least once
local returningNow   = setmetatable({}, {__mode="k"}) -- chests currently out
local origCFByChest  = setmetatable({}, {__mode="k"})

local function isChestName(n)
    n = string.lower(n or "")
    return n:match("^item chest%d*$") or n:match("^snow chest%d*$")
end

local function getDiamondCenters()
    local centers = {}
    for _,m in ipairs(WS:GetDescendants()) do
        if m:IsA("Model") and string.lower(m.Name) == "stronghold diamond chest" then
            local mp = mainPart(m)
            if mp then centers[#centers+1] = mp.Position end
        end
    end
    return centers
end

local function isNearAnyDiamond(pos, centers)
    for _,p in ipairs(centers) do
        if (p - pos).Magnitude <= DIAMOND_SKIP_RADIUS then return true end
    end
    return false
end

local function pickNextChest()
    local root = hrp(); if not root then return nil end
    local centers = getDiamondCenters()
    local best, bestD
    for _,m in ipairs(WS:GetDescendants()) do
        if m:IsA("Model") and isChestName(m.Name) and not isExcludedModel(m) and not broughtOnce[m] and not returningNow[m] then
            local mp = mainPart(m)
            if mp and not isNearAnyDiamond(mp.Position, centers) then
                local d = (mp.Position - root.Position).Magnitude
                if not bestD or d < bestD then best, bestD = m, d end
            end
        end
    end
    return best
end

local function bringOneChest()
    local chest = pickNextChest(); if not chest then return end
    local dropCF = computeForwardDropCF(); if not dropCF then return end

    origCFByChest[chest] = chest:GetPivot()
    broughtOnce[chest]   = true
    returningNow[chest]  = true

    moveModel(chest, dropCF)

    task.delay(RETURN_DELAY_SEC, function()
        if chest and chest.Parent and origCFByChest[chest] then
            moveModel(chest, origCFByChest[chest])
        end
        returningNow[chest] = nil
        -- keep broughtOnce[chest] = true so we won't pick it again
    end)
end
