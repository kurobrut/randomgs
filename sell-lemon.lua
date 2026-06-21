--// Rayfield
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
	Name = "Sell Lemon Script",
	LoadingTitle = "Sell Lemon Auto Farm",
	LoadingSubtitle = "By Cubix",
	ConfigurationSaving = {
		Enabled = true,
		FolderName = "Cubix Sell Lemon",
		FileName = "Sell Lemon Config"
	},
	KeySystem = false,
})

local MainTab = Window:CreateTab("Main", 4483362458)

--// Services
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local RemoteRequest
pcall(function()
	RemoteRequest = require(ReplicatedStorage.Core.RemoteRequest)
end)

local RemoteSignal
pcall(function()
	RemoteSignal = require(ReplicatedStorage.Core.RemoteSignal)
end)

--// Find Tycoon
local userTycoon = (function()
	for _, v in pairs(workspace:GetChildren()) do
		if v:IsA("Folder") and v.Name:match("Tycoon%d") then
			if v:FindFirstChild("Owner") and v.Owner.Value == LocalPlayer then
				return v
			end
		end
	end
end)()

if not userTycoon then
	Rayfield:Notify({ Title = "Error", Content = "Tycoon not found!", Duration = 5 })
	return
end

--// Variables
local AutoBuy = false
local AutoUpgrade = false
local AutoFruit = false
local AutoRebirth = false
local AutoCashDrops = false
local AutoPhoneOffer = false
local AutoVine = false
local AutoEvolve = false
local RebirthInterval = 30

local LastRebirthTime = 0
local Buying = false

local function saveConfig()
	pcall(function()
		if Rayfield.SaveConfiguration then
			Rayfield:SaveConfiguration()
		elseif Rayfield.SaveConfig then
			Rayfield:SaveConfig()
		end
	end)
end

local VineRequests = {}

--// Anti-AFK (Always Enabled)
LocalPlayer.Idled:Connect(function()
	local VirtualUser = game:GetService("VirtualUser")
	VirtualUser:CaptureController()
	VirtualUser:ClickButton2(Vector2.new())
end)

--// Auto Buy
local function getButtons()
	local Buttons = {}
	for _, obj in ipairs(userTycoon.Purchases:GetDescendants()) do
		if obj:IsA("Model") then
			local shown = obj:GetAttribute("Shown")
			local purchased = obj:GetAttribute("Purchased")
			if shown == true and purchased ~= true then
				local buttonPart = obj:FindFirstChild("Button")
				if buttonPart and buttonPart:IsA("BasePart") then
					table.insert(Buttons, { Name = obj.Name, Button = buttonPart })
				end
			end
		end
	end
	return Buttons
end

local function buyButton(buttonData)
	if Buying then return end
	Buying = true
	local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		Buying = false
		return
	end
	pcall(function()
		firetouchinterest(hrp, buttonData.Button, 0)
		firetouchinterest(hrp, buttonData.Button, 1)
	end)
	Buying = false
end

task.spawn(function()
	while true do
		task.wait(0.0000001)
		if AutoBuy then
			for _, button in ipairs(getButtons()) do
				pcall(function() buyButton(button) end)
			end
		end
	end
end)

--// Auto Upgrade
local function upgradeMachines()
	for _, obj in ipairs(userTycoon.Purchases:GetDescendants()) do
		if obj:IsA("RemoteFunction") and obj.Name == "Upgrade" then
			pcall(function()
				for level = 1, 100 do obj:InvokeServer(level) end
			end)
		end
	end
end

task.spawn(function()
	while true do
		task.wait(0.000001)
		if AutoUpgrade then pcall(upgradeMachines) end
	end
end)

--// Auto Fruit
local Trees = {}
local function addTree(obj)
	if obj:IsA("Model") and obj.Name == "LemonTree" and not table.find(Trees, obj) then
		table.insert(Trees, obj)
	end
