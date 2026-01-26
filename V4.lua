--[[
    ZERAA HUB - RACE V4 [ULTRA ANTI-BAN EDITION]
    Phiên bản đầy đủ, không cắt bớt.
    
    Tính năng:
    1. Tween Speed: Cố định 300 (An toàn).
    2. Anti-Ban: Max Level (Anti-Kick, Anti-AFK, Random Input).
    3. Auto Gear: Luôn bật (Chạy ngầm).
    4. Auto Train: Farm Nộ -> Bật Tộc -> Bay lên trời (Maru Style).
    5. Trial Shark: Tìm SB -> Bay tới -> Spam phím 1-4 và skill Z-V.
]]

-- // 1. CẤU HÌNH & BIẾN TOÀN CỤC //
_G.V4_Config = _G.V4_Config or {}
_G.V4_Config.LockTiers = 10
_G.V4_Config.Helper = { "HelperAccount1", "HelperAccount2" }
_G.V4_Config.V4FarmList = { "MainAccount1" }

-- Toggles (Mặc định)
_G.AutoDoor = false
_G.AutoUseRace = false
_G.AutoTrial = false
_G.AutoTrainV4 = false
_G.AutoKillPlayers = false
_G.DebugMode = false

-- Cài đặt bắt buộc
_G.TweenSpeed = 300 

-- Services
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

-- Toạ độ quan trọng
local ToT_Center = CFrame.new(28282, 14896, -11)
local Train_Mob_CFrame = CFrame.new(-9513, 164, 5786) -- Bãi xương
local RaceDoors = {
    ["Human"] = CFrame.new(29221, 14890, -206),
    ["Skypiea"] = CFrame.new(28960, 14919, 235),
    ["Fishman"] = CFrame.new(28231, 14890, -211),
    ["Mink"] = CFrame.new(29012, 14890, -380),
    ["Ghoul"] = CFrame.new(28674, 14890, 445),
    ["Cyborg"] = CFrame.new(28502, 14895, -423)
}

-- // 2. HỆ THỐNG ANTI-BAN TỐI ĐA //
local function ActivateUltraAntiBan()
    print(">> Zeraa V4: Activating Ultra Anti-Ban...")

    -- A. Anti-AFK (Kết nối event Idled)
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)

    -- B. Anti-Kick (Tự động Rejoin khi mất kết nối/Kick)
    spawn(function()
        while task.wait(1) do
            pcall(function()
                local prompt = CoreGui:FindFirstChild("RobloxPromptGui")
                if prompt then
                    local overlay = prompt:FindFirstChild("promptOverlay")
                    if overlay then
                        local errorPrompt = overlay:FindFirstChild("ErrorPrompt")
                        if errorPrompt and errorPrompt.Visible then
                            -- Nếu hiện bảng lỗi -> Rejoin ngay lập tức
                            TeleportService:Teleport(game.PlaceId, LocalPlayer)
                        end
                    end
                end
            end)
        end
    end)

    -- C. Random Behavior (Giả lập hành động ngẫu nhiên)
    spawn(function()
        while task.wait(math.random(120, 300)) do -- Mỗi 2-5 phút
            pcall(function()
                -- Rung nhẹ Camera
                local cam = Workspace.CurrentCamera
                if cam then
                    local randomAngle = math.rad(math.random(-2, 2))
                    cam.CFrame = cam.CFrame * CFrame.Angles(0, randomAngle, 0)
                end
                -- Nhấn phím vô hại (Ctrl)
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftControl, false, game)
                task.wait(0.1)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
            end)
        end
    end)
end
ActivateUltraAntiBan()

-- // 3. CÁC HÀM HỖ TRỢ (UTILS) //

local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getHRP()
    local char = getCharacter()
    return char:WaitForChild("HumanoidRootPart", 5)
end

local function isAlive()
    local char = LocalPlayer.Character
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    return hum and hum.Health > 0
end

-- Hàm gửi phím (Hỗ trợ số và chữ)
local function sendKey(key)
    pcall(function()
        local k = key
        -- Map string sang Enum
        if key == "1" then k = Enum.KeyCode.One
        elseif key == "2" then k = Enum.KeyCode.Two
        elseif key == "3" then k = Enum.KeyCode.Three
        elseif key == "4" then k = Enum.KeyCode.Four
        elseif key == "Z" then k = Enum.KeyCode.Z
        elseif key == "X" then k = Enum.KeyCode.X
        elseif key == "C" then k = Enum.KeyCode.C
        elseif key == "V" then k = Enum.KeyCode.V
        elseif key == "Y" then k = Enum.KeyCode.Y
        end
        
        VirtualInputManager:SendKeyEvent(true, k, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, k, false, game)
    end)
