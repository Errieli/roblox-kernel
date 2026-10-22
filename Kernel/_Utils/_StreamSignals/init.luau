-- // Services
local CS = game:GetService("CollectionService")

-- Streams objects with a specific tag, calling provided functions when instances are added or removed.
return function(tag, inFun, outFun: (any) -> ()?)
	CS:GetInstanceAddedSignal(tag):Connect(inFun)
	for _, part in CS:GetTagged(tag) do inFun(part) end
	if outFun then CS:GetInstanceRemovedSignal(tag):Connect(outFun) end
end