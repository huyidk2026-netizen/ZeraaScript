--[[
    AUTO V4 ULTIMATE (REDZ HUB ORIGINAL LOGIC)
    - Auto Bone: 100% Copy from Redz Hub (No Fall, Super Fast)
    - Auto V4: Redz Logic
    - Fix TP ToT: Direct CFrame + Stream Update
]]

--// CẤU HÌNH (CONFIG)
getgenv().ConfigV4 = {
    ["Account Up Gear"] = {
        "UserMain1" -- Tên đăng nhập Acc Chính
    },
    ["Account Help"] = {
        "UserHelp1", "UserHelp2" -- Tên đăng nhập Acc Phụ
    },
    ["Auto Join"] = true,
    ["Webhook"] = {
        ["url"] = "", 
        ["Done Train"] = false, 
        ["Done Trial"] = false,
        ["Tiers"] = "1-10",
        ["ChooseGear"] = "Red, Red, Blue",
    }
}
getgenv().AccountFindFullMoon = "" 

--// VARIABLES
getgenv().AutoFarmBone = false
getgenv().AutoV4Loop = true
getgenv().AutoActivateV4 = true
getgenv().SelectWeapon = "Melee" -- Mặc định Melee

-- Redz Variables
local StartBring = false
local MonFarm = ""
local PosMon = CFrame.new(0,0,0)

--// SERVICES
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer

--// UI LOADING
local Fluent = nil
local success, result = pcall(function()
    return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
end)
if success and result then Fluent = result else return end

--// ANTI-BAN
local function InitAntiBan()
    local mt = getrawmetatable(game)
    local old = mt.__namecall
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        if method == "FireServer" and self.Name == "MainEvent" and table.find({"CHECK", "One", "TeleportDetect", "Kick"}, args[1]) then
            return
        end
        return old(self, ...)
    end)
    setreadonly(mt, true)
end
InitAntiBan()

--// FIX LAG (30s Loop)
task.spawn(function()
    while true do
        pcall(function()
            local args = {{}, false, "en-gb", "Mobile", Vector2.new(1600, 900), false, 1}
            ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("OnEventServiceUpdate"):FireServer(unpack(args))
        end)
        task.wait(30)
    end
end)

--// REDZ HUB CORE FUNCTIONS

function EquipWeapon(toolName)
    pcall(function()
        local backpack = LP.Backpack
        local char = LP.Character
        local tool = backpack:FindFirstChild(toolName) or char:FindFirstChild(toolName)
        
        -- Nếu không tìm thấy tên cụ thể, tìm theo loại (Redz Logic)
        if not tool then
            for _, v in pairs(backpack:GetChildren()) do
                if v:IsA("Tool") and v.ToolTip == "Melee" then
                    tool = v
                    break
                end
            end
        end
        
        if tool and tool.Parent ~= char then
            char.Humanoid:EquipTool(tool)
        end
    end)
end

function AutoHaki()
    if not LP.Character:FindFirstChild("HasBuso") then
        ReplicatedStorage.Remotes.CommF_:InvokeServer("Buso")
    end
end

-- [REDZ TWEEN] - Sử dụng BodyVelocity để không bị rớt (BodyClip)
function topos(CFrame)
    if not LP.Character or not LP.Character:FindFirstChild("HumanoidRootPart") then return end
    local HRP = LP.Character.HumanoidRootPart
    
    -- BodyClip Logic (Redz Anti-Fall)
    if not HRP:FindFirstChild("BodyClip") then
        local bv = Instance.new("BodyVelocity")
        bv.Name = "BodyClip"
        bv.Parent = HRP
        bv.MaxForce = Vector3.new(100000, 100000, 100000)
        bv.Velocity = Vector3.new(0, 0, 0)
    end
    
    local Distance = (HRP.Position - CFrame.Position).Magnitude
    local Speed = 300
    local Time = Distance / Speed
    
    local TI = TweenInfo.new(Time, Enum.EasingStyle.Linear)
    local Tween = TweenService:Create(HRP, TI, {CFrame = CFrame})
    Tween:Play()
    
    -- Keep velocity 0 during tween
    local conn
    conn = RunService.Stepped:Connect(function()
        if HRP:FindFirstChild("BodyClip") then
            HRP.BodyClip.Velocity = Vector3.new(0, 0, 0)
        end
        -- Noclip
        for _, v in pairs(LP.Character:GetDescendants()) do
            if v:IsA("BasePart") and v.CanCollide then v.CanCollide = false end
        end
    end)
    
    Tween.Completed:Wait()
    if conn then conn:Disconnect() end
    
    -- Giữ BodyClip nếu đang farm để không rớt
    if not getgenv().AutoFarmBone and HRP:FindFirstChild("BodyClip") then
        HRP.BodyClip:Destroy()
    end
end