end

-- Hàm Remote Safe (Tránh lỗi Vararg ...)
local function safeInvoke(remoteName, ...)
    local args = {...}
    pcall(function()
        local rem = ReplicatedStorage.Remotes.CommF_
        if remoteName == "CommE" then rem = ReplicatedStorage.Remotes.CommE end
        
        if rem and rem.ClassName == "RemoteFunction" then
            rem:InvokeServer(unpack(args))
        elseif rem and rem.ClassName == "RemoteEvent" then
            rem:FireServer(unpack(args))
        end
    end)
end

-- // 4. HỆ THỐNG DI CHUYỂN & CHIẾN ĐẤU //

-- Smart Move: Xa TP, Gần Tween (Speed 300)
local function SmartMove(targetCFrame)
    if not targetCFrame then return end
    local hrp = getHRP()
    if not hrp then return end
    
    local dist = (hrp.Position - targetCFrame.Position).Magnitude
    
    -- Nếu xa hơn 2500 stud -> Dịch chuyển tức thời (Bypass)
    if dist > 2500 then
        hrp.CFrame = targetCFrame
        return
    end

    -- Nếu gần -> Tween mượt (Speed 300)
    local speed = _G.TweenSpeed
    local time = math.clamp(dist / speed, 0.1, 20)
    local info = TweenInfo.new(time, Enum.EasingStyle.Linear)
    
    -- BodyVelocity để không bị rơi
    local bv = Instance.new("BodyVelocity")
    bv.Velocity = Vector3.zero
    bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    bv.Parent = hrp

    local tween = TweenService:Create(hrp, info, {CFrame = targetCFrame})
    tween:Play()
    
    -- Noclip khi bay
    local noclip
    noclip = RunService.Stepped:Connect(function()
        if LocalPlayer.Character then
            for _, v in pairs(LocalPlayer.Character:GetDescendants()) do
                if v:IsA("BasePart") then v.CanCollide = false end
            end
        end
    end)

    tween.Completed:Connect(function()
        bv:Destroy()
        if noclip then noclip:Disconnect() end
    end)
end

-- Equip Weapon (Ưu tiên Godhuman/CDK)
local function EquipWeapon()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    
    local bp = LocalPlayer.Backpack
    local weapon = bp:FindFirstChild("Godhuman") or bp:FindFirstChild("Cursed Dual Katana")
    
    if weapon then
        hum:EquipTool(weapon)
    else
        -- Lấy đại cây nào đó hệ Melee
        for _, t in pairs(bp:GetChildren()) do
            if t:IsA("Tool") and t.ToolTip == "Melee" then
                hum:EquipTool(t)
                break
            end
        end
    end
end

-- Safe Attack (Fix lag, có delay)
local LastAtk = 0
local function SafeAttack()
    if tick() - LastAtk < 0.25 then return end -- Delay 0.25s
    LastAtk = tick()
    
    local mobs = Workspace.Enemies:GetChildren()
    local hrp = getHRP()
    if not hrp then return end

    for _, m in pairs(mobs) do
        if m:FindFirstChild("Humanoid") and m.Humanoid.Health > 0 and m:FindFirstChild("HumanoidRootPart") then
            if (m.HumanoidRootPart.Position - hrp.Position).Magnitude < 60 then
                pcall(function()
                    -- 1. Click chuột ảo
                    VirtualUser:CaptureController()
                    VirtualUser:Button1Down(Vector2.new(1280, 672))
                    
                    -- 2. Gửi Remote RegisterAttack (Nhẹ nhàng)
                    local net = ReplicatedStorage.Modules.Net
                    if net:FindFirstChild("RegisterAttack") then net["RegisterAttack"]:FireServer(0) end
                    if net:FindFirstChild("RegisterHit") then net["RegisterHit"]:FireServer(m.HumanoidRootPart) end
                end)
                break -- Đánh 1 con thôi để đỡ lag
            end
        end
    end
end

local function AutoHaki()
    local char = LocalPlayer.Character
    if char and not char:FindFirstChild("HasBuso") then
        safeInvoke("CommF_", "Buso")
    end
end

-- // 5. AUTO GEAR (CHẠY NGẦM) //
spawn(function()
    while task.wait(2) do -- Mỗi 2 giây check mua gear 1 lần
        pcall(function()
            safeInvoke("CommF_", "UpgradeRace", "Buy")
        end)
    end
end)