end
local function removeTree(obj)
	local index = table.find(Trees, obj)
	if index then table.remove(Trees, index) end
end
for _, v in ipairs(workspace:GetDescendants()) do addTree(v) end
workspace.DescendantAdded:Connect(addTree)
workspace.DescendantRemoving:Connect(removeTree)

local function collectFruit(tree)
	if not AutoFruit then return end
	local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	hrp.CFrame = tree:GetPivot() + Vector3.new(0, 5, 0)
	for _, obj in ipairs(tree:GetDescendants()) do
		if obj:IsA("BasePart") and obj.Name == "Fruit" then
			local clickPart = obj:FindFirstChild("ClickPart")
			if clickPart then
				local detector = clickPart:FindFirstChildOfClass("ClickDetector")
				if detector then
					task.wait(0.35)
					pcall(function() fireclickdetector(detector) end)
				end
			end
		end
	end
end

task.spawn(function()
	while true do
		task.wait(0.001)
		if AutoFruit then
			for _, tree in ipairs(Trees) do
				if tree and tree.Parent then pcall(function() collectFruit(tree) end) end
			end
		end
	end
end)

--// Cash Drops
local CashDropIds = {}
local CashDropRedeemRequest
local CashDropRedeemRemote
local CashDropNewSignal
local CashDropStats = {
	Seen = 0,
	Redeemed = 0,
	Failed = 0,
}

pcall(function()
	local core = ReplicatedStorage:WaitForChild("Core", 10)
	local remoteSignals = core and core:WaitForChild("RemoteSignal", 10)
	local remoteRequests = core and core:WaitForChild("RemoteRequest", 10)
	CashDropNewSignal = remoteSignals and remoteSignals:WaitForChild("CashDropService.New", 10)
	CashDropRedeemRemote = remoteRequests and remoteRequests:WaitForChild("CashDropService.Redeem", 10)

	if RemoteRequest then
		CashDropRedeemRequest = RemoteRequest.new("CashDropService.Redeem")
	end
end)

local function redeemCashDrop(dropId)
	if CashDropRedeemRequest then
		local ok, amount = pcall(function()
			return CashDropRedeemRequest:InvokeServer(dropId)
		end)
		if ok then
			return amount ~= false and amount ~= nil
		end
	end

	if CashDropRedeemRemote then
		local ok, amount = pcall(function()
			if CashDropRedeemRemote:IsA("RemoteFunction") then
				return CashDropRedeemRemote:InvokeServer(dropId)
			end

			CashDropRedeemRemote:FireServer(dropId)
			return true
		end)
		if ok then
			return amount ~= false and amount ~= nil
		end
	end

	return false
end

local function queueCashDrop(dropId, lifetime)
	if not dropId then
		return
	end

	for _, drop in ipairs(CashDropIds) do
		if drop.Id == dropId then
			return
		end
	end

	CashDropStats.Seen += 1

	if AutoCashDrops and redeemCashDrop(dropId) then
		CashDropStats.Redeemed += 1
		return
	end

	table.insert(CashDropIds, {
		Id = dropId,
		Expires = time() + (lifetime or 30),
	})
end

pcall(function()
	if RemoteSignal then
		local signal = RemoteSignal.new("CashDropService.New")
		if signal and signal.OnClientEvent then
			signal.OnClientEvent:Connect(queueCashDrop)
		end
	elseif CashDropNewSignal and CashDropNewSignal.OnClientEvent then
		CashDropNewSignal.OnClientEvent:Connect(queueCashDrop)
	end
end)

task.spawn(function()
	while true do
		task.wait(0.15)
		if AutoCashDrops then
			for i = #CashDropIds, 1, -1 do
				local drop = CashDropIds[i]
				if not drop or drop.Expires < time() or redeemCashDrop(drop.Id) then
					if drop and drop.Expires >= time() then
						CashDropStats.Redeemed += 1
					else
						CashDropStats.Failed += 1
					end
					table.remove(CashDropIds, i)
				end
			end
		end
	end
end)

