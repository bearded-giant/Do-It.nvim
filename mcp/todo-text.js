// Todo text shape: "claude: [type] N. body (dep on #M, #K)"
// N is the do-order rank the user scans in the nvim/tmux panes — priority gives
// the bucket, N gives the order inside it — and it is what deps reference.

const TEXT_SHAPE =
    /^(?<claude>claude:\s*)?(?:\[(?<type>[^\][]+)\]\s*)?(?:(?<rank>\d+)(?<suffix>[a-z]*)\.\s+)?(?<body>[\s\S]*)$/i;

const DEP_SUFFIX = /\s*\(dep on [^)]*\)\s*$/i;

// Tags live inline in the todo text, not in a schema field — same contract as
// the nvim and tmux surfaces. Matching is exact-token, so #labels never matches
// #labels-web. Charset mirrors state/tags.lua's [%w_%-/]+.
const TAG_PATTERN = /#([\w\-/]+)/g;

// all-digit tokens are rank refs ("owed in daily #73", "dep on #12"), not tags
export function parseTags(text) {
    return [...String(text || "").matchAll(TAG_PATTERN)].map(m => m[1]).filter(t => !/^\d+$/.test(t));
}

export function parseDeps(text) {
    const suffix = DEP_SUFFIX.exec(text || "");
    return suffix ? [...suffix[0].matchAll(/#(\d+[a-z]*)/gi)].map(m => m[1]) : [];
}

// Duplicate detection compares normalized text, so an item typed in nvim matches
// the same item created through MCP with a rank/type/deps wrapper around it.
// Lowercasing first is what lets the lua port (state/normalize.lua) use plain
// patterns and still agree byte-for-byte — lua has no case-insensitive matching.
const CLAUDE_PREFIX = /^claude:\s*/;
// [^\][]+ rejects both brackets, so a "[[note link]]" prefix is not eaten as a type tag.
const TYPE_TAG = /^\[[^\][]+\]\s*/;
// The trailing space is required: it keeps "1.5x throughput" and "3.buy milk" intact.
const RANK_PREFIX = /^\d+[a-z]*\.\s+/;

export function normalizeTodoText(text) {
    let s = (text || "").toLowerCase().trim();
    s = s.replace(CLAUDE_PREFIX, "");
    s = s.replace(TYPE_TAG, "");
    s = s.replace(RANK_PREFIX, "");
    s = s.replace(DEP_SUFFIX, "");
    return s.replace(/\s+/g, " ").trim();
}

export function parseTodoText(text) {
    const { groups } = TEXT_SHAPE.exec(text || "");
    return {
        claude: Boolean(groups.claude),
        type: groups.type || null,
        rank: groups.rank ? Number(groups.rank) : null,
        rankLabel: groups.rank ? `${groups.rank}${groups.suffix || ""}` : null,
        body: groups.body || "",
    };
}

const LABEL_PREFIX = /^(?:claude:\s*)?(?:\[[^\][]+\]\s*)?(?:\d+[a-z]*\.\s+)?/i;

// an owed twin names its project list ("[gate] 4. proj: body", "from: proj #4"), so a relink renames that label
export function relabelTwin(todo, oldList, newList, rankMap) {
    if (!oldList || (oldList === newList && !rankMap)) return;
    const text = todo.text || "";
    const prefix = LABEL_PREFIX.exec(text)[0];
    const rest = text.slice(prefix.length);
    if (rest.startsWith(`${oldList}: `)) todo.text = `${prefix}${newList}: ${rest.slice(oldList.length + 2)}`;
    const from = `from: ${oldList} #`;
    if ((todo.description || "").startsWith(from)) {
        let tail = todo.description.slice(from.length);
        const n = /^\d+/.exec(tail);
        if (rankMap && n && rankMap.has(Number(n[0]))) tail = `${rankMap.get(Number(n[0]))}${tail.slice(n[0].length)}`;
        todo.description = `from: ${newList} #${tail}`;
    }
}

// ranks are unique per list, so an item landing in another list takes a new rank and
// its deps follow through the same old->new map; deps the map lacks pointed into the old list
export function renumberText(text, rankMap) {
    const { groups } = TEXT_SHAPE.exec(text || "");
    const remap = (n, suffix) => (rankMap.has(Number(n)) ? `${rankMap.get(Number(n))}${suffix || ""}` : null);
    const dropped = [];
    let body = groups.body || "";
    const deps = DEP_SUFFIX.exec(body);
    if (deps) {
        const kept = [...deps[0].matchAll(/#(\d+)([a-z]*)/gi)]
            .map(([ref, n, suffix]) => {
                const next = remap(n, suffix);
                if (next === null) dropped.push(ref);
                return next;
            })
            .filter(Boolean);
        body = body.slice(0, deps.index).trimEnd();
        if (kept.length) body = `${body} (dep on ${kept.map(r => `#${r}`).join(", ")})`;
    }
    const rank = groups.rank ? remap(groups.rank, groups.suffix) || `${groups.rank}${groups.suffix || ""}` : null;
    return {
        text: [groups.claude ? "claude:" : null, groups.type ? `[${groups.type}]` : null, rank ? `${rank}.` : null, body]
            .filter(Boolean)
            .join(" "),
        dropped,
    };
}

export function nextRank(todos) {
    const ranks = (todos || []).map(t => parseTodoText(t.text).rank).filter(n => n !== null);
    return ranks.length ? Math.max(...ranks) + 1 : 1;
}

// ponytail: parts already present in `text` win over the params, so composing a
// second time is a no-op instead of stacking prefixes. `claude` is the one
// override that can turn a part OFF — inherit alone made the marker unremovable.
export function composeTodoText(text, { type, deps, rank, inherit, claude } = {}) {
    const parsed = parseTodoText(text);
    const prior = inherit ? parseTodoText(inherit) : null;

    const isClaude =
        claude !== undefined ? claude : parsed.claude || Boolean(prior && prior.claude);
    const finalType = type || parsed.type || (prior && prior.type) || null;
    const rankLabel =
        parsed.rankLabel || (prior && prior.rankLabel) || (rank != null ? String(rank) : null);

    let body = parsed.body.trim();
    if (deps) {
        body = body.replace(DEP_SUFFIX, "").trim();
        if (deps.length) {
            const refs = deps.map(d => `#${String(d).trim().replace(/^#/, "")}`);
            body = `${body} (dep on ${refs.join(", ")})`;
        }
    }

    return [
        isClaude ? "claude:" : null,
        finalType ? `[${finalType}]` : null,
        rankLabel ? `${rankLabel}.` : null,
        body,
    ]
        .filter(Boolean)
        .join(" ");
}
