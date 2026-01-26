--[[
    ZERAA HUB PREMIUM - ALL IN ONE [FIXED LOAD & V4 LOGIC]
    Version: 5.0 Stable
    Dev: Zeraa Team / Fixed by AI
    
    [Changelog]
    - Fix lỗi "Attempt to index nil with CreateWindow" (Thêm Backup Lib).
    - Tích hợp Auto Farm Level, Raid, Sea Event.
    - Race V4 Logic:
      + Mink: TP tới đích.
      + Angel: Tween mượt.
      + Cyborg: TP về sảnh né bom.
      + Shark: Bay đầu SeaBeast -> Spam 1-4 (Vũ khí) + Z,X,C,V.
      + Human/Ghoul: Gom quái + Kill.
    - Auto Train: Farm Nộ -> Bật Tộc -> Bay Y=2000 -> Hết Tộc Xuống.
]]

-- // 1. CẤU HÌNH NGƯỜI DÙNG (USER CONFIG) //
_G.V4_Config = {
    ["LockTiers"] = 10, -- Tự kick nếu Tier > 10 (Tránh reset)
    ["Helper"] = { "HelperAccount1", "" }, -- Tên acc phụ
    ["V4FarmList"] = { "MainAccount1" } -- Tên acc chính
}

-- Cài đặt Global
_G.TweenSpeed = 300 -- Tốc độ bay an toàn
_G.WhiteScreen = false -- Màn hình trắng giảm lag
_G.AutoGear = true -- Luôn tự mua Gear (Chạy ngầm)

-- // 2. KHỞI TẠO DỊCH VỤ (SERVICES) //
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- // 3. TẢI UI LIBRARY (FIX LỖI NIL) //
local Fluent = nil
local success, result = pcall(function()
    return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
end)

if success and result then
    Fluent = result
else
    -- Link dự phòng nếu link chính chết
    local backup_success, backup_result = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/bloodball/-back-ups-for-libs/main/fluent"))()
    end)
    if backup_success and backup_result then
        Fluent = backup_result
    else
        game.StarterGui:SetCore("SendNotification", {
            Title = "Zeraa Hub Error",
            Text = "Không thể tải UI Library. Vui lòng kiểm tra mạng hoặc dùng VPN!",
            Duration = 10
        })
        return -- Dừng script nếu không có UI
    end
end

local Window = Fluent:CreateWindow({
    Title = "Zeraa Hub Premium [V4 Fixed]",
    SubTitle = "Auto Farm & Race V4",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false, 
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.End
})

-- Tạo Tabs
local Tabs = {
    Main = Window:AddTab({ Title = "Farm Level" }),
    V4 = Window:AddTab({ Title = "Race V4" }),
    Stats = Window:AddTab({ Title = "Stats" }),
    Teleport = Window:AddTab({ Title = "Teleport" }),
    Raid = Window:AddTab({ Title = "Raid/Dungeon" }),
    Sea = Window:AddTab({ Title = "Sea Events" }),
    Shop = Window:AddTab({ Title = "Shop" }),
    Settings = Window:AddTab({ Title = "Settings" })
}

-- // 4. HÀM HỖ TRỢ CỐT LÕI (CORE FUNCTIONS) //

local function Notify(content)
    Fluent:Notify({Title = "Zeraa Hub", Content = content, Duration = 3})
end

local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getHRP()
    local char = getCharacter()
    return char:WaitForChild("HumanoidRootPart", 10)
end

