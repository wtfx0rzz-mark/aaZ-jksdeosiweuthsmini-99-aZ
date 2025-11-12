-- Live config (read every tick)
local CFG = {
    Speed        = 1.0,   -- 0.5–3.0: higher = faster swirl
    TightMin     = 2.0,   -- 1–6: inner radius
    TightMax     = 9.0,   -- 4–18: outer radius
    HeightBase   = 0.5,   -- -3–3: bias around HRP Y
    HeightRange  = 3.0,   -- 0.5–8: vertical spread
    JitterScale  = 1.0,   -- 0.5–2: scales all jitter amplitudes
    MaxLogs      = 50,    -- 5–150: Stop→Start to apply
}

-- Replace your constants to pull from CFG dynamically
local function cloudParams()
    return {
        Rmin = CFG.TightMin,
        Rmax = CFG.TightMax,
        Hbase = CFG.HeightBase,
        Hmin  = -math.abs(CFG.HeightRange)*0.66,
        Hmax  =  math.abs(CFG.HeightRange),
        JXZ1  = 1.4 * CFG.JitterScale,
        JXZ2  = 0.9 * CFG.JitterScale,
        JY1   = 0.9 * CFG.JitterScale,
        JY2   = 0.6 * CFG.JitterScale,
        Speed = CFG.Speed,
    }
end
