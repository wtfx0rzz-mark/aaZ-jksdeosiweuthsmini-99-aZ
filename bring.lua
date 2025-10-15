local Players = game:GetService("Players")
local Run = game:GetService("RunService")
local WS = game:GetService("Workspace")
local lp = Players.LocalPlayer

local Streamer = {}
Streamer.__index = Streamer

function Streamer.new(radius, bin, stride, cooldown)
    local self = setmetatable({}, Streamer)
    self.radius = radius or 256
    self.bin = bin or 96
    self.stride = stride or 20
    self.cooldown = cooldown or 3
    self.lastCenter = Vector3.zero
    self.binNext = {}
    self.queue = {}
    self.qi = 1
    return self
end

local function keyFromXYZ(x,y,z,bin)
    return math.floor(x/bin)..","..math.floor(y/bin)..","..math.floor(z/bin)
end

function Streamer:enqueueBins(center)
    local r = self.radius
    local b = self.bin
    local min = center - Vector3.new(r,r,r)
    local max = center + Vector3.new(r,r,r)
    local ix0, iy0, iz0 = math.floor(min.X/b), math.floor(min.Y/b), math.floor(min.Z/b)
    local ix1, iy1, iz1 = math.floor(max.X/b), math.floor(max.Y/b), math.floor(max.Z/b)
    local r2 = r*r
    for ix=ix0,ix1 do
        for iy=iy0,iy1 do
            for iz=iz0,iz1 do
                local cx = ix*b + b*0.5
                local cy = iy*b + b*0.5
                local cz = iz*b + b*0.5
                local p = Vector3.new(cx,cy,cz)
                if (p - center).Magnitude^2 <= r2 then
                    local k = ix..","..iy..","..iz
                    local t = self.binNext[k]
                    local now = os.clock()
                    if not t or now >= t then
                        self.binNext[k] = now + self.cooldown
                        self.queue[#self.queue+1] = p
                    end
                end
            end
        end
    end
end

function Streamer:tick(getCenter)
    if not WS.StreamingEnabled then return end
    local hrp = getCenter()
    if not hrp then return end
    local c = hrp.Position
    if (c - self.lastCenter).Magnitude >= self.bin then
        self.lastCenter = c
        self:enqueueBins(c)
        self.qi = 1
    end
    local limit = math.min(self.stride, #self.queue - (self.qi-1))
    for i=1,limit do
        local idx = self.qi; self.qi = self.qi + 1
        local pos = self.queue[idx]
        pcall(function() lp:RequestStreamAroundAsync(pos) end)
        pcall(function() WS:RequestStreamAroundAsync(pos) end)
    end
    if self.qi > #self.queue then
        self.queue = {}; self.qi = 1
    end
end

return function(auraRadius)
    local s = Streamer.new(auraRadius or 300, 96, 24, 3.0)
    Run.Heartbeat:Connect(function()
        s:tick(function()
            local ch = lp.Character
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
            return hrp
        end)
    end)
    return s
end
