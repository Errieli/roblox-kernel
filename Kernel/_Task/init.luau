local Task = {}

function Task.Cancel(target)
	if typeof(target) ~= "thread" or target == coroutine.running() or coroutine.status(target) == "dead" then return false end
	local success, message = pcall(task.cancel, target)
	if not success then
		warn("Unable to cancel task: " .. tostring(message))
	end
	return success
end

Task.Spawn = task.spawn
Task.Defer = task.defer
Task.Delay = task.delay
Task.Wait = task.wait

return table.freeze(Task)