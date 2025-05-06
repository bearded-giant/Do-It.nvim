-- Category window for todos module
local M = {}

function M.setup(parent_module)
    local vim = vim
    local api = vim.api
    local buf_id = nil
    local win_id = nil
    
    -- Get access to parent module
    local todo_module = parent_module
    
    -- Create window for categories
    local function create_window()
        -- Create buffer
        buf_id = api.nvim_create_buf(false, true)
        api.nvim_buf_set_option(buf_id, "bufhidden", "wipe")
        api.nvim_buf_set_option(buf_id, "modifiable", true)
        
        -- Configure window dimensions and position
        local ui = api.nvim_list_uis()[1]
        local width = 40
        local height = 20
        local row = 2
        local col = 2
        
        -- Create window
        win_id = api.nvim_open_win(buf_id, true, {
            relative = "editor",
            row = row,
            col = col,
            width = width,
            height = height,
            style = "minimal",
            border = "rounded",
            title = " Categories ",
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
        
        -- Create new category
        set_keymap("n", function() M.create_new_category() end)
        
        -- Edit category
        set_keymap("e", function() M.edit_category() end)
        
        -- Delete category
        set_keymap("d", function() M.delete_category() end)
        
        -- Apply category filter
        set_keymap("<CR>", function() M.apply_category_filter() end)
        
        -- Assign a todo to a category
        set_keymap("a", function() M.assign_todo() end)
        
        -- Clear filter
        set_keymap("c", function() M.clear_filter() end)
        
        return buf_id, win_id
    end
    
    -- Render the list of categories
    local function render_categories()
        if not buf_id or not win_id or not api.nvim_win_is_valid(win_id) then
            return
        end
        
        -- Get list of categories
        local categories = todo_module.state.get_all_categories()
        local active_category = todo_module.state.active_category
        
        -- Prepare lines for display
        local lines = {
            "  [n] Create new category",
            "  [e] Edit selected category",
            "  [d] Delete selected category",
            "  [a] Assign current todo to category",
            "  [c] Clear category filter",
            ""
        }
        
        if #categories == 0 then
            table.insert(lines, "  No categories found")
            table.insert(lines, "  Create a new category to get started")
        else
            -- Display available categories
            table.insert(lines, "  Available Categories:")
            table.insert(lines, "  ---------------------")
            
            for _, category in ipairs(categories) do
                local active_marker = category.id == active_category and "* " or "  "
                local count_str = " (" .. category.count .. ")"
                table.insert(lines, string.format("  %s%s %s%s", 
                    active_marker,
                    category.icon,
                    category.name,
                    count_str))
            end
        end
        
        -- Set buffer content
        api.nvim_buf_set_option(buf_id, "modifiable", true)
        api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
        api.nvim_buf_set_option(buf_id, "modifiable", false)
        
        -- Highlight section headers and current category
        local namespace = api.nvim_create_namespace("DoitCategoryWindow")
        api.nvim_buf_clear_namespace(buf_id, namespace, 0, -1)
        
        -- Headers in bold
        api.nvim_buf_add_highlight(buf_id, namespace, "Title", 7, 0, -1)
        api.nvim_buf_add_highlight(buf_id, namespace, "Title", 8, 0, -1)
        
        -- Active category highlighted
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
        
        -- Highlight category counts
        for i = 9, #lines do
            local line = lines[i]
            local count_start = line:find("%(")
            local count_end = line:find("%)")
            
            if count_start and count_end then
                api.nvim_buf_add_highlight(buf_id, namespace, "Comment", i - 1, count_start - 1, count_end)
            end
        end
    end
    
    -- Apply a category filter
    function M.apply_category_filter()
        if not buf_id or not win_id or not api.nvim_win_is_valid(win_id) then
            return
        end
        
        -- Get cursor position
        local cursor = api.nvim_win_get_cursor(win_id)
        local line_nr = cursor[1]
        local line = api.nvim_buf_get_lines(buf_id, line_nr - 1, line_nr, false)[1]
        
        -- Check if this is a line with a category
        if line and line:match("^  [%* ] [^%s]+ [%w%s]+") then
            local category_name = line:match("^  [%* ] [^%s]+ ([%w%s]+)")
            if category_name then
                category_name = category_name:gsub(" %([%d]+%)", "") -- Remove count
                
                -- Find category id by name
                local categories = todo_module.state.get_all_categories()
                local category_id = nil
                
                for _, cat in ipairs(categories) do
                    if cat.name == category_name then
                        category_id = cat.id
                        break
                    end
                end
                
                if category_id then
                    -- Apply the filter
                    todo_module.state.set_category_filter(category_id)
                    
                    -- Close the window
                    M.close_window()
                    
                    -- Update the main window if open
                    if todo_module.ui.main_window and todo_module.ui.main_window.render_todos then
                        todo_module.ui.main_window.render_todos()
                    end
                    
                    -- Notify user
                    vim.notify("Filtering by category: " .. category_name, vim.log.levels.INFO)
                end
            end
        end
    end
    
    -- Clear category filter
    function M.clear_filter()
        -- Clear the filter
        todo_module.state.set_category_filter(nil)
        
        -- Close the window
        M.close_window()
        
        -- Update the main window if open
        if todo_module.ui.main_window and todo_module.ui.main_window.render_todos then
            todo_module.ui.main_window.render_todos()
        end
        
        -- Notify user
        vim.notify("Category filter cleared", vim.log.levels.INFO)
    end
    
    -- Create a new category
    function M.create_new_category()
        -- Close first so we can use vim.ui.input
        M.close_window()
        
        vim.ui.input({
            prompt = "Category ID (letters/numbers only): ",
        }, function(id)
            if not id or id == "" then
                vim.notify("Category creation cancelled", vim.log.levels.INFO)
                return
            end
            
            -- Validate ID (letters/numbers only)
            if not id:match("^%w+$") then
                vim.notify("Invalid category ID. Use only letters and numbers.", vim.log.levels.ERROR)
                return
            end
            
            vim.ui.input({
                prompt = "Category Name: ",
                default = id:sub(1, 1):upper() .. id:sub(2)
            }, function(name)
                if not name or name == "" then
                    vim.notify("Category creation cancelled", vim.log.levels.INFO)
                    return
                end
                
                vim.ui.input({
                    prompt = "Icon (emoji): ",
                    default = "📁"
                }, function(icon)
                    if not icon then
                        vim.notify("Category creation cancelled", vim.log.levels.INFO)
                        return
                    end
                    
                    vim.ui.input({
                        prompt = "Color (hex): ",
                        default = "#cdd6f4"
                    }, function(color)
                        if not color then
                            vim.notify("Category creation cancelled", vim.log.levels.INFO)
                            return
                        end
                        
                        -- Create the category
                        local success, msg = todo_module.state.create_category(id, name, icon, color)
                        vim.notify(msg, success and vim.log.levels.INFO or vim.log.levels.ERROR)
                        
                        -- Re-open the category window
                        M.toggle_window()
                    end)
                end)
            end)
        end)
    end
    
    -- Edit a category
    function M.edit_category()
        if not buf_id or not win_id or not api.nvim_win_is_valid(win_id) then
            return
        end
        
        -- Get cursor position
        local cursor = api.nvim_win_get_cursor(win_id)
        local line_nr = cursor[1]
        local line = api.nvim_buf_get_lines(buf_id, line_nr - 1, line_nr, false)[1]
        
        -- Check if this is a line with a category
        if line and line:match("^  [%* ] [^%s]+ [%w%s]+") then
            local category_name = line:match("^  [%* ] [^%s]+ ([%w%s]+)")
            if category_name then
                category_name = category_name:gsub(" %([%d]+%)", "") -- Remove count
                
                -- Find category id by name
                local categories = todo_module.state.get_all_categories()
                local category_id = nil
                local category = nil
                
                for _, cat in ipairs(categories) do
                    if cat.name == category_name then
                        category_id = cat.id
                        category = cat
                        break
                    end
                end
                
                if category_id then
                    -- Close first so we can use vim.ui.input
                    M.close_window()
                    
                    vim.ui.input({
                        prompt = "Category Name: ",
                        default = category.name
                    }, function(name)
                        if not name then
                            vim.notify("Edit cancelled", vim.log.levels.INFO)
                            return
                        end
                        
                        vim.ui.input({
                            prompt = "Icon (emoji): ",
                            default = category.icon
                        }, function(icon)
                            if not icon then
                                vim.notify("Edit cancelled", vim.log.levels.INFO)
                                return
                            end
                            
                            vim.ui.input({
                                prompt = "Color (hex): ",
                                default = category.color
                            }, function(color)
                                if not color then
                                    vim.notify("Edit cancelled", vim.log.levels.INFO)
                                    return
                                end
                                
                                -- Update the category
                                local success, msg = todo_module.state.update_category(category_id, {
                                    name = name,
                                    icon = icon,
                                    color = color
                                })
                                vim.notify(msg, success and vim.log.levels.INFO or vim.log.levels.ERROR)
                                
                                -- Re-open the category window
                                M.toggle_window()
                            end)
                        end)
                    end)
                end
            end
        end
    end
    
    -- Delete a category
    function M.delete_category()
        if not buf_id or not win_id or not api.nvim_win_is_valid(win_id) then
            return
        end
        
        -- Get cursor position
        local cursor = api.nvim_win_get_cursor(win_id)
        local line_nr = cursor[1]
        local line = api.nvim_buf_get_lines(buf_id, line_nr - 1, line_nr, false)[1]
        
        -- Check if this is a line with a category
        if line and line:match("^  [%* ] [^%s]+ [%w%s]+") then
            local category_name = line:match("^  [%* ] [^%s]+ ([%w%s]+)")
            if category_name then
                category_name = category_name:gsub(" %([%d]+%)", "") -- Remove count
                
                -- Find category id by name
                local categories = todo_module.state.get_all_categories()
                local category_id = nil
                
                for _, cat in ipairs(categories) do
                    if cat.name == category_name then
                        category_id = cat.id
                        break
                    end
                end
                
                if category_id then
                    -- Close first so we can use vim.ui.input
                    M.close_window()
                    
                    -- Confirm deletion
                    vim.ui.input({
                        prompt = "Delete category '" .. category_name .. "'? (y/N): ",
                    }, function(input)
                        if input and (input:lower() == "y" or input:lower() == "yes") then
                            -- Delete the category
                            local success, msg = todo_module.state.delete_category(category_id)
                            vim.notify(msg, success and vim.log.levels.INFO or vim.log.levels.ERROR)
                        else
                            vim.notify("Deletion cancelled", vim.log.levels.INFO)
                        end
                        
                        -- Re-open the category window
                        M.toggle_window()
                    end)
                end
            end
        end
    end
    
    -- Assign a todo to a category
    function M.assign_todo()
        if not buf_id or not win_id or not api.nvim_win_is_valid(win_id) then
            return
        end
        
        -- Get current todo from main window
        local main_win = todo_module.ui.main_window.get_window_id()
        if not main_win or not vim.api.nvim_win_is_valid(main_win) then
            vim.notify("Main window not open", vim.log.levels.ERROR)
            return
        end
        
        local cursor = vim.api.nvim_win_get_cursor(main_win)
        local todo_index = cursor[1] - 1
        local todo = todo_module.state.todos[todo_index]
        
        if not todo then
            vim.notify("No todo selected", vim.log.levels.ERROR)
            return
        end
        
        -- Get cursor position in category window
        local cat_cursor = api.nvim_win_get_cursor(win_id)
        local line_nr = cat_cursor[1]
        local line = api.nvim_buf_get_lines(buf_id, line_nr - 1, line_nr, false)[1]
        
        -- Check if this is a line with a category
        if line and line:match("^  [%* ] [^%s]+ [%w%s]+") then
            local category_name = line:match("^  [%* ] [^%s]+ ([%w%s]+)")
            if category_name then
                category_name = category_name:gsub(" %([%d]+%)", "") -- Remove count
                
                -- Find category id by name
                local categories = todo_module.state.get_all_categories()
                local category_id = nil
                
                for _, cat in ipairs(categories) do
                    if cat.name == category_name then
                        category_id = cat.id
                        break
                    end
                end
                
                if category_id and todo.id then
                    -- Assign the todo to this category
                    todo_module.state.assign_todo_to_category(todo.id, category_id)
                    
                    -- Close window
                    M.close_window()
                    
                    -- Notify user
                    vim.notify("Todo assigned to category: " .. category_name, vim.log.levels.INFO)
                end
            end
        end
    end
    
    -- Toggle window visibility
    function M.toggle_window()
        if win_id and api.nvim_win_is_valid(win_id) then
            M.close_window()
        else
            create_window()
            render_categories()
        end
    end
    
    -- Close window
    function M.close_window()
        if win_id and api.nvim_win_is_valid(win_id) then
            api.nvim_win_close(win_id, true)
            win_id = nil
            buf_id = nil
        end
    end
    
    return M
end

return M