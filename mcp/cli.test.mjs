// The CLI drives the MCP tools in-process; piped stdio makes it non-interactive,
// so every prompt it would show must instead fail with a usage error.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const cli = path.join(here, "cli.js");
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "doit-cli-"));
const listsDir = path.join(dataDir, "lists");
fs.mkdirSync(listsDir);
fs.writeFileSync(path.join(dataDir, "session.json"), JSON.stringify({ active_list: "proj" }));
fs.writeFileSync(path.join(listsDir, "daily.json"), JSON.stringify({ todos: [], _metadata: {} }));

const env = { ...process.env, DOIT_DATA_DIR: dataDir, DOIT_ACTIVE_LIST: "", DOIT_PINNED_LIST: "", TMUX: "", TMUX_PANE: "" };
const run = (args, input = "") => spawnSync("node", [cli, ...args], { env, input, encoding: "utf-8" });
const ok = args => {
    const r = run(args);
    assert.equal(r.status, 0, `doit ${args.join(" ")}: ${r.stderr}`);
    return r.stdout;
};
const todos = list => JSON.parse(fs.readFileSync(path.join(listsDir, `${list}.json`), "utf-8")).todos;
const byText = (list, text) => todos(list).find(t => t.text.includes(text));

ok(["list", "add", "proj"]);
assert.ok(fs.existsSync(path.join(listsDir, "proj.json")));
let r = run(["list", "add", "../escape"]);
assert.equal(r.status, 1);
assert.match(r.stderr, /letters, digits/);

// a plain add lands on the current list, written like an nvim/tmux item: no rank, source user
ok(["add", "low", "thing"]);
const low = byText("proj", "low thing");
assert.equal(low.text, "low thing");
assert.equal(low.source, "user");
ok(["add", "buy milk", "-p", "urgent", "--due", "2026-12-01"]);
const milk = byText("proj", "buy milk");
assert.equal(milk.priorities, "urgent");
assert.equal(milk.due_date, "2026-12-01");
ok(["add", "child item", "--parent", low.id]);
assert.equal(byText("proj", "child item").parent_id, low.id);

r = run(["add"]);
assert.equal(r.status, 1);
assert.match(r.stderr, /Missing item text/);

// urgent before unprioritized; a child rides directly under its parent
const lines = ok(["ls"]).split("\n");
const at = text => lines.findIndex(l => l.includes(text));
assert.ok(at("buy milk") < at("low thing"), "priority buckets order roots");
assert.equal(at("child item"), at("low thing") + 1, "subtree stays contiguous");
assert.match(lines[at("child item")], /^ {4}\[ \] child item/);

ok(["note", milk.id, "remember", "oat"]);
assert.match(byText("proj", "buy milk").description, /remember oat/);
r = run(["note", milk.id], "piped note\n");
assert.equal(r.status, 0, r.stderr);
assert.match(byText("proj", "buy milk").description, /remember oat\n\npiped note/);

ok(["edit", "milk", "--title", "buy oat milk", "-t", "chore", "--due", "none"]);
const edited = todos("proj").find(t => t.id === milk.id);
assert.equal(edited.text, "[chore] buy oat milk");
assert.equal(edited.due_date, undefined);
r = run(["edit", milk.id]);
assert.equal(r.status, 1);
assert.match(r.stderr, /Nothing to change/);

ok(["start", "oat milk"]);
assert.equal(todos("proj").find(t => t.id === milk.id).in_progress, true);
ok(["done", "oat milk"]);
assert.equal(todos("proj").find(t => t.id === milk.id).done, true);
r = run(["done", "oat milk"]);
assert.equal(r.status, 1, "done items are not open matches");
ok(["reopen", "oat milk"]);
assert.equal(todos("proj").find(t => t.id === milk.id).done, false);

assert.match(ok(["show", milk.id]), /List: proj[\s\S]*remember oat/);
assert.match(ok(["find", "remember"]), /proj .*buy oat milk/);

ok(["add", "milk a"]);
ok(["add", "milk b"]);
r = run(["done", "milk"]);
assert.equal(r.status, 1);
assert.match(r.stderr, /matches 3 items, pass an id/);

ok(["mv", milk.id, "daily"]);
assert.ok(todos("daily").some(t => t.id === milk.id));
r = run(["rm", milk.id]);
assert.equal(r.status, 1);
assert.match(r.stderr, /Missing --yes/);
ok(["rm", milk.id, "--yes"]);
assert.ok(!todos("daily").some(t => t.id === milk.id));

const listsOut = ok(["lists"]);
assert.match(listsOut, /daily/);
assert.match(listsOut, /proj/);
assert.doesNotMatch(ok(["lists", "--mine"]), /proj/, "unflagged lists are claude's");
ok(["list", "rename", "proj", "proj2"]);
assert.ok(fs.existsSync(path.join(listsDir, "proj2.json")));
ok(["list", "rm", "proj2", "--yes"]);
assert.ok(!fs.existsSync(path.join(listsDir, "proj2.json")));

assert.equal(ok(["--version"]).trim(), fs.readFileSync(path.join(here, "..", "VERSION"), "utf-8").trim());
r = run(["bogus"]);
assert.equal(r.status, 1);
assert.match(r.stderr, /Unknown command "bogus"/);

// importing server.js must not have changed what the MCP side writes
const mcp = spawnSync("node", ["-e", `
    const { server } = await import(${JSON.stringify(path.join(here, "server.js"))});
    const { Client } = await import("@modelcontextprotocol/sdk/client/index.js");
    const { InMemoryTransport } = await import("@modelcontextprotocol/sdk/inMemory.js");
    const [c, s] = InMemoryTransport.createLinkedPair();
    await server.connect(s);
    const client = new Client({ name: "t", version: "0" });
    await client.connect(c);
    await client.callTool({ name: "add_todo", arguments: { list: "daily", text: "model work", type: "chore" } });
`], { env, encoding: "utf-8", cwd: here, input: "" });
assert.equal(mcp.status, 0, mcp.stderr);
const modelItem = byText("daily", "model work");
assert.match(modelItem.text, /^\[chore\] \d+\. model work$/);
assert.equal(modelItem.source, "mcp");

fs.rmSync(dataDir, { recursive: true, force: true });
console.log("cli: ok");
