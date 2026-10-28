#!/bin/bash

# list manager for doit tmux integration
# create, rename, delete lists

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"
source "$SCRIPT_DIR/lib-source.sh"
source "$SCRIPT_DIR/lib-twin.sh"
source "$SCRIPT_DIR/lib-origin.sh"

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required"
    exit 1
fi

if ! command -v fzf &> /dev/null; then
    echo "Error: fzf is required"
    exit 1
fi

CURRENT_LIST=$(get_active_list_name)

# --select <name>: open with the cursor on that list (the board's deep link)
SELECT_LIST=""
[[ "$1" == "--select" ]] && SELECT_LIST="$2"

# Enter opens a list without touching any link. Launched from the todo manager,
# the choice goes back through $DOIT_LM_RESULT ("view|link <name>") so the caller
# re-renders in place instead of nesting a second manager; standalone, it
# replaces this popup with the todo manager pinned to that list.
finish() {
    local action="$1" name="$2"
    if [[ -n "$DOIT_LM_RESULT" ]]; then
        printf '%s %s\n' "$action" "$name" > "$DOIT_LM_RESULT"
        exit 0
    fi
    [[ "$action" == "view" ]] && exec "$SCRIPT_DIR/todo-interactive.sh" --list "$name"
    exit 0
}
WIN=$(get_tmux_window_key 2>/dev/null) || WIN=""
LIVE_WINDOWS=$(tmux list-windows -a -F '#S:#W' 2>/dev/null)

# colors
COLOR_GREEN=$'\e[1;32m'
COLOR_YELLOW=$'\e[1;33m'
COLOR_RED=$'\e[1;31m'
COLOR_DIM=$'\e[2m'
COLOR_DIM_YELLOW=$'\e[2;33m'
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
        local total=$(jq --arg list "$name" --arg today "$(date +%F)" "$RECENT_DONE_JQ"'[.todos[] | select(.done != true or (.completed_at | recent_done($list; $today)))] | length' "$list_file" 2>/dev/null || echo 0)
        local pending=$(jq '[.todos[] | select(.done == false and .in_progress != true)] | length' "$list_file" 2>/dev/null || echo 0)
        local in_progress=$(jq '[.todos[] | select(.in_progress == true)] | length' "$list_file" 2>/dev/null || echo 0)
        local done_count=$(jq --arg list "$name" --arg today "$(date +%F)" "$RECENT_DONE_JQ"'[.todos[] | select(.done == true and (.completed_at | recent_done($list; $today)))] | length' "$list_file" 2>/dev/null || echo 0)
        local overdue=$(jq -r --arg today "$(date +%F)" '[.todos[]? | select((.done | not) and ((.due_date // "") != "") and .due_date < $today)] | length' "$list_file" 2>/dev/null || echo 0)
        echo "Total: $total  Pending: $pending  In Progress: $in_progress  Done: $done_count"
        [[ "$overdue" -gt 0 ]] 2>/dev/null && printf '%s%s overdue%s\n' "$COLOR_RED" "$overdue" "$COLOR_RESET"
        echo ""
        # view order: Mine before Claude, in-progress first inside each
        jq -r --argjson w "$text_w" "$ORIGIN_JQ"'
            [.todos[] | select(.done == false)] |
            sort_by(origin_rank, (if .in_progress then 0 else 1 end), (if .priorities == "critical" then 0 elif .priorities == "urgent" then 1 elif .priorities == "important" then 2 else 3 end), .order_index) |
            .[0:5] | .[] |
            (if .in_progress then "▶ " else "• " end) + (.text | split("\n")[0][0:$w])
        ' "$list_file" 2>/dev/null | while read -r line; do
            echo "$line"
        done
        # show completed items if enabled
        if [[ "$SHOW_COMPLETED" == "true" && "$done_count" -gt 0 ]]; then
            jq -r --argjson w "$text_w" --arg list "$name" --arg today "$(date +%F)" "$RECENT_DONE_JQ"'
                [.todos[] | select(.done == true and (.completed_at | recent_done($list; $today)))] |
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
export COLOR_RED
export COLOR_RESET

# " !2 overdue" when the list has open items past their due date
overdue_badge_for_list() {
    local n
    n=$(overdue_count_for_list "$1")
    [[ "$n" =~ ^[0-9]+$ ]] || return 0
    (( n > 0 )) && printf ' %s!%s overdue%s' "$COLOR_RED" "$n" "$COLOR_RESET"
    return 0
}

# " [sess:win1, sess:win2]" for lists some window links; dead windows render dim.
# comma-joined because window names carry spaces
badge_for_list() {
    local badge="" s
    while IFS= read -r s; do
        [[ -z "$s" ]] && continue
        if grep -qxF -- "$s" <<< "$LIVE_WINDOWS"; then
            badge+=", ${COLOR_YELLOW}${s}${COLOR_RESET}"
        else
            badge+=", ${COLOR_DIM_YELLOW}${s}${COLOR_RESET}"
        fi
    done < <(windows_for_list "$1")
    [[ -n "$badge" ]] && printf ' [%s]' "${badge#, }"
}

