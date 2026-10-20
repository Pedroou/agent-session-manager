# Design

**Date:** 2026-09-04, revised 2026-09-08
**Status:** Implemented. Installed by `./install.sh`.
**Plasmoid id:** `io.github.pedroou.agentsessionmanager`

## Goal

You run several Claude Code or OMP sessions at once, in different terminals and
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
`{name, dir}` in `$CLAUDE_PROFILES`.

That list is seeded once, on first run, by the same discovery the settings page
uses - and the fact that it has been seeded is recorded. The first version
instead fell back to `~/.claude` whenever the list was empty, which meant an
empty list could not be told apart from one nobody had filled in yet: the popup
listed an account under a name the user had never chosen while the Accounts page
said there were none. Seeding makes the list the whole truth, empty included.

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

### OMP

[OMP](https://github.com/can1357/oh-my-pi) publishes no registry, so its
sessions are found from the other end - and every step is still a file read.

**Which processes.** Every `/proc/<pid>` whose `comm` is `omp`, or `bun`/`node`
running a script called `omp`. OMP's helpers (`omp __omp_worker_js_eval_process`
and friends) share the name and are skipped by their argument. A process is
alive by construction, so there is no start time to compare.

**Which session.** OMP keeps the session's journal open for as long as it
writes to it, so `/proc/<pid>/fd` names the transcript:
`<agent-dir>/sessions/<project>/<timestamp>_<session-id>.jsonl`. The same
process also holds its subagents' transcripts open, but those are named after
the agent, so the `<timestamp>_<id>` shape picks the session out. Before its
first reply a session has nothing open - OMP creates the file lazily - and a
resumed one has nothing open until it next writes. Both are found through the
breadcrumb OMP writes per terminal for its own `--continue`:
`<agent-dir>/terminal-sessions/pts-4` holds the cwd and the transcript path,
and is trusted only when that cwd is the process's own.

**Which state.** The transcript's tail, read in one jq for every OMP session
(`scripts/omp-sessions.jq`). Bookkeeping entries - usage, titles, model changes -
are skipped, because they land after a turn has ended. Of what remains, the last
entry decides:

| Last entry                                         | Shown as    |
|----------------------------------------------------|-------------|
| assistant, `stopReason: error`                     | **Error**, with `errorMessage` |
| assistant, `stop` / `length` / `aborted`, or `/clear` | **Done** |
| tool call started, no result: `ask`                | **Waiting**, with the question |
| tool call started, no result: `bash` or `eval`     | **Running**, with the command |
| any other tool outstanding, a tool result, a prompt | **Working** |

Unlike Claude Code's transcript this one is live: `tool_execution_start` is
appended the moment a tool begins, which is what makes Running and Waiting
readable from it at all. The name is the session's title, kept in a fixed-width
slot on the file's first line that OMP rewrites in place, minus the private-use
icon OMP puts in front of it. Uptime is the process's own start, from
`/proc/<pid>/stat` and the boot time in `/proc/stat`.

**Which account.** The transcript's agent directory. `~/.omp/agent` is the
stock one; `~/.omp/profiles/<name>/agent` is the named profile `<name>`, shown as
"OMP <name>" and resumed with `omp --profile <name> --resume <id>`. Anything else
is passed back through `PI_CODING_AGENT_DIR`, and a transcript kept outside
every agent directory (`--session-dir`) resumes by its path.

**Off, and the ceilings when on.** The General page's **Show OMP sessions**
(`showOmp`, default on) sends `CLAUDE_SESSIONS_OMP=0` to the collector, which
then skips the whole OMP section - no `/proc` scan, no reads, no processes. On,
what it can cost is bounded whatever the machine is doing:

| What                       | Ceiling                                          |
|----------------------------|--------------------------------------------------|
| Sessions read              | 32; more are left out                            |
| Per file read              | `read -n`: 64 bytes of `comm`, 4 KiB per argument, breadcrumb line or transcript first line |
| Per transcript tail        | 128 KiB, and only from a regular file named `<timestamp>_<id>.jsonl` |
| Processes started          | one `tail` per session, one `readlink` per session with nothing open, one jq for all |
| Per collector process      | 1 GiB address space, 30 CPU-seconds (`ulimit`, only ever lowered) |
| Per collector run          | 20 s, then SIGTERM; SIGKILL 2 s later (`timeout`, from `main.qml`) |
| Runs at once               | one: the DataSource does not restart a source that is still running |

