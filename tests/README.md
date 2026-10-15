# doit Test Suite

## Understanding Test Output

When running the tests via `docker/run-tests.sh`, you may see warning messages in the output that look like errors but don't actually affect test results. Here's an explanation of the test output:

### Common Warning Messages

```
Testing file access with: /data/test_write.txt
❌ Failed to write test file
❌ Todos file not found or cannot be opened
Loading todos from: /data/doit_todos.json
❌ Could not open todos file for reading
```

**Explanation:** These are debug messages from `init.lua` in the Docker container. They are expected and don't indicate test failures. The Docker container is configured to isolate tests from your actual system, so file access in the `/data` directory is intentionally limited.

### Actual Test Results

The actual test results appear in blocks like this:

```
========================================	
Testing: 	/plugin/tests/state/tags_spec.lua	
[32mSuccess[0m	||	tags should get all unique tags	
[32mSuccess[0m	||	tags should set tag filter	
[32mSuccess[0m	||	tags should rename tags in all todos	
[32mSuccess[0m	||	tags should delete tags from all todos	
[32mSuccess[0m	||	tags should delete tag at the end of a line	
	
[32mSuccess: [0m	5	
[31mFailed : [0m	0	
[31mErrors : [0m	0	
========================================
```

The important parts to look for:
- `[32mSuccess[0m`: Green text indicating a passing test
- `[31mFailed[0m`: Red text indicating a failing test
- At the bottom of each test file section:
  - `Success: 5` - Number of passing tests
  - `Failed: 0` - Number of failing tests
  - `Errors: 0` - Number of errors

### Test Exit Codes

At the end of a test file run, you might see:

```
Tests Failed. Exit: 1
```

This usually appears if any test in the file failed. If all tests pass, you won't see this message.

## Running Specific Tests

`docker/run-tests.sh` takes two optional flags, so there's no need to edit the script:

```bash
# every spec file whose path contains the string
docker/run-tests.sh --pattern origin_blocks

# every spec file under a directory, or a single spec file
docker/run-tests.sh --dir tests/modules/todos
docker/run-tests.sh --dir tests/modules/todos/sorting_spec.lua
```

plenary's `test_directory` has no pattern option of its own, so the script turns `--pattern` into a list of spec files before it starts the container.

## Test Structure

The test suite is organized into the following structure:

1. **Main tests** - `tests/doit_spec.lua`: Basic plugin initialization tests

2. **State tests**:
   - `tests/state/storage_spec.lua`: Tests for saving/loading todos
   - `tests/state/todos_spec.lua`: Tests for todo CRUD operations
   - `tests/state/tags_spec.lua`: Tests for tag management
   - `tests/state/sorting_spec.lua`: Tests for todo sorting

3. **UI tests**:
   - `tests/ui/main_window_spec.lua`: Tests for the main window rendering
   - `tests/ui/search_window_spec.lua`: Tests for search functionality
