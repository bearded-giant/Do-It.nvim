import assert from "node:assert/strict";
import { isSequenced, setSequence } from "./sequence.js";

const mk = (id, sequence, extra = {}) => ({ id, done: false, in_progress: false, ...(sequence ? { sequence } : {}), ...extra });
const seqs = todos => Object.fromEntries(todos.map(t => [t.id, t.sequence ?? null]));

// insert into a contiguous run shifts only the run
{
    const todos = [mk("a", 1), mk("b", 2), mk("c", 3), mk("d", 7), mk("x")];
    setSequence(todos, todos[4], 2);
    assert.deepEqual(seqs(todos), { a: 1, b: 3, c: 4, d: 7, x: 2 });
}

// a free slot shifts nothing
{
    const todos = [mk("a", 2), mk("b", 3), mk("x")];
    setSequence(todos, todos[2], 1);
    assert.deepEqual(seqs(todos), { a: 2, b: 3, x: 1 });
}

// moving an item down leaves its old slot as a gap, no double shift
{
    const todos = [mk("a", 1), mk("b", 2), mk("c", 3)];
    setSequence(todos, todos[0], 3);
    assert.deepEqual(seqs(todos), { a: 3, b: 2, c: 4 });
}

// 0 clears; done and in-progress items neither collide nor shift
{
    const todos = [mk("a", 1), mk("d", 2, { done: true }), mk("p", 2, { in_progress: true }), mk("x", 5)];
    setSequence(todos, todos[3], 2);
    assert.deepEqual(seqs(todos), { a: 1, d: 2, p: 2, x: 2 });
    assert.equal(isSequenced(todos[1]), false);
    setSequence(todos, todos[0], 0);
    assert.equal(todos[0].sequence, undefined);
}

console.log("sequence.test.mjs ok");
