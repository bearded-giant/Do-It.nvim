-- Commands for the todos module
local M = {}

-- Setup function for commands
function M.setup(module)
    local commands = {}
    
    -- Main DoIt command
    commands.DoIt = {
        callback = function(opts)
            local state = module.state
            local config = module.config
            local main_window = module.ui.main_window
            
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
                -- doit add [arguments...]
                --------------------------------------------------
                -- Possible usage:
                -- :doit add some text
                -- :doit add -p priority1,priority2 "some text"
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
                                for _, config_p in ipairs(config.priorities) do
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
                                    { title = "doit" }
                                )
                            end

                            if #valid_priorities > 0 then
                                priorities = valid_priorities
                            end

                            i = i + 2 -- Skip past the flag and its argument
                        else
                            vim.notify("Missing priority value after " .. args[i], vim.log.levels.ERROR, { title = "doit" })
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
                    vim.notify(msg, vim.log.levels.INFO, { title = "doit" })
                end
            elseif command == "list" then
                --------------------------------------------------
                -- doit list
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
                -- doit set <index> <field> <value>
                --------------------------------------------------
                -- Example usage:
                -- :doit set 3 priorities p1,p2
                -- :doit set 2 ect 2h
                --
                if #args < 3 then
                    vim.notify("Usage: doit set <index> <field> <value>", vim.log.levels.ERROR)
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
                            for _, config_p in ipairs(config.priorities) do
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
                    -- Use the parse_time_estimation from todo_actions
                    local todo_actions = module.ui.todo_actions
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
        end,
        
        opts = {
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
                    for _, p in ipairs(module.config.priorities) do
                        table.insert(priorities, p.name)
                    end
                    return priorities
                elseif args[#args - 1] == "-p" or args[#args - 1] == "--priorities" then
                    -- Return available priorities for completion
                    local priorities = {}
                    for _, p in ipairs(module.config.priorities) do
                        table.insert(priorities, p.name)
                    end
                    return priorities
                elseif #args == 3 then
                    return { "-p", "--priorities" }
                end
                return {}
            end
        }
    }
    
    -- Move todo to another list
    commands.DoItTodoMove = {
        callback = function(opts)
            local args = opts.fargs
            if #args < 2 then
                vim.notify("Usage: DoItTodoMove <todo_index> <target_list>", vim.log.levels.ERROR)
                return
            end

            local todo_index = tonumber(args[1])
            local target_list = args[2]

            if not todo_index then
                vim.notify("Invalid todo index", vim.log.levels.ERROR)
                return
            end

            local success, msg = module.state.move_todo_to_list(todo_index, target_list)
            vim.notify(msg, success and vim.log.levels.INFO or vim.log.levels.ERROR)

            -- Refresh UI if open
            if success and module.ui.main_window and module.ui.main_window.render_todos then
                module.ui.main_window.render_todos()
            end
        end,
        opts = {
            desc = "Move a todo to another list",
            nargs = "+",
            complete = function(arglead, cmdline, cursorpos)
                local args = vim.split(cmdline, "%s+", { trimempty = true })
                if #args == 2 then
                    -- First arg: todo index (no completion needed)
                    return {}
                elseif #args == 3 then
                    -- Second arg: list names
                    local lists = module.state.get_available_lists()
                    local list_names = {}
                    for _, list in ipairs(lists) do
                        table.insert(list_names, list.name)
                    end
                    return list_names
                end
                return {}
            end
        }
    }

    -- Active Todo List command
    commands.DoItList = {
        callback = function()
            module.ui.list_window.toggle_list_window()
        end,
        opts = {
            desc = "Toggle Active Todos List window",
        }
    }
    
    -- Todo List Manager command
    commands.DoItLists = {
        callback = function(opts)
            if #opts.fargs == 0 then
                -- Toggle the list manager window
                module.ui.list_manager_window.toggle_window()
                return
            end
            
            local command = opts.fargs[1]
            table.remove(opts.fargs, 1)
            
            if command == "switch" or command == "use" then
                -- Switch to the specified list
                local list_name = opts.fargs[1]
                if not list_name then
                    vim.notify("Usage: DoItLists switch <list_name>", vim.log.levels.ERROR)
                    return
                end
                
                local success, msg = module.state.load_list(list_name)
                vim.notify(msg, success and vim.log.levels.INFO or vim.log.levels.ERROR)
                
                -- Refresh main window if open
                if module.ui.main_window and module.ui.main_window.render_todos then
                    module.ui.main_window.render_todos()
                end
            elseif command == "create" or command == "new" then
                -- Create a new list
                local list_name = opts.fargs[1]
                if not list_name then
                    vim.notify("Usage: DoItLists create <list_name>", vim.log.levels.ERROR)
                    return
                end
                
                local success, msg = module.state.create_list(list_name, {})
                vim.notify(msg, success and vim.log.levels.INFO or vim.log.levels.ERROR)
            elseif command == "delete" or command == "remove" then
                -- Delete a list
                local list_name = opts.fargs[1]
                if not list_name then
                    vim.notify("Usage: DoItLists delete <list_name>", vim.log.levels.ERROR)
                    return
                end
                
                local success, msg = module.state.delete_list(list_name)
                vim.notify(msg, success and vim.log.levels.INFO or vim.log.levels.ERROR)
                
                -- Refresh main window if open
                if module.ui.main_window and module.ui.main_window.render_todos then
                    module.ui.main_window.render_todos()
                end
            elseif command == "rename" then
                -- Rename a list
                local old_name = opts.fargs[1]
                local new_name = opts.fargs[2]
                if not old_name or not new_name then
                    vim.notify("Usage: DoItLists rename <old_name> <new_name>", vim.log.levels.ERROR)
                    return
                end
                
                local success, msg = module.state.rename_list(old_name, new_name)
                vim.notify(msg, success and vim.log.levels.INFO or vim.log.levels.ERROR)
                
                -- Refresh main window if open
                if module.ui.main_window and module.ui.main_window.render_todos then
                    module.ui.main_window.render_todos()
                end
            elseif command == "list" or command == "ls" then
                -- List available lists
                local lists = module.state.get_available_lists()
                local active_list = module.state.todo_lists.active
                
                if #lists == 0 then
                    vim.notify("No todo lists found", vim.log.levels.INFO)
                    return
                end
                
                -- Print each list name with active indicator
                for _, list in ipairs(lists) do
                    local active_marker = list.name == active_list and "* " or "  "
                    local todo_count = 0

                    -- Count active todos if this is the active list (exclude completed)
                    if list.name == active_list then
                        local todos = module.state.todos or {}
                        for _, todo in ipairs(todos) do
                            if not todo.done then
                                todo_count = todo_count + 1
                            end
                        end
                    end

                    local count_str = todo_count > 0 and string.format(" (%d todos)", todo_count) or ""
                    vim.notify(active_marker .. list.name .. count_str, vim.log.levels.INFO)
                end
            else
                -- Unknown subcommand, show usage
                vim.notify([[
Usage: DoItLists <command> [args...]

Commands:
  (no command)     Toggle the list manager window
  switch <name>    Switch to the specified list
  create <name>    Create a new empty list
  delete <name>    Delete a list
  rename <old> <new>  Rename a list
  list             Show available lists
                ]], vim.log.levels.INFO)
            end
        end,
        opts = {
            desc = "Manage Todo Lists",
            nargs = "*",
            complete = function(arglead, cmdline, cursorpos)
                local args = vim.split(cmdline, "%s+", { trimempty = true })
                
                if #args <= 2 then
                    -- Complete subcommands
                    return { "switch", "use", "create", "new", "delete", "remove", "rename", "list", "ls" }
                elseif args[2] == "switch" or args[2] == "use" or args[2] == "delete" or args[2] == "remove" or args[2] == "rename" then
                    -- Complete list names
                    local lists = module.state.get_available_lists()
                    local list_names = {}
                    for _, list in ipairs(lists) do
                        table.insert(list_names, list.name)
                    end
                    return list_names
                end
                
                return {}
            end
        }
    }
    
    return commands
end

return M