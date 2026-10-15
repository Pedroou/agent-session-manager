// Tests for the widget's pure display layer.
//   node --test plasmoid/test/sessions.test.js
//
// The QML side is deliberately thin - it binds these results to components - so
// everything with a decision in it is checked here without a running Plasma shell.

const test = require("node:test")
const assert = require("node:assert")
const Sessions = require("../package/contents/code/sessions.js")

const NOW = 1788543348520

function session(over) {
    return Object.assign({
        pid: 1234,
        profile: "work",
        name: "checkout-flow-7",
        cwd: "/home/u/code/checkout-flow",
        dir: "checkout-flow",
        repository: "checkout-flow",
        branch: "main",
        sessionId: "abc-123",
        kind: "interactive",
        status: "busy",
        state: "working",
        label: "Working",
        detail: "",
        startedAt: NOW - 3600_000,
        statusUpdatedAt: NOW - 60_000,
        version: "2.1.263"
    }, over || {})
}

test("age reports the coarsest unit that still says something", () => {
    assert.equal(Sessions.age(NOW, NOW), "0s")
    assert.equal(Sessions.age(NOW - 42_000, NOW), "42s")
    assert.equal(Sessions.age(NOW - 60_000, NOW), "1m")
    assert.equal(Sessions.age(NOW - 59 * 60_000, NOW), "59m")
    assert.equal(Sessions.age(NOW - 60 * 60_000, NOW), "1h")
    assert.equal(Sessions.age(NOW - 80 * 60_000, NOW), "1h 20m")
    assert.equal(Sessions.age(NOW - 26 * 3600_000, NOW), "1d 2h")
    assert.equal(Sessions.age(NOW - 48 * 3600_000, NOW), "2d")
})

test("age is blank when the timestamp is missing, never 'NaN' or a 1970 date", () => {
    assert.equal(Sessions.age(0, NOW), "")
    assert.equal(Sessions.age(undefined, NOW), "")
})

test("a clock that has drifted backwards does not produce a negative age", () => {
    assert.equal(Sessions.age(NOW + 5000, NOW), "0s")
})

