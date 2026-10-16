// Pure helpers for the plan-usage footer. No Qt or QML dependency, so the same
// file is exercised by plasmoid/test/usage.test.js under node.

// Which bar a profile should show. The user's pick wins; failing that the limit
// the API says is currently active, which is the one actually biting; failing
// that whatever came first.
function barFor(profile, wantedId) {
    var bars = (profile && profile.bars) || []
    if (!bars.length) {
        return null
    }
    for (var i = 0; i < bars.length; i++) {
        if (bars[i].id === wantedId) {
            return bars[i]
        }
    }
    for (var j = 0; j < bars.length; j++) {
        if (bars[j].active) {
            return bars[j]
        }
    }
    return bars[0]
}

// green / amber / red, from the API's own severity where it gives one.
function severity(bar) {
    if (!bar) {
        return "normal"
    }
    if (bar.severity === "normal" || bar.severity === "warning") {
        return bar.severity
    }
    if (bar.severity && bar.severity !== "") {
        return "critical"
    }
    var percent = bar.percent || 0
    return percent > 90 ? "critical" : (percent >= 70 ? "warning" : "normal")
}

// "resets in 2h 14m", "resets in 3d". Blank when the API gave no reset time,
// which happens for limits that are not currently counting.
function resetText(resetsAt, nowMs) {
    if (!resetsAt) {
        return ""
    }
    var at = Date.parse(resetsAt)
    if (isNaN(at)) {
        return ""
    }
    var seconds = Math.round((at - nowMs) / 1000)
    if (seconds <= 0) {
        return "resets any moment"
    }
    var minutes = Math.floor(seconds / 60)
    if (minutes < 60) {
        return "resets in " + Math.max(1, minutes) + "m"
    }
    var hours = Math.floor(minutes / 60)
    if (hours < 24) {
        return minutes % 60 ? "resets in " + hours + "h " + (minutes % 60) + "m"
                            : "resets in " + hours + "h"
    }
    var days = Math.floor(hours / 24)
    return hours % 24 ? "resets in " + days + "d " + (hours % 24) + "h"
                      : "resets in " + days + "d"
}

// What to say when a profile has no bars to draw. Each one names the fix - and
// the fix depends on which tool holds the login.
function stateMessage(profile) {
    if (!profile) {
        return "No such profile"
    }
    var omp = profile.agent === "omp"
    switch (profile.state) {
    case "ok":
        return (profile.bars && profile.bars.length) ? "" : "This plan reports no limits"
    case "absent":
        return "Not signed in"
    case "expired":
        return omp ? "Signed out - log in again in omp" : "Signed out - run claude to sign back in"
    case "uncapped":
        return "Not checked - needs systemd to cap omp's memory"
    default:
        return omp ? "Couldn't get usage from omp" : "Couldn't reach the usage API"
    }
}

function profileById(usage, id) {
    var list = (usage && usage.profiles) || []
    for (var i = 0; i < list.length; i++) {
        if (list[i].id === id) {
            return list[i]
        }
    }
    return null
}

// The profiles worth putting in the selector: any that exist, in a stable order,
// so the list does not reshuffle as tokens expire.
function selectableProfiles(usage) {
    var list = (usage && usage.profiles) || []
    return list.filter(function (p) {
        return p && p.id
    })
}

// The account the footer and the panel are pointed at.
//
// Accounts are identified by their config directory, and that list is the
// user's to edit - so the one that was selected can simply stop existing. An id
// that no longer matches falls back to the first account that has a reading,
// then to the first at all, rather than leaving the bar blank, which would read
// as "no usage" rather than "not that one". A reading first, because the first
// account is often one nobody signs into any more - someone who moved to OMP
// still has a signed-out ~/.claude at the top of the list.
function selectedProfile(usage, wantedId) {
    var list = selectableProfiles(usage)
    if (!list.length) {
        return null
    }
    for (var i = 0; i < list.length; i++) {
        if (list[i].id === wantedId) {
            return list[i]
        }
    }
    for (var j = 0; j < list.length; j++) {
        if (list[j].bars && list[j].bars.length) {
            return list[j]
        }
    }
    return list[0]
}

function selectedId(usage, wantedId) {
    var profile = selectedProfile(usage, wantedId)
    return profile ? profile.id : ""
}

// What to call an account on screen. The id is its directory, which is right
// for identity and wrong for a label.
function displayName(profile) {
    if (!profile) {
        return ""
    }
    return profile.name || profile.id || ""
}

// The bar the panel strip tracks: whichever account the footer has selected, and
// whichever limit was chosen for it - so the panel and the popup never disagree
// about what is being measured.
function panelBar(usage, profileId, barId) {
    return barFor(selectedProfile(usage, profileId), barId)
}

// Whether a bar has passed the point at which the panel bothers drawing it.
// A threshold of 0 means "always", since every percentage clears it.
function pastThreshold(bar, threshold) {
    if (!bar) {
        return false
    }
    return (bar.percent || 0) >= (threshold || 0)
}

// Carry a profile's last good bars forward when a fetch fails.
//
// The endpoint is an undocumented internal and it rate-limits; a 429 or a
// dropped connection used to blank a bar that was correct a minute ago. Only an
// `error` is papered over - `absent` and `expired` are real answers about the
// account, and hiding those behind a stale bar would be a lie rather than a
// kindness.
//
// OMP's accounts come in groups, one per agent directory, and when omp itself
// fails to answer there is no telling which accounts it would have listed: the
// collector sends one error row whose id is the group's. That row stands in for
// every account of the group that had a reading last time.
function merge(previous, fresh) {
    if (!fresh) {
        return previous
    }
    var was = {}
    var older = (previous && previous.profiles) || []
    for (var i = 0; i < older.length; i++) {
        was[older[i].id] = older[i]
    }

    function keepable(before) {
        return before && before.state === "ok" && before.bars && before.bars.length
    }
    function kept(before, name) {
        return Object.assign({}, before, {
            name: name || before.name,
            stale: true,
            since: before.stale ? before.since : (previous ? previous.fetchedAt : 0)
        })
    }

    var out = []
    var list = fresh.profiles || []
    for (var j = 0; j < list.length; j++) {
        var now = list[j]
        if (now.state === "error" && now.group && now.id === now.group) {
            var members = older.filter(function (p) {
                return p.group === now.group && p.id !== now.group && keepable(p)
            })
            if (members.length) {
                for (var k = 0; k < members.length; k++) {
                    out.push(kept(members[k]))
                }
                continue
            }
        }
        var before = was[now.id]
        if (now.state === "error" && keepable(before)) {
            out.push(kept(before, now.name))
        } else {
            out.push(now)
        }
    }
    return {fetchedAt: fresh.fetchedAt, profiles: out}
}

// Present only under node; QML ignores it.
if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        barFor: barFor,
        severity: severity,
        resetText: resetText,
        stateMessage: stateMessage,
        profileById: profileById,
        selectableProfiles: selectableProfiles,
        selectedProfile: selectedProfile,
        selectedId: selectedId,
        displayName: displayName,
        panelBar: panelBar,
        pastThreshold: pastThreshold,
        merge: merge
    }
}
