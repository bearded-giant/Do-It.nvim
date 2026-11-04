import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "doit-mcp-"));
const listsDir = path.join(dataDir, "lists");
fs.mkdirSync(listsDir);

fs.writeFileSync(path.join(dataDir, "session.json"), JSON.stringify({
    active_list: "daily",
    sessions: { "inv:golden": "repo-feat" },
}));
fs.writeFileSync(path.join(listsDir, "daily.json"), JSON.stringify({ todos: [], _metadata: {} }));
fs.writeFileSync(path.join(listsDir, "repo.json"), JSON.stringify({
    todos: [{ id: "repo_1", text: "claude: [bug] 1. fix the thing", done: false, order_index: 1, in_progress: true }],
    _metadata: {},
}));
fs.writeFileSync(path.join(listsDir, "repo-feat.json"), JSON.stringify({
    todos: [
        { id: "f1", text: "claude: [build] 1. wire rows", done: true, order_index: 1 },
        { id: "f2", text: "[gate] 2. pr merges (dep on #1)", done: false, order_index: 2, in_progress: true },
        { id: "f3", text: "claude: [build] 3. dashboard (dep on #2, #1)", done: false, order_index: 3, sequence: 1 },
        { id: "f4", text: "claude: [chore] 4. stamped already", done: false, order_index: 4, worktree: "main" },
        { id: "f5", text: "plain user item", done: false, order_index: 5 },
    ],
    notes: [{ id: "n1", title: "plan", body: "x", todo_ids: ["f3"] }],
    _metadata: {},
}));
fs.writeFileSync(path.join(listsDir, "loose.json"), JSON.stringify({
    todos: [{ id: "l1", text: "claude: [bug] 7. loose end (dep on #3)", done: false, order_index: 1 }],
    _metadata: {},
}));

const server = spawn("node", [path.join(here, "server.js")], {
    env: { ...process.env, DOIT_DATA_DIR: dataDir, DOIT_ACTIVE_LIST: "", TMUX: "" },
    stdio: ["pipe", "pipe", "inherit"],
});

let buffer = "";
const pending = new Map();
server.stdout.on("data", chunk => {
    buffer += chunk;
    let nl;
    while ((nl = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, nl).trim();
        buffer = buffer.slice(nl + 1);
        if (!line) continue;
        const msg = JSON.parse(line);
        const resolve = pending.get(msg.id);
        if (resolve) {
            pending.delete(msg.id);
            resolve(msg);
        }
    }
});

let nextId = 1;
function request(method, params) {
    const id = nextId++;
    return new Promise(resolve => {
        pending.set(id, resolve);
        server.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    });
}

async function callTool(name, args) {
    const res = await request("tools/call", { name, arguments: args });
    assert.ok(res.result, `${name} returned no result: ${JSON.stringify(res)}`);
    return res.result.content.map(c => c.text).join("\n");
}

const read = name => JSON.parse(fs.readFileSync(path.join(listsDir, `${name}.json`), "utf-8"));
const byText = (name, needle) => read(name).todos.find(t => t.text.includes(needle));


// worktree and feature are fields, shown as labels, and the owed twin carries them
const added = await callTool("add_todo", {
    list: "repo", text: "claude: wire token refresh", type: "build",
    worktree: "golden-runs-tooling", feature: "golden-runs", start: true,
});
assert.match(added, /Added to "repo": claude: \[build\] 2\. wire token refresh \(in_progress\) \[wt:golden-runs-tooling\] \[feat:golden-runs\]/);
let wt = byText("repo", "wire token");
assert.equal(wt.worktree, "golden-runs-tooling");
assert.equal(wt.feature, "golden-runs");

// one active item per worktree: starting in golden-runs-tooling left the unstamped item running
assert.equal(byText("repo", "fix the thing").in_progress, true);
await callTool("add_todo", { list: "repo", text: "claude: second in wt", type: "build", worktree: "golden-runs-tooling", start: true });
assert.equal(byText("repo", "wire token").in_progress, false);
assert.equal(byText("repo", "fix the thing").in_progress, true);
await callTool("start_todo", { list: "repo", id: wt.id });
assert.equal(byText("repo", "wire token").in_progress, true);
assert.equal(byText("repo", "second in wt").in_progress, false);
assert.equal(byText("repo", "fix the thing").in_progress, true);

