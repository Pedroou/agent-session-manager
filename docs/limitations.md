<!-- Kept out of the README on purpose: worth being straight about, but not
     what someone reading the front page is there for. -->

# Known limitations

- **Subagents look like thinking.** Bash calls are visible in the process tree;
  subagents run inside the process and leave no trace, so a session working
  through one reads as **Working** rather than **Running**.
- **No interrupt button.** Claude Code reads Ctrl+C as a byte off a raw-mode
  terminal, and its `SIGINT` handler calls the same `shutdown(0)` as `SIGTERM`.
  A signal can end a session but cannot pause one, so ending is all that is
  offered.
- **Linux only**, since it reads `/proc`. Which a Plasma panel rather implies.
- **Accounts are found, not watched.** The Accounts page searches when you ask
  it to, and never on its own - otherwise an account you removed from the list
  would come back by itself. A new one you create later is a search away, not
  automatic.
- **OMP's approval prompts look like the tool running.** OMP marks a tool as
  started before asking whether it may run, and the prompt itself is never
  written down - so a `bash` call waiting for your approval reads as
  **Running**, and any other tool waiting for it as **Working**. Only `ask`,
  whose question is the tool, reads as **Waiting**.
- **OMP has no Shell state.** Nothing it writes says the terminal has been
  handed to a shell; a `!` command typed at its prompt is recorded only once it
  has finished.
- **OMP sessions that never touched a terminal are found late.** A session is
  identified by the transcript it holds open, and OMP opens it only once the
  first reply lands. An interactive session is found before that through the
  breadcrumb OMP keeps per terminal - looked for under `~/.omp` only - but one
  run headless, or over RPC, appears with its first reply.
- **OMP's plan usage needs systemd.** `omp` is only ever run where a systemd
  user session can hold it to its memory cap; elsewhere its rows say they were
  not checked rather than run it unbounded. Profiles are looked for under
  `~/.omp/profiles` only, so an OMP relocated with `PI_CONFIG_DIR` or XDG paths
  shows its stock account but not its named ones.
- **Which OMP login a session is spending is not shown.** OMP can pool several
  Claude accounts and pick one per request, and its transcripts record only a
  hash of the account. The usage rows are per login, not per session.

None of these are oversights. Each is a place where the thing the widget wants to
know is not observable from outside the process, and guessing would have been
worse than saying so.