-- // 6. GIAO DIỆN UI (FLUENT) //
local Window = Fluent:CreateWindow({
    Title = "Zeraa Hub - Race V4 [Ultra Safe]",
    SubTitle = "Speed 300 | Max Anti-Ban",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false, 
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.End
})

local Tabs = {
    Main = Window:AddTab({ Title = "Main V4" }),
    Train = Window:AddTab({ Title = "Auto Train" }),
    Settings = Window:AddTab({ Title = "Settings" })
}

-- // 7. LOGIC TỰ ĐỘNG HÓA //

-- A. Auto Door
Tabs.Main:AddToggle("AutoDoor", {
    Title = "Tự Động Đến Cửa Tộc",
    Description = "TP Đền -> Tween Cửa",
    Default = false,
    Callback = function(v) _G.AutoDoor = v end
})

spawn(function()
    while task.wait() do
        if _G.AutoDoor then
            pcall(function()
                local hrp = getHRP()
                if not hrp then return end
                
                -- Check độ cao (Nếu < 14000 là đang ở dưới đất)
                if hrp.Position.Y < 14000 then
                    hrp.CFrame = ToT_Center -- TP Lên Đền
                else
                    -- Đã ở trên đền -> Tween vào cửa tộc
                    local race = LocalPlayer.Data.Race.Value
                    if RaceDoors[race] then
                        SmartMove(RaceDoors[race])
                    end
                end
            end)
        end
    end
end)

-- B. Auto Use Race
Tabs.Main:AddToggle("AutoUseRace", {
    Title = "Tự Động Bật Tộc (Nhìn Trăng)",
    Default = false,
    Callback = function(v) _G.AutoUseRace = v end
})

spawn(function()
    while task.wait(0.5) do
        if _G.AutoUseRace then
            pcall(function()
                local moonDir = Lighting:GetMoonDirection()
                if moonDir then
                    Workspace.CurrentCamera.CFrame = CFrame.lookAt(Workspace.CurrentCamera.CFrame.Position, moonDir * 10000)
                end
                safeInvoke("CommE", "ActivateAbility")
            end)
        end
    end
end)

-- C. Auto Trial (Logic Shark Mới)
Tabs.Main:AddToggle("AutoTrial", {
    Title = "Hoàn Thành Ải (Trial)",
    Description = "Shark: Spam Weapons & Skills",
    Default = false,
    Callback = function(v) _G.AutoTrial = v end
})