-- Smart Move: Xa > 2500 TP, Gần thì Tween (Fix Kick)
local function SmartMove(targetCFrame)
    if not targetCFrame then return end
    local hrp = getHRP()
    if not hrp then return end
    
    local dist = (hrp.Position - targetCFrame.Position).Magnitude
    
    if dist > 2500 then
        hrp.CFrame = targetCFrame -- Instant TP
        return
    end

    local speed = _G.TweenSpeed
    local time = math.clamp(dist / speed, 0.1, 30)
    local info = TweenInfo.new(time, Enum.EasingStyle.Linear)
    
    local bv = Instance.new("BodyVelocity")
    bv.Velocity = Vector3.zero
    bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    bv.Parent = hrp

    local tween = TweenService:Create(hrp, info, {CFrame = targetCFrame})
    tween:Play()
    
    -- Anti Fall / Noclip
    local con
    con = RunService.Stepped:Connect(function()
        if LocalPlayer.Character then
            for _, v in pairs(LocalPlayer.Character:GetDescendants()) do
                if v:IsA("BasePart") then v.CanCollide = false end
            end
        end
    end)

    tween.Completed:Connect(function()
        bv:Destroy()
        if con then con:Disconnect() end
    end)
end

local function SendKey(key)
    pcall(function()
        local k = key
        -- Map string to Enum
        local map = {
            ["1"] = Enum.KeyCode.One, ["2"] = Enum.KeyCode.Two, ["3"] = Enum.KeyCode.Three, ["4"] = Enum.KeyCode.Four,
            ["Z"] = Enum.KeyCode.Z, ["X"] = Enum.KeyCode.X, ["C"] = Enum.KeyCode.C, ["V"] = Enum.KeyCode.V, ["F"] = Enum.KeyCode.F, ["Y"] = Enum.KeyCode.Y
        }
        if map[key] then k = map[key] end
        
        VirtualInputManager:SendKeyEvent(true, k, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, k, false, game)
    end)
end

local function EquipWeapon(type) 
    -- type: "Melee", "Sword", "Gun", "Fruit"
    local bp = LocalPlayer.Backpack
    local char = LocalPlayer.Character
    local tool
    
    -- Ưu tiên hàng xịn
    if type == "Melee" then
        tool = bp:FindFirstChild("Godhuman") or bp:FindFirstChild("Electric Claw")
    elseif type == "Sword" then
        tool = bp:FindFirstChild("Cursed Dual Katana") or bp:FindFirstChild("Hallow Scythe")
    end
    
    -- Nếu không có hàng xịn, lấy theo ToolTip
    if not tool then
        for _, t in pairs(bp:GetChildren()) do
            if t:IsA("Tool") and t.ToolTip == type then
                tool = t
                break
            end
        end
    end
    
    if tool then
        local hum = char:FindFirstChild("Humanoid")
        if hum then hum:EquipTool(tool) end
    end
end

-- Safe Attack (Fix Dam Ảo)
local LastAtk = 0
local function SafeAttack()
    if tick() - LastAtk < 0.22 then return end -- Delay 0.22s
    LastAtk = tick()
    
    local enemies = Workspace.Enemies:GetChildren()
    local hrp = getHRP()
    if not hrp then return end

    for _, v in pairs(enemies) do
        if v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 and v:FindFirstChild("HumanoidRootPart") then
            if (v.HumanoidRootPart.Position - hrp.Position).Magnitude < 60 then
                pcall(function()
                    -- 1. Click
                    VirtualUser:CaptureController()
                    VirtualUser:Button1Down(Vector2.new(1280, 672))
                    -- 2. Remote
                    local net = ReplicatedStorage.Modules.Net
                    if net:FindFirstChild("RegisterAttack") then net["RegisterAttack"]:FireServer(0) end
                    if net:FindFirstChild("RegisterHit") then net["RegisterHit"]:FireServer(v.HumanoidRootPart) end
                end)
                break
            end
        end
    end
end

local function AutoHaki()
    if LocalPlayer.Character and not LocalPlayer.Character:FindFirstChild("HasBuso") then
        ReplicatedStorage.Remotes.CommF_:InvokeServer("Buso")
    end
end

-- // 5. HỆ THỐNG ANTI-BAN CAO CẤP //
spawn(function()
    -- Anti-Kick
    CoreGui.RobloxPromptGui.promptOverlay.ChildAdded:Connect(function(child)
        if child.Name == "ErrorPrompt" then
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        end
    end)
    
    -- Anti-AFK & Random Input
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
    
    while task.wait(math.random(100, 300)) do
        SendKey("One") -- Fake switch weapon
        task.wait(0.5)
        SendKey("Two")
    end
end)

