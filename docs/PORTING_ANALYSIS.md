# iDOpus — Porting Analysis

## Source: Directory Opus 5.82 Magellan (Amiga, 1995)

**Target: Native macOS on Apple Silicon (ARM64)**

---

## 1. Codebase Overview

| Component | C Files | Lines | Purpose |
|-----------|---------|-------|---------|
| Program (main app) | 214 | ~107K | Core application, Listers, event loop, file ops |
| Library (dopus5.library) | 78 | ~40K | Shared support library, GUI toolkit, IPC |
| Modules (plugins) | 126 | ~80K | FTP, viewer, print, diskcopy, themes, etc. |
| Config (preferences) | 52 | ~31K | Configuration editor |
| FileTypeModule | 8 | ~3.5K | File type detection modules |
| NewRegModules | 5 | ~2.5K | Registration modules |
| Misc | 3 | ~1K | ViewFont utility |
| **Total C** | **486** | **~266K** | |
| Headers | 231 | ~41K | |
| Assembly (68K) | 12 | 987 | sprintf wrappers, bit ops, CPU measurement |
| **Grand Total** | **729 files** | **~308K lines** | |

---

## 2. Amiga API Dependencies

### 2.1 exec.library — Memory, IPC, Semaphores, Tasks

**251+ files, ~2,641 occurrences. Most pervasive dependency.**

- **Memory:** `AllocVec`/`FreeVec`, `AllocMem`/`FreeMem`, `AllocPooled`/`FreePooled` — ubiquitous
- **Message passing:** `CreateMsgPort`/`DeleteMsgPort`, `PutMsg`/`GetMsg`/`ReplyMsg`/`WaitPort` — the entire architecture is message-port based
- **Signals:** `Signal`/`Wait`/`SetSignal`/`AllocSignal`/`FreeSignal` — event loop and IPC
- **Tasks:** `FindTask`, `CreateNewProc` — multi-process architecture
- **Semaphores:** `ObtainSemaphore`/`ReleaseSemaphore`/`InitSemaphore` — 772 occurrences in 107 files
- **Atomic ops:** `Forbid`/`Permit` — 107+ files

**macOS replacement:** `malloc`/`free`, GCD dispatch queues, `pthread_mutex`/`os_unfair_lock`, `NSOperationQueue`

### 2.2 dos.library — File Operations

**330+ files, ~5,069 occurrences. Second most pervasive.**

- **File I/O:** `Open`/`Close`/`Read`/`Write`/`Seek`
- **Directory scanning:** `Lock`/`UnLock`/`Examine`/`ExNext` — 156 occurrences in 56 files
- **Path manipulation:** `FilePart`/`PathPart`/`AddPart`/`NameFromLock`/`ParentDir`/`CurrentDir`
- **Pattern matching:** `ParsePattern`/`MatchPattern` — 63 occurrences in 28 files
- **Process creation:** `CreateNewProc`/`SystemTagList` — 255 occurrences in 89 files
- **File attributes:** `SetProtection`/`SetComment`/`SetFileDate`/`DeleteFile`/`Rename`/`CreateDir`

**macOS replacement:** POSIX `open`/`read`/`write`/`opendir`/`readdir`/`stat`, Foundation `NSFileManager`

### 2.3 Intuition / BOOPSI — GUI

**120+ files, ~1,900 occurrences.**

- **Windows:** `OpenWindow`/`CloseWindow`/`ModifyIDCMP`/`ActivateWindow` — 310 occurrences
- **DOpus layout system:** `OpenConfigWindow`/`AddObjectList`/`SetGadgetValue`/`GetGadgetValue` — **1,173 occurrences in 61 files** (custom GUI abstraction)
- **BOOPSI OOP:** `NewObject`/`DisposeObject`/`SetAttrs`/`GetAttr`/`DoMethod` — 197 occurrences in 38 files
- **Menus:** `CreateMenus`/`LayoutMenus`/`FreeMenus` — 30 occurrences in 7 files

