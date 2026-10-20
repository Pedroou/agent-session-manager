// Pure display helpers for the session list. No Qt or QML dependency, so the
// same file is exercised by plasmoid/test/sessions.test.js under node.
//
// Deliberately not `.pragma library`: that directive is not valid JavaScript, and
// it would stop node from loading this file at all. Nothing here reads the QML
// context, so the only thing the pragma would buy is sharing one copy.

// Every state the widget knows, most wanting-your-attention first. The order is
// the one the collector sorts by and the one the summary reads in.
var STATES = ["waiting", "error", "running", "working", "shell", "done", "unknown"]

// How each state reads in the summary sentence, as a plural-safe noun phrase.
var STATE_NOUNS = {
    waiting: "waiting for you",
    error: "with an error",
    running: "running",
    working: "working",
    shell: "in a shell",
    done: "done",
    unknown: "in an unknown state"
}

// The colour each state falls back to when the user has not picked one. Chosen
// to sit clear of a dark panel without going illegible on a light one: these are
// mid-tones, the weight most palettes reserve for exactly that job.
//
// Blue is deliberately absent. It is the commonest convention for "in progress",
// but it disappears into a dark blue panel, which is the whole reason these
// stopped being theme colours.
var DEFAULT_COLORS = {
    waiting: "#f97316", // orange - a person has to do something
    error: "#ef4444", // red - the long-standing meaning, worth not reinventing
    running: "#eab308", // yellow - busy, but nobody is being waited on
    working: "#06b6d4", // cyan - active, and the one that had to leave blue
    shell: "#94a3b8", // slate - a real state, but not one to shout about
    done: "#22c55e", // green - finished
    unknown: "#94a3b8"
}

function defaultColor(state) {
    return DEFAULT_COLORS[state] || DEFAULT_COLORS.unknown
}

// Bars are all one height. Colour alone carries the state - a deliberate choice
// to keep the panel from looking like a jagged little chart.
function railFraction() {
    return 1.0
}

// "12s", "4m", "1h 20m", "2d 3h" - the coarsest unit that still says something.
function age(sinceMs, nowMs) {
    if (!sinceMs) {
        return ""
    }
    var seconds = Math.max(0, Math.round((nowMs - sinceMs) / 1000))
    if (seconds < 60) {
        return seconds + "s"
    }
    var minutes = Math.floor(seconds / 60)
    if (minutes < 60) {
        return minutes + "m"
    }
    var hours = Math.floor(minutes / 60)
    if (hours < 24) {
        return minutes % 60 ? hours + "h " + (minutes % 60) + "m" : hours + "h"
    }
    var days = Math.floor(hours / 24)
    return hours % 24 ? days + "d " + (hours % 24) + "h" : days + "d"
}

// The summary, broken into its pieces so each count can be drawn in its own
// colour. `[{state, count, noun}]`, in attention order.
function summaryParts(counts) {
    var parts = []
    if (!counts) {
        return parts
    }
    for (var i = 0; i < STATES.length; i++) {
        var state = STATES[i]
        if (counts[state]) {
            parts.push({state: state, count: counts[state], noun: STATE_NOUNS[state]})
        }
    }
    return parts
}

// The one sentence that answers "does anything need me?".
function headline(counts) {
    if (!counts || !counts.total) {
        return "Nothing running"
    }
    return summaryParts(counts).map(function (p) {
        return p.count + " " + p.noun
    }).join(", ")
}

// Same information, one state per line, for the panel's hover tooltip.
function tooltipLines(counts) {
    if (!counts || !counts.total) {
        return "No sessions running"
    }
    return summaryParts(counts).map(function (p) {
        return p.count + " " + p.noun
    }).join("\n")
}

// The state that decides the widget's overall tone.
//
// Anything blocked on a person wins outright, however few - that is the question
// the panel exists to answer. Failing that it is simply the biggest group, with
// ties broken by which state is more urgent.
function dominantState(counts) {
    if (!counts || !counts.total) {
        return "none"
    }
    if (counts.waiting) {
        return "waiting"
    }
    var best = "none"
    var bestCount = 0
    for (var i = 0; i < STATES.length; i++) {
        var state = STATES[i]
        if (counts[state] > bestCount) {
            best = state
            bestCount = counts[state]
        }
    }
    return best
}

