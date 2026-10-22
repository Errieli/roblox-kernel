local GuiTemplates = {}

function GuiTemplates.Detach(template)
	template.Parent = nil
	return template
end

return table.freeze(GuiTemplates)