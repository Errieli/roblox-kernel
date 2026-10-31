-- Internal listener list shared by Events, Players, Multiplier and client Reply.
-- Every Connect is an independent token. Dispatch walks a snapshot in insertion
-- order, so callbacks may connect or disconnect while an emission is running.
local Task = require(script.Parent._Task)

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({_tokens = {}}, Signal)
end

function Signal:Connect(callback)
	assert(type(callback) == "function", "Signal callback must be a function")
	local tokens = self._tokens
	local token = {Callback = callback, Connected = true}
	table.insert(tokens, token)

	local function disconnect()
		if not token.Connected then return end
		token.Connected = false
		local index = table.find(tokens, token)
		if index then table.remove(tokens, index) end
	end

	return disconnect, token
end

function Signal:IsEmpty()
	return #self._tokens == 0
end

local function dispatch(self, deliver, ...)
	local tokens = self._tokens
	if #tokens == 0 then return false end
	for _, token in table.clone(tokens) do
		if token.Connected then deliver(token, ...) end
	end

	return true
end

local function spawnToken(token, ...)
	Task.Run(token.Callback, ...)
end

local function callToken(token, ...)
	token.Callback(...)
end

local function deferToken(token, ...)
	task.defer(function(...)
		if token.Connected then token.Callback(...) end
	end, ...)
end

-- Each Fire variant returns whether any listener was connected.
function Signal:Fire(...)
	return dispatch(self, spawnToken, ...)
end

function Signal:FireInline(...)
	return dispatch(self, callToken, ...)
end

-- Deferred delivery skips tokens disconnected before their turn.
function Signal:FireDeferred(...)
	return dispatch(self, deferToken, ...)
end

return table.freeze(Signal)
