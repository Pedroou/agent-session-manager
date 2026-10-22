<div align="center">

<img src="docs/screenshots/logo.png" alt="" width="112">

<h1>Agent Session Manager</h1>

<p><b>See which of your Claude Code sessions needs you, from your Plasma panel.</b></p>

<p>
<img alt="KDE Plasma 6" src="https://img.shields.io/badge/KDE_Plasma-6-1d99f3?style=flat-square&logo=kde&logoColor=white&labelColor=2d333b">
<img alt="QML and bash" src="https://img.shields.io/badge/QML_%2B_bash-41cd52?style=flat-square&logo=qt&logoColor=white&labelColor=2d333b">
<a href="https://store.kde.org/p/2379987/"><img alt="KDE Store" src="https://img.shields.io/badge/KDE_Store-Agent_Session_Manager-1d99f3?style=flat-square&logo=kde&logoColor=white&labelColor=2d333b"></a>
<a href="https://github.com/Pedroou/agent-session-manager/actions/workflows/tests.yml"><img alt="tests" src="https://img.shields.io/github/actions/workflow/status/Pedroou/agent-session-manager/tests.yml?branch=main&style=flat-square&label=tests&labelColor=2d333b"></a>
<a href="LICENSE"><img alt="MIT licence" src="https://img.shields.io/badge/licence-MIT-blue?style=flat-square&labelColor=2d333b"></a>
</p>

<p>
<a href="#features">Features</a> •
<a href="#reading-the-panel">Reading the panel</a> •
<a href="#install">Install</a> •
<a href="#how-it-works">How it works</a>
</p>

<img src="docs/screenshots/demo.gif" alt="The panel bars and the popup updating as sessions change state" width="760">

</div>

Run several Claude Code or OMP sessions at once and the interesting question
stops being *what is the agent doing* and becomes **which one is waiting on me**.
This puts the answer in your panel: one bar per session, coloured by what that
session is doing, so a glance is enough.

## Features

- **Live status for every session** - waiting on you, stopped on an error,
  running a command, working, in a shell, or done.
