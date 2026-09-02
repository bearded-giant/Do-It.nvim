-- Tests for the markdown exporter. Output must match tmux/scripts/todo-export.sh
-- (see tests/tmux/test_export.sh for the bash side of the same fixture).
local export_markdown = require("doit.modules.todos.state.export_markdown")

local FIXTURE = {
    {
        id = "1",
        text = "fix auth bug",
        done = false,
        in_progress = false,
        order_index = 3,
        priorities = "critical",
        description = "check token expiry\n\nsecond para\n\n\n----------\nlast modified: 2026-07-14: 16:00",
    },
    { id = "2", text = "ship release", done = false, in_progress = true, order_index = 9, priorities = "critical" },
    { id = "3", text = "multi\nline item", done = false, in_progress = false, order_index = 1 },
    { id = "4", text = "already done", done = true, in_progress = false, order_index = 2, priorities = "urgent" },
    {
        id = "5",
        text = "footer only note",
        done = false,
        in_progress = false,
        order_index = 5,
        description = "\n\n\n----------\nlast modified: 2026-07-14: 16:00",
    },
    { id = "6", text = "nudge docs", done = false, in_progress = false, order_index = 7, priorities = "important" },
}

describe("todos export_markdown", function()
    local md

    before_each(function()
        md = export_markdown.build(FIXTURE, "work", "2026-07-30 10:00")
    end)

    it("matches the exporter format byte for byte", function()
        local expected = table.concat({
            "# work",
            "",
            "_exported 2026-07-30 10:00_",
            "",
            "## Critical",
            "",
            "- [ ] ship release",
            "",
            "- [ ] fix auth bug",
            "",
            "  check token expiry",
            "",
            "  second para",
            "",
            "## Important",
            "",
            "- [ ] nudge docs",
            "",
            "## Default",
            "",
            "- [ ] multi",
            "  line item",
            "",
            "- [ ] footer only note",
            "",
        }, "\n")
        assert.are.equal(expected, md)
    end)

    it("skips completed todos", function()
        assert.is_nil(md:find("already done", 1, true))
    end)

    it("omits priority sections with no pending items", function()
        assert.is_nil(md:find("## Urgent", 1, true))
    end)

    it("handles a list with no pending items", function()
        local empty = export_markdown.build({ { text = "done", done = true } }, "work", "2026-07-30 10:00")
        assert.is_not_nil(empty:find("_no pending items_", 1, true))
    end)

    -- same fixture and golden as tests/tmux/test_export.sh "nests children"
    it("nests children under their parent, byte for byte with the tmux exporter", function()
        local nested = {
            { id = "p", text = "parent", done = false, order_index = 1 },
            { id = "c2", text = "second child", done = false, order_index = 3, parent_id = "p" },
            { id = "c1", text = "first child\nmore", done = false, order_index = 2, parent_id = "p", description = "child note" },
            { id = "g", text = "grandchild", done = false, order_index = 4, parent_id = "c1" },
            { id = "dp", text = "done parent", done = true, order_index = 5 },
            { id = "oc", text = "orphaned child", done = false, order_index = 6, parent_id = "dp", priorities = "urgent" },
            { id = "dc", text = "done child", done = true, order_index = 7, parent_id = "p" },
            { id = "u", text = "urgent root", done = false, order_index = 8, priorities = "urgent" },
        }
        local expected = table.concat({
            "# nest",
            "",
            "_exported 2026-07-30 10:00_",
            "",
            "## Urgent",
            "",
            "- [ ] orphaned child",
            "",
            "- [ ] urgent root",
            "",
            "## Default",
            "",
            "- [ ] parent",
            "",
            "  - [ ] first child",
            "    more",
            "",
            "    child note",
            "",
            "    - [ ] grandchild",
            "",
            "  - [ ] second child",
            "",
        }, "\n")
        assert.are.equal(expected, export_markdown.build(nested, "nest", "2026-07-30 10:00"))
    end)

    it("writes the file and reports the pending count", function()
        local path = vim.fn.tempname() .. ".md"
        local ok, msg = export_markdown.write(path, FIXTURE, "work")
        assert.is_true(ok)
        assert.is_not_nil(msg:find("5 pending todos", 1, true))
        assert.are.equal("# work", vim.fn.readfile(path)[1])
        os.remove(path)
    end)
end)