-- [REDZ BRING MOB LOOP] - Gom quái siêu dính
task.spawn(function()
    while true do
        task.wait()
        if StartBring then
            pcall(function()
                for _, v in pairs(Workspace.Enemies:GetChildren()) do
                    if v.Name == MonFarm and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                        -- Bring Logic
                        v.HumanoidRootPart.CanCollide = false
                        v.HumanoidRootPart.Size = Vector3.new(60, 60, 60)
                        v.HumanoidRootPart.CFrame = PosMon -- Teleport mob đến vị trí farm
                        v.Humanoid.WalkSpeed = 0
                        v.Humanoid:ChangeState(11) -- Stun
                        
                        if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then
                            -- Set SimulationRadius to huge to own physics
                            sethiddenproperty(LP, "SimulationRadius", math.huge)
                        end
                    end
                end
            end)
        end
    end
end)

--// AUTO FARM BONE (REDZ HUB EXACT LOGIC)
function AutoFarmBoneOriginal()
    task.spawn(function()
        while getgenv().AutoFarmBone do
            local hasMob = false
            
            -- Check Quest Mobs Priority (Redz Order)
            local Mobs = {"Reborn Skeleton", "Living Zombie", "Demonic Soul", "Posessed Mummy"}
            local TargetMob = nil
            
            -- Tìm quái còn sống
            for _, name in ipairs(Mobs) do
                local mob = Workspace.Enemies:FindFirstChild(name)
                if mob and mob:FindFirstChild("Humanoid") and mob.Humanoid.Health > 0 then
                    TargetMob = mob
                    break
                end
            end
            
            if TargetMob then
                hasMob = true
                StartBring = true
                MonFarm = TargetMob.Name
                
                -- Vị trí farm: Trên đầu quái
                PosMon = TargetMob.HumanoidRootPart.CFrame * CFrame.new(0, 30, 0)
                
                -- Tween đến quái
                topos(PosMon)
                
                -- Equip & Haki
                EquipWeapon()
                AutoHaki()
                
                -- Attack
                VirtualUser:CaptureController()
                VirtualUser:Button1Down(Vector2.new(1280, 672))
                
                -- Redz Spam Skill (Z, X)
                -- VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Z, false, game) ... (Optional)
            else
                -- Không có quái -> Về giữa bãi Bone để chờ spawn
                StartBring = false
                topos(CFrame.new(-9508, 142, 5737))
            end
            
            task.wait()
        end
        -- Tắt Bring khi dừng farm
        StartBring = false
        if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") and LP.Character.HumanoidRootPart:FindFirstChild("BodyClip") then
             LP.Character.HumanoidRootPart.BodyClip:Destroy()
        end
    end)
end

--// TP TEMPLE OF TIME (DIRECT FIX)
function TeleportToT()
    local ToT_Pos = CFrame.new(28286, 14897, 103)
    
    -- 1. Load Map trước (Bypass Falling)
    pcall(function()
        local args = {{}, false, "en-gb", "Mobile", Vector2.new(1600, 900), false, 1}
        ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("OnEventServiceUpdate"):FireServer(unpack(args))
        LP.ReplicatedFirst:WaitForChild("RequestStreamAroundAsync"):InvokeServer(ToT_Pos.Position)
    end)
    task.wait(0.5)
    
    -- 2. Direct TP (Set CFrame)
    if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then
        LP.Character.HumanoidRootPart.CFrame = ToT_Pos
    end
end

--// AUTO ACTIVATE V4 (REDZ LOGIC)
task.spawn(function()
    while true do
        task.wait()
        if getgenv().AutoActivateV4 then
             pcall(function()
                if LP.Character and LP.Character:FindFirstChild("RaceTransformed") then
                    -- Đã bật, không làm gì
                else
                    -- Chưa bật, spam Y
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Y, false, game)
                    task.wait(0.1)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Y, false, game)
                end
             end)
        end
    end
end)

--// TRIAL & GEAR LOGIC (Banana Cat)
local V4_Door_Coords = {
    ["Human"] = CFrame.new(29221, 14890, -205),
    ["Skypiea"] = CFrame.new(28960, 14919, 235),
    ["Fishman"] = CFrame.new(28231, 14890, -211),
    ["Cyborg"] = CFrame.new(28502, 14895, -423),
    ["Ghoul"] = CFrame.new(28674, 14890, 445),
    ["Mink"] = CFrame.new(29012, 14890, -380)
}
local AncientClock_CFrame = CFrame.new(28286, 14897, 103)