--// Auto Rebirth
local function findRebirthRemote()
	for _, obj in ipairs(userTycoon:GetDescendants()) do
		if (obj.Name == "Rebirth" or obj.Name == "Rebirthed") and (obj:IsA("RemoteFunction") or obj:IsA("RemoteEvent")) then
			return obj
		end
	end
	return nil
end

local function performRebirth()
	local remote = findRebirthRemote()
	if remote then
		pcall(function()
			if remote:IsA("RemoteFunction") then remote:InvokeServer() else remote:FireServer() end
		end)
		return true
	end
	return false
end

task.spawn(function()
	while true do
		task.wait(5)
		if AutoRebirth then
			local currentTime = tick()
			if currentTime - LastRebirthTime >= (RebirthInterval * 60) then
				if performRebirth() then
					LastRebirthTime = currentTime
				end
			end
		end
	end
end)

--// Auto Evolve
local function findEvolveRemote()
	for _, obj in ipairs(userTycoon:GetDescendants()) do
		if (obj.Name == "Evolve" or obj.Name == "Evolved") and (obj:IsA("RemoteFunction") or obj:IsA("RemoteEvent")) then
			return obj
		end
	end
	return nil
end

local function performEvolve()
	local remote = findEvolveRemote()
	if remote then
		pcall(function()
			if remote:IsA("RemoteFunction") then remote:InvokeServer() else remote:FireServer() end
		end)
		return true
	end
	return false
end

task.spawn(function()
	while true do
		task.wait(1.5)
		if AutoEvolve then
			performEvolve()
		end
	end
end)

--// Auto Phone Offer
task.spawn(function()
	while true do
		task.wait(0.8)
		if AutoPhoneOffer then
			for _, obj in ipairs(userTycoon:GetDescendants()) do
				if obj.Name == "PhoneOffer" and (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) then
					pcall(function()
						if obj:IsA("RemoteFunction") then obj:InvokeServer("Accept") else obj:FireServer("Accept") end
					end)
				end
			end
		end
	end
end)

--// Auto Vine
local function getCashVines()
	local vines = {}

	pcall(function()
		for _, vine in ipairs(CollectionService:GetTagged("CashVine")) do
			if vine:IsDescendantOf(workspace) and not table.find(vines, vine) then
				table.insert(vines, vine)
			end
		end
	end)

	for _, obj in ipairs(userTycoon:GetDescendants()) do
		if obj.Name == "CashVine" and not table.find(vines, obj) then
			table.insert(vines, obj)
		end
	end

	return vines
end

local function useVine(vine)
	local used = false

	if RemoteRequest then
		used = pcall(function()
			local request = VineRequests[vine]
			if not request then
				request = RemoteRequest.new("Use", vine)
				VineRequests[vine] = request
			end
			request:InvokeServer()
		end)
	end

	if used then
		return true
	end

	local prompt = vine:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then
		if not prompt.Enabled then
			return false
		end

		used = pcall(function()
			fireproximityprompt(prompt)
		end)
	end

	if used then
		return true
	end

	for _, obj in ipairs(vine:GetDescendants()) do
		if obj.Name == "Use" and (obj:IsA("RemoteFunction") or obj:IsA("RemoteEvent")) then
			return pcall(function()
				if obj:IsA("RemoteFunction") then
					obj:InvokeServer()
				else
					obj:FireServer()
				end
			end)
		end
	end

	return false
end

task.spawn(function()
	while true do
		task.wait(0.8)
		if AutoVine then
			for _, vine in ipairs(getCashVines()) do
				useVine(vine)
			end
		end
	end
end)

--// GUI
MainTab:CreateSection("Progression")

MainTab:CreateToggle({
	Name = "Auto Rebirth",
	CurrentValue = AutoRebirth,
	Flag = "AutoRebirth",
	Callback = function(Value)
		AutoRebirth = Value
		LastRebirthTime = tick()
		Rayfield:Notify({
			Title = "Auto Rebirth",
			Content = Value and
				("Enabled - Every " .. RebirthInterval .. " minutes") or "Disabled",
			Duration = 4
		})
		saveConfig()
	end,
})

