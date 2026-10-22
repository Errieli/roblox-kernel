type anyCallback = (...any?) -> (...any?)
type anyTable = {[any]: any}

local weakK = { __mode = "k" }

local Table = {}

-- Iterates over a table and calls a callback function for each key-value pair.
function Table.Iterate(list: anyTable, callback: anyCallback, ...: any?) : ()
	for key, value in list do
		callback(key, value, ...)
	end
end

-- Removes a specified value from a table.
function Table.Remove(list: anyTable, value): boolean?
	local index = table.find(list, value)
	if not index then return nil end
	table.remove(list, index)
	return true
end

-- Counts the number of elements in a table.
function Table.Size(list: anyTable)
	local count = 0
	for _ in list do count += 1 end
	return count
end

-- Counts the number of elements in a table.
function Table.IterateIfTable(data: any? | {any?}, callback: anyCallback)
	if typeof(data) == "table" then
		for _, value in data do
			callback(value)
		end
	else
		callback(data)
	end
end

-- Create a weak a table.
function Table.Weak()
	return setmetatable({}, weakK) :: {}
end

-- Resolves a dot-separated path and returns its parent, key and current value.
function Table.GetPath(root: anyTable, path: string)
	if typeof(root) ~= "table" or typeof(path) ~= "string" then return end

	local parts = string.split(path, ".")
	local current = root

	for index = 1, #parts - 1 do
		if typeof(current) ~= "table" then return end
		local key = parts[index]
		if current[key] == nil then key = tonumber(key) or key end
		current = current[key]
	end

	if typeof(current) ~= "table" then return end

	local key = parts[#parts]
	if current[key] == nil then key = tonumber(key) or key end

	return current, key, current[key]
end

-- Create a deep copy of a table.
function Table.DeepCopy<T>(original: T, copy: T?): T
	copy = copy or {}

	for key, value in pairs(original) do
		if typeof(value) == "table" then
			(copy :: any)[key] = Table.DeepCopy(value)
		else
			(copy :: any)[key] = value
		end
	end

	return copy
end

return Table