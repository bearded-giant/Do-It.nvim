-- Sort the todo list by done-ness, in-progress status, priority score, due date, etc.

local Sorting = {}

-- Rank by the priority string directly (critical > urgent > important > none).
-- Config-independent so ordering matches the tmux view even when the weighted
-- priorities config is absent/nested. Higher rank sorts first.
local PRIORITY_RANK = {
	critical = 4,
	urgent = 3,
	important = 2,
}

local function priority_rank(todo)
	local p = todo.priorities
	if type(p) == "string" and p ~= "" then
		return PRIORITY_RANK[p] or 1
	elseif type(p) == "table" then
		local best = 1
		for _, name in ipairs(p) do
			best = math.max(best, PRIORITY_RANK[name] or 1)
		end
		return best
	end
	return 1
end

function Sorting.setup(M, config)
	function M.sort_todos()
		table.sort(M.todos, function(a, b)
			-- 1) Completed items last
			if a.done ~= b.done then
				return not a.done
			end

			if not a.done and not b.done then
				-- 2) In-progress items lead the list (matches tmux view)
				if a.in_progress ~= b.in_progress then
					return a.in_progress and not b.in_progress
				end

				-- 3) Priority rank (critical -> urgent -> important -> none)
				local a_rank = priority_rank(a)
				local b_rank = priority_rank(b)
				if a_rank ~= b_rank then
					return a_rank > b_rank
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

			-- 5) Preserve manual order, then creation time
			if a.order_index and b.order_index and a.order_index ~= b.order_index then
				return a.order_index < b.order_index
			end
			return (a.created_at or 0) < (b.created_at or 0)
		end)
	end
end

return Sorting
