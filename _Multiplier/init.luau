local Signal = require(script.Parent._Signal)

type callback = (Name: string, Value: number) -> ()

type self = {
	_cache: {[string]: number},
	_types: {[string]: {[string]: number}},
	_changed: typeof(Signal.new()),
}

local Multipliers = {}
type Multipliers = setmetatable<self, typeof(Multipliers)>
Multipliers.__index = Multipliers

local function calculate(values: {[string]: number})
	local total = 1

	for _, value in pairs(values) do
		total *= value
	end

	return total
end

function Multipliers.Set(self: Multipliers, typeName: string, source: string, value: number?)
	if not self._types[typeName] then
		self._types[typeName] = {}
	end

	local types = self._types[typeName]
	if types[source] == value then return end

	types[source] = value

	local newValue = calculate(types)
	self._cache[typeName] = newValue

	self._changed:FireInline(typeName, newValue)
end

function Multipliers.Get(self: Multipliers, typeName: string)
	return self._cache[typeName] or 1
end

function Multipliers.GetSource(self: Multipliers, typeName: string, source: string): number?
	local typeTable = self._types[typeName]
	if not typeTable then return nil end

	return typeTable[source]
end

function Multipliers.Changed(self: Multipliers, callback: callback)
	return (self._changed:Connect(callback))
end

return function(): Multipliers
	local data = {
		_cache = {},
		_types = {},
		_changed = Signal.new(),
	}

	return setmetatable(data, Multipliers)
end
