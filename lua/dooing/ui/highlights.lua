local vim = vim

local M = {}

-- Our main namespace for dooing highlights
local ns_id = vim.api.nvim_create_namespace("dooing")
-- Cache for highlight groups
local highlight_cache = {}

-- Set up base highlights
function M.setup_highlights()
	highlight_cache = {} -- Clear any old cache

	vim.api.nvim_set_hl(0, "DooingPending", { link = "Question", default = true })
	vim.api.nvim_set_hl(0, "DooingDone", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "DooingHelpText", { link = "Directory", default = true })
	vim.api.nvim_set_hl(0, "DooingTimestamp", { link = "Comment", default = true })

	highlight_cache.pending = "DooingPending"
	highlight_cache.done = "DooingDone"
	highlight_cache.help = "DooingHelpText"
end

-- Return the highlight cache's namespace
function M.get_namespace_id()
	return ns_id
end

-- Return a highlight group for a set of priorities
function M.get_priority_highlight(priorities, config)
	if not priorities or #priorities == 0 then
		return highlight_cache.pending
	end

	-- Sort config priority groups by size, descending
	local sorted_groups = {}
	for name, group in pairs(config.options.priority_groups or {}) do
		table.insert(sorted_groups, { name = name, group = group })
	end
	table.sort(sorted_groups, function(a, b)
		return #a.group.members > #b.group.members
	end)

	-- Check each group to see if all members match
	for _, group_data in ipairs(sorted_groups) do
		local group = group_data.group
		local all_members_match = true
		for _, member in ipairs(group.members) do
			local found = false
			for _, priority in ipairs(priorities) do
				if priority == member then
					found = true
					break
				end
			end
			if not found then
				all_members_match = false
				break
			end
		end

		if all_members_match then
			-- Create a cache key
			local cache_key = table.concat(group.members, "_")
			if highlight_cache[cache_key] then
				return highlight_cache[cache_key]
			end

			local hl_group = highlight_cache.pending
			if group.color and type(group.color) == "string" and group.color:match("^#%x%x%x%x%x%x$") then
				local hl_name = "Dooing" .. group.color:gsub("#", "")
				vim.api.nvim_set_hl(0, hl_name, { fg = group.color })
				hl_group = hl_name
			elseif group.hl_group then
				hl_group = group.hl_group
			end

			highlight_cache[cache_key] = hl_group
			return hl_group
		end
	end

	return highlight_cache.pending
end

return M
