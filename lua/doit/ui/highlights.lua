local vim = vim

local M = {}

local ns_id = vim.api.nvim_create_namespace("doit")
local highlight_cache = {}

function M.setup_highlights()
	highlight_cache = {} -- Clear any old cache

	vim.api.nvim_set_hl(0, "DoItPending", { link = "Question", default = true })
	vim.api.nvim_set_hl(0, "DoItDone", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "DoItHelpText", { link = "Directory", default = true })
	vim.api.nvim_set_hl(0, "DoItTimestamp", { link = "Comment", default = true })

	highlight_cache.pending = "DoItPending"
	highlight_cache.done = "DoItDone"
	highlight_cache.help = "DoItHelpText"
end

function M.get_namespace_id()
	return ns_id
end

function M.get_priority_highlight(priorities, config)
	if not priorities or (type(priorities) == "string" and priorities == "") then
		return highlight_cache.pending
	end
	
	-- Handle the new string format for priority
	local priority_name = nil
	if type(priorities) == "string" then
		priority_name = priorities
	elseif type(priorities) == "table" and #priorities > 0 then
		-- Backward compatibility during migration
		priority_name = priorities[1]
	else
		return highlight_cache.pending
	end

	-- Sort groups by size, descending
	local sorted_groups = {}
	for name, group in pairs(config.options.priority_groups or {}) do
		table.insert(sorted_groups, { name = name, group = group })
	end
	table.sort(sorted_groups, function(a, b)
		return #a.group.members > #b.group.members
	end)

	-- Check each group to see if the priority is a member
	for _, group_data in ipairs(sorted_groups) do
		local group = group_data.group
		
		for _, member in ipairs(group.members) do
			if priority_name == member then
				-- Create a cache key
				local cache_key = member
				if highlight_cache[cache_key] then
					return highlight_cache[cache_key]
				end

				local hl_group = highlight_cache.pending
				if group.color and type(group.color) == "string" and group.color:match("^#%x%x%x%x%x%x$") then
					local hl_name = "doit" .. group.color:gsub("#", "")
					vim.api.nvim_set_hl(0, hl_name, { fg = group.color })
					hl_group = hl_name
				elseif group.hl_group then
					hl_group = group.hl_group
				end

				highlight_cache[cache_key] = hl_group
				return hl_group
			end
		end
	end

	return highlight_cache.pending
end

return M
