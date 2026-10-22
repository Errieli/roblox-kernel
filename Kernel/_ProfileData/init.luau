-- Persistence/replication values form a tree. Typed path segments preserve numeric keys.
local Data = {Protocol = 1}
function Data.Key(key)
	assert((type(key) == "string" and key ~= "") or (type(key) == "number" and key >= 1 and key < math.huge and key % 1 == 0), "Invalid data key")
end
function Data.Keys(value)
	local strings, numbers, maxIndex = 0, 0, 0
	for key in value do
		Data.Key(key)
		if type(key) == "number" then numbers += 1; maxIndex = math.max(maxIndex, key) else strings += 1 end
	end
	assert(numbers == 0 or (strings == 0 and numbers == maxIndex), "Data tables must be dictionaries or dense arrays")
end
function Data.Copy(value, ancestors)
	local kind = type(value)
	if kind == "number" then assert(value == value and math.abs(value) < math.huge, "Data numbers must be finite") end
	assert(kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" or kind == "table", "Unsupported data value")
	if kind ~= "table" then return value end
	ancestors = ancestors or {}
	assert(not ancestors[value], "Data cannot contain cycles")
	ancestors[value] = true
	Data.Keys(value)
	local copy = {}
	for key, child in value do
		copy[key] = Data.Copy(child, ancestors)
	end
	ancestors[value] = nil
	return copy
end
function Data.Parent(root, segments)
	if type(segments) ~= "table" or #segments == 0 then return nil end
	local current = root
	for index = 1, #segments - 1 do
		if type(current) ~= "table" then return nil end
		current = current[segments[index]]
	end
	if type(current) ~= "table" then return nil end
	return current, segments[#segments]
end
function Data.Path(segments)
	local parts = {}
	for i, key in segments do parts[i] = tostring(key) end
	return table.concat(parts, ".")
end
function Data.Version(version)
	return type(version) == "number" and version >= 0 and version < math.huge and version % 1 == 0
end
function Data.Equal(left, right)
	if type(left) ~= type(right) then return false end
	if type(left) ~= "table" then return left == right end
	for key, value in left do
		if not Data.Equal(value, right[key]) then return false end
	end
	for key in right do
		if left[key] == nil then return false end
	end
	return true
end

function Data.Segments(segments)
	assert(type(segments) == "table" and #segments > 0, "Data path is required")
	local count = 0
	for index, key in segments do
		assert(type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #segments, "Invalid path array")
		Data.Key(key)
		count += 1
	end
	assert(count == #segments, "Sparse data path")
end
return table.freeze(Data)
