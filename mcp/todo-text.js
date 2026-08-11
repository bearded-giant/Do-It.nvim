// Todo text shape: "claude: [type] N. body (dep on #M, #K)"
// N is the do-order rank the user scans in the nvim/tmux panes — priority gives
// the bucket, N gives the order inside it — and it is what deps reference.

const TEXT_SHAPE =
    /^(?<claude>claude:\s*)?(?:\[(?<type>[^\]]+)\]\s*)?(?:(?<rank>\d+)(?<suffix>[a-z]*)\.\s+)?(?<body>[\s\S]*)$/i;

const DEP_SUFFIX = /\s*\(dep on [^)]*\)\s*$/i;

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

export function nextRank(todos) {
    const ranks = (todos || []).map(t => parseTodoText(t.text).rank).filter(n => n !== null);
    return ranks.length ? Math.max(...ranks) + 1 : 1;
}

// ponytail: parts already present in `text` win over the params, so composing a
// second time is a no-op instead of stacking prefixes.
export function composeTodoText(text, { type, deps, rank, inherit } = {}) {
    const parsed = parseTodoText(text);
    const prior = inherit ? parseTodoText(inherit) : null;

    const isClaude = parsed.claude || Boolean(prior && prior.claude);
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