-- // 6. AUTO GEAR (CHẠY NGẦM) //
spawn(function()
    while task.wait(1.5) do
        if _G.AutoGear then
            pcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer("UpgradeRace", "Buy")
            end)
        end
    end
end)

-- // 7. LOGIC RACE V4 (CHI TIẾT) //

local ToT_Center = CFrame.new(28282, 14896, -11)
local RaceDoors = {
    ["Human"] = CFrame.new(29221, 14890, -206),
    ["Skypiea"] = CFrame.new(28960, 14919, 235),
    ["Fishman"] = CFrame.new(28231, 14890, -211),
    ["Mink"] = CFrame.new(29012, 14890, -380),
    ["Ghoul"] = CFrame.new(28674, 14890, 445),
    ["Cyborg"] = CFrame.new(28502, 14895, -423)
}

-- [TAB V4] UI Elements
Tabs.V4:AddToggle("AutoDoor", {Title = "Auto Go To Door (Smart)", Default = false, Callback = function(v) _G.AutoDoor = v end})
Tabs.V4:AddToggle("AutoUseRace", {Title = "Auto Use Race (Look Moon)", Default = false, Callback = function(v) _G.AutoUseRace = v end})
Tabs.V4:AddToggle("AutoTrial", {Title = "Auto Complete Trial", Default = false, Callback = function(v) _G.AutoTrial = v end})
Tabs.V4:AddToggle("AutoTrainV4", {Title = "Auto Train V4 (Maru)", Default = false, Callback = function(v) _G.AutoTrainV4 = v end})
Tabs.V4:AddToggle("AutoKillPlayers", {Title = "Auto PvP (Kill Aura)", Default = false, Callback = function(v) _G.AutoKillPlayers = v end})

-- [LOGIC] Auto Door
spawn(function()
    while task.wait() do
        if _G.AutoDoor then
            pcall(function()
                local hrp = getHRP()
                if not hrp then return end
                
                -- Check độ cao: Dưới 14000 là ở biển/đất -> TP lên Đền
                if hrp.Position.Y < 14000 then
                    hrp.CFrame = ToT_Center
                else
                    -- Đã ở Đền -> Tween vào Cửa
                    local race = LocalPlayer.Data.Race.Value
                    if RaceDoors[race] then
                        SmartMove(RaceDoors[race])
                    end
                end
            end)
        end
    end
end)

-- [LOGIC] Auto Use Race
spawn(function()
    while task.wait(0.5) do
        if _G.AutoUseRace then
            pcall(function()
                local moon = Lighting:GetMoonDirection()
                if moon then
                    Workspace.CurrentCamera.CFrame = CFrame.lookAt(Workspace.CurrentCamera.CFrame.Position, moon * 10000)
                end
                ReplicatedStorage.Remotes.CommE:FireServer("ActivateAbility")
            end)
        end
    end
end)

