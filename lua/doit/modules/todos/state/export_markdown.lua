-- Markdown export of non-completed todos, grouped under priority headers.
-- Output must stay byte-identical to the tmux exporter (tmux/scripts/todo-export.sh).

local footer = require("doit.core.utils.footer")

local M = {}

local LABELS = { "Critical", "Urgent", "Important", "Default" }

local function priority_rank(todo)
    local p = todo.priorities
    if type(p) == "table" then
        p = p[1]
    end
    if p == "critical" then
        return 1
    elseif p == "urgent" then
        return 2
    elseif p == "important" then
        return 3
    end
    return 4
end

local function indent(text)
    local out = {}
    for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
        out[#out + 1] = line == "" and "" or ("  " .. line)
    end
    return table.concat(out, "\n")
end

-- child items nest as an indented markdown list under their parent
local function pad(block, depth)
    if depth == 0 then
        return block
    end
    local prefix = string.rep("  ", depth)
    local out = {}
    for _, line in ipairs(vim.split(block, "\n", { plain = true })) do
        out[#out + 1] = line == "" and "" or (prefix .. line)
    end
    return table.concat(out, "\n")
end

local function item_block(todo)
    local text_lines = vim.split(todo.text or "", "\n", { plain = true })
    local block = "- [ ] " .. (text_lines[1] or "")
    if #text_lines > 1 then
        block = block .. "\n" .. indent(table.concat(text_lines, "\n", 2))
    end

    local desc = footer.strip(todo.description or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if desc ~= "" then
        block = block .. "\n\n" .. indent(desc)
    end
    return block
end

local function entry_less_than(a, b)
    local ra, rb = priority_rank(a.todo), priority_rank(b.todo)
    if ra ~= rb then
        return ra < rb
    end
    local pa = a.todo.in_progress and 0 or 1
    local pb = b.todo.in_progress and 0 or 1
    if pa ~= pb then
        return pa < pb
    end
    local oa = a.todo.order_index or a.seq
    local ob = b.todo.order_index or b.seq
    if oa ~= ob then
        return oa < ob
    end
    return a.seq < b.seq
end

-- Tree order over the pending set, mirroring sorting.structure_aware but with
-- the exporter's comparator: a child rides with its parent into the parent's
-- priority section, and a child whose parent is done or missing exports as a
-- root. Rows carry the root's rank so sections are bucketed by subtree.
local function nest(pending)
    local by_id, children, roots = {}, {}, {}
    for _, entry in ipairs(pending) do
        if entry.todo.id then
            by_id[entry.todo.id] = entry
        end
    end
    for _, entry in ipairs(pending) do
        local parent_id = entry.todo.parent_id
        local parent = parent_id and by_id[parent_id]
        if parent and parent ~= entry then
            children[parent_id] = children[parent_id] or {}
            table.insert(children[parent_id], entry)
        else
            table.insert(roots, entry)
        end
    end

    table.sort(roots, entry_less_than)
    for _, group in pairs(children) do
        table.sort(group, entry_less_than)
    end

    local rows, emitted = {}, {}
    local function emit(entry, depth, rank)
        if emitted[entry] then
            return
        end
        emitted[entry] = true
        rows[#rows + 1] = { todo = entry.todo, depth = depth, rank = rank }
        for _, child in ipairs(children[entry.todo.id] or {}) do
            emit(child, depth + 1, rank)
        end
    end
    for _, root in ipairs(roots) do
        emit(root, 0, priority_rank(root.todo))
    end
    -- a parent cycle is unreachable from any root; keep it in the export
    for _, entry in ipairs(pending) do
        if not emitted[entry] then
            rows[#rows + 1] = { todo = entry.todo, depth = 0, rank = priority_rank(entry.todo) }
        end
    end
    return rows
end

function M.build(todos, list_name, timestamp)
    local pending = {}
    for i, todo in ipairs(todos or {}) do
        if not todo.done then
            pending[#pending + 1] = { todo = todo, seq = i }
        end
    end

    local buckets = {}
    for _, row in ipairs(nest(pending)) do
        buckets[row.rank] = buckets[row.rank] or {}
        table.insert(buckets[row.rank], pad(item_block(row.todo), row.depth))
    end

    local body = {}
    for rank = 1, #LABELS do
        if buckets[rank] then
            body[#body + 1] = "## " .. LABELS[rank] .. "\n\n" .. table.concat(buckets[rank], "\n\n")
        end
    end

    local stamp = timestamp or os.date("%Y-%m-%d %H:%M")
    local header = "# " .. (list_name or "todos") .. "\n\n_exported " .. stamp .. "_\n\n"
    if #body == 0 then
        return header .. "_no pending items_\n"
    end
    return header .. table.concat(body, "\n\n") .. "\n"
end

function M.write(file_path, todos, list_name)
    local file, err = io.open(file_path, "w")
    if not file then
        return false, "Could not open file for writing: " .. (err or file_path)
    end
    file:write(M.build(todos, list_name))
    file:close()

    local count = 0
    for _, todo in ipairs(todos or {}) do
        if not todo.done then
            count = count + 1
        end
    end
    return true, string.format("Exported %d pending todos to %s", count, file_path)
end

return M
