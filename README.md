# iDOpus

**A modern macOS file manager, ported from the legendary Directory Opus 5 Magellan (Amiga, 1995).**

iDOpus brings the classic dual-pane file manager experience from the Commodore Amiga to modern macOS on Apple Silicon. The original Directory Opus 5 Magellan was released as open source under the AROS Public License in 2012, and this project builds on that codebase.

![iDOpus screenshot — two Listers with Button Bank between them](docs/screenshot.png)

## Status

**Working preview.** Dual-pane Listers with classic DOpus source/destination semantics, a Magellan-style Button Bank between them, and the full set of common file operations with per-item progress. See the current feature list below.

Still to come: file type actions, user-configurable Button Bank, built-in viewer, FTP, and the other DOpus modules.

## Features

### Listers
- Two tiled Listers side-by-side on launch (classic Magellan layout)
- Each Lister is SOURCE / DEST / OFF (mirrors `LISTERF_SOURCE` / `LISTERF_DEST`). Focusing a Lister promotes it to SOURCE; previous SOURCE demotes to DEST.
- Columns: Name, Size, Date, Type — click header to sort, click again to reverse
- `⌘N` new Lister · `⇧⌘N` Split Display (halves the current Lister and opens a second tiled alongside)
- Navigate: double-click folder, path field, ↑ (parent), ↻ (refresh), or Parent / Root buttons

### File operations
- `F5` Copy · `F6` Move (source selection → dest Lister's path)
- `F7` MakeDir · `F8` Delete (to Trash, with confirmation)
- `F3` Rename · `F9` Info (properties for 1 or N selected items)
- `⇧⌘F` Filter (Show/Hide glob + hide-dotfiles toggle)
- `⇧⌘A` Select By Pattern (`*.txt` etc.)
- Space — Quick Look preview (native macOS QL)
- Drag-and-drop between Listers (copy; Option = move) — and to/from Finder, Trash, the Dock
- Right-click any file for context menu (Open, Reveal in Finder, Info, Rename, Trash)

### Button Bank panel
- Magellan-style floating panel docked in the gap between the two Listers
- Buttons: Copy · Move · Delete · Rename · MakeDir · Info · Filter · Parent · Root · Refresh · All · None
- Non-activating: clicking a button does not steal focus from the SOURCE Lister
- `⌘B` toggle visibility

### Progress
- Long copy / move operations run on a background queue with a sheet on the source Lister showing *(N/M) filename*, Cancel / Esc aborts, affected Listers auto-refresh

## Download & install (macOS, Apple Silicon)

1. Grab the latest `.dmg` from [**Releases**](https://github.com/bamsejon/idopus/releases/latest).
2. Open the `.dmg` and drag **iDOpus.app** to **Applications**.
3. First launch: because the app is not code-signed, macOS will refuse to open it with a "unidentified developer" warning. **Right-click** iDOpus in Applications and choose **Open** — confirm once, and the app will open normally every time after that.
   Alternatively, from a terminal:
   ```
   xattr -dr com.apple.quarantine /Applications/iDOpus.app
   ```

Requires macOS 13 (Ventura) or later on Apple Silicon (M1/M2/M3/M4).

## Keyboard reference

| Key | Action |
|---|---|
| `F3` | Rename |
| `F5` | Copy (source → dest) |
| `F6` | Move (source → dest) |
| `F7` | MakeDir |
| `F8` | Delete (to Trash) |
| `F9` | Info |
| `Space` | Quick Look |
| `⌘N` | New Lister |
| `⇧⌘N` | Split Display |
| `⌘W` | Close Lister |
| `⌘B` | Show/Hide Button Bank |
| `⌘.` | Toggle hidden files |
| `⇧⌘F` | Filter… |
| `⇧⌘A` | Select By Pattern… |

Drag between Listers = copy; hold `⌥` (Option) while dragging = move.

## Background

Directory Opus was *the* file manager on Amiga. First released in 1990 by Jonathan Potter / GP Software, it became the gold standard for file management — a dual-pane, fully customizable powerhouse that made the Amiga's Workbench feel primitive in comparison.

Version 5 ("Magellan") was the pinnacle: it could replace Workbench entirely, acting as a complete desktop environment with Lister windows, button banks, ARexx scripting, FTP integration, and a modular architecture.

Today, macOS still lacks a truly great dual-pane file manager in the spirit of DOpus. This project aims to change that.

## Origin

The source code is derived from [Directory Opus 5.82 Magellan](https://github.com/MrZammler/opus_magellan), released under the AROS Public License (APL v1.1, based on Mozilla Public License) by GP Software in 2012 via the [power2people.org](https://power2people.org/projects/dopus-magellan/) bounty program.

### Trademark notice

"Directory Opus" is a registered trademark of GP Software. The trademark is licensed for use on Amigoid platforms (AROS, AmigaOS, MorphOS) only. This macOS port uses the name **iDOpus** and is not affiliated with or endorsed by GP Software. The commercial [Directory Opus for Windows](https://www.gpsoft.com.au/) (currently v13) is a separate product.

## Architecture

The project is a clean-room port guided by the original source in `original-amiga-source/` — Amiga subsystems are replaced by their macOS equivalents rather than emulated.

| Amiga layer | macOS replacement | Status |
|---|---|---|
| `exec.library` (memory, IPC, signals) | `malloc`/GCD/`pthread_mutex` via PAL | ✅ |
| `dos.library` (file I/O, paths, patterns) | POSIX + Foundation via PAL | ✅ |
| Intuition / BOOPSI GUI | AppKit (`NSWindow`, `NSTableView`) | ✅ core Lister |
| DOpus Lister + source/dest model | `ListerWindowController` state | ✅ |
| DOpus Button Bank | floating non-activating `NSPanel` | ✅ defaults, not yet user-editable |
| `graphics.library` rendering | CoreGraphics / AppKit drawing | ✅ (via NSTableView) |
| 68K assembler fragments | Removed / rewritten in C | N/A |
| SAS/C 6 compiler | Clang / Xcode | ✅ |
| FileTypes + actions | AppKit + NSWorkspace + Quick Look | ⏳ planned |
| ARexx scripting | AppleScript bridge / embedded Lua | ⏳ planned |
| Modules (FTP, viewer, …) | macOS bundles (`.bundle` + dlopen) | ⏳ planned |

See [docs/PORTING_ANALYSIS.md](docs/PORTING_ANALYSIS.md) for a deep analysis of the original codebase and the phased porting plan.

## Building from source

Requires Xcode Command Line Tools and CMake (3.20+).

```
cmake -S . -B build
cmake --build build
open build/iDOpus.app
```

Run the PAL and core test suites:

```
./build/pal_test
./build/core_test
```

Produce a distributable `.dmg` in `dist/`:

```
./scripts/package.sh
```

## License

Source code is licensed under the **AROS Public License v1.1** (APL), based on the Mozilla Public License v1.1. See [LICENSE](LICENSE) for full text.

Original source copyright (c) GP Software / Jonathan Potter.
macOS port and modifications copyright (c) 2026 Jon Bylund.

## Contributing

Early-stage port of a 30-year-old Amiga file manager to macOS. If that's your kind of project, pull requests and issues are very welcome.

## Credits

- **Jonathan Potter / GP Software** — original author of Directory Opus
- **MrZammler et al.** — maintaining the open source Amiga version
- **power2people.org** — funded the open source release in 2012
- **Claude Code** (AI agent) — assisting with the porting process