Failure costs the OMP rows of one refresh, never more. A command that cannot
start - out of memory, out of processes, missing - leaves the jq short of a
record per session, and the collector drops all of OMP for that run rather
than misalign the list; nothing is retried and nothing is ever written. A run
takes about 10 MB and a tenth of a CPU second, and still completes under a
128 MB address-space limit, so none of the ceilings binds on a run that works.

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
would be a lie rather than a kindness. Hovering an account's row says when the
limit it shows resets - "resets in 2h 14m", ticking down while the popup is open -
and, for a kept reading, how old it is.

#### OMP's logins

OMP keeps its Claude logins in its own database, per agent directory, and
refreshes their tokens as it uses them. Reading that database would mean
handling another tool's credentials and still showing "expired" for a token OMP
would have refreshed on its next request - so the widget asks OMP instead:

```
omp [--profile <name>] usage --json --provider anthropic --no-extensions
```

once for `~/.omp/agent` and once per `~/.omp/profiles/<name>/agent`, run from
`/` so no project's settings apply. `scripts/omp-usage.jq` turns each
Anthropic account in the answer into a row: `reports[]` become `ok` rows,
`accountsWithoutUsage[]` `error`, `disabledCredentials[]` `expired`. Limits map
onto Claude Code's bar ids - `anthropic:5h` is `session`, `anthropic:7d` is
`weekly`, `Claude 7 Day (Fable)` is `scoped:Fable` - so a limit picked as the
default means the same on both. A row's id is `omp:<agent-dir>#<account>` and
it carries `group: omp:<agent-dir>`; when omp gives no usable answer at all the
collector sends one `error` row whose id *is* the group, and `Usage.merge` lets
it stand for every account of that group that had a reading, so a failed run
keeps the bars on screen exactly as a failed Claude Code fetch does.

`omp` is a Bun binary that maps about 13 GB of address space and touches about
190 MB, so the collector's `ulimit -v` approach cannot bound it. It runs inside
a transient systemd scope instead:

```
timeout -k 2 15 systemd-run --user --scope --quiet --collect \
    -p MemoryMax=512M -p MemorySwapMax=0 -p TasksMax=64 -- omp …
```

The kernel enforces those on the scope: past 512 MB omp alone is OOM-killed
inside it (measured: under a 64 MB cap it exits 137 and nothing else is
touched). Output is read up to 1 MiB. Where `systemd-run` or the user manager's
socket is missing, omp is not run and the row's state is `uncapped`. The whole
usage run is also under `timeout -k 2 60` from `main.qml`.

With nothing chosen, the footer and the panel strip follow the first account
that has a reading rather than the first account: someone who has moved to OMP
still has a signed-out `~/.claude` at the top of the list.

#### The footer's order

Opened up, the footer lists accounts most recently shown first. There is no
"current account goes on top" rule; there is one history, `usageRecent`, newest
first, and `main.qml` writes into it whichever account is actually on screen -
picked by hand, picked automatically on a first run, or fallen back to after the
picked one went away. Since the history's head is therefore always the current
account, `Usage.byRecency` ordering by the history alone puts it on top, the one
shown before it second, and accounts never shown after, in the collector's
order. The write only happens when the head is wrong, and it is checked when
either the selection or the history changes, so a reset or a hand-edited history
is put right at once without the write ever triggering itself. The history keeps
the 32 most recent ids.

## Architecture

```
install.sh                       # kpackagetool6 --install / --upgrade
package/
  metadata.json
  contents/
    scripts/claude-sessions      # bash: registry + /proc + transcripts → JSON
    scripts/omp-sessions.jq      # OMP transcript tails → registry-shaped records
    scripts/claude-usage         # bash: credentials + usage API → JSON
    scripts/omp-usage.jq         # `omp usage --json` → usage profiles
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
    ui/Config{General,Panel,Popup,Profiles,Colours}.qml
    config/{main.xml,config.qml}
    scripts/claude-find-profiles   # account discovery, for the settings page
    icons/{io.github.pedroou.agentsessionmanager,reload}.svg
test/
  sessions.test.js               # node tests for the pure layers
  usage.test.js
  test-collectors.fish           # sandbox tests for both collectors
tools/screenshots/               # the rig that produces docs/screenshots
docs/design.md                   # this file
```

### The isolation boundary

Everything with a decision in it sits in one of six testable units; the QML
binds and lays out.

**`scripts/claude-sessions`** owns the registry: which directories to read,
which records are live, how a status maps to a state, the two states that are
worked out rather than read, the git repository and branch behind each session,
and what order they come in. It also finds OMP's sessions, and hands their
transcripts to **`scripts/omp-sessions.jq`**, which owns what an OMP transcript
means. It prints one document and nothing else, which is also how it is tested -
`test/test-collectors.fish` builds a throwaway `$HOME`, a throwaway `/proc`
(`CLAUDE_SESSIONS_PROC`) and throwaway transcripts, and runs the real script
against them.

