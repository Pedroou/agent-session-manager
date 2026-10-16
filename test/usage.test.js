// Tests for the plan-usage footer's pure layer.
//   node --test plasmoid/test/usage.test.js

const test = require("node:test")
const assert = require("node:assert")
const Usage = require("../package/contents/code/usage.js")

const NOW = Date.parse("2026-09-08T12:00:00Z")

function profile(over) {
    return Object.assign({
        id: "work",
        state: "ok",
        bars: [
            {id: "session", label: "Session", percent: 11, severity: "normal",
             resetsAt: "2026-09-08T16:30:00Z", active: true},
            {id: "weekly", label: "Weekly", percent: 5, severity: "normal",
             resetsAt: "2026-09-10T16:00:00Z", active: false},
            {id: "scoped:Fable", label: "Fable", percent: 0, severity: "normal",
             resetsAt: null, active: false}
        ]
    }, over || {})
}

test("the bar you picked is the bar you get", () => {
    assert.equal(Usage.barFor(profile(), "weekly").label, "Weekly")
    assert.equal(Usage.barFor(profile(), "scoped:Fable").label, "Fable")
})

test("a bar the plan no longer has falls back to the one actually counting", () => {
    assert.equal(Usage.barFor(profile(), "scoped:Gone").label, "Session")
})

test("with nothing active it falls back to the first bar rather than nothing", () => {
    const p = profile()
    p.bars.forEach(b => { b.active = false })
    assert.equal(Usage.barFor(p, "nope").label, "Session")
})

test("a profile with no bars has no bar", () => {
    assert.equal(Usage.barFor(profile({bars: []}), "session"), null)
    assert.equal(Usage.barFor(null, "session"), null)
})

test("severity comes from the API when it gives one", () => {
    assert.equal(Usage.severity({percent: 99, severity: "normal"}), "normal")
    assert.equal(Usage.severity({percent: 5, severity: "warning"}), "warning")
    assert.equal(Usage.severity({percent: 5, severity: "exceeded"}), "critical")
})

test("and from the percentage when it does not", () => {
    assert.equal(Usage.severity({percent: 10}), "normal")
    assert.equal(Usage.severity({percent: 70}), "warning")
    assert.equal(Usage.severity({percent: 95}), "critical")
    assert.equal(Usage.severity(null), "normal")
})

test("the reset time reads as a countdown", () => {
    assert.equal(Usage.resetText("2026-09-08T16:30:00Z", NOW), "resets in 4h 30m")
    assert.equal(Usage.resetText("2026-09-08T12:45:00Z", NOW), "resets in 45m")
    assert.equal(Usage.resetText("2026-09-10T12:00:00Z", NOW), "resets in 2d")
    assert.equal(Usage.resetText("2026-09-10T18:00:00Z", NOW), "resets in 2d 6h")
})

test("a limit with no reset time says nothing rather than lying", () => {
    assert.equal(Usage.resetText(null, NOW), "")
    assert.equal(Usage.resetText("not a date", NOW), "")
})

test("a reset already due does not count backwards", () => {
    assert.equal(Usage.resetText("2026-09-08T11:00:00Z", NOW), "resets any moment")
})