function StartTrialLoop()
    task.spawn(function()
        while getgenv().AutoV4Loop do
            pcall(function()
                local race = LP.Data.Race.Value
                local doorCF = V4_Door_Coords[race]
                local ToT_Pos = CFrame.new(28286, 14897, 103)

                if doorCF then
                    -- 1. Đến ToT
                    if (LP.Character.HumanoidRootPart.Position - ToT_Pos.Position).Magnitude > 3000 then
                        TeleportToT() 
                        task.wait(1)
                    end
                    
                    -- 2. Đến Cửa
                    if (LP.Character.HumanoidRootPart.Position - doorCF.Position).Magnitude > 15 then
                        topos(doorCF)
                    end
                    
                    -- 3. Spam Tộc (ActivateAbility)
                    if (LP.Character.HumanoidRootPart.Position - doorCF.Position).Magnitude < 20 then
                        ReplicatedStorage.Remotes.CommE:FireServer("ActivateAbility")
                    end
                end
                
                -- 4. Logic Trial
                if (LP.Character.HumanoidRootPart.Position - ToT_Pos.Position).Magnitude < 2000 then
                     -- Check Role
                    local isMain = false
                    for _, name in pairs(getgenv().ConfigV4["Account Up Gear"]) do
                        if LP.Name == name then isMain = true end
                    end
                    
                    if isMain then
                        -- Main: Kill All Players near ToT
                        for _, plr in pairs(Players:GetPlayers()) do
                            if plr ~= LP and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
                                if (plr.Character.HumanoidRootPart.Position - ToT_Pos.Position).Magnitude < 1500 then
                                    local isHelper = false
                                    for _, hName in pairs(getgenv().ConfigV4["Account Help"]) do
                                        if plr.Name == hName then isHelper = true end
                                    end
                                    
                                    if not isHelper then
                                        -- Kill
                                        topos(plr.Character.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0))
                                        EquipWeapon()
                                        VirtualUser:CaptureController()
                                        VirtualUser:Button1Down(Vector2.new(1280, 672))
                                        -- Spam Skill
                                        VirtualUser:TypeKey(Enum.KeyCode.Z)
                                        VirtualUser:TypeKey(Enum.KeyCode.X)
                                    end
                                end
                            end
                        end
                        
                        -- Win -> Buy Gear
                        if (LP.Character.HumanoidRootPart.Position - AncientClock_CFrame.Position).Magnitude < 500 then
                            topos(AncientClock_CFrame)
                            task.wait(1)
                            if Workspace.Map.TempleOfTime:FindFirstChild("AncientClock") then
                                fireclickdetector(Workspace.Map.TempleOfTime.AncientClock.ClickDetector)
                            end
                            task.wait(2)
                            ReplicatedStorage.Remotes.CommF_:InvokeServer("UpgradeRace", "Buy")
                        end
                    else
                        -- Help: Reset if in Trial
                         if (LP.Character.HumanoidRootPart.Position - ToT_Pos.Position).Magnitude < 1500 then
                             -- Đơn giản: Reset liên tục nếu ở trong khu vực trial
                             LP.Character.Humanoid.Health = 0
                         end
                    end
                end
            end)
            task.wait(1)
        end
    end)
end

--// UI SETUP (FLUENT)
local Window = Fluent:CreateWindow({
    Title = "Auto V4 Ultimate (Redz Copy 100%)",
    SubTitle = "Fixed Fall & TP",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Main Control", Icon = "home" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

-- Role Detection
local Role = "Unknown"
for _, n in pairs(getgenv().ConfigV4["Account Up Gear"]) do if LP.Name == n then Role = "Up Gear" end end
for _, n in pairs(getgenv().ConfigV4["Account Help"]) do if LP.Name == n then Role = "Helper" end end

Tabs.Main:AddParagraph({ Title = "Info", Content = "Role: " .. Role })

local BoneToggle = Tabs.Main:AddToggle("AutoBone", {Title = "Auto Farm Bone (Redz Original)", Default = false })
BoneToggle:OnChanged(function()
    getgenv().AutoFarmBone = BoneToggle.Value
    if getgenv().AutoFarmBone then AutoFarmBoneOriginal() end
end)

local V4Toggle = Tabs.Main:AddToggle("AutoV4", {Title = "Auto V4 Loop", Default = true })
V4Toggle:OnChanged(function() getgenv().AutoV4Loop = V4Toggle.Value end)

local V4ActToggle = Tabs.Main:AddToggle("AutoActV4", {Title = "Auto Activate V4 (Redz)", Default = true })
V4ActToggle:OnChanged(function() getgenv().AutoActivateV4 = V4ActToggle.Value end)

Tabs.Main:AddButton({
    Title = "Fix TP Temple of Time",
    Description = "TP Ngay Lập Tức",
    Callback = function() TeleportToT() end
})

Window:SelectTab(1)
Fluent:Notify({ Title = "Script Loaded", Content = "Auto V4 Ultimate Loaded", Duration = 5 })

--// AUTO EXECUTE LOGIC
if Role == "Up Gear" then
    if getgenv().ConfigV4.Webhook["Done Train"] == false then
        BoneToggle:SetValue(true)
    else
        StartTrialLoop()
    end
elseif Role == "Helper" then
    StartTrialLoop()
end

-- Auto Rejoin
if getgenv().ConfigV4["Auto Join"] then
    game.CoreGui.RobloxPromptGui.promptOverlay.ChildAdded:Connect(function(child)
        if child.Name == 'ErrorPrompt' and child:FindFirstChild('MessageArea') and child.MessageArea:FindFirstChild("ErrorFrame") then
            game:GetService("TeleportService"):Teleport(game.PlaceId)
        end
    end)
end
