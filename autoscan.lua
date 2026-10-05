-- Cubix Scan & Save: extracted from your House Cloner script.
-- Saves the existing HouseFS format, including mannequin outfit data.

-- Single-instance guard: re-executing the script cleanly stops the old scanner first.
local GLOBAL_ENV = (getgenv and getgenv()) or _G
if type(GLOBAL_ENV.__CubixScannerShutdown) == "function" then
	pcall(GLOBAL_ENV.__CubixScannerShutdown)
	GLOBAL_ENV.__CubixScannerShutdown = nil
end
GLOBAL_ENV.__CubixScannerGeneration = (tonumber(GLOBAL_ENV.__CubixScannerGeneration) or 0) + 1
local CUBIX_SCANNER_GENERATION = GLOBAL_ENV.__CubixScannerGeneration

if not game:IsLoaded() then game.Loaded:Wait() end
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local cd = require(ReplicatedStorage.ClientModules.Core.ClientData)
local furnituresdb = require(ReplicatedStorage.ClientDB.Housing.FurnitureDB)
local texturesdb = require(ReplicatedStorage.ClientDB.Housing.TexturesDB)
local plr = Players.LocalPlayer
while not plr do task.wait(); plr = Players.LocalPlayer end

local function loadMain()
	local fetchOk, rayfieldSource = pcall(function()
		return game:HttpGet("https://sirius.menu/rayfield")
	end)
	if not fetchOk or type(rayfieldSource) ~= "string" or rayfieldSource == "" then
		error("Failed to download Rayfield: " .. tostring(rayfieldSource))
	end
	local rayfieldChunk, compileError = loadstring(rayfieldSource)
	if not rayfieldChunk then
		error("Failed to compile Rayfield: " .. tostring(compileError))
	end
	local runOk, Rayfield = pcall(rayfieldChunk)
	if not runOk or not Rayfield then
		error("Failed to initialize Rayfield: " .. tostring(Rayfield))
	end

	local runtimeAlive = true
	local autoStop = false

	local function runtimeIsAlive()
		return runtimeAlive and GLOBAL_ENV.__CubixScannerGeneration == CUBIX_SCANNER_GENERATION
	end

	local function shutdownCubixScanner()
		if not runtimeAlive then return end
		runtimeAlive = false
		autoStop = true

		-- The scan overlay is not owned by Rayfield, so remove it explicitly.
		pcall(function()
			local pg = plr and plr:FindFirstChild("PlayerGui")
			local old = pg and pg:FindFirstChild("CubixScanInformation")
			if old then old:Destroy() end
		end)
		pcall(function()
			if gethui then
				local hui = gethui()
				local old = hui and hui:FindFirstChild("CubixScanInformation")
				if old then old:Destroy() end
			end
		end)
		pcall(function() Rayfield:Destroy() end)

		if GLOBAL_ENV.__CubixScannerShutdown == shutdownCubixScanner then
			GLOBAL_ENV.__CubixScannerShutdown = nil
		end
	end

	GLOBAL_ENV.__CubixScannerShutdown = shutdownCubixScanner

	local Window = Rayfield:CreateWindow({
		Name = "Cubix . Scan, Save & Auto Scan",
		LoadingTitle = "Cubix",
		LoadingSubtitle = "Scan & Save",
		Theme = "Amethyst",
		ConfigurationSaving = { Enabled = false },
		Discord = { Enabled = false },
	})
	local savedhouse = nil
	local houseFilesPath = "HouseFS/Houses"
	local Manager = Window:CreateTab("Scan Information", "info")
	local Tab = Window:CreateTab("Scan", "home")
	Tab:CreateLabel("Enter the house, wait for it to load, then scan before saving.", "info")
	Manager:CreateSection("Scan Information")
	local furniture_label = Manager:CreateLabel("House Furniture: 0 ($0)", "armchair")
	local textures_label = Manager:CreateLabel("House Textures: 0 ($0)", "grid-2x2")
	local ambiance_label = Manager:CreateLabel("House Ambiance: No", "sun")
	local type_label = Manager:CreateLabel("House Type: -", "home")

	local scanInfoGui
	local scanInfoFrame
	local scanInfoLabels = {}
	local scanInfoVisible = false
	local scanInfoValues = { 0, 0, 0, 0, "No", "-" }

	local function getScanInfoParent()
		local success, hui = pcall(function()
			return gethui and gethui()
		end)
		if success and hui then return hui end
		-- PlayerGui is safer than CoreGui when the executor does not have CoreGui write capability.
		return plr:WaitForChild("PlayerGui")
	end

	local function createScanInfoGui()
		if scanInfoGui then return end

		scanInfoGui = Instance.new("ScreenGui")
		scanInfoGui.Name = "CubixScanInformation"
		scanInfoGui.ResetOnSpawn = false
		scanInfoGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		scanInfoGui.Enabled = scanInfoVisible
		scanInfoGui.Parent = getScanInfoParent()

		scanInfoFrame = Instance.new("Frame")
		scanInfoFrame.Name = "ScanInformation"
		scanInfoFrame.Position = UDim2.new(0, 20, 0, 100)
		scanInfoFrame.Size = UDim2.new(0, 260, 0, 150)
		scanInfoFrame.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
		scanInfoFrame.BackgroundTransparency = 0.1
		scanInfoFrame.BorderSizePixel = 0
		scanInfoFrame.Parent = scanInfoGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = scanInfoFrame

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, -20, 0, 28)
		title.Position = UDim2.new(0, 10, 0, 8)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.Text = "House Scan Information"
		title.TextColor3 = Color3.fromRGB(255, 255, 255)
		title.TextSize = 16
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = scanInfoFrame

		local entries = {
			{ name = "Furniture", y = 40 },
			{ name = "Textures", y = 62 },
			{ name = "Ambiance", y = 84 },
			{ name = "House Type", y = 106 },
		}
		for _, entry in ipairs(entries) do
			local label = Instance.new("TextLabel")
			label.Name = entry.name:gsub("%s", "")
			label.Size = UDim2.new(1, -20, 0, 20)
			label.Position = UDim2.new(0, 10, 0, entry.y)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.Gotham
			label.TextColor3 = Color3.fromRGB(225, 225, 235)
			label.TextSize = 13
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.Parent = scanInfoFrame
			scanInfoLabels[entry.name] = label
		end
	end

	local function updateScanInfoGui(f_count, f_cost, t_count, t_cost, amb, typ)
		if not scanInfoGui then return end
		scanInfoLabels.Furniture.Text = "Furniture: " .. f_count .. " ($" .. f_cost .. ")"
		scanInfoLabels.Textures.Text = "Textures: " .. t_count .. " ($" .. t_cost .. ")"
		scanInfoLabels.Ambiance.Text = "Ambiance: " .. amb
		scanInfoLabels["House Type"].Text = "House Type: " .. typ
	end

	Manager:CreateSection("Process Status")
	local status_label = Manager:CreateLabel("Status: Idle", "activity")
	local prog_label = Manager:CreateLabel("Progress: -", "trending-up")
	local item_label = Manager:CreateLabel("Items: -", "box")

	local function setscaninfo(f_count, f_cost, t_count, t_cost, amb, typ)
		scanInfoValues = { f_count, f_cost, t_count, t_cost, amb, typ }
		updateScanInfoGui(f_count, f_cost, t_count, t_cost, amb, typ)
		pcall(function()
			furniture_label:Set("House Furniture: " .. f_count .. " ($" .. f_cost .. ")")
			textures_label:Set("House Textures: " .. t_count .. " ($" .. t_cost .. ")")
			ambiance_label:Set("House Ambiance: " .. amb)
			type_label:Set("House Type: " .. typ)
		end)
	end

	Manager:CreateToggle({
		Name = "Show Scan Information Overlay",
		CurrentValue = false,
		Flag = "ShowScanInformationOverlay",
		Callback = function(value)
			scanInfoVisible = value
			createScanInfoGui()
			scanInfoGui.Enabled = value
			if value then
				updateScanInfoGui(table.unpack(scanInfoValues))
			end
		end,
	})

	local function updatestatus(s)
		pcall(function()
			status_label:Set("Status: " .. s)
		end)
	end
	local function updateprog(p)
		pcall(function()
			prog_label:Set("Progress: " .. p)
		end)
	end
	local function updateitem(i)
		pcall(function()
			item_label:Set("Items: " .. i)
		end)
	end

	updatestatus("Idle")
	updateprog("-")
	updateitem("-")

	local function countfurnitures(t)
		local c = 0
		for _ in pairs(t or {}) do c += 1 end
		return c
	end

	local function counttextures(textures)
		local c = 0
		for _, v in pairs(textures or {}) do
			if v.walls then c += 1 end
			if v.floors then c += 1 end
		end
		return c
	end

	local function deepCopy(tbl)
		if type(tbl) ~= "table" then return tbl end
		local t = {}
		for k, v in pairs(tbl) do t[k] = deepCopy(v) end
		return t
	end

	local function serializeAutoPasteValue(value, seen)
		local valueType = typeof(value)
		if valueType == "CFrame" then
			return { __type = "CFrame", components = { value:GetComponents() } }
		elseif valueType == "Color3" then
			return { __type = "Color3", r = value.R, g = value.G, b = value.B }
		elseif valueType == "Vector3" then
			return { __type = "Vector3", x = value.X, y = value.Y, z = value.Z }
		elseif valueType == "Instance" or valueType == "function" or valueType == "thread" then
			return nil
		elseif valueType == "table" then
			seen = seen or {}
			if seen[value] then return nil end
			seen[value] = true

			local count = 0
			local maxIndex = 0
			local numericOnly = true
			for key in pairs(value) do
				count += 1
				if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
					numericOnly = false
				else
					maxIndex = math.max(maxIndex, key)
				end
			end

			local isArray = numericOnly and count == maxIndex
			local copy = {}
			if isArray then
				for i = 1, maxIndex do
					local serialized = serializeAutoPasteValue(value[i], seen)
					if serialized ~= nil then copy[i] = serialized end
				end
			else
				for key, item in pairs(value) do
					local serialized = serializeAutoPasteValue(item, seen)
					if serialized ~= nil then copy[tostring(key)] = serialized end
				end
			end

			seen[value] = nil
			return copy
		end
		return value
	end


	-- Shared analysis/cleanup helpers so manual Scan, local save, Pastebin and Auto Scan
	-- all use one source of truth for counts, costs and unknown-price items.
	local function analyzeHouse(house)
		local info = {
			furnitureCount = 0,
			textureCount = 0,
			furnitureCost = 0,
			textureCost = 0,
			totalCost = 0,
			unknownCount = 0,
			unknownItems = {},
			houseType = tostring((house and house.building_type) or "-"),
			ambiance = house and house.ambiance and "Yes" or "No",
		}

		for _, item in pairs((house and house.furniture) or {}) do
			info.furnitureCount += 1
			local id = item and item.id
			local db = id and furnituresdb[id]
			if db and type(db.cost) == "number" then
				info.furnitureCost += db.cost
			else
				info.unknownCount += 1
				table.insert(info.unknownItems, "furniture:" .. tostring(id or "unknown"))
			end
		end

		for _, room in pairs((house and house.textures) or {}) do
			local wallId = room and room.walls
			if wallId then
				info.textureCount += 1
				local db = texturesdb.walls and texturesdb.walls[wallId]
				if db and type(db.cost) == "number" then
					info.textureCost += db.cost
				else
					info.unknownCount += 1
					table.insert(info.unknownItems, "wall:" .. tostring(wallId))
				end
			end

			local floorId = room and room.floors
			if floorId then
				info.textureCount += 1
				local db = texturesdb.floors and texturesdb.floors[floorId]
				if db and type(db.cost) == "number" then
					info.textureCost += db.cost
				else
					info.unknownCount += 1
					table.insert(info.unknownItems, "floor:" .. tostring(floorId))
				end
			end
		end

		info.totalCost = info.furnitureCost + info.textureCost
		table.sort(info.unknownItems)
		return info
	end

	local function getHouseCostInfo(house)
		local info = analyzeHouse(house)
		return info.furnitureCost, info.textureCost, info.unknownCount
	end

	local function prepareHouseForSave(house)
		local clean = deepCopy(house or {})
		for _, item in pairs(clean.furniture or {}) do
			item.creator = nil
			item.hash = nil
			item.was_free = nil
			item.no_value = nil
			item.was_default = nil
			item.item_category = nil
			item.item_kind = nil
			item.door_position = nil
			item.last_position = nil
			item.on = nil
		end
		local fc, tc, unknown = getHouseCostInfo(clean)
		clean.total_cost = fc + tc
		clean.furniture_quantity = countfurnitures(clean.furniture)
		clean.saved_by = "Cubix-HouseCloner"
		clean.properties = nil
		clean.house_id = nil
		clean.listed_for_trade = nil
		clean.unique = nil
		clean.active_addons = nil
		clean.allows_coop_building = nil
		clean.house_pos = nil
		clean.textures_hash = nil
		clean.player = nil
		return clean, fc, tc, unknown
	end

	local function encodeHouseForSave(house)
		local clean, fc, tc, unknown = prepareHouseForSave(house)
		local ok, encoded = pcall(function()
			return HttpService:JSONEncode(serializeAutoPasteValue(clean))
		end)
		if not ok then return nil, tostring(encoded), clean, fc, tc, unknown end
		return encoded, nil, clean, fc, tc, unknown
	end

	Tab:CreateButton({
		Name = "Scan house",
		Callback = function()
			local success, house = pcall(function()
				return cd.get("house_interior")
			end)
			if not success or not house or house.player == nil then
				Rayfield:Notify({
					Title = "Error",
					Content = "You need to enter a house to copy",
					Duration = 3,
					Image = "circle-alert",
				})
				return
			end
			updatestatus("Scanning")
			savedhouse = deepCopy(house)
			if savedhouse.furniture then
				for _, v in pairs(savedhouse.furniture) do
					if v.creator then v.creator = nil end
				end
			end
			local info = analyzeHouse(savedhouse)
			task.spawn(
				setscaninfo,
				info.furnitureCount,
				info.furnitureCost,
				info.textureCount,
				info.textureCost,
				info.ambiance,
				info.houseType
			)
			Rayfield:Notify({ Title = "Success", Content = "Scanned house", Duration = 3, Image = "circle-check" })
			updatestatus("Idle")
		end,
	})

	local function sanitizeFileName(name)
		name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
		name = name:gsub("%.json$", ""):gsub("%.txt$", ""):gsub("%.lua$", "")
		name = name:gsub("%.%.", "_"):gsub("[/\\:*?\"<>|]", "_")
		name = name:gsub("[%c]", "_"):sub(1, 100)
		if name == "" then return nil end
		return name
	end

	local CreateFileTab = Window:CreateTab("Save File", "folder")
	CreateFileTab:CreateLabel("Saves to HouseFS/Houses in your executor workspace. An existing file with the same name is replaced.", "info")
	local saveInput = CreateFileTab:CreateInput({
		Name = "Save As", PlaceholderText = "Enter file name",
		RemoveTextAfterFocusLost = false, Callback = function(_) end,
	})
	CreateFileTab:CreateButton({
		Name = "Save House to File",
		Callback = function()
			if not savedhouse then
				return Rayfield:Notify({ Title = "Error", Content = "Scan a house first", Duration = 3, Image = "circle-alert" })
			end
			local filename = sanitizeFileName(saveInput.CurrentValue)
			if not filename then
				return Rayfield:Notify({ Title = "Error", Content = "Please enter a valid filename", Duration = 3, Image = "circle-alert" })
			end
			local encoded, encodeErr = encodeHouseForSave(savedhouse)
			if not encoded then
				return Rayfield:Notify({ Title = "Error", Content = "Failed to encode house data: " .. tostring(encodeErr):sub(1, 100), Duration = 4, Image = "circle-alert" })
			end
			local wrote, writeErr = pcall(function()
				if type(isfolder) ~= "function" or type(makefolder) ~= "function" or type(writefile) ~= "function" then
					error("This executor does not support local file saving")
				end
				if not isfolder("HouseFS") then makefolder("HouseFS") end
				if not isfolder(houseFilesPath) then makefolder(houseFilesPath) end
				writefile(houseFilesPath .. "/" .. filename .. ".json", encoded)
			end)
			if not wrote then
				return Rayfield:Notify({ Title = "Error", Content = "Failed to save file: " .. tostring(writeErr):sub(1, 120), Duration = 4, Image = "circle-alert" })
			end
			Rayfield:Notify({ Title = "Success", Content = "House saved: " .. filename .. ".json", Duration = 3, Image = "circle-check" })
		end,
	})



	-- Pastebin API: https://pastebin.com/doc_api
	local function postPastebin(url, fields)
		local send = request or http_request or (syn and syn.request) or (http and http.request)
		if type(send) ~= "function" then return nil, "This executor does not support HTTP requests" end
		local parts = {}
		for key, value in pairs(fields) do
			table.insert(parts, HttpService:UrlEncode(key) .. "=" .. HttpService:UrlEncode(tostring(value)))
		end
		local ok, response = pcall(send, {
			Url = url, Method = "POST",
			Headers = { ["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8" },
			Body = table.concat(parts, "&"),
		})
		if not ok or type(response) ~= "table" then return nil, "Pastebin request failed" end
		local body = tostring(response.Body or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local code = tonumber(response.StatusCode)
		if (code and (code < 200 or code >= 300)) or response.Success == false then
			return nil, "Pastebin HTTP error " .. tostring(code or "unknown")
		end
		if body:match("^Bad API request") then return nil, body:sub(1, 200) end
		if body == "" then return nil, "Pastebin returned an empty response" end
		return body
	end
	local function getUserKey(devKey, username, password)
		if username == "" and password == "" then return nil, "NO_LOGIN" end
		if username == "" or password == "" then return nil, "Enter both username and password, or leave both blank" end
		local key, err = postPastebin("https://pastebin.com/api/api_login.php", {
			api_dev_key = devKey, api_user_name = username, api_user_password = password,
		})
		if not key then return nil, err end
		if not key:match("^[%w]+$") then return nil, "Pastebin returned an invalid login response" end
		return key
	end
	local function createPaste(encoded, name, devKey, userKey)
		local fields = {
			api_dev_key = devKey, api_option = "paste", api_paste_code = encoded,
			api_paste_name = name, api_paste_private = "1", api_paste_expire_date = "N",
		}
		if userKey then fields.api_user_key = userKey end
		local url, err = postPastebin("https://pastebin.com/api/api_post.php", fields)
		if not url then return nil, err end
		if not url:match("^https://pastebin%.com/[%w]+$") then return nil, "Pastebin returned an unexpected response" end
		return url
	end
	local PastebinTab = Window:CreateTab("Save Pastebin", "clipboard")
	local userPastebinDevKey = ""
	local userPastebinUsername = ""
	local userPastebinPassword = ""


	PastebinTab:CreateLabel(
		"TO GET DEV API KEY YOU NEED TO MAKE ACCOUNT ON PASTEBIN AFTER THAT GO TO https://pastebin.com/doc_api AND COPY YOUR DEV API KEY",
		"info"
	)
	PastebinTab:CreateDivider()

	PastebinTab:CreateInput({
		Name = "Pastebin Dev API Key (Required)",
		PlaceholderText = "Paste ONLY the API key (not a link)",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			value = tostring(value):gsub("%s+", ""):gsub("YouruniquedeveloperAPIkey:", ""):gsub("Your%w+developer%w+API%w+key:", "")
			userPastebinDevKey = value
		end,
	})
	PastebinTab:CreateInput({
		Name = "Pastebin Username",
		PlaceholderText = "Your Pastebin username",
		RemoveTextAfterFocusLost = false,
		Callback = function(value) userPastebinUsername = value end,
	})
	PastebinTab:CreateInput({
		Name = "Pastebin Password",
		PlaceholderText = "Your Pastebin password",
		RemoveTextAfterFocusLost = false,
		Callback = function(value) userPastebinPassword = value end,
	})

	local pasteNameInput = PastebinTab:CreateInput({
		Name = "House Name for Pastebin",
		PlaceholderText = "Enter house name (optional)",
		RemoveTextAfterFocusLost = false,
		Callback = function() end,
	})

	PastebinTab:CreateLabel("Save uploads the scanned house as an unlisted paste. Leave username and password blank to post as a guest.", "info")
	local pasteResultLabel = PastebinTab:CreateLabel("Saved link: -", "link")
	PastebinTab:CreateButton({
		Name = "Save House to Pastebin",
		Callback = function()
			if not savedhouse then
				return Rayfield:Notify({ Title = "Error", Content = "Scan a house first", Duration = 3 })
			end
			if #userPastebinDevKey < 20 or not userPastebinDevKey:match("^[%w]+$") then
				return Rayfield:Notify({ Title = "Invalid API Key", Content = "Paste ONLY the Pastebin Dev API key.\nDo not paste a URL.", Duration = 5 })
			end
			local encoded, encodeErr = encodeHouseForSave(savedhouse)
			if not encoded then
				return Rayfield:Notify({ Title = "Error", Content = "Failed to encode house data: " .. tostring(encodeErr):sub(1, 100), Duration = 4 })
			end
			local apiUserKey, loginErr = getUserKey(userPastebinDevKey, userPastebinUsername, userPastebinPassword)
			if not apiUserKey and loginErr ~= "NO_LOGIN" then
				return Rayfield:Notify({ Title = "Pastebin Login", Content = tostring(loginErr), Duration = 5 })
			end
			local inputtedName = pasteNameInput.CurrentValue or ""
			local pasteName = "CubixHouse" .. (inputtedName ~= "" and "_" .. inputtedName or "")
			local result, err = createPaste(encoded, pasteName, userPastebinDevKey, apiUserKey)
			if err or not result then
				return Rayfield:Notify({ Title = "Pastebin Error", Content = tostring(err or result), Duration = 6 })
			end
			pcall(function() pasteResultLabel:Set("Saved link: " .. result) end)
			local copied = false
			if type(setclipboard) == "function" then copied = pcall(setclipboard, result) end
			Rayfield:Notify({ Title = "Success", Content = "House saved: " .. result .. (copied and "\nLink copied to clipboard" or ""), Duration = 8 })
		end,
	})


	local Telegram = Window:CreateTab("Telegram", "send")
	local telegramEnabled, telegramToken, telegramChat = false, "", ""
	local telegramMinimum = 50000
	local telegramStatus = Telegram:CreateLabel("Notifications off", "info")
	local function telegramNote(message)
		pcall(function() telegramStatus:Set(message) end)
	end
	local telegramSettingsPath = "HouseFS/settings/telegram.json"
	local telegramSettingsReady = false
	local telegramStorageStatus = Telegram:CreateLabel("Settings: loading", "folder")
	local function telegramStorageNote(message)
		pcall(function() telegramStorageStatus:Set(message) end)
	end
	local function saveTelegramSettings()
		if not telegramSettingsReady then return false end
		local ok = pcall(function()
			if type(isfolder) ~= "function" or type(makefolder) ~= "function" or type(writefile) ~= "function" then error("File saving unavailable") end
			if not isfolder("HouseFS") then makefolder("HouseFS") end
			if not isfolder("HouseFS/settings") then makefolder("HouseFS/settings") end
			writefile(telegramSettingsPath, HttpService:JSONEncode({
				version = 1, token = telegramToken, chat_id = telegramChat,
				minimum_cost = telegramMinimum, enabled = telegramEnabled,
			}))
		end)
		-- Never display raw filesystem errors: some executors echo write arguments.
		telegramStorageNote(ok and "Settings saved automatically" or "Settings could not be saved; this session still works")
		return ok
	end
	local function loadTelegramSettings()
		if type(isfile) ~= "function" or type(readfile) ~= "function" then
			telegramStorageNote("Settings cannot be restored: file reading unavailable")
			return
		end
		local existsOk, exists = pcall(isfile, telegramSettingsPath)
		if not existsOk then telegramStorageNote("Unable to check saved settings"); return end
		if not exists then telegramStorageNote("Enter settings once; changes will save automatically"); return end
		local ok, config = pcall(function() return HttpService:JSONDecode(readfile(telegramSettingsPath)) end)
		if not ok or type(config) ~= "table" or config.version ~= 1 then
			telegramStorageNote("Saved settings unreadable; enter them again")
			return
		end
		if type(config.token) == "string" and (config.token == "" or config.token:match("^%d+:[%w_-]+$")) then telegramToken = config.token end
		if type(config.chat_id) == "string" and (config.chat_id == "" or config.chat_id:match("^%-?%d+$")) then telegramChat = config.chat_id end
		local amount = config.minimum_cost
		if type(amount) == "number" and amount == amount and amount >= 0 and amount < math.huge then telegramMinimum = amount end
		telegramEnabled = config.enabled == true and telegramToken ~= "" and telegramChat ~= ""
		telegramStorageNote("Saved settings restored")
	end
	loadTelegramSettings()

	local function telegramRequest(token, method, payload)
		local send = request or http_request or (syn and syn.request) or (http and http.request)
		if type(send) ~= "function" then return nil, "Executor HTTP requests are unavailable" end
		-- Never print request URLs or transport errors: they may contain the token.
		local ok, response = pcall(function()
			return send({ Url = "https://api.telegram.org/bot" .. token .. "/" .. method,
				Method = "POST", Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode(payload) })
		end)
		if not ok or type(response) ~= "table" then return nil, "Telegram network request failed; delivery unknown" end
		local decodedOk, decoded = pcall(function() return HttpService:JSONDecode(response.Body or "") end)
		if not decodedOk or type(decoded) ~= "table" then return nil, "Telegram returned an unreadable response; delivery unknown" end
		if decoded.ok == true then return decoded.result end
		local code = tonumber(decoded.error_code) or tonumber(response.StatusCode)
		local messages = { [400] = "Check Chat ID and send /start to your bot", [401] = "Bot token is invalid",
			[403] = "Bot cannot message this chat; unblock it and press Start", [409] = "Another bot service is receiving updates",
			[429] = "Telegram rate limit reached; try again later" }
		return nil, messages[code] or ("Telegram API error " .. tostring(code or "unknown"))
	end
	local function telegramSettingsValid(needsChat)
		if not telegramToken:match("^%d+:[%w_-]+$") then telegramNote("Enter a valid BotFather token"); return false end
		if needsChat and not telegramChat:match("^%-?%d+$") then telegramNote("Enter a numeric Chat ID"); return false end
		return true
	end
	Telegram:CreateLabel("Create a bot with @BotFather (/newbot), then open your new bot and send /start. Enter its token below. Settings auto-save locally to HouseFS/settings/telegram.json. This file contains your bot token in plain text; keep it private.", "info")
	Telegram:CreateInput({ Name = "Bot token", PlaceholderText = "Paste your token here", RemoveTextAfterFocusLost = true,
		Callback = function(value)
			local token = tostring(value or ""):gsub("%s+", "")
			if token ~= "" then telegramToken = token; telegramNote("Token entered"); saveTelegramSettings() end
		end })
	local telegramChatInput = Telegram:CreateInput({ Name = "Chat ID", PlaceholderText = "Your numeric Telegram chat ID", CurrentValue = telegramChat, RemoveTextAfterFocusLost = false,
		Callback = function(value) telegramChat = tostring(value or ""):gsub("%s+", ""); saveTelegramSettings() end })
	Telegram:CreateInput({ Name = "Minimum notification cost", PlaceholderText = "50000", CurrentValue = tostring(telegramMinimum), RemoveTextAfterFocusLost = false,
		Callback = function(value)
			local amount = tonumber(value)
			if amount and amount == amount and amount >= 0 and amount < math.huge then telegramMinimum = amount; saveTelegramSettings()
			else telegramNote("Invalid cost; keeping " .. telegramMinimum) end
		end })
	local telegramEnableToggle = Telegram:CreateToggle({ Name = "Enable Telegram notifications", CurrentValue = telegramEnabled,
		Callback = function(value) telegramEnabled = value; telegramNote(value and "Enabled for qualifying auto-saves" or "Notifications off"); saveTelegramSettings() end })
	local lookupBusy, testBusy = false, false
	Telegram:CreateButton({ Name = "Find my Chat ID (send /start first)", Callback = function()
		if lookupBusy or not telegramSettingsValid(false) then return end
		lookupBusy = true
		local token = telegramToken
		task.spawn(function()
			local updates, err = telegramRequest(token, "getUpdates", { timeout = 0, limit = 100 })
			lookupBusy = false
			if token ~= telegramToken then return end
			if type(updates) ~= "table" then telegramNote(err or "No updates returned"); return end
			local found, ids = {}, {}
			for _, update in ipairs(updates) do
				local chat = update.message and update.message.chat
				if chat and chat.type == "private" and chat.id then found[tostring(chat.id)] = true end
			end
			for id in pairs(found) do table.insert(ids, id) end
			table.sort(ids)
			if #ids == 1 then
				telegramChat = ids[1]
				pcall(function() telegramChatInput:Set(ids[1]) end)
				saveTelegramSettings()
				telegramNote("Chat ID found: " .. ids[1] .. ". Send a test message to check it.")
			elseif #ids == 0 then telegramNote("No private chat found. Send a fresh message to your bot, then try again.")
			else telegramNote("Multiple chats found. Enter your own Chat ID manually: " .. table.concat(ids, ", "):sub(1, 180)) end
		end)
	end })
	local function telegramEscapeHtml(value)
		return tostring(value or "")
			:gsub("&", "&amp;")
			:gsub("<", "&lt;")
			:gsub(">", "&gt;")
	end

	Telegram:CreateButton({ Name = "Send test notification", Callback = function()
		if testBusy or not telegramSettingsValid(true) then return end
		testBusy = true
		local token, chat = telegramToken, telegramChat
		task.spawn(function()
			local testMessage = table.concat({
				"🏠 <b>Cubix House Scanner</b>",
				"━━━━━━━━━━━━━━━━━━",
				"✅ <b>Telegram connected</b>",
				"This is a test notification.",
				"",
				"<i>Auto-saved houses that pass your filters will appear in this format.</i>",
			}, "\n")
			local sent, err = telegramRequest(token, "sendMessage", {
				chat_id = chat,
				text = testMessage,
				parse_mode = "HTML",
				disable_web_page_preview = true,
			})
			testBusy = false
			telegramNote(sent and "Test message sent" or (err or "Test failed"))
		end)
	end })
	Telegram:CreateButton({ Name = "Clear Telegram credentials", Callback = function()
		telegramEnabled, telegramToken, telegramChat = false, "", ""
		telegramSettingsReady = false
		pcall(function() telegramChatInput:Set("") end)
		pcall(function() telegramEnableToggle:Set(false) end)
		telegramSettingsReady = true
		if saveTelegramSettings() then
			telegramNote("Credentials cleared from this session and saved settings; notifications disabled")
		else
			telegramNote("Cleared in memory only. Remove HouseFS/settings/telegram.json manually to clear saved credentials.")
		end
	end })
	telegramSettingsReady = true
	telegramNote(telegramEnabled and "Notifications enabled; saved settings loaded" or (telegramToken ~= "" and "Saved token loaded; notifications off" or "Notifications off"))
	local function notifyTelegramSave(path, houseType, playerName, cost, unknownCosts)
		if not telegramEnabled or cost < telegramMinimum then return end
		if not telegramSettingsValid(true) then return end
		local token, chat = telegramToken, telegramChat
		local filename = path:match("([^/]+)$") or path
		local roundedCost = math.floor((tonumber(cost) or 0) + 0.5)
		local warning = ""
		if unknownCosts > 0 then
			warning = "\n⚠️ <b>Price warning:</b> " .. tostring(unknownCosts) .. " item(s) have unknown prices, so the total only includes known prices."
		end

		-- Telegram has no Discord-style embeds, so this uses HTML formatting to create an embed-like card.
		local message = table.concat({
			"🏠 <b>Cubix • House Saved</b>",
			"━━━━━━━━━━━━━━━━━━",
			"👤 <b>Player</b>",
			telegramEscapeHtml(playerName),
			"",
			"🏡 <b>House Type</b>",
			telegramEscapeHtml(houseType),
			"",
			"💵 <b>Estimated Build Cost</b>",
			"$" .. tostring(roundedCost),
			"",
			"📄 <b>File</b>",
			"<code>" .. telegramEscapeHtml(filename) .. "</code>",
			"",
			"📁 <b>Saved To</b>",
			"<code>" .. telegramEscapeHtml(path) .. "</code>",
			"",
			"<i>Cost includes furniture + textures and does not include the house purchase price.</i>",
		}, "\n") .. warning

		-- Run separately: a Telegram failure must never fail or repeat a house save.
		task.spawn(function()
			if not telegramEnabled or token ~= telegramToken or chat ~= telegramChat then return end
			local sent, err = telegramRequest(token, "sendMessage", {
				chat_id = chat,
				text = message,
				parse_mode = "HTML",
				disable_web_page_preview = true,
			})
			telegramNote(sent and ("Notification sent: " .. filename) or ("House saved; " .. (err or "notification failed")))
		end)
	end


	-- Auto Scan: optimized stability checks, retries, anti-duplicate cache, full settings, and live statistics.
	local AutoScan = Window:CreateTab("Auto Scan", "map-pin")
	local autoScanFilesPath = "HouseFS/autoscan"
	local autoScanSettingsPath = "HouseFS/settings/autoscan.json"
	local duplicateCachePath = "HouseFS/settings/autoscan_duplicates.json"
	local favoritesPath = "HouseFS/favorites"

	local autoRunning = false
	autoStop = false
	local autoMode, autoPlayer = "Everyone in server", plr.Name
	local selectedHouseTypes = {}
	local minCostText, maxCostText, minFurnitureText, minTexturesText = "", "", "", ""
	local includeDetails, skipEmpty, antiDuplicate = true, true, true
	local settleSeconds, retryCount = 4, 1
	local unknownCostPolicy = "Save anyway"
	local autoScanSettingsReady = false
	local duplicateCache = {}

	local function trim(value)
		return tostring(value or ""):match("^%s*(.-)%s*$")
	end

	local function selectedTypesArray()
		local arr = {}
		for id in pairs(selectedHouseTypes) do table.insert(arr, id) end
		table.sort(arr)
		return arr
	end

	local function ensureAutoFolders()
		if type(isfolder) ~= "function" or type(makefolder) ~= "function" then return false, "Folder functions unavailable" end
		local ok, err = pcall(function()
			if not isfolder("HouseFS") then makefolder("HouseFS") end
			if not isfolder("HouseFS/settings") then makefolder("HouseFS/settings") end
			if not isfolder(autoScanFilesPath) then makefolder(autoScanFilesPath) end
		end)
		return ok, err
	end

	local function saveAutoScanSettings()
		if not autoScanSettingsReady then return false end
		if type(writefile) ~= "function" then return false end
		local folderOk = ensureAutoFolders()
		if not folderOk then return false end
		local ok = pcall(function()
			writefile(autoScanSettingsPath, HttpService:JSONEncode({
				version = 2,
				mode = autoMode,
				player = autoPlayer,
				house_types = selectedTypesArray(),
				min_cost = minCostText,
				max_cost = maxCostText,
				min_furniture = minFurnitureText,
				min_textures = minTexturesText,
				include_details = includeDetails,
				skip_empty = skipEmpty,
				anti_duplicate = antiDuplicate,
				settle_seconds = settleSeconds,
				retry_count = retryCount,
				unknown_cost_policy = unknownCostPolicy,
			}))
		end)
		return ok
	end

	local function loadAutoScanSettings()
		if type(isfile) ~= "function" or type(readfile) ~= "function" then return end
		local okExists, exists = pcall(isfile, autoScanSettingsPath)
		if not okExists or not exists then return end
		local ok, cfg = pcall(function() return HttpService:JSONDecode(readfile(autoScanSettingsPath)) end)
		if not ok or type(cfg) ~= "table" then return end
		if type(cfg.mode) == "string" then autoMode = cfg.mode end
		if type(cfg.player) == "string" then autoPlayer = cfg.player end
		if type(cfg.min_cost) == "string" then minCostText = cfg.min_cost end
		if type(cfg.max_cost) == "string" then maxCostText = cfg.max_cost end
		if type(cfg.min_furniture) == "string" then minFurnitureText = cfg.min_furniture end
		if type(cfg.min_textures) == "string" then minTexturesText = cfg.min_textures end
		if type(cfg.include_details) == "boolean" then includeDetails = cfg.include_details end
		if type(cfg.skip_empty) == "boolean" then skipEmpty = cfg.skip_empty end
		if type(cfg.anti_duplicate) == "boolean" then antiDuplicate = cfg.anti_duplicate end
		if type(cfg.settle_seconds) == "number" then settleSeconds = math.clamp(cfg.settle_seconds, 2, 15) end
		if type(cfg.retry_count) == "number" then retryCount = math.clamp(math.floor(cfg.retry_count), 0, 3) end
		if cfg.unknown_cost_policy == "Save anyway" or cfg.unknown_cost_policy == "Skip when filtering by cost" then
			unknownCostPolicy = cfg.unknown_cost_policy
		end
		if type(cfg.house_types) == "table" then
			for _, id in ipairs(cfg.house_types) do if type(id) == "string" then selectedHouseTypes[id] = true end end
		end
	end

	local function loadDuplicateCache()
		duplicateCache = {}
		if type(isfile) ~= "function" or type(readfile) ~= "function" then return end
		local okExists, exists = pcall(isfile, duplicateCachePath)
		if not okExists or not exists then return end
		local ok, data = pcall(function() return HttpService:JSONDecode(readfile(duplicateCachePath)) end)
		if ok and type(data) == "table" then duplicateCache = data end
	end

	local function saveDuplicateCache()
		if type(writefile) ~= "function" then return false end
		if not ensureAutoFolders() then return false end
		return pcall(function() writefile(duplicateCachePath, HttpService:JSONEncode(duplicateCache)) end)
	end

	loadAutoScanSettings()
	loadDuplicateCache()

	local houseDB = {}
	pcall(function() houseDB = require(ReplicatedStorage.ClientDB.Housing.HouseDB) end)
	local houseTypeOptions, houseTypeOptionToId, houseTypeIdToOption = {}, {}, {}
	for id, entry in pairs(houseDB) do
		if type(id) == "string" then
			local displayName = type(entry) == "table" and tostring(entry.name or id) or id
			local option = displayName .. " [" .. id .. "]"
			table.insert(houseTypeOptions, option)
			houseTypeOptionToId[option] = id
			houseTypeIdToOption[id] = option
		end
	end
	table.sort(houseTypeOptions, function(a, b) return a:lower() < b:lower() end)

	local function currentHouseTypeOptions()
		local out = {}
		for id in pairs(selectedHouseTypes) do
			local option = houseTypeIdToOption[id]
			if option then table.insert(out, option) end
		end
		table.sort(out)
		return out
	end

	local function setSelectedHouseTypes(value)
		selectedHouseTypes = {}
		if type(value) == "table" then
			for _, option in ipairs(value) do
				local id = houseTypeOptionToId[option] or option
				if type(id) == "string" and id ~= "" then selectedHouseTypes[id] = true end
			end
		end
		saveAutoScanSettings()
	end

	local function playerNames()
		local names = {}
		for _, player in ipairs(Players:GetPlayers()) do table.insert(names, player.Name) end
		table.sort(names)
		return names
	end

	AutoScan:CreateLabel("Visits accessible houses and saves matching scans to HouseFS/autoscan. Estimated cost includes known furniture + textures only.", "info")
	AutoScan:CreateDropdown({
		Name = "Visit", Options = { "Selected player", "Everyone in server" }, CurrentOption = { autoMode }, MultipleOptions = false,
		Callback = function(value)
			autoMode = type(value) == "table" and value[1] or value
			saveAutoScanSettings()
		end,
	})
	local playerDropdown = AutoScan:CreateDropdown({
		Name = "Player", Options = playerNames(), CurrentOption = { autoPlayer }, MultipleOptions = false,
		Callback = function(value)
			autoPlayer = type(value) == "table" and value[1] or value
			saveAutoScanSettings()
		end,
	})
	AutoScan:CreateButton({ Name = "Refresh players", Callback = function()
		local names = playerNames()
		pcall(function() playerDropdown:Refresh(names, true) end)
		if autoPlayer and Players:FindFirstChild(autoPlayer) then pcall(function() playerDropdown:Set({ autoPlayer }) end) end
	end })

	AutoScan:CreateSection("Filters")
	local houseTypeDropdown = AutoScan:CreateDropdown({
		Name = "House types (none selected = any)", Options = houseTypeOptions, CurrentOption = currentHouseTypeOptions(), MultipleOptions = true,
		Callback = setSelectedHouseTypes,
	})
	AutoScan:CreateButton({ Name = "Clear house type selection", Callback = function()
		selectedHouseTypes = {}
		pcall(function() houseTypeDropdown:Set({}) end)
		saveAutoScanSettings()
	end })
	AutoScan:CreateInput({ Name = "Minimum build cost (blank = no minimum)", PlaceholderText = "10000", CurrentValue = minCostText, RemoveTextAfterFocusLost = false,
		Callback = function(value) minCostText = trim(value); saveAutoScanSettings() end })
	AutoScan:CreateInput({ Name = "Maximum build cost (blank = no maximum)", PlaceholderText = "100000", CurrentValue = maxCostText, RemoveTextAfterFocusLost = false,
		Callback = function(value) maxCostText = trim(value); saveAutoScanSettings() end })
	AutoScan:CreateInput({ Name = "Minimum furniture count (blank/0 = no minimum)", PlaceholderText = "150", CurrentValue = minFurnitureText, RemoveTextAfterFocusLost = false,
		Callback = function(value) minFurnitureText = trim(value); saveAutoScanSettings() end })
	AutoScan:CreateInput({ Name = "Minimum texture count (blank/0 = no minimum)", PlaceholderText = "0", CurrentValue = minTexturesText, RemoveTextAfterFocusLost = false,
		Callback = function(value) minTexturesText = trim(value); saveAutoScanSettings() end })
	AutoScan:CreateDropdown({
		Name = "Unknown-price items", Options = { "Save anyway", "Skip when filtering by cost" }, CurrentOption = { unknownCostPolicy }, MultipleOptions = false,
		Callback = function(value)
			unknownCostPolicy = type(value) == "table" and value[1] or value
			saveAutoScanSettings()
		end,
	})

	AutoScan:CreateSection("Reliability")
	AutoScan:CreateToggle({ Name = "Skip empty houses", CurrentValue = skipEmpty, Callback = function(value) skipEmpty = value; saveAutoScanSettings() end })
	AutoScan:CreateToggle({ Name = "Anti-duplicate saves", CurrentValue = antiDuplicate, Callback = function(value) antiDuplicate = value; saveAutoScanSettings() end })
	AutoScan:CreateToggle({ Name = "Include house type and cost in filename", CurrentValue = includeDetails, Callback = function(value) includeDetails = value; saveAutoScanSettings() end })
	AutoScan:CreateInput({ Name = "Stable-data wait (seconds)", PlaceholderText = "4", CurrentValue = tostring(settleSeconds), RemoveTextAfterFocusLost = false,
		Callback = function(value) settleSeconds = math.clamp(tonumber(value) or 4, 2, 15); saveAutoScanSettings() end })
	AutoScan:CreateInput({ Name = "Retry failed house loads", PlaceholderText = "1", CurrentValue = tostring(retryCount), RemoveTextAfterFocusLost = false,
		Callback = function(value) retryCount = math.clamp(math.floor(tonumber(value) or 1), 0, 3); saveAutoScanSettings() end })
	AutoScan:CreateButton({ Name = "Clear anti-duplicate history", Callback = function()
		duplicateCache = {}
		saveDuplicateCache()
		Rayfield:Notify({ Title = "Auto Scan", Content = "Duplicate history cleared.", Duration = 3 })
	end })
	autoScanSettingsReady = true
	saveAutoScanSettings()

	AutoScan:CreateSection("Live status")
	local autoStatus = AutoScan:CreateLabel("Idle", "activity")
	local statProgress = AutoScan:CreateLabel("Progress: 0 / 0", "list")
	local statSaved = AutoScan:CreateLabel("Saved: 0", "save")
	local statSkipped = AutoScan:CreateLabel("Skipped: 0", "circle-minus")
	local statFailed = AutoScan:CreateLabel("Failed: 0", "circle-alert")
	local statCurrent = AutoScan:CreateLabel("Current: -", "user")
	local statHouse = AutoScan:CreateLabel("House: -", "home")
	local statQueue = AutoScan:CreateLabel("Queue: 0", "list-plus")
	local statReasons = AutoScan:CreateLabel("Reasons: -", "info")

	local function autoMessage(message)
		pcall(function() autoStatus:Set(message) end)
		updatestatus(message)
	end

	local function updateStats(index, total, saved, skipped, failed, current, info, queueRemaining, reasonSummary)
		pcall(function() statProgress:Set("Progress: " .. tostring(index or 0) .. " / " .. tostring(total or 0)) end)
		pcall(function() statSaved:Set("Saved: " .. tostring(saved or 0)) end)
		pcall(function() statSkipped:Set("Skipped: " .. tostring(skipped or 0)) end)
		pcall(function() statFailed:Set("Failed: " .. tostring(failed or 0)) end)
		pcall(function() statCurrent:Set("Current: " .. tostring(current or "-")) end)
		pcall(function() statHouse:Set("House: " .. tostring(info or "-")) end)
		pcall(function() statQueue:Set("Queue: " .. tostring(queueRemaining or 0)) end)
		pcall(function() statReasons:Set("Reasons: " .. tostring(reasonSummary or "-")) end)
	end

	-- Saved auto-scan files browser + preview / delete / favorites manager.
	AutoScan:CreateSection("Saved files")
	local selectedSavedFile = nil
	local savedFileStatus = AutoScan:CreateLabel("Selected file: -", "file-json")
	local savedPreviewType = AutoScan:CreateLabel("House type: -", "home")
	local savedPreviewCost = AutoScan:CreateLabel("Build cost: -", "dollar-sign")
	local savedPreviewFurniture = AutoScan:CreateLabel("Furniture: -", "armchair")
	local savedPreviewTextures = AutoScan:CreateLabel("Textures: -", "grid-2x2")
	local savedPreviewPlayer = AutoScan:CreateLabel("Player: -", "user")
	local savedPreviewQuality = AutoScan:CreateLabel("Quality: -", "sparkles")

	local function resetSavedPreview()
		pcall(function() savedPreviewType:Set("House type: -") end)
		pcall(function() savedPreviewCost:Set("Build cost: -") end)
		pcall(function() savedPreviewFurniture:Set("Furniture: -") end)
		pcall(function() savedPreviewTextures:Set("Textures: -") end)
		pcall(function() savedPreviewPlayer:Set("Player: -") end)
		pcall(function() savedPreviewQuality:Set("Quality: -") end)
	end
	local function getSavedAutoScanFiles()
		local names = {}
		if type(listfiles) ~= "function" or type(isfolder) ~= "function" then return { "File listing unavailable" } end
		local okFolder, exists = pcall(isfolder, autoScanFilesPath)
		if not okFolder or not exists then return { "No saved files" } end
		local ok, files = pcall(listfiles, autoScanFilesPath)
		if not ok or type(files) ~= "table" then return { "File listing unavailable" } end
		for _, path in ipairs(files) do
			local normalized = tostring(path):gsub("\\", "/")
			local name = normalized:match("([^/]+)$") or normalized
			if name:lower():sub(-5) == ".json" then table.insert(names, name) end
		end
		table.sort(names, function(a,b) return a:lower() < b:lower() end)
		return #names > 0 and names or { "No saved files" }
	end
	local function estimateQuality(cost, furnitureCount, textureCount)
		cost, furnitureCount, textureCount = tonumber(cost) or 0, tonumber(furnitureCount) or 0, tonumber(textureCount) or 0
		if cost >= 100000 and furnitureCount >= 300 then return "Very Detailed" end
		if cost >= 70000 and furnitureCount >= 200 then return "Detailed" end
		if cost >= 50000 and furnitureCount >= 150 then return "Good Build" end
		if cost >= 30000 and furnitureCount >= 80 then return "Moderate" end
		if furnitureCount >= 150 and textureCount >= 8 then return "Decor-heavy" end
		return "Light Build"
	end
	local function escapeLuaPattern(value)
		return tostring(value or ""):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
	end
	local function extractPlayerFromSavedName(name, buildingType)
		local base = tostring(name or ""):gsub("%.json$", "")
		if buildingType and tostring(buildingType) ~= "" then
			local marker = "_" .. escapeLuaPattern(buildingType) .. "_cost%d+_"
			local playerPart = base:match("^(.-)" .. marker)
			if playerPart and playerPart ~= "" then return playerPart end
		end
		return base:match("^(.-)_%d%d%d%d%d%d%d%d_%d%d%d%d%d%d_") or "Unknown"
	end
	local function previewSavedFile(name)
		if not name then resetSavedPreview(); return end
		if type(readfile) ~= "function" then resetSavedPreview(); pcall(function() savedPreviewType:Set("Preview unavailable: readfile unsupported") end); return end
		local ok, data = pcall(function() return HttpService:JSONDecode(readfile(autoScanFilesPath .. "/" .. name)) end)
		if not ok or type(data) ~= "table" then resetSavedPreview(); pcall(function() savedPreviewType:Set("Preview unavailable: invalid JSON") end); return end
		local furnitureCount = tonumber(data.furniture_quantity) or countfurnitures(data.furniture)
		local textureCount = counttextures(data.textures)
		local cost = tonumber(data.total_cost) or 0
		local houseType = tostring(data.building_type or "Unknown")
		local entry = houseDB[data.building_type]
		local display = type(entry) == "table" and tostring(entry.name or houseType) or houseType
		local playerName = extractPlayerFromSavedName(name, data.building_type)
		pcall(function() savedPreviewType:Set("House type: " .. display .. " [" .. houseType .. "]") end)
		pcall(function() savedPreviewCost:Set("Build cost: $" .. math.floor(cost)) end)
		pcall(function() savedPreviewFurniture:Set("Furniture: " .. furnitureCount) end)
		pcall(function() savedPreviewTextures:Set("Textures: " .. textureCount) end)
		pcall(function() savedPreviewPlayer:Set("Player: " .. playerName) end)
		pcall(function() savedPreviewQuality:Set("Quality: " .. estimateQuality(cost, furnitureCount, textureCount)) end)
	end
	local savedFilesDropdown
	local function refreshSavedFiles(keepSelection)
		local options = getSavedAutoScanFiles()
		pcall(function() savedFilesDropdown:Refresh(options, true) end)
		if keepSelection and selectedSavedFile then
			for _, name in ipairs(options) do
				if name == selectedSavedFile then pcall(function() savedFilesDropdown:Set({ selectedSavedFile }) end); previewSavedFile(selectedSavedFile); return end
			end
		end
		selectedSavedFile = nil
		pcall(function() savedFileStatus:Set("Selected file: -") end)
		resetSavedPreview()
	end
	savedFilesDropdown = AutoScan:CreateDropdown({
		Name = "View saved files", Options = getSavedAutoScanFiles(), CurrentOption = {}, MultipleOptions = false,
		Callback = function(value)
			local name = type(value) == "table" and value[1] or value
			if name == "No saved files" or name == "File listing unavailable" or name == nil then selectedSavedFile = nil; pcall(function() savedFileStatus:Set("Selected file: -") end); resetSavedPreview(); return end
			selectedSavedFile = tostring(name)
			pcall(function() savedFileStatus:Set("Selected file: " .. selectedSavedFile) end)
			previewSavedFile(selectedSavedFile)
		end,
	})
	AutoScan:CreateButton({ Name = "Refresh saved files", Callback = function() refreshSavedFiles(true) end })
	AutoScan:CreateButton({ Name = "Copy selected file path", Callback = function()
		if not selectedSavedFile then return Rayfield:Notify({ Title = "Saved Files", Content = "Select a saved file first.", Duration = 3 }) end
		local path = autoScanFilesPath .. "/" .. selectedSavedFile
		if type(setclipboard) == "function" and pcall(setclipboard, path) then return Rayfield:Notify({ Title = "Saved Files", Content = "File path copied: " .. selectedSavedFile, Duration = 3 }) end
		Rayfield:Notify({ Title = "Saved Files", Content = path, Duration = 5 })
	end })
	AutoScan:CreateButton({ Name = "Favorite selected file", Callback = function()
		if not selectedSavedFile then return Rayfield:Notify({ Title = "Favorites", Content = "Select a saved file first.", Duration = 3 }) end
		if type(readfile) ~= "function" or type(writefile) ~= "function" or type(isfolder) ~= "function" or type(makefolder) ~= "function" then return Rayfield:Notify({ Title = "Favorites", Content = "Required file functions are unavailable.", Duration = 5 }) end
		local ok, err = pcall(function()
			if not isfolder("HouseFS") then makefolder("HouseFS") end
			if not isfolder(favoritesPath) then makefolder(favoritesPath) end
			writefile(favoritesPath .. "/" .. selectedSavedFile, readfile(autoScanFilesPath .. "/" .. selectedSavedFile))
		end)
		if not ok then return Rayfield:Notify({ Title = "Favorites", Content = "Could not favorite file: " .. tostring(err):sub(1,100), Duration = 5 }) end
		Rayfield:Notify({ Title = "Favorites", Content = "Saved to HouseFS/favorites: " .. selectedSavedFile, Duration = 4, Image = "heart" })
	end })
	AutoScan:CreateButton({ Name = "Delete selected saved file", Callback = function()
		if not selectedSavedFile then return Rayfield:Notify({ Title = "Saved Files", Content = "Select a saved file first.", Duration = 3 }) end
		if type(delfile) ~= "function" then return Rayfield:Notify({ Title = "Saved Files", Content = "Deleting files is unavailable.", Duration = 4 }) end
		local deleting = selectedSavedFile
		local ok, err = pcall(delfile, autoScanFilesPath .. "/" .. deleting)
		if not ok then return Rayfield:Notify({ Title = "Saved Files", Content = "Delete failed: " .. tostring(err):sub(1,100), Duration = 5 }) end
		selectedSavedFile = nil
		refreshSavedFiles(false)
		Rayfield:Notify({ Title = "Saved Files", Content = "Deleted: " .. deleting, Duration = 4, Image = "trash-2" })
	end })

	-- Stronger stability signature. This stays much lighter than a full deep copy/JSON encode,
	-- but also watches position/rotation/color-like fields so we do not declare a house stable
	-- just because its furniture IDs stopped changing.
	local function hashText(checksum, text)
		text = tostring(text or "")
		for i = 1, #text do
			checksum = (checksum * 33 + text:byte(i)) % 2147483647
		end
		return checksum
	end

	local function quickHashValue(checksum, value, depth)
		depth = depth or 0
		if depth > 2 then return checksum end
		local valueType = typeof(value)
		if valueType == "CFrame" then
			local c = { value:GetComponents() }
			for i = 1, #c do checksum = hashText(checksum, string.format("%.4f", c[i])) end
		elseif valueType == "Vector3" then
			checksum = hashText(checksum, string.format("%.4f,%.4f,%.4f", value.X, value.Y, value.Z))
		elseif valueType == "Color3" then
			checksum = hashText(checksum, string.format("%.4f,%.4f,%.4f", value.R, value.G, value.B))
		elseif valueType == "number" then
			checksum = hashText(checksum, string.format("%.5f", value))
		elseif valueType == "string" or valueType == "boolean" then
			checksum = hashText(checksum, tostring(value))
		elseif valueType == "table" then
			local keys = {}
			for key in pairs(value) do table.insert(keys, tostring(key)) end
			table.sort(keys)
			local limit = math.min(#keys, 24)
			for i = 1, limit do
				local key = keys[i]
				checksum = hashText(checksum, key)
				local originalValue = value[key]
				if originalValue == nil then
					local numericKey = tonumber(key)
					if numericKey then originalValue = value[numericKey] end
				end
				checksum = quickHashValue(checksum, originalValue, depth + 1)
			end
		end
		return checksum
	end

	local STABILITY_FIELDS = {
		"cframe", "CFrame", "position", "Position", "rotation", "Rotation",
		"color", "Color", "colors", "scale", "Scale", "size", "Size",
		"offset", "Offset", "outfit", "mannequin", "properties",
	}

	local function lightweightHouseSignature(house)
		local furnitureCount, textureCount = 0, 0
		local checksum = hashText(5381, tostring(house.building_type or ""))
		for _, item in pairs(house.furniture or {}) do
			furnitureCount += 1
			checksum = hashText(checksum, tostring(item.id or ""))
			for _, field in ipairs(STABILITY_FIELDS) do
				local value = item[field]
				if value ~= nil then
					checksum = hashText(checksum, field)
					checksum = quickHashValue(checksum, value, 0)
				end
			end
		end
		for _, room in pairs(house.textures or {}) do
			if room.walls then textureCount += 1; checksum = hashText(checksum, "w:" .. tostring(room.walls)) end
			if room.floors then textureCount += 1; checksum = hashText(checksum, "f:" .. tostring(room.floors)) end
		end
		return table.concat({ tostring(house.building_type or ""), tostring(furnitureCount), tostring(textureCount), tostring(checksum) }, "|")
	end

	local function ownedBy(house, player)
		if not house then return false end
		local owner = house.player
		return owner == player or owner == player.Name or owner == player.UserId
	end

	local function waitForHouse(player, stableWait, timeoutSeconds)
		local deadline = os.clock() + (timeoutSeconds or 30)
		local lastSignature, stableSince, arrivedAt = nil, nil, nil
		while os.clock() < deadline do
			if autoStop or not runtimeIsAlive() then return nil, "Stopped" end
			if player.Parent ~= Players then return nil, "Player left" end
			local ok, house = pcall(function() return cd.get("house_interior") end)
			if ok and ownedBy(house, player) and type(house.furniture) == "table" and house.building_type then
				local now = os.clock()
				arrivedAt = arrivedAt or now
				local signature = lightweightHouseSignature(house)
				if signature ~= lastSignature then lastSignature, stableSince = signature, now end
				if stableSince and now - arrivedAt >= 3 and now - stableSince >= stableWait then
					return deepCopy(house)
				end
			else
				lastSignature, stableSince, arrivedAt = nil, nil, nil
			end
			task.wait(0.5)
		end
		return nil, "House did not load or settle"
	end

	local function enterAndWait(interiors, player, stableWait, retries)
		local lastErr = "House did not load"
		for attempt = 1, (retries or 0) + 1 do
			if autoStop or not runtimeIsAlive() then return nil, "Stopped" end
			autoMessage("Entering " .. player.Name .. "'s house" .. (attempt > 1 and (" (retry " .. (attempt-1) .. ")") or ""))
			local enterOk, enterErr = pcall(function() interiors.enter("housing", "MainDoor", { house_owner = player }) end)
			if enterOk then
				autoMessage("Waiting for " .. player.Name .. "'s house data")
				local snapshot, err = waitForHouse(player, stableWait, 30)
				if snapshot then return snapshot end
				lastErr = err or lastErr
			else
				lastErr = "Enter failed: " .. tostring(enterErr):sub(1,100)
			end
			if autoStop or not runtimeIsAlive() then return nil, "Stopped" end
			task.wait(1.5)
		end
		return nil, lastErr
	end

	local function simpleHash(text)
		local h = 5381
		for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967296 end
		return string.format("%08x", h)
	end

	local function canonicalSerialize(value, seen)
		local valueType = typeof(value)
		if valueType == "nil" then return "nil" end
		if valueType == "number" then return string.format("n:%.10g", value) end
		if valueType == "boolean" then return value and "b:1" or "b:0" end
		if valueType == "string" then return "s:" .. value end
		if valueType == "CFrame" then
			local c = { value:GetComponents() }
			for i = 1, #c do c[i] = string.format("%.6f", c[i]) end
			return "cf:" .. table.concat(c, ",")
		end
		if valueType == "Vector3" then return string.format("v3:%.6f,%.6f,%.6f", value.X, value.Y, value.Z) end
		if valueType == "Color3" then return string.format("c3:%.6f,%.6f,%.6f", value.R, value.G, value.B) end
		if valueType ~= "table" then return valueType .. ":" .. tostring(value) end

		seen = seen or {}
		if seen[value] then return "<cycle>" end
		seen[value] = true
		local keys = {}
		for key in pairs(value) do table.insert(keys, key) end
		table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
		local parts = {}
		for _, key in ipairs(keys) do
			table.insert(parts, canonicalSerialize(key, seen) .. "=" .. canonicalSerialize(value[key], seen))
		end
		seen[value] = nil
		return "{" .. table.concat(parts, ";") .. "}"
	end

	local function canonicalHouseFingerprint(cleanHouse)
		local normalized = {}
		for key, value in pairs(cleanHouse or {}) do
			if key ~= "furniture" and key ~= "textures" and key ~= "total_cost" and key ~= "furniture_quantity" and key ~= "saved_by" then
				normalized[key] = value
			end
		end

		local furniture = {}
		for _, item in pairs((cleanHouse and cleanHouse.furniture) or {}) do
			table.insert(furniture, canonicalSerialize(item))
		end
		table.sort(furniture)
		normalized.__furniture = furniture

		local textures = {}
		for _, room in pairs((cleanHouse and cleanHouse.textures) or {}) do
			table.insert(textures, canonicalSerialize(room))
		end
		table.sort(textures)
		normalized.__textures = textures

		return simpleHash(canonicalSerialize(normalized))
	end

	local function encodeAutoSnapshot(house)
		local encoded, err, clean, fc, tc, unknown = encodeHouseForSave(house)
		if not encoded then return nil, err end
		local info = analyzeHouse(house)
		return {
			encoded = encoded, clean = clean, fc = fc, tc = tc, unknown = unknown,
			analysis = info, fingerprint = canonicalHouseFingerprint(clean),
		}
	end

	local function saveAutoSnapshot(prepared, house, player, details)
		if type(writefile) ~= "function" then return nil, "writefile unavailable" end
		local folderOk, folderErr = ensureAutoFolders()
		if not folderOk then return nil, tostring(folderErr or "Could not create folders") end
		local base = player.Name
		if details then base = base .. "_" .. tostring(house.building_type) .. "_cost" .. math.floor(prepared.fc + prepared.tc) end
		base = (sanitizeFileName(base) or "House"):sub(1,75)
		local suffix = os.date("%Y%m%d_%H%M%S") .. "_" .. HttpService:GenerateGUID(false):sub(1,8)
		local path = autoScanFilesPath .. "/" .. base .. "_" .. suffix .. ".json"
		if autoStop or not runtimeIsAlive() then return nil, "Stopped" end
		local ok, err = pcall(writefile, path, prepared.encoded)
		if not ok then return nil, "writefile failed: " .. tostring(err):sub(1,100) end
		task.defer(function() refreshSavedFiles(true) end)
		return path
	end

	local function parseNonnegative(textValue, whole)
		if textValue == "" then return nil, true end
		local n = tonumber(textValue)
		if not n or n < 0 or (whole and n % 1 ~= 0) then return nil, false end
		if whole and n == 0 then return nil, true end
		return n, true
	end

	local function startAutoScan()
		if autoRunning then return false end
		local minCost, ok1 = parseNonnegative(minCostText, false)
		local maxCost, ok2 = parseNonnegative(maxCostText, false)
		local minFurniture, ok3 = parseNonnegative(minFurnitureText, true)
		local minTextures, ok4 = parseNonnegative(minTexturesText, true)
		if not ok1 or not ok2 or not ok3 or not ok4 or (minCost and maxCost and minCost > maxCost) then
			Rayfield:Notify({ Title = "Filters", Content = "Check your minimum/maximum cost and count filters.", Duration = 5 })
			return false
		end

		local modeSnapshot = autoMode
		local queue, queued, processed = {}, {}, {}
		local function enqueueTarget(target)
			if not target or target.Parent ~= Players then return false end
			local key = tostring(target.UserId)
			if queued[key] or processed[key] then return false end
			queued[key] = true
			table.insert(queue, target)
			return true
		end

		if modeSnapshot == "Everyone in server" then
			local initial = Players:GetPlayers()
			table.sort(initial, function(a,b) return a.Name:lower() < b.Name:lower() end)
			for _, target in ipairs(initial) do enqueueTarget(target) end
		else
			local target = autoPlayer and Players:FindFirstChild(autoPlayer)
			if target then enqueueTarget(target) end
		end

		if #queue == 0 then
			Rayfield:Notify({ Title = "Auto Scan", Content = "Select a player who is still in this server.", Duration = 5 })
			return false
		end

		local wantedTypes = {}
		for id in pairs(selectedHouseTypes) do wantedTypes[id] = true end
		local details, ignoreEmpty, stableWait, retries = includeDetails, skipEmpty, settleSeconds, retryCount
		local duplicateEnabled, unknownPolicy = antiDuplicate, unknownCostPolicy
		autoRunning, autoStop = true, false

		local skipReasons, failReasons = {}, {}
		local function addReason(bucket, reason)
			reason = tostring(reason or "Unknown")
			local key = reason
			if reason:find("Duplicate", 1, true) then key = "Duplicate"
			elseif reason:find("House type", 1, true) then key = "House type"
			elseif reason:find("Empty house", 1, true) then key = "Empty"
			elseif reason:find("Furniture count", 1, true) then key = "Furniture filter"
			elseif reason:find("Texture count", 1, true) then key = "Texture filter"
			elseif reason:find("Unknown prices", 1, true) then key = "Unknown prices"
			elseif reason:find("Cost below", 1, true) then key = "Below min cost"
			elseif reason:find("Cost above", 1, true) then key = "Above max cost"
			elseif reason:find("Player left", 1, true) then key = "Player left"
			elseif reason:find("load or settle", 1, true) then key = "House load"
			elseif reason:find("Enter failed", 1, true) then key = "Enter failed"
			elseif reason:find("Encode failed", 1, true) then key = "Encode"
			elseif reason:find("writefile", 1, true) then key = "File save" end
			bucket[key] = (bucket[key] or 0) + 1
		end

		local function compactReasons()
			local parts = {}
			local function append(prefix, bucket)
				local rows = {}
				for name, count in pairs(bucket) do table.insert(rows, {name=name,count=count}) end
				table.sort(rows, function(a,b) if a.count == b.count then return a.name < b.name end return a.count > b.count end)
				for i = 1, math.min(3, #rows) do table.insert(parts, prefix .. rows[i].name .. " " .. rows[i].count) end
			end
			append("S:", skipReasons)
			append("F:", failReasons)
			return #parts > 0 and table.concat(parts, " | ") or "-"
		end

		updateStats(0, #queue, 0, 0, 0, "-", "-", #queue, "-")

		task.spawn(function()
			local saved, skipped, failed = 0, 0, 0
			local joinConnection
			if modeSnapshot == "Everyone in server" then
				joinConnection = Players.PlayerAdded:Connect(function(newPlayer)
					if autoRunning and not autoStop and runtimeIsAlive() and enqueueTarget(newPlayer) then
						autoMessage("Queued " .. newPlayer.Name .. " (joined server)")
						updateStats(0, #queue, saved, skipped, failed, "-", "New player queued", #queue, compactReasons())
					end
				end)
			end

			local ok, outerErr = pcall(function()
				local folderOk, folderErr = ensureAutoFolders()
				if not folderOk or type(writefile) ~= "function" then error(folderErr or "Local file saving unavailable") end
				local load = require(ReplicatedStorage:WaitForChild("Fsys")).load
				local interiors = load("InteriorsM")

				local index = 1
				while index <= #queue do
					if autoStop or not runtimeIsAlive() then break end
					local target = queue[index]
					local targetKey = target and tostring(target.UserId) or "missing:" .. tostring(index)
					queued[targetKey] = nil
					processed[targetKey] = true
					local total = #queue
					local remainingQueue = math.max(0, total - index)
					local targetName = target and target.Name or "Unknown"

					updateprog(index .. "/" .. total)
					updateitem(targetName)
					updateStats(index, total, saved, skipped, failed, targetName, "Loading...", remainingQueue, compactReasons())

					local visitOk, outcome, reason = pcall(function()
						if not target or target.Parent ~= Players then return "skipped", "Player left" end
						local snapshot, loadErr = enterAndWait(interiors, target, stableWait, retries)
						if autoStop or not runtimeIsAlive() then return "stopped" end
						if not snapshot then return "failed", loadErr end

						local info = analyzeHouse(snapshot)
						local kind = info.houseType
						local entry = houseDB[snapshot.building_type]
						local display = type(entry) == "table" and tostring(entry.name or kind) or kind
						local statusInfo = display .. " | $" .. math.floor(info.totalCost) .. " | " .. info.furnitureCount .. " furniture"
						updateStats(index, #queue, saved, skipped, failed, target.Name, statusInfo, math.max(0, #queue-index), compactReasons())
						setscaninfo(info.furnitureCount, info.furnitureCost, info.textureCount, info.textureCost, info.ambiance, kind)

						if next(wantedTypes) ~= nil and not wantedTypes[kind] then return "skipped", "House type filter" end
						if ignoreEmpty and info.furnitureCount == 0 then return "skipped", "Empty house" end
						if minFurniture and info.furnitureCount < minFurniture then return "skipped", "Furniture count " .. info.furnitureCount .. " < " .. minFurniture end
						if minTextures and info.textureCount < minTextures then return "skipped", "Texture count " .. info.textureCount .. " < " .. minTextures end
						if (minCost or maxCost) and info.unknownCount > 0 and unknownPolicy == "Skip when filtering by cost" then return "skipped", "Unknown prices: " .. info.unknownCount end
						if minCost and info.totalCost < minCost then return "skipped", "Cost below minimum" end
						if maxCost and info.totalCost > maxCost then return "skipped", "Cost above maximum" end

						local prepared, prepErr = encodeAutoSnapshot(snapshot)
						if not prepared then return "failed", "Encode failed: " .. tostring(prepErr):sub(1,100) end
						local duplicateKey = tostring(target.UserId) .. ":" .. kind .. ":" .. prepared.fingerprint
						if duplicateEnabled and duplicateCache[duplicateKey] then return "skipped", "Duplicate house" end
						local path, saveErr = saveAutoSnapshot(prepared, snapshot, target, details)
						if not path then if saveErr == "Stopped" then return "stopped" end; return "failed", saveErr end
						duplicateCache[duplicateKey] = { file = path, saved_at = os.time(), player = target.Name, building_type = kind, fingerprint = prepared.fingerprint }
						if duplicateEnabled then saveDuplicateCache() end
						savedhouse = snapshot
						notifyTelegramSave(path, display .. " [" .. kind .. "]", target.Name, prepared.analysis.totalCost, prepared.analysis.unknownCount)
						return "saved", path
					end)

					if autoStop or not runtimeIsAlive() or outcome == "stopped" then break end
					if not visitOk then
						failed += 1
						addReason(failReasons, outcome)
						autoMessage(targetName .. ": " .. tostring(outcome):sub(1,120))
					elseif outcome == "saved" then
						saved += 1
						autoMessage("Saved " .. targetName)
					elseif outcome == "skipped" then
						skipped += 1
						addReason(skipReasons, reason)
						autoMessage("Skipped " .. targetName .. ": " .. tostring(reason))
					else
						failed += 1
						addReason(failReasons, reason)
						autoMessage("Failed " .. targetName .. ": " .. tostring(reason))
					end

					updateStats(index, #queue, saved, skipped, failed, targetName, reason or outcome or "-", math.max(0, #queue-index), compactReasons())
					index += 1
					task.wait(0.75)
				end
			end)

			if joinConnection then pcall(function() joinConnection:Disconnect() end) end
			autoRunning = false
			local summary = saved .. " saved, " .. skipped .. " skipped, " .. failed .. " failed."
			local reasons = compactReasons()
			if reasons ~= "-" then summary = summary .. " Reasons: " .. reasons end
			if not ok then summary = summary .. " " .. tostring(outerErr):sub(1,160) end
			autoMessage((autoStop and "Stopped. " or "Finished. ") .. summary)
			updateStats(#queue, #queue, saved, skipped, failed, "-", "-", 0, reasons)
			if runtimeIsAlive() then Rayfield:Notify({ Title = "Auto Scan", Content = summary, Duration = 8 }) end
		end)
		return true
	end

	AutoScan:CreateButton({ Name = "Start Teleport + Scan + Save", Callback = startAutoScan })
	AutoScan:CreateButton({ Name = "Stop Auto Scan", Callback = function()
		autoStop = true
		autoMessage(autoRunning and "Stopping..." or "Idle")
	end })

	if runtimeIsAlive() then
		Rayfield:Notify({ Title = "Cubix", Content = "Scan, Save & Auto Scan is ready", Duration = 4 })
	end
end

local ok, err = pcall(loadMain)
if not ok then
	warn("[Cubix] Startup error:", err)
end
