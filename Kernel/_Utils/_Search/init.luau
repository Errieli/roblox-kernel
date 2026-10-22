return function(query, ...)
	query = string.lower(query)
	if query == "" then return true end

	for index = 1, select("#", ...) do
		const value = select(index, ...)

		if string.find(string.lower(value), query, 1, true) then return true end
	end

	return false
end