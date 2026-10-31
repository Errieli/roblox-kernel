-- The public Kernel members and the rules for registering them.
local Exports = {
	Values = {},
	Info = {},
}

function Exports.AddBuiltin(name, value, purpose)
	Exports.Values[name] = value
	Exports.Info[name] = {purpose = purpose, dependencies = {}}
end

function Exports.Add(definition)
	local name, value, purpose = definition.name, definition.value, definition.purpose
	assert(typeof(name) == "string" and name ~= "", "Kernel export name must be a non-empty string")
	assert(value ~= nil, "Kernel export value is required: " .. name)
	assert(Exports.Values[name] == nil, "Duplicate Kernel export: " .. name)
	assert(typeof(purpose) == "string" and purpose ~= "", "Kernel export purpose is required: " .. name)

	local dependencies = definition.dependencies
	if dependencies == nil then dependencies = {} end
	assert(typeof(dependencies) == "table", "Kernel dependencies must be a table: " .. name)
	dependencies = table.clone(dependencies)
	for _, dependency in ipairs(dependencies) do
		assert(typeof(dependency) == "string" and dependency ~= "", "Invalid Kernel dependency for " .. name)
	end

	Exports.Values[name] = value
	Exports.Info[name] = {purpose = purpose, dependencies = dependencies}
end

function Exports.Missing()
	local result = {}
	for name, details in pairs(Exports.Info) do
		local missing = {}
		for _, dependency in ipairs(details.dependencies) do
			if Exports.Values[dependency] == nil then missing[#missing + 1] = dependency end
		end
		if #missing > 0 then result[name] = missing end
	end
	return result
end

-- Failure message for declared dependencies nobody registered, or nil when all resolved.
function Exports.Unresolved()
	local unresolved = {}
	for name, dependencies in pairs(Exports.Missing()) do
		unresolved[#unresolved + 1] = name .. " -> " .. table.concat(dependencies, ", ")
	end
	if #unresolved == 0 then return nil end
	table.sort(unresolved)
	return "Unresolved dependencies: " .. table.concat(unresolved, "; ")
end

return Exports
