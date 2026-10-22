local SectionList = {}

function SectionList.GetItemKeys(groups)
	local keys = {}

	for _, group in groups do
		for _, item in group.Items do
			keys[#keys + 1] = item.Key
		end
	end

	return keys
end

function SectionList.Render(options)
	local groups = options.Groups or {}
	local order = options.StartOrder or 1

	if options.BeforeRender then
		options.BeforeRender()
	end

	for _, group in groups do
		if options.CreateTitle then
			options.CreateTitle(group.Title, order, group)
			order += 1
		end

		for _, item in group.Items do
			options.CreateItem(item, order, group)
			order += 1
		end
	end

	local reset = options.Reset
	if reset then
		if options.CreateTitle then
			options.CreateTitle(reset.Title or "Reset", order, reset)
			order += 1
		end

		if options.CreateAction then
			options.CreateAction(reset, order)
			order += 1
		end
	end

	if options.ConnectItem then
		for _, group in groups do
			for _, item in group.Items do
				options.ConnectItem(item, group)
			end
		end
	end

	return order
end

return table.freeze(SectionList)