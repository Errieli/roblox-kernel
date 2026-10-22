-- // Services
local Beat = require(script.Parent.Parent._Beat)

local debounces = {}

Beat.Heartbeat(0.05, function()
	local currentClock = os.clock()
	for key, endClock in debounces do
		if endClock <= currentClock then
			debounces[key] = nil
		end
	end
end)

-- Manages debouncing to prevent a function from being called too frequently. 
return function (key: any, timer: number?, needToReplace: boolean?)
	if not key then
		return warn(`Debounce Key is nil`)
	end

	if needToReplace and timer and debounces[key] then
		debounces[key] = os.clock() + timer
		return
	end

	if debounces[key] then return true end

	if not timer then return end

	debounces[key] = os.clock() + timer
end