const owed = await callTool("add_todo", { list: "repo", text: "rotate the key", type: "sec", owe: true, worktree: "main" });
assert.match(owed, /\[wt:main\]/);
assert.equal(byText("daily", "repo: rotate the key").worktree, "main");

// filters are exact; labels show in list_todos and get_todo
let listed = await callTool("list_todos", { list: "repo", worktree: "golden-runs-tooling" });
assert.match(listed, /List: repo \(2 items\)/);
assert.match(listed, /wire token refresh.*\[wt:golden-runs-tooling\] \[feat:golden-runs\]  \[id:/);
listed = await callTool("list_todos", { list: "repo", feature: "golden-runs" });
assert.match(listed, /List: repo \(1 items\)/);
assert.match(await callTool("get_todo", { id: wt.id }), /Worktree: golden-runs-tooling\nFeature: golden-runs/);

// empty string clears
await callTool("update_todo", { list: "repo", id: wt.id, feature: "" });
wt = byText("repo", "wire token");
assert.equal(wt.feature, undefined);
assert.equal(wt.worktree, "golden-runs-tooling");

// move_todo takes the target's next rank; deps into the old list drop out and are recorded
await callTool("move_todo", { id: "l1", from_list: "loose", to_list: "repo" });
const loose = byText("repo", "loose end");
assert.equal(loose.text, "claude: [bug] 5. loose end");
assert.match(loose.description, /moved from loose #7; its deps there: #3/);

// merge_list: fresh ranks after the target's, deps remapped, stamps, one active per worktree, notes, links
const merged = await callTool("merge_list", { from: "repo-feat", to: "repo", feature: "golden-runs", worktree: "golden-runs-tooling" });
assert.match(merged, /Merged 5 item\(s\) \(4 pending\) and 1 note\(s\) from "repo-feat" into "repo"; ranks #6-#9/);
const repo = read("repo");
const get = id => repo.todos.find(t => t.id === id);
assert.equal(get("f1").text, "claude: [build] 6. wire rows");
assert.equal(get("f2").text, "[gate] 7. pr merges (dep on #6)");
assert.equal(get("f3").text, "claude: [build] 8. dashboard (dep on #7, #6)");
assert.equal(get("f5").text, "plain user item");
assert.equal(get("f3").feature, "golden-runs");
assert.equal(get("f4").worktree, "main");
assert.equal(get("f2").worktree, "golden-runs-tooling");
assert.equal(get("f2").in_progress, false, "wire token already holds the golden-runs-tooling slot");
assert.equal(get("f3").sequence, 1);
assert.deepEqual(repo.notes.map(n => n.id), ["n1"]);
assert.deepEqual(read("repo-feat").todos, []);
assert.equal(JSON.parse(fs.readFileSync(path.join(dataDir, "session.json"), "utf-8")).sessions["inv:golden"], "repo");

// owed twins follow a merge, with the daily side's "from:" rank rewritten
fs.writeFileSync(path.join(listsDir, "old.json"), JSON.stringify({ todos: [], _metadata: {} }));
await callTool("add_todo", { list: "old", text: "filler", type: "chore" });
await callTool("add_todo", { list: "old", text: "approve the idp app", type: "setup", owe: true });
const mergedOwed = await callTool("merge_list", { from: "old", to: "repo" });
assert.match(mergedOwed, /1 twin\(s\) relinked/);
const projSide = byText("repo", "approve the idp app");
const dailySide = byText("daily", "approve the idp app");
assert.deepEqual(projSide.twin, { list: "daily", id: dailySide.id });
assert.deepEqual(dailySide.twin, { list: "repo", id: projSide.id });
assert.match(dailySide.text, /\[setup\] \d+\. repo: approve the idp app/);
assert.match(dailySide.description, new RegExp(`^from: repo #${projSide.text.match(/\] (\d+)\./)[1]} `));

const refused = await request("tools/call", { name: "merge_list", arguments: { from: "repo", to: "daily" } });
assert.ok(refused.result.isError, "daily is never a merge end");
assert.ok(read("repo").todos.length > 0);

server.kill();
fs.rmSync(dataDir, { recursive: true, force: true });
console.log("scope fields + merge_list: ok");
