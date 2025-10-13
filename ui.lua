local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
local Window = WindUI:CreateWindow({ Title = "99 Nights" })

local Tabs = {
    Main = Window:Tab({ Title = "Main" }),
    Combat = Window:Tab({ Title = "Combat" }),
    Auto = Window:Tab({ Title = "Auto" }),
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local function findWindowScreenGui()
    local pg = lp:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local bestSG, bestScore = nil, -1
    for _, sg in ipairs(pg:GetChildren()) do
        if sg:IsA("ScreenGui") and sg.Enabled then
            local score = 0
            for _, d in ipairs(sg:GetDescendants()) do
                if d:IsA("TextLabel") and type(d.Text) == "string" then
                    if d.Text == "99 Nights" or d.Text:find("99 Nights") then
                        score = score + 10
                    end
                end
                if d:IsA("Frame") then
                    score = score + 1
                end
            end
            if score > bestScore then
                bestScore = score
                bestSG = sg
            end
        end
    end
    return bestSG
end

local function findMainFrame(sg)
    if not sg then return nil end
    local best, area = nil, 0
    for _, d in ipairs(sg:GetDescendants()) do
        if d:IsA("Frame") and d.Visible then
            local a = d.AbsoluteSize.X * d.AbsoluteSize.Y
            if a > area then
                area = a
                best = d
            end
        end
    end
    return best
end

local function createBadge(parentSG)
    local sg = Instance.new("ScreenGui")
    sg.Name = "NN_UserBadge"
    sg.IgnoreGuiInset = true
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = parentSG or lp:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Name = "Badge"
    frame.Size = UDim2.fromOffset(230, 66)
    frame.AnchorPoint = Vector2.new(0, 1)
    frame.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.Parent = sg

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local avatar = Instance.new("ImageLabel")
    avatar.BackgroundTransparency = 1
    avatar.Size = UDim2.fromOffset(48, 48)
    avatar.Position = UDim2.fromOffset(10, 9)
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
    display.Parent = frame

    local username = Instance.new("TextLabel")
    username.BackgroundTransparency = 1
    username.Font = Enum.Font.Gotham
    username.TextSize = 14
    username.TextXAlignment = Enum.TextXAlignment.Left
    username.TextColor3 = Color3.fromRGB(170, 170, 170)
    username.Position = UDim2.fromOffset(68, 32)
    username.Size = UDim2.new(1, -78, 0, 20)
    username.Parent = frame

    local thumb = Players:GetUserThumbnailAsync(lp.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
    avatar.Image = thumb
    display.Text = lp.DisplayName or lp.Name
    username.Text = "@" .. (lp.Name or "")

    return sg, frame
end

local containerSG = findWindowScreenGui()
local attachFrame = findMainFrame(containerSG)
local badgeSG, badge = createBadge(containerSG or lp:WaitForChild("PlayerGui"))

local function place()
    if attachFrame and attachFrame.AbsoluteSize.X > 0 and attachFrame.Visible then
        local p = attachFrame.AbsolutePosition
        local s = attachFrame.AbsoluteSize
        badge.Position = UDim2.fromOffset(p.X + 12, p.Y + s.Y - 12)
    else
        badge.Position = UDim2.new(0, 12, 1, -12)
    end
end

place()
if attachFrame then
    attachFrame:GetPropertyChangedSignal("AbsolutePosition"):Connect(place)
    attachFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
end
RunService.RenderStepped:Connect(place)

return { Lib = WindUI, Window = Window, Tabs = Tabs, UserBadge = badge }
