return function(render, cleanup)
	local active = false
	local dirty = true

	const function refresh(...)
		if not active then
			dirty = true
			return false
		end

		dirty = false
		render(...)

		return true
	end

	const function open(...)
		active = true
		if dirty then refresh(...) end
	end

	const function close()
		active = false
		dirty = true
		if cleanup then cleanup() end
	end

	return {
		Close = close,
		IsActive = function()
			return active
		end,
		MarkDirty = function()
			dirty = true
		end,
		Open = open,
		Refresh = refresh,
	}
end