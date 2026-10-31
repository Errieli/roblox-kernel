-- Turns one data write into Data.Changed/Added/Removed events for the paths it affected.
local DataTree = require(script.Parent._DataTree)

local EVENT_KINDS = {"Changed", "Added", "Removed"}

local DataChanges = {}

local function descendant(root, suffix)
	local current = root
	for part in string.gmatch(suffix, "[^.]+") do
		if type(current) ~= "table" then return nil end
		local key = current[part] ~= nil and part or tonumber(part)
		if key == nil then return nil end
		current = current[key]
	end
	return current
end

-- The written path plus every subscribed path below it.
local function affectedPaths(events, path, prefix)
	local paths = {[path] = true}
	for _, kind in EVENT_KINDS do
		local eventPrefix = "Data." .. kind .. ":"
		for _, name in events.Subscribed(eventPrefix) do
			local candidate = string.sub(name, #eventPrefix + 1)
			if path == "" or string.sub(candidate, 1, #prefix) == prefix then paths[candidate] = true end
		end
	end
	return paths
end

-- Detached before and after values of each path that really changed, in path order.
local function computeTransitions(paths, path, prefix, value, old)
	local transitions = {}
	for candidate in paths do
		if candidate == "" then continue end
		local nextValue, previous = value, old
		if candidate ~= path then
			local suffix = string.sub(candidate, #prefix + 1)
			nextValue, previous = descendant(value, suffix), descendant(old, suffix)
		end
		if not DataTree.Equal(nextValue, previous) then
			table.insert(transitions, {Path = candidate, Value = DataTree.Copy(nextValue), Old = DataTree.Copy(previous)})
		end
	end
	table.sort(transitions, function(left, right) return left.Path < right.Path end)
	return transitions
end

-- Server listeners also receive the profile: first on Changed, last on Added and Removed.
local function dispatch(events, change, profile)
	local path, value, old = change.Path, change.Value, change.Old
	-- Copied now: Changed listeners own value and old, and may edit them.
	local classification, payload
	if old == nil then classification, payload = "Data.Added:", DataTree.Copy(value)
	elseif value == nil then classification, payload = "Data.Removed:", DataTree.Copy(old) end

	if profile then events.Fire("Data.Changed:" .. path, profile, value, old)
	else events.Fire("Data.Changed:" .. path, value, old) end
	if not classification then return end
	if profile then events.Fire(classification .. path, payload, profile)
	else events.Fire(classification .. path, payload) end
end

function DataChanges.Emit(events, segments, value, old, profile)
	local path = DataTree.JoinPath(segments)
	local prefix = path == "" and "" or path .. "."
	local paths = affectedPaths(events, path, prefix)
	for _, change in computeTransitions(paths, path, prefix, value, old) do
		dispatch(events, change, profile)
	end
end

return table.freeze(DataChanges)