# daily pinned to the top with its pending count; active list marked with *
build_rows() {
    local name pending marker
    if [[ -f "$LISTS_DIR/daily.json" ]] && { list_in_filter daily || [[ daily == "$CURRENT_LIST" ]]; }; then
        pending=$(jq '[.todos[] | select(.done == false)] | length' "$LISTS_DIR/daily.json" 2>/dev/null || echo 0)
        marker="  "; [[ "daily" == "$CURRENT_LIST" ]] && marker="* "
        printf '%sdaily (%s pending)%s%s\n' "$marker" "$pending" \
            "$(overdue_badge_for_list daily)" "$(badge_for_list daily)"
    fi
    while IFS= read -r name; do
        [[ -z "$name" || "$name" == "daily" ]] && continue
        list_in_filter "$name" || [[ "$name" == "$CURRENT_LIST" ]] || continue
        marker="  "; [[ "$name" == "$CURRENT_LIST" ]] && marker="* "
        printf '%s%s%s%s\n' "$marker" "$name" \
            "$(overdue_badge_for_list "$name")" "$(badge_for_list "$name")"
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
    "updated_at": $(date +%s),
    "source": "user"
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

    if [[ "$old_name" == daily ]]; then
        echo "${COLOR_RED}daily is permanent; it can't be renamed.${COLOR_RESET}"
        sleep 1
        return
    fi

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
    relink_windows_for_list "$old_name" "$SAFE_NAME"
    # a twin pair can sit inside this one list, so refs to the old name read as the new one
    local ref
    while IFS= read -r ref; do
        twin_apply "$ref" relink "$SAFE_NAME" >/dev/null
    done < <(jq -r --arg old "$old_name" --arg new "$SAFE_NAME" '.todos[] | .twin // empty | select(.list and .id)
        | "\(if .list == $old then $new else .list end)\t\(.id)"' "$LISTS_DIR/${SAFE_NAME}.json")

    # update the link if this was the active list
    if [[ "$old_name" == "$CURRENT_LIST" ]]; then
        set_active_list "$SAFE_NAME"
    fi

    echo "${COLOR_GREEN}Renamed: $old_name -> $SAFE_NAME${COLOR_RESET}"
    sleep 1
}

delete_list() {
    local list_name="$1"

    if [[ "$list_name" == daily ]]; then
        echo "${COLOR_RED}daily is permanent; it can't be deleted.${COLOR_RESET}"
        sleep 1
        return
    fi

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

    # format list with active indicator + window-link badges
    LIST_DISPLAY=$(build_rows)

    WINDOW_HINT=""
    [[ -n "$WIN" ]] && WINDOW_HINT=" - Window: $WIN"
    # rows are matched the way SELECTED_LIST is parsed below
    START_BIND=()
    if [[ -n "$SELECT_LIST" ]]; then
        ln=$(printf '%s\n' "$LIST_DISPLAY" | sed 's/\x1b\[[0-9;]*m//g; s/^[* ]*//' | awk '{print $1}' | grep -nxF -- "$SELECT_LIST" | head -1 | cut -d: -f1)
        [[ -n "$ln" ]] && START_BIND=(--bind "start:pos($ln)")
        SELECT_LIST=""
    fi
    SELECTION=$(echo "$LIST_DISPLAY" | fzf --ansi \
        "${START_BIND[@]}" \
        --header="
 List Manager - Active: $CURRENT_LIST$WINDOW_HINT   view: $(source_filter)
─────────────────────────────────────────
 n: New    r: Rename    d: Delete    b: Backup    y: Copy name
 s: Cycle view (all/mine/claude)    S: Flip list mine/claude
 ENTER: Open    l: Link to window    g: Set global    u: Unlink window    /: Search
─────────────────────────────────────────
" \
        --prompt="List > " \
        --height=100% \
        --layout=reverse \
        --expect=n,r,d,b,y,l,g,u,s,S,enter,q,/ \
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
        "s")
            cycle_source_filter > /dev/null
            ;;
        "S")
            if [[ -n "$SELECTED_LIST" ]]; then
                new_src=$(toggle_list_source "$SELECTED_LIST") &&
                    echo "${COLOR_GREEN}$SELECTED_LIST: $([[ $new_src == user ]] && echo mine || echo claude)${COLOR_RESET}"
                sleep 0.5
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
                --header=" Type to filter, Enter to open, Esc to cancel" \
                --prompt="/ " \
                --height=100% \
                --layout=reverse \
                --preview='bash -c "preview_list {}"' \
                --preview-window=right:50%:wrap)

            if [[ -n "$SEARCH_RESULT" ]]; then
                SEARCH_LIST=$(echo "$SEARCH_RESULT" | sed 's/^[* ]*//' | awk '{print $1}')
                [[ -n "$SEARCH_LIST" ]] && finish view "$SEARCH_LIST"
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
            if [[ -n "$WIN" ]]; then
                unlink_current_window
                echo "${COLOR_GREEN}Unlinked window '$WIN' (falls back to daily)${COLOR_RESET}"
                sleep 0.5
            fi
            ;;
        "enter")
            [[ -n "$SELECTED_LIST" ]] && finish view "$SELECTED_LIST"
            ;;
        "l")
            if [[ -n "$SELECTED_LIST" ]]; then
                set_active_list "$SELECTED_LIST"
                finish link "$SELECTED_LIST"
            fi
            ;;
    esac
done
