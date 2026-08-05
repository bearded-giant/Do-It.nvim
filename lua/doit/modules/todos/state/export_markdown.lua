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

function M.build(todos, list_name, timestamp)
    local pending = {}
    for i, todo in ipairs(todos or {}) do
        if not todo.done then
            pending[#pending + 1] = { todo = todo, seq = i }
        end
    end

    table.sort(pending, function(a, b)
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
    end)

    local sections = {}
    local current_rank, items = nil, nil
    for _, entry in ipairs(pending) do
        local rank = priority_rank(entry.todo)
        if rank ~= current_rank then
            items = {}
            sections[#sections + 1] = { rank = rank, items = items }
            current_rank = rank
        end
        items[#items + 1] = item_block(entry.todo)
    end

    local body = {}
    for _, section in ipairs(sections) do
        body[#body + 1] = "## " .. LABELS[section.rank] .. "\n\n" .. table.concat(section.items, "\n\n")
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