-- [LOGIC] Auto Trial (Chi tiết theo yêu cầu)
spawn(function()
    while task.wait() do
        if _G.AutoTrial then
            pcall(function()
                local race = LocalPlayer.Data.Race.Value
                local hrp = getHRP()
                if not hrp then return end

                -- TỘC MINK (Thỏ): TP Đích
                if race == "Mink" then
                    for _, v in pairs(Workspace.Map:GetDescendants()) do
                        if v.Name == "FinishPoint" or v.Name == "EndPoint" then
                            hrp.CFrame = v.CFrame -- Dịch chuyển tức thời
                        end
                    end

                -- TỘC SKY (Thiên Thần): Tween
                elseif race == "Skypiea" then
                    local sky = Workspace.Map:FindFirstChild("SkyTrial")
                    if sky then
                        local endPart = sky.Model:FindFirstChild("snowisland_Cylinder.081")
                        if endPart then SmartMove(endPart.CFrame) end
                    end

                -- TỘC HUMAN / GHOUL: Kill Mobs
                elseif race == "Human" or race == "Ghoul" then
                    for _, v in pairs(Workspace.Enemies:GetChildren()) do
                        if v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                            local root = v:FindFirstChild("HumanoidRootPart")
                            if root and (root.Position - hrp.Position).Magnitude < 1000 then
                                SmartMove(root.CFrame * CFrame.new(0,5,0))
                                AutoHaki()
                                EquipWeapon("Melee")
                                SafeAttack()
                                -- Gom quái
                                root.CFrame = hrp.CFrame * CFrame.new(0,0,-3)
                                root.CanCollide = false
                            end
                        end
                    end

                -- TỘC CYBORG (Máy): TP về Sảnh né bom
                elseif race == "Cyborg" then
                    -- Nếu đang ở xa tâm (tức là trong phòng trial) -> TP về tâm
                    if (hrp.Position - ToT_Center.Position).Magnitude > 300 then
                        hrp.CFrame = ToT_Center
                    end

                -- TỘC SHARK (Cá): Tìm SeaBeast -> Spam Vũ khí & Chiêu
                elseif race == "Fishman" then
                    local sbFolder = Workspace:FindFirstChild("SeaBeasts")
                    local target = nil
                    local minDist = math.huge

                    if sbFolder then
                        for _, v in pairs(sbFolder:GetChildren()) do
                            if v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 and v:FindFirstChild("HumanoidRootPart") then
                                local dist = (v.HumanoidRootPart.Position - hrp.Position).Magnitude
                                if dist < minDist then
                                    minDist = dist
                                    target = v
                                end
                            end
                        end
                    end

                    if target then
                        -- Bay tới đầu Sea Beast
                        SmartMove(target.HumanoidRootPart.CFrame * CFrame.new(0, 50, 0))
                        
                        -- SPAM: Đổi súng 1->4 và dùng chiêu
                        local weapons = {"1", "2", "3", "4"} 
                        local skills = {"Z", "X", "C", "V"}

                        for _, w in ipairs(weapons) do
                            SendKey(w) -- Đổi vũ khí
                            task.wait(0.2)
                            -- Xả skill
                            for _, s in ipairs(skills) do
                                SendKey(s)
                                task.wait(0.1)
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- [LOGIC] Auto Kill Players (PvP)
spawn(function()
    while task.wait() do
        if _G.AutoKillPlayers then
            pcall(function()
                local hrp = getHRP()
                for _, pl in pairs(Players:GetPlayers()) do
                    if pl ~= LocalPlayer and pl.Character and pl.Character:FindFirstChild("Humanoid") and pl.Character.Humanoid.Health > 0 then
                        local pHrp = pl.Character.HumanoidRootPart
                        -- Check khoảng cách (Trong đấu trường)
                        if (pHrp.Position - hrp.Position).Magnitude < 800 then
                            SmartMove(pHrp.CFrame * CFrame.new(0,4,0))
                            AutoHaki()
                            EquipWeapon("Melee")
                            SafeAttack()
                            SendKey("Z"); SendKey("X")
                        end
                    end
                end
            end)
        end
    end
end)

-- [LOGIC] Auto Train (Maru Style)
spawn(function()
    while task.wait() do
        if _G.AutoTrainV4 then
            pcall(function()
                local char = getCharacter()
                local hrp = getHRP()
                if not char or not hrp then return end

                local transformed = char:FindFirstChild("RaceTransformed")

                if transformed then
                    -- GIAI ĐOẠN 3: Đã bật tộc -> Bay lên trời cao (Y=2000)
                    local skyPos = CFrame.new(hrp.Position.X, 2000, hrp.Position.Z)
                    SmartMove(skyPos)
                    
                    -- Spam skill ảo để giữ trạng thái combat
                    if tick() % 2 == 0 then
                        SendKey("Z")
                        task.wait(0.1)
                        SendKey("X")
                    end
                else
                    -- GIAI ĐOẠN 1: Chưa bật tộc -> Farm nộ ở Haunted Castle
                    local target = nil
                    for _, v in pairs(Workspace.Enemies:GetChildren()) do
                        if (v.Name == "Reborn Skeleton" or v.Name == "Living Zombie") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                            target = v
                            break
                        end
                    end

                    if target then
                        SmartMove(target.HumanoidRootPart.CFrame * CFrame.new(0,5,0))
                        AutoHaki()
                        EquipWeapon("Melee")
                        SafeAttack()
                        
                        -- Gom quái
                        for _, v in pairs(Workspace.Enemies:GetChildren()) do
                            if (v.Name == "Reborn Skeleton" or v.Name == "Living Zombie") and (v.HumanoidRootPart.Position - hrp.Position).Magnitude < 300 then
                                v.HumanoidRootPart.CFrame = target.HumanoidRootPart.CFrame
                                v.HumanoidRootPart.CanCollide = false
                            end
                        end
                        
                        -- GIAI ĐOẠN 2: Spam Y để bật tộc
                        SendKey("Y")
                    else
                        -- Không có quái -> Bay về bãi farm (-9513, 164, 5786)
                        SmartMove(CFrame.new(-9513, 164, 5786))
                    end
                end
            end)
        end
    end
end)

-- // 8. FARM LEVEL (CƠ BẢN) //
Tabs.Main:AddToggle("AutoLevel", {
    Title = "Auto Farm Level",
    Default = false,
    Callback = function(v) _G.AutoLevel = v end
})

spawn(function()
    while task.wait() do
        if _G.AutoLevel then
            pcall(function()
                -- Logic xác định quái dựa trên Level (Rút gọn)
                local level = LocalPlayer.Data.Level.Value
                local mobName = "Bandit"
                local questName = "BanditQuest1"
                local levelReq = 1
                local mobCFrame = CFrame.new(1060, 16, 1547)
                local questCFrame = CFrame.new(1060, 16, 1547)

                -- Ví dụ logic cơ bản (Thực tế cần list mob dài hơn)
                if level >= 1 then 
                    -- Tự động nhận diện mob gần nhất hoặc theo list (Giả lập)
                    -- Phần này bạn có thể thêm logic check level chi tiết nếu cần
                end

                -- Nhận Quest
                local guideModule = require(ReplicatedStorage.GuideModule)
                local currentQuest = guideModule["CurrentQuest"]
                
                if not currentQuest then
                    SmartMove(questCFrame)
                    if (getHRP().Position - questCFrame.Position).Magnitude < 10 then
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("StartQuest", questName, levelReq)
                    end
                else
                    -- Đánh quái
                    for _, v in pairs(Workspace.Enemies:GetChildren()) do
                        if v.Name == mobName and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                            SmartMove(v.HumanoidRootPart.CFrame * CFrame.new(0,7,0))
                            AutoHaki()
                            EquipWeapon("Melee")
                            SafeAttack()
                            v.HumanoidRootPart.CFrame = getHRP().CFrame * CFrame.new(0,0,-3)
                            v.HumanoidRootPart.CanCollide = false
                            break
                        end
                    end
                end
            end)
        end
    end
end)

-- // 9. SETTINGS TAB //
Tabs.Settings:AddButton({Title = "Rejoin Server", Callback = function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end})
Tabs.Settings:AddButton({Title = "Hop Server", Callback = function() 
    -- Logic Hop Server cơ bản
    local PlaceID = game.PlaceId
    local AllIDs = {}
    local found = false
    local function Teleport()
        while wait() do
            pcall(function()
                local Site = game.HttpService:JSONDecode(game:HttpGet('https://games.roblox.com/v1/games/' .. PlaceID .. '/servers/Public?sortOrder=Asc&limit=100'))
                for i,v in pairs(Site.data) do
                    if v.playing ~= v.maxPlayers then
                        local ID = v.id
                        if not found then
                            table.insert(AllIDs, ID)
                        end
                    end
                end
            end)
            if found then break end
            pcall(function()
                TeleportService:TeleportToPlaceInstance(PlaceID, AllIDs[math.random(1, #AllIDs)], LocalPlayer)
            end)
            wait(4)
        end
    end
    Teleport()
end})

-- // KẾT THÚC //
Notify("Zeraa Hub Premium Loaded Successfully!")