MainTab:CreateSlider({
	Name = "Rebirth Every (Minutes)",
	Range = { 1, 120 },
	Increment = 1,
	CurrentValue = RebirthInterval,
	Flag = "RebirthInterval",
	Callback = function(Value)
		RebirthInterval = Value
		saveConfig()
	end,
})

MainTab:CreateButton({
	Name = "Rebirth Now",
	Callback = function()
		if performRebirth() then
			Rayfield:Notify({ Title = "Rebirth", Content = "Rebirth triggered!", Duration = 4 })
		else
			Rayfield:Notify({ Title = "Rebirth", Content = "Rebirth remote not found!", Duration = 4 })
		end
	end,
})

MainTab:CreateToggle({
	Name = "Auto Evolve",
	CurrentValue = AutoEvolve,
	Flag = "AutoEvolve",
	Callback = function(Value)
		AutoEvolve = Value
		Rayfield:Notify({ Title = "Auto Evolve", Content = Value and "Enabled" or "Disabled", Duration = 4 })
		saveConfig()
	end,
})

MainTab:CreateButton({
	Name = "Evolve Now",
	Callback = function()
		if performEvolve() then
			Rayfield:Notify({ Title = "Evolve", Content = "Evolve triggered!", Duration = 4 })
		else
			Rayfield:Notify({ Title = "Evolve", Content = "Evolve remote not found!", Duration = 4 })
		end
	end,
})

MainTab:CreateSection("Collection")

MainTab:CreateToggle({
	Name = "Auto Fruit",
	CurrentValue = AutoFruit,
	Flag = "AutoFruit",
	Callback = function(Value)
		AutoFruit = Value
		saveConfig()
	end,
})

MainTab:CreateToggle({
	Name = "Auto Cash Drops",
	CurrentValue = AutoCashDrops,
	Flag = "AutoCashDrops",
	Callback = function(Value)
		AutoCashDrops = Value
		saveConfig()
	end,
})

MainTab:CreateToggle({
	Name = "Auto Vine",
	CurrentValue = AutoVine,
	Flag = "AutoVine",
	Callback = function(Value)
		AutoVine = Value
		local content = Value and ("Enabled - Found " .. #getCashVines() .. " vine(s)") or "Disabled"
		Rayfield:Notify({ Title = "Auto Vine", Content = content })
		saveConfig()
	end,

})

MainTab:CreateSection("Tycoon Automation")

MainTab:CreateToggle({
	Name = "Auto Buy Buttons",
	CurrentValue = AutoBuy,
	Flag = "AutoBuy",
	Callback = function(Value)
		AutoBuy = Value
		saveConfig()
	end,
})

MainTab:CreateToggle({
	Name = "Auto Upgrade Machines",
	CurrentValue = AutoUpgrade,
	Flag = "AutoUpgrade",
	Callback = function(Value)
		AutoUpgrade = Value
		saveConfig()
	end,
})

MainTab:CreateToggle({
	Name = "Auto Phone Offer (Always Accept)",
	CurrentValue = AutoPhoneOffer,
	Flag = "AutoPhoneOffer",
	Callback = function(Value)
		AutoPhoneOffer = Value
		saveConfig()
		Rayfield:Notify({ Title = "Auto Phone Offer", Content = Value and "✅ Always Accept Enabled" or "Disabled", Duration = 4 })
	end,
})

pcall(function()
	if Rayfield.LoadConfiguration then
		Rayfield:LoadConfiguration()
	elseif Rayfield.LoadConfig then
		Rayfield:LoadConfig()
	end
end)

Rayfield:Notify({
	Title = "Script Loaded",
	Content = "Sell a Lemon Script",
	Duration = 5,
})
