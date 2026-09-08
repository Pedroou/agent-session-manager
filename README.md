<div align="center">

# Claude Sessions

**A KDE Plasma 6 panel widget that shows what every running Claude Code session is doing.**

[![Plasma 6](https://img.shields.io/badge/Plasma-6-1d99f3?style=for-the-badge&logo=kde&logoColor=white&labelColor=2d333b)](https://kde.org/plasma-desktop/)
[![QML](https://img.shields.io/badge/QML-41cd52?style=for-the-badge&logo=qt&logoColor=white&labelColor=2d333b)](https://doc.qt.io/qt-6/qmlapplications.html)
[![Licence: MIT](https://img.shields.io/badge/Licence-MIT-blue?style=for-the-badge&labelColor=2d333b)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-118-brightgreen?style=for-the-badge&labelColor=2d333b)](#tests)

<img src="docs/screenshots/panel.png" alt="Five coloured bars in a panel with a usage strip beneath them" width="340">

</div>

Run four Claude Code sessions across four projects and the interesting question
stops being *what is Claude doing* and becomes **which one needs me right now**.

This answers that from the panel. One bar per session, coloured by what it is
doing, with anything blocked on you taking the widget's overall colour however
few of them there are.

<div align="center">
<img src="docs/screenshots/popup.png" alt="The popup listing five sessions, one per state, with a plan usage bar at the bottom" width="620">
</div>

## What the colours mean

| | | |
|---|---|---|
| 🟧 **Waiting** | orange | blocked on you — and it says what for |
| 🟥 **Error** | red | its last turn failed, with the message |
| 🟨 **Running** | yellow | a command or script is executing, and it says which |
| 🟦 **Working** | cyan | Claude is generating |
| ⬜ **Shell** | slate | the terminal has been handed to a shell |
| 🟩 **Done** | green | finished, waiting for your next prompt |

Every one is overridable in settings.

## Features

- **One bar per session in the panel**, plus a running total coloured by the
  state with the most sessions — unless something is waiting on you, which
  always wins.
- **A plan usage strip** under the bars, which can stay hidden until the limit
  is actually worth knowing about.
- **Click a row for its details** — profile, uptime, directory, repository,
  branch, session id, pid, version. Click any value to copy it; every copy is
  confirmed by name, because a row has eight things you might have been aiming
  at.
- **Right-click to copy** the whole row, or — collapsed — the command that drops
  you back into that session.
- **Rename a session** to something you will recognise, and **end one** with a
  button that asks first.
- **Hide every name and path** with one click, for screen-sharing.
- **Two accounts side by side.** Claude Code supports a second config directory
  via `CLAUDE_CONFIG_DIR`; if you run one, both profiles show up, each with its
  own usage bar and limit.

<div align="center">
<img src="docs/screenshots/popup-expanded.png" alt="A session expanded to show profile, uptime, directory, repository, session id, process and version" width="620">
</div>

## Install

Needs Plasma 6, fish 3.2+, `jq`, `curl` and `kpackagetool6`.

```fish
git clone https://github.com/Pedroou/claude-sessions-widget
cd claude-sessions-widget
./install.fish
```

Then right-click the panel → **Add or Manage Widgets…** → search **Claude
Sessions**.

Upgrading while it is already on the panel needs a shell restart, because Plasma
caches applet QML — `install.fish` prints the command.

## How it works

Claude Code already publishes most of this. Every running session maintains a
record at `<config-dir>/sessions/<pid>.json` and rewrites it as its state
changes. No hooks, no wrappers, nothing to configure: the widget is a reader of a
file the tool already writes.

Two of the six states are **not** in that record and are worked out here.

**Running** comes from the process tree. Claude Code executes every Bash tool
call as a direct child shell of its own process, while its long-lived children
are MCP servers — which are not shells, so the two never get confused. The
command itself is recoverable from the child's `cmdline`, which is why a row can
tell you it is running `npm run build`.

**Error** comes from the transcript, whose last assistant entry carries
`isApiErrorMessage` and a message worth reading. The transcript lags live state
badly — the assistant's own tool call is not flushed while a tool is running —
which is exactly why it is trusted only for a session that has already stopped.

Records outlive sessions that were killed rather than closed, so each one is
checked the way Claude Code checks its own: the process must exist **and** its
start time in `/proc` must match the record, which is what rules out a recycled
pid.

There is deliberately **no interrupt button**. Claude Code reads Ctrl+C as a byte
off a raw-mode terminal, and its actual `SIGINT` handler calls the same
`shutdown(0)` as `SIGTERM`. A signal can end a session but cannot pause one, and
a button labelled "interrupt" that quietly ended sessions would be worse than no
button at all.

[`docs/design.md`](docs/design.md) covers the rest — including why each colour is
what it is, and what the usage endpoint does when it rate-limits you.

## Tests

Every decision lives in one of four units that run without a Plasma shell: two
fish collectors, and two Qt-free JavaScript files.

```fish
fish --no-config test/test-collectors.fish   # 70 assertions
node --test test/sessions.test.js            # 29
node --test test/usage.test.js               # 19
```

The fish suite builds a throwaway `$HOME`, a throwaway `/proc` **and** throwaway
transcripts, then runs the real collectors against them. So a recycled pid, a
half-written record, an MCP child that is not a command, an error a session
recovered from, and a command starting with `--` that `jq` would otherwise eat as
a flag are all covered rather than assumed.

## Privacy

The only part that touches the network is the plan-usage bar, which asks
Anthropic for your limits using the login Claude Code already stores — at most
once a minute, and every five minutes on its own. The token is handed to `curl`
through stdin rather than argv, so it never appears in the process list, and the
whole feature has an off switch.

Nothing else leaves the machine, and nothing is written to your Claude Code
config.

## Licence

MIT — see [LICENSE](LICENSE).
