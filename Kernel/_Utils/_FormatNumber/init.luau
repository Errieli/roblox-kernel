local FormatNumber = {}

function FormatNumber.Round(value)
	return math.floor((tonumber(value) or 0) + 0.5)
end

function FormatNumber.Compact(value)
	value = FormatNumber.Round(value)

	if value >= 1000000 then
		local text = string.format("%.1fM", value / 1000000)
		return (text:gsub("%.0M", "M"))
	end

	if value >= 1000 then
		local text = string.format("%.1fK", value / 1000)
		return (text:gsub("%.0K", "K"))
	end

	return tostring(value)
end

return table.freeze(FormatNumber)