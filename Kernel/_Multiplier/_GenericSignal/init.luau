type callback = (...any) -> ()

type self = {
	_listeners: {[callback]: true}
}

local Signal = {}
export type Signal = setmetatable<self, typeof(Signal)>
Signal.__index = Signal

function Signal.Connect(self: Signal, fn: callback)
	self._listeners[fn] = true

	return function()
		self._listeners[fn] = nil
	end
end

function Signal.Fire(self: Signal, ...)
	for fn in self._listeners do
		fn(...)
	end
end

function Signal:Destroy()
	setmetatable(self, nil)
end

return function(): Signal
	local data = {
		_listeners = {}
	}
	
	return setmetatable(data, Signal)
end