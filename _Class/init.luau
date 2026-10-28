export type Destructor <T> = (self: T) -> ()
export type Constructor <T, Args...> = (self: T, Args...) -> (boolean?)

export type Create <T, Args...> = {
	Constructor: Constructor<T, Args...>?,
	Destructor: Destructor<T>?,
	[string]: any
}

return function <T, Args...> (class: Create <T, Args...>): (Args...) -> (T?)
	class.__index = class

	if class.Destructor then
		function class:Destroy()
			self:Destructor()
			setmetatable(self, nil)
		end
	else
		function class:Destroy()
			setmetatable(self, nil)
		end
	end

	if class.Constructor then
		return function(...)
			local data = {}

			if not class.Constructor(data, ...) then return nil end

			return setmetatable(data, class)
		end
	else
		return function()
			return setmetatable({}, class)
		end
	end
end