**6 custom BOOPSI widget classes:**
1. `button_class.c` — toolbar buttons (1,200+ lines)
2. `listview_class.c` — file list view (1,500+ lines)
3. `image_class.c` — icon/image rendering (1,000+ lines)
4. `palette_class.c` — color picker
5. `bitmap_class.c` — bitmap display
6. `string_class.c` — text input

**macOS replacement:** AppKit (`NSWindow`, `NSTableView`, `NSOutlineView`, `NSSplitView`, `NSToolbar`)

### 2.4 graphics.library — Rendering

**120 files, ~1,393 occurrences.**

- **Drawing:** `Move`/`Draw`/`SetAPen`/`SetBPen`/`RectFill`
- **Blitting:** `BltBitMap`/`BltBitMapRastPort`/`ScrollRaster`
- **Text:** `Text`/`TextLength`/`TextExtent`/`SetFont`

**macOS replacement:** CoreGraphics / AppKit drawing

### 2.5 Other Dependencies

| Library | Files | Occurrences | macOS replacement |
|---------|-------|-------------|-------------------|
| workbench/icon.library | 61 | 223 | macOS icons / UTI |
| ARexx (scripting) | 12 | dedicated subsystem | AppleScript / Lua |
| commodities.library | 2 | 7 | Global hotkey APIs |
| locale.library | 34 .cd files | pervasive | NSLocalizedString |
| GadTools | ~20 | ~100 | AppKit standard controls |
| ASL (file requesters) | ~10 | ~30 | NSOpenPanel / NSSavePanel |
| IFF parsing | 3 | dedicated | Custom or drop |
| Timer | 2 | dedicated | dispatch_after / NSTimer |
| Clipboard | 1 | dedicated | NSPasteboard |

### 2.6 SAS/C Compiler-Specific

**720 occurrences of `__asm`/`__saveds`/`__regargs` across 161 files.**

Register-based parameter passing for Amiga ABI. Not inline assembly — just calling conventions. All can be removed.

---

## 3. 68K Assembly — All Trivially Replaceable

| File | Lines | Purpose | Replacement |
|------|-------|---------|-------------|
| `*/lsprintf.asm` (x6) | 186 | sprintf via RawDoFmt + SwapMem | `snprintf` + trivial C |
| `Program/assembly.asm` | 328 | Line counting, tab removal, audio filter | C loops; drop audio filter |
| `Program/rotate.asm` | 35 | Bitmap rotation | C bit rotation |
| `Library/functions.asm` | 78 | RNG, BCPL strings, division | `rand()`, `strcpy`, `/` |
| `Library/anim_asm.asm` | 216 | Animation delta decoding | C byte operations |
| `Library/getusage.asm` | 123 | CPU usage measurement | `host_statistics()` |
| `Modules/subproc_a4.asm` | 15 | SAS/C data model glue | Not needed |
| **Total** | **987** | | **All drop-in replaceable** |

---

## 4. Core Architecture

### Startup Flow (`Program/main.c`)

16-phase initialization:
1. DOS/process setup
2. Verify DOPUS5: assignment
3. Open dopus5.library
4. Initialize locale
5. Check for duplicate instance
6. Open system libraries
7. Init GUI structures + memory pools
8. Load environment/settings
9. Parse command line
10. Display splash screen
11-15. Init desktop, ARexx, commands, filetypes, notifications, icons
16. Enter `event_loop()` (main event loop)

### Listers (File Panels)

The fundamental UI unit. Each Lister:
- Runs as its **own process** with dedicated message port
- Contains: directory buffer, window, scrollbars, path field, toolbar, status area
- Supports: text list mode, icon view, icon action mode
- Has source/destination semantics for dual-pane operations
- ~240-line struct definition, ~70+ command types
- Communication via IPC messages

### IPC System (`Library/ipc.c`)

Custom message-passing built on Amiga message ports:
- `IPC_Launch()` — spawn process with message port
- `IPC_Command()` — send sync/async commands
- **1,128 occurrences across 137 files** — this IS the application's backbone

### Module System

Dynamically loaded Amiga shared libraries (.module):
- Each module opens required system libs in `libinit.c`
- Communicates with main app via IPC
- Receives callback pointers to dopus5.library functions
- 23+ modules: FTP, print, viewer, diskcopy, format, themes, etc.

---

