local M = {}

function M.setup(parent_module)
    local vim = vim
    local api = vim.api
    local buf_id = nil
    local win_id = nil
    local preview_buf_id = nil
    local preview_win_id = nil
    local selected_index = 1
    
    local todo_module = parent_module
    local config = todo_module.config
    local preview_enabled = config.list_manager and config.list_manager.preview_enabled ~= false
    
    local function close_windows()
        -- Store window IDs before closing
        local preview_win_to_close = preview_win_id
        local main_win_to_close = win_id
        
        -- Clear references first
        preview_win_id = nil
        win_id = nil
        buf_id = nil
        preview_buf_id = nil
        
        -- Close both windows in one go
        if preview_win_to_close and api.nvim_win_is_valid(preview_win_to_close) then
            api.nvim_win_close(preview_win_to_close, true)
        end
        if main_win_to_close and api.nvim_win_is_valid(main_win_to_close) then
            api.nvim_win_close(main_win_to_close, true)
        end
    end
    
    local function create_windows()
        local ui = api.nvim_list_uis()[1]
        local width_ratio = config.list_manager and config.list_manager.width_ratio or 0.8
        local height_ratio = config.list_manager and config.list_manager.height_ratio or 0.8
        local list_panel_ratio = config.list_manager and config.list_manager.list_panel_ratio or 0.4
        
        local total_width = math.min(100, math.floor(ui.width * width_ratio))
        local total_height = math.min(40, math.floor(ui.height * height_ratio))
        local list_width = preview_enabled and math.floor(total_width * list_panel_ratio) or total_width
        local preview_width = total_width - list_width - 3
        
        local row = math.floor((ui.height - total_height) / 2)
        local col = math.floor((ui.width - total_width) / 2)
        
        -- List buffer
        buf_id = api.nvim_create_buf(false, true)
        api.nvim_buf_set_option(buf_id, "bufhidden", "wipe")
        api.nvim_buf_set_option(buf_id, "modifiable", true)
        
        -- List window
        win_id = api.nvim_open_win(buf_id, true, {
            relative = "editor",
            row = row,
            col = col,
            width = list_width,
            height = total_height,
            style = "minimal",
            border = "rounded",
            title = " Todo Lists ",
            title_pos = "center"
        })
        
        api.nvim_win_set_option(win_id, "wrap", false)
        api.nvim_win_set_option(win_id, "number", false)
        api.nvim_win_set_option(win_id, "cursorline", true)
        
        if preview_enabled then
            -- Preview buffer
            preview_buf_id = api.nvim_create_buf(false, true)
            api.nvim_buf_set_option(preview_buf_id, "bufhidden", "wipe")
            api.nvim_buf_set_option(preview_buf_id, "modifiable", true)
            
            -- Preview window
            preview_win_id = api.nvim_open_win(preview_buf_id, false, {
                relative = "editor",
                row = row,
                col = col + list_width + 2,
                width = preview_width,
                height = total_height,
                style = "minimal",
                border = "rounded",
                title = " Preview ",
                title_pos = "center"
            })
            
            api.nvim_win_set_option(preview_win_id, "wrap", true)
            api.nvim_win_set_option(preview_win_id, "number", false)
        end
        
        return buf_id, win_id, preview_buf_id, preview_win_id
    end
    
    local function render_preview(list_name)
        if not preview_buf_id or not preview_win_id or not api.nvim_win_is_valid(preview_win_id) then
            return
        end
        
        local lines = {}
        local namespace = api.nvim_create_namespace("DoitListPreview")
        api.nvim_buf_clear_namespace(preview_buf_id, namespace, 0, -1)
        
        -- Load the list data temporarily
        local saved_active = todo_module.state.todo_lists.active
        local saved_todos = vim.deepcopy(todo_module.state.todos)
        
        todo_module.state.load_list(list_name)
        local todos = todo_module.state.todos or {}
        local metadata = todo_module.state.todo_lists.metadata[list_name] or {}
        
        -- Restore original list
        todo_module.state.todo_lists.active = saved_active
        todo_module.state.todos = saved_todos
        
        -- Header
        table.insert(lines, "  " .. list_name)
        table.insert(lines, "  " .. string.rep("─", #list_name))
        table.insert(lines, "")
        
        -- Metadata
        if metadata.created_at then
            local created = os.date("%Y-%m-%d %H:%M", metadata.created_at)
            table.insert(lines, "  Created: " .. created)
        end
        
        if metadata.updated_at then
            local updated = os.date("%Y-%m-%d %H:%M", metadata.updated_at)
            table.insert(lines, "  Updated: " .. updated)
        end
        
        table.insert(lines, "")
        
        -- Stats
        local total = #todos
        local done = 0
        local in_progress = 0
        local pending = 0
        
        for _, todo in ipairs(todos) do
            if todo.done then
                done = done + 1
            elseif todo.status == "in_progress" then
                in_progress = in_progress + 1
            else
                pending = pending + 1
            end
        end
        
        table.insert(lines, string.format("  Total: %d", total))
        table.insert(lines, string.format("  ✓ Done: %d", done))
        table.insert(lines, string.format("  ◐ In Progress: %d", in_progress))
        table.insert(lines, string.format("  ○ Pending: %d", pending))
        table.insert(lines, "")
        
        -- Recent todos (show up to 10)
        if #todos > 0 then
            table.insert(lines, "  Recent Todos:")
            table.insert(lines, "  " .. string.rep("─", 12))
            
            local count = 0
            for i = #todos, 1, -1 do
                if count >= 10 then break end
                local todo = todos[i]
                
                local icon = todo.done and "✓" or (todo.status == "in_progress" and "◐" or "○")
                local text = todo.text
                if #text > 40 then
                    text = text:sub(1, 37) .. "..."
                end
                
                table.insert(lines, string.format("  %s %s", icon, text))
                count = count + 1
            end
        else
            table.insert(lines, "  (No todos in this list)")
        end
        
        -- Set buffer content
        api.nvim_buf_set_option(preview_buf_id, "modifiable", true)
        api.nvim_buf_set_lines(preview_buf_id, 0, -1, false, lines)
        api.nvim_buf_set_option(preview_buf_id, "modifiable", false)
        
        -- Highlights
        api.nvim_buf_add_highlight(preview_buf_id, namespace, "Title", 0, 0, -1)
        api.nvim_buf_add_highlight(preview_buf_id, namespace, "Comment", 1, 0, -1)
        
        for i = 4, 5 do
            if i <= #lines then
                api.nvim_buf_add_highlight(preview_buf_id, namespace, "Comment", i - 1, 0, -1)
            end
        end
        
        -- Stats highlighting
        local stats_start = 7
        for i = stats_start, stats_start + 3 do
            if i <= #lines then
                if lines[i]:match("Done") then
                    api.nvim_buf_add_highlight(preview_buf_id, namespace, "DiagnosticOk", i - 1, 0, -1)
                elseif lines[i]:match("In Progress") then
                    api.nvim_buf_add_highlight(preview_buf_id, namespace, "DiagnosticWarn", i - 1, 0, -1)
                elseif lines[i]:match("Pending") then
                    api.nvim_buf_add_highlight(preview_buf_id, namespace, "DiagnosticInfo", i - 1, 0, -1)
                end
            end
        end
    end
    
    local function render_lists()
        if not buf_id or not win_id or not api.nvim_win_is_valid(win_id) then
            return
        end
        
        -- Refresh lists to get updated active list
        local lists = todo_module.state.get_available_lists()
        local active_list = todo_module.state.todo_lists.active
        
        local lines = {}
        
        -- Start with Available Lists at the top
        table.insert(lines, "  Todo Lists")
        table.insert(lines, "  ══════════════════════════════════")
        table.insert(lines, "")
        
        if #lists == 0 then
            table.insert(lines, "  No todo lists found")
            table.insert(lines, "  Press 'n' to create your first list")
        else
            -- Add numbered lists
            for i, list in ipairs(lists) do
                if i <= 10 then
                    local num = i == 10 and "0" or tostring(i)
                    local active_marker = list.name == active_list and "[active]" or ""
                    local selection_marker = i == selected_index and "▶ " or "  "
                    
                    local metadata = list.metadata or {}
                    local todo_count = metadata.todo_count or 0
                    
                    table.insert(lines, string.format("%s[%s] %s (%d todos) %s", 
                        selection_marker, num, list.name, todo_count, active_marker))
                else
                    -- Lists beyond 10
                    local active_marker = list.name == active_list and "[active]" or ""
                    local selection_marker = i == selected_index and "▶ " or "  "
                    
                    local metadata = list.metadata or {}
                    local todo_count = metadata.todo_count or 0
                    
                    table.insert(lines, string.format("%s    %s (%d todos) %s", 
                        selection_marker, list.name, todo_count, active_marker))
                end
            end
        end
        
        -- Add help at the bottom
        table.insert(lines, "")
        table.insert(lines, "  ──────────────────────────────────")
        table.insert(lines, "  Keys:")
        table.insert(lines, "  [1-9/0] Select   [Enter] Switch")
        table.insert(lines, "  [n] New          [d] Delete")
        table.insert(lines, "  [r] Rename       [e] Export")
        table.insert(lines, "  [i] Import       [q] Close")
        table.insert(lines, "  [?] Show full help")
        
        -- Set buffer content
        api.nvim_buf_set_option(buf_id, "modifiable", true)
        api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
        api.nvim_buf_set_option(buf_id, "modifiable", false)
        
        -- Highlighting
        local namespace = api.nvim_create_namespace("DoitListManager")
        api.nvim_buf_clear_namespace(buf_id, namespace, 0, -1)
        
        -- Title highlighting
        api.nvim_buf_add_highlight(buf_id, namespace, "Title", 0, 0, -1)
        api.nvim_buf_add_highlight(buf_id, namespace, "Comment", 1, 0, -1)
        
        -- Highlight active list markers
        for i, line in ipairs(lines) do
            if line:match("%[active%]") then
                local start_idx = line:find("%[active%]")
                if start_idx then
                    api.nvim_buf_add_highlight(buf_id, namespace, "DiagnosticOk", i-1, start_idx-1, start_idx+7)
                end
            end
        end
        
        -- Highlight keybindings
        for i = 2, 13 do
            local line = lines[i]
            if line and line:match("^  %w") then
                api.nvim_buf_add_highlight(buf_id, namespace, "Special", i - 1, 2, 6)
            end
        end
        
        -- Highlight active and selected list
        for i = 18, #lines do
            local line = lines[i]
            if line and line:match("^  %[%d%]") then
                -- Number in brackets
                local start_pos = line:find("%[")
                if start_pos then
                    api.nvim_buf_add_highlight(buf_id, namespace, "Number", i - 1, start_pos - 1, start_pos + 2)
                end
            end
            
            if line and line:match("▶") then
                api.nvim_buf_add_highlight(buf_id, namespace, "PmenuSel", i - 1, 0, -1)
            elseif line and line:match("%*") then
                api.nvim_buf_add_highlight(buf_id, namespace, "DiagnosticOk", i - 1, 0, -1)
            end
        end
        
        -- Update preview for selected list
        if preview_enabled and #lists > 0 and selected_index <= #lists then
            render_preview(lists[selected_index].name)
        end
        
        -- Move cursor to selected line
        if #lists > 0 then
            local cursor_line = 18 + selected_index
            if cursor_line <= #lines then
                api.nvim_win_set_cursor(win_id, {cursor_line, 0})
            end
        end
    end
    
    local function switch_to_list(list_name)
        -- Load the list and get feedback
        local success, msg = todo_module.state.load_list(list_name)
        
        if success then
            -- Close windows after successful switch
            close_windows()
            
            -- Update the main window if it's open
            local main_window = todo_module.ui.main_window
            if main_window and main_window.render_todos then
                main_window.render_todos()
            end
            
            -- Update list window if it's open
            local list_window = require("doit.ui.list_window")
            if list_window and list_window.render_list then
                pcall(list_window.render_list)
            end
            
            -- Show confirmation with todo count
            local todo_count = 0
            if todo_module.state.todos then
                todo_count = #todo_module.state.todos
            end
            vim.notify(string.format("Switched to list '%s' (%d todos)", list_name, todo_count), vim.log.levels.INFO)
        else
            vim.notify("Failed to switch list: " .. (msg or "unknown error"), vim.log.levels.ERROR)
        end
    end
    
    local function set_keymaps()
        local function set_keymap(key, callback)
            api.nvim_buf_set_keymap(buf_id, "n", key, "", {
                nowait = true,
                noremap = true,
                silent = true,
                callback = callback
            })
        end
        
        -- Also set close keymaps on preview buffer if it exists
        local function set_preview_keymap(key, callback)
            if preview_buf_id and api.nvim_buf_is_valid(preview_buf_id) then
                api.nvim_buf_set_keymap(preview_buf_id, "n", key, "", {
                    nowait = true,
                    noremap = true,
                    silent = true,
                    callback = callback
                })
            end
        end
        
        -- Number keys for quick selection
        for i = 1, 9 do
            set_keymap(tostring(i), function()
                local lists = todo_module.state.get_available_lists()
                if i <= #lists then
                    selected_index = i
                    render_lists()
                end
            end)
        end
        
        -- 0 for 10th item
        set_keymap("0", function()
            local lists = todo_module.state.get_available_lists()
            if 10 <= #lists then
                selected_index = 10
                render_lists()
            end
        end)
        
        -- Navigation
        set_keymap("j", function()
            local lists = todo_module.state.get_available_lists()
            if selected_index < #lists then
                selected_index = selected_index + 1
                render_lists()
            end
        end)
        
        set_keymap("k", function()
            if selected_index > 1 then
                selected_index = selected_index - 1
                render_lists()
            end
        end)
        
        -- Confirm selection with space
        set_keymap("<Space>", function()
            local lists = todo_module.state.get_available_lists()
            if selected_index <= #lists then
                switch_to_list(lists[selected_index].name)
            end
        end)
        
        -- Switch immediately with enter
        set_keymap("<CR>", function()
            local lists = todo_module.state.get_available_lists()
            if selected_index <= #lists then
                switch_to_list(lists[selected_index].name)
            end
        end)
        
        -- Actions
        set_keymap("n", function() M.create_new_list() end)
        set_keymap("d", function() M.delete_list() end)
        set_keymap("r", function() M.rename_list() end)
        set_keymap("i", function() M.import_list() end)
        set_keymap("e", function() M.export_list() end)
        
        -- Close (set on both buffers)
        set_keymap("q", function() close_windows() end)
        set_keymap("<Esc>", function() close_windows() end)
        set_preview_keymap("q", function() close_windows() end)
        set_preview_keymap("<Esc>", function() close_windows() end)
    end
    
    function M.create_new_list()
        close_windows()
        
        vim.ui.input({
            prompt = "New list name: ",
        }, function(input)
            if not input or input == "" then
                vim.notify("List creation cancelled", vim.log.levels.INFO)
                return
            end
            
            local success, msg = todo_module.state.create_list(input, {})
            if success then
                vim.notify(msg, vim.log.levels.INFO)
                todo_module.state.load_list(input)
                
                local main_window = todo_module.ui.main_window
                if main_window and main_window.render_todos then
                    main_window.render_todos()
                end
            else
                vim.notify(msg, vim.log.levels.ERROR)
            end
            
            M.toggle_window()
        end)
    end
    
    function M.delete_list()
        local lists = todo_module.state.get_available_lists()
        if selected_index > #lists then return end
        
        local list_name = lists[selected_index].name
        close_windows()
        
        vim.ui.input({
            prompt = "Delete list '" .. list_name .. "'? (y/N): ",
        }, function(input)
            if input and (input:lower() == "y" or input:lower() == "yes") then
                local success, msg = todo_module.state.delete_list(list_name)
                if success then
                    vim.notify(msg, vim.log.levels.INFO)
                    
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
            
            M.toggle_window()
        end)
    end
    
    function M.rename_list()
        local lists = todo_module.state.get_available_lists()
        if selected_index > #lists then return end
        
        local list_name = lists[selected_index].name
        close_windows()
        
        vim.ui.input({
            prompt = "New name for list '" .. list_name .. "': ",
            default = list_name
        }, function(input)
            if not input or input == "" or input == list_name then
                vim.notify("List rename cancelled", vim.log.levels.INFO)
            else
                local success, msg = todo_module.state.rename_list(list_name, input)
                if success then
                    vim.notify(msg, vim.log.levels.INFO)
                    
                    local main_window = todo_module.ui.main_window
                    if main_window and main_window.render_todos then
                        main_window.render_todos()
                    end
                else
                    vim.notify(msg, vim.log.levels.ERROR)
                end
            end
            
            M.toggle_window()
        end)
    end
    
    function M.import_list()
        close_windows()
        
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
            
            vim.ui.input({
                prompt = "Import as new list (leave empty to merge with current list): ",
            }, function(list_name)
                local success, msg
                if list_name and list_name ~= "" then
                    success, msg = todo_module.state.import_todos(file_path, list_name)
                else
                    success, msg = todo_module.state.import_todos(file_path)
                end
                
                if success then
                    vim.notify(msg, vim.log.levels.INFO)
                    
                    local main_window = todo_module.ui.main_window
                    if main_window and main_window.render_todos then
                        main_window.render_todos()
                    end
                else
                    vim.notify(msg, vim.log.levels.ERROR)
                end
                
                M.toggle_window()
            end)
        end)
    end
    
    function M.export_list()
        local lists = todo_module.state.get_available_lists()
        local list_name = selected_index <= #lists and lists[selected_index].name or todo_module.state.todo_lists.active
        
        close_windows()
        
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
            
            if list_name ~= todo_module.state.todo_lists.active then
                todo_module.state.load_list(list_name)
            end
            
            vim.ui.input({
                prompt = "Export format (full/simple): ",
                default = "full"
            }, function(format)
                local export_format = format and format:lower() == "simple" and "simple" or "full"
                
                local success, msg = todo_module.state.export_todos(file_path, export_format)
                if success then
                    vim.notify(msg, vim.log.levels.INFO)
                else
                    vim.notify(msg, vim.log.levels.ERROR)
                end
                
                M.toggle_window()
            end)
        end)
    end
    
    function M.toggle_window()
        if win_id and api.nvim_win_is_valid(win_id) then
            close_windows()
        else
            create_windows()
            set_keymaps()
            render_lists()
        end
    end
    
    function M.close_window()
        close_windows()
    end
    
    return M
end

return M