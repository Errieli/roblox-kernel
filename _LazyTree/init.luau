local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Mirrors the folder at ReplicatedStorage.<path...> lazily: the folder is
-- located on first access, and each child is resolved on first access and
-- cached. Folders become nested mirrors; any other child is required as a
-- ModuleScript unless resolve(child) decides its value.
-- kind names the entry in errors ("Config", "Utility", "Asset").
return function(path, kind, resolve)
	resolve = resolve or function(child)
		if not child:IsA("ModuleScript") then
			error(kind .. " " .. child:GetFullName() .. " must be a ModuleScript or Folder", 3)
		end

		return require(child)
	end

	local function locate()
		local container = ReplicatedStorage
		for _, name in path do
			container = container:FindFirstChild(name)
			if not container then
				error("Missing project folder: ReplicatedStorage." .. table.concat(path, "."), 3)
			end
		end

		return container
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
