# Claude Sessions

A KDE Plasma 6 panel widget that shows what every running Claude Code session is
doing, so you can tell from the panel whether one of them is blocked on you.

Run four sessions across four projects and the interesting question stops being
"what is Claude doing" and becomes "which one needs me right now". That is the
question this answers without alt-tabbing through terminals.

```
▎▎▎▎ 4          ← in the panel

┌──────────────────────────────────────────────┐
│ Claude Code Sessions                    👁  ⟳ │
│ 1 waiting for you, 2 running, 1 done         │
├──────────────────────────────────────────────┤
│ ▎ checkout-flow-7                          Waiting   │
│ ▎ checkout-flow — input needed                    12s │
│ ▎ docs-site-b2      ✎  ✕  Running   │
│ ▎ Claude-Acc-Manager — npm test           4m │
│ ▎ infra-scripts-a9               Done   │
│ ▎ infra-scripts/master           7m │
├──────────────────────────────────────────────┤
│ ▸ work        ▸  Session ███░░░░░░░░░░  11%  │
└──────────────────────────────────────────────┘
```

## What the colours mean

| | | |
|---|---|---|
| **Waiting** | orange | blocked on you, and it says what for |
| **Error** | red | its last turn failed, with the message |
| **Running** | yellow | a command or script is executing, and it says which |
| **Working** | cyan | Claude is generating |
| **Shell** | slate | the terminal has been handed to a shell |
| **Done** | green | finished, waiting for your next prompt |

The panel shows one bar per session plus a running total, coloured by whichever
state has the most sessions — unless something is waiting on you, which always
wins, because that is the whole point. Every colour is overridable in settings.

## Install

Needs Plasma 6, fish 3.2+, `jq`, `curl` and `kpackagetool6`.

```fish
git clone https://github.com/Pedroou/claude-sessions-widget
cd claude-sessions-widget
./install.fish
```

Then right-click the panel → **Add or Manage Widgets…** → search **Claude
Sessions**. Upgrading it while it is already on the panel needs a shell restart,
because Plasma caches applet QML; `install.fish` prints the command.

## What it does

**Click a row** for its details — profile, uptime, directory, repository, branch,
session id, pid, version — and click any value to copy it. **Right-click** copies
the whole thing, or, closed, the command to get back into that session. Every
copy is confirmed by a pill that floats over the list for a moment and names what
it took, since a row has several things you might have been aiming at.
**Hovering** gives you a pencil, which sets a nickname the widget remembers, and
a close button that asks once before ending the session. The **eye** in the
header blanks every name and path, for screen-sharing.

The popup is as tall as its sessions need and no taller, up to a ceiling you set,
past which it scrolls.

The panel carries a thin usage bar under the session bars for whichever limit
you have selected — no number, just the bar — and it can be set to stay hidden
until the limit is actually worth knowing about.

At the bottom of the popup, each profile's plan usage. Claude Code supports a second config
directory via `CLAUDE_CONFIG_DIR`, so if you run two accounts side by side both
show up here; the selector picks which one is on screen when it is collapsed, and
the arrow beside each picks which limit its bar tracks — session, weekly, or a
model-scoped one, whichever your plan actually reports.

## How it works

Claude Code already publishes most of this. Every running session maintains a
record at `<config-dir>/sessions/<pid>.json` and rewrites it as its state
changes. No hooks, no wrappers, nothing to configure — the widget is a reader of
a file the tool already writes.

Two of the six states are not in that record and are worked out here:

- **Running** comes from the process tree. Claude Code executes every Bash tool
  call as a direct child shell of its own process, while its long-lived children
  are MCP servers, which are not shells — so the two never get confused, and the
  command itself is recoverable and shown.
- **Error** comes from the transcript, whose last assistant entry carries
  `isApiErrorMessage` and a message worth reading. The transcript lags live
  state badly, which is exactly why it is only trusted for a session that has
  already stopped.

Records outlive sessions that were killed rather than closed, so each one is
checked the way Claude Code checks its own: the process must exist *and* its
start time in `/proc` must match the record, which is what rules out a recycled
pid.

There is deliberately no interrupt button. Claude Code reads Ctrl+C as a byte off
a raw-mode terminal, and its actual `SIGINT` handler calls the same `shutdown(0)`
as `SIGTERM` — so a signal can end a session but cannot pause one, and a button
labelled "interrupt" that quietly ended sessions would be worse than none.

`docs/design.md` covers the rest, including why each colour is what it is.

## Tests

The interesting decisions live in two fish collectors and two Qt-free JavaScript
files, all four testable without a running Plasma shell.

```fish
fish --no-config test/test-collectors.fish
node --test test/sessions.test.js
node --test test/usage.test.js
```

The fish suite builds a throwaway `$HOME`, a throwaway `/proc` and throwaway
transcripts, and runs the real collectors against them — so a recycled pid, a
half-written record, an MCP child that is not a command, and an error a session
recovered from are all covered rather than assumed.

## Privacy

The only part that touches the network is the plan-usage footer, which asks
Anthropic for your limits every five minutes using the login Claude Code already
stores. The token is handed to curl through stdin rather than argv, so it never
appears in the process list, and the whole feature has an off switch. Nothing
else leaves the machine, and nothing is written to your Claude Code config.

## Licence

MIT — see [LICENSE](LICENSE).
