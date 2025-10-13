-- ui.lua
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
local Window = WindUI:CreateWindow({ Title = "99 Nights" })
 
-- Define UI Tabs
local Tabs = {
    Main   = Window:Tab({ Title = "Main" }),
    Combat = Window:Tab({ Title = "Combat" }),
    Auto   = Window:Tab({ Title = "Auto" }),
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

-- Create the bottom left badge in the UI
local function createUserBadge(parentGui, attachFrame)
    local sg = Instance.new("ScreenGui")
    sg.Name = "NN_UserBadge"
    sg.IgnoreGuiInset = true
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = parentGui

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
    avatar.Name = "Avatar"
    avatar.BackgroundTransparency = 1
    avatar.Size = UDim2.fromOffset(48, 48)
    avatar.Position = UDim2.fromOffset(10, 9)
    avatar.Parent = frame

    local mask = Instance.new("UICorner")
    mask.CornerRadius = UDim.new(1, 0)
    mask.Parent = avatar

    local display = Instance.new("TextLabel")
    display.Name = "DisplayName"
    display.BackgroundTransparency = 1
    display.Font = Enum.Font.GothamSemibold
    display.TextScaled = false
    display.TextSize = 16
    display.TextXAlignment = Enum.TextXAlignment.Left
    display.TextColor3 = Color3.fromRGB(235, 235, 235)
    display.Position = UDim2.fromOffset(68, 10)
    display.Size = UDim2.new(1, -78, 0, 22)
    display.Parent = frame

    local username = Instance.new("TextLabel")
    username.Name = "UserName"
    username.BackgroundTransparency = 1
    username.Font = Enum.Font.Gotham
    username.TextScaled = false
    username.TextSize = 14
    username.TextXAlignment = Enum.TextXAlignment.Left
    username.TextColor3 = Color3.fromRGB(170, 170, 170)
    username.Position = UDim2.fromOffset(68, 32)
    username.Size = UDim2.new(1, -78, 0, 20)
    username.Parent = frame

    local thumb, _ = Players:GetUserThumbnailAsync(lp.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
    avatar.Image = thumb
    display.Text = lp.DisplayName or lp.Name
    username.Text = "@" .. (lp.Name or "")

    local function place()
        if attachFrame and attachFrame.AbsoluteSize.X > 0 then
            local pos = attachFrame.AbsolutePosition
            local size = attachFrame.AbsoluteSize
            frame.Position = UDim2.fromOffset(pos.X + 12, pos.Y + size.Y - 12)
        else
            frame.Position = UDim2.new(0, 12, 1, -12)
        end
    end

    place()
    local conn1, conn2
    if attachFrame then
        conn1 = attachFrame:GetPropertyChangedSignal("AbsolutePosition"):Connect(place)
        conn2 = attachFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
    else
        RunService.RenderStepped:Connect(place)
    end

    return frame
end

local function findWindowRoot(win)
    local candidate
    pcall(function()
        if win and win.Gui then
            candidate = win.Gui
        end
    end)
    if candidate then return candidate end
    local pg = lp:WaitForChild("PlayerGui", 5)
    return pg
end

local function findAttachFrame()
    local pg = lp:FindFirstChild("PlayerGui")
    if not pg then return nil end
    for _,sg in ipairs(pg:GetChildren()) do
        if sg:IsA("ScreenGui") and sg.Enabled then
            local maxArea, best = 0, nil
            for _,d in ipairs(sg:GetDescendants()) do
                if d:IsA("Frame") then
                    local a = d.AbsoluteSize.X * d.AbsoluteSize.Y
                    if a > maxArea then
                        maxArea = a
                        best = d
                    end
                end
            end
            if best then return best end
        end
    end
    return nil
end

local parentGui = findWindowRoot(Window)
local attach = findAttachFrame()
local UserBadge = createUserBadge(parentGui, attach)

return {
    Lib = WindUI,
    Window = Window,
    Tabs = Tabs,
    UserBadge = UserBadge,
}