- **Claude Code and [OMP](https://github.com/can1357/oh-my-pi)**, side by side
  in one list.
- **No setup.** It reads what each tool already writes: Claude Code's session
  registry, and the transcript every OMP session keeps open. No hooks, no
  wrappers, no config files to place.
- **Jump to any session.** Click its name and its terminal comes forward - on
  the right tab in Konsole, the right pane in tmux.
- **Model and context at a glance** - which model each session is on, and how
  full its context window is.
- **A popup with the details** - directory, git repository and branch, uptime,
  session id, pid. Click any value to copy it.
- **Your plan usage**, per Claude Code account, for whichever limit you care
  about.
- **Multiple account profiles.** Claude Code switches accounts with
  `CLAUDE_CONFIG_DIR`, which takes any path; OMP's named profiles are picked up
  on their own.
- **Native Plasma theming**, with every status colour overridable.

## Reading the panel

<div align="center">
<img src="docs/screenshots/panel.png" alt="Five coloured bars with a usage strip beneath and the session count beside them" width="122">
</div>

<div align="center">

| | State | Meaning |
|:--:|---|---|
| <img src="docs/screenshots/chips/error.png" alt="" width="34"> | **Error** | its last turn failed, and the message is shown |
| <img src="docs/screenshots/chips/waiting.png" alt="" width="34"> | **Waiting** | blocked on you, and it says what for |
| <img src="docs/screenshots/chips/running.png" alt="" width="34"> | **Running** | a command or script is executing, and it says which |
| <img src="docs/screenshots/chips/working.png" alt="" width="34"> | **Working** | Claude is generating |
| <img src="docs/screenshots/chips/shell.png" alt="" width="34"> | **Shell** | the terminal has been handed to a shell |
| <img src="docs/screenshots/chips/done.png" alt="" width="34"> | **Done** | finished, waiting for your next prompt |

</div>

The number beside the bars is the session count, coloured by whichever state has
the most sessions - unless something is waiting on you, which always takes
priority. Underneath sits a thin bar for your plan usage, which turns amber
and then red as the limit fills.

## The popup

Click the widget for the full list, sorted so whatever is blocked sits at the
top. Click a session's name to go to it: the window it runs in comes forward,
on the right Konsole tab or tmux pane. Click anywhere else on the row to open
its details, and any value to copy it. Right-click copies the whole row, or the
command to drop back into that session.

Under each state sits the model the session is on and a bar for how full its
context window is, amber past three quarters and red past 90%. Hover it for the
token count. The model and the bar can each be turned off on the Popup settings
page, and the exact percentage turned on.

<div align="center">
<img src="docs/screenshots/copy.gif" alt="A session opened, one of its values clicked to copy it, then the whole row right-clicked" width="660">
<p><sub>Every session worst first, one of them opened up, and a value copied out of it</sub></p>
</div>

Hovering a row gives you a pencil, to rename it to something you will recognise,
and a close button that asks before ending the session. The eye in the header
blanks every name and path for screen-sharing.

<div align="center">
<img src="docs/screenshots/actions.gif" alt="A session's name underlined under the pointer, then a session renamed, then another one ended" width="660">
<p><sub>The name is the link to the session; rename one, or end one - the second click is the confirmation</sub></p>
</div>

## Plan usage

At the bottom, how much of your plan each account has used. Pick the limit each
one tracks - session, weekly, or a model-scoped one - behind the dots on its
row; the panel bar follows the account on screen. Hover a row to see when its
limit resets.

OMP's Claude logins get a row each, **OMP** or **OMP <profile>**. Their numbers
come from `omp usage`, so the widget never reads OMP's logins, and an account
you only use through OMP has a bar without Claude Code being signed in.

<div align="center">
<img src="docs/screenshots/usage.gif" alt="The usage footer opened to show both accounts, their bars sliding between readings and changing colour" width="660">
<p><sub>Both accounts at once, green to amber to red as the limit fills</sub></p>
</div>

## Install

Requires **Plasma 6**, `bash`, `jq`, `curl` and `timeout`. OMP's usage rows also
need a systemd user session, which is what keeps `omp` to its memory cap.

**From the KDE Store.** Right-click your panel → **Add or Manage Widgets…** →
**Get New Widgets** → **Download New Plasma Widgets**, search **Agent Session
Manager** and install it. The listing is at
[store.kde.org/p/2379987](https://store.kde.org/p/2379987/).

**From source.** `install.sh` checks for every requirement, plus
`kpackagetool6`, before it installs:

```sh
git clone https://github.com/Pedroou/agent-session-manager
cd agent-session-manager
./install.sh
```

Either way, add it with right-click on the panel → **Add or Manage Widgets…** →
search **Agent Session Manager**.

Upgrading while the widget is already on the panel needs a shell restart, since
Plasma caches applet QML. `install.sh` prints the command.

## Configuration

Right-click the widget → **Configure…**. Five pages, split by where each setting
takes effect:

- **General** - how often to check, the needs-attention highlight, the privacy
  toggle, and whether to show OMP sessions and OMP's plan usage. Plus one button
  that resets every page.
- **Panel** - the session count and its size, and the usage bar: whether to show
  it, how used the limit must be before it appears, and whether it colours by
  severity.
- **Popup** - how many sessions it shows before scrolling, which limit plan
  usage shows by default, which of the model, context bar and context
  percentage a row carries, which rows an expanded session has, and where the
  branch goes.
- **Accounts** - which config directories to watch.
- **Colours** - all six status colours.

### Accounts

On first run the widget looks once for accounts and lists what it finds, so the
common case needs no setup.

After that it is the **Accounts** page. **Search** looks one level down a
directory - your home, by default - for anything Claude Code has written to.
Results are marked **found** and only watched once you press **+**; a directory
you type in yourself goes straight in. Accounts can be renamed, switched off, or
removed, and nothing searches again unless you ask, so a removed account stays
removed.

## How it works

**Claude Code** already publishes most of this: every running session keeps a
record at `<config-dir>/sessions/<pid>.json` and rewrites it as its state
changes. The widget reads that, and works out the two states the record lacks:

- **Running** from the process tree: every Bash tool call is a child shell of
  the session, and its `cmdline` holds the command.
- **Error** from the transcript, whose last reply is marked as an API error,
  trusted only once the session has stopped.

Each record is checked against `/proc` - the process must exist and its start
time must match - because records outlive sessions that were killed, and pids
get reused. The same check guards ending a session or jumping to it.

**OMP** keeps no registry, so it goes the other way round: each `omp` process
holds its transcript open, and the end of that transcript says whether it is
working, running a command, asking you something, failed, or done.

The **model and context** line comes from the same transcripts: each reply
records its model and how many tokens its request carried, and the context
window follows from the model. **Jumping** walks up from the session's process to
the terminal that shows it, picks the tab through Konsole's D-Bus or the pane
through tmux, and has KWin raise the window.

Everything with a decision in it lives in two bash collectors, two jq programs
and two Qt-free JavaScript files, all tested without a running Plasma shell. The
collector suite runs the real scripts against a throwaway `$HOME`, `/proc` and
transcripts; it is written in fish, so running it needs fish - the widget does
not:

```fish
fish --no-config test/test-collectors.fish   # 140 assertions
node --test test/sessions.test.js            # 39
node --test test/usage.test.js               # 29
```

[`docs/design.md`](docs/design.md) is the full write-up - including what each
collector costs and how `omp` is kept in check - and
[`docs/limitations.md`](docs/limitations.md) is honest about what it cannot do.

## Privacy

**What leaves your machine.** Only the plan-usage bar. It asks Anthropic for your
limits using the login Claude Code already stores; the token goes to `curl`
through stdin rather than argv, so it never appears in the process list, and it
never reaches the widget's own code. For OMP's logins it runs `omp usage`, and
OMP makes the same request with its own credentials. Nothing else leaves the
machine, and the widget writes nothing to your Claude Code or OMP config
(`omp usage` keeps its own cache and refreshes its own tokens, as it does
whenever you run it). There is no server, no telemetry and nothing to sign up
for.

**About that endpoint.** It is the one Claude Code's own `/usage` view uses, and
it is undocumented. Anthropic's terms describe the OAuth login as being for
Claude Code and other Anthropic applications, and point developers building on
Claude at an API key instead. So this reads your own token on your own machine
for your own numbers, but it is not a use Anthropic has blessed, and the honest
expectation is that it stops working one day rather than that it keeps working
forever. See [Anthropic's legal and compliance
page](https://code.claude.com/docs/en/legal-and-compliance).

It is on by default because it is half of what the widget is for, and it is one
checkbox to turn off: **Configure… → Popup → Plan usage for each profile**, plus
**Panel → Plan Usage Bar** for the strip under the bars. OMP's rows have their
own: **General → Show plan usage for OMP's Claude logins**. The session list is
unaffected either way - that half reads nothing but your own filesystem.

## Licence

MIT - see [LICENSE](LICENSE).

<sub>Unofficial, and not affiliated with or endorsed by Anthropic. Claude and
Claude Code are trademarks of Anthropic, PBC.</sub>
