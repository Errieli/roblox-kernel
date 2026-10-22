local HttpService = game:GetService("HttpService")
local loaded = {
	GetRandomUID = function()
		return HttpService:GenerateGUID(false)
	end,
}

return table.freeze(setmetatable({}, {
	__index = function(_, name)
		if typeof(name) ~= "string" then return nil end
		if loaded[name] ~= nil then return loaded[name] end

		local module = script:FindFirstChild("_" .. name)
		if not module or not module:IsA("ModuleScript") then
			error("Unknown Kernel utility: " .. name, 2)
		end

		local value = require(module)
		loaded[name] = value
		return value
	end,
}))
