--========================
-- Placeholder block (safe no-op)
--========================
tab:Section({ Title = "Placeholders", Icon = "clock" })

tab:Button({
    Title = "Bring Lost Child (placeholder)",
    Callback = function()
        -- no-op: just give a tiny visual ping so users know it's not implemented yet
        local old = "Bring Lost Child (placeholder)"
        -- Wind's Button helper doesn't expose the instance; re-add a transient toast via a temporary edge button
        local pg = lp:WaitForChild("PlayerGui")
        local sg = pg:FindFirstChild("EdgeButtons") or Instance.new("ScreenGui")
        if not sg.Parent then
            sg.Name = "EdgeButtons"
            sg.ResetOnSpawn = false
            sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            sg.Parent = pg
        end
        local tip = Instance.new("TextLabel")
        tip.Name = "PlaceholderToast"
        tip.AnchorPoint = Vector2.new(1, 0)
        tip.Position = UDim2.new(1, -6, 0, 6 + (4-1)*36) -- row 4 under existing edge buttons
        tip.Size = UDim2.new(0, 160, 0, 30)
        tip.BackgroundColor3 = Color3.fromRGB(30,30,35)
        tip.BorderSizePixel = 0
        tip.TextColor3 = Color3.new(1,1,1)
        tip.Font = Enum.Font.GothamBold
        tip.TextSize = 12
        tip.Text = "Coming soon…"
        tip.Parent = sg
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = tip
        task.delay(1.2, function()
            if tip then tip:Destroy() end
        end)
    end
})
