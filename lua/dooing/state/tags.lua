-- Tag-related operations: get all tags, rename, delete, set filter, etc.

local Tags = {}

function Tags.setup(M, config)
	-- Gather all unique tags from todos
	function M.get_all_tags()
		local tags = {}
		local seen = {}
		for _, todo in ipairs(M.todos) do
			for tag in todo.text:gmatch("#(%w+)") do
				if not seen[tag] then
					seen[tag] = true
					table.insert(tags, tag)
				end
			end
		end
		table.sort(tags)
		return tags
	end

	-- Set the active filter
	function M.set_filter(tag)
		M.active_filter = tag
	end

	-- Rename a tag in all todos
	function M.rename_tag(old_tag, new_tag)
		for _, todo in ipairs(M.todos) do
			todo.text = todo.text:gsub("#" .. old_tag, "#" .. new_tag)
		end
		M.save_to_disk()
	end

	-- Delete a tag from all todos
	function M.delete_tag(tag)
		for _, todo in ipairs(M.todos) do
			-- Replace the tag if present
			-- e.g. remove "#tag " or "#tag$" at line-end
			todo.text = todo.text:gsub("#" .. tag .. "(%s)", "%1")
			todo.text = todo.text:gsub("#" .. tag .. "$", "")
		end
		M.save_to_disk()
	end
end

return Tags
