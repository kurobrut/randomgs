-- // Services and modules
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

local router = require(ReplicatedStorage.ClientModules.Core.RouterClient.RouterClient)
local cd = require(ReplicatedStorage.ClientModules.Core.ClientData)
local furnituresdb = require(ReplicatedStorage.ClientDB.Housing.FurnitureDB)
local texturesdb = require(ReplicatedStorage.ClientDB.Housing.TexturesDB)
local housedb = require(ReplicatedStorage.ClientDB.Housing.HouseDB)

local Fsys = require(ReplicatedStorage:WaitForChild("Fsys")).load
local HouseDB = Fsys("HouseDB")
local ClientData = Fsys("ClientData")
local Router = Fsys("RouterClient")

local plr = Players.LocalPlayer
while not plr do
	task.wait()
	plr = Players.LocalPlayer
end

--==================================================
-- JSON Helpers
--==================================================
local function lEncode(t)
	return HttpService:JSONEncode(t)
end
local function lDecode(s)
	return HttpService:JSONDecode(s)
end

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

	local Window = Rayfield:CreateWindow({
		Name = "Cubix . House Cloner ",
		LoadingTitle = "Cubix",
		LoadingSubtitle = "House Cloner",
		Theme = "Amethyst",
		ConfigurationSaving = {
			Enabled = true,
			FileName = "CubixAutoPaste",
		},
		Discord = {
			Enabled = true,
			Invite = "VVsxaBNakm",
			RememberJoins = false,
		},
	})

	local savedhouse = nil
	local stopFlag = false  -- single declaration

	-- Forward-declare paste functions so Auto Paste tab can reference them
	local pastehousefast
	local pastehouseslow
	local IgnoreTypeCheck
	local Pastetextures

	local afkEnabled = false
	plr.Idled:Connect(function()
		local afkOk = pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new(0, 0))
		end)
		if not afkEnabled then
			afkEnabled = true
			Rayfield:Notify({
				Title = "AFK",
				Content = afkOk and "Anti-AFK is now active" or "Anti-AFK is unavailable in this executor",
				Duration = 3
			})
		end
	end)

	local Manager = Window:CreateTab("Manager", "trending-up")
	local Tab = Window:CreateTab("Main", "home")
	local BuyerTab = Window:CreateTab("House Buyer", "shopping-bag")
	local TradeTab = Window:CreateTab("Trading", "repeat")

	-- ==================== MANAGER TAB ====================
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
	local status_label = Manager:CreateLabel("Building Status: Idle", "activity")
	local prog_label = Manager:CreateLabel("Building Prog: -", "trending-up")
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
			status_label:Set("Building Status: " .. s)
		end)
	end
	local function updateprog(p)
		pcall(function()
			prog_label:Set("Building Prog: " .. p)
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

	-- ==================== SHARED OWNED HOUSES SYSTEM ====================
	local ownedHouseList = {}
	local ownedHouseMap = {} -- unique display label → house_id
	local ownedHouseLabelById = {} -- house_id → unique display label
	local ownedHouseTypeMap = {} -- house_id → resolved house type
	local ownedDropdown
	local tradeDropdown
	local autoPasteDropdown
	local autoPasteSelections = {} -- { [house_id] = display_label }
	local pendingAutoPasteTargetIds = {} -- saved IDs waiting for house_manager to populate
	local restorePendingAutoPasteTargets
	local autoPasteApplyingSavedTargets = false

	local function resolveHouseType(typeValue)
		if not typeValue or typeValue == "-" or typeValue == "Unknown" or typeValue == "" then
			return nil
		end

		local low = string.lower(tostring(typeValue))
		for kind, data in pairs(housedb) do
			if string.lower(tostring(kind)) == low then
				return string.lower(tostring(kind))
			end
			if data.name and string.lower(data.name) == low then
				return string.lower(tostring(kind))
			end
			if data.building_type and string.lower(tostring(data.building_type)) == low then
				return string.lower(tostring(kind))
			end
			if data.type and string.lower(tostring(data.type)) == low then
				return string.lower(tostring(kind))
			end
		end

		return low
	end

	local function resolveExactHouseType(typeValue)
		if not typeValue or typeValue == "-" or typeValue == "Unknown" then return nil end
		for kind, data in pairs(housedb) do
			if kind == typeValue then return kind end
			if data.name and string.lower(data.name) == string.lower(tostring(typeValue)) then return kind end
			if data.building_type and data.building_type == typeValue then return kind end
			if data.type and data.type == typeValue then return kind end
		end
		return typeValue
	end

	local function getExactHouseDisplayName(kind)
		for k, data in pairs(housedb) do
			if k == kind then return data.name or kind end
		end
		return kind
	end

	local function isExactSameHouseType(a, b)
		if a == b then return true end
		local function getName(val)
			for kind, data in pairs(housedb) do
				if kind == val then return data.name end
				if data.name and string.lower(data.name) == string.lower(tostring(val)) then return data.name end
			end
			return tostring(val)
		end
		return string.lower(getName(a)) == string.lower(getName(b))
	end

	local function getSavedHouseExactType(houseData)
		local savedType = "-"
		local savedKind = nil
		local savedName = nil
		pcall(function()
			savedType = houseData.building_type or "-"
			savedKind = houseData.kind
			savedName = houseData.name
		end)

		local resolvedSaved = resolveExactHouseType(savedType)
		if not resolvedSaved and savedKind then resolvedSaved = resolveExactHouseType(savedKind) end
		if not resolvedSaved and savedName then resolvedSaved = resolveExactHouseType(savedName) end
		return resolvedSaved
	end

	local function getInteriorExactType(houseInterior)
		local currentType = "-"
		pcall(function()
			currentType = houseInterior.building_type or "-"
		end)
		return resolveExactHouseType(currentType)
	end

	local function refreshOwnedHouses()
		table.clear(ownedHouseList)
		table.clear(ownedHouseMap)
		table.clear(ownedHouseLabelById)
		table.clear(ownedHouseTypeMap)

		local manager = {}
		pcall(function()
			manager = ClientData.get("house_manager") or {}
		end)
		local nameCounts = {}
		for _, house in pairs(manager) do
			local baseName = tostring(house.name or "House")
			nameCounts[baseName] = (nameCounts[baseName] or 0) + 1
		end

		for _, house in pairs(manager) do
			local baseName = tostring(house.name or "House")
			local label = baseName
			if (nameCounts[baseName] or 0) > 1 then
				label = baseName .. " [" .. tostring(house.house_id) .. "]"
			end
			table.insert(ownedHouseList, label)
			ownedHouseMap[label] = house.house_id
			ownedHouseLabelById[house.house_id] = label
			local houseType = house.building_type or house.kind or house.type or "unknown"
			ownedHouseTypeMap[house.house_id] = resolveExactHouseType(houseType) or resolveHouseType(houseType) or tostring(houseType)
		end

		table.sort(ownedHouseList)

		if ownedDropdown then
			pcall(function() ownedDropdown:Refresh(ownedHouseList, true) end)
		end
		if tradeDropdown then
			pcall(function() tradeDropdown:Refresh(ownedHouseList, true) end)
		end
		if autoPasteDropdown then
			autoPasteApplyingSavedTargets = true
			pcall(function()
				autoPasteDropdown:Refresh(ownedHouseList, true)
				local selectedLabels = {}
				for houseId in pairs(autoPasteSelections) do
					local label = ownedHouseLabelById[houseId]
					if label then table.insert(selectedLabels, label) end
				end
				table.sort(selectedLabels)
				autoPasteDropdown:Set(selectedLabels)
			end)
			autoPasteApplyingSavedTargets = false
		end

		-- Saved target IDs may be loaded before ClientData has populated
		-- house_manager. Resolve them automatically whenever the house list changes.
		if restorePendingAutoPasteTargets then
			restorePendingAutoPasteTargets(true)
		end
	end

	-- ==================== AUTO PASTE TAB ====================
	local AutoPasteTab = Window:CreateTab("Auto Paste", "copy")

	local autoPasteRunning = false
	local autoListAfterPaste = false
	local queueKaliremHouses
	local processAutoList
	local autoBuyQueuedHouses
	local autoBuyQueuedEnabled = false
	local autoBuyQueuedRunning = false
	local autoBuyQueuedToggle
	local autoTradeEnabled = false
	local selectedPlayer = nil
	local autoAcceptToggle
	local PlayerDropdown
	local getPlayers
	local autoPasteMode = "fast"
	local autoPasteSource = "loaded"
	local autoPasteSingleFile = false
	local fileQueue = {}
	local fqAllFiles = {}
	local fqSearchQuery = ""
	local fqFileDropdown
	local fqQueueListLabel
	local autoPasteFileInfo
	local autoPasteQueueCostLabel
	local autoPasteStatus
	local autoPasteProgress
	local autoPastePastebinValue = ""
	local autoPasteQueueCopies = 1
	local autoPasteSourceDropdown
	local autoPasteConfigReady = false
	local autoPasteSaveState = { pending = false, dirty = false, lastError = nil }


	local houseFSPath = "HouseFS"
	local houseSettingsPath = houseFSPath .. "/settings"
	local houseFilesPath = houseFSPath .. "/Houses"
	local autoPasteConfigPath = houseSettingsPath .. "/autopaste.json"

	pcall(function()
		if not isfolder(houseFSPath) then
			makefolder(houseFSPath)
		end

		if not isfolder(houseSettingsPath) then
			makefolder(houseSettingsPath)
		end

		if not isfolder(houseFilesPath) then
			makefolder(houseFilesPath)
		end
	end)


	local function deserializeFileValue(value, context)
		if type(value) ~= "table" then return value end

		-- New files use explicit type tags so Vector3 and Color3 are never ambiguous.
		if value.__type == "CFrame" then
			local components = value.components or value.c or {}
			return CFrame.new(table.unpack(components))
		elseif value.__type == "Vector3" then
			return Vector3.new(value.x or value.X or 0, value.y or value.Y or 0, value.z or value.Z or 0)
		elseif value.__type == "Color3" then
			return Color3.new(value.r or value.R or 0, value.g or value.G or 0, value.b or value.B or 0)
		end

		-- Backward compatibility with old HouseFS files. Raw 12-number arrays are CFrames.
		-- Raw 3-number arrays are only treated as colors when their parent is known to be
		-- a color container; otherwise they stay arrays instead of being misread as Color3.
		if context ~= "preserve" and #value > 0 then
			if #value == 12 and type(value[1]) == "number" then
				return CFrame.new(table.unpack(value))
			end
			if #value == 3 and type(value[1]) == "number" and (context == "color" or context == "ambiance") then
				return Color3.new(value[1], value[2], value[3])
			end
		end

		if value.r and value.g and value.b and type(value.r) == "number" then
			return Color3.new(value.r, value.g, value.b)
		end
		if value.R and value.G and value.B and type(value.R) == "number" then
			return Color3.new(value.R, value.G, value.B)
		end

		for k, v in pairs(value) do
			local key = string.lower(tostring(k))
			local nextContext = context
			if context == "colors" then
				nextContext = "color"
			elseif context == "ambiance" then
				nextContext = "ambiance"
			elseif key == "colors" then
				nextContext = "colors"
			elseif key == "ambiance" then
				nextContext = "ambiance"
			elseif key == "outfit" then
				nextContext = "preserve"
			end
			value[k] = deserializeFileValue(v, nextContext)
		end
		return value
	end

	local function convertFileToInternalFormat(decoded)
		if decoded.f and type(decoded.f) == "table" and #decoded.f > 0 and decoded.t and decoded.b then
			local furniture = {}
			for i, f in ipairs(decoded.f) do
				local colors = {}
				for ck, cv in pairs(f.cl or {}) do colors[tonumber(ck)] = cv end
				furniture[tostring(i)] = {
					id = f.i,
					cframe = f.c,
					colors = colors,
					scale = f.s,
					outfit = f.outfit or f.o,
					outfit_name = f.outfit_name or f.on,
				}
			end
			decoded.furniture = furniture
			decoded.f = nil

			local textures = {}
			for _, t in pairs(decoded.t or {}) do
				local room = t.r
				if not textures[room] then textures[room] = {} end
				if t.k == "walls" then textures[room].walls = t.i
				elseif t.k == "floors" then textures[room].floors = t.i end
			end
			decoded.textures = textures
			decoded.building_type = decoded.b
			decoded.ambiance = decoded.a
		elseif decoded.Furniture then
			decoded.furnitures = decoded.Furniture
			decoded.Furniture = nil
		end

		if decoded.Floors or decoded.Walls then
			decoded.textures = {}
			if decoded.Floors then
				for _, f in ipairs(decoded.Floors) do
					table.insert(decoded.textures, { type = f.typeOfTexture, id = f.id, room = f.room })
				end
			end
			if decoded.Walls then
				for _, w in ipairs(decoded.Walls) do
					table.insert(decoded.textures, { type = w.typeOfTexture, id = w.id, room = w.room })
				end
			end
		end

		if decoded.BuildType then decoded.building_type = decoded.BuildType decoded.BuildType = nil end

		if decoded.furnitures and #decoded.furnitures > 0 then
			local function convertColors(obj)
				if type(obj) ~= "table" then return obj end
				if obj.__isColor then return { __type = "Color3", r = obj.r, g = obj.g, b = obj.b } end
				for k, v in pairs(obj) do obj[k] = convertColors(v) end
				return obj
			end

			local furniture = {}
			for i, f in ipairs(decoded.furnitures) do
				local colors = {}
				for ck, cv in pairs(f.colors or {}) do colors[ck] = cv end
				furniture[tostring(i)] = {
					id = f.id,
					cframe = f.cframe,
					colors = colors,
					scale = f.scale,
					outfit = f.outfit,
					outfit_name = f.outfit_name,
				}
			end
			decoded.furniture = furniture
			decoded.furnitures = nil

			local textures = {}
			for _, t in ipairs(decoded.textures or {}) do
				if not textures[t.room] then textures[t.room] = {} end
				if t.type == "walls" then textures[t.room].walls = t.id
				elseif t.type == "floors" then textures[t.room].floors = t.id end
			end
			decoded.textures = textures
			if decoded.ambiance then decoded.ambiance = convertColors(decoded.ambiance) end
		elseif type(decoded.furniture) == "table" then
			for _, item in pairs(decoded.furniture) do
				local new_colors = {}
				for i, col in pairs(item.colors or {}) do new_colors[i] = col end
				item.colors = new_colors
				if type(item.cframe) == "table" and item.cframe.components then
					item.cframe = item.cframe.components
				end
			end
		end

		decoded.building_type = decoded.building_type or decoded.buildingType or "Unknown"
		decoded.buildingType = nil
		return decoded
	end

	local function loadHouseDataFromFile(filename)
		filename = tostring(filename or ""):match("([^/\\]+)$") or tostring(filename or "")
		local filePath = houseFilesPath .. "/" .. filename
		local success, content = pcall(readfile, filePath)
		if not success or not content then
			return nil, "Failed to read file"
		end

		local decoded
		local ok = pcall(function()
			decoded = HttpService:JSONDecode(content)
		end)

		if not ok then
			local env = {
				Vector3 = { new = function(x, y, z) return { __type = "Vector3", X = x, Y = y, Z = z } end },
				Color3 = { new = function(r, g, b) return { __type = "Color3", R = r, G = g, B = b } end },
				CFrame = { new = function(...) return { __type = "CFrame", components = { ... } } end },
			}
			local func, loaderr = loadstring(content)
			if not func then return nil, "Loadstring error: " .. tostring(loaderr) end
			if type(setfenv) ~= "function" then
				return nil, "This executor cannot safely load Lua-format house files (setfenv unavailable)"
			end
			local envOk, envErr = pcall(setfenv, func, env)
			if not envOk then return nil, "Sandbox error: " .. tostring(envErr) end
			local runok, data = pcall(func)
			if not runok then return nil, "Run error: " .. tostring(data) end
			decoded = data
		end

		if type(decoded) ~= "table" then
			return nil, "Invalid data in file"
		end

		return deserializeFileValue(convertFileToInternalFormat(decoded)), nil
	end

	local function loadHouseDataFromPastebin(pasteValue)
		local input = tostring(pasteValue or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if input == "" then
			return nil, "Please enter a Pastebin link or ID"
		end

		-- Support a paste ID alone, a normal link, and a /raw/ link.
		local pasteId = input:match("^[Hh][Tt][Tt][Pp][Ss]?://[^/]*pastebin%.com/raw/([^/?#]+)")
			or input:match("^[Hh][Tt][Tt][Pp][Ss]?://[^/]*pastebin%.com/([^/?#]+)")
			or input:match("^[Ww][Ww][Ww]%.pastebin%.com/raw/([^/?#]+)")
			or input:match("^[Ww][Ww][Ww]%.pastebin%.com/([^/?#]+)")
			or input:match("^[Pp]astebin%.com/raw/([^/?#]+)")
			or input:match("^[Pp]astebin%.com/([^/?#]+)")
			or input:match("^([^/?#%s]+)$")

		if not pasteId or not pasteId:match("^[%w_-]+$") then
			return nil, "Enter a Pastebin ID or Pastebin link"
		end

		local response
		local success = pcall(function()
			response = HttpService:RequestAsync({
				Url = "https://pastebin.com/raw/" .. pasteId,
				Method = "GET",
			})
		end)

		if not success or not response or response.Success == false or not response.Body or response.Body == "" then
			return nil, "Failed to fetch Pastebin data"
		end

		local decoded
		local ok = pcall(function()
			decoded = HttpService:JSONDecode(response.Body)
		end)

		if not ok or type(decoded) ~= "table" then
			return nil, "Invalid Pastebin JSON"
		end

		return deserializeFileValue(convertFileToInternalFormat(decoded)), pasteId
	end

	local function getFileHouseType(houseData)
		return getSavedHouseExactType(houseData) or "Unknown"
	end

	local function findMatchingHouse(fileType, candidateIds, usedIds)
		local fallbackId = nil
		for _, houseId in ipairs(candidateIds) do
			if not usedIds[houseId] then
				local ownedType = ownedHouseTypeMap[houseId]
				if ownedType and isExactSameHouseType(fileType, ownedType) then
					return houseId
				end
				if not fallbackId and (not ownedType or ownedType == "unknown" or ownedType == "Unknown") then
					fallbackId = houseId
				end
			end
		end
		return fallbackId
	end

	local function getQueueHouseCost(houseData)
		if type(houseData) ~= "table" then
			return 0
		end

		local furnitureCost = 0
		for _, item in pairs(houseData.furniture or {}) do
			if furnituresdb[item.id] then
				furnitureCost += furnituresdb[item.id].cost or 0
			end
		end

		local textureCost = 0
		for _, texture in pairs(houseData.textures or {}) do
			if texturesdb.walls[texture.walls] then
				textureCost += texturesdb.walls[texture.walls].cost or 0
			end
			if texturesdb.floors[texture.floors] then
				textureCost += texturesdb.floors[texture.floors].cost or 0
			end
		end

		return furnitureCost + textureCost
	end

	local function getQueueTotalCost()
		local total = 0
		for _, entry in ipairs(fileQueue) do
			total += getQueueHouseCost(entry.houseData)
		end
		return total
	end

	local function setAPFileInfo()
		if autoPasteFileInfo then
			pcall(function()
				autoPasteFileInfo:Set("File Queue: " .. #fileQueue .. " file(s)")
			end)
		end
		if autoPasteQueueCostLabel then
			pcall(function()
				autoPasteQueueCostLabel:Set("Queued Total Cost: $" .. getQueueTotalCost())
			end)
		end
	end

	local function setAutoPasteSource(source)
		autoPasteSource = source
		if autoPasteSourceDropdown then
			pcall(function()
				autoPasteSourceDropdown:Set(source == "filequeue" and "File Queue" or "Loaded House")
			end)
		end
	end

	local function rebuildQueueLabel()
		if not fqQueueListLabel then return end
		if #fileQueue == 0 then
			pcall(function() fqQueueListLabel:Set("Queue: (empty)") end)
			return
		end

		local lines = {}
		for i, entry in ipairs(fileQueue) do
			local cost = getQueueHouseCost(entry.houseData)
			table.insert(lines, i .. ". " .. entry.filename .. " [" .. getFileHouseType(entry.houseData) .. "] ($" .. cost .. ")")
		end
		pcall(function() fqQueueListLabel:Set("Queue:\n" .. table.concat(lines, "\n")) end)
	end

	local function getAutoPasteTargetNames()
		local selectedNames = {}
		for houseId in pairs(autoPasteSelections) do
			local label = ownedHouseLabelById[houseId]
			if label then table.insert(selectedNames, label) end
		end
		table.sort(selectedNames)
		return selectedNames
	end

	restorePendingAutoPasteTargets = function(updateDropdown)
		local restored = 0
		for savedId in pairs(pendingAutoPasteTargetIds) do
			for label, houseId in pairs(ownedHouseMap) do
				if tostring(houseId) == tostring(savedId) then
					autoPasteSelections[houseId] = label
					pendingAutoPasteTargetIds[savedId] = nil
					restored += 1
					break
				end
			end
		end

		-- Refresh labels for already-selected IDs too (important after renames or
		-- duplicate-name disambiguation changes).
		for houseId in pairs(autoPasteSelections) do
			local label = ownedHouseLabelById[houseId]
			if label then autoPasteSelections[houseId] = label end
		end

		if updateDropdown and restored > 0 and autoPasteDropdown then
			autoPasteApplyingSavedTargets = true
			pcall(function() autoPasteDropdown:Set(getAutoPasteTargetNames()) end)
			autoPasteApplyingSavedTargets = false
		end
		return restored
	end

	-- Queue entries contain Roblox values (such as CFrame and Color3) that JSON
	-- cannot store directly. Convert them into explicit typed tables and also
	-- normalize dictionary keys so HttpService:JSONEncode never receives a
	-- mixed-key table.
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

	local function saveAutoPasteConfig()
		local folderOk, folderErr = pcall(function()
			if not isfolder(houseFSPath) then makefolder(houseFSPath) end
			if not isfolder(houseSettingsPath) then makefolder(houseSettingsPath) end
		end)
		if not folderOk then
			autoPasteSaveState.lastError = "Could not create settings folder: " .. tostring(folderErr)
			return false, autoPasteSaveState.lastError
		end

		local targetIds = {}
		local targetIdSet = {}
		for houseId in pairs(autoPasteSelections) do
			local id = tostring(houseId)
			if not targetIdSet[id] then
				targetIdSet[id] = true
				table.insert(targetIds, id)
			end
		end
		for savedId in pairs(pendingAutoPasteTargetIds) do
			local id = tostring(savedId)
			if not targetIdSet[id] then
				targetIdSet[id] = true
				table.insert(targetIds, id)
			end
		end

		local config = {
			version = 1,
			source = autoPasteSource,
			singleFileMode = autoPasteSingleFile,
			pasteMode = autoPasteMode,
			queueCopies = autoPasteQueueCopies,
			pastebinValue = autoPastePastebinValue,
			targetHouseIds = targetIds,
			queue = serializeAutoPasteValue(fileQueue),
			autoAcceptPlayer = selectedPlayer,
			autoAcceptEnabled = autoTradeEnabled,
			autoBuyQueuedHouses = false,
		}

		local ok, encoded = pcall(function() return HttpService:JSONEncode(config) end)
		if not ok then
			autoPasteSaveState.lastError = "Could not encode queue config: " .. tostring(encoded)
			return false, autoPasteSaveState.lastError
		end

		local wrote, err = pcall(function() writefile(autoPasteConfigPath, encoded) end)
		if not wrote then
			autoPasteSaveState.lastError = "Could not save config: " .. tostring(err)
			return false, autoPasteSaveState.lastError
		end

		autoPasteSaveState.lastError = nil
		autoPasteSaveState.dirty = false
		return true, #fileQueue, #targetIds
	end

	local function loadAutoPasteConfig()
		if not isfile(autoPasteConfigPath) then
			return false, "No saved Auto Paste config found"
		end

		local readOk, content = pcall(function() return readfile(autoPasteConfigPath) end)
		if not readOk then return false, "Could not read config: " .. tostring(content) end
		local decodeOk, config = pcall(function() return HttpService:JSONDecode(content) end)
		if not decodeOk or type(config) ~= "table" then return false, "Saved config is invalid" end

		table.clear(fileQueue)
		for _, entry in ipairs(config.queue or {}) do
			if type(entry) == "table" and type(entry.houseData) == "table" then
				table.insert(fileQueue, {
					filename = tostring(entry.filename or entry.sourceName or "Queued House"),
					sourceName = tostring(entry.sourceName or entry.filename or "Queued House"),
					houseData = deserializeFileValue(entry.houseData),
				})
			end
		end

		autoPasteSource = config.source == "filequeue" and "filequeue" or "loaded"
		autoPasteSingleFile = config.singleFileMode == true
		autoPasteMode = config.pasteMode == "slow" and "slow" or "fast"
		autoPasteQueueCopies = math.clamp(math.floor(tonumber(config.queueCopies) or 1), 1, 50)
		autoPastePastebinValue = tostring(config.pastebinValue or "")
		selectedPlayer = type(config.autoAcceptPlayer) == "string" and config.autoAcceptPlayer or nil
		autoTradeEnabled = config.autoAcceptEnabled == true
		autoBuyQueuedEnabled = false -- always start disabled; do not restore from saved config

		table.clear(autoPasteSelections)
		table.clear(pendingAutoPasteTargetIds)
		for _, savedId in ipairs(config.targetHouseIds or {}) do
			pendingAutoPasteTargetIds[tostring(savedId)] = true
		end
		restorePendingAutoPasteTargets(false)

		local missingTargets = 0
		for _ in pairs(pendingAutoPasteTargetIds) do
			missingTargets += 1
		end

		setAutoPasteSource(autoPasteSource)
		if autoPasteDropdown then
			autoPasteApplyingSavedTargets = true
			pcall(function() autoPasteDropdown:Set(getAutoPasteTargetNames()) end)
			autoPasteApplyingSavedTargets = false
		end
		autoPasteApplyingSavedTargets = true
		if PlayerDropdown then
			pcall(function()
				PlayerDropdown:Refresh(getPlayers())
				PlayerDropdown:Set(selectedPlayer or "None")
			end)
		end
		if autoAcceptToggle then
			pcall(function() autoAcceptToggle:Set(autoTradeEnabled) end)
		end
		autoPasteApplyingSavedTargets = false
		if autoBuyQueuedToggle then
			pcall(function() autoBuyQueuedToggle:Set(autoBuyQueuedEnabled) end)
		end
		rebuildQueueLabel()
		setAPFileInfo()
		return true, #fileQueue, missingTargets
	end

	local function autoSaveAutoPasteConfig()
		-- Queue, target houses, selected player, and Auto Accept are persistent
		-- session state. Never discard their save request, even while Auto Paste
		-- is running. A tiny debounce coalesces callbacks that fire in the same
		-- frame, then the complete latest state is written to disk.
		autoPasteSaveState.dirty = true
		if not autoPasteConfigReady then return end
		if autoPasteSaveState.pending then return end

		autoPasteSaveState.pending = true
		task.delay(0.05, function()
			autoPasteSaveState.pending = false
			if not autoPasteConfigReady or not autoPasteSaveState.dirty then return end

			local callOk, savedOk, saveErr = pcall(saveAutoPasteConfig)
			if not callOk then
				autoPasteSaveState.lastError = tostring(savedOk)
				warn("[Cubix AutoSave] " .. autoPasteSaveState.lastError)
			elseif not savedOk then
				warn("[Cubix AutoSave] " .. tostring(saveErr))
			end

		end)
	end

	local function refreshFQFileList()
		table.clear(fqAllFiles)
		local folderOk, folderExists = pcall(isfolder, houseFilesPath)
		if not folderOk or not folderExists then
			pcall(makefolder, houseFilesPath)
		end

		local listed, files = pcall(listfiles, houseFilesPath)
		if not listed or type(files) ~= "table" then
			files = {}
		end

		for _, filePath in ipairs(files) do
			local fileName = tostring(filePath):match("([^/\\]+)$") or tostring(filePath)
			if fileName ~= "auto_paste_config.json"
				and (fileName:sub(-5) == ".json" or fileName:sub(-4) == ".txt" or fileName:sub(-4) == ".lua")
			then
				table.insert(fqAllFiles, fileName)
			end
		end
		table.sort(fqAllFiles)

		local filtered = {}
		for _, name in ipairs(fqAllFiles) do
			if fqSearchQuery == "" or string.find(string.lower(name), string.lower(fqSearchQuery), 1, true) then
				table.insert(filtered, name)
			end
		end

		if fqFileDropdown then
			pcall(function() fqFileDropdown:Refresh(filtered) end)
		end
	end

	refreshOwnedHouses()
	AutoPasteTab:CreateLabel("Use the current loaded house, or queue files from HouseFS/Houses.", "info")

	AutoPasteTab:CreateSection("Source")
	autoPasteSourceDropdown = AutoPasteTab:CreateDropdown({
		Name = "Paste Source",
		Options = { "Loaded House", "File Queue" },
		CurrentOption = { "Loaded House" },
		MultipleOptions = false,
		Flag = "AutoPasteSource",
		Callback = function(opt)
			local v = (typeof(opt) == "table") and opt[1] or opt
			setAutoPasteSource(v == "File Queue" and "filequeue" or "loaded")
			autoSaveAutoPasteConfig()
		end,
	})

	AutoPasteTab:CreateToggle({
		Name = "Single File Mode",
		CurrentValue = false,
		Flag = "AutoPasteSingleFileMode",
		Callback = function(v)
			autoPasteSingleFile = v
			autoSaveAutoPasteConfig()
		end,
	})

	autoBuyQueuedToggle = AutoPasteTab:CreateToggle({
		Name = "Auto Buy Queued Houses",
		CurrentValue = false,
		Callback = function(value)
			autoBuyQueuedEnabled = value
			autoSaveAutoPasteConfig()
			if value and #fileQueue > 0 and autoBuyQueuedHouses then
				autoBuyQueuedHouses()
			end
		end,
	})

	AutoPasteTab:CreateSection("File Queue")
	AutoPasteTab:CreateInput({
		Name = "Copies To Queue",
		PlaceholderText = "1",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			local n = tonumber(value)
			if n and n > 0 then
				autoPasteQueueCopies = math.clamp(math.floor(n), 1, 50)
				Rayfield:Notify({
					Title = "File Queue",
					Content = "Copies set to " .. autoPasteQueueCopies,
					Duration = 2,
				})
				autoSaveAutoPasteConfig()
			end
		end,
	})

	AutoPasteTab:CreateInput({
		Name = "Search Files",
		PlaceholderText = "Type to filter files...",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			fqSearchQuery = tostring(value or "")
			refreshFQFileList()
		end,
	})

	fqFileDropdown = AutoPasteTab:CreateDropdown({
		Name = "Select File(s) to Queue",
		Options = {},
		CurrentOption = {},
		MultipleOptions = true,
		Callback = function(_) end,
	})

	AutoPasteTab:CreateButton({
		Name = "Refresh File List",
		Callback = function()
			refreshFQFileList()
			Rayfield:Notify({ Title = "File Queue", Content = "File list refreshed", Duration = 2 })
		end,
	})

	AutoPasteTab:CreateButton({
		Name = "Add Selected File(s) to Queue",
		Callback = function()
			local selected = fqFileDropdown.CurrentOption
			if type(selected) == "string" then selected = { selected } end
			if not selected or #selected == 0 then
				return Rayfield:Notify({ Title = "File Queue", Content = "No file selected", Duration = 3 })
			end

			local added = 0
			for _, filename in ipairs(selected) do
				local houseData, err = loadHouseDataFromFile(filename)
				if houseData then
					setAutoPasteSource("filequeue")
					for copyIndex = 1, autoPasteQueueCopies do
						local displayName = filename
						if autoPasteQueueCopies > 1 then
							displayName = filename .. " #" .. copyIndex
						end
						table.insert(fileQueue, { filename = displayName, sourceName = filename, houseData = houseData })
						added += 1
					end
					Rayfield:Notify({
						Title = "File Queue",
						Content = "Added " .. autoPasteQueueCopies .. "x " .. filename .. " [" .. getFileHouseType(houseData) .. "]",
						Duration = 2,
					})
				else
					Rayfield:Notify({
						Title = "File Queue",
						Content = "Failed to load " .. filename .. ": " .. tostring(err),
						Duration = 4,
					})
				end
			end

			rebuildQueueLabel()
			setAPFileInfo()
			autoSaveAutoPasteConfig()
			if added > 0 and autoBuyQueuedEnabled and autoBuyQueuedHouses then
				autoBuyQueuedHouses()
			end
			if added > 0 then
				Rayfield:Notify({ Title = "File Queue", Content = added .. " file(s) added", Duration = 3 })
			end
		end,
	})

	fqQueueListLabel = AutoPasteTab:CreateLabel("Queue: (empty)", "list")

	AutoPasteTab:CreateInput({
		Name = "Pastebin Link / ID",
		PlaceholderText = "https://pastebin.com/xxxxxx or xxxxxx",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			autoPastePastebinValue = tostring(value or "")
			autoSaveAutoPasteConfig()
		end,
	})

	AutoPasteTab:CreateButton({
		Name = "Add Pastebin to Queue",
		Callback = function()
			local houseData, pasteIdOrErr = loadHouseDataFromPastebin(autoPastePastebinValue)
			if not houseData then
				return Rayfield:Notify({
					Title = "Pastebin Queue",
					Content = tostring(pasteIdOrErr),
					Duration = 4,
				})
			end

			local pasteId = tostring(pasteIdOrErr)
			local baseName = "Pastebin_" .. pasteId
			setAutoPasteSource("filequeue")
			for copyIndex = 1, autoPasteQueueCopies do
				local displayName = baseName
				if autoPasteQueueCopies > 1 then
					displayName = baseName .. " #" .. copyIndex
				end
				table.insert(fileQueue, {
					filename = displayName,
					sourceName = baseName,
					houseData = houseData,
				})
			end
			rebuildQueueLabel()
			setAPFileInfo()
			autoSaveAutoPasteConfig()
			if autoBuyQueuedEnabled and autoBuyQueuedHouses then
				autoBuyQueuedHouses()
			end

			Rayfield:Notify({
				Title = "Pastebin Queue",
				Content = "Added " .. autoPasteQueueCopies .. "x " .. baseName .. " [" .. getFileHouseType(houseData) .. "]",
				Duration = 3,
			})
		end,
	})

	AutoPasteTab:CreateButton({
		Name = "Remove First Queue Item",
		Callback = function()
			if #fileQueue == 0 then
				return Rayfield:Notify({ Title = "File Queue", Content = "Queue is empty", Duration = 2 })
			end
			local removed = table.remove(fileQueue, 1)
			rebuildQueueLabel()
			setAPFileInfo()
			autoSaveAutoPasteConfig()
			Rayfield:Notify({ Title = "File Queue", Content = "Removed " .. removed.filename, Duration = 2 })
		end,
	})

	AutoPasteTab:CreateButton({
		Name = "Clear File Queue",
		Callback = function()
			autoPasteRunning = false
			stopFlag = true
			table.clear(fileQueue)
			rebuildQueueLabel()
			setAPFileInfo()
			autoSaveAutoPasteConfig()
			if autoPasteStatus then
				pcall(function() autoPasteStatus:Set("Status: Idle") end)
			end
			if autoPasteProgress then
				pcall(function() autoPasteProgress:Set("Progress: -") end)
			end
			Rayfield:Notify({ Title = "File Queue", Content = "Queue cleared", Duration = 2 })
		end,
	})

	AutoPasteTab:CreateSection("Target Houses")

	autoPasteDropdown = AutoPasteTab:CreateDropdown({
		Name = "Select Houses to Paste Into",
		Options = ownedHouseList,
		CurrentOption = {},
		MultipleOptions = true,
		Flag = "AutoPasteTargetHouses",
		Callback = function(opts)
			if autoPasteApplyingSavedTargets then return end
			table.clear(autoPasteSelections)
			table.clear(pendingAutoPasteTargetIds)
			for _, name in ipairs(opts or {}) do
				local id = ownedHouseMap[name]
				if id then
					autoPasteSelections[id] = name
				end
			end
			local count = 0
			for _ in pairs(autoPasteSelections) do count += 1 end
			autoSaveAutoPasteConfig()
			if autoPasteConfigReady then
				Rayfield:Notify({
					Title = "Auto Paste",
					Content = count .. " house(s) selected",
					Duration = 2,
				})
			end
		end,
	})

	AutoPasteTab:CreateButton({
		Name = "Refresh House List",
		Callback = function()
			-- Refresh available houses without destroying the saved target IDs.
			refreshOwnedHouses()
			restorePendingAutoPasteTargets(true)
			autoSaveAutoPasteConfig()
			Rayfield:Notify({
				Title = "Auto Paste",
				Content = "House list refreshed (" .. #ownedHouseList .. " houses). Saved targets were preserved.",
				Duration = 4,
			})
		end,
	})

	AutoPasteTab:CreateSection("Paste Mode")

	AutoPasteTab:CreateDropdown({
		Name = "Paste Mode",
		Options = { "Fast", "Slow" },
		CurrentOption = { "Fast" },
		MultipleOptions = false,
		Flag = "AutoPasteMode",
		Callback = function(opt)
			local v = (typeof(opt) == "table") and opt[1] or opt
			autoPasteMode = v == "Slow" and "slow" or "fast"
			autoSaveAutoPasteConfig()
		end,
	})

	AutoPasteTab:CreateSection("Controls")

	autoPasteStatus = AutoPasteTab:CreateLabel("Status: Idle", "activity")
	autoPasteProgress = AutoPasteTab:CreateLabel("Progress: -", "trending-up")
	autoPasteFileInfo = AutoPasteTab:CreateLabel("File Queue: 0 file(s)", "list")
	autoPasteQueueCostLabel = AutoPasteTab:CreateLabel("Queued Total Cost: $0", "list")

	local function setAPStatus(s) pcall(function() autoPasteStatus:Set("Status: " .. s) end) end
	local function setAPProg(s)   pcall(function() autoPasteProgress:Set("Progress: " .. s) end) end

	local function waitUntilInsideHouse(targetId, timeout)
		timeout = timeout or 30
		local start = tick()
		while tick() - start < timeout do
			local ok, interior = pcall(function() return cd.get("house_interior") end)
			if ok and interior and interior.house_id == targetId then
				return true
			end
			task.wait(0.5)
		end
		return false
	end

	local function teleportToHouse(houseId)
		local ok, err = pcall(function()
			local interiors = Fsys("InteriorsM")
			-- SpawnHouse selects the exact owned house. Entry itself uses the normal
			-- owner form; waitUntilInsideHouse strictly verifies house_id afterward.
			interiors.enter("housing", "MainDoor", { house_owner = Players.LocalPlayer })
		end)
		return ok, err
	end

	local function exitCurrentHouse()
		local ok, err = pcall(function()
			local interior = ClientData.get("house_interior")
			if interior then
				Router.get("HousingAPI/UnsubscribeFromHouse")
					:InvokeServer(interior.house_owner or Players.LocalPlayer, true)
			end
		end)
		return ok, err
	end

	local function deselectAutoPasteTarget(houseId)
		if not houseId then return end
		autoPasteSelections[houseId] = nil
		if autoPasteDropdown then
			local selectedNames = {}
			for _, name in pairs(autoPasteSelections) do
				table.insert(selectedNames, name)
			end
			table.sort(selectedNames)
			pcall(function() autoPasteDropdown:Set(selectedNames) end)
		end
		autoSaveAutoPasteConfig()
	end

	local function clearCurrentHouseFurniture(timeout)
		timeout = timeout or 15
		local ok, interior = pcall(function() return cd.get("house_interior") end)
		if not ok or not interior then
			return false, "Could not read current house"
		end

		local ids = {}
		for furnitureId in pairs(interior.furniture or {}) do
			table.insert(ids, furnitureId)
		end
		if #ids == 0 then return true end

		local sellOk, sellErr = pcall(function()
			router.get("HousingAPI/SellFurniture"):FireServer(false, ids, "sell")
		end)
		if not sellOk then
			return false, tostring(sellErr)
		end

		local started = tick()
		while tick() - started < timeout do
			if stopFlag then return false, "Stopped" end
			local readOk, current = pcall(function() return cd.get("house_interior") end)
			if readOk and current then
				local remaining = 0
				for _ in pairs(current.furniture or {}) do remaining += 1 end
				if remaining == 0 then return true end
			end
			task.wait(0.5)
		end
		return false, "Timed out waiting for furniture to clear"
	end

	local function getCurrentHouseType()
		local ok, interior = pcall(function() return cd.get("house_interior") end)
		if not ok or not interior then
			return nil
		end

		return getInteriorExactType(interior)
	end

	local function pasteIntoHouse(houseId, houseName, houseData, mode, expectedType)
		local spawnOk, spawnErr = pcall(function()
			router.get("HousingAPI/SpawnHouse"):FireServer(houseId)
		end)
		if not spawnOk then
			Rayfield:Notify({ Title = "Auto Paste", Content = "Failed to spawn " .. houseName .. ": " .. tostring(spawnErr), Duration = 5 })
			return false
		end
		task.wait(2)

		Rayfield:Notify({ Title = "Auto Paste", Content = "Entering: " .. houseName, Duration = 3 })
		local enterOk, enterErr = teleportToHouse(houseId)
		if not enterOk then
			Rayfield:Notify({ Title = "Auto Paste", Content = "Failed to enter " .. houseName .. ": " .. tostring(enterErr), Duration = 5 })
			return false
		end

		local inside = waitUntilInsideHouse(houseId, 20)
		if not inside then
			Rayfield:Notify({ Title = "Auto Paste", Content = "Could not verify entry into " .. houseName .. ", skipping", Duration = 5 })
			exitCurrentHouse()
			return false
		end

		local actualType = getCurrentHouseType()
		if actualType then ownedHouseTypeMap[houseId] = actualType end

		if expectedType and (not actualType or not isExactSameHouseType(expectedType, actualType)) then
			Rayfield:Notify({
				Title = "Auto Paste",
				Content = "House types do not match!\nSaved: "
					.. tostring(getExactHouseDisplayName(expectedType))
					.. "\nCurrent: "
					.. tostring(actualType and getExactHouseDisplayName(actualType) or "Unknown")
					.. "\nSkipped: " .. houseName,
				Duration = 6,
			})
			exitCurrentHouse()
			task.wait(1)
			return "type_mismatch"
		end

		local cleared, clearErr = clearCurrentHouseFurniture(15)
		if not cleared then
			Rayfield:Notify({ Title = "Auto Paste", Content = "Could not clear " .. houseName .. ": " .. tostring(clearErr), Duration = 5 })
			exitCurrentHouse()
			return false
		end
		if stopFlag or not autoPasteRunning then
			exitCurrentHouse()
			return false
		end

		local pasteOk = (mode == "slow") and pastehouseslow(houseData) or pastehousefast(houseData)
		if pasteOk ~= true then
			Rayfield:Notify({ Title = "Auto Paste", Content = "Paste failed for " .. houseName .. "; queue item kept", Duration = 5 })
			exitCurrentHouse()
			return false
		end
		if stopFlag or not autoPasteRunning then
			exitCurrentHouse()
			return false
		end

		exitCurrentHouse()
		task.wait(2)
		deselectAutoPasteTarget(houseId)
		return true
	end

	AutoPasteTab:CreateButton({
		Name = "Start Auto Paste Queue",
		Callback = function()
			if autoPasteRunning then
				return Rayfield:Notify({ Title = "Auto Paste", Content = "Already running!", Duration = 3 })
			end

			if type(pastehousefast) ~= "function" or type(pastehouseslow) ~= "function" then
				return Rayfield:Notify({
					Title = "Auto Paste",
					Content = "Script not fully loaded yet.\nPlease wait a moment and try again.",
					Duration = 5,
				})
			end

			if autoPasteSource == "loaded" and not savedhouse then
				return Rayfield:Notify({
					Title = "Auto Paste",
					Content = "No house loaded.\nPlease scan or load a house first.",
					Duration = 4,
				})
			end

			if autoPasteSource == "filequeue" and #fileQueue == 0 then
				return Rayfield:Notify({
					Title = "Auto Paste",
					Content = "File Queue is empty.\nAdd files first.",
					Duration = 4,
				})
			end

			local candidateIds = {}
			for id, _ in pairs(autoPasteSelections) do
				table.insert(candidateIds, id)
			end

			if #candidateIds == 0 then
				return Rayfield:Notify({
					Title = "Auto Paste",
					Content = "No houses selected.\nUse Refresh then select houses from dropdown.",
					Duration = 5,
				})
			end

			autoPasteRunning = true
			stopFlag = false

			task.spawn(function()
				setAPStatus("Running")

				if autoPasteSource == "loaded" then
					local total = #candidateIds
					for i, houseId in ipairs(candidateIds) do
						if stopFlag or not autoPasteRunning then break end
						local houseName = autoPasteSelections[houseId] or tostring(houseId)
						local expectedType = nil
						if not (IgnoreTypeCheck and IgnoreTypeCheck.CurrentValue) then
							expectedType = getSavedHouseExactType(savedhouse)
						end
						setAPProg(i .. "/" .. total .. " - " .. houseName)
						if pasteIntoHouse(houseId, houseName, savedhouse, autoPasteMode, expectedType) == true then
							Rayfield:Notify({ Title = "Auto Paste", Content = houseName .. " done", Duration = 2 })
						end
						task.wait(1)
					end
				elseif autoPasteSource == "filequeue" then
					local usedHouseIds = {}

					if autoPasteSingleFile then
						local fileEntry = fileQueue[1]
						if fileEntry then
							local fileType = getFileHouseType(fileEntry.houseData)
							local matchingHouses = {}
							local completed = true

							for _, houseId in ipairs(candidateIds) do
								local ownedType = ownedHouseTypeMap[houseId]
								if (ownedType and isExactSameHouseType(fileType, ownedType))
									or not ownedType
									or ownedType == "unknown"
									or ownedType == "Unknown"
								then
									table.insert(matchingHouses, houseId)
								end
							end

							if #matchingHouses == 0 then
								Rayfield:Notify({
									Title = "Auto Paste",
									Content = "No matching houses for " .. fileEntry.filename .. " [" .. fileType .. "]",
									Duration = 5,
								})
							else
								for i, houseId in ipairs(matchingHouses) do
									if stopFlag or not autoPasteRunning then
										completed = false
										break
									end
									local houseName = autoPasteSelections[houseId] or tostring(houseId)
									setAPProg(i .. "/" .. #matchingHouses .. " - " .. fileEntry.filename .. " -> " .. houseName)
									local pasteResult = pasteIntoHouse(houseId, houseName, fileEntry.houseData, autoPasteMode, fileType)
									if pasteResult == true then
										Rayfield:Notify({ Title = "Auto Paste", Content = houseName .. " done", Duration = 2 })
									else
										completed = false
										if stopFlag or not autoPasteRunning then break end
									end
									task.wait(1)
								end
							end

							-- Keep the entry if the run was stopped or no target matched;
							-- it can be continued after selecting compatible houses.
							if completed and #matchingHouses > 0 then
								table.remove(fileQueue, 1)
								rebuildQueueLabel()
								setAPFileInfo()
								autoSaveAutoPasteConfig()
							end
						end
					else
						local totalFiles = #fileQueue
						local fileIndex = 1
						local progressIndex = 0

						while fileIndex <= #fileQueue and autoPasteRunning and not stopFlag do
							local fileEntry = fileQueue[fileIndex]
							local currentProgress = math.min(progressIndex + 1, totalFiles)
							local fileType = getFileHouseType(fileEntry.houseData)
							local matchedId = findMatchingHouse(fileType, candidateIds, usedHouseIds)

							if not matchedId then
								Rayfield:Notify({
									Title = "Auto Paste",
									Content = "No matching house for " .. fileEntry.filename .. " [" .. fileType .. "], skipping",
									Duration = 5,
								})
								progressIndex += 1
								fileIndex += 1
								continue
							end

							local houseName = autoPasteSelections[matchedId] or tostring(matchedId)
							setAPProg(currentProgress .. "/" .. totalFiles .. " - " .. fileEntry.filename .. " -> " .. houseName)

							local pasteResult = pasteIntoHouse(matchedId, houseName, fileEntry.houseData, autoPasteMode, fileType)
							if pasteResult == true then
								progressIndex += 1
								usedHouseIds[matchedId] = true
								table.remove(fileQueue, fileIndex)
								rebuildQueueLabel()
								setAPFileInfo()
								autoSaveAutoPasteConfig()
								Rayfield:Notify({
									Title = "Auto Paste",
									Content = fileEntry.filename .. " -> " .. houseName .. " done",
									Duration = 3,
								})
							elseif pasteResult == "type_mismatch" then
								usedHouseIds[matchedId] = true
							else
								progressIndex += 1
								fileIndex += 1
							end

							task.wait(1)
						end
					end
				end

				local wasStopped = stopFlag
				autoPasteRunning = false
				autoSaveAutoPasteConfig()
				setAPStatus(wasStopped and "Stopped" or "Idle")
				setAPProg("-")
				if not wasStopped then
					Rayfield:Notify({ Title = "Auto Paste", Content = "Auto paste finished", Duration = 5 })
				end
				if autoListAfterPaste and not wasStopped then
					-- The Auto Trade worker is persistent. Calling this again is safe:
					-- it either starts the watcher or leaves the existing watcher running.
					processAutoList()
				end
			end)
		end,
	})

	AutoPasteTab:CreateButton({
		Name = "Stop",
		Callback = function()
				autoPasteRunning = false
				stopFlag = true
				autoSaveAutoPasteConfig()
				setAPStatus("Stopped")
			setAPProg("-")
			Rayfield:Notify({ Title = "Auto Paste", Content = "Stopped", Duration = 3 })
		end,
	})

	refreshFQFileList()

	-- ==================== HOUSE BUYER TAB ====================
	local selectedHouseKinds = {}
	local selectedHouseId = nil
	local autoBuy = false
	local buyAmount = 1

	local houseList = {}
	local houseMap = {}

	for _, data in pairs(HouseDB) do
		if data.is_for_sale then
			table.insert(houseList, data.name)
			houseMap[data.name] = data.kind
		end
	end

	table.sort(houseList)

	BuyerTab:CreateDropdown({
		Name = "Select House To Buy",
		Options = houseList,
		MultipleOptions = true,
		Callback = function(opt)
			table.clear(selectedHouseKinds)
			if typeof(opt) == "table" then
				for _, v in ipairs(opt) do
					if houseMap[v] then
						table.insert(selectedHouseKinds, houseMap[v])
					end
				end
			else
				if houseMap[opt] then
					table.insert(selectedHouseKinds, houseMap[opt])
				end
			end
		end,
	})

	BuyerTab:CreateInput({
		Name = "Amount of Houses to Buy",
		PlaceholderText = "Enter number...",
		RemoveTextAfterFocusLost = false,
		Callback = function(t)
			local n = tonumber(t)
			if n and n > 0 then
				buyAmount = math.clamp(math.floor(n), 1, 100)
				Rayfield:Notify({ Title = "Auto Buy", Content = "Set to " .. buyAmount, Duration = 3 })
			end
		end,
	})

	local function captureOwnedHouseIds()
		local ids = {}
		for _, house in pairs(ClientData.get("house_manager") or {}) do
			ids[house.house_id] = true
		end
		return ids
	end

	local function getOwnedHouseById(id)
		for _, house in pairs(ClientData.get("house_manager") or {}) do
			if house.house_id == id then return house end
		end
		return nil
	end

	local function waitUntilHouseGone(id, timeout, shouldContinue)
		local started = tick()
		while true do
			if shouldContinue and not shouldContinue() then
				return false, "cancelled"
			end

			if not getOwnedHouseById(id) then
				return true
			end

			-- A nil/false/zero timeout means wait indefinitely. This is used by
			-- Auto Paste -> Auto Trade so a listed Kalirem house is never skipped
			-- just because nobody accepted it within an arbitrary time window.
			if timeout and timeout > 0 and tick() - started >= timeout then
				return false, "timeout"
			end

			task.wait(0.5)
		end
	end

	local function autoRenameNewHouse(before, timeout)
		timeout = timeout or 8
		local started = tick()
		local newHouses = {}
		repeat
			table.clear(newHouses)
			for _, house in pairs(ClientData.get("house_manager") or {}) do
				if not before[house.house_id] then
					table.insert(newHouses, house)
				end
			end
			if #newHouses > 0 then break end
			task.wait(0.4)
		until tick() - started >= timeout

		if #newHouses == 0 then return 0 end

		local maxNumber = 0
		for _, house in pairs(ClientData.get("house_manager") or {}) do
			local n = tonumber(string.match(tostring(house.name or ""), "^Kalirem (%d+)$")) or 0
			if n > maxNumber then maxNumber = n end
		end

		for _, house in ipairs(newHouses) do
			maxNumber += 1
			local newName = "Kalirem " .. maxNumber
			local ok = pcall(function()
				Router.get("HousingAPI/RenameHouse"):FireServer(house.house_id, newName)
			end)
			if ok then
				Rayfield:Notify({ Title = "Rename", Content = newName, Duration = 2 })
			else
				warn("House was purchased but rename failed for:", house.house_id)
			end
		end
		return #newHouses
	end

	local function buyOneHouse(kind)
		local before = captureOwnedHouseIds()
		local invokeOk, invokeResult = pcall(function()
			return Router.get("HousingAPI/BuyHouseWithAddons")
				:InvokeServer(kind, {}, Color3.fromRGB(255, 182, 193))
		end)
		if not invokeOk then
			Rayfield:Notify({ Title = "Auto Buy", Content = "Failed " .. tostring(kind) .. ": " .. tostring(invokeResult), Duration = 4 })
			return false
		end

		local renamed = autoRenameNewHouse(before, 8)
		if renamed <= 0 then
			Rayfield:Notify({ Title = "Auto Buy", Content = "Purchase was not confirmed for " .. tostring(kind), Duration = 4 })
			return false
		end
		Rayfield:Notify({ Title = "Auto Buy", Content = "Bought " .. tostring(kind) .. " 🏠", Duration = 2 })
		return true
	end

	local function buyHouse()
		if #selectedHouseKinds == 0 then
			Rayfield:Notify({ Title = "Auto Buy", Content = "No house selected ❌", Duration = 3 })
			return false
		end
		local allSucceeded = true
		for _, kind in ipairs(selectedHouseKinds) do
			if not buyOneHouse(kind) then allSucceeded = false end
			task.wait(0.5)
		end
		refreshOwnedHouses()
		return allSucceeded
	end

	autoBuyQueuedHouses = function()
		if not autoBuyQueuedEnabled or #fileQueue == 0 or autoBuyQueuedRunning then
			return
		end

		autoBuyQueuedRunning = true

		task.spawn(function()
			local ok, err = pcall(function()

				local required = {}

				for _, entry in ipairs(fileQueue) do
					local houseType = getFileHouseType(entry.houseData)

					-- Convert known display name to database kind
					if houseType == "Tiny Home" then
						houseType = "micro_2023"
					end

					local buyKind = nil

					-- Find the actual purchasable HouseDB kind
					for dbKind, data in pairs(HouseDB) do
						if type(data) ~= "table" then
							continue
						end

						if data.is_for_sale ~= true then
							continue
						end

						local candidates = {
							data.kind,
							dbKind,
							data.building_type,
							data.type,
							data.name,
						}

						for _, candidate in ipairs(candidates) do
							if candidate and (
								string.lower(tostring(candidate))
									== string.lower(tostring(houseType))
								or isExactSameHouseType(houseType, candidate)
							) then
								buyKind = data.kind or dbKind
								break
							end
						end

						if buyKind then
							break
						end
					end

					if buyKind then
						required[buyKind] = (required[buyKind] or 0) + 1
					else
						Rayfield:Notify({
							Title = "Auto Buy",
							Content = "Could not find purchasable house for: "
								.. tostring(houseType),
							Duration = 4,
						})
					end
				end

				-- ==========================================
				-- BUY EXACTLY WHAT IS IN THE QUEUE
				-- ==========================================

				local totalRequired = 0

				for _, amount in pairs(required) do
					totalRequired += amount
				end

				if totalRequired == 0 then
					return
				end

				local boughtTotal = 0

				for kind, needed in pairs(required) do
					if not autoBuyQueuedEnabled then
						return
					end

					for i = 1, needed do
						if not autoBuyQueuedEnabled then
							return
						end

						local before = {}

						for _, house in pairs(ClientData.get("house_manager") or {}) do
							before[house.house_id] = true
						end

						local success, buyError = pcall(function()
							Router.get("HousingAPI/BuyHouseWithAddons")
								:InvokeServer(
									kind,
									{},
									Color3.fromRGB(255, 182, 193)
								)
						end)

						if success then
							local renamed = autoRenameNewHouse(before, 8)
							if renamed > 0 then
								boughtTotal += 1
								Rayfield:Notify({
									Title = "Auto Buy",
									Content = "Bought queued " .. tostring(kind) .. " (" .. i .. "/" .. needed .. ")\nTotal: " .. boughtTotal .. "/" .. totalRequired,
									Duration = 2,
								})
							else
								Rayfield:Notify({ Title = "Auto Buy", Content = "Purchase was not confirmed for " .. tostring(kind), Duration = 4 })
								break
							end

						else
							Rayfield:Notify({
								Title = "Auto Buy",
								Content =
									"Failed to buy "
									.. tostring(kind)
									.. " ❌"
									.. "\n"
									.. tostring(buyError or ""),
								Duration = 4,
							})

							-- Stop this purchase type if Roblox rejects it
							break
						end

						task.wait(0.5)
					end
				end

				Rayfield:Notify({
					Title = "Auto Buy",
					Content =
						"Finished buying queued houses 🏠"
						.. "\nBought: "
						.. boughtTotal
						.. "/"
						.. totalRequired,
					Duration = 5,
				})
			end)

			autoBuyQueuedRunning = false

			-- One-shot toggle: after this queued-house buy run finishes (or errors),
			-- always return Auto Buy Queued Houses to OFF and persist that state.
			autoBuyQueuedEnabled = false
			if autoBuyQueuedToggle then
				pcall(function() autoBuyQueuedToggle:Set(false) end)
			end
			autoSaveAutoPasteConfig()

			if not ok then
				warn("Queued house auto-buy failed: " .. tostring(err))
			end
		end)
	end

	ownedDropdown = BuyerTab:CreateDropdown({
		Name = "Select Owned House to Sell",
		Options = ownedHouseList,
		CurrentOption = {},
		MultipleOptions = false,
		Callback = function(opt)
			local name = (typeof(opt) == "table") and opt[1] or opt
			selectedHouseId = ownedHouseMap[name] or nil
		end,
	})

	BuyerTab:CreateButton({
		Name = "Sell Selected House",
		Callback = function()
			if not selectedHouseId then
				return Rayfield:Notify({ Title = "Sell", Content = "No house selected ❌", Duration = 3 })
			end
			local sellingId = selectedHouseId
			local ok, err = pcall(function()
				return Router.get("HousingAPI/SellHouse"):InvokeServer(sellingId)
			end)
			if not ok then
				return Rayfield:Notify({ Title = "Sell", Content = "Sell request failed: " .. tostring(err), Duration = 4 })
			end
			if waitUntilHouseGone(sellingId, 8) then
				selectedHouseId = nil
				refreshOwnedHouses()
				Rayfield:Notify({ Title = "Sell", Content = "House sold ✔", Duration = 3 })
			else
				Rayfield:Notify({ Title = "Sell", Content = "Sell was not confirmed by inventory", Duration = 4 })
			end
		end,
	})

	BuyerTab:CreateButton({
		Name = "Buy Selected House (One-Time)",
		Callback = function()
			buyHouse()
		end,
	})

	local autoBuyToggle
	autoBuyToggle = BuyerTab:CreateToggle({
		Name = "Auto Buy",
		Callback = function(v)
			autoBuy = v
			if v then
				if #selectedHouseKinds == 0 then
					autoBuy = false
					pcall(function() autoBuyToggle:Set(false) end)
					return Rayfield:Notify({ Title = "Auto Buy", Content = "No house selected ❌", Duration = 3 })
				end
				task.spawn(function()
					for index = 1, buyAmount do
						if not autoBuy then break end
						local kind = selectedHouseKinds[((index - 1) % #selectedHouseKinds) + 1]
						buyOneHouse(kind)
						task.wait(0.5)
					end
					autoBuy = false
					refreshOwnedHouses()
					pcall(function() autoBuyToggle:Set(false) end)
				end)
			end
		end,
	})

	-- ==================== TRADING TAB ====================
	local tradingRunning = false
	local tradeSelections = {}
	local lastTradeCount = -1

	tradeDropdown = TradeTab:CreateDropdown({
		Name = "Select Houses To Trade",
		Options = ownedHouseList,
		CurrentOption = {},
		MultipleOptions = true,
		Callback = function(opts)
			table.clear(tradeSelections)
			for _, name in ipairs(opts or {}) do
				local id = ownedHouseMap[name]
				if id then tradeSelections[id] = name end
			end
			local selectedCount = 0
			for _ in pairs(tradeSelections) do selectedCount += 1 end
			if selectedCount ~= lastTradeCount then
				lastTradeCount = selectedCount
				Rayfield:Notify({ Title = "Trading", Content = selectedCount .. " houses selected" })
			end
		end,
	})

	local function processTrade()
		if tradingRunning then return end
		tradingRunning = true

		Rayfield:Notify({
			Title = "Trading",
			Content = "Started dynamic queue",
			Duration = 3
		})

		task.spawn(function()
			while tradingRunning do
				refreshOwnedHouses()

				local currentQueue = {}

				for id, _ in pairs(tradeSelections) do
					table.insert(currentQueue, id)
				end

				if #currentQueue == 0 then
					Rayfield:Notify({
						Title = "Trading",
						Content = "Queue finished ✅",
						Duration = 3
					})
					break
				end

				if not tradingRunning then break end
				local id = currentQueue[1]
				local name = tradeSelections[id]
				if not name then
					task.wait()
					continue
				end

				Rayfield:Notify({
					Title = "Trading",
					Content = "Spawning " .. name,
					Duration = 3
				})

				-- 1. Spawn the house first
				local spawnSuccess = pcall(function()
					Router.get("HousingAPI/SpawnHouse"):FireServer(id)
				end)

				if not spawnSuccess then
					Rayfield:Notify({ Title = "Trading", Content = "Failed to spawn " .. name .. " ❌; skipped", Duration = 4 })
					tradeSelections[id] = nil
					task.wait(1)
					continue
				end

				-- 2. Give the server/client time to finish spawning it
				task.wait(5)

				Rayfield:Notify({
					Title = "Trading",
					Content = "Listing " .. name,
					Duration = 3
				})

				-- 3. List the house AFTER the delay
				local listSuccess = pcall(function()
					Router.get("HousingAPI/ListHouse"):InvokeServer(id)
				end)

				if not listSuccess then
					Rayfield:Notify({ Title = "Trading", Content = "Failed to list " .. name .. " ❌; skipped", Duration = 4 })
					tradeSelections[id] = nil
					task.wait(1)
					continue
				end

				-- 4. Wait for the house to disappear / trade
				if waitUntilHouseGone(id, 300, function() return tradingRunning end) then
					Rayfield:Notify({
						Title = "Trading",
						Content = name .. " traded ✔",
						Duration = 3
					})

					tradeSelections[id] = nil
				else
					Rayfield:Notify({ Title = "Trading", Content = name .. " timeout ❌; removed from queue", Duration = 4 })
					tradeSelections[id] = nil
				end

				task.wait(1)
			end

			tradingRunning = false
		end)
	end

	local function isKaliremHouseName(name)
		local lowered = string.lower(tostring(name or ""))
		-- Match every owned house whose name starts with "Kalirem".
		-- This includes Kalirem, Kalirem 1, Kalirem House, etc.
		return lowered:match("^%s*kalirem") ~= nil
	end

	-- Auto Paste Auto Trade uses its own worker state. Do not share
	-- tradingRunning/tradeSelections with the manual Trading tab queue.
	local autoTradeLoopRunning = false
	local autoTradeLoopToken = 0
	local autoTradeWaitingNoticeShown = false
	local autoTradeToggle -- forward declaration so the worker can switch the UI toggle off

	local function getKaliremTradeHouses()
		-- Poll ClientData directly. Do not call refreshOwnedHouses() every second;
		-- that refreshes several Rayfield dropdowns and can cause unnecessary lag.
		local manager = {}
		pcall(function()
			manager = ClientData.get("house_manager") or {}
		end)

		local matches = {}
		for _, house in pairs(manager) do
			local houseName = tostring(house.name or "")
			if house.house_id and isKaliremHouseName(houseName) then
				table.insert(matches, {
					id = house.house_id,
					name = houseName,
				})
			end
		end

		-- Make the order stable. Numbered Kalirem houses are handled in number order,
		-- with the house id as the final tie-breaker.
		table.sort(matches, function(a, b)
			local aNum = tonumber(a.name:match("[Kk][Aa][Ll][Ii][Rr][Ee][Mm]%s*(%d+)"))
			local bNum = tonumber(b.name:match("[Kk][Aa][Ll][Ii][Rr][Ee][Mm]%s*(%d+)"))
			if aNum and bNum and aNum ~= bNum then
				return aNum < bNum
			elseif aNum and not bNum then
				return true
			elseif bNum and not aNum then
				return false
			end

			local aName = string.lower(a.name)
			local bName = string.lower(b.name)
			if aName ~= bName then
				return aName < bName
			end
			return tostring(a.id) < tostring(b.id)
		end)

		return matches
	end

	local function refreshKaliremTradeSelections()
		-- Auto Paste Auto Trade only needs the live count here. Do not touch
		-- tradeSelections because that table belongs to the manual Trading tab.
		return #getKaliremTradeHouses()
	end

	queueKaliremHouses = function()
		return refreshKaliremTradeSelections()
	end

	processAutoList = function()
		-- Only one Auto Paste Auto Trade worker may exist at a time.
		if autoTradeLoopRunning then return end

		autoTradeLoopToken += 1
		local myLoopToken = autoTradeLoopToken
		autoTradeLoopRunning = true
		autoTradeWaitingNoticeShown = false

		task.spawn(function()
			local tradedAnyThisRun = false

			local function autoTradeStillEnabled()
				return autoTradeLoopRunning
					and autoListAfterPaste
					and autoTradeLoopToken == myLoopToken
			end

			while autoTradeStillEnabled() do
				-- Never trade a target while Auto Paste is still editing houses.
				-- Stay alive and begin/resume immediately after Auto Paste finishes.
				if autoPasteRunning then
					task.wait(0.5)
					continue
				end

				-- IMPORTANT: rebuild from house_manager every pass. Never rely on the
				-- old queue because Auto Paste/Auto Buy can create or rename houses
				-- while this worker is already running.
				local matches = getKaliremTradeHouses()

				if #matches == 0 then
					-- Once at least one Kalirem house was successfully traded and none
					-- remain, automatically turn Auto Trade OFF instead of waiting forever.
					if tradedAnyThisRun then
						Rayfield:Notify({
							Title = "Auto Trade",
							Content = "All Kalirem houses were traded - Auto Trade disabled",
							Duration = 4,
						})

						if autoTradeToggle then
							pcall(function() autoTradeToggle:Set(false) end)
						else
							autoListAfterPaste = false
							autoTradeLoopToken += 1
							autoTradeLoopRunning = false
						end
						break
					end

					-- If Auto Trade was enabled before any Kalirem house exists, keep
					-- waiting so Auto Paste/Auto Buy can still create one later.
					if not autoTradeWaitingNoticeShown then
						autoTradeWaitingNoticeShown = true
						Rayfield:Notify({
							Title = "Auto Trade",
							Content = "Waiting for a Kalirem house...",
							Duration = 3,
						})
					end
					task.wait(1)
					continue
				end

				autoTradeWaitingNoticeShown = false
				local entry = matches[1]
				local entryId = entry.id
				local entryName = entry.name

				-- Verify the same house is still owned and still named Kalirem before
				-- doing anything with it.
				local currentHouse = getOwnedHouseById(entryId)
				if not currentHouse or not isKaliremHouseName(currentHouse.name) then
					task.wait(0.25)
					continue
				end

				Rayfield:Notify({
					Title = "Auto Trade",
					Content = "Spawning " .. entryName,
					Duration = 3,
				})

				-- Retry SpawnHouse until it succeeds, the house disappears/gets renamed,
				-- or Auto Trade is switched off.
				local spawned = false
				while autoTradeStillEnabled() and not spawned do
					currentHouse = getOwnedHouseById(entryId)
					if not currentHouse or not isKaliremHouseName(currentHouse.name) then
						break
					end

					spawned = pcall(function()
						Router.get("HousingAPI/SpawnHouse"):FireServer(entryId)
					end)

					if not spawned then
						task.wait(1)
					end
				end

				if not autoTradeStillEnabled() then break end

				currentHouse = getOwnedHouseById(entryId)
				if not currentHouse or not isKaliremHouseName(currentHouse.name) then
					task.wait(0.25)
					continue
				end

				-- Give the spawned house time to become the active house.
				task.wait(4)

				if not autoTradeStillEnabled() then break end
				currentHouse = getOwnedHouseById(entryId)
				if not currentHouse or not isKaliremHouseName(currentHouse.name) then
					continue
				end

				Rayfield:Notify({
					Title = "Auto Trade",
					Content = "Listing " .. entryName .. " and waiting for trade...",
					Duration = 4,
				})

				-- Keep the SAME Kalirem house listed until it leaves house_manager.
				-- We intentionally do not depend on listed_for_trade because that field
				-- is not reliable on every client version. Re-sending ListHouse every
				-- few seconds also recovers from a silently rejected/late list request.
				local lastListAttempt = 0
				while autoTradeStillEnabled() do
					currentHouse = getOwnedHouseById(entryId)
					if not currentHouse then
						tradedAnyThisRun = true
						Rayfield:Notify({
							Title = "Auto Trade",
							Content = entryName .. " traded ✔",
							Duration = 3,
						})
						-- Update the visible owned-house dropdowns once per completed trade.
						pcall(refreshOwnedHouses)
						break
					end

					-- If something renamed this house away from Kalirem, stop handling
					-- this one and immediately rescan the owned houses.
					if not isKaliremHouseName(currentHouse.name) then
						break
					end

					if tick() - lastListAttempt >= 4 then
						lastListAttempt = tick()
						pcall(function()
							Router.get("HousingAPI/ListHouse"):InvokeServer(entryId)
						end)
					end

					task.wait(0.5)
				end

				-- Immediately loop back and rescan. If another Kalirem house exists,
				-- it becomes the next trade automatically.
				task.wait(0.5)
			end

			-- Do not let an old worker overwrite the state of a newer worker.
			if autoTradeLoopToken == myLoopToken then
				autoTradeLoopRunning = false
				autoTradeWaitingNoticeShown = false
			end
		end)
	end



	autoTradeToggle = AutoPasteTab:CreateToggle({
		Name = "Auto Trade",
		CurrentValue = false,
		Callback = function(value)
			autoListAfterPaste = value

			if value then
				local selectedCount = queueKaliremHouses()

				if selectedCount > 0 then
					Rayfield:Notify({
						Title = "Auto Trade",
						Content = "Loop started - found " .. selectedCount .. " Kalirem house(s)",
						Duration = 3,
					})
				else
					Rayfield:Notify({
						Title = "Auto Trade",
						Content = "Loop started - waiting for a Kalirem house",
						Duration = 3,
					})
				end

				-- Start now even while Auto Paste is still running. The worker will
				-- continuously detect Kalirem houses as they appear.
				processAutoList()
			else
				-- Stop only the Auto Paste Auto Trade worker. Invalidate the current
				-- token too, so a quick OFF -> ON cannot revive the old task.
				autoTradeLoopToken += 1
				autoTradeLoopRunning = false
				autoTradeWaitingNoticeShown = false
			end
		end,
	})

	TradeTab:CreateButton({ Name = "Start Trading Queue", Callback = processTrade })

	TradeTab:CreateButton({
		Name = "Clear Queue",
		Callback = function()
			tradingRunning = false
			table.clear(tradeSelections)
			lastTradeCount = 0
			pcall(function()
				if tradeDropdown then tradeDropdown:Set({}) end
			end)
			Rayfield:Notify({ Title = "Trading", Content = "Queue cleared & stopped 🛑" })
		end,
	})

	-- ==================== HELPER FUNCTIONS ====================
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

	local function getCurrentInteriorModel()
		for _, v in pairs(workspace:GetChildren()) do
			if v.Name:lower():find("interior") and v:IsA("Model") and v.PrimaryPart then
				return v
			end
		end
		return nil
	end

	local function _toRelativeCFrame(worldCf)
		local interior = getCurrentInteriorModel()
		if interior and interior.PrimaryPart then
			return interior.PrimaryPart.CFrame:ToObjectSpace(worldCf)
		end
		return worldCf
	end

	local function _toWorldCFrame(relativeCf)
		local interior = getCurrentInteriorModel()
		if interior and interior.PrimaryPart then
			return interior.PrimaryPart.CFrame:ToWorldSpace(relativeCf)
		end
		return relativeCf
	end

	local function deepCopy(tbl)
		if type(tbl) ~= "table" then return tbl end
		local t = {}
		for k, v in pairs(tbl) do t[k] = deepCopy(v) end
		return t
	end

	-- ==================== MAIN TAB ====================
	Tab:CreateLabel(
		"If you are using glitch houses, use the slow paste. And if you are using normal houses, use the fast paste. If you use it on higher builds expect lagging or crashing.",
		"info"
	)
	Tab:CreateLabel("Do not Touch", "info")

	Pastetextures = Tab:CreateToggle({
		Name = "Paste textures",
		CurrentValue = true,
		Flag = "Pastetextures",
		Callback = function(_) end,
	})
	IgnoreTypeCheck = Tab:CreateToggle({
		Name = "Ignore House Type",
		CurrentValue = false,
		Flag = "IgnoreType",
		Callback = function(_) end,
	})

	Tab:CreateSection("Slow Paste Settings")
	local batch_size = 10
	local delay_seconds = 1

	Tab:CreateInput({
		Name = "Batch Size (items per batch)",
		PlaceholderText = "10",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			batch_size = math.clamp(math.floor(tonumber(value) or 10), 1, 100)
		end,
	})

	Tab:CreateInput({
		Name = "Delay (seconds between batches)",
		PlaceholderText = "1",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			delay_seconds = math.clamp(tonumber(value) or 1, 0.05, 10)
		end,
	})

	Tab:CreateSection("Main Function")

	-- Furniture/texture helpers
	local function canbuyfurniture(kind)
		local db_entry = furnituresdb[kind]
		if not db_entry or not db_entry.cost or db_entry.off_sale then
			return false, false
		end
		local success, player_data = pcall(function()
			return cd.get_data()[plr.Name]
		end)
		if not success or not player_data then
			return false, false
		end
		return db_entry.cost <= (player_data.money or 0), true
	end

	local function getPlayerMoney()
		local ok, playerData = pcall(function() return cd.get_data()[plr.Name] end)
		if not ok or not playerData then return nil end
		return tonumber(playerData.money) or 0
	end

	local function getFurnitureRequestsCost(requests)
		local total = 0
		for _, request in ipairs(requests or {}) do
			local db = furnituresdb[request.kind]
			if db and db.cost then total += db.cost end
		end
		return total
	end

	local function canAffordFurnitureRequests(requests)
		local money = getPlayerMoney()
		if money == nil then return false, 0, 0 end
		local cost = getFurnitureRequestsCost(requests)
		return money >= cost, cost, money
	end

	local function notifyUnavailableFurniture(items)
		if #items == 0 then return end
		local names = {}
		for _, kind in ipairs(items) do
			if not table.find(names, kind) then
				table.insert(names, kind)
			end
		end
		local content = "Skipped " .. #items .. " unavailable furniture item(s). Auto Paste will continue and remove the completed house from the queue."
		if #names <= 3 then
			content = content .. "\n" .. table.concat(names, ", ")
		else
			content = content .. "\n" .. names[1] .. ", " .. names[2] .. ", " .. names[3] .. ", ..."
		end
		Rayfield:Notify({
			Title = "Unavailable Furniture",
			Content = content,
			Duration = 8,
		})
	end

	local function textureexists(room, texturetype, texture)
		if texture == "tile" then return true end
		local success, textures = pcall(function()
			return cd.get("house_interior").textures
		end)
		if not success or not textures then return false end
		for i, v in pairs(textures) do
			if i == room and v[texturetype] == texture then return true end
		end
		return false
	end

	local function buytexturewithretry(room, texturetype, texture, tries)
		tries = tries or 0
		if stopFlag then return false end
		if textureexists(room, texturetype, texture) then return true end
		if tries >= 10 then
			warn("Failed to buy texture:", texture)
			return false
		end
		local ok = pcall(function()
			router.get("HousingAPI/BuyTexture"):FireServer(room, texturetype, texture)
		end)
		if not ok then return false end
		task.wait(0.2)
		return textureexists(room, texturetype, texture) or buytexturewithretry(room, texturetype, texture, tries + 1)
	end

	local max_retries = 3

	local function applyRequestedOutfits(requests)
		if type(requests) ~= "table" then return true end

		-- Outfit data is not applied by BuyFurnitures itself. We must wait for the
		-- newly-created furniture to appear in house_interior, match each request to
		-- its mannequin, then use the normal mannequin edit/save flow.
		local outfitRequests = {}
		for _, request in ipairs(requests) do
			local properties = request.properties or {}
			if properties.outfit ~= nil then
				table.insert(outfitRequests, request)
			end
		end
		if #outfitRequests == 0 then return true end

		local character = plr.Character
		if not character then
			local ok, result = pcall(function()
				return plr.CharacterAdded:Wait()
			end)
			if ok then character = result end
		end

		local usedFurniture = {}
		local applied = 0

		for requestIndex, request in ipairs(outfitRequests) do
			if stopFlag then return false end

			local properties = request.properties or {}
			local matchedId = nil
			local matchedDistance = math.huge

			-- ClientData can lag behind BuyFurnitures for a moment. Retry the lookup
			-- instead of doing a single scan and silently skipping the outfit.
			local lookupStarted = tick()
			repeat
				local success, interior = pcall(function()
					return cd.get("house_interior")
				end)

				if success and interior and interior.furniture then
					local fallbackId = nil
					for furnitureId, furniture in pairs(interior.furniture) do
						if not usedFurniture[furnitureId] and furniture.id == request.kind then
							fallbackId = fallbackId or furnitureId
							local distance = math.huge
							if typeof(furniture.cframe) == "CFrame" and typeof(properties.cframe) == "CFrame" then
								distance = (furniture.cframe.Position - properties.cframe.Position).Magnitude
							end
							if distance < matchedDistance then
								matchedDistance = distance
								matchedId = furnitureId
							end
						end
					end

					-- If CFrames are unavailable/different after server normalization, still
					-- use an unused furniture instance of the exact same kind.
					if not matchedId then matchedId = fallbackId end
				end

				if not matchedId then task.wait(0.25) end
			until matchedId or tick() - lookupStarted >= 5

			if not matchedId then
				warn("[Cubix Outfit] Could not find pasted mannequin for", request.kind, "request", requestIndex)
			else
				usedFurniture[matchedId] = true
				local saved = false
				local lastErr = nil

				for attempt = 1, 3 do
					if stopFlag then return false end

					local editOk, editResult = pcall(function()
						return router.get("AvatarAPI/StartEditingMannequin"):InvokeServer(properties.outfit)
					end)
					if not editOk then
						lastErr = "StartEditingMannequin: " .. tostring(editResult)
					else
						-- Give the edit state a moment to reach the server before saving it to
						-- the furniture. Calling both remotes back-to-back was unreliable.
						task.wait(0.2)
						local saveOk, saveResult = pcall(function()
							return router.get("HousingAPI/ActivateFurniture"):InvokeServer(
								plr,
								matchedId,
								"UseBlock",
								{ save_outfit = true, outfit_name = properties.outfit_name or "Outfit" },
								character or plr.Character
							)
						end)
						if saveOk then
							saved = true
							break
						else
							lastErr = "ActivateFurniture: " .. tostring(saveResult)
						end
					end

					task.wait(0.35)
				end

				if saved then
					applied += 1
				else
					warn("[Cubix Outfit] Failed to apply outfit to", request.kind, "-", tostring(lastErr))
				end
			end
		end

		if applied < #outfitRequests then
			Rayfield:Notify({
				Title = "Outfits",
				Content = "Applied " .. applied .. "/" .. #outfitRequests .. " mannequin outfit(s). Check console for failed ones.",
				Duration = 5,
			})
		end

		return applied == #outfitRequests
	end

	local function placeFurnitures(furnList, isFix)
		local totalfurnitures = #furnList
		if totalfurnitures == 0 then return true end
		updateprog("0/" .. totalfurnitures)

		local batches, currentBatch = {}, {}
		for _, item in ipairs(furnList) do
			table.insert(currentBatch, item)
			if #currentBatch >= batch_size then
				table.insert(batches, currentBatch)
				currentBatch = {}
			end
		end
		if #currentBatch > 0 then table.insert(batches, currentBatch) end

		local placed = 0
		local allSuccessful = true
		updatestatus(isFix and "Fixing Missing Items" or "Pasting Furniture (Slow)")

		for batchIndex, batch in ipairs(batches) do
			if stopFlag then return false end
			for _, item in ipairs(batch) do
				updateitem((isFix and "Fixing: " or "Placing: ") .. (item.kind or "Unknown"))
				local normalized = {}
				for colorIndex, color in pairs((item.properties and item.properties.colors) or {}) do
					if typeof(color) == "Color3" then
						normalized[colorIndex] = color
					elseif type(color) == "table" then
						normalized[colorIndex] = Color3.new(color[1] or color.R or color.r or 1, color[2] or color.G or color.g or 1, color[3] or color.B or color.b or 1)
					end
				end
				item.properties.colors = normalized
			end

			local beforeOk, beforeCount = pcall(function() return countfurnitures(cd.get("house_interior").furniture) end)
			if not beforeOk then return false end

			local invokeOk, invokeErr = pcall(function()
				return router.get("HousingAPI/BuyFurnitures"):InvokeServer(batch)
			end)
			if not invokeOk then
				allSuccessful = false
				warn("Furniture batch invoke failed:", invokeErr)
			else
				-- Never re-send a partially successful batch: that can duplicate furniture.
				local confirmed = false
				local started = tick()
				while tick() - started < math.max(4, delay_seconds + 3) do
					if stopFlag then return false end
					local afterOk, afterCount = pcall(function() return countfurnitures(cd.get("house_interior").furniture) end)
					if afterOk and afterCount - beforeCount >= #batch then
						confirmed = true
						break
					end
					task.wait(0.4)
				end
				if confirmed then
					placed += #batch
				else
					allSuccessful = false
					Rayfield:Notify({ Title = "Warning", Content = "Batch " .. batchIndex .. " was not fully confirmed. It will not be resent to avoid duplicates.", Duration = 6, Image = "circle-alert" })
				end
			end
			updateprog(placed .. "/" .. totalfurnitures)
			task.wait(delay_seconds)
		end
		return allSuccessful
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
			local furniturecost = 0
			for _, v in pairs(savedhouse.furniture or {}) do
				local db_entry = furnituresdb[v.id]
				if db_entry and db_entry.cost then furniturecost += db_entry.cost end
			end
			local texturecost = 0
			for _, v in pairs(savedhouse.textures or {}) do
				if v.walls and texturesdb.walls[v.walls] and texturesdb.walls[v.walls].cost then
					texturecost += texturesdb.walls[v.walls].cost
				end
				if v.floors and texturesdb.floors[v.floors] and texturesdb.floors[v.floors].cost then
					texturecost += texturesdb.floors[v.floors].cost
				end
			end
			local t_count = counttextures(savedhouse.textures)
			local amb = savedhouse.ambiance and "Yes" or "No"
			local typ = "-"
			pcall(function() typ = savedhouse.building_type or "-" end)
			task.spawn(setscaninfo, countfurnitures(savedhouse.furniture), furniturecost, t_count, texturecost, amb, typ)
			Rayfield:Notify({ Title = "Success", Content = "Scanned house", Duration = 3, Image = "circle-check" })
			updatestatus("Idle")
		end,
	})

	Tab:CreateButton({
		Name = "Sell All Furnitures",
		Callback = function()
			stopFlag = false
			updatestatus("Clearing House")
			local cleared, err = clearCurrentHouseFurniture(15)
			if cleared then
				Rayfield:Notify({ Title = "Success", Content = "House cleared successfully!", Duration = 3, Image = "circle-check" })
			else
				Rayfield:Notify({ Title = "Error", Content = "House clear failed: " .. tostring(err), Duration = 4, Image = "circle-alert" })
			end
			updatestatus("Idle")
		end,
	})

	Tab:CreateSection("Paste Functions")

	-- ==================== PASTE FAST (assigned to upvalue) ====================
	pastehousefast = function(houseData)
		local houseToPaste = houseData or savedhouse
		if not houseToPaste or not houseToPaste.furniture then
			Rayfield:Notify({ Title = "Error", Content = "No house has been saved", Duration = 3, Image = "circle-alert" })
			return false
		end
		Rayfield:Notify({ Title = "Loading", Content = "Pasting furnitures...", Duration = 3, Image = "loader" })
		updatestatus("Pasting Furniture")

		local validFurniture = {}
		local totalfurnitures = 0
		for i, v in pairs(houseToPaste.furniture) do
			if v.id == "lures_2023_cozy_home_lure" then
				warn("[SKIP] Skipping lure item:", v.id)
				continue
			end
			if type(v.cframe) == "table" then
				local ok, cf = pcall(function() return CFrame.new(table.unpack(v.cframe)) end)
				if ok and cf then v.cframe = cf
				else warn("[SKIP] Could not convert cframe for:", v.id) continue end
			end
			if typeof(v.cframe) == "CFrame" then
				validFurniture[i] = v
				totalfurnitures += 1
			else
				warn("[SKIP] Missing or invalid cframe for:", v.id)
			end
		end

		updateprog("0/" .. totalfurnitures)
		updateitem("-")

		local processedCount = 0
		local furniturest = {}
		local unavailableFurniture = {}

		for i, v in pairs(validFurniture) do
			if stopFlag then break end
			local canbuy, exists = canbuyfurniture(v.id)
			if not canbuy and exists == true then
				updatestatus("Idle") updateprog("-") updateitem("-")
				Rayfield:Notify({ Title = "Error", Content = "Insufficient funds for furniture: " .. v.id, Duration = 3, Image = "circle-alert" })
				return false
			elseif not canbuy and exists == false then
				table.insert(unavailableFurniture, v.id)
				processedCount += 1
				updateprog(processedCount .. "/" .. totalfurnitures)
				continue
			end
			local normalizedColors = {}
			for ci, col in pairs(v.colors or {}) do
				if typeof(col) == "Color3" then
					normalizedColors[ci] = col
				elseif type(col) == "table" then
					normalizedColors[ci] = Color3.new(
						col[1] or col.R or col.r or 1,
						col[2] or col.G or col.g or 1,
						col[3] or col.B or col.b or 1
					)
				end
			end
			table.insert(furniturest, {
				kind = v.id,
				properties = {
					colors = normalizedColors,
					cframe = v.cframe,
					scale = v.scale,
					outfit = v.outfit,
					outfit_name = v.outfit_name,
				},
			})
			processedCount += 1
			updateprog(processedCount .. "/" .. totalfurnitures)
			updateitem(v.id)
		end

		notifyUnavailableFurniture(unavailableFurniture)

		if stopFlag then
			updatestatus("Stopped") updateprog("-") updateitem("-")
			return false
		end

		if #furniturest > 0 then
			local affordable, requiredCost, availableMoney = canAffordFurnitureRequests(furniturest)
			if not affordable then
				Rayfield:Notify({ Title = "Error", Content = "Not enough money for this paste. Need $" .. requiredCost .. ", have $" .. availableMoney, Duration = 5, Image = "circle-alert" })
				updatestatus("Idle") updateprog("-") updateitem("-")
				return false
			end
			local beforeOk, beforeCount = pcall(function() return countfurnitures(cd.get("house_interior").furniture) end)
			if not beforeOk then return false end
			local invokeOk, invokeErr = pcall(function()
				return router.get("HousingAPI/BuyFurnitures"):InvokeServer(furniturest)
			end)
			if not invokeOk then
				warn("BuyFurnitures failed:", invokeErr)
				return false
			end
			local confirmed = false
			local started = tick()
			while tick() - started < 6 do
				if stopFlag then return false end
				local afterOk, afterCount = pcall(function() return countfurnitures(cd.get("house_interior").furniture) end)
				if afterOk and afterCount - beforeCount >= #furniturest then confirmed = true break end
				task.wait(0.35)
			end
			if not confirmed then
				Rayfield:Notify({ Title = "Error", Content = "Furniture paste was not fully confirmed", Duration = 5, Image = "circle-alert" })
				return false
			end
			applyRequestedOutfits(furniturest)
		end

		-- Activate furniture
		local success, interior = pcall(function() return cd.get("house_interior") end)
		if success and interior and interior.furniture then
			for i, v in pairs(interior.furniture) do
				if stopFlag then break end
				if v.text then
					pcall(function()
						router.get("HousingAPI/ActivateFurniture"):InvokeServer(plr, i, "UseBlock", v.text, plr.Character)
					end)
				end
			end
		end

		-- Apply textures
		local texturesSuccessful = true
		if houseToPaste.textures and Pastetextures.CurrentValue then
			updatestatus("Pasting Textures")
			updateprog("-")
			for roomId, textureData in pairs(houseToPaste.textures) do
				if stopFlag then break end
				if textureData.floors and not textureexists(roomId, "floors", textureData.floors) then
					updateitem(roomId .. " floors: " .. textureData.floors)
					if not buytexturewithretry(roomId, "floors", textureData.floors) then texturesSuccessful = false end
				end
				if stopFlag then break end
				if textureData.walls and not textureexists(roomId, "walls", textureData.walls) then
					updateitem(roomId .. " walls: " .. textureData.walls)
					if not buytexturewithretry(roomId, "walls", textureData.walls) then texturesSuccessful = false end
				end
				task.wait()
			end
		end

		if houseToPaste.ambiance then
			pcall(function() router.get("AmbianceAPI/UpdateAmbiance"):FireServer(houseToPaste.ambiance) end)
		end
		if houseToPaste.music then
			pcall(function()
				router.get("RadioAPI/Play"):FireServer(houseToPaste.music.name, houseToPaste.music.id)
				if not houseToPaste.music.playing then
					router.get("RadioAPI/Pause"):InvokeServer()
				end
			end)
		end

		if not texturesSuccessful then
			-- Unavailable/failed textures are non-fatal. Keep the furniture that was
			-- successfully pasted and let Auto Paste remove this file from the queue.
			Rayfield:Notify({ Title = "Warning", Content = "Paste completed. Unavailable/failed textures were skipped.", Duration = 5, Image = "circle-alert" })
			updatestatus("Idle") updateprog("-") updateitem("-")
			return true
		end
		Rayfield:Notify({ Title = "Success", Content = "House Placed successfully!", Duration = 3, Image = "circle-check" })
		updatestatus("Idle")
		updateprog("-")
		updateitem("-")
		return true
	end

	-- ==================== PASTE SLOW (assigned to upvalue) ====================
	pastehouseslow = function(houseData)
		local houseToPaste = houseData or savedhouse
		if not houseToPaste or not houseToPaste.furniture then
			Rayfield:Notify({ Title = "Error", Content = "No house has been saved", Duration = 3, Image = "circle-alert" })
			return false
		end
		Rayfield:Notify({ Title = "Loading", Content = "Pasting furnitures slowly...", Duration = 3, Image = "loader" })
		updatestatus("Pasting Furniture (Slow)")

		local validFurniture = {}
		local totalfurnitures = 0
		for i, v in pairs(houseToPaste.furniture) do
			if v.id == "lures_2023_cozy_home_lure" then
				warn("[SKIP] Skipping lure item:", v.id)
				continue
			end
			if type(v.cframe) == "table" then
				local ok, cf = pcall(function() return CFrame.new(table.unpack(v.cframe)) end)
				if ok and cf then v.cframe = cf
				else warn("[SKIP] Could not convert cframe for:", v.id) continue end
			end
			if typeof(v.cframe) == "CFrame" then
				validFurniture[i] = v
				totalfurnitures += 1
			else
				warn("[SKIP] Missing or invalid cframe for:", v.id)
			end
		end

		updateprog("0/" .. totalfurnitures)
		updateitem("-")

		local processedCount = 0
		local furniturest = {}
		local unavailableFurniture = {}

		for i, v in pairs(validFurniture) do
			if stopFlag then break end
			local canbuy, exists = canbuyfurniture(v.id)
			if not canbuy and exists == true then
				updatestatus("Idle") updateprog("-") updateitem("-")
				Rayfield:Notify({ Title = "Error", Content = "Insufficient funds for furniture: " .. v.id, Duration = 3, Image = "circle-alert" })
				return false
			elseif not canbuy and exists == false then
				table.insert(unavailableFurniture, v.id)
				processedCount += 1
				updateprog(processedCount .. "/" .. totalfurnitures)
				continue
			end
			local normalizedColors = {}
			for ci, col in pairs(v.colors or {}) do
				if typeof(col) == "Color3" then
					normalizedColors[ci] = col
				elseif type(col) == "table" then
					normalizedColors[ci] = Color3.new(
						col[1] or col.R or col.r or 1,
						col[2] or col.G or col.g or 1,
						col[3] or col.B or col.b or 1
					)
				end
			end
			table.insert(furniturest, {
				kind = v.id,
				properties = {
					colors = normalizedColors,
					cframe = v.cframe,
					scale = v.scale,
					outfit = v.outfit,
					outfit_name = v.outfit_name,
				},
			})
			processedCount += 1
			updateprog(processedCount .. "/" .. totalfurnitures)
			updateitem(v.id)
		end

		notifyUnavailableFurniture(unavailableFurniture)

		if stopFlag then
			updatestatus("Stopped") updateprog("-") updateitem("-")
			return false
		end

		if #furniturest > 0 then
			local affordable, requiredCost, availableMoney = canAffordFurnitureRequests(furniturest)
			if not affordable then
				Rayfield:Notify({ Title = "Error", Content = "Not enough money for this paste. Need $" .. requiredCost .. ", have $" .. availableMoney, Duration = 5, Image = "circle-alert" })
				return false
			end
			if not placeFurnitures(furniturest, false) then return false end
			task.wait(1)
			applyRequestedOutfits(furniturest)
		end

		if stopFlag then
			updatestatus("Stopped") updateprog("-") updateitem("-")
			return false
		end

		-- Activate furniture
		local success, interior = pcall(function() return cd.get("house_interior") end)
		if success and interior and interior.furniture then
			for i, v in pairs(interior.furniture) do
				if stopFlag then break end
				if v.text then
					pcall(function()
						router.get("HousingAPI/ActivateFurniture"):InvokeServer(plr, i, "UseBlock", v.text, plr.Character)
					end)
				end
			end
		end

		-- Apply textures
		local texturesSuccessful = true
		if houseToPaste.textures and Pastetextures.CurrentValue then
			updatestatus("Pasting Textures")
			updateprog("-")
			for roomId, textureData in pairs(houseToPaste.textures) do
				if stopFlag then break end
				if textureData.floors and not textureexists(roomId, "floors", textureData.floors) then
					updateitem(roomId .. " floors: " .. textureData.floors)
					if not buytexturewithretry(roomId, "floors", textureData.floors) then texturesSuccessful = false end
				end
				if stopFlag then break end
				if textureData.walls and not textureexists(roomId, "walls", textureData.walls) then
					updateitem(roomId .. " walls: " .. textureData.walls)
					if not buytexturewithretry(roomId, "walls", textureData.walls) then texturesSuccessful = false end
				end
				task.wait()
			end
		end

		if houseToPaste.ambiance then
			pcall(function() router.get("AmbianceAPI/UpdateAmbiance"):FireServer(houseToPaste.ambiance) end)
		end
		if houseToPaste.music then
			pcall(function()
				router.get("RadioAPI/Play"):FireServer(houseToPaste.music.name, houseToPaste.music.id)
				if not houseToPaste.music.playing then
					router.get("RadioAPI/Pause"):InvokeServer()
				end
			end)
		end

		if not texturesSuccessful then
			-- Unavailable/failed textures are non-fatal. Keep the furniture that was
			-- successfully pasted and let Auto Paste remove this file from the queue.
			Rayfield:Notify({ Title = "Warning", Content = "Paste completed. Unavailable/failed textures were skipped.", Duration = 5, Image = "circle-alert" })
			updatestatus("Idle") updateprog("-") updateitem("-")
			return true
		end
		Rayfield:Notify({ Title = "Success", Content = "House Placed successfully! (Slow mode)", Duration = 3, Image = "circle-check" })
		updatestatus("Idle")
		updateprog("-")
		updateitem("-")
		return true
	end

	local function colorValueToTuple(value)
		if typeof(value) == "Color3" then return value.R, value.G, value.B end
		if type(value) == "table" then return value[1] or value.R or value.r, value[2] or value.G or value.g, value[3] or value.B or value.b end
		return nil
	end

	local function colorsEqual(a, b)
		a, b = a or {}, b or {}
		local bByKey, countA, countB = {}, 0, 0
		for k, v in pairs(b) do bByKey[tostring(k)] = v countB += 1 end
		for k, av in pairs(a) do
			countA += 1
			local bv = bByKey[tostring(k)]
			if bv == nil then return false end
			local ar, ag, ab = colorValueToTuple(av)
			local br, bg, bb = colorValueToTuple(bv)
			if not ar or not br or math.abs(ar - br) > 0.001 or math.abs(ag - bg) > 0.001 or math.abs(ab - bb) > 0.001 then return false end
		end
		return countA == countB
	end

	local function cframesClose(a, b)
		if typeof(a) ~= "CFrame" or typeof(b) ~= "CFrame" then return a == b end
		local ac, bc = { a:GetComponents() }, { b:GetComponents() }
		for i = 1, 12 do if math.abs(ac[i] - bc[i]) > 0.002 then return false end end
		return true
	end

	-- ==================== FIX MISSING ====================
	local function fixMissing()
		stopFlag = false
		if not savedhouse then
			return Rayfield:Notify({ Title = "Error", Content = "No house has been saved", Duration = 3, Image = "circle-alert" })
		end
		local house_success, houseInterior = pcall(function() return cd.get("house_interior") end)
		if not house_success or not houseInterior or houseInterior.player ~= plr then
			return Rayfield:Notify({ Title = "Error", Content = "Please enter your house", Duration = 3, Image = "circle-alert" })
		end
		updatestatus("Checking Missing Items")
		local currentFurn = houseInterior.furniture or {}
		local missing = {}
		local skipped = 0
		for _, savedItem in pairs(savedhouse.furniture or {}) do
			if stopFlag then break end
			local found = false
			for _, currItem in pairs(currentFurn) do
				if currItem.id == savedItem.id
					and cframesClose(currItem.cframe, savedItem.cframe)
					and (currItem.scale == savedItem.scale or (not currItem.scale and not savedItem.scale))
					and colorsEqual(currItem.colors, savedItem.colors)
				then
					found = true
					break
				end
			end
			if not found then
				local canbuy, exists = canbuyfurniture(savedItem.id)
				if canbuy then
					table.insert(missing, {
						kind = savedItem.id,
						properties = {
							colors = savedItem.colors,
							cframe = savedItem.cframe,
							scale = savedItem.scale,
							outfit = savedItem.outfit,
							outfit_name = savedItem.outfit_name,
						},
					})
				else
					skipped += 1
					if exists then
						Rayfield:Notify({ Title = "Warning", Content = "Insufficient funds for: " .. savedItem.id, Duration = 3, Image = "circle-alert" })
					else
						Rayfield:Notify({ Title = "Warning", Content = savedItem.id .. " is off-sale or invalid", Duration = 3, Image = "circle-alert" })
					end
				end
			end
		end
		if #missing == 0 then
			Rayfield:Notify({ Title = "Info", Content = "No missing items found (or all skipped). Skipped: " .. skipped, Duration = 5, Image = "info" })
			updatestatus("Idle") updateprog("-") updateitem("-")
			return
		end
		local affordable, requiredCost, availableMoney = canAffordFurnitureRequests(missing)
		if not affordable then
			updatestatus("Idle") updateprog("-") updateitem("-")
			return Rayfield:Notify({ Title = "Error", Content = "Not enough money to fix missing items. Need $" .. requiredCost .. ", have $" .. availableMoney, Duration = 5, Image = "circle-alert" })
		end
		Rayfield:Notify({ Title = "Fixing", Content = "Attempting to place " .. #missing .. " missing items...", Duration = 5, Image = "loader" })
		if not placeFurnitures(missing, true) then
			updatestatus("Idle") updateprog("-") updateitem("-")
			return Rayfield:Notify({ Title = "Warning", Content = "Some missing items were not confirmed; no batch was resent to avoid duplicates.", Duration = 6, Image = "circle-alert" })
		end
		task.wait(1)
		applyRequestedOutfits(missing)
		if stopFlag then
			updatestatus("Stopped") updateprog("-") updateitem("-")
			return false
		end
		local success, interior = pcall(function() return cd.get("house_interior") end)
		if success and interior and interior.furniture then
			for i, v in pairs(interior.furniture) do
				if stopFlag then break end
				if v.text then
					pcall(function()
						router.get("HousingAPI/ActivateFurniture"):InvokeServer(plr, i, "UseBlock", v.text, plr.Character)
					end)
				end
			end
		end
		Rayfield:Notify({ Title = "Success", Content = "Fix attempt completed!", Duration = 3, Image = "circle-check" })
		updatestatus("Idle") updateprog("-") updateitem("-")
	end

	-- ==================== PASTE INIT ====================
	local manualPasteRunning = false
	local function pastehouseinit(mode)
		if manualPasteRunning then
			return Rayfield:Notify({ Title = "Paste", Content = "A manual paste is already running", Duration = 3, Image = "circle-alert" })
		end
		stopFlag = false
		if not savedhouse then
			return Rayfield:Notify({ Title = "Error", Content = "No house has been saved", Duration = 3, Image = "circle-alert" })
		end
		local success, houseInterior = pcall(function() return cd.get("house_interior") end)
		if not success or not houseInterior or not houseInterior.player or houseInterior.player ~= plr then
			return Rayfield:Notify({ Title = "Error", Content = "Please enter your house to paste the house", Duration = 3, Image = "circle-alert" })
		end

		local resolvedSaved = getSavedHouseExactType(savedhouse)
		local resolvedCurrent = getInteriorExactType(houseInterior)
		if not IgnoreTypeCheck.CurrentValue and not isExactSameHouseType(resolvedSaved, resolvedCurrent) then
			return Rayfield:Notify({
				Title = "Error",
				Content = "House types do not match!\nSaved: " .. tostring(getExactHouseDisplayName(resolvedSaved)) .. "\nCurrent: " .. tostring(getExactHouseDisplayName(resolvedCurrent)) .. "\n\nEnable 'Ignore House Type' to force paste.",
				Duration = 6, Image = "circle-alert",
			})
		end

		local houseSnapshot = savedhouse
		manualPasteRunning = true
		task.spawn(function()
			local ok, result = pcall(function()
				Rayfield:Notify({ Title = "Loading", Content = "Clearing house", Duration = 3, Image = "loader" })
				updatestatus("Clearing House")
				local cleared, clearErr = clearCurrentHouseFurniture(15)
				if not cleared then
					if stopFlag then return false end
					error(clearErr or "Could not clear house")
				end
				if stopFlag then return false end
				return (mode == "slow") and pastehouseslow(houseSnapshot) or pastehousefast(houseSnapshot)
			end)
			manualPasteRunning = false
			if not ok then
				updatestatus("Idle") updateprog("-") updateitem("-")
				Rayfield:Notify({ Title = "Paste Error", Content = tostring(result), Duration = 5, Image = "circle-alert" })
			end
		end)
	end

	Tab:CreateButton({ Name = "Place House Fast", Callback = function() pastehouseinit("fast") end })
	Tab:CreateButton({ Name = "Place House Slow", Callback = function() pastehouseinit("slow") end })
	Tab:CreateButton({ Name = "Fix Missing Items", Callback = fixMissing })

	Tab:CreateButton({
		Name = "Stop All",
		Callback = function()
			stopFlag = true
			autoPasteRunning = false
			updatestatus("Stopped") updateprog("-") updateitem("-")
			Rayfield:Notify({ Title = "Stopped", Content = "All processes stopped", Duration = 3, Image = "circle-check" })
		end,
	})

	Tab:CreateSection("Trade Functions")

	Tab:CreateButton({
		Name = "List House for Trade",
		Callback = function()
			local success, house = pcall(function() return cd.get("house_interior") end)
			if not success or not house then
				return Rayfield:Notify({ Title = "Error", Content = "Failed to access house data", Duration = 3, Image = "circle-alert" })
			end
			local listOk, listErr = pcall(function() return router.get("HousingAPI/ListHouse"):InvokeServer() end)
			if not listOk then
				return Rayfield:Notify({ Title = "Trade", Content = "List request failed: " .. tostring(listErr), Duration = 4, Image = "circle-alert" })
			end
			Rayfield:Notify({ Title = "Trade", Content = "List request sent.", Duration = 3, Image = "circle-check" })
		end,
	})

	Tab:CreateButton({
		Name = "Unlist House for Trade",
		Callback = function()
			local success, house = pcall(function() return cd.get("house_interior") end)
			if not success or not house then
				return Rayfield:Notify({ Title = "Error", Content = "Failed to access house data", Duration = 3, Image = "circle-alert" })
			end
			local unlistOk, unlistErr = pcall(function() return router.get("HousingAPI/UnlistHouse"):InvokeServer() end)
			if not unlistOk then
				return Rayfield:Notify({ Title = "Trade", Content = "Unlist request failed: " .. tostring(unlistErr), Duration = 4, Image = "circle-alert" })
			end
			Rayfield:Notify({ Title = "Trade", Content = "Unlist request sent.", Duration = 3, Image = "circle-check" })
		end,
	})

	local tradeSection = Tab:CreateSection("Auto Accept Trade Requests")
	local TradeRequestEvent = router.get_event("TradeAPI/TradeRequestReceived")
	local activeAcceptedTradePlayer = nil
	local activeAcceptedTradeAt = 0

	local function resolvePlayer(obj)
		if typeof(obj) == "Instance" and obj:IsA("Player") then
			return obj
		elseif typeof(obj) == "number" then
			return Players:GetPlayerByUserId(obj)
		elseif typeof(obj) == "string" then
			local wanted = string.lower(obj)
			for _, player in ipairs(Players:GetPlayers()) do
				if string.lower(player.Name) == wanted or string.lower(player.DisplayName) == wanted then
					return player
				end
			end
		end
		return nil
	end

	getPlayers = function()
		local t = { "None" }
		local seen = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= Players.LocalPlayer then
				table.insert(t, p.Name)
				seen[string.lower(p.Name)] = true
			end
		end

		-- Keep the saved player selectable even when they are currently offline.
		if selectedPlayer and selectedPlayer ~= "" and not seen[string.lower(selectedPlayer)] then
			table.insert(t, selectedPlayer)
		end

		if #t == 1 then table.insert(t, "No Players Online") end
		return t
	end

	PlayerDropdown = Tab:CreateDropdown({
		Name = "Select Player",
		Options = getPlayers(),
		CurrentOption = "None",
		MultipleOptions = false,
		Callback = function(option)
			if autoPasteApplyingSavedTargets then return end
			local value = (typeof(option) == "table") and option[1] or option
			if value == "None" or value == "No Players Online" then
				selectedPlayer = nil
			else
				selectedPlayer = value
			end
			autoSaveAutoPasteConfig()
		end,
	})

	local function refreshPlayers()
		local players = getPlayers()
		autoPasteApplyingSavedTargets = true
		pcall(function()
			PlayerDropdown:Refresh(players)
			PlayerDropdown:Set(selectedPlayer or "None")
		end)
		autoPasteApplyingSavedTargets = false
	end

	Tab:CreateInput({
		Name = "Type Player Name",
		PlaceholderText = "Enter username...",
		RemoveTextAfterFocusLost = false,
		Callback = function(text)
			if text ~= "" then
				selectedPlayer = text
				autoSaveAutoPasteConfig()
				Rayfield:Notify({ Title = "Player Set", Content = "Now accepting: " .. text, Duration = 3 })
			else
				selectedPlayer = nil
				PlayerDropdown:Set("None")
				autoSaveAutoPasteConfig()
			end
		end,
	})

	local function isSelectedTradeStillActive(playerName, acceptedAt)
		if not autoTradeEnabled or activeAcceptedTradeAt ~= acceptedAt then
			return false
		end

		-- When no player is selected, Auto Accept works for any player.
		-- If a player is selected, keep the sequence locked to that player only.
		if not selectedPlayer or selectedPlayer == "" then
			return activeAcceptedTradePlayer ~= nil
				and string.lower(activeAcceptedTradePlayer) == string.lower(tostring(playerName))
		end

		local player = resolvePlayer(selectedPlayer)
		return player ~= nil and string.lower(player.Name) == string.lower(tostring(playerName))
	end

	local function runTradeAcceptSequence(playerName, acceptedAt)
		-- Robust three-phase accept flow:
		-- 1) accept the incoming request repeatedly for a short window,
		-- 2) retry the negotiation Accept until that stage has had time to register,
		-- 3) stop touching AcceptNegotiation and retry only the final Confirm.
		-- The sequence is scoped to the selected player and is cancelled immediately
		-- when the toggle/player changes or a newer request starts.
		task.spawn(function()
			local player = resolvePlayer(playerName)
			if not player then
				if activeAcceptedTradeAt == acceptedAt then activeAcceptedTradePlayer = nil end
				return
			end

			-- PHASE 1: catch the pending request even when TradeRequestReceived was late.
			for _ = 1, 8 do
				if not isSelectedTradeStillActive(player.Name, acceptedAt) then return end
				pcall(function()
					local remote = router.get("TradeAPI/AcceptOrDeclineTradeRequest")
					if not remote then return end
					pcall(function() remote:FireServer(player, true) end)
					pcall(function() remote:InvokeServer(player, true) end)
					pcall(function() remote:FireServer(true) end)
				end)
				task.wait(0.5)
			end

			-- PHASE 2: Roblox may ignore the first AcceptNegotiation if the request
			-- has not fully transitioned into negotiation yet, so retry briefly.
			for _ = 1, 8 do
				if not isSelectedTradeStillActive(player.Name, acceptedAt) then return end
				pcall(function()
					local remote = router.get("TradeAPI/AcceptNegotiation")
					if not remote then return end
					pcall(function() remote:FireServer() end)
					pcall(function() remote:InvokeServer() end)
				end)
				task.wait(0.75)
			end

			-- PHASE 3: once we reach confirmation, never send AcceptNegotiation again.
			-- Keep retrying ConfirmTrade long enough to cover the countdown/server lag.
			for _ = 1, 32 do
				if not isSelectedTradeStillActive(player.Name, acceptedAt) then return end
				pcall(function()
					local remote = router.get("TradeAPI/ConfirmTrade")
					if not remote then return end
					pcall(function() remote:FireServer() end)
					pcall(function() remote:InvokeServer() end)
				end)
				task.wait(0.75)
			end

			if activeAcceptedTradeAt == acceptedAt then
				activeAcceptedTradePlayer = nil
			end
		end)
	end

	TradeRequestEvent.OnClientEvent:Connect(function(...)
		if not autoTradeEnabled then return end

		local args = { ... }
		local player = nil
		local selected = selectedPlayer and resolvePlayer(selectedPlayer) or nil

		for _, arg in ipairs(args) do
			local candidate = resolvePlayer(arg)
			if candidate and candidate ~= Players.LocalPlayer then
				if selectedPlayer and selectedPlayer ~= "" then
					if selected and candidate.UserId == selected.UserId then
						player = candidate
						break
					end
				else
					-- No saved/selected player: accept whoever sent the request,
					-- including players who joined after the script started.
					player = candidate
					break
				end
			end
		end

		if not player then return end

		activeAcceptedTradePlayer = player.Name
		activeAcceptedTradeAt += 1
		runTradeAcceptSequence(player.Name, activeAcceptedTradeAt)
	end)

	-- Fallback watcher: some client versions can miss TradeRequestReceived if the
	-- request was already visible when the toggle/config was restored. Periodically
	-- try the selected player's request and start the same guarded sequence.
	task.spawn(function()
		while true do
			task.wait(1)
			if autoTradeEnabled and selectedPlayer and not activeAcceptedTradePlayer then
				local player = resolvePlayer(selectedPlayer)
				if player and player ~= Players.LocalPlayer then
					pcall(function()
						local remote = router.get("TradeAPI/AcceptOrDeclineTradeRequest")
						if remote then
							pcall(function() remote:FireServer(player, true) end)
							pcall(function() remote:InvokeServer(player, true) end)
							pcall(function() remote:FireServer(true) end)
						end
					end)
					activeAcceptedTradePlayer = player.Name
					activeAcceptedTradeAt += 1
					runTradeAcceptSequence(player.Name, activeAcceptedTradeAt)
				end
			end
		end
	end)

	autoAcceptToggle = Tab:CreateToggle({
		Name = "Auto Accept Player",
		CurrentValue = false,
		Callback = function(val)
			if autoPasteApplyingSavedTargets then return end
			autoTradeEnabled = val
			if not val then
				activeAcceptedTradePlayer = nil
				activeAcceptedTradeAt += 1
			end
			autoSaveAutoPasteConfig()
			Rayfield:Notify({
				Title = "Auto Trade",
				Content = val and ("Enabled for: " .. (selectedPlayer or "Any Player")) or "Disabled",
				Duration = 3,
			})
		end,
	})

	Players.PlayerAdded:Connect(function(player)
		task.wait(0.3)
		refreshPlayers()
		if autoTradeEnabled and not selectedPlayer and player ~= Players.LocalPlayer then
			Rayfield:Notify({
				Title = "Auto Trade",
				Content = player.Name .. " joined - Auto Accept is ready for their trade request.",
				Duration = 3,
			})
		end
	end)
	Players.PlayerRemoving:Connect(function() task.wait(0.3) refreshPlayers() end)

	-- ==================== PASTEBIN TAB ====================
	local PastebinTab = Window:CreateTab("Pastebin", "clipboard")
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

	local function LoadHouseFromPastebin(pasteValue)
		local houseData, pasteIdOrErr = loadHouseDataFromPastebin(pasteValue)
		if not houseData then
			return Rayfield:Notify({ Title = "Error", Content = tostring(pasteIdOrErr), Duration = 4 })
		end
		savedhouse = houseData
		local furniturecost = 0
		for _, v in pairs(savedhouse.furniture or {}) do if furnituresdb[v.id] then furniturecost += furnituresdb[v.id].cost or 0 end end
		local texturecost = 0
		for _, v in pairs(savedhouse.textures or {}) do
			if texturesdb.walls[v.walls] then texturecost += texturesdb.walls[v.walls].cost or 0 end
			if texturesdb.floors[v.floors] then texturecost += texturesdb.floors[v.floors].cost or 0 end
		end
		local t_count = counttextures(savedhouse.textures)
		local amb = savedhouse.ambiance and "Yes" or "No"
		local typ = savedhouse.building_type or "-"
		task.spawn(setscaninfo, countfurnitures(savedhouse.furniture), furniturecost, t_count, texturecost, amb, typ)
		Rayfield:Notify({ Title = "Success", Content = "House loaded from Pastebin", Duration = 3, Image = "circle-check" })
	end

	PastebinTab:CreateInput({
		Name = "Pastebin Link / ID",
		PlaceholderText = "https://pastebin.com/xxxxxx or xxxxxx",
		RemoveTextAfterFocusLost = true,
		WaitTime = 2,
		Callback = function(value) LoadHouseFromPastebin(value) end,
	})

	PastebinTab:CreateButton({
		Name = "Save House to Pastebin",
		Callback = function()
			if not savedhouse then
				return Rayfield:Notify({ Title = "Error", Content = "No house has been scanned or loaded", Duration = 3 })
			end
			if #userPastebinDevKey < 20 or not userPastebinDevKey:match("^[%w]+$") then
				return Rayfield:Notify({ Title = "Invalid API Key", Content = "Paste ONLY the Pastebin Dev API key.\nDo not paste a URL.", Duration = 5 })
			end
			local clean_house = deepCopy(savedhouse)
			local furniturecost = 0
			for _, v in pairs(clean_house.furniture or {}) do
				if furnituresdb[v.id] then furniturecost += furnituresdb[v.id].cost or 0 end
				v.hash = nil v.was_free = nil v.no_value = nil v.was_default = nil
				v.item_category = nil v.item_kind = nil v.occupied = v.occupied or nil
				v.door_position = nil v.last_position = nil v.on = nil
			end
			local texturecost = 0
			for _, v in pairs(clean_house.textures or {}) do
				if texturesdb.walls[v.walls] then texturecost += texturesdb.walls[v.walls].cost or 0 end
				if texturesdb.floors[v.floors] then texturecost += texturesdb.floors[v.floors].cost or 0 end
			end
			clean_house.total_cost = furniturecost + texturecost
			clean_house.furniture_quantity = countfurnitures(clean_house.furniture)
			clean_house.saved_by = "Cubix-HouseCloner"
			clean_house.properties = nil clean_house.house_id = nil clean_house.listed_for_trade = nil
			clean_house.unique = nil clean_house.active_addons = nil clean_house.allows_coop_building = nil
			clean_house.house_pos = nil clean_house.textures_hash = nil clean_house.player = nil
			local serializableHouse = serializeAutoPasteValue(clean_house)
			local ok, encoded = pcall(function() return HttpService:JSONEncode(serializableHouse) end)
			if not ok then return Rayfield:Notify({ Title = "Error", Content = "Failed to encode house data", Duration = 3 }) end
			local apiUserKey, loginErr = getUserKey(userPastebinDevKey, userPastebinUsername, userPastebinPassword)
			if not apiUserKey and loginErr ~= "NO_LOGIN" then
				Rayfield:Notify({ Title = "Warning", Content = "Pastebin login failed; posting as guest", Duration = 3 })
			end
			local inputtedName = pasteNameInput.CurrentValue or ""
			local pasteName = "CubixHouse" .. (inputtedName ~= "" and "_" .. inputtedName or "")
			local result, err = createPaste(encoded, pasteName, userPastebinDevKey, apiUserKey)
			if err or not result then
				return Rayfield:Notify({ Title = "Pastebin Error", Content = tostring(err or result), Duration = 6 })
			end
			if setclipboard then setclipboard(result) end
			Rayfield:Notify({ Title = "Success", Content = "House saved to Pastebin\nLink copied to clipboard", Duration = 8 })
		end,
	})

	-- ==================== CREATE FILE TAB ====================
	local CreateFileTab = Window:CreateTab("Create File", "folder")

	if not isfolder(houseFilesPath) then makefolder(houseFilesPath) end

	CreateFileTab:CreateSection("Saved Houses")

	local fileDropdown = CreateFileTab:CreateDropdown({
		Name = "Select Saved House",
		Options = {},
		CurrentOption = nil,
		MultipleOptions = false,
		Flag = "FileDropdown",
		Callback = function(_) end,
	})

	local saveInput = CreateFileTab:CreateInput({
		Name = "Save As",
		PlaceholderText = "Enter File Name",
		RemoveTextAfterFocusLost = false,
		Callback = function(_) end,
	})

	local pendingDelete = nil
	local fileSearchQuery = ""
	local allFilesCache = {}

	local function getBaseFileName(path)
		return tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
	end

	local function sanitizeFileName(name)
		name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
		name = name:gsub("%.json$", ""):gsub("%.txt$", ""):gsub("%.lua$", "")
		name = name:gsub("%.%.", "_"):gsub("[/\\:*?\"<>|]", "_")
		name = name:gsub("[%c]", "_"):sub(1, 100)
		if name == "" then return nil end
		return name
	end

	local function naturalSort(a, b)
		local function pad(n) return ("%010d"):format(tonumber(n) or 0) end
		local na = a:lower():gsub("%d+", pad)
		local nb = b:lower():gsub("%d+", pad)
		return na < nb
	end

	local function refreshFileDropdown()
		local folderOk, folderExists = pcall(isfolder, houseFilesPath)
		if not folderOk or not folderExists then
			pcall(makefolder, houseFilesPath)
		end

		local listed, files = pcall(listfiles, houseFilesPath)
		if not listed or type(files) ~= "table" then
			files = {}
		end
		local validFiles = {}
		for _, filePath in ipairs(files) do
			local fileName = tostring(filePath):match("([^/\\]+)$") or tostring(filePath)
			if fileName:sub(-5) == ".json" or fileName:sub(-4) == ".txt" or fileName:sub(-4) == ".lua" then
				table.insert(validFiles, fileName)
			end
		end
		table.sort(validFiles, naturalSort)
		allFilesCache = validFiles
		local filtered = {}
		for _, name in ipairs(allFilesCache) do
			if fileSearchQuery == "" or string.find(string.lower(name), string.lower(fileSearchQuery), 1, true) then
				table.insert(filtered, name)
			end
		end
		if not fileDropdown then
			refreshFQFileList()
			return
		end

		local currentlySelected = fileDropdown.CurrentOption
		if type(currentlySelected) == "table" then currentlySelected = currentlySelected[1] end
		pcall(function() fileDropdown:Refresh(filtered) end)
		if currentlySelected and table.find(filtered, currentlySelected) then
			pcall(function() fileDropdown:Set(currentlySelected) end)
		elseif #filtered > 0 then
			pcall(function() fileDropdown:Set(filtered[1]) end)
		else
			-- Rayfield cannot safely Set(nil) on an empty dropdown.
			pcall(function() fileDropdown:Set({}) end)
		end
		refreshFQFileList()
	end

	refreshFileDropdown()

	CreateFileTab:CreateInput({
		Name = "Search Files",
		PlaceholderText = "Type to search house files...",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			fileSearchQuery = tostring(value or "")
			refreshFileDropdown()
		end,
	})

	CreateFileTab:CreateButton({
		Name = "Save House to File",
		Callback = function()
			if not savedhouse then
				return Rayfield:Notify({ Title = "Error", Content = "No house has been scanned or loaded", Duration = 3, Image = "circle-alert" })
			end
			local filename = sanitizeFileName(saveInput.CurrentValue)
			if not filename then
				return Rayfield:Notify({ Title = "Error", Content = "Please enter a valid filename", Duration = 3, Image = "circle-alert" })
			end
			local clean_house = deepCopy(savedhouse)
			local furniturecost = 0
			for _, v in pairs(clean_house.furniture or {}) do
				if furnituresdb[v.id] then furniturecost += furnituresdb[v.id].cost or 0 end
				v.hash = nil v.was_free = nil v.no_value = nil v.was_default = nil
				v.item_category = nil v.item_kind = nil v.occupied = v.occupied or nil
				v.door_position = nil v.last_position = nil v.on = nil
			end
			local texturecost = 0
			for _, v in pairs(clean_house.textures or {}) do
				if texturesdb.walls[v.walls] then texturecost += texturesdb.walls[v.walls].cost or 0 end
				if texturesdb.floors[v.floors] then texturecost += texturesdb.floors[v.floors].cost or 0 end
			end
			clean_house.total_cost = furniturecost + texturecost
			clean_house.furniture_quantity = countfurnitures(clean_house.furniture)
			clean_house.saved_by = "Cubix-HouseCloner"
			clean_house.properties = nil clean_house.house_id = nil clean_house.listed_for_trade = nil
			clean_house.unique = nil clean_house.active_addons = nil clean_house.allows_coop_building = nil
			clean_house.house_pos = nil clean_house.textures_hash = nil clean_house.player = nil
			local serializableHouse = serializeAutoPasteValue(clean_house)
			local success, encoded = pcall(function() return HttpService:JSONEncode(serializableHouse) end)
			if not success then
				return Rayfield:Notify({ Title = "Error", Content = "Failed to encode house data", Duration = 3, Image = "circle-alert" })
			end
			local wrote, writeErr = pcall(function() writefile(houseFilesPath .. "/" .. filename .. ".json", encoded) end)
			if not wrote then
				return Rayfield:Notify({ Title = "Error", Content = "Failed to save file: " .. tostring(writeErr), Duration = 4, Image = "circle-alert" })
			end
			refreshFileDropdown()
			Rayfield:Notify({ Title = "Success", Content = "House saved: " .. filename .. ".json", Duration = 3, Image = "circle-check" })
		end,
	})


	CreateFileTab:CreateButton({
		Name = "Load House from File",
		Callback = function()
			local selected = fileDropdown.CurrentOption
			if type(selected) == "table" then selected = selected[1] end
			if not selected or selected == "" then
				return Rayfield:Notify({ Title = "Error", Content = "No file selected to load", Duration = 3 })
			end
			local houseData, err = loadHouseDataFromFile(selected)
			if not houseData then
				return Rayfield:Notify({ Title = "Error", Content = "Failed to load " .. selected .. ": " .. tostring(err), Duration = 3 })
			end
			savedhouse = houseData
			local furniturecost = 0
			for _, v in pairs(savedhouse.furniture or {}) do
				if furnituresdb[v.id] then furniturecost += furnituresdb[v.id].cost or 0 end
			end
			local texturecost = 0
			for _, v in pairs(savedhouse.textures or {}) do
				if texturesdb.walls[v.walls] then texturecost += texturesdb.walls[v.walls].cost or 0 end
				if texturesdb.floors[v.floors] then texturecost += texturesdb.floors[v.floors].cost or 0 end
			end
			local t_count = counttextures(savedhouse.textures)
			local amb = savedhouse.ambiance and "Yes" or "No"
			local typ = savedhouse.building_type or "-"
			task.spawn(setscaninfo, countfurnitures(savedhouse.furniture), furniturecost, t_count, texturecost, amb, typ)
			Rayfield:Notify({ Title = "Success", Content = "House loaded from file: " .. selected, Duration = 3 })
			refreshFileDropdown()
		end,
	})

	CreateFileTab:CreateButton({
		Name = "Delete Selected House",
		Callback = function()
			local selected = fileDropdown.CurrentOption
			if type(selected) == "table" then selected = selected[1] end
			if not selected or selected == "" then
				return Rayfield:Notify({ Title = "Error", Content = "No house selected to delete.", Duration = 3 })
			end
			if pendingDelete == selected then
				selected = getBaseFileName(selected)
				local filePath = houseFilesPath .. "/" .. selected
				local existsOk, exists = pcall(isfile, filePath)
				if existsOk and exists then
					local deleteOk, deleteErr = pcall(delfile, filePath)
					if not deleteOk then
						return Rayfield:Notify({ Title = "Error", Content = "Delete failed: " .. tostring(deleteErr), Duration = 4 })
					end
					Rayfield:Notify({ Title = "Deleted", Content = selected .. " has been deleted.", Duration = 3, Image = "circle-check" })
					pendingDelete = nil
					refreshFileDropdown()
				else
					Rayfield:Notify({ Title = "Error", Content = "File not found: " .. selected, Duration = 3 })
				end
			else
				pendingDelete = selected
				Rayfield:Notify({
					Title = "Confirm Delete",
					Content = "Are you sure you want to delete **" .. selected .. "**?\n\nClick the Delete button again to confirm.",
					Duration = 10,
					Image = "circle-alert",
				})
			end
		end,
	})

	CreateFileTab:CreateButton({
		Name = "Refresh List",
		Callback = function()
			refreshFileDropdown()
			Rayfield:Notify({ Title = "Refreshed", Content = "File list updated and sorted", Duration = 2 })
		end,
	})

	-- ==================== TELEPORT TAB ====================
	local Teleport = Window:CreateTab("Teleport", "map-pin")
	Teleport:CreateSection("House Teleports")

	local function loadinterior(interiortype, name)
		local load = require(game:GetService("ReplicatedStorage").Fsys).load
		local interiors = load("InteriorsM")
		local enter = interiors.enter
		if interiortype == "interior" then enter(name, "", {}) return end
		if interiortype == "house" then enter("housing", "MainDoor", { house_owner = name }) end
	end

	local function getplayernames()
		local players = Players:GetPlayers()
		local names = table.create(#players)
		for i, player in ipairs(players) do names[i] = player.Name end
		return names
	end

	local selectedplayer = Teleport:CreateDropdown({
		Name = "Select Player",
		Options = getplayernames(),
		CurrentOption = { getplayernames()[1] },
		MultipleOptions = false,
		Flag = "Dropdown1",
		Callback = function(_) end,
	})

	Players.PlayerAdded:Connect(function() selectedplayer:Refresh(getplayernames()) end)
	Players.PlayerRemoving:Connect(function() selectedplayer:Refresh(getplayernames()) end)

	Teleport:CreateButton({
		Name = "Enter House",
		Callback = function()
			local target = Players:FindFirstChild(selectedplayer.CurrentOption[1])
			if target then loadinterior("house", target) end
		end,
	})

	Teleport:CreateButton({
		Name = "Teleport to My House",
		Callback = function()
			local lp = Players.LocalPlayer
			if lp then loadinterior("house", lp) end
		end,
	})

	-- ==================== AUTO REFRESH ====================
	refreshOwnedHouses()

	-- Use the ClientData callback when available, but do not rely on it alone.
	-- Some client versions expose register_callback_plus_existing() successfully
	-- yet do not consistently fire it for later house_manager mutations.
	pcall(function()
		ClientData.register_callback_plus_existing("house_manager", function()
			refreshOwnedHouses()
		end)
	end)

	-- Reliable Target Houses watcher. This runs regardless of whether the callback
	-- API exists. It builds a stable signature from the owned house IDs + names
	-- and refreshes the dropdown only when that signature actually changes.
	-- Locals stay inside this spawned function so they do not add register pressure
	-- to the already-large loadMain() function.
	task.spawn(function()
		local lastSignature = nil

		local function getHouseManagerSignature()
			local parts = {}
			local ok, manager = pcall(function()
				return ClientData.get("house_manager") or {}
			end)

			if not ok or type(manager) ~= "table" then
				return nil
			end

			for _, house in pairs(manager) do
				table.insert(parts,
					tostring(house.house_id or "")
						.. "|" .. tostring(house.name or "")
						.. "|" .. tostring(house.building_type or house.kind or house.type or "")
				)
			end

			table.sort(parts)
			return table.concat(parts, ";")
		end

		while true do
			local signature = getHouseManagerSignature()
			if signature ~= nil and signature ~= lastSignature then
				lastSignature = signature
				refreshOwnedHouses()
			end
			task.wait(2)
		end
	end)

	-- Rayfield shows a "configuration loaded" toast by default. Load the
	-- configuration normally, but hide only that library status notification.
	local originalRayfieldNotify = Rayfield.Notify
	Rayfield.Notify = function(self, notification)
		if notification and notification.Title == "Rayfield Configurations" then
			return
		end
		return originalRayfieldNotify(self, notification)
	end
	do
		local rayfieldConfigOk, rayfieldConfigErr = pcall(function()
			Rayfield:LoadConfiguration()
		end)
		Rayfield.Notify = originalRayfieldNotify
		if not rayfieldConfigOk then
			warn("[Cubix] Rayfield configuration load failed: " .. tostring(rayfieldConfigErr))
		end
	end
	refreshOwnedHouses()
	local loadCallOk, loadedOk, loadInfo = pcall(loadAutoPasteConfig)
	if not loadCallOk then
		warn("[Cubix AutoSave] Failed to load Auto Paste config: " .. tostring(loadedOk))
	elseif loadedOk == false and loadInfo ~= "No saved Auto Paste config found" then
		warn("[Cubix AutoSave] " .. tostring(loadInfo))
	end
	autoPasteConfigReady = true
	autoSaveAutoPasteConfig()
	Rayfield:Notify({ Title = "Cubix", Content = "Loaded successfully!", Duration = 5 })
end

loadMain()
