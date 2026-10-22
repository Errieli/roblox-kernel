local function formatTime(seconds: number?): string
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))

	local minutes = math.floor(seconds / 60)
	local remainder = seconds % 60

	return string.format("%02d:%02d", minutes, remainder)
end

return formatTime