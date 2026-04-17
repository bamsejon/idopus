# iDOpus

**A modern macOS file manager, ported from the legendary Directory Opus 5 Magellan (Amiga, 1995).**

iDOpus is a project to bring the classic dual-pane file manager experience from the Commodore Amiga to modern macOS on Apple Silicon. The original Directory Opus 5 Magellan was released as open source under the AROS Public License in 2012, and this project builds on that codebase.

## Status

**Early stage** — porting in progress. The Amiga-specific code (Intuition GUI, AmigaDOS, BOOPSI classes, 68K assembler fragments) needs to be replaced with macOS equivalents (AppKit/SwiftUI, POSIX/Foundation, Cocoa).

## Background

Directory Opus was *the* file manager on Amiga. First released in 1990 by Jonathan Potter / GP Software, it became the gold standard for file management — a dual-pane, fully customizable powerhouse that made the Amiga's Workbench feel primitive in comparison.

Version 5 ("Magellan") was the pinnacle: it could replace Workbench entirely, acting as a complete desktop environment with Lister windows, button banks, ARexx scripting, FTP integration, and a modular architecture.

Today, macOS still lacks a truly great dual-pane file manager in the spirit of DOpus. This project aims to change that.

## Origin

The source code is derived from [Directory Opus 5.82 Magellan](https://github.com/MrZammler/opus_magellan), released under the AROS Public License (APL v1.1, based on Mozilla Public License) by GP Software in 2012 via the [power2people.org](https://power2people.org/projects/dopus-magellan/) bounty program.

### Trademark notice

"Directory Opus" is a registered trademark of GP Software. The trademark is licensed for use on Amigoid platforms (AROS, AmigaOS, MorphOS) only. This macOS port uses the name **iDOpus** and is not affiliated with or endorsed by GP Software. The commercial [Directory Opus for Windows](https://www.gpsoft.com.au/) (currently v13) is a separate product.

## Architecture (planned)

| Amiga layer | macOS replacement |
|---|---|
| Intuition / BOOPSI GUI | AppKit (NSWindow, NSOutlineView, NSSplitView) |
| AmigaDOS / dos.library | POSIX / Foundation (NSFileManager) |
| Exec / message ports | GCD / NSOperationQueue |
| ARexx scripting | AppleScript / Shortcuts / Lua |
| IFF/ILBM icons | macOS native icons + UTI |
| 68K assembler fragments | Removed / rewritten in C or Swift |
| SAS/C 6 compiler | Clang / Xcode |

## Building

*Not yet buildable.* Porting work has not started. Watch this repo for progress.

## License

Source code is licensed under the **AROS Public License v1.1** (APL), based on the Mozilla Public License v1.1. See [LICENSE](LICENSE) for full text.

Original source copyright (c) GP Software / Jonathan Potter.
macOS port and modifications copyright (c) 2026 Jon Bylund.

## Contributing

This is an early-stage research project. If you're interested in helping port a 30-year-old Amiga file manager to macOS, you're exactly the right kind of person. Open an issue or PR.

## Credits

- **Jonathan Potter / GP Software** — original author of Directory Opus
- **MrZammler et al.** — maintaining the open source Amiga version
- **power2people.org** — funded the open source release in 2012
- **Claude Code** (AI agent) — assisting with the porting process