test("every profile state names its own fix", () => {
    assert.equal(Usage.stateMessage(profile()), "")
    assert.equal(Usage.stateMessage(profile({state: "absent"})), "Not signed in")
    assert.match(Usage.stateMessage(profile({state: "expired"})), /run claude/)
    assert.match(Usage.stateMessage(profile({state: "error"})), /Couldn't reach/)
    assert.match(Usage.stateMessage(profile({bars: []})), /no limits/)
})

test("profiles are found by id and listed in a stable order", () => {
    const usage = {profiles: [profile(), profile({id: "personal", state: "absent", bars: []})]}
    assert.equal(Usage.profileById(usage, "personal").state, "absent")
    assert.equal(Usage.profileById(usage, "nope"), null)
    assert.deepEqual(Usage.selectableProfiles(usage).map(p => p.id), ["work", "personal"])
    assert.deepEqual(Usage.selectableProfiles(null), [])
})

test("the panel tracks the same profile and limit the popup is set to", () => {
    const usage = {profiles: [profile(), profile({id: "personal", state: "absent", bars: []})]}
    assert.equal(Usage.panelBar(usage, "work", "weekly").label, "Weekly")
    assert.equal(Usage.panelBar(usage, "work", "session").label, "Session")
    assert.equal(Usage.panelBar(usage, "personal", "session"), null)
    assert.equal(Usage.panelBar(null, "work", "session"), null)
})

test("a threshold of zero means always, and a missing bar is never", () => {
    const bar = {percent: 61}
    assert.equal(Usage.pastThreshold(bar, 0), true)
    assert.equal(Usage.pastThreshold(bar, 50), true)
    assert.equal(Usage.pastThreshold(bar, 61), true)
    assert.equal(Usage.pastThreshold(bar, 75), false)
    assert.equal(Usage.pastThreshold(null, 0), false)
})

test("a bar sitting at zero still clears the always threshold", () => {
    assert.equal(Usage.pastThreshold({percent: 0}, 0), true)
    assert.equal(Usage.pastThreshold({percent: 0}, 25), false)
})

test("a failed refresh keeps the bars it had, marked stale", () => {
    const before = {fetchedAt: 1000, profiles: [profile()]}
    const after = Usage.merge(before, {fetchedAt: 2000, profiles: [profile({state: "error", bars: []})]})
    const work = Usage.profileById(after, "work")
    assert.equal(work.state, "ok")
    assert.equal(work.bars.length, 3)
    assert.equal(work.stale, true)
    assert.equal(work.since, 1000, "stale reading dates from when it was actually taken")
})

test("a stale reading keeps its original timestamp across repeated failures", () => {
    const before = {fetchedAt: 1000, profiles: [profile()]}
    const once = Usage.merge(before, {fetchedAt: 2000, profiles: [profile({state: "error", bars: []})]})
    const twice = Usage.merge(once, {fetchedAt: 3000, profiles: [profile({state: "error", bars: []})]})
    assert.equal(Usage.profileById(twice, "work").since, 1000)
})

test("a fresh reading replaces a stale one outright", () => {
    const stale = Usage.merge({fetchedAt: 1000, profiles: [profile()]},
                              {fetchedAt: 2000, profiles: [profile({state: "error", bars: []})]})
    const fresh = Usage.merge(stale, {fetchedAt: 3000, profiles: [profile()]})
    const work = Usage.profileById(fresh, "work")
    assert.equal(work.state, "ok")
    assert.notEqual(work.stale, true)
})

test("signed out and not signed in are real answers, never papered over", () => {
    const before = {fetchedAt: 1000, profiles: [profile()]}
    for (const state of ["expired", "absent"]) {
        const after = Usage.merge(before, {fetchedAt: 2000, profiles: [profile({state, bars: []})]})
        const work = Usage.profileById(after, "work")
        assert.equal(work.state, state, state + " must survive the merge")
        assert.equal(work.bars.length, 0)
    }
})

test("with nothing to fall back on, a failure stays a failure", () => {
    const after = Usage.merge(null, {fetchedAt: 2000, profiles: [profile({state: "error", bars: []})]})
    assert.equal(Usage.profileById(after, "work").state, "error")
    assert.equal(Usage.merge(null, null), null)
})

// Accounts are identified by their config directory, and that list is the
// user's to edit - so the account the footer was pointed at can simply stop
// existing. Falling back to the first beats showing an empty bar, which reads
// as "nothing used" rather than "not that one".
test("a selection that no longer exists falls back to the first account", () => {
    const usage = {profiles: [
        {id: "/home/u/.claude", name: "day job", state: "ok", bars: [
            {id: "session", label: "Session", percent: 12}]},
        {id: "/home/u/.claude-side", name: "side project", state: "ok", bars: []}
    ]}
    assert.equal(Usage.selectedId(usage, "/home/u/.claude-side"), "/home/u/.claude-side")
    assert.equal(Usage.selectedId(usage, "/home/u/.gone"), "/home/u/.claude")
    assert.equal(Usage.selectedId(usage, ""), "/home/u/.claude")
    assert.equal(Usage.selectedId({profiles: []}, "anything"), "")
    assert.equal(Usage.selectedProfile(null, "x"), null)

    // And the panel strip follows the same fallback, so it and the footer never
    // end up measuring different accounts.
    assert.equal(Usage.panelBar(usage, "/home/u/.gone", "session").percent, 12)
})

// Someone who moved to OMP keeps a signed-out ~/.claude at the top of the list,
// and an unchosen strip pointed at that is a strip that never shows anything.
test("with nothing chosen, the first account that has a reading is the one shown", () => {
    const usage = {profiles: [
        {id: "/home/u/.claude", name: "default", state: "expired", bars: []},
        {id: "omp:/home/u/.omp/agent#acct", name: "OMP", agent: "omp", state: "ok", bars: [
            {id: "session", label: "Session", percent: 4}]}
    ]}
    assert.equal(Usage.selectedId(usage, ""), "omp:/home/u/.omp/agent#acct")
    assert.equal(Usage.selectedId(usage, "/home/u/.gone"), "omp:/home/u/.omp/agent#acct")
    assert.equal(Usage.panelBar(usage, "", "session").percent, 4)
    // A choice is still a choice, even of the account with nothing to show.
    assert.equal(Usage.selectedId(usage, "/home/u/.claude"), "/home/u/.claude")
})

test("an OMP login's fix is in omp, not claude", () => {
    const omp = {agent: "omp", bars: []}
    assert.match(Usage.stateMessage(Object.assign({state: "expired"}, omp)), /in omp/)
    assert.match(Usage.stateMessage(Object.assign({state: "error"}, omp)), /from omp/)
    assert.match(Usage.stateMessage(Object.assign({state: "uncapped"}, omp)), /systemd/)
})

// When omp itself cannot answer, the collector cannot know which accounts it
// would have listed, so it sends one error row for the whole agent directory.
test("omp failing keeps every account of its agent directory on its last reading", () => {
    const group = "omp:/home/u/.omp/agent"
    const before = {fetchedAt: 1000, profiles: [
        profile({id: group + "#a", name: "OMP · a@x", group, agent: "omp"}),
        profile({id: group + "#b", name: "OMP · b@x", group, agent: "omp"}),
        profile({id: "/home/u/.claude", name: "work"})
    ]}
    const after = Usage.merge(before, {fetchedAt: 2000, profiles: [
        profile({id: "/home/u/.claude", name: "work"}),
        {id: group, group, agent: "omp", name: "OMP", state: "error", bars: []}
    ]})
    assert.deepEqual(after.profiles.map(p => p.id), ["/home/u/.claude", group + "#a", group + "#b"])
    const a = Usage.profileById(after, group + "#a")
    assert.equal(a.stale, true)
    assert.equal(a.since, 1000)
    assert.equal(Usage.displayName(a), "OMP · a@x")

    // With nothing to carry, the failure is what shows.
    const cold = Usage.merge(null, {fetchedAt: 2000, profiles: [
        {id: group, group, agent: "omp", name: "OMP", state: "error", bars: []}]})
    assert.equal(cold.profiles[0].state, "error")
})

test("a kept reading keeps its name, not just its bars", () => {
    const before = {fetchedAt: 1000, profiles: [profile({id: "/home/u/.claude", name: "day job"})]}
    const after = Usage.merge(before, {fetchedAt: 2000, profiles: [
        profile({id: "/home/u/.claude", name: "day job", state: "error", bars: []})]})
    assert.equal(Usage.displayName(Usage.profileById(after, "/home/u/.claude")), "day job")
})

// The footer's order is the history of accounts shown, newest first - and the
// widget records the one on screen however it got there, so the history's head
// is always the current account. These walk that through as the widget does.
test("the footer lists accounts most recently shown first", () => {
    const ids = list => list.map(p => p.id)
    const profiles = [{id: "default"}, {id: "personal"}, {id: "omp"}]

    // Never run before: nothing picked, so the widget falls back to an
    // account and records that one like any other.
    let recent = Usage.remember([], "default")
    assert.deepEqual(ids(Usage.byRecency(profiles, recent)), ["default", "personal", "omp"])

    recent = Usage.remember(recent, "omp")
    assert.deepEqual(ids(Usage.byRecency(profiles, recent)), ["omp", "default", "personal"])

    recent = Usage.remember(recent, "personal")
    assert.deepEqual(ids(Usage.byRecency(profiles, recent)), ["personal", "omp", "default"])

    // Back to one already in the history: it moves up, it is not listed twice.
    recent = Usage.remember(recent, "omp")
    assert.deepEqual(recent, ["omp", "personal", "default"])
    assert.deepEqual(ids(Usage.byRecency(profiles, recent)), ["omp", "personal", "default"])
})

test("accounts the history has not seen follow it in the collector's order", () => {
    const profiles = [{id: "a"}, {id: "b"}, {id: "c"}, {id: "d"}]
    assert.deepEqual(Usage.byRecency(profiles, ["c", "gone"]).map(p => p.id), ["c", "a", "b", "d"])
    assert.deepEqual(Usage.byRecency(profiles, null).map(p => p.id), ["a", "b", "c", "d"])
    assert.deepEqual(Usage.byRecency(null, ["a"]), [])
})

test("the history stays bounded and ignores nothing-selected", () => {
    let recent = []
    for (let i = 0; i < 100; i++) {
        recent = Usage.remember(recent, "acct-" + i)
    }
    assert.equal(recent.length, 32)
    assert.equal(recent[0], "acct-99")
    assert.deepEqual(Usage.remember(["a"], ""), ["a"])
    assert.deepEqual(Usage.remember("junk", "a"), ["a"])
})

test("an account is shown by its name and identified by its directory", () => {
    assert.equal(Usage.displayName({id: "/home/u/.claude-side", name: "side"}), "side")
    // No name is not a crash: the directory is at least true.
    assert.equal(Usage.displayName({id: "/home/u/.claude-side"}), "/home/u/.claude-side")
    assert.equal(Usage.displayName(null), "")
})

// The chain the default setting relies on. barIdFor hands barFor either the
// account's stored pick or the configured default, so the order that matters
// is: an id the plan has wins outright, and only an id it lacks falls through
// to the API's own active flag.
test("a wanted limit beats the one the API calls active", () => {
    const p = profile()
    p.bars.forEach(b => { b.active = b.id === "weekly" })

    // The default the widget ships with, against a plan where weekly is the
    // one counting. Before this was configurable the active flag won, so the
    // bar quietly changed which limit it measured when the flag moved.
    assert.equal(Usage.barFor(p, "session").label, "Session")
    assert.equal(Usage.barFor(p, "weekly").label, "Weekly")

    // A default the plan does not carry still falls through rather than
    // leaving the row blank, which is why the setting offers only the two
    // every plan has.
    assert.equal(Usage.barFor(p, "scoped:Nope").label, "Weekly")

    // And the panel resolves it identically, so the strip and the footer
    // cannot end up measuring different limits.
    const usage = {profiles: [Object.assign(p, {id: "/home/u/.claude"})]}
    assert.equal(Usage.panelBar(usage, "/home/u/.claude", "session").label, "Session")
    assert.equal(Usage.panelBar(usage, "/home/u/.claude", "scoped:Nope").label, "Weekly")
})
