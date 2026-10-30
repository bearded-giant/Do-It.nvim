-- List notes link to todos in the same list through note.todo_ids.
-- Stale ids (deleted or moved todos) are skipped, never an error.
local M = {}

local function has(ids, id)
    for _, v in ipairs(type(ids) == "table" and ids or {}) do
        if v == id then
            return true
        end
    end
    return false
end
M.has = has

function M.notes_for_todo(notes, todo_id)
    local out = {}
    for _, note in ipairs(notes or {}) do
        if has(note.todo_ids, todo_id) then
            table.insert(out, note)
        end
    end
    return out
end

function M.todos_for_note(todos, note)
    local out = {}
    for _, todo in ipairs(todos or {}) do
        if has(note and note.todo_ids, todo.id) then
            table.insert(out, todo)
        end
    end
    return out
end

function M.counts_by_todo(notes)
    local counts = {}
    for _, note in ipairs(notes or {}) do
        for _, id in ipairs(type(note.todo_ids) == "table" and note.todo_ids or {}) do
            counts[id] = (counts[id] or 0) + 1
        end
    end
    return counts
end

-- returns the new id list with todo_id added or removed
function M.toggled(ids, todo_id)
    local out = {}
    local found = false
    for _, v in ipairs(type(ids) == "table" and ids or {}) do
        if v == todo_id then
            found = true
        else
            table.insert(out, v)
        end
    end
    if not found then
        table.insert(out, todo_id)
    end
    return out
end

return M
