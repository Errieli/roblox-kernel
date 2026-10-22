local Group = {}

local DEFAULT_GROUP_ID = if game.CreatorType == Enum.CreatorType.Group then game.CreatorId else 0

local function getGroupId(groupId: number?): number
	return groupId or DEFAULT_GROUP_ID
end

function Group.GetRank(player: Player, groupId: number?): number
	local id = getGroupId(groupId)
	if id <= 0 then return 0 end

	local ok, rank = pcall(player.GetRankInGroup, player, id)
	return ok and rank or 0
end

function Group.IsMember(player: Player, groupId: number?): boolean
	return Group.GetRank(player, groupId) > 0
end

return Group
