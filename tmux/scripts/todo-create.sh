#!/bin/bash

# Create a new todo item for the daily list
TODO_LIST_PATH="$HOME/.local/share/nvim/doit/lists/daily.json"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    exit 1
fi

# Check if the daily list file exists
if [[ ! -f "$TODO_LIST_PATH" ]]; then
    echo "Error: Daily todo list not found at $TODO_LIST_PATH"
    echo "Please create a 'daily' list in Do-It.nvim first"
    exit 1
fi

# Colors for display
BOLD='\033[1m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
RESET='\033[0m'

# Create a temporary file for multi-line input
TEMP_FILE=$(mktemp /tmp/todo_create.XXXXXX)

# Display header
clear
echo -e "${BLUE}${BOLD}╭─────────────────────────────────────────────╮${RESET}"
echo -e "${BLUE}${BOLD}│         Create New Todo - Daily List        │${RESET}"
echo -e "${BLUE}${BOLD}╰─────────────────────────────────────────────╯${RESET}"
echo ""
echo -e "${BOLD}Instructions:${RESET}"
echo "• Enter your todo text (can be multiple lines)"
echo "• Press Ctrl+D when done to save"
echo "• Press Ctrl+C to cancel"
echo ""
echo -e "${BLUE}─────────────────────────────────────────────${RESET}"
echo ""

# Open editor for input (using default editor or nano)
EDITOR=${EDITOR:-nano}

# For a simpler inline experience without external editor
if [[ "$1" == "--inline" ]] || [[ "$EDITOR" == "none" ]]; then
    echo -e "${BOLD}Enter todo text (press Ctrl+D when done):${RESET}"
    echo ""
    cat > "$TEMP_FILE"
else
    # Use the system editor
    echo -e "${BOLD}Opening editor for todo entry...${RESET}"
    sleep 1

    # Add template to temp file
    echo "# Enter your todo text below (lines starting with # will be ignored)" > "$TEMP_FILE"
    echo "# You can write multiple lines. Save and exit when done." >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"

    # Open editor
    $EDITOR "$TEMP_FILE"

    # Remove comment lines
    grep -v '^#' "$TEMP_FILE" > "${TEMP_FILE}.clean"
    mv "${TEMP_FILE}.clean" "$TEMP_FILE"
fi

# Check if any text was entered
if [[ ! -s "$TEMP_FILE" ]]; then
    echo ""
    echo "No todo text entered. Cancelled."
    rm -f "$TEMP_FILE"
    exit 0
fi

# Read the todo text and combine multi-line into single line with spaces
TODO_TEXT=$(cat "$TEMP_FILE" | tr '\n' ' ' | sed 's/  */ /g' | xargs)

# Clean up temp file
rm -f "$TEMP_FILE"

# Check if text is empty after processing
if [[ -z "$TODO_TEXT" ]]; then
    echo "No valid todo text entered. Cancelled."
    exit 0
fi

# Create backup
cp "$TODO_LIST_PATH" "${TODO_LIST_PATH}.bak"

# Generate a unique ID (timestamp + random)
TODO_ID="${EPOCHSECONDS:-$(date +%s)}_$(( RANDOM * RANDOM % 9999999 ))"

# Get the highest order_index
MAX_ORDER=$(jq '.todos | map(.order_index) | max // 0' "$TODO_LIST_PATH")
NEW_ORDER=$((MAX_ORDER + 1))

# Add the new todo to the list
jq --arg id "$TODO_ID" \
   --arg text "$TODO_TEXT" \
   --arg order "$NEW_ORDER" \
   '.todos += [{
      id: $id,
      text: $text,
      done: false,
      in_progress: false,
      order_index: ($order | tonumber),
      timestamp: (now | floor),
      "_score": 10
   }] |
   ._metadata.updated_at = (now | floor)' \
   "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"

# Verify the todo was added
if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✓ Todo created successfully!${RESET}"
    echo -e "${BOLD}Text:${RESET} $TODO_TEXT"

    # Show quick stats
    TOTAL=$(jq '.todos | length' "$TODO_LIST_PATH")
    PENDING=$(jq '[.todos[] | select(.done == false)] | length' "$TODO_LIST_PATH")
    echo ""
    echo -e "${BOLD}Daily list now has:${RESET} $TOTAL todos ($PENDING pending)"

    # Option to immediately mark as in-progress
    echo ""
    echo -n "Mark as in-progress? (y/N): "
    read -n 1 -r REPLY
    echo

    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        # Clear all other in_progress flags and set this one
        jq --arg id "$TODO_ID" '
            .todos |= map(
                if .id == $id then
                    .in_progress = true
                else
                    .in_progress = false
                end
            ) |
            ._metadata.updated_at = (now | floor)
        ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"

        echo -e "${GREEN}▶ Marked as in-progress${RESET}"
    fi
else
    echo ""
    echo "Error: Failed to create todo"
    # Restore backup
    mv "${TODO_LIST_PATH}.bak" "$TODO_LIST_PATH"
    exit 1
fi

echo ""
echo "Press any key to close..."
read -n 1 -s