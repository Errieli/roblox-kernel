local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Mirrors ReplicatedStorage[rootName] lazily: each child is resolved on first
-- access and cached. Folders become nested mirrors; any other child is
-- required as a ModuleScript unless resolve(child) decides its value.
-- kind names the entry in errors ("Config", "Utility", "Asset").
-- search, when given, is shared with the facade: search.Folders lists the
-- ReplicatedStorage children looked in, in order, when the root has no
-- rootName folder; search.Resolved records that a lookup has happened.
return function(rootName, kind, resolve, search)
	resolve = resolve or function(child)
		if not child:IsA("ModuleScript") then
			error(kind .. " " .. child:GetFullName() .. " must be a ModuleScript or Folder", 3)
		end

		return require(child)
	end

	local function locate()
		if search then search.Resolved = true end

		local container = ReplicatedStorage:FindFirstChild(rootName)
		if container then return container end

		local searched = {"ReplicatedStorage"}
		for _, name in if search then search.Folders else {} do
			local folder = ReplicatedStorage:FindFirstChild(name)
			container = folder and folder:FindFirstChild(rootName)
			if container then return container end
			searched[#searched + 1] = "ReplicatedStorage." .. name
		end

		error("Missing project folder: " .. rootName .. " (searched " .. table.concat(searched, ", ") .. ")", 3)
	end

	local function mirror(container)
		return setmetatable({}, {
			__index = function(self, name)
				if not container then container = locate() end

				local child = container:FindFirstChild(name)
				if not child then
					error(kind .. " " .. name .. " does not exist in " .. container:GetFullName(), 2)
				end

				local value = if child:IsA("Folder") then mirror(child) else resolve(child)
				rawset(self, name, value)
				return value
			end,
		})
	end

	return mirror(nil)
end