// Sessions the widget should draw, given the user's settings. The collector has
// already sorted them, so this only ever removes.
function visible(sessions, settings) {
    if (!sessions) {
        return []
    }
    if (!settings || settings.showDone !== false) {
        return sessions
    }
    return sessions.filter(function (s) {
        return s.state !== "done"
    })
}

// The counts that go with a filtered list, so the header and the panel never
// disagree with what is on screen.
function countsFor(sessions) {
    var counts = {total: 0}
    for (var i = 0; i < STATES.length; i++) {
        counts[STATES[i]] = 0
    }
    for (var j = 0; j < (sessions ? sessions.length : 0); j++) {
        var state = sessions[j].state
        if (counts[state] === undefined) {
            state = "unknown"
        }
        counts[state] += 1
        counts.total += 1
    }
    return counts
}

// What a session is called, allowing for a nickname the user has given it and
// for the privacy toggle that blanks names out.
function displayName(session, nicknames, censored) {
    if (censored) {
        return "Session " + session.pid
    }
    var nick = nicknames ? nicknames[session.sessionId] : undefined
    return (nick !== undefined && nick !== "") ? nick : session.name
}

// The second line of a row: where the session is, and what it wants. Blank when
// names are censored, which is the point of censoring them.
function context(session, showProfile, censored) {
    if (censored) {
        return ""
    }
    var bits = []
    if (showProfile && session.profile) {
        bits.push(session.profile)
    }
    if (session.dir) {
        bits.push(session.dir)
    }
    if (session.detail) {
        bits.push(session.detail)
    }
    return bits.join(" - ")
}

// A model id as a person would say it: "claude-opus-5-5" is "Opus 5.5",
// "claude-3-5-haiku-20241022" is "Haiku 3.5". OMP qualifies ids with their
// provider ("anthropic/claude-opus-5-5"), and Claude Code can carry a "[1m]"
// tag; neither is part of the name. An id that is not a Claude model is shown
// as it is - it is already what that provider calls it.
function parseModel(id) {
    var bare = String(id || "")
    bare = bare.slice(bare.lastIndexOf("/") + 1)
    bare = bare.replace(/\[1m\]$/i, "").replace(/[-@][0-9]{8}$/, "")
    var m = /^claude-(opus|sonnet|haiku|fable|mythos)-([0-9]+)(?:-([0-9]+))?$/.exec(bare)
    if (!m) {
        // The ids before Claude 4 put the version first.
        var old = /^claude-([0-9]+)(?:-([0-9]+))?-(opus|sonnet|haiku)$/.exec(bare)
        if (old) {
            m = [old[0], old[3], old[1], old[2]]
        }
    }
    if (!m) {
        return {family: "", major: 0, minor: 0, bare: bare}
    }
    return {family: m[1], major: parseInt(m[2], 10), minor: m[3] ? parseInt(m[3], 10) : 0,
            bare: bare}
}

function modelLabel(id) {
    var p = parseModel(id)
    if (!p.family) {
        // "<synthetic>" is what Claude Code records for a message it wrote
        // itself, such as an API error - no model at all.
        return /^<.*>$/.test(p.bare) ? "" : p.bare
    }
    var version = p.minor ? p.major + "." + p.minor : String(p.major)
    return p.family.charAt(0).toUpperCase() + p.family.slice(1) + " " + version
}

