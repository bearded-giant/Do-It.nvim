# Obsidian-Sync Module Tests

Comprehensive test suite for the obsidian-sync module.

## Test Files

### `obsidian_sync_spec.lua`
Unit tests covering:
- Module loading and metadata
- Setup configuration
- Import functionality
  - Standard checkbox format `- [ ] text`
  - Leading dash format `- [ ] - text`
  - Empty placeholder handling
  - Duplicate prevention
- List determination logic
  - Path-based mapping (daily/, inbox/, projects/)
  - Tag-based mapping (#work, #personal)
  - Default list fallback
- Sync completion states
  - Only marks `[x]` when fully completed
  - Keeps `[ ]` for in-progress items
- Reference tracking
- List management (creation, switching)

### `integration_spec.lua`
Integration tests covering:
- Command creation
- Real file operations
- Buffer manipulation
- Keymap setup

## Running Tests

### All obsidian-sync tests with Docker:
```bash
docker/run-tests.sh --dir tests/modules/obsidian-sync
```

### Run specific test pattern:
```bash
docker/run-tests.sh --pattern "obsidian_sync_spec"
```

### Simple standalone test:
```bash
nvim --headless -l tests/modules/obsidian-sync/run_simple_test.lua
```

## Test Coverage

✅ **Import Logic**
- Parses various checkbox formats
- Strips leading dashes from `- [ ] - text`
- Skips empty placeholders
- Prevents duplicate imports
- Adds tracking markers

✅ **State Management**
- Correct todo state mappings:
  - Not started: `done=false, in_progress=false` → `[ ]`
  - In progress: `done=false, in_progress=true` → `[ ]`
  - Completed: `done=true, in_progress=false` → `[x]`

✅ **List Handling**
- Creates lists automatically
- Maps folders to lists (daily/, inbox/, etc.)
- Switches between lists during import
- Restores original list after import

✅ **Edge Cases**
- Invalid buffer references
- Missing todos module
- Files outside vault path
- Already imported items

## Mocking Strategy

Since these tests run without obsidian.nvim, we mock:
- `obsidian.get_client()` - Returns nil
- `doit.core.get_module()` - Returns mock todos module
- Todo state operations

This ensures tests run reliably without external dependencies.