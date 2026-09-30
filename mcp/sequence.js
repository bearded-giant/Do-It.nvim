// Mirrors state/sorting.lua's sequenced()/set_sequence() and the tmux S key, so all
// three views agree on the run queue.

export function isSequenced(todo) {
    return typeof todo.sequence === "number" && !todo.done && !todo.in_progress;
}

// Only the colliding run (pos, pos+1, ...) shifts down, so the other labels stay put.
export function setSequence(todos, target, pos) {
    delete target.sequence;
    if (!pos || pos < 1) return;
    const taken = new Set(todos.filter(t => t !== target && isSequenced(t)).map(t => t.sequence));
    let free = pos;
    while (taken.has(free)) free++;
    for (const t of todos) {
        if (t !== target && isSequenced(t) && t.sequence >= pos && t.sequence < free) t.sequence++;
    }
    target.sequence = pos;
}