test("every state has a colour, and none of them is blue", () => {
    for (const state of Sessions.STATES) {
        const hex = Sessions.defaultColor(state)
        assert.match(hex, /^#[0-9a-f]{6}$/, state + " needs a colour")
        // Blue is the commonest "in progress" convention and the reason these
        // stopped being theme colours: it vanishes into a dark blue panel.
        const r = parseInt(hex.slice(1, 3), 16)
        const g = parseInt(hex.slice(3, 5), 16)
        const b = parseInt(hex.slice(5, 7), 16)
        assert.ok(!(b > r + 40 && b > g + 40), state + " is a blue: " + hex)
    }
    assert.equal(Sessions.defaultColor("something-new"), Sessions.defaultColor("unknown"))
})

test("bars are all one height, so the panel is not a jagged chart", () => {
    assert.equal(Sessions.railFraction(), 1.0)
})

test("the summary breaks into parts so each count can wear its own colour", () => {
    const parts = Sessions.summaryParts({waiting: 1, working: 3, done: 2, total: 6})
    assert.deepEqual(parts.map(p => p.state), ["waiting", "working", "done"])
    assert.deepEqual(parts.map(p => p.count), [1, 3, 2])
    assert.equal(parts[0].noun, "waiting for you")
})

test("the headline leads with whatever is blocked, then what failed", () => {
    assert.equal(Sessions.headline({waiting: 1, error: 1, running: 2, working: 3, done: 2, total: 9}),
                 "1 waiting for you, 1 with an error, 2 running, 3 working, 2 done")
    assert.equal(Sessions.headline({working: 2, total: 2}), "2 working")
    assert.equal(Sessions.headline({shell: 1, total: 1}), "1 in a shell")
})

test("the headline says something useful when nothing is running", () => {
    assert.equal(Sessions.headline({total: 0}), "Nothing running")
    assert.equal(Sessions.headline(null), "Nothing running")
})

test("the tooltip is the same facts, one per line", () => {
    assert.equal(Sessions.tooltipLines({waiting: 1, done: 2, total: 3}),
                 "1 waiting for you\n2 done")
    assert.equal(Sessions.tooltipLines({total: 0}), "No sessions running")
})

test("the dominant state is the biggest group", () => {
    assert.equal(Sessions.dominantState({working: 5, done: 1, total: 6}), "working")
    assert.equal(Sessions.dominantState({working: 1, done: 4, total: 5}), "done")
    assert.equal(Sessions.dominantState({running: 3, working: 2, total: 5}), "running")
    assert.equal(Sessions.dominantState({total: 0}), "none")
})

test("but anything blocked on a person wins, however few", () => {
    assert.equal(Sessions.dominantState({waiting: 1, working: 9, total: 10}), "waiting")
})

test("a tie goes to the more urgent state", () => {
    assert.equal(Sessions.dominantState({error: 2, done: 2, total: 4}), "error")
    assert.equal(Sessions.dominantState({running: 2, working: 2, total: 4}), "running")
})

test("finished sessions can be hidden without disturbing the rest", () => {
    const sessions = [
        {name: "a", state: "waiting"},
        {name: "b", state: "working"},
        {name: "c", state: "done"}
    ]
    assert.deepEqual(Sessions.visible(sessions, {showDone: true}).map(s => s.name), ["a", "b", "c"])
    assert.deepEqual(Sessions.visible(sessions, {showDone: false}).map(s => s.name), ["a", "b"])
    assert.deepEqual(Sessions.visible(sessions, {}).map(s => s.name), ["a", "b", "c"])
    assert.deepEqual(Sessions.visible(undefined, {}), [])
})

test("the counts follow the filter, so the header can never contradict the list", () => {
    const sessions = [
        {state: "waiting"}, {state: "working"}, {state: "working"}, {state: "done"}
    ]
    const kept = Sessions.visible(sessions, {showDone: false})
    const counts = Sessions.countsFor(kept)
    assert.equal(counts.total, 3)
    assert.equal(counts.working, 2)
    assert.equal(counts.done, 0)
})

test("a status this version has never heard of is counted, not dropped", () => {
    const counts = Sessions.countsFor([{state: "hibernating"}])
    assert.equal(counts.unknown, 1)
    assert.equal(counts.total, 1)
})

test("a nickname replaces the name, and censoring replaces both", () => {
    const s = session()
    assert.equal(Sessions.displayName(s, {}, false), "checkout-flow-7")
    assert.equal(Sessions.displayName(s, {"abc-123": "the refactor"}, false), "the refactor")
    assert.equal(Sessions.displayName(s, {"abc-123": ""}, false), "checkout-flow-7")
    assert.equal(Sessions.displayName(s, {"abc-123": "the refactor"}, true), "Session 1234")
})

test("the row's second line says where the session is and what it wants", () => {
    assert.equal(
        Sessions.context(session({detail: "input needed"}), false, false),
        "checkout-flow - input needed")
    assert.equal(
        Sessions.context(session({profile: "personal", detail: ""}), true, false),
        "personal - checkout-flow")
    assert.equal(Sessions.context(session({detail: ""}), false, false), "checkout-flow")
})

test("censoring leaves no second line at all", () => {
    assert.equal(Sessions.context(session({detail: "input needed"}), true, true), "")
})

test("the detail rows read in a fixed order", () => {
    const keys = Sessions.detailRows(session(), {}, NOW, false).map(r => r.key)
    assert.deepEqual(keys,
        ["Profile", "Uptime", "Directory", "Repository", "Session", "Process", "Version"])
})

test("the branch rides on the repository by default, and can move to its own row", () => {
    const merged = Sessions.detailRows(session(), {}, NOW, false)
    assert.equal(merged.find(r => r.key === "Repository").value, "checkout-flow/main")
    assert.equal(merged.find(r => r.key === "Branch"), undefined)

    const split = Sessions.detailRows(session(), {branchSeparate: true}, NOW, false)
    assert.equal(split.find(r => r.key === "Repository").value, "checkout-flow")
    assert.equal(split.find(r => r.key === "Branch").value, "main")
    assert.deepEqual(split.map(r => r.key),
        ["Profile", "Uptime", "Directory", "Repository", "Branch", "Session", "Process", "Version"])
})

test("turning the branch off removes it from both places", () => {
    const merged = Sessions.detailRows(session(), {detailBranch: false}, NOW, false)
    assert.equal(merged.find(r => r.key === "Repository").value, "checkout-flow")

    const split = Sessions.detailRows(session(), {detailBranch: false, branchSeparate: true}, NOW, false)
    assert.equal(split.find(r => r.key === "Branch"), undefined)
    assert.equal(split.find(r => r.key === "Repository").value, "checkout-flow")
})

test("each optional row can be turned off on its own", () => {
    const off = {detailRepository: false, detailSession: false, detailProcess: false, detailVersion: false}
    assert.deepEqual(Sessions.detailRows(session(), off, NOW, false).map(r => r.key),
                     ["Profile", "Uptime", "Directory"])
})

test("a session outside a repository simply has no repository row", () => {
    const keys = Sessions.detailRows(session({repository: "", branch: ""}), {}, NOW, false).map(r => r.key)
    assert.deepEqual(keys, ["Profile", "Uptime", "Directory", "Session", "Process", "Version"])
})

test("the labels can be abbreviated", () => {
    const keys = Sessions.detailRows(session(), {shortLabels: true}, NOW, false).map(r => r.key)
    assert.ok(keys.includes("Dir"))
    assert.ok(keys.includes("Repo"))
    assert.ok(!keys.includes("Directory"))
})

test("censoring hides the rows that would give the path away", () => {
    const keys = Sessions.detailRows(session(), {}, NOW, true).map(r => r.key)
    assert.deepEqual(keys, ["Profile", "Uptime", "Session", "Process", "Version"])
})

test("only the rows worth pasting are click-to-copy", () => {
    const rows = Sessions.detailRows(session(), {branchSeparate: true}, NOW, false)
    const copyable = rows.filter(r => r.copyable).map(r => r.key)
    assert.deepEqual(copyable,
        ["Directory", "Repository", "Branch", "Session", "Process", "Version"])
})

test("the resume command lands you back in the session, in its own directory", () => {
    assert.equal(Sessions.resumeCommand(session()),
                 "cd /home/u/code/checkout-flow && claude --resume abc-123")
    assert.equal(Sessions.resumeCommand(session({
                     profileDir: "/home/u/.claude", profileDefault: true})),
                 "cd /home/u/code/checkout-flow && claude --resume abc-123")
})

// $CLAUDE_CONFIG_DIR is how Claude Code itself is told which account to use, so
// it works whatever the account was called and wherever it was put - and the
// stock directory is the one value it must never be set to, which is the whole
// job of profileDefault.
test("a session from a second account carries that account's directory", () => {
    assert.equal(Sessions.resumeCommand(session({
                     profileDir: "/home/u/.claude-side", profileDefault: false})),
                 "cd /home/u/code/checkout-flow && "
                 + "CLAUDE_CONFIG_DIR=/home/u/.claude-side claude --resume abc-123")
    assert.equal(Sessions.resumeCommand(session({
                     profileDir: "/home/u/my accounts/side", profileDefault: false})),
                 "cd /home/u/code/checkout-flow && "
                 + "CLAUDE_CONFIG_DIR='/home/u/my accounts/side' claude --resume abc-123")
})

function ompSession(over) {
    return session(Object.assign({
        agent: "omp",
        sessionId: "01a14088-a104",
        profileDir: "/home/u/.omp/agent",
        profileDefault: true,
        ompProfile: "",
        sessionFile: "/home/u/.omp/agent/sessions/-code-checkout-flow/2026-10-15T17-07-38-372Z_01a14088-a104.jsonl"
    }, over || {}))
}

// `omp --resume <id>` looks the id up in the agent directory it runs with, so the
// command has to start omp with the same one: nothing for the stock directory,
// --profile for a named profile, $PI_CODING_AGENT_DIR for anything else.
test("an OMP session resumes with omp, in the agent directory it came from", () => {
    assert.equal(Sessions.resumeCommand(ompSession()),
                 "cd /home/u/code/checkout-flow && omp --resume 01a14088-a104")
    assert.equal(Sessions.resumeCommand(ompSession({
                     profileDir: "/home/u/.omp/profiles/side job/agent", profileDefault: false,
                     ompProfile: "side job",
                     sessionFile: "/home/u/.omp/profiles/side job/agent/sessions/-x/a_01a14088-a104.jsonl"})),
                 "cd /home/u/code/checkout-flow && omp --profile 'side job' --resume 01a14088-a104")
    assert.equal(Sessions.resumeCommand(ompSession({
                     profileDir: "/srv/omp-agent", profileDefault: false,
                     sessionFile: "/srv/omp-agent/sessions/-x/a_01a14088-a104.jsonl"})),
                 "cd /home/u/code/checkout-flow && "
                 + "PI_CODING_AGENT_DIR=/srv/omp-agent omp --resume 01a14088-a104")
})

// --session-dir keeps a transcript outside every agent directory, where no id
// lookup reaches - but omp also resumes from a path.
test("an OMP transcript kept outside the agent directory resumes by its path", () => {
    assert.equal(Sessions.resumeCommand(ompSession({
                     profileDir: "/home/u/my sessions", profileDefault: false,
                     sessionFile: "/home/u/my sessions/2026-10-15T17-07-38-372Z_01a14088-a104.jsonl"})),
                 "cd /home/u/code/checkout-flow && "
                 + "omp --resume '/home/u/my sessions/2026-10-15T17-07-38-372Z_01a14088-a104.jsonl'")
})

// kill(2) reads 0 as "my own process group" and a negative pid as a whole
// group, so anything but a plain pid above 1 must never become a command.
test("ending is refused for any pid that is not a plain process id", () => {
    for (const pid of [0, 1, -1, -4321, "12abc", "1 2", "", undefined, null, NaN, 1.5]) {
        assert.equal(Sessions.endCommand({pid: pid, procStart: "400100"}), "", `pid ${pid}`)
    }
})

test("ending is refused when the start time cannot be checked", () => {
    for (const start of ["", undefined, null, "12; rm -rf ~", "-1", "4e5"]) {
        assert.equal(Sessions.endCommand({pid: 4321, procStart: start}), "", `start ${start}`)
    }
})

// Run for real, against a real process, through the same /bin/sh the widget's
// executable engine uses - the only way to know the command does what it says.
test("the end command signals the process it was given, and only while it is still that process", () => {
    const {spawn, spawnSync} = require("node:child_process")
    const fs = require("node:fs")
    const child = spawn("sleep", ["30"])
    try {
        const stat = fs.readFileSync(`/proc/${child.pid}/stat`, "utf8")
        const start = stat.slice(stat.lastIndexOf(") ") + 2).split(" ")[19]

        spawnSync("/bin/sh", ["-c", Sessions.endCommand({pid: child.pid, procStart: "1" + start})])
        assert.equal(child.exitCode, null)
        assert.equal(child.signalCode, null)
        assert.ok(fs.existsSync(`/proc/${child.pid}`), "a different start time leaves it running")

        const ended = spawnSync("/bin/sh", ["-c", Sessions.endCommand({pid: child.pid, procStart: start})])
        assert.equal(ended.status, 0)
        const deadline = Date.now() + 2000
        while (fs.existsSync(`/proc/${child.pid}/stat`)
               && !fs.readFileSync(`/proc/${child.pid}/stat`, "utf8").includes(") Z ")
               && Date.now() < deadline) {
            spawnSync("sleep", ["0.05"])
        }
        const after = fs.existsSync(`/proc/${child.pid}/stat`)
            ? fs.readFileSync(`/proc/${child.pid}/stat`, "utf8") : ""
        assert.ok(after === "" || after.includes(") Z "), "the matching start time ends it")
    } finally {
        child.kill("SIGKILL")
    }
})

test("a path with a space or a quote in it is still a safe command", () => {
    assert.equal(Sessions.shellQuote("/home/u/my code"), "'/home/u/my code'")
    assert.equal(Sessions.shellQuote("/home/u/it's"), "'/home/u/it'\\''s'")
    assert.equal(Sessions.shellQuote("/plain/path-1.2"), "/plain/path-1.2")
})

test("copying an expanded session gives you everything on screen", () => {
    const text = Sessions.detailsAsText(session({detail: "input needed"}), {}, NOW, {}, false)
    const lines = text.split("\n")
    assert.equal(lines[0], "checkout-flow-7 - Working")
    assert.equal(lines[1], "work - checkout-flow - input needed")
    assert.ok(lines.includes("Repository: checkout-flow/main"))
    assert.ok(lines.includes("Session: abc-123"))
})
