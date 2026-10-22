local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local rootName = "Configs"

local function load(container)
	local loaded = {}

	local metatable = {
		__index = function(self, name)
			if not container then
				container = ReplicatedStorage:FindFirstChild(rootName)
				assert(container, "Missing project folder: " .. rootName)
			end
			local child = container:FindFirstChild(name)
			if not child then
				error("Config " .. name .. " does not exist in " .. container:GetFullName(), 2)
			end

			local value

			if child:IsA("Folder") then
				value = load(child)
			elseif child:IsA("ModuleScript") then
				value = require(child)
			else
				error("Config " .. child:GetFullName() .. " must be a ModuleScript or Folder", 2)
			end

			rawset(self, name, value)

			return value
		end,
	}

	return setmetatable(loaded, metatable)
end

return load(nil)
