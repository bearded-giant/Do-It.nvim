local doit_state = require("doit.state")
local tags = require("doit.state.tags")

describe("tags", function()
	before_each(function()
		-- Reinitialize the todos module for each test
		package.loaded["doit.state"] = nil  -- Clear cached state
		local doit = require("doit")
		doit.setup({
			modules = {
				todos = { enabled = true }
			}
		})
		doit_state = require("doit.state")  -- Re-require after setup
		
		doit_state.todos = {
			{ text = "Todo with #tag1", done = false },
			{ text = "Todo with #tag2 and #tag3", done = false },
			{ text = "Another #tag1 todo", done = true },
			{ text = "No tags here", done = false },
		}
		doit_state.save_to_disk = function() end -- Mock save_to_disk
	end)

	it.skip("should get all unique tags", function()
		local all_tags = doit_state.get_all_tags()

		assert.are.equal(3, #all_tags)

		-- Tags are returned as objects with name and count, sorted by count
		assert.are.equal("tag1", all_tags[1].name)
		assert.are.equal(2, all_tags[1].count)  -- tag1 appears twice
		assert.is_string(all_tags[2].name)  -- Could be tag2 or tag3 (both appear once)
		assert.is_string(all_tags[3].name)
	end)

	it("should set tag filter", function()
		assert.is_nil(doit_state.active_filter)

		doit_state.set_tag_filter("tag1")
		assert.are.equal("tag1", doit_state.active_filter)

		doit_state.set_tag_filter(nil)
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
