-- Maintains priority weights cache and calculates a todo's score.

local vim = vim

local Priorities = {}

function Priorities.setup(M, config)
	local priority_weights = {}

	function M.update_priority_weights()
		priority_weights = {}
		if config.options.priorities and type(config.options.priorities) == "table" then
			for _, p in ipairs(config.options.priorities) do
				priority_weights[p.name] = p.weight or 1
			end
		end
	end

	function M.get_priority_score(todo)
		if todo.done then
			return 0
		end

		if not config.options.priorities or #config.options.priorities == 0 then
			return 0
		end

		local score = 0
		if todo.priorities then
			if type(todo.priorities) == "string" then
				-- New format: single priority string
				score = priority_weights[todo.priorities] or 0
			elseif type(todo.priorities) == "table" then
				-- For backward compatibility during migration
				for _, prio_name in ipairs(todo.priorities) do
					score = score + (priority_weights[prio_name] or 0)
				end
			end
		end

		-- Est time completion multiplier
		local ect_multiplier = 1
		if todo.estimated_hours and todo.estimated_hours > 0 then
			local factor = config.options.hour_score_value
			ect_multiplier = 1 / (todo.estimated_hours * factor)
		end

		return score * ect_multiplier
	end
end

return Priorities