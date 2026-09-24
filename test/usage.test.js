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

test("an account is shown by its name and identified by its directory", () => {
    assert.equal(Usage.displayName({id: "/home/u/.claude-side", name: "side"}), "side")
    // No name is not a crash: the directory is at least true.
    assert.equal(Usage.displayName({id: "/home/u/.claude-side"}), "/home/u/.claude-side")
    assert.equal(Usage.displayName(null), "")
})
