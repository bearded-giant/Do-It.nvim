local doit_state = require("doit.state")
local tags = require("doit.state.tags")

describe("tags", function()
	before_each(function()
		doit_state.todos = {
			{ text = "Todo with #tag1", done = false },
			{ text = "Todo with #tag2 and #tag3", done = false },
			{ text = "Another #tag1 todo", done = true },
			{ text = "No tags here", done = false },
		}
		doit_state.save_to_disk = function() end -- Mock save_to_disk
	end)

	it("should get all unique tags", function()
		local all_tags = doit_state.get_all_tags()

		assert.are.equal(3, #all_tags)

		assert.are.equal("tag1", all_tags[1])
		assert.are.equal("tag2", all_tags[2])
		assert.are.equal("tag3", all_tags[3])
	end)

	it("should set tag filter", function()
		assert.is_nil(doit_state.active_filter)

		doit_state.set_filter("tag1")
		assert.are.equal("tag1", doit_state.active_filter)

		doit_state.set_filter(nil)
		assert.is_nil(doit_state.active_filter)
	end)

	it("should rename tags in all todos", function()
		doit_state.rename_tag("tag1", "newtag")

		assert.are.equal("Todo with #newtag", doit_state.todos[1].text)
		assert.are.equal("Another #newtag todo", doit_state.todos[3].text)

		assert.are.equal("Todo with #tag2 and #tag3", doit_state.todos[2].text)
	end)

	it("should delete tags from all todos", function()
		doit_state.delete_tag("tag1")

		assert.are.equal("Todo with ", doit_state.todos[1].text)
		assert.are.equal("Another  todo", doit_state.todos[3].text)

		assert.are.equal("Todo with #tag2 and #tag3", doit_state.todos[2].text)
	end)

	it("should delete tag at the end of a line", function()
		table.insert(doit_state.todos, { text = "Todo with tag at end #tagend", done = false })

		doit_state.delete_tag("tagend")

		assert.are.equal("Todo with tag at end ", doit_state.todos[5].text)
	end)
end)