## 5. Reusability Assessment

### Reusable (~10-15%)

- Search algorithms (`Library/search.c`)
- Sort algorithms (`Program/buffers_sort.c`)
- String utilities (`Library/strings.c`)
- Config data structures (logic reusable, format must change from IFF to plist/JSON)
- File operation logic (copy/delete/rename — replace API calls, keep algorithms)
- Architectural patterns (Lister concept, module system, IPC design)

### Must Rewrite (~85-90%)

- **GUI** (~50% of codebase) — Intuition/BOOPSI/layout system → AppKit
- **File I/O** (~25%) — AmigaDOS → POSIX/Foundation
- **Rendering** (~10%) — RastPort → CoreGraphics
- **System integration** (~10%) — Workbench, Commodities, ARexx → macOS equivalents

---

## 6. Recommended Strategy

### GUI Framework: AppKit (Cocoa)

| Framework | Fit | Reasoning |
|-----------|-----|-----------|
| **AppKit** | Best | NSTableView/NSOutlineView = Listers, NSSplitView = dual-pane, NSToolbar, native drag-drop |
| SwiftUI | Poor | Immature for complex file managers, limited low-level control |
| SDL2 | Poor | No native widgets, must build everything from scratch |

### Phased Approach

| Phase | Scope | Estimate |
|-------|-------|----------|
| **1. Platform Abstraction** | Memory, lists, semaphores, IPC, file I/O, paths, strings, timers, localization | 3-4 months |
| **2. Core Logic** | Directory buffers, sorting, config (IFF→JSON), file type detection, search, file operations | 2-3 months |
| **3. GUI** | AppKit Lister windows, dual-pane, toolbar, menus, drag-drop, icon rendering | 6-8 months |
| **4. Modules** | Port FTP, text viewer, themes as native bundles; drop Amiga-only modules | 3-4 months |
| **5. Integration** | Scripting (AppleScript/Lua), global hotkeys, Dock, Finder services | 2-3 months |

### MVP Target

A **minimal viable product** (dual-pane file manager with copy/move/delete, toolbar, basic config):
- Estimated: **12-18 months** for one experienced developer
- With AI assistance: potentially faster on boilerplate/abstraction layers

### Priority Order

1. Platform abstraction layer (PAL)
2. Directory buffer + sorting
3. Single Lister window in AppKit
4. File operations (copy/move/delete)
5. Dual-pane mode
6. Configuration system
7. Toolbar and button banks
8. File type detection
9. Search
10. FTP module
11. Scripting interface
12. Advanced features (desktop, themes)

---

## 7. Key Architectural Decisions for macOS Port

| Decision | Amiga Original | Recommended macOS Approach |
|----------|---------------|---------------------------|
| Process model | Each Lister = separate process | Each Lister = GCD serial queue or NSOperation |
| IPC | Amiga message ports | GCD dispatch queues + blocks |
| GUI toolkit | Custom BOOPSI layout engine | AppKit with Auto Layout |
| Config format | IFF FORM | JSON or Property List |
| Scripting | ARexx | AppleScript bridge + embedded Lua |
| Icons | Amiga .info files (IFF/ILBM) | macOS native icons via NSWorkspace |
| File metadata | FileInfoBlock + protection bits | POSIX stat + extended attributes |
| Pattern matching | AmigaDOS #?-patterns | NSPredicate or POSIX fnmatch |
| Plugin format | Amiga shared library (.module) | macOS bundle (.bundle) with dlopen |
| Hotkeys | Commodities Exchange | CGEventTap or MASShortcut |

---

## 8. Conclusion

Directory Opus 5 Magellan is a brilliantly architected file manager whose **design patterns** (Lister-based browsing, message-driven IPC, modular plugins, declarative GUI definitions) are timeless and translate well to modern frameworks. However, the **implementation** is 85-90% Amiga-specific and must be rewritten.

The recommended approach: use the original source as a **living specification** — the definitive reference for behavior, features, and UX — while building the macOS implementation fresh in AppKit/Swift, guided by the original C code's architecture.

The assembly code (987 lines) is trivial. The real work is the GUI rewrite and the platform abstraction layer.
