return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    local Players = (C and C.Services and C.Services.Players) or game:GetService("Players")
    local RS      = (C and C.Services and C.Services.RS)      or game:GetService("ReplicatedStorage")
    local WS      = (C and C.Services and C.Services.WS)      or game:GetService("Workspace")
    local Run     = (C and C.Services and C.Services.Run)     or game:GetService("RunService")

    local lp = Players.LocalPlayer
    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    local UID = (C and C.Config and C.Config.UID_SUFFIX) or "0000000000"
    local TREE_NAMES = { ["Small Tree"]=true, ["Snowy Small Tree"]=true, ["Small Webbed Tree"]=true }

    local function bestTreeHitPart(tree)
        if not tree or not tree:IsA("Model") then return nil end
        local hr = tree:FindFirstChild("HitRegisters")
        if hr then
            local t = hr:FindFirstChild("Trunk")
            if t and t:IsA("BasePart") then return t end
            local any = hr:FindFirstChildWhichIsA("BasePart")
            if any then return any end
        end
        local t2 = tree:FindFirstChild("Trunk")
        if t2 and t2:IsA("BasePart") then return t2 end
        return tree.PrimaryPart or tree:FindFirstChildWhichIsA("BasePart")
    end

    local function dist2(a, b)
        local v = a - b
        return v.X*v.X + v.Y*v.Y + v.Z*v.Z
    end

    local pg = lp:WaitForChild("PlayerGui")
    local sg = Instance.new("ScreenGui")
    sg.Name = "ChopDebugUI"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.Parent = pg

    local frame = Instance.new("Frame")
    frame.Name = "Win"
    frame.Size = UDim2.new(0, 360, 0, 220)
    frame.Position = UDim2.new(1, -380, 0, 60)
    frame.BackgroundColor3 = Color3.fromRGB(16,16,16)
    frame.BackgroundTransparency = 0.25
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = sg

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 28)
    bar.BackgroundColor3 = Color3.fromRGB(30,30,30)
    bar.BorderSizePixel = 0
    bar.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -140, 1, 0)
    title.Position = UDim2.new(0, 8, 0, 0)
    title.BackgroundTransparency = 1
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.Code
    title.TextSize = 14
    title.TextColor3 = Color3.fromRGB(230,230,230)
    title.Text = "Chop Debug"
    title.Parent = bar

    local countLbl = Instance.new("TextLabel")
    countLbl.Size = UDim2.new(0, 120, 1, 0)
    countLbl.Position = UDim2.new(1, -120, 0, 0)
    countLbl.BackgroundTransparency = 1
    countLbl.TextXAlignment = Enum.TextXAlignment.Right
    countLbl.Font = Enum.Font.Code
    countLbl.TextSize = 14
    countLbl.TextColor3 = Color3.fromRGB(180,180,180)
    countLbl.Text = "Range: 0"
    countLbl.Parent = bar

    local copyBtn = Instance.new("TextButton")
    copyBtn.Size = UDim2.new(0, 52, 0, 24)
    copyBtn.Position = UDim2.new(0, 6, 0, 30)
    copyBtn.Text = "Copy"
    copyBtn.Font = Enum.Font.Code
    copyBtn.TextSize = 14
    copyBtn.BackgroundColor3 = Color3.fromRGB(45,45,45)
    copyBtn.TextColor3 = Color3.fromRGB(235,235,235)
    copyBtn.Parent = frame

    local clearBtn = copyBtn:Clone()
    clearBtn.Position = UDim2.new(0, 64, 0, 30)
    clearBtn.Text = "Clear"
    clearBtn.Parent = frame

    local closeBtn = copyBtn:Clone()
    closeBtn.Position = UDim2.new(0, 122, 0, 30)
    closeBtn.Text = "Close"
    closeBtn.Parent = frame

    local box = Instance.new("TextBox")
    box.MultiLine = true
    box.ClearTextOnFocus = false
    box.Size = UDim2.new(1, -12, 1, -60)
    box.Position = UDim2.new(0, 6, 0, 58)
    box.Font = Enum.Font.Code
    box.TextSize = 13
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.TextYAlignment = Enum.TextYAlignment.Top
    box.TextWrapped = false
    box.TextEditable = true
    box.Text = ""
    box.PlaceholderText = ""
    box.RichText = false
    box.BackgroundColor3 = Color3.fromRGB(18,18,18)
    box.TextColor3 = Color3.fromRGB(220,220,220)
    box.Parent = frame

    local lines = {}
    local maxChars = 120000
    local function now()
        local t = os.clock()
        local s = math.floor(t % 60)
        local m = math.floor((t/60) % 60)
        return string.format("%02d:%02d", m, s)
    end
    local function push(msg)
        lines[#lines+1] = "["..now().."] "..msg
        if #lines > 4000 then
            for i=1,1000 do table.remove(lines,1) end
        end
        local t = table.concat(lines, "\n")
        if #t > maxChars then
            t = string.sub(t, #t - maxChars + 1)
        end
        box.Text = t
        box.CursorPosition = #box.Text + 1
    end

    copyBtn.MouseButton1Click:Connect(function()
        local t = box.Text
        local ok = false
        if typeof(setclipboard) == "function" then
            local s, e = pcall(setclipboard, t)
            ok = s and e == nil
        end
        if not ok and getgenv then
            local f = getgenv().setclipboard or getgenv().setrbxclipboard
            if typeof(f) == "function" then pcall(f, t) end
        end
        box:CaptureFocus()
        box.SelectionStart = 1
        box.CursorPosition = #box.Text + 1
    end)
    clearBtn.MouseButton1Click:Connect(function()
        lines = {}
        box.Text = ""
    end)
    closeBtn.MouseButton1Click:Connect(function()
        sg:Destroy()
    end)

    local Index = { TreesSet = {}, TreesArr = {} }
    local function addTree(m)
        if Index.TreesSet[m] then return end
        Index.TreesSet[m] = true
        Index.TreesArr[#Index.TreesArr+1] = m
    end
    local function remTree(m)
        if not Index.TreesSet[m] then return end
        Index.TreesSet[m] = nil
    end

    local function seed(root)
        if not root then return end
        for _,d in ipairs(root:GetDescendants()) do
            if d:IsA("Model") and TREE_NAMES[d.Name] then addTree(d) end
        end
    end
    local function hook(root)
        if not root then return end
        seed(root)
        root.DescendantAdded:Connect(function(d)
            if d:IsA("Model") and TREE_NAMES[d.Name] then addTree(d) end
        end)
        root.DescendantRemoving:Connect(function(d)
            if d:IsA("Model") then remTree(d) end
        end)
    end

    hook(WS)
    hook(RS:FindFirstChild("Assets"))
    hook(RS:FindFirstChild("CutsceneSets"))

    local tracked = {}
    local attrCache = setmetatable({}, {__mode="k"})

    local function attrKeys(inst)
        local t = {}
        local attrs = inst and inst:GetAttributes() or nil
        if attrs then
            for k,_ in pairs(attrs) do
                t[k] = true
            end
        end
        return t
    end

    local function bucketFor(tree)
        local hr = tree and tree:FindFirstChild("HitRegisters")
        return (hr and hr:IsA("Instance")) and hr or tree
    end

    local function inRangeList()
        local r = hrp(); if not r then return {} end
        local origin = r.Position
        local radius = (C and C.State and tonumber(C.State.AuraRadius)) or 150
        local r2 = radius*radius
        local out = {}
        for i=1,#Index.TreesArr do
            local m = Index.TreesArr[i]
            if m and Index.TreesSet[m] and m.Parent then
                local part = bestTreeHitPart(m)
                if part and dist2(part.Position, origin) <= r2 then
                    out[#out+1] = m
                end
            end
        end
        table.sort(out, function(a,b)
            local pa, pb = bestTreeHitPart(a), bestTreeHitPart(b)
            if not pa or not pb then return (a.Name or "") < (b.Name or "") end
            return (pa.Position - origin).Magnitude < (pb.Position - origin).Magnitude
        end)
        return out
    end

    local lastInRange = {}
    task.spawn(function()
        while sg.Parent do
            local list = inRangeList()
            countLbl.Text = "Range: "..tostring(#list)
            local seen = {}
            for _,m in ipairs(list) do
                seen[m] = true
                if not tracked[m] then
                    tracked[m] = true
                    local b = bucketFor(m)
                    attrCache[m] = attrKeys(b)
                    push("enter "..m:GetFullName())
                end
            end
            for m,_ in pairs(tracked) do
                if not seen[m] or not m.Parent then
                    tracked[m] = nil
                    attrCache[m] = nil
                    push("leave "..(m and m:GetFullName() or "nil"))
                end
            end
            lastInRange = seen
            task.wait(0.25)
        end
    end)

    local function equipped()
        local ch = lp.Character
        if not ch then return "" end
        local t = ch:FindFirstChildOfClass("Tool")
        return t and t.Name or ""
    end

    task.spawn(function()
        while sg.Parent do
            for m,_ in pairs(tracked) do
                local b = bucketFor(m)
                local prev = attrCache[m] or {}
                local cur = attrKeys(b)
                for k,_ in pairs(cur) do
                    if not prev[k] then
                        local ok = string.match(k or "", "^(%d+)_"..UID.."$")
                        if ok then
                            local tool = equipped()
                            push("attr "..m.Name.." +"..k.." tool="..(tool or ""))
                        end
                    end
                end
                attrCache[m] = cur
            end
            task.wait(0.15)
        end
    end)
end
