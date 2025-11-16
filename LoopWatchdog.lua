-- LoopWatchdog.lua
local RunService = game:GetService("RunService")

local LoopWatchdog = {}
LoopWatchdog.__index = LoopWatchdog

local loops = {}
local nextId = 0

local SUSPICIOUS_IDLE_SEC = 5
local REPORT_INTERVAL_SEC = 10

local function now()
    return os.clock()
end

function LoopWatchdog.register(name, shouldBeActiveFn)
    nextId += 1
    local id = nextId
    loops[id] = {
        id        = id,
        name      = tostring(name or ("loop_" .. id)),
        shouldFn  = shouldBeActiveFn or function() return true end,
        ticks     = 0,
        lastTick  = nil,
        lastState = nil,
        createdAt = now(),
    }
    local self = setmetatable({ _id = id }, LoopWatchdog)
    return self
end

function LoopWatchdog:tick()
    local rec = loops[self._id]
    if not rec then return end
    rec.ticks += 1
    rec.lastTick = now()
end

function LoopWatchdog:stop()
    local rec = loops[self._id]
    if not rec then return end
    rec.lastState = false
end

local function summarize()
    local t = now()
    local activeCount = 0
    local idleButTick = {}
    local staleLoops  = {}

    for _, rec in pairs(loops) do
        local should = true
        local ok, res = pcall(rec.shouldFn)
        if ok then
            should = not not res
        end

        local age   = t - rec.createdAt
        local since = rec.lastTick and (t - rec.lastTick) or math.huge
        local isActive = (rec.lastTick ~= nil and since < 60)

        if should and isActive then
            activeCount += 1
        end

        if (not should) and isActive and since < SUSPICIOUS_IDLE_SEC then
            table.insert(idleButTick, rec)
        end

        if (rec.lastTick == nil and age > 60) then
            table.insert(staleLoops, rec)
        end
    end

    if #idleButTick > 0 or #staleLoops > 0 then
        warn("LoopWatchdog report:")
        warn("  Active loops (should==true & ticking):", activeCount)

        if #idleButTick > 0 then
            warn("  Suspicious loops (ticking but should be OFF):")
            for _,rec in ipairs(idleButTick) do
                local since = rec.lastTick and (t - rec.lastTick) or -1
                warn(string.format("    - %s (id=%d) ticks=%d lastTick=%.1fs ago",
                    rec.name, rec.id, rec.ticks, since))
            end
        end

        if #staleLoops > 0 then
            warn("  Registered but never ticked (maybe unused):")
            for _,rec in ipairs(staleLoops) do
                warn(string.format("    - %s (id=%d) age=%.1fs",
                    rec.name, rec.id, t - rec.createdAt))
            end
        end
    end
end

do
    local accum = 0
    RunService.Heartbeat:Connect(function(dt)
        accum += dt
        if accum >= REPORT_INTERVAL_SEC then
            accum = 0
            summarize()
        end
    end)
end

return LoopWatchdog