spawn(function()
    while task.wait() do
        if _G.AutoTrial then
            pcall(function()
                local race = LocalPlayer.Data.Race.Value
                local hrp = getHRP()
                if not hrp then return end

                -- Tộc Người / Ghoul: Đánh quái
                if race == "Human" or race == "Ghoul" then
                    for _, v in pairs(Workspace.Enemies:GetChildren()) do
                        if v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                            if (v.HumanoidRootPart.Position - hrp.Position).Magnitude < 1000 then
                                SmartMove(v.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0))
                                AutoHaki()
                                EquipWeapon()
                                SafeAttack()
                                v.HumanoidRootPart.CFrame = hrp.CFrame * CFrame.new(0,0,-3)
                                v.HumanoidRootPart.CanCollide = false
                            end
                        end
                    end

                -- Tộc Thỏ (Mink): TP Đích
                elseif race == "Mink" then
                    for _, v in pairs(Workspace.Map:GetDescendants()) do
                        if v.Name == "FinishPoint" or v.Name == "EndPoint" then
                            hrp.CFrame = v.CFrame
                        end
                    end

                -- Tộc Thiên Thần (Sky): Tween
                elseif race == "Skypiea" then
                    local sky = Workspace.Map:FindFirstChild("SkyTrial")
                    if sky then
                        local endPart = sky.Model:FindFirstChild("snowisland_Cylinder.081")
                        if endPart then SmartMove(endPart.CFrame) end
                    end

                -- Tộc Máy (Cyborg): TP Né Bom
                elseif race == "Cyborg" then
                    if (hrp.Position - ToT_Center.Position).Magnitude > 300 then
                        hrp.CFrame = ToT_Center
                    end

                -- Tộc Cá (Fishman/Shark) - LOGIC MỚI
                elseif race == "Fishman" then
                    local sbFolder = Workspace:FindFirstChild("SeaBeasts")
                    local targetSB = nil
                    
                    -- Tìm SB gần nhất
                    if sbFolder then
                        local minDist = math.huge
                        for _, v in pairs(sbFolder:GetChildren()) do
                            if v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 and v:FindFirstChild("HumanoidRootPart") then
                                local dist = (v.HumanoidRootPart.Position - hrp.Position).Magnitude
                                if dist < minDist then
                                    minDist = dist
                                    targetSB = v
                                end
                            end
                        end
                    end

                    if targetSB then
                        -- Bay lên đầu Sea Beast
                        SmartMove(targetSB.HumanoidRootPart.CFrame * CFrame.new(0, 60, 0))
                        
                        -- SPAM COMBO (Vũ khí 1-4 + Skill Z-V)
                        local weapons = {"1", "2", "3", "4"}
                        local skills = {"Z", "X", "C", "V"}
                        
                        for _, wKey in ipairs(weapons) do
                            sendKey(wKey) -- Đổi vũ khí
                            task.wait(0.3) -- Chờ equip
                            
                            -- Xả skill
                            for _, sKey in ipairs(skills) do
                                sendKey(sKey)
                                task.wait(0.1)
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- D. Auto Kill Players (PvP)
Tabs.Main:AddToggle("AutoKill", {Title = "Auto Kill Players", Default = false, Callback = function(v) _G.AutoKillPlayers = v end})

spawn(function()
    while task.wait() do
        if _G.AutoKillPlayers then
            pcall(function()
                local hrp = getHRP()
                for _, pl in pairs(Players:GetPlayers()) do
                    if pl ~= LocalPlayer and pl.Character and pl.Character:FindFirstChild("Humanoid") and pl.Character.Humanoid.Health > 0 then
                        local pHrp = pl.Character.HumanoidRootPart
                        if (pHrp.Position - hrp.Position).Magnitude < 800 then
                            SmartMove(pHrp.CFrame * CFrame.new(0, 4, 0))
                            AutoHaki()
                            EquipWeapon()
                            SafeAttack()
                            sendKey("Z"); sendKey("X")
                        end
                    end
                end
            end)
        end
    end
end)

-- E. Auto Train V4 (Maru Style)
Tabs.Train:AddToggle("AutoTrain", {
    Title = "Auto Train V4",
    Description = "Farm Nộ -> Bật Tộc -> Bay Lên Cao -> Hết Tộc Xuống",
    Default = false,
    Callback = function(v) _G.AutoTrainV4 = v end
})

spawn(function()
    while task.wait() do
        if _G.AutoTrainV4 then
            pcall(function()
                local char = getCharacter()
                local hrp = getHRP()
                if not char or not hrp then return end

                local isTransformed = char:FindFirstChild("RaceTransformed")

                if isTransformed then
                    -- Giai đoạn 3: Đang bật tộc -> Bay lên trời cao (Y=2000)
                    local skyPos = CFrame.new(hrp.Position.X, 2000, hrp.Position.Z)
                    SmartMove(skyPos)
                    
                    -- Spam skill ảo để giữ combat
                    if tick() % 2 == 0 then
                        sendKey("Z")
                        task.wait(0.1)
                        sendKey("X")
                    end
                else
                    -- Giai đoạn 1: Farm nộ (Haunted Castle)
                    local target = nil
                    -- Ưu tiên tìm Reborn Skeleton / Living Zombie
                    for _, v in pairs(Workspace.Enemies:GetChildren()) do
                        if (v.Name == "Reborn Skeleton" or v.Name == "Living Zombie") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                            target = v
                            break
                        end
                    end

                    if target then
                        -- Bay tới quái
                        SmartMove(target.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0))
                        AutoHaki()
                        EquipWeapon()
                        SafeAttack()
                        
                        -- Gom quái (nhẹ)
                        for _, v in pairs(Workspace.Enemies:GetChildren()) do
                            if (v.Name == "Reborn Skeleton" or v.Name == "Living Zombie") and (v.HumanoidRootPart.Position - hrp.Position).Magnitude < 300 then
                                v.HumanoidRootPart.CFrame = target.HumanoidRootPart.CFrame
                                v.HumanoidRootPart.CanCollide = false
                            end
                        end
                        
                        -- Giai đoạn 2: Bật tộc khi đủ nộ (Spam Y)
                        sendKey("Y")
                    else
                        -- Không thấy quái -> Bay về bãi farm
                        SmartMove(Train_Mob_CFrame)
                    end
                end
            end)
        end
    end
end)

-- Rejoin Button
Tabs.Settings:AddButton({Title = "Rejoin Server", Callback = function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end})

-- Notification
Fluent:Notify({
    Title = "Zeraa Hub V4",
    Content = "Script Loaded Successfully!\nMode: Ultra Anti-Ban (Speed 300)",
    Duration = 5
})
