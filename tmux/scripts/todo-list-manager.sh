#!/bin/bash

# list manager for doit tmux integration
# create, rename, delete lists

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required"
    exit 1
fi

if ! command -v fzf &> /dev/null; then
    echo "Error: fzf is required"
    exit 1
fi

CURRENT_LIST=$(get_active_list_name)
SESS=$(get_tmux_session_name 2>/dev/null) || SESS=""
LIVE_SESSIONS=$(tmux list-sessions -F '#S' 2>/dev/null)

# colors
COLOR_GREEN=$'\e[1;32m'
COLOR_YELLOW=$'\e[1;33m'
COLOR_RED=$'\e[1;31m'
COLOR_DIM=$'\e[2m'
COLOR_RESET=$'\e[0m'

# config: show completed items (default true)
SHOW_COMPLETED=$(tmux show-option -gqv @doit-show-completed)
SHOW_COMPLETED="${SHOW_COMPLETED:-true}"

preview_list() {
    # rows carry markers/badges — first word after any "* " marker is the name
    local name
    name=$(printf '%s' "$1" | sed 's/^[* ]*//' | awk '{print $1}')
    local list_file="$LISTS_DIR/${name}.json"
    # truncate to the preview pane, not a fixed column count, so wide terminals
    # show the whole line. must stay inline: fzf runs this function in a fresh
    # bash, where only exported functions exist (a helper here is not found).
    local text_w=$(( ${FZF_PREVIEW_COLUMNS:-0} - 2 ))
    (( text_w < 20 )) && text_w=200
    if [[ -f "$list_file" ]]; then
        local total=$(jq '.todos | length' "$list_file" 2>/dev/null || echo 0)
        local pending=$(jq '[.todos[] | select(.done == false and .in_progress != true)] | length' "$list_file" 2>/dev/null || echo 0)
        local in_progress=$(jq '[.todos[] | select(.in_progress == true)] | length' "$list_file" 2>/dev/null || echo 0)
        local done_count=$(jq '[.todos[] | select(.done == true)] | length' "$list_file" 2>/dev/null || echo 0)
        echo "Total: $total  Pending: $pending  In Progress: $in_progress  Done: $done_count"
        echo ""
        # show in-progress first, then pending
        jq -r --argjson w "$text_w" '
            [.todos[] | select(.done == false)] |
            sort_by((if .in_progress then 0 else 1 end), (if .priorities == "critical" then 0 elif .priorities == "urgent" then 1 elif .priorities == "important" then 2 else 3 end), .order_index) |
            .[0:5] | .[] |
            (if .in_progress then "▶ " else "• " end) + (.text | split("\n")[0][0:$w])
        ' "$list_file" 2>/dev/null | while read -r line; do
            echo "$line"
        done
        # show completed items if enabled
        if [[ "$SHOW_COMPLETED" == "true" && "$done_count" -gt 0 ]]; then
            jq -r --argjson w "$text_w" '
                [.todos[] | select(.done == true)] |
                sort_by((if .priorities == "critical" then 0 elif .priorities == "urgent" then 1 elif .priorities == "important" then 2 else 3 end), .order_index) |
                .[0:3] | .[] |
                "✓ " + (.text | split("\n")[0][0:$w])
            ' "$list_file" 2>/dev/null | while read -r line; do
                printf '%s%s%s\n' "$COLOR_DIM" "$line" "$COLOR_RESET"
            done
        fi
    fi
}
export -f preview_list
export LISTS_DIR
export SHOW_COMPLETED
export COLOR_DIM
export COLOR_RESET

# " [sess1 sess2]" for lists some session links; dead sessions render dim
badge_for_list() {
    local badge="" s
    while IFS= read -r s; do
        [[ -z "$s" ]] && continue
        if grep -qxF -- "$s" <<< "$LIVE_SESSIONS"; then
            badge+=" $s"
        else
            badge+=" ${COLOR_DIM}${s}${COLOR_RESET}"
        fi
    done < <(sessions_for_list "$1")
    [[ -n "$badge" ]] && printf ' [%s]' "${badge# }"
}

