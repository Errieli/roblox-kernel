-- Fire starts scheduled work immediately; FireYield runs inline.
-- FireState retains the latest value; Observe replays it once if still current.
local callbacks, retained = {}, {}
local Events = {}

local function add(name, callback)
	assert(type(name) == "string" and name ~= "", "Event name is required")
	assert(type(callback) == "function", "Event callback is required")
	local list = callbacks[name]
	if not list then list = {}; callbacks[name] = list end
	local token = {Callback = callback, Connected = true}
	list[token] = true
	local function disconnect()
		if not token.Connected then return end
		token.Connected = false
		list[token] = nil
		if not next(list) and callbacks[name] == list then callbacks[name] = nil end
	end
	return disconnect, token
end

function Events.Connect(name, callback)
	local disconnect = add(name, callback)
	return disconnect
end

function Events.Observe(name, callback)
	local disconnect, token = add(name, callback)
	local values = retained[name]
	if values then
		task.defer(function()
			if token.Connected and retained[name] == values then
				callback(table.unpack(values, 1, values.n))
			end
		end)
	end
	return disconnect
end

function Events.Once(name, callback)
	local disconnect
	disconnect = Events.Connect(name, function(...)
		disconnect()
		callback(...)
	end)
	return disconnect
end

local function fire(name, values, inline)
	assert(type(name) == "string" and name ~= "", "Event name is required")
	local list = callbacks[name]
	if not list then return end
	-- A callback may subscribe/unsubscribe while dispatching.
	local pending = {}
	for token in list do table.insert(pending, token) end
	for _, token in pending do
		if token.Connected then
			if inline then token.Callback(table.unpack(values, 1, values.n))
			else task.spawn(token.Callback, table.unpack(values, 1, values.n)) end
		end
	end
end

function Events.Fire(name, ...) fire(name, table.pack(...), false) end
function Events.FireYield(name, ...) fire(name, table.pack(...), true) end
function Events.FireState(name, ...)
	assert(type(name) == "string" and name ~= "", "Event name is required")
	local values = table.pack(...)
	retained[name] = values
	fire(name, values, false)
end
function Events.ClearState(name) retained[name] = nil end
function Events.HasState(name) return retained[name] ~= nil end
-- Used by data change projection to visit only paths with actual listeners.
function Events.Subscribed(prefix)
	local names = {}
	for name in callbacks do
		if string.sub(name, 1, #prefix) == prefix then table.insert(names, name) end
	end
	table.sort(names)
	return names
end
function Events.Wait(name)
	local thread = coroutine.running()
	Events.Once(name, function(...) task.spawn(thread, ...) end)
	return coroutine.yield()
end
function Events.WaitState(name)
	local values = retained[name]
	if values then return table.unpack(values, 1, values.n) end
	return Events.Wait(name)
end
return table.freeze(Events)
