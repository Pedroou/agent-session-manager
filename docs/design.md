# Design

**Date:** 2026-09-04, revised 2026-09-08
**Status:** Implemented. Installed by `./install.fish`.
**Plasmoid id:** `com.claudeaccmanager.claudesessions`

## Goal

You run several Claude Code sessions at once, in different terminals and
different projects. One of them is blocked on a permission prompt while you are
reading another. The widget answers one question from the panel, without you
alt-tabbing through terminals: **is any session waiting on me?** Opening it
answers the follow-ups: which one, in which project, on which branch, for how
long, and how much of the plan each account has left.

## Non-goals

- No control over what a session is *doing*. It can end a session, because that
  is a signal the process handles; it cannot interrupt one (see "Interrupting",
  below).
- No history. A session that has exited is gone from the list, not greyed out.
- No renaming of the real session. Claude Code owns that name and rewrites its
  record constantly; the widget keeps a nickname of its own instead.

## Data source

Claude Code already publishes most of what the widget needs. Every running
session maintains its own record at `<profile-dir>/sessions/<pid>.json` and
rewrites it whenever its state changes:

```json
{
  "pid": 299676,
  "sessionId": "8bc54fbf-…",
  "cwd": "/home/dev/code/checkout-flow",
  "name": "checkout-flow-7",
  "kind": "interactive",
  "status": "waiting",
  "waitingFor": "input needed",
  "procStart": "1789211",
  "startedAt": 1788540652634,
  "statusUpdatedAt": 1788543329846,
  "version": "2.1.263"
}
```

No hooks and no polling of transcripts for live state. `status` is a closed set
of four values, confirmed against the binary (`var Ke=["busy","shell","idle",
"waiting"]`, guarding the field on read).

### The six states

Four come from the registry. Two are worked out here, because the registry has
no idea about either.

| Shown as    | Source                                    | Means                                                        |
|-------------|-------------------------------------------|--------------------------------------------------------------|
| **Waiting** | `status: waiting`                         | Blocked on you - a permission prompt, a dialog, an MCP request. `waitingFor`/`needs` says which. |
| **Error**   | worked out - transcript                   | Idle, and its last turn ended in an API error. The message is shown. |
| **Running** | worked out - `/proc`                      | Busy, with a shell command or script executing. The command is shown. |
| **Working** | `status: busy`                            | Claude is generating, with no command out                    |
| **Shell**   | `status: shell`                           | The session has handed the terminal to a shell               |
| **Done**    | `status: idle`                            | Finished; waiting for your next prompt                       |

A seventh display state, **unknown**, catches any value a future version
invents: it is counted and listed with the raw status title-cased, never
dropped. The order above is also the sort order and the order the summary
sentence reads in.

**Running** is detected from the process tree. Claude Code runs every Bash tool
call as a direct child shell of its own process; its long-lived children are MCP
servers (`npm exec …`), which are not shells, so the two never get confused. The
`eval '…'` payload in the child's `cmdline` is the command, and it is shown.
Subagents run *inside* the process and leave no trace in `/proc`, so a session
thinking through a subagent is indistinguishable from one thinking on its own -
both read as Working.

