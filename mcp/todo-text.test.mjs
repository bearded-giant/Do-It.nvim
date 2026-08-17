import assert from "node:assert/strict";
import { parseTodoText, nextRank, composeTodoText, normalizeTodoText } from "./todo-text.js";

// parse
assert.deepEqual(parseTodoText("[gate] 30. pre-store check"), {
    claude: false, type: "gate", rank: 30, rankLabel: "30", body: "pre-store check",
});
assert.deepEqual(parseTodoText("claude: [loader] 4. seed data"), {
    claude: true, type: "loader", rank: 4, rankLabel: "4", body: "seed data",
});
assert.deepEqual(parseTodoText("5b. audit ops"), {
    claude: false, type: null, rank: 5, rankLabel: "5b", body: "audit ops",
});
assert.deepEqual(parseTodoText("logic port"), {
    claude: false, type: null, rank: null, rankLabel: null, body: "logic port",
});
// a decimal is not a rank
assert.equal(parseTodoText("1.5x throughput fix").rank, null);

// next rank ignores untagged items and honors letter suffixes
assert.equal(nextRank([{ text: "1. a" }, { text: "[gate] 30. b" }, { text: "12b. c" }]), 31);
assert.equal(nextRank([]), 1);
assert.equal(nextRank([{ text: "no rank here" }]), 1);

// compose
assert.equal(
    composeTodoText("pre-store gate check", { type: "gate", rank: 41, deps: [12, "#28"] }),
    "[gate] 41. pre-store gate check (dep on #12, #28)"
);
assert.equal(
    composeTodoText("claude: seed the loader", { type: "loader", rank: 7 }),
    "claude: [loader] 7. seed the loader"
);
// idempotent — re-composing does not stack prefixes or dep suffixes
const once = composeTodoText("ship it", { type: "gate", rank: 3, deps: [1] });
assert.equal(composeTodoText(once, { type: "gate", rank: 99, deps: [1] }), once);
// a rank already in the text wins over the auto-assigned one
assert.equal(composeTodoText("[decision] 40. call it", { rank: 2 }), "[decision] 40. call it");
// an explicit type param wins, so a retype is possible
assert.equal(composeTodoText("[decision] 40. call it", { type: "gate" }), "[gate] 40. call it");
// update path keeps rank/type/claude from the old text
assert.equal(
    composeTodoText("rewritten body", { inherit: "claude: [comms] 28. old body" }),
    "claude: [comms] 28. rewritten body"
);
// deps replace rather than append, and [] clears them
assert.equal(
    composeTodoText("[gate] 3. x (dep on #1)", { deps: [9] }),
    "[gate] 3. x (dep on #9)"
);
assert.equal(composeTodoText("[gate] 3. x (dep on #1)", { deps: [] }), "[gate] 3. x");

// --- normalizeTodoText (dedupe) ---
// NORMALIZE_FIXTURES is mirrored in tests/modules/todos/normalize_spec.lua.
// Any change here must land there in the same commit or the two surfaces
// silently disagree about what counts as a duplicate.
const NORMALIZE_FIXTURES = [
    ["buy milk", "buy milk"],
    ["claude: [chore] 3. buy milk (dep on #1)", "buy milk"],
    ["Claude: [Chore] 3. Buy Milk (Dep On #1)", "buy milk"],
    ["  buy   milk  ", "buy milk"],
    ["buy\nmilk", "buy milk"],
    // a note-link prefix is not a type tag and must survive
    ["[[my note]] buy milk", "[[my note]] buy milk"],
    // a rank needs the trailing space, so these keep their leading number
    ["1.5x throughput fix", "1.5x throughput fix"],
    ["3.buy milk", "3.buy milk"],
    // lettered rank suffixes are still ranks
    ["5b. audit ops", "audit ops"],
    ["", ""],
    // empty body: the rank keeps its dot because nothing follows the space it
    // requires. Two empty-bodied items with different ranks stay distinct, which
    // is what we want — collapsing them would be a silent data loss.
    ["claude: [gate] 12.", "12."],
];
for (const [input, want] of NORMALIZE_FIXTURES) {
    assert.equal(normalizeTodoText(input), want, `normalize(${JSON.stringify(input)})`);
}
// the whole point: nvim-typed and MCP-created forms collapse together
assert.equal(
    normalizeTodoText("buy milk"),
    normalizeTodoText("claude: [chore] 3. buy milk (dep on #1)")
);
// but genuinely different bodies do not
assert.notEqual(normalizeTodoText("buy milk"), normalizeTodoText("buy bread"));

console.log("todo-text: all checks passed");
