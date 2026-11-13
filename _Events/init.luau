-- Fire starts scheduled work immediately; FireYield runs inline.
-- FireState retains the latest value; Observe replays it once if still current.
local Signal = require(script.Parent._Signal)
local signals, retained = {}, {}
local Events = {}

local function add(name, callback)
	assert(type(name) == "string" and name ~= "", "Event name is required")
	assert(type(callback) == "function", "Event callback is required")
	local signal = signals[name]
	if not signal then signal = Signal.new(); signals[name] = signal end
	local disconnectToken, token = signal:Connect(callback)

	local function disconnect()
		disconnectToken()
		if signals[name] == signal and signal:IsEmpty() then signals[name] = nil end
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
	local signal = signals[name]
	if not signal then return end
	if inline then signal:FireInline(table.unpack(values, 1, values.n))
	else signal:Fire(table.unpack(values, 1, values.n)) end
end

function Events.Fire(name, ...)
	fire(name, table.pack(...), false)
end

function Events.FireYield(name, ...)
	fire(name, table.pack(...), true)
end

function Events.FireState(name, ...)
	assert(type(name) == "string" and name ~= "", "Event name is required")
	local values = table.pack(...)
	retained[name] = values
	fire(name, values, false)
end

function Events.ClearState(name)
	retained[name] = nil
end

function Events.HasState(name)
	return retained[name] ~= nil
end

-- Used by data change projection to visit only paths with actual listeners.
function Events.Subscribed(prefix)
	local names = {}
	for name in signals do
		if string.sub(name, 1, #prefix) == prefix then table.insert(names, name) end
	end

	table.sort(names)
	return names
end

-- The listener lives only as long as the wait: a thread resumed or cancelled by someone else is left alone.
function Events.Wait(name)
	local thread = coroutine.running()
	local disconnect = Events.Once(name, function(...)
		if coroutine.status(thread) == "suspended" then task.spawn(thread, ...) end
	end)

	local values = table.pack(coroutine.yield())
	disconnect()
	return table.unpack(values, 1, values.n)
end

function Events.WaitState(name)
	local values = retained[name]
	if values then return table.unpack(values, 1, values.n) end
	return Events.Wait(name)
end

return table.freeze(Events)
