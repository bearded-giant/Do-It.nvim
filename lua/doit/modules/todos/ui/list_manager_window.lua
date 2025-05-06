-- List manager window for todo lists
local M = {}

function M.setup(parent_module)
    local vim = vim
    local api = vim.api
    local buf_id = nil
    local win_id = nil
    
    -- Get access to parent module
    local todo_module = parent_module
    
    -- Create window for list manager
    local function create_window()
        -- Create buffer
        buf_id = api.nvim_create_buf(false, true)
        api.nvim_buf_set_option(buf_id, "bufhidden", "wipe")
        api.nvim_buf_set_option(buf_id, "modifiable", true)
        
        -- Configure window dimensions and position
        local ui = api.nvim_list_uis()[1]
        local width = 50
        local height = 15
        local row = math.floor((ui.height - height) / 2) - 2
        local col = math.floor((ui.width - width) / 2)
        
        -- Create window
        win_id = api.nvim_open_win(buf_id, true, {
            relative = "editor",
            row = row,
            col = col,
            width = width,
            height = height,
            style = "minimal",
            border = "rounded",
            title = " Todo Lists ",
            title_pos = "center"
        })
        
        -- Set window options
        api.nvim_win_set_option(win_id, "wrap", false)
        api.nvim_win_set_option(win_id, "number", false)
        
        -- Set up keymaps
        local function set_keymap(key, callback)
            api.nvim_buf_set_keymap(buf_id, "n", key, "", {
                nowait = true,
                noremap = true,
                silent = true,
                callback = callback
            })
        end
        
        -- Close window on q/Esc
        set_keymap("q", function() M.close_window() end)
        set_keymap("<Esc>", function() M.close_window() end)
        
        -- Create new list
        set_keymap("n", function() M.create_new_list() end)
        
        -- Delete list
        set_keymap("d", function() M.delete_list() end)
        
        -- Rename list
        set_keymap("r", function() M.rename_list() end)
        
        -- Import list
        set_keymap("i", function() M.import_list() end)
        
        -- Export list
        set_keymap("e", function() M.export_list() end)
        
        -- Switch list (enter)
        set_keymap("<CR>", function() M.switch_to_list() end)
        
        -- Create a special mapping to detect double click
        vim.cmd([[
            augroup DoitListManagerDoubleClick
                autocmd!
                autocmd WinEnter,CursorHold <buffer> lua require('doit.modules.todos.ui.list_manager_window').handle_click()
            augroup END
        ]])
        
        return buf_id, win_id
    end
    
    -- Render the list of todo lists
    local function render_lists()
        if not buf_id or not win_id or not api.nvim_win_is_valid(win_id) then
            return
        end
        
        -- Get list of available lists
        local lists = todo_module.state.get_available_lists()
        local active_list = todo_module.state.todo_lists.active
        
        -- Prepare lines for display
        local lines = {
            "  [n] Create new list",
            "  [d] Delete selected list",
            "  [r] Rename selected list",
            "  [i] Import list from file",
            "  [e] Export selected list",
            ""
        }
        
        if #lists == 0 then
            table.insert(lines, "  No todo lists found")
            table.insert(lines, "  Create a new list to get started")
        else
            -- Display available lists
            table.insert(lines, "  Available Todo Lists:")
            table.insert(lines, "  ---------------------")
            
            for _, list in ipairs(lists) do
                local active_marker = list.name == active_list and "* " or "  "
                local metadata = list.metadata or {}
                local updated = metadata.updated_at
                local updated_str = ""
                
                if updated then
                    local diff = os.time() - updated
                    if diff < 3600 then
                        updated_str = string.format(" (updated %d min ago)", math.floor(diff / 60))
                    elseif diff < 86400 then
                        updated_str = string.format(" (updated %d hours ago)", math.floor(diff / 3600))
                    else
                        updated_str = string.format(" (updated %d days ago)", math.floor(diff / 86400))
                    end
                end
                
                table.insert(lines, string.format("  %s%s%s", active_marker, list.name, updated_str))
            end
        end
        
        -- Set buffer content
        api.nvim_buf_set_option(buf_id, "modifiable", true)
        api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
        api.nvim_buf_set_option(buf_id, "modifiable", false)
        
        -- Highlight section headers and current list
        local namespace = api.nvim_create_namespace("DoitListManager")
        api.nvim_buf_clear_namespace(buf_id, namespace, 0, -1)
        
        -- Headers in bold
        api.nvim_buf_add_highlight(buf_id, namespace, "Title", 7, 0, -1)
        api.nvim_buf_add_highlight(buf_id, namespace, "Title", 8, 0, -1)
        
        -- Active list highlighted
        local active_line = -1
        for i, line in ipairs(lines) do
            if line:match("^  %* ") then
                active_line = i - 1
                break
            end
        end
        
        if active_line >= 0 then
            api.nvim_buf_add_highlight(buf_id, namespace, "PmenuSel", active_line, 0, -1)
        end
    end
    
    -- Handle click on a list name
    function M.handle_click()
        if not buf_id or not win_id or not api.nvim_win_is_valid(win_id) then
            return
        end
        
        -- Get cursor position
        local cursor = api.nvim_win_get_cursor(win_id)
        local line_nr = cursor[1]
        local line = api.nvim_buf_get_lines(buf_id, line_nr - 1, line_nr, false)[1]
        
        -- Check if this is a line with a list name
        if line and line:match("^  [%* ] [%w%-%_]+") then
            -- Extract list name
            local list_name = line:match("^  [%* ] ([%w%-%_]+)")
            if list_name then
                M.close_window()
                todo_module.state.load_list(list_name)
                
                -- Refresh main window
                local main_window = todo_module.ui.main_window
                if main_window and main_window.render_todos then
                    main_window.render_todos()
                end
                
                -- Show notification
                vim.notify("Switched to todo list: " .. list_name, vim.log.levels.INFO)
            end
        end
    end
    
    -- Switch to the selected list
    function M.switch_to_list()
        if not buf_id or not win_id or not api.nvim_win_is_valid(win_id) then
            return
        end
        
        -- Get cursor position
        local cursor = api.nvim_win_get_cursor(win_id)
        local line_nr = cursor[1]
        local line = api.nvim_buf_get_lines(buf_id, line_nr - 1, line_nr, false)[1]
        
        -- Check if this is a line with a list name
        if line and line:match("^  [%* ] [%w%-%_]+") then
            -- Extract list name
            local list_name = line:match("^  [%* ] ([%w%-%_]+)")
            if list_name then
                M.close_window()
                todo_module.state.load_list(list_name)
                
                -- Refresh main window
                local main_window = todo_module.ui.main_window
                if main_window and main_window.render_todos then
                    main_window.render_todos()
                end
                
                -- Show notification
                vim.notify("Switched to todo list: " .. list_name, vim.log.levels.INFO)
            end
        end
    end
    
    -- Create a new list
    function M.create_new_list()
        -- Close first so we can use vim.ui.input
        M.close_window()
        
        vim.ui.input({
            prompt = "New list name: ",
        }, function(input)
            if not input or input == "" then
                vim.notify("List creation cancelled", vim.log.levels.INFO)
                return
            end
            
            -- Create new list
            local success, msg = todo_module.state.create_list(input, {})
            if success then
                vim.notify(msg, vim.log.levels.INFO)
                
                -- Switch to the new list
                todo_module.state.load_list(input)
                
                -- Refresh main window
                local main_window = todo_module.ui.main_window
                if main_window and main_window.render_todos then
                    main_window.render_todos()
                end
            else
                vim.notify(msg, vim.log.levels.ERROR)
            end
            
            -- Re-open the list manager
            M.toggle_window()
        end)
    end
    
    -- Delete the selected list
    function M.delete_list()
        if not buf_id or not win_id or not api.nvim_win_is_valid(win_id) then
            return
        end
        
        -- Get cursor position
        local cursor = api.nvim_win_get_cursor(win_id)
        local line_nr = cursor[1]
        local line = api.nvim_buf_get_lines(buf_id, line_nr - 1, line_nr, false)[1]
        
        -- Check if this is a line with a list name
        if line and line:match("^  [%* ] [%w%-%_]+") then
            -- Extract list name
            local list_name = line:match("^  [%* ] ([%w%-%_]+)")
            if list_name then
                -- Close first so we can use vim.ui.input
                M.close_window()
                
                -- Confirm deletion
                vim.ui.input({
                    prompt = "Delete list '" .. list_name .. "'? (y/N): ",
                }, function(input)
                    if input and (input:lower() == "y" or input:lower() == "yes") then
                        -- Delete the list
                        local success, msg = todo_module.state.delete_list(list_name)
                        if success then
                            vim.notify(msg, vim.log.levels.INFO)
                            
                            -- Refresh main window
                            local main_window = todo_module.ui.main_window
                            if main_window and main_window.render_todos then
                                main_window.render_todos()
                            end
                        else
                            vim.notify(msg, vim.log.levels.ERROR)
                        end
                    else
                        vim.notify("List deletion cancelled", vim.log.levels.INFO)
                    end
                    
                    -- Re-open the list manager
                    M.toggle_window()
                end)
            end
        end
    end
    
    -- Rename the selected list
    function M.rename_list()
        if not buf_id or not win_id or not api.nvim_win_is_valid(win_id) then
            return
        end
        
        -- Get cursor position
        local cursor = api.nvim_win_get_cursor(win_id)
        local line_nr = cursor[1]
        local line = api.nvim_buf_get_lines(buf_id, line_nr - 1, line_nr, false)[1]
        
        -- Check if this is a line with a list name
        if line and line:match("^  [%* ] [%w%-%_]+") then
            -- Extract list name
            local list_name = line:match("^  [%* ] ([%w%-%_]+)")
            if list_name then
                -- Close first so we can use vim.ui.input
                M.close_window()
                
                -- Get new name
                vim.ui.input({
                    prompt = "New name for list '" .. list_name .. "': ",
                    default = list_name
                }, function(input)
                    if not input or input == "" or input == list_name then
                        vim.notify("List rename cancelled", vim.log.levels.INFO)
                    else
                        -- Rename the list
                        local success, msg = todo_module.state.rename_list(list_name, input)
                        if success then
                            vim.notify(msg, vim.log.levels.INFO)
                            
                            -- Refresh main window
                            local main_window = todo_module.ui.main_window
                            if main_window and main_window.render_todos then
                                main_window.render_todos()
                            end
                        else
                            vim.notify(msg, vim.log.levels.ERROR)
                        end
                    end
                    
                    -- Re-open the list manager
                    M.toggle_window()
                end)
            end
        end
    end
    
    -- Import a list from a file
    function M.import_list()
        -- Close first so we can use vim.ui.input
        M.close_window()
        
        vim.ui.input({
            prompt = "File to import: ",
            default = vim.fn.expand("~/todos.json"),
            completion = "file"
        }, function(file_path)
            if not file_path or file_path == "" then
                vim.notify("Import cancelled", vim.log.levels.INFO)
                M.toggle_window()
                return
            end
            
            -- Get list name
            vim.ui.input({
                prompt = "Import as new list (leave empty to merge with current list): ",
            }, function(list_name)
                -- Import the list
                local success, msg
                if list_name and list_name ~= "" then
                    success, msg = todo_module.state.import_todos(file_path, list_name)
                else
                    success, msg = todo_module.state.import_todos(file_path)
                end
                
                if success then
                    vim.notify(msg, vim.log.levels.INFO)
                    
                    -- Refresh main window
                    local main_window = todo_module.ui.main_window
                    if main_window and main_window.render_todos then
                        main_window.render_todos()
                    end
                else
                    vim.notify(msg, vim.log.levels.ERROR)
                end
                
                -- Re-open the list manager
                M.toggle_window()
            end)
        end)
    end
    
    -- Export the selected list
    function M.export_list()
        if not buf_id or not win_id or not api.nvim_win_is_valid(win_id) then
            return
        end
        
        -- Get cursor position
        local cursor = api.nvim_win_get_cursor(win_id)
        local line_nr = cursor[1]
        local line = api.nvim_buf_get_lines(buf_id, line_nr - 1, line_nr, false)[1]
        
        -- Close first so we can use vim.ui.input
        M.close_window()
        
        -- Check if this is a line with a list name
        local list_name = nil
        if line and line:match("^  [%* ] [%w%-%_]+") then
            -- Extract list name
            list_name = line:match("^  [%* ] ([%w%-%_]+)")
        end
        
        -- If no list selected, use active list
        if not list_name then
            list_name = todo_module.state.todo_lists.active
        end
        
        -- Get export path
        vim.ui.input({
            prompt = "Export list '" .. list_name .. "' to: ",
            default = vim.fn.expand("~/" .. list_name .. "_todos.json"),
            completion = "file"
        }, function(file_path)
            if not file_path or file_path == "" then
                vim.notify("Export cancelled", vim.log.levels.INFO)
                M.toggle_window()
                return
            end
            
            -- Switch to the list if it's not the active one
            if list_name ~= todo_module.state.todo_lists.active then
                todo_module.state.load_list(list_name)
            end
            
            -- Choose export format
            vim.ui.input({
                prompt = "Export format (full/simple): ",
                default = "full"
            }, function(format)
                local export_format = format:lower() == "simple" and "simple" or "full"
                
                -- Export the list
                local success, msg = todo_module.state.export_todos(file_path, export_format)
                if success then
                    vim.notify(msg, vim.log.levels.INFO)
                else
                    vim.notify(msg, vim.log.levels.ERROR)
                end
                
                -- Re-open the list manager
                M.toggle_window()
            end)
        end)
    end
    
    -- Toggle window visibility
    function M.toggle_window()
        if win_id and api.nvim_win_is_valid(win_id) then
            M.close_window()
        else
            create_window()
            render_lists()
        end
    end
    
    -- Close window
    function M.close_window()
        if win_id and api.nvim_win_is_valid(win_id) then
            api.nvim_win_close(win_id, true)
            win_id = nil
            buf_id = nil
            
            -- Clean up autocommands
            vim.cmd("augroup DoitListManagerDoubleClick")
            vim.cmd("autocmd!")
            vim.cmd("augroup END")
        end
    end
    
    return M
end

return M