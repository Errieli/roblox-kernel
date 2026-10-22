-- // Services
local CS = game:GetService("CollectionService")

type Callback = () -> ()

return function(tag: string, callback: (Instance) -> (Callback)?)
	local cleanups: {[Instance]: () -> ()} = {}

	local function handleAdd(inst: Instance)
		if cleanups[inst] then
			cleanups[inst]()
		end
		
		local cleanup = callback(inst)
		if cleanup then
			cleanups[inst] = cleanup
		end
	end

	local function handleRemove(inst: Instance)
		local cleanup = cleanups[inst]
		if cleanup then
			cleanup()
			cleanups[inst] = nil
		end
	end

	local addedConn = CS:GetInstanceAddedSignal(tag):Connect(handleAdd)
	local removedConn = CS:GetInstanceRemovedSignal(tag):Connect(handleRemove)

	for _, inst in CS:GetTagged(tag) do
		handleAdd(inst)
	end

	return function()
		addedConn:Disconnect()
		removedConn:Disconnect()

		for inst, cleanup in cleanups do
			cleanup()
			cleanups[inst] = nil
		end
	end
end