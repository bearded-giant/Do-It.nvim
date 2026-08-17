-- Derives a todo-list name from a git root, so opening a repo lands on that
-- repo's list instead of the shared default.
--
-- The sanitizer here is a CROSS-SURFACE CONTRACT: tmux/scripts/get-active-list.sh
-- and tmux/scripts/todo-list-manager.sh implement the same rule in bash. If the
-- two drift, one repo resolves to two different lists depending on which UI you
-- opened, and todos silently split. tests/tmux/test_project_list.sh asserts the
-- bash side against the same fixture table used in
-- tests/modules/todos/project_list_spec.lua.
local M = {}

-- A list name becomes a filename ({name}.json), so keep it to characters that
-- are safe in a path. Dots are KEPT on purpose: repos like "do-it.nvim" would
-- otherwise collapse to "do-itnvim".
function M.sanitize(name)
    if not name or name == "" then
        return nil
    end

    local clean = name:gsub("%s+", "_"):gsub("[^%w%._%-]", "")

    -- a name of only illegal characters, or one that would look like a path
    if clean == "" or clean == "." or clean == ".." then
        return nil
    end

    return clean
end

-- Name of the list for the given cwd, or nil when cwd is not in a git repo.
function M.derive(cwd)
    local project = require("doit.core.utils.project")
    local root = project.get_git_root(cwd)
    if not root then
        return nil
    end

    return M.sanitize(vim.fn.fnamemodify(root, ":t"))
end

return M
