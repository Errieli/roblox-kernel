local Task = {}

function Task.Cancel(target)
	if typeof(target) ~= "thread" or target == coroutine.running() or coroutine.status(target) == "dead" then return false end
	local success, message = pcall(task.cancel, target)
	if not success then
		warn("Unable to cancel task: " .. tostring(message))
	end

	return success
end

-- Run calls back on a reused runner thread instead of creating one per call.
-- A callback that yields keeps the runner and the next call gets a new one;
-- one that errors kills its runner. The thread is shared, so none is returned.
local freeRunner: thread? = nil

local function acquireAndCall(callback, ...)
	local runner = freeRunner
	freeRunner = nil
	callback(...)
	freeRunner = runner
end

local function runLoop(...)
	acquireAndCall(...)
	while true do
		acquireAndCall(coroutine.yield())
	end
end

function Task.Run(callback, ...)
	-- A free runner cancelled from outside is dead and must be replaced.
	if not freeRunner or coroutine.status(freeRunner) == "dead" then
		freeRunner = coroutine.create(runLoop)
	end

	task.spawn(freeRunner, callback, ...)
end

Task.Spawn = task.spawn
Task.Defer = task.defer
Task.Delay = task.delay
Task.Wait = task.wait

return table.freeze(Task)