**`scripts/claude-usage`** owns the credentials and the API call, with
`CLAUDE_USAGE_FIXTURE` standing in for the network under test, and asks omp
for OMP's; **`scripts/omp-usage.jq`** owns what omp's answer means. The suite
stands a fake `omp` and a fake `systemd-run` in for the real ones and checks
the cap omp is started under.

**`code/sessions.js`** and **`code/usage.js`** own presentation: relative ages,
the summary sentence broken into colourable parts, which state dominates, the
detail rows and their order, the resume command's shell quoting, and the
fallbacks when a limit or a profile is missing. Plain JavaScript with no Qt
import, loaded by node in `test/`.

Costs, measured: the session collector runs two programs and takes ~25 ms; it reads
`/proc` and record bodies with bash builtins rather than forked `cat`s, which is
what took it there from ~520 ms, and its helpers hand their answers back in
variables rather than through a `$(…)` subshell each. Looking for OMP adds a
read of every process's `comm` (~15 ms over 500 processes), and each OMP session
found adds one `tail`, with one `realpath` and one jq shared between them: three
sessions took a run from 25 ms to 90 ms.

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

Ending checks the target first. `kill(2)` reads pid 0 as the caller's own
process group and a negative pid as a whole group, so `Sessions.endCommand`
refuses anything but digits above 1; and a pid can be reused by the time the
button is pressed, so the command re-reads the start time from
`/proc/<pid>/stat` and signals only if it still equals the one the collector
reported (`procStart`, which both agents now carry). A session without a known
start time has no end button.

## Error and empty states

| Condition                          | Panel                     | Popup                                                    |
|------------------------------------|---------------------------|-----------------------------------------------------------|
| Nothing running                    | faint tick, no number     | "No sessions running" / "Open a terminal and run claude or omp to start one." |
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

Five pages, each a `KCM.SimpleKCM` rather than a bare `Kirigami.FormLayout` -
that wrapper is what gives a config page its title and its margins, because the
config dialog instantiates each page with `title` set to the category's name and
a root with a `title` property picks it up. Plasma's own About and Keyboard
Shortcuts pages are built the same way; ours started out flush against the top
with no heading, which is what gave them away as third-party.

They are split by *where* a setting takes effect rather than by what kind of
thing it is - the same split the widely-used plasmoids arrive at once they have
both a panel and a popup to configure, and the reason a single "General" page
stopped working here.

**General** - how often to check, the needs-attention highlight, the privacy
toggle that blanks names and paths, and OMP's two switches: its sessions, and
its plan usage. They sit here rather than with the accounts because OMP has no
accounts to list - both are found on their own. Then, last and set apart, one
button that resets every page. Plasma's applet dialog has no Defaults button of
its own, so the widget provides it; a control that throws away every setting
belongs at the end of the first page rather than at the top competing with the
settings it would discard.

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
  interpretation lives in one bash script with its own test suite.
- **So is the usage endpoint**, and so is `isApiErrorMessage`. A change to
  either degrades one panel of the widget, not the widget.
- **So is OMP's transcript, in part.** Its layout is written up in OMP's own
  documentation, but `tool_execution_start` and the title slot are core
  bookkeeping rather than an interface. A change there costs Running, Waiting or
  the name - never the session - and all of it is one jq file under test.
- **`/proc` is Linux-only.** So is a Plasma panel, so this costs nothing here.
- **Plasma caches applet QML.** After an upgrade the shell has to be restarted
  before the new code loads; `install.sh` says so rather than doing it.

## The screenshots

`docs/screenshots/` is generated, not captured. `tools/screenshots/` fabricates
a home directory, mounts it at `/home/dev` with `bwrap`, drives a real
`CompactView` and `FullView` through a scripted timeline, and writes frames out
with `grabToImage`.

The reason is not consistency, though it buys that too. The widget displays
directories, branch names and session ids, so a screenshot of it is a screenshot
of whoever took it - and that is not a leak that can be fixed afterwards,
because the images are rendered pixels and a real path in one cannot be found by
grepping the repository. Fabricating the home means there is no real path in the
process's view of the filesystem to render in the first place.

`tools/screenshots/README.md` has the scenarios, the environment the capture
needs, and the handful of things that turned out to matter - why the clock is
frozen, why a child item is grabbed rather than the stage, and why the device
pixel ratio is the zoom.
