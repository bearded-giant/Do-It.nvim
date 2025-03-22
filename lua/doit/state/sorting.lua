-- Sort the todo list by done-ness, priority score, due date, etc.

local Sorting = {}

function Sorting.setup(M, config)
	function M.sort_todos()
		table.sort(M.todos, function(a, b)
			-- 1) Sort by completion
			if a.done ~= b.done then
				return not a.done
			end

			-- 2) Sort by order_index if both have it
			if a.order_index and b.order_index then
				return a.order_index < b.order_index
			elseif a.order_index then
				return true
			elseif b.order_index then
				return false
			end

			-- 3) Sort by priority score
			if config.options.priorities and #config.options.priorities > 0 then
				local a_score = M.get_priority_score(a) -- from priorities.lua
				local b_score = M.get_priority_score(b)
				if a_score ~= b_score then
					return a_score > b_score
				end
			end

			-- 4) Sort by due date
			if a.due_at and b.due_at then
				if a.due_at ~= b.due_at then
					return a.due_at < b.due_at
				end
			elseif a.due_at then
				return true
			elseif b.due_at then
				return false
			end

			-- 5) Sort by creation time
			return a.created_at < b.created_at
		end)
	end
end

return Sorting
