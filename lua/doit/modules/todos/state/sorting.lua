-- Sorting functionality for todos module
local M = {}

-- Rank by the priority string directly (critical > urgent > important > none).
-- Config-independent so ordering matches the tmux view even when the weighted
-- priorities config is absent or nested. Higher rank sorts first.
local PRIORITY_RANK = {
    critical = 4,
    urgent = 3,
    important = 2,
}

function M.priority_rank(todo)
    local p = todo.priorities
    if type(p) == "string" and p ~= "" then
        return PRIORITY_RANK[p] or 1
    elseif type(p) == "table" then
        local best = 1
        for _, name in ipairs(p) do
            best = math.max(best, PRIORITY_RANK[name] or 1)
        end
        return best
    end
    return 1
end

-- Comparator shared by sort_todos and get_filtered_todos so ordering never drifts
-- between them: done last, in_progress first, priority rank desc, order_index,
-- due date, creation time.
local function todo_less_than(a, b)
    if a.done ~= b.done then
        return not a.done
    end
    if a.in_progress ~= b.in_progress then
        return a.in_progress
    end
    local a_rank = M.priority_rank(a)
    local b_rank = M.priority_rank(b)
    if a_rank ~= b_rank then
        return a_rank > b_rank
    end
    if a.order_index and b.order_index and a.order_index ~= b.order_index then
        return a.order_index < b.order_index
    end
    if a.due_date and b.due_date and a.due_date ~= b.due_date then
        return a.due_date < b.due_date
    end
    if a.due_date and not b.due_date then
        return true
    elseif not a.due_date and b.due_date then
        return false
    end
    return (a.timestamp or 0) < (b.timestamp or 0)
end

-- Setup module
function M.setup(state)
    -- Sort all todos
    function M.sort_todos()
        for _, todo in ipairs(state.todos) do
            todo._score = M.priority_rank(todo)
        end
        table.sort(state.todos, todo_less_than)
    end

    -- Get filtered and sorted list of todos
    function M.get_filtered_todos()
        local todos = {}

        -- Apply tag filter if set
        if state.active_filter then
            for _, todo in ipairs(state.todos) do
                if todo.text:find("#" .. state.active_filter) then
                    table.insert(todos, todo)
                end
            end
        else
            todos = vim.deepcopy(state.todos)
        end

        -- Sort the filtered todos with the same comparator as sort_todos
        table.sort(todos, todo_less_than)

        return todos
    end

    return M
end

return M
