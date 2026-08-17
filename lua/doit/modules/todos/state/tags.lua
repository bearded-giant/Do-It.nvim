-- Tag management for todos module.
-- Tags live inline in the todo text; there is no schema field. Matching is
-- exact-token: #labels must never match #labels-web. Every operation compares
-- captured tokens for equality rather than interpolating the tag into a Lua
-- pattern, which also makes tags containing '-' safe (a '-' inside a pattern is
-- a quantifier, so the old "#" .. tag approach both over-matched and misparsed).
local M = {}

-- Shared charset. Mirrors dooing's [%w_%-/]+ so tags round-trip between the two.
M.PATTERN = "#([%w_%-/]+)"

function M.parse(text)
    local found = {}
    for tag in (text or ""):gmatch(M.PATTERN) do
        table.insert(found, tag)
    end
    return found
end

function M.has_tag(text, tag)
    if not tag or tag == "" then
        return true
    end
    for found in (text or ""):gmatch(M.PATTERN) do
        if found == tag then
            return true
        end
    end
    return false
end

-- Setup module
function M.setup(state)
    -- Get all unique tags (from active todos only), most used first
    function M.get_all_tags()
        local tag_count = {}
        local order = {}

        for _, todo in ipairs(state.todos) do
            -- Only count tags from active todos
            if not todo.done then
                for _, tag in ipairs(M.parse(todo.text)) do
                    if not tag_count[tag] then
                        tag_count[tag] = 1
                        table.insert(order, tag)
                    else
                        tag_count[tag] = tag_count[tag] + 1
                    end
                end
            end
        end

        local tag_list = {}
        for _, tag in ipairs(order) do
            table.insert(tag_list, { name = tag, count = tag_count[tag] })
        end

        table.sort(tag_list, function(a, b)
            if a.count ~= b.count then
                return a.count > b.count
            end
            return a.name < b.name
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
            local changed = false
            local new_text = todo.text:gsub(M.PATTERN, function(found)
                if found == old_tag then
                    changed = true
                    return "#" .. new_tag
                end
            end)

            if changed then
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
            local changed = false
            local new_text = todo.text:gsub(M.PATTERN, function(found)
                if found == tag then
                    changed = true
                    return ""
                end
            end)

            if changed then
                -- close the gap the tag left behind without touching newlines:
                -- todo text can be multi-line and %s+ would collapse it to one line
                new_text = new_text
                    :gsub("[ \t]+", " ")
                    :gsub("[ \t]+\n", "\n")
                    :gsub("^[ \t]+", "")
                    :gsub("[ \t]+$", "")
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
