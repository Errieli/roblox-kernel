local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local rootName = "Assets"

local function map(container)
	local mapped = {}

	local metatable = {
		__index = function(self, name)
			if not container then
				container = ReplicatedStorage:FindFirstChild(rootName)
				assert(container, "Missing project folder: " .. rootName)
			end
			local child = container:FindFirstChild(name)
			if not child then
				error("Asset " .. name .. " does not exist in " .. container:GetFullName(), 2)
			end

			local value = if child:IsA("Folder") then map(child) else child

			rawset(self, name, value)

			return value
		end,
	}

	return setmetatable(mapped, metatable)
end

return map(nil)
