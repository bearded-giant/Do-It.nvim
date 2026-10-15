-- Owed items live twice (a project list and daily), cross-linked by `twin`.
-- Mirrors mcp/server.js syncTwin so an nvim edit to one copy reaches the other.
local M = {}

local MAX_DELETED = 10

local state

function M.setup(parent_state)
    state = parent_state
    return M
end

local function find(todos, id)
    for i, t in ipairs(todos or {}) do
        if t.id == id then
            return i, t
        end
    end
end

local function read_list(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local content = f:read("*all")
    f:close()
    local ok, data = pcall(vim.fn.json_decode, content)
    if ok and type(data) == "table" then
        return data
    end
end

local function write_list(path, data)
    data._metadata.updated_at = os.time()
    local f = io.open(path, "w")
    if not f then
        return false
    end
    f:write(vim.fn.json_encode(data))
    f:close()
    return true
end

local function mutate(twin, op, value, source_id)
    if op == "complete" then
        twin.done = true
        twin.in_progress = false
        twin.completed_at = value or os.time()
    elseif op == "revert" then
        twin.done = false
        twin.in_progress = false
        twin.completed_at = nil
    elseif op == "priority" then
        twin.priorities = value
    elseif op == "due" then
        twin.due_date = value
    elseif op == "relink" then
        twin.twin = { list = value, id = source_id }
    end
end

-- op: complete|revert|priority|due|relink|delete|restore; value is the stamp/priority/date/list name
function M.sync(todo, op, value)
    local ref = type(todo) == "table" and todo.twin
    if type(ref) ~= "table" or not ref.list or not ref.id or not state or not state.get_list_path then
        return
    end

    -- the loaded list is saved from memory, so a disk-only write there would be clobbered
    local loaded = state.todo_lists and state.todo_lists.active == ref.list
    local path = state.get_list_path(ref.list)
    local data
    if loaded then
        state.todo_lists.metadata = state.todo_lists.metadata or {}
        data = { todos = state.todos, _metadata = state.todo_lists.metadata }
    else
        data = vim.fn.filereadable(path) == 1 and read_list(path) or nil
        if not data then
            vim.notify(string.format('Twin list "%s" is gone', ref.list), vim.log.levels.WARN)
            return
        end
        data.todos = data.todos or {}
        data._metadata = type(data._metadata) == "table" and data._metadata or {}
    end
    local deleted = data._metadata.deleted_todos or {}

    local idx, twin = find(op == "restore" and deleted or data.todos, ref.id)
    if not twin then
        -- undo of a clear-done restores items whose twins were never deleted
        if op == "restore" and find(data.todos, ref.id) then
            return
        end
        vim.notify(string.format('Twin %s is no longer in "%s"', ref.id, ref.list), vim.log.levels.WARN)
        return
    end

    if op == "delete" then
        table.remove(data.todos, idx)
        table.insert(deleted, 1, twin)
        while #deleted > MAX_DELETED do
            table.remove(deleted)
        end
        data._metadata.deleted_todos = deleted
    elseif op == "restore" then
        table.remove(deleted, idx)
        table.insert(data.todos, twin)
    else
        mutate(twin, op, value, todo.id)
    end

    if loaded then
        state.save_todos()
    else
        write_list(path, data)
    end
end

function M.relink_list(list_name)
    if not state or not state.get_list_path then
        return
    end
    local data = read_list(state.get_list_path(list_name))
    for _, todo in ipairs(data and data.todos or {}) do
        M.sync(todo, "relink", list_name)
    end
end

return M
