local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
local Window = WindUI:CreateWindow({ Title = "99 Nights" })

local Tabs = {
    Main = Window:Tab({ Title = "Main" }),
    Combat = Window:Tab({ Title = "Combat" }),
    Auto = Window:Tab({ Title = "Auto" }),
}

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local function containsTexts(inst, texts)
    local found = 0
    for _,d in ipairs(inst:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local t = tostring(d.Text or "")
            for _,needle in ipairs(texts) do
                if t == needle or string.find(t, needle, 1, true) then
                    found += 1
                    break
                end
            end
        end
    end
    return found
end

local function findWindowRootFrame()
    local pg = lp:WaitForChild("PlayerGui", 5)
    if not pg then return nil end
    local best, scoreBest = nil, -1
    for _,sg in ipairs(pg:GetChildren()) do
        if sg:IsA("ScreenGui") and sg.Enabled then
            for _,f in ipairs(sg:GetDescendants()) do
                if f:IsA("Frame") and f.Visible then
                    local score = 0
                    score += containsTexts(f, {"99 Nights"}) * 100000
                    score += containsTexts(f, {"Main","Combat","Auto"}) * 1000
                    score += math.floor(f.AbsoluteSize.X * f.AbsoluteSize.Y)
                    if score > scoreBest then
                        scoreBest = score
                        best = f
                    end
                end
            end
        end
    end
    if not best then return nil end
    local root = best
    while root and root.Parent and root.Parent ~= root.Parent.Parent and root.Parent:IsA("Frame") do
        root = root.Parent
    end
    return root
end

local function createBadge(parentFrame)
    local frame = Instance.new("Frame")
    frame.Name = "NN_UserBadge"
    frame.Size = UDim2.fromOffset(230, 66)
    frame.AnchorPoint = Vector2.new(0, 1)
    frame.Position = UDim2.new(0, 12, 1, -12)
    frame.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.ZIndex = 1000
    frame.Parent = parentFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local avatar = Instance.new("ImageLabel")
    avatar.BackgroundTransparency = 1
    avatar.Size = UDim2.fromOffset(48, 48)
    avatar.Position = UDim2.fromOffset(10, 9)
    avatar.ZIndex = 1001
    avatar.Parent = frame

    local mask = Instance.new("UICorner")
    mask.CornerRadius = UDim.new(1, 0)
    mask.Parent = avatar

    local display = Instance.new("TextLabel")
    display.BackgroundTransparency = 1
    display.Font = Enum.Font.GothamSemibold
    display.TextSize = 16
    display.TextXAlignment = Enum.TextXAlignment.Left
    display.TextColor3 = Color3.fromRGB(235, 235, 235)
    display.Position = UDim2.fromOffset(68, 10)
    display.Size = UDim2.new(1, -78, 0, 22)
    display.ZIndex = 1001
    display.Parent = frame

    local username = Instance.new("TextLabel")
    username.BackgroundTransparency = 1
    username.Font = Enum.Font.Gotham
    username.TextSize = 14
    username.TextXAlignment = Enum.TextXAlignment.Left
    username.TextColor3 = Color3.fromRGB(170, 170, 170)
    username.Position = UDim2.fromOffset(68, 32)
    username.Size = UDim2.new(1, -78, 0, 20)
    username.ZIndex = 1001
    username.Parent = frame

    local thumb = Players:GetUserThumbnailAsync(lp.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
    avatar.Image = thumb
    display.Text = lp.DisplayName or lp.Name
    username.Text = "@" .. (lp.Name or "")

    return frame
end

local root = findWindowRootFrame() or lp:WaitForChild("PlayerGui")
local UserBadge = createBadge(root)

return { Lib = WindUI, Window = Window, Tabs = Tabs, UserBadge = UserBadge }