# daily pinned to the top with its pending count; active list marked with *
build_rows() {
    local name pending marker
    if [[ -f "$LISTS_DIR/daily.json" ]]; then
        pending=$(jq '[.todos[] | select(.done == false)] | length' "$LISTS_DIR/daily.json" 2>/dev/null || echo 0)
        marker="  "; [[ "daily" == "$CURRENT_LIST" ]] && marker="* "
        printf '%sdaily (%s pending)%s\n' "$marker" "$pending" "$(badge_for_list daily)"
    fi
    while IFS= read -r name; do
        [[ -z "$name" || "$name" == "daily" ]] && continue
        marker="  "; [[ "$name" == "$CURRENT_LIST" ]] && marker="* "
        printf '%s%s%s\n' "$marker" "$name" "$(badge_for_list "$name")"
    done < <(get_available_lists)
}

create_list() {
    echo ""
    echo -n "New list name: "
    read -r NEW_NAME

    if [[ -z "$NEW_NAME" ]]; then
        echo "Cancelled"
        return
    fi

    # sanitize name (alphanumeric, dash, underscore only)
    SAFE_NAME=$(sanitize_list_name "$NEW_NAME")

    if [[ -f "$LISTS_DIR/${SAFE_NAME}.json" ]]; then
        echo "${COLOR_RED}Error: List '$SAFE_NAME' already exists${COLOR_RESET}"
        sleep 1
        return
    fi

    # create new list with empty structure
    cat > "$LISTS_DIR/${SAFE_NAME}.json" << EOF
{
  "todos": [],
  "_metadata": {
    "created_at": $(date +%s),
    "updated_at": $(date +%s)
  }
}
EOF

    echo "${COLOR_GREEN}Created list: $SAFE_NAME${COLOR_RESET}"

    echo -n "Switch to new list? (Y/n): "
    read -n 1 -r SWITCH
    echo
    if [[ ! "$SWITCH" =~ ^[Nn]$ ]]; then
        set_active_list "$SAFE_NAME"
        echo "Switched to: $SAFE_NAME"
    fi
    sleep 1
}

rename_list() {
    local old_name="$1"

    if [[ "$old_name" == "$CURRENT_LIST" ]]; then
        echo "${COLOR_YELLOW}Warning: Renaming active list${COLOR_RESET}"
    fi

    echo -n "New name for '$old_name': "
    read -r NEW_NAME

    if [[ -z "$NEW_NAME" ]]; then
        echo "Cancelled"
        return
    fi

    SAFE_NAME=$(sanitize_list_name "$NEW_NAME")

    if [[ -f "$LISTS_DIR/${SAFE_NAME}.json" ]]; then
        echo "${COLOR_RED}Error: List '$SAFE_NAME' already exists${COLOR_RESET}"
        sleep 1
        return
    fi

    mv "$LISTS_DIR/${old_name}.json" "$LISTS_DIR/${SAFE_NAME}.json"
    relink_sessions_for_list "$old_name" "$SAFE_NAME"

    # update session if this was active list
    if [[ "$old_name" == "$CURRENT_LIST" ]]; then
        set_active_list "$SAFE_NAME"
    fi

    echo "${COLOR_GREEN}Renamed: $old_name -> $SAFE_NAME${COLOR_RESET}"
    sleep 1
}

delete_list() {
    local list_name="$1"

    if [[ "$list_name" == "$CURRENT_LIST" ]]; then
        echo "${COLOR_RED}Cannot delete active list. Switch to another list first.${COLOR_RESET}"
        sleep 1
        return
    fi

    local todo_count=$(jq '.todos | length' "$LISTS_DIR/${list_name}.json" 2>/dev/null || echo 0)

    echo -n "${COLOR_RED}Delete '$list_name' ($todo_count todos)? Type 'yes' to confirm: ${COLOR_RESET}"
    read -r CONFIRM

    if [[ "$CONFIRM" == "yes" ]]; then
        rm -f "$LISTS_DIR/${list_name}.json"
        prune_links_for_list "$list_name"
        echo "${COLOR_GREEN}Deleted: $list_name${COLOR_RESET}"
    else
        echo "Cancelled"
    fi
    sleep 1
}

