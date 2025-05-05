-- Tag management for todos module
local M = {}

-- Setup module
function M.setup(state)
    -- Get all unique tags
    function M.get_all_tags()
        local tags = {}
        local tag_count = {}
        
        for _, todo in ipairs(state.todos) do
            for tag in todo.text:gmatch("#(%w+)") do
                if not tags[tag] then
                    tags[tag] = true
                    tag_count[tag] = 1
                else
                    tag_count[tag] = tag_count[tag] + 1
                end
            end
        end
        
        -- Convert to array and sort by count
        local tag_list = {}
        for tag, _ in pairs(tags) do
            table.insert(tag_list, {
                name = tag,
                count = tag_count[tag]
            })
        end
        
        table.sort(tag_list, function(a, b)
            return a.count > b.count
        end)
        
        return tag_list
    end
    
    -- Set active tag filter
    function M.set_tag_filter(tag)
        state.active_filter = tag
    end
    
    -- Rename a tag in all todos
    function M.rename_tag(old_tag, new_tag)
        local count = 0
        
        for _, todo in ipairs(state.todos) do
            local text = todo.text
            local new_text = text:gsub("#" .. old_tag, "#" .. new_tag)
            
            if text ~= new_text then
                todo.text = new_text
                count = count + 1
            end
        end
        
        if count > 0 then
            state.save_todos()
        end
        
        -- Update filter if needed
        if state.active_filter == old_tag then
            state.active_filter = new_tag
        end
        
        return count
    end
    
    -- Delete a tag from all todos
    function M.delete_tag(tag)
        local count = 0
        
        for _, todo in ipairs(state.todos) do
            local text = todo.text
            
            -- Special handling for end of line
            local new_text = text:gsub("#" .. tag .. "$", "")
            
            -- Handle tag in middle of text
            new_text = new_text:gsub("#" .. tag .. " ", " ")
            
            if text ~= new_text then
                todo.text = new_text
                count = count + 1
            end
        end
        
        if count > 0 then
            state.save_todos()
        end
        
        -- Clear filter if it was this tag
        if state.active_filter == tag then
            state.active_filter = nil
        end
        
        return count
    end
    
    return M
end

return M