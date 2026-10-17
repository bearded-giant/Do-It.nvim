-- daily is the owed inbox: its done section shows only items completed today,
-- so yesterday's checked-off twins stop piling up. Every other list keeps
-- showing all its done items. Mirrors tests/tmux/test_owed_done.sh.
describe("owed list done section", function()
    local sorting = require("doit.modules.todos.state.sorting")
    local mock_state

    local function displays(list)
        mock_state.todo_lists = { active = list }
        local out = {}
        for _, row in ipairs(require("doit.ui.main_window").build_render_rows()) do
            out[#out + 1] = row.display
        end
        return table.concat(out, "\n")
    end

    before_each(function()
        package.loaded["doit.ui.main_window"] = nil
        package.loaded["doit.ui.todo_actions"] = nil
        package.loaded["doit.config"] = nil
        require("doit.config").setup({})
        package.loaded["doit.calendar"] = {}

        local now = os.time()
        mock_state = {
            active_filter = nil,
            todos = {
                { id = "p", text = "still open", done = false, order_index = 1 },
                { id = "t", text = "done today", done = true, order_index = 2, completed_at = now },
                { id = "y", text = "done yesterday", done = true, order_index = 3, completed_at = now - 90000 },
                { id = "n", text = "done no stamp", done = true, order_index = 4 },
            },
        }
        mock_state.sort_todos = function()
            local ordered = sorting.structure_aware(mock_state.todos)
            for i, t in ipairs(ordered) do
                mock_state.todos[i] = t
            end
        end
        package.loaded["doit.core"] = {
            get_module = function(name)
                if name == "todos" then
                    return { state = mock_state }
                end
            end,
        }
    end)

    it("daily shows today's done item and pending items", function()
        local out = displays("daily")
        assert.truthy(out:find("done today", 1, true))
        assert.truthy(out:find("still open", 1, true))
    end)

    it("daily hides yesterday's done item and one with no completed_at", function()
        local out = displays("daily")
        assert.falsy(out:find("done yesterday", 1, true))
        assert.falsy(out:find("done no stamp", 1, true))
    end)

    it("a project list still shows every done item", function()
        local out = displays("proj")
        assert.truthy(out:find("done yesterday", 1, true))
        assert.truthy(out:find("done no stamp", 1, true))
    end)
end)
