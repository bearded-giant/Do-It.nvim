-- EZ text-based search over todos

local Search = {}

function Search.setup(M, config)
	function M.search_todos(query)
		local results = {}
		query = query:lower()

		for index, todo in ipairs(M.todos) do
			if todo.text:lower():find(query) then
				table.insert(results, {
					lnum = index,
					todo = todo,
				})
			end
		end

		return results
	end
end

return Search
