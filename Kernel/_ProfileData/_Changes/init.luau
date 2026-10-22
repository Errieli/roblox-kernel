local Data = require(script.Parent)
local Changes = {}

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

function Changes.Emit(events, segments, value, old, profile)
	local path = Data.Path(segments)
	local prefix = path == "" and "" or path .. "."
	local paths = {[path] = true}
	for _, kind in {"Changed", "Added", "Removed"} do
		local eventPrefix = "Data." .. kind .. ":"
		for _, name in events.Subscribed(eventPrefix) do
			local candidate = string.sub(name, #eventPrefix + 1)
			if path == "" or string.sub(candidate, 1, #prefix) == prefix then paths[candidate] = true end
		end
	end
	local transitions = {}
	for candidate in paths do
		if candidate == "" then continue end
		local nextValue, previous = value, old
		if candidate ~= path then
			local suffix = string.sub(candidate, #prefix + 1)
			nextValue, previous = descendant(value, suffix), descendant(old, suffix)
		end
		if not Data.Equal(nextValue, previous) then
			table.insert(transitions, {Path = candidate, Value = Data.Copy(nextValue), Old = Data.Copy(previous)})
		end
	end
	table.sort(transitions, function(a, b) return a.Path < b.Path end)
	for _, change in transitions do
		if profile then events.Fire("Data.Changed:" .. change.Path, profile, Data.Copy(change.Value), Data.Copy(change.Old))
		else events.Fire("Data.Changed:" .. change.Path, Data.Copy(change.Value), Data.Copy(change.Old)) end
		local name, payload
		if change.Old == nil then name, payload = "Data.Added:", change.Value
		elseif change.Value == nil then name, payload = "Data.Removed:", change.Old end
		if name then
			if profile then events.Fire(name .. change.Path, Data.Copy(payload), profile)
			else events.Fire(name .. change.Path, Data.Copy(payload)) end
		end
	end
end

return table.freeze(Changes)
