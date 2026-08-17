-- Sorting functionality for todos module
local tags_util = require("doit.modules.todos.state.tags")

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
    return (a.created_at or 0) < (b.created_at or 0)
end

-- Order a flat list so every child follows its parent and a subtree stays
-- contiguous. Roots are sorted by the normal comparator; a child rides with its
-- parent regardless of its own priority, so a subtree never splits across a
-- priority or status section.
--
-- A todo whose parent_id points at something not in `todos` (a different list,
-- or a parent deleted out from under it) is treated as a root, so nothing can
-- disappear from the render.
function M.structure_aware(todos)
    local by_id, children, roots = {}, {}, {}

    for _, todo in ipairs(todos) do
        if todo.id then
            by_id[todo.id] = todo
        end
    end

    for _, todo in ipairs(todos) do
        local parent = todo.parent_id and by_id[todo.parent_id]
        -- a cycle would otherwise strand the whole ring out of the output
        if parent and parent ~= todo then
            children[todo.parent_id] = children[todo.parent_id] or {}
            table.insert(children[todo.parent_id], todo)
        else
            table.insert(roots, todo)
        end
    end

    table.sort(roots, todo_less_than)
    for _, group in pairs(children) do
        table.sort(group, todo_less_than)
    end

    local ordered = {}
    local emitted = {}

    local function emit(todo, depth)
        if emitted[todo] then
            return
        end
        emitted[todo] = true
        todo.depth = depth
        table.insert(ordered, todo)
        for _, child in ipairs(children[todo.id] or {}) do
            emit(child, depth + 1)
        end
    end

    for _, root in ipairs(roots) do
        emit(root, 0)
    end

    -- any todo left over sat in a parent cycle; append so it stays reachable
    for _, todo in ipairs(todos) do
        if not emitted[todo] then
            todo.depth = 0
            table.insert(ordered, todo)
        end
    end

    return ordered
end

-- Setup module
function M.setup(state)
    -- Sort all todos
    function M.sort_todos()
        local ordered = M.structure_aware(state.todos)
        for i, todo in ipairs(ordered) do
            state.todos[i] = todo
        end
    end

    -- Get filtered and sorted list of todos
    function M.get_filtered_todos()
        local todos = {}

        -- Apply tag filter if set
        if state.active_filter then
            for _, todo in ipairs(state.todos) do
                if tags_util.has_tag(todo.text, state.active_filter) then
                    table.insert(todos, todo)
                end
            end
        else
            todos = vim.deepcopy(state.todos)
        end

        return M.structure_aware(todos)
    end

    return M
end

return M
