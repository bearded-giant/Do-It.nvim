local sorting = require("doit.modules.todos.state.sorting")

local function todo(id, opts)
	opts = opts or {}
	return {
		id = id,
		text = opts.text or id,
		done = opts.done or false,
		in_progress = opts.in_progress or false,
		priorities = opts.priorities,
		order_index = opts.order_index or 0,
		parent_id = opts.parent_id,
		depth = opts.depth,
		created_at = opts.created_at or 0,
	}
end

local function ids(list)
	local out = {}
	for _, t in ipairs(list) do
		table.insert(out, t.id)
	end
	return out
end

describe("structure-aware ordering", function()
	it("keeps a child directly under its parent", function()
		local ordered = sorting.structure_aware({
			todo("b", { order_index = 2 }),
			todo("a", { order_index = 1 }),
			todo("a1", { parent_id = "a", order_index = 5 }),
		})

		assert.are.same({ "a", "a1", "b" }, ids(ordered))
	end)

	it("assigns depth from the tree, not from stored values", function()
		local ordered = sorting.structure_aware({
			todo("root", { order_index = 1 }),
			todo("kid", { parent_id = "root", order_index = 2, depth = 99 }),
			todo("grandkid", { parent_id = "kid", order_index = 3 }),
		})

		assert.are.same({ "root", "kid", "grandkid" }, ids(ordered))
		assert.are.equal(0, ordered[1].depth)
		assert.are.equal(1, ordered[2].depth)
		assert.are.equal(2, ordered[3].depth)
	end)

	it("never splits a subtree across a priority boundary", function()
		-- the child has no priority, so a flat sort would drop it below "urgent"
		local ordered = sorting.structure_aware({
			todo("low-parent", { order_index = 2 }),
			todo("low-child", { parent_id = "low-parent", order_index = 3 }),
			todo("urgent-item", { priorities = "urgent", order_index = 1 }),
		})

		assert.are.same({ "urgent-item", "low-parent", "low-child" }, ids(ordered))
	end)

	it("keeps a child with a done parent attached to it", function()
		local ordered = sorting.structure_aware({
			todo("done-parent", { done = true, order_index = 1 }),
			todo("open-child", { parent_id = "done-parent", order_index = 2 }),
			todo("open-other", { order_index = 3 }),
		})

		-- done sorts last, and the child rides along rather than jumping up
		assert.are.same({ "open-other", "done-parent", "open-child" }, ids(ordered))
	end)

	it("treats a child of a missing parent as top level", function()
		local ordered = sorting.structure_aware({
			todo("orphan", { parent_id = "gone", order_index = 1 }),
			todo("normal", { order_index = 2 }),
		})

		assert.are.same({ "orphan", "normal" }, ids(ordered))
		assert.are.equal(0, ordered[1].depth)
	end)

	it("does not lose todos caught in a parent cycle", function()
		local ordered = sorting.structure_aware({
			todo("x", { parent_id = "y" }),
			todo("y", { parent_id = "x" }),
			todo("z"),
		})

		assert.are.equal(3, #ordered)
	end)

	it("does not drop a todo that is its own parent", function()
		local ordered = sorting.structure_aware({
			todo("self", { parent_id = "self" }),
		})

		assert.are.same({ "self" }, ids(ordered))
	end)
end)

describe("nesting render", function()
	local doit_state

	before_each(function()
		package.loaded["doit.state"] = nil
		local doit = require("doit")
		doit.setup({ modules = { todos = { enabled = true } } })
		doit_state = require("doit.state")
		doit_state.todos = {}
		doit_state.save_to_disk = function() end
		doit_state.save_todos = function() end
	end)

	local function line_of(rows, todo)
		for i, row in ipairs(rows) do
			if row.todo == todo and row.is_first then
				return i
			end
		end
		return nil
	end

	it("keeps a done subtask under its open parent, above the completed divider", function()
		local parent = doit_state.add_todo("parent", {})
		local child = doit_state.add_todo("child", {}, parent.id)
		local other = doit_state.add_todo("other", {})
		child.done = true

		local rows = require("doit.ui.main_window").build_render_rows()

		assert.are.equal(line_of(rows, parent) + 1, line_of(rows, child))
		assert.is_truthy(rows[line_of(rows, child)].display:find("^  "))
		local divider
		for i, row in ipairs(rows) do
			if row.kind == "divider" then
				divider = i
			end
		end
		assert.is_nil(divider)
		assert.is_true(line_of(rows, other) > line_of(rows, child))
	end)

	it("does not open a new priority header between an urgent parent and its default child", function()
		local urgent = doit_state.add_todo("urgent parent", "urgent")
		local child = doit_state.add_todo("plain child", {}, urgent.id)
		doit_state.add_todo("plain root", {})

		local rows = require("doit.ui.main_window").build_render_rows()

		assert.are.equal(line_of(rows, urgent) + 1, line_of(rows, child))
		local headers = 0
		for _, row in ipairs(rows) do
			if row.kind == "priority_header" then
				headers = headers + 1
			end
		end
		assert.are.equal(2, headers)
	end)

	it("resolves the cursor line of an indented child to that child", function()
		local parent = doit_state.add_todo("parent", {})
		local child = doit_state.add_todo("child", {}, parent.id)

		local main_window = require("doit.ui.main_window")
		local rows = main_window.build_render_rows()
		main_window._rendered_rows = rows

		assert.are.equal(child, rows[line_of(rows, child)].todo)
	end)
end)

describe("nesting mutations", function()
	local doit_state

	before_each(function()
		package.loaded["doit.state"] = nil
		local doit = require("doit")
		doit.setup({ modules = { todos = { enabled = true } } })
		doit_state = require("doit.state")
		doit_state.todos = {}
		doit_state.deleted_todos = {}
		doit_state.MAX_UNDO_HISTORY = 10
		doit_state.save_to_disk = function() end
		doit_state.save_todos = function() end
	end)

	it("sets depth from the parent when creating a child", function()
		local parent = doit_state.add_todo("parent", {})
		local child = doit_state.add_todo("child", {}, parent.id)
		local grandchild = doit_state.add_todo("grandchild", {}, child.id)

		assert.are.equal(parent.id, child.parent_id)
		assert.are.equal(1, child.depth)
		assert.are.equal(2, grandchild.depth)
	end)

	it("ignores a parent id that does not exist", function()
		local orphan = doit_state.add_todo("orphan", {}, "nope")

		assert.is_nil(orphan.parent_id)
	end)

	it("promotes children when the parent is deleted", function()
		local parent = doit_state.add_todo("parent", {})
		local child = doit_state.add_todo("child", {}, parent.id)
		local grandchild = doit_state.add_todo("grandchild", {}, child.id)

		doit_state.delete_todo(1) -- the parent

		assert.is_nil(child.parent_id)
		assert.are.equal(0, child.depth)
		-- the grandchild stays attached to its parent and just re-depths
		assert.are.equal(child.id, grandchild.parent_id)
		assert.are.equal(1, grandchild.depth)
	end)

	it("promotes children when a completed parent is cleared", function()
		local parent = doit_state.add_todo("parent", {})
		local child = doit_state.add_todo("child", {}, parent.id)
		parent.done = true

		doit_state.delete_completed()

		assert.is_nil(child.parent_id)
		assert.are.equal(1, #doit_state.todos)
	end)

	it("does not restore a dangling parent link on undo", function()
		local parent = doit_state.add_todo("parent", {})
		doit_state.add_todo("child", {}, parent.id)

		doit_state.delete_todo(2) -- the child
		doit_state.delete_todo(1) -- the parent
		doit_state.undo_delete() -- brings the child back, parent still gone

		local restored = doit_state.todos[#doit_state.todos]
		assert.is_nil(restored.parent_id)
	end)
end)
