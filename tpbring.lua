-- File: modules/tpbring.lua
return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(UI and UI.Tabs and UI.Tabs.TPBring, "tpbring.lua: TPBring tab missing")

    local Players = (C and C.Services and C.Services.Players) or game:GetService("Players")
    local lp = Players.LocalPlayer

    local tab = UI.Tabs.TPBring
    tab:Section({ Title = "TP Bring" })

    local function ensureEdgeUI()
        local pg = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
        local edgeGui = pg:FindFirstChild("EdgeButtons")
        if not edgeGui then
            edgeGui = Instance.new("ScreenGui")
            edgeGui.Name = "EdgeButtons"
            edgeGui.ResetOnSpawn = false
            pcall(function() edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
            edgeGui.Parent = pg
        end

        local stack = edgeGui:FindFirstChild("EdgeStack")
        if not stack then
            stack = Instance.new("Frame")
            stack.Name = "EdgeStack"
            stack.AnchorPoint = Vector2.new(1, 0)
            stack.Position = UDim2.new(1, -6, 0, 6)
            stack.Size = UDim2.new(0, 130, 1, -12)
            stack.BackgroundTransparency = 1
            stack.BorderSizePixel = 0
            stack.Parent = edgeGui

            local list = Instance.new("UIListLayout")
            list.Name = "VList"
            list.FillDirection = Enum.FillDirection.Vertical
            list.SortOrder = Enum.SortOrder.LayoutOrder
            list.Padding = UDim.new(0, 6)
            list.HorizontalAlignment = Enum.HorizontalAlignment.Right
            list.Parent = stack
        end
        return edgeGui, stack
    end

    local function makeEdgeBtn(stack, name, label, order)
        local b = stack:FindFirstChild(name)
        if not b then
            b = Instance.new("TextButton")
            b.Name = name
            b.Size = UDim2.new(1, 0, 0, 30)
            b.Text = label
            b.TextSize = 12
            b.Font = Enum.Font.GothamBold
            b.BackgroundColor3 = Color3.fromRGB(30,30,35)
            b.TextColor3 = Color3.new(1,1,1)
            b.BorderSizePixel = 0
            b.Visible = false
            b.LayoutOrder = order or 1
            b.Parent = stack
            local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = b
        else
            b.Text = label
            b.LayoutOrder = order or b.LayoutOrder
            b.Visible = false
        end
        return b
    end

    local getBtn, stopBtn

    local function showGetOnly()
        local _, stack = ensureEdgeUI()
        if not getBtn then getBtn = makeEdgeBtn(stack, "GetLogsEdge", "Get Logs", 20) end
        if not stopBtn then stopBtn = makeEdgeBtn(stack, "StopLogsEdge", "STOP", 21) end
        getBtn.Visible = true
        stopBtn.Visible = false
    end

    local function wireHandlers()
        if getBtn and not getBtn.__wired then
            getBtn.MouseButton1Click:Connect(function()
                stopBtn.Visible = true
            end)
            getBtn.__wired = true
        end
        if stopBtn and not stopBtn.__wired then
            stopBtn.MouseButton1Click:Connect(function()
                stopBtn.Visible = false
                getBtn.Visible = false
            end)
            stopBtn.__wired = true
        end
    end

    tab:Button({
        Title = "Get Logs",
        Callback = function()
            showGetOnly()
            wireHandlers()
        end
    })
end
