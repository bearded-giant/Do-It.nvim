-- Categories management for todos module
local M = {}

-- Setup module
function M.setup(state)
    -- Default categories (can be customized in config)
    state.categories = state.categories or {
        work = {
            name = "Work",
            icon = "🏢",
            color = "#7287fd", -- Lavender
            todos = {}
        },
        personal = {
            name = "Personal",
            icon = "🏠",
            color = "#74c7ec", -- Sapphire
            todos = {}
        },
        shopping = {
            name = "Shopping",
            icon = "🛒",
            color = "#94e2d5", -- Teal
            todos = {}
        },
        health = {
            name = "Health",
            icon = "🏥",
            color = "#f38ba8", -- Red
            todos = {}
        },
        ideas = {
            name = "Ideas",
            icon = "💡",
            color = "#fab387", -- Peach
            todos = {}
        },
        uncategorized = {
            name = "Uncategorized",
            icon = "📌",
            color = "#a6adc8", -- Subtext0
            todos = {}
        }
    }
    
    -- Active category filter
    state.active_category = nil
    
    -- Map categories by ID
    M.categories_by_id = {}
    for id, category in pairs(state.categories) do
        M.categories_by_id[id] = category
    end
    
    -- Get all categories as a list
    function M.get_all_categories()
        local categories = {}
        
        for id, category in pairs(state.categories) do
            -- Count only active todos in category
            local active_count = 0
            if category.todos then
                for _, todo_id in ipairs(category.todos) do
                    -- Find the todo in state
                    for _, todo in ipairs(state.todos) do
                        if todo.id == todo_id and not todo.done then
                            active_count = active_count + 1
                            break
                        end
                    end
                end
            end

            table.insert(categories, {
                id = id,
                name = category.name,
                icon = category.icon,
                color = category.color,
                count = active_count
            })
        end
        
        -- Sort by name
        table.sort(categories, function(a, b)
            if a.id == "uncategorized" then
                return false -- Uncategorized goes last
            elseif b.id == "uncategorized" then
                return true
            else
                return a.name < b.name
            end
        end)
        
        return categories
    end
    
    -- Set active category filter
    function M.set_category_filter(category_id)
        state.active_category = category_id
    end
    
    -- Create a new category
    function M.create_category(id, name, icon, color)
        if state.categories[id] then
            return false, "Category already exists"
        end
        
        state.categories[id] = {
            name = name,
            icon = icon or "📁",
            color = color or "#cdd6f4", -- Text color
            todos = {}
        }
        
        M.categories_by_id[id] = state.categories[id]
        state.save_category_metadata()
        
        return true, "Category created"
    end
    
    -- Update a category
    function M.update_category(id, updates)
        if not state.categories[id] then
            return false, "Category does not exist"
        end
        
        if updates.name then
            state.categories[id].name = updates.name
        end
        
        if updates.icon then
            state.categories[id].icon = updates.icon
        end
        
        if updates.color then
            state.categories[id].color = updates.color
        end
        
        state.save_category_metadata()
        
        return true, "Category updated"
    end
    
    -- Delete a category
    function M.delete_category(id)
        if not state.categories[id] or id == "uncategorized" then
            return false, "Cannot delete this category"
        end
        
        -- Move todos from this category to uncategorized
        local todos = state.categories[id].todos or {}
        for _, todo_id in ipairs(todos) do
            table.insert(state.categories.uncategorized.todos, todo_id)
        end
        
        -- Remove the category
        state.categories[id] = nil
        M.categories_by_id[id] = nil
        
        -- Clear filter if it was this category
        if state.active_category == id then
            state.active_category = nil
        end
        
        state.save_category_metadata()
        
        return true, "Category deleted"
    end
    
    -- Assign a todo to a category
    function M.assign_todo_to_category(todo_id, category_id)
        -- Ensure todo exists
        local todo = state.get_todo_by_id(todo_id)
        if not todo then
            return false, "Todo not found"
        end
        
        -- Ensure category exists
        if not state.categories[category_id] then
            return false, "Category not found"
        end
        
        -- Remove from current category if any
        for cat_id, category in pairs(state.categories) do
            for i, t_id in ipairs(category.todos or {}) do
                if t_id == todo_id then
                    table.remove(category.todos, i)
                    break
                end
            end
        end
        
        -- Add to new category
        table.insert(state.categories[category_id].todos, todo_id)
        
        -- Save changes
        state.save_category_metadata()
        
        return true, "Todo assigned to category"
    end
    
    -- Get todos by category
    function M.get_todos_by_category(category_id)
        if not state.categories[category_id] then
            return {}
        end
        
        local result = {}
        local todo_ids = state.categories[category_id].todos or {}
        
        for _, todo_id in ipairs(todo_ids) do
            local todo = state.get_todo_by_id(todo_id)
            if todo then
                table.insert(result, todo)
            end
        end
        
        return result
    end
    
    -- Find category for a todo
    function M.get_todo_category(todo_id)
        for cat_id, category in pairs(state.categories) do
            for _, t_id in ipairs(category.todos or {}) do
                if t_id == todo_id then
                    return cat_id, category
                end
            end
        end
        
        return "uncategorized", state.categories.uncategorized
    end
    
    -- Save category metadata (separate from todos)
    function state.save_category_metadata()
        if not state.todo_lists then
            return
        end
        
        -- Get current lists metadata
        local metadata = state.todo_lists.metadata or {}
        
        -- Convert categories to storable format (without todo lists)
        local categories_data = {}
        for id, category in pairs(state.categories) do
            categories_data[id] = {
                name = category.name,
                icon = category.icon,
                color = category.color
            }
        end
        
        -- Add to metadata
        metadata.categories = categories_data
        
        -- Store metadata
        state.todo_lists.metadata = metadata
        
        -- Save to disk
        state.save_todos()
    end
    
    -- Load category metadata (separate from todos)
    function state.load_category_metadata()
        if not state.todo_lists or not state.todo_lists.metadata then
            return
        end
        
        local metadata = state.todo_lists.metadata or {}
        local categories_data = metadata.categories or {}
        
        -- Restore category metadata
        for id, data in pairs(categories_data) do
            if state.categories[id] then
                state.categories[id].name = data.name or state.categories[id].name
                state.categories[id].icon = data.icon or state.categories[id].icon
                state.categories[id].color = data.color or state.categories[id].color
            else
                state.categories[id] = {
                    name = data.name,
                    icon = data.icon,
                    color = data.color,
                    todos = {}
                }
            end
            
            M.categories_by_id[id] = state.categories[id]
        end
    end
    
    -- Categorize todos (call after loading todos)
    function M.categorize_todos()
        -- Clear existing category assignments
        for _, category in pairs(state.categories) do
            category.todos = {}
        end
        
        -- Check if each todo has a category tag
        for _, todo in ipairs(state.todos) do
            local category_found = false
            
            -- Skip if no ID (for backward compatibility)
            if not todo.id then
                todo.id = os.time() .. "_" .. math.random(1000000, 9999999)
            end
            
            -- Look for @category tags
            for cat in todo.text:gmatch("@(%w+)") do
                if state.categories[cat] then
                    table.insert(state.categories[cat].todos, todo.id)
                    category_found = true
                    break
                end
            end
            
            -- If no category found, add to uncategorized
            if not category_found then
                table.insert(state.categories.uncategorized.todos, todo.id)
            end
        end
    end
    
    return M
end

return M