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

None of these are oversights. Each is a place where the thing the widget wants to
know is not observable from outside the process, and guessing would have been
worse than saying so.
