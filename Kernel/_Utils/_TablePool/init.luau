type anyTable = {[any]: any?}

local pool: {anyTable} = {}

local TablePool = {}

function TablePool.Get(): (anyTable)
	local tab = pool[#pool]
	
	if tab then
		pool[#pool] = nil
		return tab
	end

	return {}
end

function TablePool.Release(tab: anyTable)
	table.clear(tab)
	pool[#pool + 1] = tab
end


return TablePool