// How many tokens a session's model can hold, or 0 when there is no telling.
//
// Neither transcript records it, so it follows the model, the way both tools
// size it: Fable, Sonnet 5 and later, Haiku 5.5 and Opus 4.7 and later have a
// native 1M window; Opus 4.6 and Sonnet 4.6 reach 1M only when asked for, which
// Claude Code does through a "[1m]" model variant that the transcript does not
// keep, and OMP does by default. Everything older is 200K. A session already
// holding more than 200K is on the 1M window whatever its id said.
function contextWindow(id, agent, tokens) {
    var p = parseModel(id)
    var version = p.major * 100 + p.minor
    var million = 1000000
    var window
    if (/\[1m\]$/i.test(String(id || ""))) {
        window = million
    } else if (p.family === "fable" || p.family === "mythos") {
        window = million
    } else if (p.family === "opus") {
        window = version >= 407 || (version === 406 && agent === "omp") ? million : 200000
    } else if (p.family === "sonnet") {
        window = version >= 500 || (version === 406 && agent === "omp") ? million : 200000
    } else if (p.family === "haiku") {
        window = version >= 505 ? million : 200000
    } else {
        return 0
    }
    return tokens > window ? million : window
}

// How full a session's context is, 0-100, or -1 when that cannot be said: no
// reply yet, or a model whose window is not known.
function contextPercent(session) {
    var tokens = session ? Number(session.contextTokens) || 0 : 0
    var window = session ? contextWindow(session.model, session.agent, tokens) : 0
    if (tokens <= 0 || window <= 0) {
        return -1
    }
    return Math.min(100, Math.round(tokens * 100 / window))
}

// "850", "224K", "1M", "1.2M".
function tokenCount(n) {
    if (n < 1000) {
        return String(n)
    }
    if (n < 999500) {
        return Math.round(n / 1000) + "K"
    }
    return (Math.round(n / 100000) / 10) + "M"
}

function label(key, settings, shortKey) {
    return (settings && settings.shortLabels && shortKey) ? shortKey : key
}

// The rows behind an expanded session, in the order they are read: who, how
// long, where, then the identifiers you would otherwise dig out of `ps`.
//
// A row with no value never appears - a session outside a git repository simply
// has no Repository line rather than an empty one.
function detailRows(session, settings, nowMs, censored) {
    var s = settings || {}
    var rows = []

    function add(id, key, value, copyable) {
        if (value === undefined || value === null || value === "" || value === "0") {
            return
        }
        rows.push({id: id, key: key, value: String(value), copyable: copyable === true})
    }

    var branchShown = s.detailBranch !== false && session.branch
    var branchOnItsOwn = branchShown && s.branchSeparate === true

    var repository = session.repository
    if (repository && branchShown && !branchOnItsOwn) {
        repository = repository + "/" + session.branch
    }

    add("profile", "Profile", session.profile, false)
    add("uptime", "Uptime", age(session.startedAt, nowMs), false)
    if (!censored) {
        add("directory", label("Directory", s, "Dir"), session.cwd, true)
    }
    if (s.detailRepository !== false && !censored) {
        add("repository", label("Repository", s, "Repo"), repository, true)
    }
    if (branchOnItsOwn && !censored) {
        add("branch", "Branch", session.branch, true)
    }
    if (s.detailSession !== false) {
        add("session", "Session", session.sessionId, true)
    }
    if (s.detailProcess !== false) {
        add("process", "Process", session.pid, true)
    }
    if (s.detailVersion !== false) {
        add("version", "Version", session.version, true)
    }
    return rows
}

// The command that reopens a session in a new terminal. `claude --resume <id>`
// from its own directory is the one that actually lands you back in it.
//
// A session from a second account needs that account's config directory, and
// $CLAUDE_CONFIG_DIR is how Claude Code itself is told - so this works whatever
// the user called the account and wherever they put it. The stock directory is
// the one value it must never be set to, which is what profileDefault marks.
//
// OMP sessions resume with `omp --resume <id>`, which finds the id anywhere in
// the agent directory it runs with: the stock one plainly, a named profile with
// `--profile`, and any other through $PI_CODING_AGENT_DIR. A transcript kept
// outside every agent directory (`--session-dir`) can only be found by its path.
function resumeCommand(session) {
    var into = "cd " + shellQuote(session.cwd) + " && "
    if (session.agent === "omp") {
        var home = session.profileDir + "/sessions/"
        if (String(session.sessionFile || "").indexOf(home) !== 0) {
            return into + "omp --resume " + shellQuote(session.sessionFile)
        }
        if (session.ompProfile) {
            return into + "omp --profile " + shellQuote(session.ompProfile)
                   + " --resume " + session.sessionId
        }
        if (session.profileDefault === false) {
            return into + "PI_CODING_AGENT_DIR=" + shellQuote(session.profileDir)
                   + " omp --resume " + session.sessionId
        }
        return into + "omp --resume " + session.sessionId
    }
    var prefix = ""
    if (session.profileDir && session.profileDefault === false) {
        prefix = "CLAUDE_CONFIG_DIR=" + shellQuote(session.profileDir) + " "
    }
    return into + prefix + "claude --resume " + session.sessionId
}

