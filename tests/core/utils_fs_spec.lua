local fs = require("doit.core.utils.fs")
local path = require("doit.core.utils.path")

describe("core utils fs", function()
    local test_dir

    before_each(function()
        test_dir = "/tmp/doit_fs_test_" .. os.time() .. "_" .. math.random(1000)
        path.ensure_dir(test_dir)
    end)

    after_each(function()
        os.execute("rm -rf " .. test_dir)
    end)

    describe("read_file", function()
        it("should read file contents", function()
            local file_path = test_dir .. "/test.txt"
            local f = io.open(file_path, "w")
            f:write("hello world")
            f:close()

            local content = fs.read_file(file_path)
            assert.are.equal("hello world", content)
        end)

        it("should return nil for non-existent file", function()
            local content = fs.read_file(test_dir .. "/nonexistent.txt")
            assert.is_nil(content)
        end)
    end)

    describe("write_file", function()
        it("should write content to file", function()
            local file_path = test_dir .. "/output.txt"
            local ok = fs.write_file(file_path, "test content")
            assert.is_true(ok)

            local content = fs.read_file(file_path)
            assert.are.equal("test content", content)
        end)

        it("should create parent directories", function()
            local file_path = test_dir .. "/sub/dir/output.txt"
            local ok = fs.write_file(file_path, "nested")
            assert.is_true(ok)

            local content = fs.read_file(file_path)
            assert.are.equal("nested", content)
        end)

        it("should overwrite existing file", function()
            local file_path = test_dir .. "/overwrite.txt"
            fs.write_file(file_path, "first")
            fs.write_file(file_path, "second")

            local content = fs.read_file(file_path)
            assert.are.equal("second", content)
        end)
    end)

    describe("read_json / write_json", function()
        it("should round-trip JSON data", function()
            local file_path = test_dir .. "/data.json"
            local data = { name = "test", count = 42, items = { "a", "b" } }

            local ok = fs.write_json(file_path, data)
            assert.is_true(ok)

            local loaded = fs.read_json(file_path)
            assert.are.equal("test", loaded.name)
            assert.are.equal(42, loaded.count)
            assert.are.equal(2, #loaded.items)
        end)

        it("should return nil for non-existent JSON file", function()
            local data = fs.read_json(test_dir .. "/nonexistent.json")
            assert.is_nil(data)
        end)

        it("should return nil for invalid JSON", function()
            local file_path = test_dir .. "/bad.json"
            fs.write_file(file_path, "not valid json {{{")

            local data = fs.read_json(file_path)
            assert.is_nil(data)
        end)
    end)

    describe("list_files", function()
        it("should list files in directory", function()
            fs.write_file(test_dir .. "/a.txt", "a")
            fs.write_file(test_dir .. "/b.txt", "b")
            path.ensure_dir(test_dir .. "/subdir")

            local files = fs.list_files(test_dir)
            assert.are.equal(2, #files)
        end)

        it("should filter by pattern", function()
            fs.write_file(test_dir .. "/a.txt", "a")
            fs.write_file(test_dir .. "/b.lua", "b")

            local files = fs.list_files(test_dir, "%.txt$")
            assert.are.equal(1, #files)
            assert.truthy(files[1]:match("a%.txt$"))
        end)

        it("should return empty for non-existent directory", function()
            local files = fs.list_files(test_dir .. "/nope")
            assert.are.equal(0, #files)
        end)
    end)

    describe("list_dirs", function()
        it("should list only directories", function()
            fs.write_file(test_dir .. "/file.txt", "x")
            path.ensure_dir(test_dir .. "/dir1")
            path.ensure_dir(test_dir .. "/dir2")

            local dirs = fs.list_dirs(test_dir)
            assert.are.equal(2, #dirs)
        end)

        it("should return empty for non-existent directory", function()
            local dirs = fs.list_dirs(test_dir .. "/nope")
            assert.are.equal(0, #dirs)
        end)
    end)

    describe("rename", function()
        it("should rename a file", function()
            local old = test_dir .. "/old.txt"
            local new = test_dir .. "/new.txt"
            fs.write_file(old, "content")

            local ok = fs.rename(old, new)
            assert.is_true(ok)
            assert.is_nil(fs.read_file(old))
            assert.are.equal("content", fs.read_file(new))
        end)

        it("should return false for non-existent source", function()
            local ok, err = fs.rename(test_dir .. "/nope.txt", test_dir .. "/dest.txt")
            assert.is_false(ok)
        end)
    end)

    describe("delete", function()
        it("should delete a file", function()
            local file_path = test_dir .. "/delete_me.txt"
            fs.write_file(file_path, "gone")

            local ok = fs.delete(file_path)
            assert.is_true(ok)
            assert.is_nil(fs.read_file(file_path))
        end)

        it("should return false for non-existent file", function()
            local ok, err = fs.delete(test_dir .. "/nope.txt")
            assert.is_false(ok)
        end)
    end)
end)