**Error** is detected from the transcript. A session whose turn fails goes back
to `idle`, but the transcript records it, and the last assistant entry carries
`isApiErrorMessage` with a message worth reading ("You've hit your session limit
· resets 6:40pm", "Login expired · Please run /login"). The transcript is a
lagging source - the assistant's own `tool_use` entry is not flushed while a
tool runs - which is exactly why it is only trusted for a state the session has
already stopped in.

### Liveness

A record outlives its session when the process is killed rather than exiting
cleanly, so a record alone does not mean "running". Each one is checked the way
Claude Code checks its own: the process must exist **and** field 22 of
`/proc/<pid>/stat` - the start time in clock ticks - must equal the record's
`procStart`. That second half is what rules out a recycled pid.

### Accounts

`sessions/` is per config directory, so reading more than one account is reading
more than one directory. Which directories is not something to guess at:
`CLAUDE_CONFIG_DIR` is Claude Code's own switch and it takes any path, so the
widget hands the collectors the list the user configured, as a JSON array of
`{name, dir}` in `$CLAUDE_PROFILES`. Nothing configured falls back to `~/.claude`
so a fresh install still shows something.

An account is identified by its directory throughout - two of them may well be
called the same thing - and the name exists only to be printed. That is also
what makes the resume command right for any account: `CLAUDE_CONFIG_DIR=<dir>
claude --resume <id>`, except for `~/.claude`, the one value Claude Code
documents as never to set it to.

The account is only *shown* on a row when the list on screen actually spans more
than one of them.

Discovery is a separate script, `claude-find-profiles`, and it only runs when
the settings page asks. A directory counts as an account when Claude Code has
written `.claude.json` or `.credentials.json` into it - with the home directory
itself excluded, because the stock profile keeps its `.claude.json` beside
`~/.claude` rather than inside it. The same script answers "what is under here?"
and "is this one?", which is how a path typed by hand gets checked before it
joins the list.

### Plan usage

The percentages behind Claude Code's own `/usage` come from one authenticated
call, using the bearer token each profile already stores:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken>          # from <profile>/.credentials.json
anthropic-beta: oauth-2025-04-20
```

The token goes to curl through stdin (`--config -`), never argv, so it does not
appear in the process list. `limits[]` already carries a percentage, a severity,
a reset time and - for scoped limits - the model they belong to, so the bars on
offer are whatever the plan actually has rather than a hardcoded three. Today
that is Session, Weekly and Fable.

This is the only part of the widget that touches the network, so it is the only
part with an off switch, and it runs on a five-minute timer rather than the
session poll. Opening the popup also asks for a reading, but no more often than
once a minute - otherwise a habit of opening and closing the widget is enough to
get throttled, and the punishment arrives as an empty bar.

When a fetch does fail, the profile keeps the bars it had rather than blanking:
the endpoint rate-limits, and a reading that was right a minute ago beats no
reading at all. Only an `error` is carried forward like this. `absent` and
`expired` are real answers about the account, and hiding those behind a stale bar
would be a lie rather than a kindness. The percentage's tooltip says how old a
kept reading is.

## Architecture

```
install.fish                     # kpackagetool6 --install / --upgrade
package/
  metadata.json
  contents/
    scripts/claude-sessions      # fish: registry + /proc + transcripts → JSON
    scripts/claude-usage         # fish: credentials + usage API → JSON
    code/sessions.js             # pure display logic, no Qt
    code/usage.js                # pure usage logic, no Qt
    ui/main.qml                  # PlasmoidItem: polling, state, colours
    ui/CompactView.qml           # the panel
    ui/FullView.qml              # the popup
    ui/SessionRow.qml            # one session
    ui/Rail.qml                  # one bar
    ui/ProfileFooter.qml         # the profile selector
    ui/UsageBar.qml              # one plan limit
    ui/CopyToast.qml             # the copy confirmation
    ui/Config{General,Panel,Popup,Colours}.qml
    config/{main.xml,config.qml}
    icons/{claude-sessions,reload}.svg
test/
  sessions.test.js               # node tests for the pure layers
  usage.test.js
  test-collectors.fish           # sandbox tests for both collectors
docs/design.md                   # this file
```

### The isolation boundary

Everything with a decision in it sits in one of four testable units; the QML
binds and lays out.

**`scripts/claude-sessions`** owns the registry: which directories to read,
which records are live, how a status maps to a state, the two states that are
worked out rather than read, the git repository and branch behind each session,
and what order they come in. It prints one document and nothing else, which is
also how it is tested - `test/test-collectors.fish` builds a throwaway `$HOME`, a
throwaway `/proc` (`CLAUDE_SESSIONS_PROC`) and throwaway transcripts, and runs
the real script against them.

**`scripts/claude-usage`** owns the credentials and the API call, with
`CLAUDE_USAGE_FIXTURE` standing in for the network under test.

**`code/sessions.js`** and **`code/usage.js`** own presentation: relative ages,
the summary sentence broken into colourable parts, which state dominates, the
detail rows and their order, the resume command's shell quoting, and the
fallbacks when a limit or a profile is missing. Plain JavaScript with no Qt
import, loaded by node in `test/`.

Costs, measured: the session collector is two subprocesses and ~75 ms; it reads
`/proc` and record bodies with fish builtins rather than forked `cat`s, which is
what took it there from ~520 ms.

### Data flow

1. A `Timer` in `main.qml` fires - every second while the popup is open, every
   `refreshInterval` seconds (default 5) while it is closed. A second, five-minute
   timer drives usage.
2. `Plasma5Support.DataSource` (`executable` engine) runs the collector,
   resolved from inside the package with `Qt.resolvedUrl`.
3. `onNewData` parses stdout, or sets `failure` from stderr. A non-zero exit,
   empty output, or unparseable JSON is a failure state, never a silent empty
   list. A failed *usage* fetch leaves the last good reading on screen instead.
4. The views bind to `shown` (the configured filter applied) and `shownCounts`
   (derived from `shown`, so the header can never contradict the list).

## What it looks like

The one invented device is the **rail**: a session is a rounded bar, and the same
bar appears in both representations, so the popup reads as the panel opened up.
All rails are the same length; colour alone carries the state.

Status colours are the widget's own rather than the theme's, because the theme
accent is usually blue and blue is exactly what disappears into a blue panel.
The defaults are mid-tones - the weight a palette reserves for "legible on either
background" - and every one of them is overridable:

| State   | Default   | Why                                                        |
|---------|-----------|------------------------------------------------------------|
| Waiting | `#f97316` | orange: a person has to do something                        |
| Error   | `#ef4444` | red: the long-standing meaning, not worth reinventing       |
| Running | `#eab308` | yellow: busy, but nobody is being waited on                 |
| Working | `#06b6d4` | cyan: active, and the one that had to leave blue behind     |
| Shell   | `#94a3b8` | slate: a real state, but not one to shout about             |
| Done    | `#22c55e` | green: finished                                             |

Blue is the commonest convention for "in progress" and is deliberately unused; a
test asserts no default is a blue.

**Panel.** The bars side by side, with the running total beside them in the
colour of the state with the most sessions - except that anything blocked on a
person wins outright, however few, since that is the question the panel exists to
answer. Capped at eight bars; past that the number carries it. Nothing running
draws one faint tick - quiet, not broken. Vertical panels stack the bars.

**Popup.** A heading, then one sentence - "1 waiting for you, 3 working" - with
each count in its own status colour, then the list, sorted with anything blocked
at the top. The popup is as tall as its sessions need and no taller, up to a
ceiling in settings, past which the list scrolls.

```
Claude Code Sessions                    👁  ⟳
1 waiting for you, 2 running, 1 done
──────────────────────────────────────────────
▎ checkout-flow-7                          Waiting
▎ checkout-flow - input needed                    12s
▎ docs-site-b2      ✎  ✕  Running
▎ docs-site - npm run build           4m
──────────────────────────────────────────────
▸ work        ▸  Session ███░░░░░░░  11%
```

Clicking a row opens its details - Profile, Uptime, Directory, Repository,
Branch, Session, Process, Version - and clicking any value copies it. Right-
clicking copies the whole thing when open, and the command to get back into the
session when closed.

Every copy is confirmed by a pill that floats over the list for about two
seconds. It floats rather than sitting in the layout so a copy never reflows the
popup under the pointer, and it names what it took - "Repository copied",
"Resume command copied" - because a single row offers half a dozen copy targets
and a bare "Copied" would leave you guessing which one you hit. It is
deliberately not a system notification: this is a keystroke-sized action, and
routing it to the notification centre would bury the messages that matter. Hovering reveals a pencil, which gives the session a
nickname the widget keeps, and a close button that asks once before ending it.
The eye in the header blanks every name and path for screen-sharing.

**The panel's usage strip.** Under the session bars, a thin bar for whichever
limit the popup's footer is set to, on whichever profile it has selected - the
same measurement, without the number, because at panel size a percentage is
unreadable and the point is the glance. It can be held back until the limit is
some way gone, so it stays out of the way until it means something.

**Motion.** Exactly one thing moves on its own: a working session breathes - the
rail and its "Working" label together. The label follows the rail's opacity
rather than running a second animation, because two identical animations started
in the same frame look synchronised right up until something restarts one of
them. It stops when the user has turned animations off.

## Interrupting

There is no interrupt button, and this is the one item on the request list that
could not be built as asked.

Claude Code puts the terminal in raw mode and reads Ctrl+C as a *byte* off the
input stream. Its actual signal handlers do something else entirely:

```js
process.on("SIGINT", () => { …; rU(); this.shutdown(0) })
process.on("SIGTERM", () => { …; rU(); this.shutdown(0) })
```

Both signals mean "shut down". So a signal can end a session but cannot pause
one, and a button labelled "interrupt" that quietly ended sessions would be worse
than no button. Ending is kept, because SIGTERM is genuinely the graceful path
and the transcript survives - which is what the right-click resume command is
for. Doing this properly would mean speaking the peer protocol on
`messagingSocketPath`, which is undocumented and not worth the risk here.

## Error and empty states

| Condition                          | Panel                     | Popup                                                    |
|------------------------------------|---------------------------|-----------------------------------------------------------|
| Nothing running                    | faint tick, no number     | "No sessions running" / "Open a terminal and run claude to start one." |
| Before the first result            | faint tick                | nothing - an empty list would be a guess, not an answer   |
| Collector failed / unparseable     | tick in the error colour  | "Can't read the session list" + stderr                    |
| A torn or malformed record         | unaffected                | that one record is skipped, the rest still listed         |
| Profile not signed in              | unaffected                | "Not signed in" in place of its usage bar                 |
| Token expired                      | unaffected                | "Signed out - run claude to sign back in"                 |
| Usage API unreachable, or rate-limiting | unaffected           | last good reading stays; "Couldn't reach the usage API" if there was none |

A note on that last row, learned the hard way: the endpoint answers a rate-limited
request with a perfectly valid JSON error object. It has no `limits` key, so it
parsed as "this plan has no limits" and the widget quietly showed an empty
footer. `curl --fail` plus a type check on `limits` turns that back into the
failure it is.

## Settings

Four pages, each a `KCM.SimpleKCM` rather than a bare `Kirigami.FormLayout` -
that wrapper is what gives a config page its title and its margins, because the
config dialog instantiates each page with `title` set to the category's name and
a root with a `title` property picks it up. Plasma's own About and Keyboard
Shortcuts pages are built the same way; ours started out flush against the top
with no heading, which is what gave them away as third-party.

They are split by *where* a setting takes effect rather than by what kind of
thing it is - the same split the widely-used plasmoids arrive at once they have
both a panel and a popup to configure, and the reason a single "General" page
stopped working here.

**General** - how often to check, the needs-attention highlight, and the privacy
toggle that blanks names and paths. Then, last and set apart, one button that
resets every page. Plasma's applet dialog has no Defaults button of its own, so
the widget provides it; a control that throws away every setting belongs at the
end of the first page rather than at the top competing with the settings it would
discard.

**Panel** - the session count and its size, and the usage strip: whether to show
it, how used the limit has to be before it appears, and whether it colours itself
by severity.

**Popup** - how many sessions it shows before scrolling, whether finished
sessions are listed, whether
the usage footer shows, and which rows an expanded session has. Where the branch
goes is a two-option chooser rather than a checkbox hanging off the Branch tick,
which read as an afterthought and looked like one.

**Colours** - the six status colours, each with its own revert. Off goes back to
the built-ins rather than to the last colours picked.

All of it resets from one button, at the foot of the General page.

- **Check every** *n* seconds (1-60, default 5) while the popup is closed.
- **Popup max height**, counted in sessions (3-25, default 5). Grid units were
  the old unit and meant nothing to anyone reading the dialog. It is a fixed
  height, not a ceiling: four sessions in a popup set to five leave space rather
  than shrinking the window, because a popup that changed shape every time a
  session started or ended was unreadable as a setting. The minimum, preferred
  and maximum heights are all the same number, which Plasma propagates to the
  window, so it cannot be dragged and any remembered height is clamped away.
- **Show**: sessions that are done · the session count in the panel · the
  needs-attention highlight · plan usage.
- **Customize status colours** - off uses the built-ins; on reveals a picker per
  state, each with its own revert button. Turning it off goes back to the
  defaults rather than to the last colours picked.
- **Session details** - Repository, Branch (and whether the branch gets its own
  row or rides on the repository as `repo/branch`), Session, Process, Version.
  Profile, Uptime and Directory are not optional: they are what the expansion is
  for. Directory and Repository can be abbreviated to Dir and Repo.
- **Hide session names and paths** - the same toggle as the eye in the header.

## Risks

- **The registry is a Claude Code internal.** `sessions/<pid>.json` is not
  documented API, and the `status` vocabulary could grow. Two things contain
  that: an unrecognised status is displayed rather than dropped, and all the
  interpretation lives in one fish script with its own test suite.
- **So is the usage endpoint**, and so is `isApiErrorMessage`. A change to
  either degrades one panel of the widget, not the widget.
- **`/proc` is Linux-only.** So is a Plasma panel, so this costs nothing here.
- **Plasma caches applet QML.** After an upgrade the shell has to be restarted
  before the new code loads; `install.fish` says so rather than doing it.
