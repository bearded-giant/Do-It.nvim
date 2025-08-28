#!/usr/bin/env lua
-- Script to generate help documentation from the central help module
-- Run this whenever keybindings or commands change

-- Add the plugin path to package.path
package.path = package.path .. ";../lua/?.lua"

-- Load the help module
local help = require("doit.help")

-- Generate HELP.txt
local help_text = help.get_help_text()
local file = io.open("HELP.txt", "w")
if file then
	file:write(help_text)
	file:close()
	print("✓ Generated docker/HELP.txt")
else
	print("✗ Error: Could not write to HELP.txt")
	os.exit(1)
end

-- Generate markdown documentation
local markdown_text = help.get_markdown_help()
local md_file = io.open("../docs/KEYBINDINGS.md", "w")
if md_file then
	md_file:write(markdown_text)
	md_file:close()
	print("✓ Generated docs/KEYBINDINGS.md")
else
	print("✗ Error: Could not write to KEYBINDINGS.md")
	-- Don't exit with error as markdown generation is optional
end

print("\nHelp documentation updated successfully!")
print("Files generated:")
print("  • docker/HELP.txt (for interactive script)")
print("  • docs/KEYBINDINGS.md (for GitHub/documentation)")