local Players           = game:GetService("Players")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lp  = Players.LocalPlayer
local gui = lp:WaitForChild("PlayerGui")

local function safeRequire(path)
	local ok, mod = pcall(require, path)
	if ok then return mod end
	return nil
end

local ItemModule = safeRequire(ReplicatedStorage:FindFirstChild("Shared")
	and ReplicatedStorage.Shared:FindFirstChild("Item"))
local Layouts = safeRequire(ReplicatedStorage:FindFirstChild("Shared")
	and ReplicatedStorage.Shared:FindFirstChild("Layouts"))

local LOCAL_FILE   = "TradeInventoryStack.json"
local ID_FILE      = "TradeInventoryStack_BinID.txt"
local COUNTER_FILE = "TradeInventoryStack_Count.txt"

local NPOINT_API = "https://api.npoint.io"
local NPOINT_WEB = "https://www.npoint.io/docs/"

local httpRequest = (syn and syn.request)
	or (http and http.request)
	or (typeof(request) == "function" and request)
	or (typeof(http_request) == "function" and http_request)

local hasFiles = (typeof(writefile) == "function")
	and (typeof(readfile) == "function")
	and (typeof(isfile) == "function")

local function shouldSkip(name)
	if not name then return true end
	local lower = name:lower()
	if lower:sub(1, 7) == "default" then return true end
	if lower:find("effect", 1, true) then return true end
	return false
end

local function readLocal(path)
	if not hasFiles or not isfile(path) then return nil end
	local ok, raw = pcall(readfile, path)
	if ok then return raw end
	return nil
end

local function writeLocal(path, content)
	if not hasFiles then return end
	pcall(writefile, path, content)
end

local function jsonDecode(s)
	if not s or s == "" then return {} end
	local ok, data = pcall(function() return HttpService:JSONDecode(s) end)
	if ok and type(data) == "table" then return data end
	return {}
end

local function jsonEncode(t)
	local ok, s = pcall(function() return HttpService:JSONEncode(t) end)
	if ok then return s end
	return "{}"
end

local function httpDo(method, url, body)
	if not httpRequest then return nil end
	local ok, res = pcall(function()
		return httpRequest({
			Url = url,
			Method = method,
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})
	end)
	if not ok or not res then return nil end
	if res.StatusCode and res.StatusCode >= 200 and res.StatusCode < 300 then
		return res.Body
	end
	return nil
end

local function loadBinID()
	local raw = readLocal(ID_FILE)
	if raw then
		local trimmed = raw:match("^%s*(.-)%s*$")
		if trimmed and #trimmed > 0 then return trimmed end
	end
	return nil
end

local function saveBinID(id)
	writeLocal(ID_FILE, id)
end

local function createBin(initialData)
	local body = jsonEncode(initialData)
	local res = httpDo("POST", NPOINT_API, body)
	if not res then return nil end
	local parsed = jsonDecode(res)
	local id = parsed and (parsed.token or parsed.id)
	return id
end

local function fetchBin(id)
	local res = httpDo("GET", NPOINT_API .. "/" .. id)
	if not res then return nil end
	return jsonDecode(res)
end

local function updateBin(id, data)
	local body = jsonEncode(data)
	httpDo("POST", NPOINT_API .. "/" .. id, body)
end

local function getInventoryHolder()
	local ok, holder = pcall(function()
		return gui:WaitForChild("Main", 5)
			:WaitForChild("MainInventoryFrame", 5)
			:WaitForChild("ItemsHolderFrame", 5)
	end)
	if ok then return holder end
	return nil
end

local function readGameItems(holder)
	local items = {}
	for _, frame in ipairs(holder:GetChildren()) do
		if frame:IsA("Frame") or frame:IsA("ImageButton") or frame:IsA("TextButton") then
			if not shouldSkip(frame.Name) then
				local countLabel = frame:FindFirstChild("ItemCount")
				if countLabel then
					local count = tonumber(countLabel.Text) or 0
					if count > 0 then
						items[frame.Name] = {
							count = count,
							frame = frame,
							label = countLabel,
						}
					end
				end
			end
		end
	end
	return items
end

local function loadStored()
	local binID = loadBinID()
	if binID and httpRequest then
		local remote = fetchBin(binID)
		if remote and type(remote) == "table" then
			writeLocal(LOCAL_FILE, jsonEncode(remote))
			return remote, binID
		end
	end
	local raw = readLocal(LOCAL_FILE)
	return jsonDecode(raw or "{}"), binID
end

local function saveStored(data, binID)
	writeLocal(LOCAL_FILE, jsonEncode(data))
	if not httpRequest then return binID end
	if binID then
		updateBin(binID, data)
		return binID
	end
	local newID = createBin(data)
	if newID then
		saveBinID(newID)
		warn("[StackInventory] Editar cantidades en: " .. NPOINT_WEB .. newID)
		return newID
	end
	return nil
end

