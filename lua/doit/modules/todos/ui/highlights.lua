local vim = vim

local M = {}

local ns_id = vim.api.nvim_create_namespace("doit_todos")
local highlight_cache = {}

function M.setup_highlights()
    highlight_cache = {} -- Clear any old cache

    vim.api.nvim_set_hl(0, "DoItPending", { link = "Question", default = true })
    vim.api.nvim_set_hl(0, "DoItDone", { link = "Comment", default = true })
    vim.api.nvim_set_hl(0, "DoItHelpText", { link = "Directory", default = true })
    vim.api.nvim_set_hl(0, "DoItTimestamp", { link = "Comment", default = true })
    vim.api.nvim_set_hl(0, "DoItInProgress", { link = "Title", default = true })
    vim.api.nvim_set_hl(0, "DoItDueDate", { link = "WarningMsg", default = true })
    vim.api.nvim_set_hl(0, "DoItOverdue", { link = "ErrorMsg", default = true })

    highlight_cache.pending = "DoItPending"
    highlight_cache.done = "DoItDone"
    highlight_cache.help = "DoItHelpText"
    highlight_cache.in_progress = "DoItInProgress"
    highlight_cache.due_date = "DoItDueDate"
    highlight_cache.overdue = "DoItOverdue"
end

function M.get_namespace_id()
    return ns_id
end

function M.get_priority_highlight(priorities, config)
    local priority_name = nil
    if type(priorities) == "string" and priorities ~= "" then
        priority_name = priorities
    elseif type(priorities) == "table" and #priorities > 0 then
        -- backward compatibility from the original list
        priority_name = priorities[1]
    end

    -- Handle nil or empty priority - use low priority group per config
    if not priority_name or priority_name == "" then
        local low_group = config.priority_groups and config.priority_groups.low
        if low_group then
            local cache_key = "low_default"
            if highlight_cache[cache_key] then
                return highlight_cache[cache_key]
            end

            local hl_group = highlight_cache.pending
            if low_group.color and type(low_group.color) == "string" and low_group.color:match("^#%x%x%x%x%x%x$") then
                local hl_name = "doit" .. low_group.color:gsub("#", "")
                vim.api.nvim_set_hl(0, hl_name, { fg = low_group.color })
                hl_group = hl_name
            elseif low_group.hl_group then
                hl_group = low_group.hl_group
            end

            highlight_cache[cache_key] = hl_group
            return hl_group
        end
        return highlight_cache.pending
    end

    -- Sort groups by size, descending
    local sorted_groups = {}
    for name, group in pairs(config.priority_groups or {}) do
        table.insert(sorted_groups, { name = name, group = group })
    end
    table.sort(sorted_groups, function(a, b)
        return #a.group.members > #b.group.members
    end)

    -- Check each group to see if the priority is a member
    for _, group_data in ipairs(sorted_groups) do
        local group = group_data.group

        for _, member in ipairs(group.members) do
            if priority_name == member then
                -- Create a cache key
                local cache_key = member
                if highlight_cache[cache_key] then
                    return highlight_cache[cache_key]
                end

                local hl_group = highlight_cache.pending
                if group.color and type(group.color) == "string" and group.color:match("^#%x%x%x%x%x%x$") then
                    local hl_name = "doit" .. group.color:gsub("#", "")
                    vim.api.nvim_set_hl(0, hl_name, { fg = group.color })
                    hl_group = hl_name
                elseif group.hl_group then
                    hl_group = group.hl_group
                end

                highlight_cache[cache_key] = hl_group
                return hl_group
            end
        end
    end

    -- No matching priority found, use low priority group as default
    local low_group = config.priority_groups and config.priority_groups.low
    if low_group then
        local cache_key = "low_default"
        if highlight_cache[cache_key] then
            return highlight_cache[cache_key]
        end

        local hl_group = highlight_cache.pending
        if low_group.color and type(low_group.color) == "string" and low_group.color:match("^#%x%x%x%x%x%x$") then
            local hl_name = "doit" .. low_group.color:gsub("#", "")
            vim.api.nvim_set_hl(0, hl_name, { fg = low_group.color })
            hl_group = hl_name
        elseif low_group.hl_group then
            hl_group = low_group.hl_group
        end

        highlight_cache[cache_key] = hl_group
        return hl_group
    end

    return highlight_cache.pending
end

-- Initialize highlights on module load
M.setup_highlights()

return M