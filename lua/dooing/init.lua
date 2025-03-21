local M = {}

-- Existing requires
local config = require("dooing.config")
local state = require("dooing.state")

-- New requires for refactored UI modules
local ui = require("dooing.ui")
local main_window = ui.main_window
local todo_actions = ui.todo_actions

-- Expose modules for testing
M.state = state
M.ui = ui

function M.setup(opts)
	-- Set up user config
	config.setup(opts)
	-- Load todos from state
	state.load_todos()

	-- Primary user command: :Dooing
	vim.api.nvim_create_user_command("Dooing", function(opts)
		local args = vim.split(opts.args, "%s+", { trimempty = true })
		if #args == 0 then
			-- No args => toggle the main todo window
			main_window.toggle_todo_window()
			return
		end

		local command = args[1]
		table.remove(args, 1) -- Remove the command from the front

		if command == "add" then
			--------------------------------------------------
			-- Dooing add [arguments...]
			--------------------------------------------------
			-- Possible usage:
			-- :Dooing add some text
			-- :Dooing add -p priority1,priority2 "some text"
			--
			-- This block handles parsing out -p / --priorities and then
			-- adds the todo to state
			local priorities = nil
			local todo_text = ""

			local i = 1
			while i <= #args do
				if args[i] == "-p" or args[i] == "--priorities" then
					-- If we see -p or --priorities, the next item in args
					-- is a comma-separated list of priorities
					if i + 1 <= #args then
						local priority_str = args[i + 1]
						local priority_list = vim.split(priority_str, ",", { trimempty = true })

						local valid_priorities = {}
						local invalid_priorities = {}
						for _, p in ipairs(priority_list) do
							local is_valid = false
							for _, config_p in ipairs(config.options.priorities) do
								if p == config_p.name then
									is_valid = true
									table.insert(valid_priorities, p)
									break
								end
							end
							if not is_valid then
								table.insert(invalid_priorities, p)
							end
						end

						if #invalid_priorities > 0 then
							vim.notify(
								"Invalid priorities: " .. table.concat(invalid_priorities, ", "),
								vim.log.levels.WARN,
								{ title = "Dooing" }
							)
						end

						if #valid_priorities > 0 then
							priorities = valid_priorities
						end

						i = i + 2 -- Skip past the flag and its argument
					else
						vim.notify(
							"Missing priority value after " .. args[i],
							vim.log.levels.ERROR,
							{ title = "Dooing" }
						)
						return
					end
				else
					-- Everything else is part of the to-do text
					todo_text = todo_text .. " " .. args[i]
					i = i + 1
				end
			end

			todo_text = vim.trim(todo_text)
			if todo_text ~= "" then
				-- Actually add the todo
				state.add_todo(todo_text, priorities)

				local msg = "Todo created: " .. todo_text
				if priorities then
					msg = msg .. " (priorities: " .. table.concat(priorities, ", ") .. ")"
				end
				vim.notify(msg, vim.log.levels.INFO, { title = "Dooing" })
			end
		elseif command == "list" then
			--------------------------------------------------
			-- Dooing list
			--------------------------------------------------
			-- Shows all todos, printed with `:messages`
			for i, todo in ipairs(state.todos) do
				local status = todo.done and "✓" or "○"

				-- Collect metadata
				local metadata = {}
				if todo.priorities and #todo.priorities > 0 then
					table.insert(metadata, "priorities: " .. table.concat(todo.priorities, ", "))
				end
				if todo.due_date then
					table.insert(metadata, "due: " .. todo.due_date)
				end
				if todo.estimated_hours then
					table.insert(metadata, string.format("estimate: %.1fh", todo.estimated_hours))
				end

				local score = state.get_priority_score(todo)
				table.insert(metadata, string.format("score: %.1f", score))

				local metadata_text = #metadata > 0 and (" (" .. table.concat(metadata, ", ") .. ")") or ""

				vim.notify(string.format("%d. %s %s%s", i, status, todo.text, metadata_text), vim.log.levels.INFO)
			end
		elseif command == "set" then
			--------------------------------------------------
			-- Dooing set <index> <field> <value>
			--------------------------------------------------
			-- Example usage:
			-- :Dooing set 3 priorities p1,p2
			-- :Dooing set 2 ect 2h
			--
			if #args < 3 then
				vim.notify("Usage: Dooing set <index> <field> <value>", vim.log.levels.ERROR)
				return
			end

			local index = tonumber(args[1])
			if not index or not state.todos[index] then
				vim.notify("Invalid todo index: " .. args[1], vim.log.levels.ERROR)
				return
			end

			local field = args[2]
			local value = args[3]

			if field == "priorities" then
				-- If user typed "nil", it means clear priorities
				if value == "nil" then
					state.todos[index].priorities = nil
					state.save_todos()
					vim.notify("Cleared priorities for todo " .. index, vim.log.levels.INFO)
				else
					local priority_list = vim.split(value, ",", { trimempty = true })
					local valid_priorities = {}
					local invalid_priorities = {}

					for _, p in ipairs(priority_list) do
						local is_valid = false
						for _, config_p in ipairs(config.options.priorities) do
							if p == config_p.name then
								is_valid = true
								table.insert(valid_priorities, p)
								break
							end
						end
						if not is_valid then
							table.insert(invalid_priorities, p)
						end
					end

					if #invalid_priorities > 0 then
						vim.notify(
							"Invalid priorities: " .. table.concat(invalid_priorities, ", "),
							vim.log.levels.WARN
						)
					end

					if #valid_priorities > 0 then
						state.todos[index].priorities = valid_priorities
						state.save_todos()
						vim.notify("Updated priorities for todo " .. index, vim.log.levels.INFO)
					end
				end
			elseif field == "ect" then
				-- Use the parse_time_estimation from the newly refactored todo_actions
				local hours, err = todo_actions.parse_time_estimation(value)
				if hours then
					state.todos[index].estimated_hours = hours
					state.save_todos()
					vim.notify("Updated estimated completion time for todo " .. index, vim.log.levels.INFO)
				else
					vim.notify("Error: " .. (err or "Invalid time format"), vim.log.levels.ERROR)
				end
			else
				vim.notify("Unknown field: " .. field, vim.log.levels.ERROR)
			end
		else
			-- If no recognized subcommand, just toggle the window
			main_window.toggle_todo_window()
		end
	end, {
		desc = "Toggle Todo List window or add new todo",
		nargs = "*",
		complete = function(arglead, cmdline, cursorpos)
			local args = vim.split(cmdline, "%s+", { trimempty = true })
			if #args <= 2 then
				return { "add", "list", "set" }
			elseif args[1] == "set" and #args == 3 then
				return { "priorities", "ect" }
			elseif args[1] == "set" and (args[3] == "priorities") then
				local priorities = { "nil" } -- Let user type "nil" to clear
				for _, p in ipairs(config.options.priorities) do
					table.insert(priorities, p.name)
				end
				return priorities
			elseif args[#args - 1] == "-p" or args[#args - 1] == "--priorities" then
				-- Return available priorities for completion
				local priorities = {}
				for _, p in ipairs(config.options.priorities) do
					table.insert(priorities, p.name)
				end
				return priorities
			elseif #args == 3 then
				return { "-p", "--priorities" }
			end
			return {}
		end,
	})

	-- Optional keymap for toggling the window
	if config.options.keymaps.toggle_window then
		vim.keymap.set("n", config.options.keymaps.toggle_window, function()
			main_window.toggle_todo_window()
		end, { desc = "Toggle Todo List" })
	end
end

return M