local function getTemplate()
	local main = gui:FindFirstChild("Main")
	if not main then return nil end
	local invFrame = main:FindFirstChild("MainInventoryFrame")
	if not invFrame then return nil end
	return invFrame:FindFirstChild("Template")
end

local function buildFrame(holder, name, count)
	local template = getTemplate()
	if not template then return nil end

	local existing = holder:FindFirstChild(name)
	if existing then return existing end

	local frame = template:Clone()
	frame.Name = name
	frame.Visible = true
	frame.Parent = holder

	local itemData = ItemModule and ItemModule[name]
	if itemData then
		pcall(function()
			if frame:FindFirstChild("ItemImage") then
				frame.ItemImage.Image = itemData.Image or ""
			end
			if frame:FindFirstChild("cover") and frame.cover:FindFirstChild("ItemName") then
				frame.cover.ItemName.Text = itemData.ItemName or name
			end
			if itemData.Rarity and Layouts and Layouts[itemData.Rarity] then
				if frame:FindFirstChild("cover") and frame.cover:FindFirstChild("UIGradient") then
					frame.cover.UIGradient.Color = Layouts[itemData.Rarity].Gradient
				end
				if frame:FindFirstChild("UIStroke") and frame.UIStroke:FindFirstChild("UIGradient") then
					frame.UIStroke.UIGradient.Color = Layouts[itemData.Rarity].Gradient
				end
				frame.LayoutOrder = Layouts[itemData.Rarity].Index or frame.LayoutOrder
			end
		end)
	else
		pcall(function()
			if frame:FindFirstChild("cover") and frame.cover:FindFirstChild("ItemName") then
				frame.cover.ItemName.Text = name
			end
		end)
	end

	if frame:FindFirstChild("ItemCount") then
		frame.ItemCount.Text = tostring(count)
	end

	return frame
end

local function applyToHolder(holder, stored)
	for name, count in pairs(stored) do
		if not shouldSkip(name) then
			local frame = holder:FindFirstChild(name)
			if frame then
				local lbl = frame:FindFirstChild("ItemCount")
				if lbl then
					local current = tonumber(lbl.Text) or 0
					if count > current then
						lbl.Text = tostring(count)
					end
				end
			else
				buildFrame(holder, name, count)
			end
		end
	end
end

local function initialize()
	local holder = getInventoryHolder()
	if not holder then return end

	local stored, binID = loadStored()
	local inGame = readGameItems(holder)
	local isFirstRun = next(stored) == nil

	if isFirstRun then
		stored = {}
		for name, info in pairs(inGame) do
			stored[name] = info.count
		end
		local id = saveStored(stored, binID)
		print("[StackInventory] Valores iniciales guardados.")
		if id then
			print("[StackInventory] Editar cantidades en: " .. NPOINT_WEB .. id)
		end
	else
		local raw = readLocal(COUNTER_FILE)
		local execCount = tonumber(raw and raw:match("%d+")) or 0
		execCount = execCount + 1
		writeLocal(COUNTER_FILE, tostring(execCount))

		if execCount % 3 == 0 then
			for name, count in pairs(stored) do
				if type(count) == "number" then
					stored[name] = count + 1
				end
			end
			print("[StackInventory] Ejecucion " .. execCount .. ": +1 a todos los items.")
		else
			print("[StackInventory] Ejecucion " .. execCount .. ": sin cambios.")
		end
		local id = saveStored(stored, binID)
		if id then
			print("[StackInventory] Editar cantidades en: " .. NPOINT_WEB .. id)
		end
	end

	applyToHolder(holder, stored)

	holder.ChildRemoved:Connect(function(child)
		if shouldSkip(child.Name) then return end
		task.wait(0.05)
		local cur = jsonDecode(readLocal(LOCAL_FILE) or "{}")
		local count = tonumber(cur[child.Name])
		if count and count > 0 and not holder:FindFirstChild(child.Name) then
			buildFrame(holder, child.Name, count)
		end
	end)

	holder.ChildAdded:Connect(function(child)
		if shouldSkip(child.Name) then return end
		task.wait(0.1)
		local cur = jsonDecode(readLocal(LOCAL_FILE) or "{}")
		local count = tonumber(cur[child.Name])
		local lbl = child:FindFirstChild("ItemCount")
		if count and lbl then
			local current = tonumber(lbl.Text) or 0
			if count > current then
				lbl.Text = tostring(count)
			end
		end
	end)

	for _, frame in ipairs(holder:GetChildren()) do
		if not shouldSkip(frame.Name) then
			local lbl = frame:FindFirstChild("ItemCount")
			if lbl then
				lbl:GetPropertyChangedSignal("Text"):Connect(function()
					local cur = jsonDecode(readLocal(LOCAL_FILE) or "{}")
					local count = tonumber(cur[frame.Name])
					local current = tonumber(lbl.Text) or 0
					if count and count > current then
						lbl.Text = tostring(count)
					end
				end)
			end
		end
	end
end

initialize()
