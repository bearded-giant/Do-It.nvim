-- Maintains priority weights cache and calculates a todo's score.

local vim = vim

local Priorities = {}

function Priorities.setup(M, config)
	-- Priority weights cache
	local priority_weights = {}

	-- Rebuild the cache from config
	function M.update_priority_weights()
		priority_weights = {}
		if config.options.priorities and type(config.options.priorities) == "table" then
			for _, p in ipairs(config.options.priorities) do
				priority_weights[p.name] = p.weight or 1
			end
		end
	end

	-- Get priority score for a single todo
	function M.get_priority_score(todo)
		if todo.done then
			return 0
		end

		if not config.options.priorities or #config.options.priorities == 0 then
			return 0
		end

		local score = 0
		if todo.priorities and type(todo.priorities) == "table" then
			for _, prio_name in ipairs(todo.priorities) do
				score = score + (priority_weights[prio_name] or 0)
			end
		end

		-- Estimated completion time multiplier
		local ect_multiplier = 1
		if todo.estimated_hours and todo.estimated_hours > 0 then
			local factor = config.options.hour_score_value
			ect_multiplier = 1 / (todo.estimated_hours * factor)
		end

		return score * ect_multiplier
	end
end

return Priorities