// The shell command that ends a session, or "" when it cannot be done safely.
//
// Ending sends SIGTERM to a pid, and a pid is the one thing here that can do
// real damage when it is wrong. 0 means "my own process group" to kill(2), and
// a negative number means a whole group, so only a plain integer above 1 ever
// reaches the command. And by the time the button is pressed the session may
// have exited and its pid been handed to something else, so the command reads
// the process's start time from /proc at that moment and signals it only if it
// is still the one the collector saw. A session whose start time is not known
// cannot be checked, and so cannot be ended from here.
//
// Both values are digits by the time they are spliced in, so there is nothing
// in them a shell could read as anything but a number.
function endCommand(session) {
    var args = processArgs(session)
    if (args === null) {
        return ""
    }
    // Field 22 of /proc/<pid>/stat is the start time; field 2 is the name in
    // parentheses and may contain spaces, so everything up to the last ") " is
    // dropped and it becomes field 20.
    return "read -r l < /proc/" + args.pid + "/stat && set -- ${l##*) } && [ \"${20}\" = \""
           + args.start + "\" ] && kill -TERM " + args.pid
}

// A session's pid and start time, as plain digits, or null when either is not
// safe to put on a command line. Shared by ending a session and jumping to it,
// which both act on a pid and both check the start time again before they do.
function processArgs(session) {
    var pid = String(session && session.pid !== undefined ? session.pid : "")
    var start = String(session && session.procStart !== undefined ? session.procStart : "")
    if (!/^[0-9]+$/.test(pid) || parseInt(pid, 10) <= 1 || !/^[0-9]+$/.test(start)) {
        return null
    }
    return {pid: pid, start: start}
}

// The arguments for scripts/jump-to-session, or "" when the session cannot be
// pointed at safely.
function jumpArgs(session) {
    var args = processArgs(session)
    return args === null ? "" : args.pid + " " + args.start
}

function shellQuote(text) {
    if (text === undefined || text === null) {
        return "''"
    }
    if (/^[A-Za-z0-9_@%+=:,.\/-]+$/.test(text)) {
        return text
    }
    return "'" + String(text).replace(/'/g, "'\\''") + "'"
}

// Everything on screen for one session, as plain text worth pasting somewhere.
function detailsAsText(session, settings, nowMs, nicknames, censored) {
    var lines = [displayName(session, nicknames, censored) + " - " + session.label]
    var second = context(session, true, censored)
    if (second) {
        lines.push(second)
    }
    var rows = detailRows(session, settings, nowMs, censored)
    for (var i = 0; i < rows.length; i++) {
        lines.push(rows[i].key + ": " + rows[i].value)
    }
    return lines.join("\n")
}

// Present only under node; QML ignores it.
if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        STATES: STATES,
        DEFAULT_COLORS: DEFAULT_COLORS,
        defaultColor: defaultColor,
        railFraction: railFraction,
        age: age,
        summaryParts: summaryParts,
        headline: headline,
        tooltipLines: tooltipLines,
        dominantState: dominantState,
        visible: visible,
        countsFor: countsFor,
        displayName: displayName,
        context: context,
        modelLabel: modelLabel,
        contextWindow: contextWindow,
        contextPercent: contextPercent,
        tokenCount: tokenCount,
        detailRows: detailRows,
        resumeCommand: resumeCommand,
        endCommand: endCommand,
        jumpArgs: jumpArgs,
        shellQuote: shellQuote,
        detailsAsText: detailsAsText
    }
}
