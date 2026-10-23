import assert from "node:assert/strict";
import fs from "fs";
import os from "os";
import path from "path";
import { buildVault, syncDir } from "./vault-export.js";

process.env.TZ = "UTC";

const lists = [
    {
        name: "daily",
        data: { todos: [{ id: "d_0001", text: "[gate] 7. proj: deploy chip", twin: { list: "proj", id: "a_0001" } }] },
    },
    {
        name: "proj",
        data: {
            _metadata: { updated_at: 1792111781 },
            todos: [
                {
                    id: "a_0001",
                    text: "[gate] 3. owed in daily #7: deploy chip",
                    in_progress: true,
                    priorities: "urgent",
                    created_at: 1792111781,
                    twin: { list: "daily", id: "d_0001" },
                    description: "why:\nbecause\n\n\n----------\nlast modified: 2026-10-15: 20:49",
                },
                { id: "b_0001", text: "claude: [bug] 4. fix #api parser (dep on #3)", sequence: 1, order_index: 9 },
                { id: "c_0001", text: "[chore] 5. done thing", done: true, completed_at: 1792113263 },
                { id: "e_1111", text: "buy milk", priorities: "critical", order_index: 1 },
                { id: "e_2222", text: "buy milk", order_index: 2 },
            ],
            notes: [{ id: "n_0001", title: "Plan: overview", body: "the plan", created_at: "1790643681" }],
        },
    },
];

const files = buildVault(lists, "doit-todos");

// every item, note, and index lands at a stable readable path; done items move under done/
assert.deepEqual([...files.keys()].sort(), [
    "daily/7-proj-deploy-chip.md",
    "daily/daily.md",
    "doit-todos.md",
    "proj/3-owed-in-daily-7-deploy-chip.md",
    "proj/4-fix-api-parser.md",
    "proj/buy-milk-2222.md",
    "proj/buy-milk.md",
    "proj/done/5-done-thing.md",
    "proj/notes/plan-overview.md",
    "proj/proj.md",
]);

// frontmatter carries status, twin link, and the footer timestamp; the footer leaves the body
{
    const a = files.get("proj/3-owed-in-daily-7-deploy-chip.md");
    assert.match(a, /^---\nid: "doit-a_0001"\n/);
    assert.match(a, /\ndoit_list: "proj"\n/);
    assert.match(a, /\nstatus: "in_progress"\n/);
    assert.match(a, /\npriority: "urgent"\n/);
    assert.match(a, /\ntags: \["doit", "doit\/gate"\]\n/);
    assert.match(a, /\ncreated: "2026-10-16T00:49"\n/);
    assert.match(a, /\nupdated: "2026-10-15T20:49"\n/);
    assert.match(a, /\ntwin: "\[\[doit-todos\/daily\/7-proj-deploy-chip\]\]"\n/);
    assert.match(a, /\n# 3\. owed in daily #7: deploy chip\n\nwhy:\nbecause\n$/);
    assert.doesNotMatch(a, /----------/);
}

// deps resolve rank refs to links; inline tags and the claude marker reach frontmatter
{
    const b = files.get("proj/4-fix-api-parser.md");
    assert.match(b, /\ntags: \["doit", "doit\/bug", "api"\]\n/);
    assert.match(b, /\nclaude: true\n/);
    assert.match(b, /\nsequence: 1\n/);
    assert.match(b, /\ndeps: \["\[\[doit-todos\/proj\/3-owed-in-daily-7-deploy-chip\]\]"\]\n/);
    assert.match(files.get("proj/done/5-done-thing.md"), /\nstatus: "done"\ntype: "chore"\nrank: "5"\n/);
}

// list index: in progress, then pending (sequenced first, then priority), done, notes
{
    const index = files.get("proj/proj.md");
    assert.match(index, /\nin_progress: 1\npending: 3\ndone: 1\n/);
    const order = [
        "## In progress",
        "[[doit-todos/proj/3-owed-in-daily-7-deploy-chip|3. owed in daily #7: deploy chip]] · gate · !!",
        "## Pending",
        "[[doit-todos/proj/4-fix-api-parser|4. fix #api parser (dep on #3)]] · bug",
        "[[doit-todos/proj/buy-milk|buy milk]] · !!!",
        "[[doit-todos/proj/buy-milk-2222|buy milk]]",
        "## Done",
        "[[doit-todos/proj/done/5-done-thing|5. done thing]] · chore",
        "## Notes",
        "[[doit-todos/proj/notes/plan-overview|Plan: overview]]",
    ].map(s => index.indexOf(s));
    assert.ok(order.every(i => i >= 0), `missing line in index:\n${index}`);
    assert.deepEqual(order, [...order].sort((x, y) => x - y));
    assert.match(files.get("doit-todos.md"), /\| \[\[doit-todos\/proj\/proj\\\|proj\]\] \| 1 \| 3 \| 1 \|/);
}

// sync writes changes, prunes stale generated notes only, keeps broken lists and user files
{
    const out = fs.mkdtempSync(path.join(os.tmpdir(), "doit-vault-"));
    const put = (rel, text) => {
        fs.mkdirSync(path.dirname(path.join(out, rel)), { recursive: true });
        fs.writeFileSync(path.join(out, rel), text);
    };
    const stale = '---\ndoit_list: "proj"\n---\n# old\n';
    put("proj/old.md", stale);
    put("proj/mine.md", "# my own note\n");
    put("gone/x.md", stale);
    put("broken/y.md", stale);
    fs.mkdirSync(path.join(out, "inbox"));

    syncDir(out, files, new Set(["broken"]));
    const exists = rel => fs.existsSync(path.join(out, rel));
    assert.equal(exists("proj/old.md"), false);
    assert.equal(exists("gone"), false);
    assert.equal(exists("proj/mine.md"), true);
    assert.equal(exists("broken/y.md"), true);
    assert.equal(exists("inbox"), true);
    for (const [rel, text] of files) assert.equal(fs.readFileSync(path.join(out, rel), "utf-8"), text);

    // unchanged content is not rewritten, so the vault's git sees no churn
    const probe = path.join(out, "proj/proj.md");
    fs.utimesSync(probe, 1000, 1000);
    syncDir(out, files);
    assert.equal(fs.statSync(probe).mtimeMs, 1000 * 1000);
    fs.rmSync(out, { recursive: true });
}

console.log("vault-export.test.mjs ok");
