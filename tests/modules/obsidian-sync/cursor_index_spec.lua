-- get_current_todo_index feeds the completion-sync toggle hook; it must agree
-- with the rendered rows or the hook reads the wrong todo id.
describe("obsidian-sync get_current_todo_index", function()
    local obsidian_sync
    local mock_state
    local cursor_line
    local win = 100

    before_each(function()
        package.loaded["doit.modules.obsidian-sync"] = nil
        package.loaded["doit.ui.main_window"] = nil
        package.loaded["doit.ui.todo_actions"] = nil
        package.loaded["doit.config"] = nil
        require("doit.config").setup({})
        package.loaded["doit.calendar"] = {}

        mock_state = { todos = {}, active_filter = nil, sort_todos = function() end }
        package.loaded["doit.core"] = {
            get_module = function(name)
                if name == "todos" then
                    return { state = mock_state }
                end
            end,
            register_module = function() end,
        }

        vim.api.nvim_win_is_valid = function(w) return w == win end
        vim.api.nvim_win_get_cursor = function() return { cursor_line, 0 } end

        obsidian_sync = require("doit.modules.obsidian-sync")
        obsidian_sync.setup_functions()
    end)

    it("maps a cursor line under a priority header to its todo", function()
        mock_state.todos = {
            { id = "a", text = "Alpha", done = false, in_progress = false, priorities = "critical" },
            { id = "b", text = "Bravo", done = false, in_progress = false },
        }
        -- blank, Critical, Alpha, blank, Default, Bravo
        cursor_line = 6
        assert.are.equal(2, obsidian_sync.get_current_todo_index(win))
        cursor_line = 3
        assert.are.equal(1, obsidian_sync.get_current_todo_index(win))
    end)

    it("returns nil on a header line", function()
        mock_state.todos = {
            { id = "a", text = "Alpha", done = false, in_progress = false },
        }
        cursor_line = 2
        assert.is_nil(obsidian_sync.get_current_todo_index(win))
    end)
end)