# main loop
while true; do
    clear
    CURRENT_LIST=$(get_active_list_name)

    # format list with active indicator + session-link badges
    LIST_DISPLAY=$(build_rows)

    SESSION_HINT=""
    [[ -n "$SESS" ]] && SESSION_HINT=" - Session: $SESS"
    SELECTION=$(echo "$LIST_DISPLAY" | fzf --ansi \
        --header="
 List Manager - Active: $CURRENT_LIST$SESSION_HINT
─────────────────────────────────────────
 n: New    r: Rename    d: Delete    b: Backup    y: Copy name
 ENTER: Link to session    g: Set global    u: Unlink session    /: Search
─────────────────────────────────────────
" \
        --prompt="List > " \
        --height=100% \
        --layout=reverse \
        --expect=n,r,d,b,y,g,u,enter,q,/ \
        --preview='bash -c "preview_list {}"' \
        --preview-window=right:50%:wrap)

    KEY=$(echo "$SELECTION" | head -1)
    LIST_LINE=$(echo "$SELECTION" | tail -1)

    # extract list name from line (strip marker, count, badges)
    SELECTED_LIST=$(echo "$LIST_LINE" | sed 's/^[* ]*//' | awk '{print $1}')

    case "$KEY" in
        "q"|"")
            break
            ;;
        "n")
            create_list
            ;;
        "r")
            if [[ -n "$SELECTED_LIST" ]]; then
                rename_list "$SELECTED_LIST"
            fi
            ;;
        "d")
            if [[ -n "$SELECTED_LIST" ]]; then
                delete_list "$SELECTED_LIST"
            fi
            ;;
        "/")
            # search mode: re-launch fzf with filtering enabled
            SEARCH_RESULT=$(echo "$LIST_DISPLAY" | fzf --ansi \
                --header=" Type to filter, Enter to switch, Esc to cancel" \
                --prompt="/ " \
                --height=100% \
                --layout=reverse \
                --preview='bash -c "preview_list {}"' \
                --preview-window=right:50%:wrap)

            if [[ -n "$SEARCH_RESULT" ]]; then
                SEARCH_LIST=$(echo "$SEARCH_RESULT" | sed 's/^[* ]*//' | awk '{print $1}')
                if [[ -n "$SEARCH_LIST" ]]; then
                    set_active_list "$SEARCH_LIST"
                    break
                fi
            fi
            ;;
        "y")
            if [[ -n "$SELECTED_LIST" ]]; then
                if command -v pbcopy &>/dev/null; then
                    printf '%s' "$SELECTED_LIST" | pbcopy
                elif command -v xclip &>/dev/null; then
                    printf '%s' "$SELECTED_LIST" | xclip -selection clipboard
                elif command -v xsel &>/dev/null; then
                    printf '%s' "$SELECTED_LIST" | xsel --clipboard
                else
                    echo "${COLOR_RED}No clipboard tool found (pbcopy/xclip/xsel)${COLOR_RESET}"
                    sleep 1
                    continue
                fi
                echo "${COLOR_GREEN}Copied list name: $SELECTED_LIST${COLOR_RESET}"
                sleep 0.5
            fi
            ;;
        "b")
            "$SCRIPT_DIR/todo-backup.sh"
            sleep 1
            ;;
        "g")
            if [[ -n "$SELECTED_LIST" ]]; then
                set_global_list "$SELECTED_LIST"
                echo "${COLOR_GREEN}Global list set: $SELECTED_LIST${COLOR_RESET}"
                sleep 0.5
            fi
            ;;
        "u")
            if [[ -n "$SESS" ]]; then
                unlink_session "$SESS"
                echo "${COLOR_GREEN}Unlinked session '$SESS' (falls back to global list)${COLOR_RESET}"
                sleep 0.5
            fi
            ;;
        "enter")
            if [[ -n "$SELECTED_LIST" ]]; then
                set_active_list "$SELECTED_LIST"
                break
            fi
            ;;
    esac
done
