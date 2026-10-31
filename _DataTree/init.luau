-- Rules for persisted and replicated values, which form a tree of finite numbers,
-- strings, booleans, dense arrays and string dictionaries. A path is an array of
-- typed segments, so numeric keys survive. Assert* functions raise; Is* functions answer.
local DataTree = {Protocol = 1}

function DataTree.AssertKey(key)
	assert((type(key) == "string" and key ~= "") or (type(key) == "number" and key >= 1 and key < math.huge and key % 1 == 0), "Invalid data key")
end

function DataTree.AssertShape(value)
	local strings, numbers, maxIndex = 0, 0, 0
	for key in value do
		DataTree.AssertKey(key)
		if type(key) == "number" then numbers += 1; maxIndex = math.max(maxIndex, key) else strings += 1 end
	end
	assert(numbers == 0 or (strings == 0 and numbers == maxIndex), "Data tables must be dictionaries or dense arrays")
end

function DataTree.AssertPath(path)
	assert(type(path) == "table" and #path > 0, "Data path is required")
	local count = 0
	for index, key in path do
		assert(type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #path, "Invalid path array")
		DataTree.AssertKey(key)
		count += 1
	end
	assert(count == #path, "Sparse data path")
end

function DataTree.IsVersion(version)
	return type(version) == "number" and version >= 0 and version < math.huge and version % 1 == 0
end

local function copy(value, ancestors)
	local kind = type(value)
	if kind == "number" then assert(value == value and math.abs(value) < math.huge, "Data numbers must be finite") end
	assert(kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" or kind == "table", "Unsupported data value")
	if kind ~= "table" then return value end
	ancestors = ancestors or {}
	assert(not ancestors[value], "Data cannot contain cycles")
	ancestors[value] = true
	DataTree.AssertShape(value)
	local result = {}
	for key, child in value do
		result[key] = copy(child, ancestors)
	end
	ancestors[value] = nil
	return result
end

-- Detached copy of a value, raising if it is not a valid tree.
function DataTree.Copy(value)
	return copy(value)
end

-- Raises if the value is not a valid tree; for when the copy itself is not needed.
function DataTree.Validate(value)
	copy(value)
end

function DataTree.Equal(left, right)
	if type(left) ~= type(right) then return false end
	if type(left) ~= "table" then return left == right end
	for key, value in left do
		if not DataTree.Equal(value, right[key]) then return false end
	end
	for key in right do
		if left[key] == nil then return false end
	end
	return true
end

-- The table holding the path's last segment and that segment, or nil if a parent is missing.
function DataTree.Parent(root, path)
	if type(path) ~= "table" or #path == 0 then return nil end
	local current = root
	for index = 1, #path - 1 do
		if type(current) ~= "table" then return nil end
		current = current[path[index]]
	end
	if type(current) ~= "table" then return nil end
	return current, path[#path]
end

-- The dotted form used in event names and messages.
function DataTree.JoinPath(path)
	local parts = {}
	for index, key in path do parts[index] = tostring(key) end
	return table.concat(parts, ".")
end

return table.freeze(DataTree)
