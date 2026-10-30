# Changelog

Notable changes in each release, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/2.0.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.2.1] - 2026-10-26

### Fixed

- Long session names are cut short instead of pushing the status out of the popup.

## [1.2.0] - 2026-10-22

### Added

- The model, context bar and context percentage can each be turned off.

### Changed

- The context percentage starts off.

## [1.1.0] - 2026-10-20

### Added

- OMP sessions, behind a switch, and a usage bar for each of OMP's Claude logins.
- Clicking a session's name brings its terminal forward, on the right Konsole tab
  or tmux pane.
- Each session's model, and how full its context window is.
- Hovering an account's usage says when its limit resets.

### Changed

- The collectors run on bash, so the widget no longer needs fish.

### Fixed

- The usage strip no longer waits for a third session before it appears.

## [1.0.0] - 2026-09-24

### Added

- One bar per Claude Code session in the panel, coloured by what it's doing.
- A popup with every session, blocked ones first, and the details of each.
- Plan usage for each account.
- Any number of accounts, found on first run.

[1.2.1]: https://github.com/Pedroou/agent-session-manager/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/Pedroou/agent-session-manager/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/Pedroou/agent-session-manager/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Pedroou/agent-session-manager/releases/tag/v1.0.0
