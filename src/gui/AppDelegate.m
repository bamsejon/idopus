/*
 * iDOpus — GUI: Application Delegate
 *
 * Sets up the macOS app: main menu, initial window, buffer cache.
 */

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import <QuickLookThumbnailing/QuickLookThumbnailing.h>
#import <CoreServices/CoreServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#include <sys/socket.h>
#include <net/if.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <fcntl.h>
#include <netdb.h>
#include <errno.h>

/* Shorthand for NSLocalizedString with nil comment. Keys are the English
 * source strings; translations live in resources/<lang>.lproj/Localizable.strings
 * and are bundled into the .app/Contents/Resources/<lang>.lproj at build time. */
#define L(s) NSLocalizedString((s), nil)
#include <sys/stat.h>
#include <pwd.h>
#include <grp.h>
#include "core/dir_buffer.h"
#include "pal/pal_strings.h"
#include "pal/pal_file.h"

/* --- Lister state (mirrors original LISTERF_SOURCE/LISTERF_DEST) --- */

typedef NS_ENUM(NSInteger, ListerState) {
    ListerStateOff = 0,
    ListerStateSource,
    ListerStateDest,
};

/* Forward declarations */
@class ListerWindowController;
@class ButtonBankPanelController;
@class PreferencesWindowController;
@class IDOpusAppDelegate;

/* Forward interface for the rclone helper — implementation lives at the
 * bottom of the file. Listed here so ListerWindowController (defined above
 * the implementation) can call it during remote load. */
@interface IDOpusRclone : NSObject
+ (NSString *)binaryPath;
+ (void)obscurePassword:(NSString *)plaintext
             completion:(void (^)(NSString *obscured, NSError *err))completion;
+ (void)listRemote:(NSString *)remoteSpec
              path:(NSString *)remotePath
        completion:(void (^)(NSArray<NSDictionary *> *entries, NSError *err))completion;
+ (NSTask *)copyFromRemote:(NSString *)remoteSpec
                remotePath:(NSString *)remotePath
                   toLocal:(NSString *)localDir
                  progress:(void (^)(NSString *line))progress
                completion:(void (^)(int status))completion;
@end

/* Forward-declared remote UI classes — full implementations near the bottom
 * of the file. The @interface is declared here (not @class) so the AppDelegate
 * can read the `.window` property from NSWindowController. */
@interface ConnectDialogController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property (nonatomic, copy) void (^onConnect)(NSString *displayName,
                                               NSString *rcloneSpec,
                                               NSString *startPath);
@end

@interface RemoteBrowserWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithDisplayName:(NSString *)name
                           spec:(NSString *)spec
                           path:(NSString *)path
                    appDelegate:(IDOpusAppDelegate *)app;
@end

/* --- App Delegate --- */

@interface IDOpusAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (nonatomic) buffer_cache_t *bufferCache;
@property (nonatomic, strong) NSMutableArray<ListerWindowController *> *listerControllers;
@property (nonatomic, weak) ListerWindowController *activeSource;
@property (nonatomic, weak) ListerWindowController *activeDest;
@property (nonatomic, strong) ButtonBankPanelController *buttonBankPanel;
@property (nonatomic, strong) PreferencesWindowController *preferencesWindow;
@property (nonatomic, strong) NSMutableArray *remoteBrowsers;   /* active RemoteBrowser controllers */
@property (nonatomic, strong) ConnectDialogController *connectDialog;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSValue *> *lastListerFrames;
@property (nonatomic, assign) BOOL suppressSnap;
/* Snapshotted layout so the zoom button toggles: first click tiles full
 * screen, second click restores these frames. Nil = currently untiled. */
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSValue *> *preZoomFrames;

- (void)refreshAllListersShowing:(NSString *)path;
- (void)raiseAllListerWindowsExcept:(ListerWindowController *)primary;
- (void)listerDidMove:(ListerWindowController *)lw;
- (void)enforceBankBetweenListers;
- (void)snapshotListerFrames;
- (void)snapDestToBankRightEdge;
- (void)zoomToTileWorkspace;
- (void)showAlert:(NSString *)title info:(NSString *)info style:(NSAlertStyle)style;
- (void)performDropOntoLister:(ListerWindowController *)dest
                     fromURLs:(NSArray<NSURL *> *)urls
                       asMove:(BOOL)isMove;
- (NSString *)uniqueChild:(NSString *)name inDir:(NSString *)dir;
- (void)refreshButtonBankEnablement;
@end

@interface IDOpusAppDelegate ()
- (void)createMainMenu;
- (ListerWindowController *)newListerWindow:(NSString *)path frame:(NSRect)frame;
- (void)promoteToSource:(ListerWindowController *)ctrl;
- (void)listerClosing:(ListerWindowController *)ctrl;
- (void)showPreferencesAction:(id)sender;

/* Button Bank panel actions — operate on the active SOURCE lister */
- (void)parentAction:(id)sender;
- (void)rootAction:(id)sender;
- (void)refreshAction:(id)sender;
- (void)allAction:(id)sender;
- (void)noneAction:(id)sender;
- (void)infoAction:(id)sender;
- (void)filterAction:(id)sender;
- (void)toggleHidden:(id)sender;
- (void)toggleButtonBank:(id)sender;
- (void)selectPatternAction:(id)sender;
- (void)compareSourceWithDestAction:(id)sender;
- (void)goToPathAction:(id)sender;
- (void)runCustomButton:(NSButton *)sender;
- (void)addCustomButtonAction:(id)sender;
- (void)removeCustomButtonAction:(id)sender;
- (void)editCustomButtonAction:(id)sender;
- (void)addFileTypeActionAction:(id)sender;
- (void)manageFileTypeActionsAction:(id)sender;
- (NSArray<NSDictionary *> *)fileTypeActionsForExt:(NSString *)ext;
- (NSDictionary *)defaultFileTypeActionForExt:(NSString *)ext;
- (void)runFileTypeAction:(NSDictionary *)action onPath:(NSString *)path sourceLister:(ListerWindowController *)src;
- (void)syncSourceToDestAction:(id)sender;
- (void)addSyncProfileAction:(id)sender;
- (void)removeSyncProfileAction:(id)sender;
- (void)runSyncProfile:(NSMenuItem *)sender;
- (void)toggleQuickLook:(id)sender;
- (void)sortByAction:(NSMenuItem *)sender;
- (void)toggleReverseSortAction:(id)sender;
- (void)toggleFilesMixedAction:(id)sender;
- (void)toggleColumnVisibility:(NSMenuItem *)sender;
- (void)navigateToBookmark:(NSMenuItem *)sender;
- (void)addCurrentBookmark:(id)sender;
- (void)removeBookmark:(id)sender;
@end

#pragma mark - Lister Table Data

#pragma mark - Lister Table View

@protocol ListerTypeSearchDataSource <NSObject>
- (NSInteger)rowForNamePrefix:(NSString *)prefix;
@end

@protocol ListerKeyNavTarget <NSObject>
- (void)openSelectionAction:(id)sender;
- (void)goUp:(id)sender;
@end

/* NSTableView subclass with:
 *   - bare Space forwarded to toggleQuickLook: (macOS consumes Space inside
 *     the table otherwise, so View → Quick Look's bare-Space keyEquivalent
 *     never fires from within the table).
 *   - type-to-find: typing printable chars builds a prefix and jumps to the
 *     first matching row. Prefix resets after 500 ms of no typing, or Esc. */
@interface ListerTableView : NSTableView
@property (nonatomic, copy) NSString *typeSearchBuffer;
@property (nonatomic, assign) NSTimeInterval lastTypeTime;
@end

@implementation ListerTableView

- (void)keyDown:(NSEvent *)event {
    NSUInteger mods = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    NSString *chars = event.charactersIgnoringModifiers;

    /* Bare Space → Quick Look */
    if (mods == 0 && [chars isEqualToString:@" "]) {
        [NSApp sendAction:@selector(toggleQuickLook:) to:nil from:self];
        return;
    }
    /* Esc → clear type-to-find buffer */
    if (chars.length == 1 && [chars characterAtIndex:0] == 0x1B) {
        _typeSearchBuffer = nil;
        [super keyDown:event];
        return;
    }
    /* Enter / Return → open selected row */
    if (mods == 0 && chars.length == 1) {
        unichar c = [chars characterAtIndex:0];
        if (c == NSCarriageReturnCharacter || c == NSNewlineCharacter || c == NSEnterCharacter) {
            id target = [self findNavTarget];
            if ([target respondsToSelector:@selector(openSelectionAction:)]) {
                [target openSelectionAction:self];
                return;
            }
        }
        /* Backspace / Delete → parent directory (only when search buffer empty) */
        if ((c == NSBackspaceCharacter || c == NSDeleteCharacter || c == 0x7F)
            && (_typeSearchBuffer.length == 0
                || [NSDate timeIntervalSinceReferenceDate] - _lastTypeTime > 0.5)) {
            id target = [self findNavTarget];
            if ([target respondsToSelector:@selector(goUp:)]) {
                [target goUp:self];
                return;
            }
        }
    }

    /* Type-to-find: single printable character, no Cmd/Ctrl */
    BOOL hasCmdOrCtrl = (mods & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) != 0;
    if (!hasCmdOrCtrl && chars.length == 1) {
        unichar c = [chars characterAtIndex:0];
        if (c >= 0x20 && c < 0x7F) {
            NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
            if (!_typeSearchBuffer || now - _lastTypeTime > 0.5) {
                _typeSearchBuffer = [chars lowercaseString];
            } else {
                _typeSearchBuffer = [_typeSearchBuffer stringByAppendingString:[chars lowercaseString]];
            }
            _lastTypeTime = now;
            [self selectByTypePrefix:_typeSearchBuffer];
            return;
        }
    }

    [super keyDown:event];
}

/* Walk up responder chain to find the ListerWindowController (which owns
 * openSelectionAction: and goUp:). Keeps ListerTableView ignorant of the
 * concrete class that sits above it. */
- (id<ListerKeyNavTarget>)findNavTarget {
    NSResponder *r = self.nextResponder;
    while (r) {
        if ([r respondsToSelector:@selector(openSelectionAction:)] &&
            [r respondsToSelector:@selector(goUp:)]) {
            return (id)r;
        }
        r = r.nextResponder;
    }
    return nil;
}

- (void)selectByTypePrefix:(NSString *)prefix {
    if (prefix.length == 0) return;
    id<ListerTypeSearchDataSource> ds = (id)self.dataSource;
    if (![ds respondsToSelector:@selector(rowForNamePrefix:)]) return;
    NSInteger row = [ds rowForNamePrefix:prefix];
    if (row < 0) return;
    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [self scrollRowToVisible:row];
}

@end

#pragma mark - Lister Window Controller (interface)

@class ListerDataSource;

/* Trampoline used by the rsync dialog's three buttons to stop a modal run
 * with distinct codes. Kept lightweight so dialogs don't need their own
 * controller class. */
@interface IDOpusDialogHandler : NSObject
@end
@implementation IDOpusDialogHandler
- (IBAction)stopCancel:(id)s { [NSApp stopModalWithCode:0]; }
- (IBAction)stopRun:(id)s    { [NSApp stopModalWithCode:1]; }
- (IBAction)stopSave:(id)s   { [NSApp stopModalWithCode:2]; }
@end

/* NSPathControl subclass with a hover highlight so the breadcrumb actually
 * looks clickable. Uses an NSTrackingArea to toggle a subtle background tint
 * when the pointer is inside, and sets a pointing-hand cursor. */
@interface HoverPathControl : NSPathControl
@end

@implementation HoverPathControl {
    NSTrackingArea *_trackingArea;
}
- (instancetype)initWithFrame:(NSRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 4;
    self.toolTip = NSLocalizedString(@"Click any segment to jump there", nil);
    return self;
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
        options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect | NSTrackingCursorUpdate)
        owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}
- (void)mouseEntered:(NSEvent *)e {
    self.layer.backgroundColor = [NSColor.selectedControlColor colorWithAlphaComponent:0.18].CGColor;
}
- (void)mouseExited:(NSEvent *)e {
    self.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
}
- (void)cursorUpdate:(NSEvent *)e {
    [[NSCursor pointingHandCursor] set];
}
@end

/* Forward-declared: used inside ListerWindowController before its own
 * @implementation. Full @interface + @implementation follow below. */
@interface ProgressSheetController : NSObject
@property (nonatomic, strong) NSView *rowView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *fileLabel;
@property (nonatomic, strong) NSTextField *statsLabel;     /* "381 MB of 6.5 GB — 11.5 MB/s — 9 min" */
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSButton *disclosureButton;
@property (nonatomic, strong) NSView *detailsView;
@property (nonatomic, strong) NSLayoutConstraint *detailsHeightConstraint;
/* Value fields inside the details panel — caller sets meta (server/from/to)
 * once; progress-callback updates the dynamic ones. */
@property (nonatomic, strong) NSTextField *detailServer;
@property (nonatomic, strong) NSTextField *detailFrom;
@property (nonatomic, strong) NSTextField *detailTo;
@property (nonatomic, strong) NSTextField *detailTransferred;
@property (nonatomic, strong) NSTextField *detailSpeed;
@property (nonatomic, strong) NSTextField *detailRemaining;
@property (nonatomic, strong) NSTextField *detailElapsed;
@property (nonatomic, strong) NSTextField *detailError;
@property (nonatomic, strong) NSDate *startTime;
@property (atomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL detailsExpanded;
/* Optional: handler invoked by cancel: so jobs that don't use runOperation:
 * (rclone-backed downloads, etc.) can terminate their own tasks. */
@property (nonatomic, copy) void (^cancelHandler)(void);
- (void)runOperation:(BOOL)isMove
               paths:(NSArray<NSString *> *)paths
               names:(NSArray<NSString *> *)names
              destDir:(NSString *)destDir
          sourceWindow:(NSWindow *)srcWin
           completion:(void (^)(NSArray<NSString *> *failed))completion;
@end

/* Shared panel that displays all in-flight file operations as rows. Replaces
 * per-Lister progress sheets so the Listers stay usable while copies run,
 * and multiple parallel jobs live in a single window instead of stacking up
 * as modal sheets across different Listers. */
@interface JobsPanelController : NSWindowController
@property (nonatomic, strong) NSStackView *stack;
+ (instancetype)shared;
- (void)addJobRow:(NSView *)row;
- (void)removeJobRow:(NSView *)row;
- (void)relayoutForExpandedRow;
@end

@interface ListerWindowController : NSWindowController <NSWindowDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate, NSMenuDelegate, NSSearchFieldDelegate>
@property (nonatomic, strong) ListerDataSource *dataSource;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSTextField *pathField;        /* edit mode */
@property (nonatomic, strong) NSPathControl *pathControl;    /* breadcrumb mode */
@property (nonatomic, strong) NSTextField *stateLabel;  /* SOURCE/DEST/OFF */
@property (nonatomic, strong) NSTextField *statusBar;   /* file/dir counts */
@property (nonatomic, strong) NSStackView *buttonBank;
@property (nonatomic, copy) NSString *currentPath;
@property (nonatomic, assign) ListerState state;
@property (nonatomic, weak) IDOpusAppDelegate *appDelegate;
@property (nonatomic, strong) NSMutableArray<NSString *> *history;
@property (nonatomic, assign) NSInteger historyIndex;
@property (nonatomic, assign) BOOL navigatingInHistory;
@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSButton *forwardButton;
@property (nonatomic, strong) NSSearchField *findField;
@property (nonatomic, strong) NSLayoutConstraint *findHeightConstraint;
@property (nonatomic, assign) FSEventStreamRef fsStream;
@property (nonatomic, strong) NSTextField *emptyStateLabel;
/* Remote mode: when set, the Lister's buffer is populated from rclone lsjson
 * instead of the local filesystem. currentPath is the remote path (not a
 * local one). FSEvents is skipped; pal_file operations are bypassed. */
@property (nonatomic, copy) NSString *remoteSpec;
@property (nonatomic, copy) NSString *remoteLabel;
- (void)loadRemotePath:(NSString *)path;
- (BOOL)isRemote;
- (void)setState:(ListerState)state;
- (void)goBack:(id)sender;
- (void)goForward:(id)sender;
- (void)performFindPanelAction:(id)sender;
- (void)findCancelAction:(id)sender;
- (NSArray<NSString *> *)selectedPaths;
- (NSArray<NSString *> *)selectedNames;
- (void)reloadBuffer;
- (void)updateStatusBar;
- (BOOL)startInlineRenameIfSingleSelection;
@end

#pragma mark - Lister Table Data

/* Wraps a dir_buffer_t for NSTableView display */
@interface ListerDataSource : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
@property (nonatomic) dir_buffer_t *buffer;
@property (nonatomic, assign) NSTableView *tableView;
@property (nonatomic, copy) void (^onColumnClick)(NSString *identifier);
@property (nonatomic, copy) NSString *showPattern;   /* nil = show all */
@property (nonatomic, copy) NSString *hidePattern;   /* nil = hide none */
@property (nonatomic, assign) BOOL hideDotfiles;     /* default YES */
@property (nonatomic, weak) ListerWindowController *owner;  /* for drag-drop access */
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSImage *> *iconCache;
@property (nonatomic, strong) NSCache<NSString *, NSImage *> *thumbnailCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *pendingThumbnails;
- (void)loadPath:(NSString *)path;
- (void)sortByColumn:(NSString *)identifier;
- (void)applyCurrentFilter;
- (NSInteger)rowForNamePrefix:(NSString *)prefix;
@end

@implementation ListerDataSource

- (instancetype)init {
    self = [super init];
    if (self) {
        _buffer = dir_buffer_create();
        NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
        _hideDotfiles = [u objectForKey:@"prefHideDotfilesDefault"]
                          ? [u boolForKey:@"prefHideDotfilesDefault"] : YES;
        _iconCache = [NSMutableDictionary dictionary];
        _thumbnailCache = [[NSCache alloc] init];
        _thumbnailCache.countLimit = 512;
        _pendingThumbnails = [NSMutableSet set];
    }
    return self;
}

- (NSImage *)iconForEntry:(dir_entry_t *)entry {
    if (!entry || !_owner) return nil;

    /* Remote Listers: there's no local file to inspect for an icon, so use
     * system-symbol folder for dirs and extension-derived icons for files.
     * Thumbnail generation is skipped entirely (QL has no way to preview a
     * remote file without downloading it first). */
    if (_owner.isRemote) {
        if (dir_entry_is_dir(entry)) {
            NSImage *c = _iconCache[@"__remote_dir__"];
            if (c) return c;
            NSImage *img = [NSImage imageWithSystemSymbolName:@"folder.fill"
                                        accessibilityDescription:nil];
            if (img) {
                img.size = NSMakeSize(16, 16);
                _iconCache[@"__remote_dir__"] = img;
            }
            return img;
        }
        const char *ext = pal_path_extension(entry->name);
        NSString *extKey = ext && *ext
            ? [@"remote." stringByAppendingString:[NSString stringWithUTF8String:ext]].lowercaseString
            : @"__remote_file__";
        NSImage *cached = _iconCache[extKey];
        if (cached) return cached;
        NSImage *img = nil;
        if (ext && *ext) {
            img = [[NSWorkspace sharedWorkspace]
                iconForContentType:[UTType typeWithFilenameExtension:
                                    [NSString stringWithUTF8String:ext]]];
        }
        if (!img) img = [NSImage imageWithSystemSymbolName:@"doc"
                                     accessibilityDescription:nil];
        if (img) {
            img.size = NSMakeSize(16, 16);
            _iconCache[extKey] = img;
        }
        return img;
    }

    /* Directories: single shared icon, cache by extension key */
    if (dir_entry_is_dir(entry)) {
        NSImage *c = _iconCache[@"__dir__"];
        if (c) return c;
        char full[4096];
        pal_path_join([_owner.currentPath fileSystemRepresentation],
                      entry->name, full, sizeof(full));
        NSImage *img = [[NSWorkspace sharedWorkspace] iconForFile:
                        [NSString stringWithUTF8String:full]];
        img.size = NSMakeSize(16, 16);
        if (img) _iconCache[@"__dir__"] = img;
        return img;
    }

    /* Files: build the full path once */
    char full[4096];
    pal_path_join([_owner.currentPath fileSystemRepresentation],
                  entry->name, full, sizeof(full));
    NSString *fullPath = [NSString stringWithUTF8String:full];

    /* Check thumbnail cache (per-file, high-resolution previews) */
    NSImage *thumb = [_thumbnailCache objectForKey:fullPath];
    if (thumb) return thumb;

    /* Kick off an async thumbnail request if we haven't already */
    if (![_pendingThumbnails containsObject:fullPath]) {
        [_pendingThumbnails addObject:fullPath];
        [self requestThumbnailForPath:fullPath];
    }

    /* Fallback: generic extension icon while the thumbnail renders */
    const char *ext = pal_path_extension(entry->name);
    NSString *extKey = ext && *ext
        ? [@"." stringByAppendingString:[NSString stringWithUTF8String:ext]].lowercaseString
        : @"__file__";
    NSImage *cached = _iconCache[extKey];
    if (cached) return cached;
    NSImage *img = [[NSWorkspace sharedWorkspace] iconForFile:fullPath];
    img.size = NSMakeSize(16, 16);
    if (img) _iconCache[extKey] = img;
    return img;
}

- (void)requestThumbnailForPath:(NSString *)fullPath {
    CGFloat scale = [NSScreen mainScreen].backingScaleFactor ?: 2.0;
    QLThumbnailGenerationRequest *req = [[QLThumbnailGenerationRequest alloc]
        initWithFileAtURL:[NSURL fileURLWithPath:fullPath]
                     size:CGSizeMake(18, 18)
                    scale:scale
      representationTypes:QLThumbnailGenerationRequestRepresentationTypeThumbnail];

    __weak typeof(self) weakSelf = self;
    [[QLThumbnailGenerator sharedGenerator] generateBestRepresentationForRequest:req
                                                              completionHandler:
      ^(QLThumbnailRepresentation *rep, NSError *err) {
        if (!rep || err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.pendingThumbnails removeObject:fullPath];
            });
            return;
        }
        NSImage *img = rep.NSImage;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) s = weakSelf;
            if (!s) return;
            [s.pendingThumbnails removeObject:fullPath];
            if (!img) return;
            [s.thumbnailCache setObject:img forKey:fullPath];
            /* Find and redraw the row for this path */
            [s reloadRowForPath:fullPath];
        });
    }];
}

- (void)reloadRowForPath:(NSString *)fullPath {
    if (!_buffer || !_owner) return;
    NSString *dir = _owner.currentPath;
    if (!dir) return;
    /* Derive the filename this thumbnail belongs to */
    if (![fullPath hasPrefix:dir]) return;
    NSString *name = fullPath.lastPathComponent;
    int total = _buffer->stats.total_entries;
    for (int i = 0; i < total; i++) {
        dir_entry_t *e = dir_buffer_get_entry(_buffer, i);
        if (!e || !e->name) continue;
        if (strcmp(e->name, [name UTF8String]) == 0) {
            [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)i]
                                  columnIndexes:[NSIndexSet indexSetWithIndex:0]];
            return;
        }
    }
}

- (void)dealloc {
    if (_buffer) dir_buffer_free(_buffer);
}

- (void)loadPath:(NSString *)path {
    if (!_buffer || !path) return;
    dir_buffer_read(_buffer, [path fileSystemRepresentation]);
    [self applyCurrentFilter];
    [_tableView reloadData];
}

- (void)applyCurrentFilter {
    if (!_buffer) return;
    dir_buffer_set_filter(_buffer,
                          _showPattern.length ? [_showPattern UTF8String] : NULL,
                          _hidePattern.length ? [_hidePattern UTF8String] : NULL,
                          _hideDotfiles);
    dir_buffer_apply_filter(_buffer);
    [_tableView reloadData];
}

- (NSInteger)rowForNamePrefix:(NSString *)prefix {
    if (!_buffer || prefix.length == 0) return -1;
    const char *cpre = [prefix UTF8String];
    size_t plen = strlen(cpre);
    int total = _buffer->stats.total_entries;
    for (int i = 0; i < total; i++) {
        dir_entry_t *e = dir_buffer_get_entry(_buffer, i);
        if (!e || !e->name) continue;
        if (strncasecmp(e->name, cpre, plen) == 0) return i;
    }
    return -1;
}

- (void)sortByColumn:(NSString *)identifier {
    if (!_buffer) return;
    sort_field_t field = SORT_NAME;
    if ([identifier isEqualToString:@"size"])       field = SORT_SIZE;
    else if ([identifier isEqualToString:@"date"])  field = SORT_DATE;
    else if ([identifier isEqualToString:@"type"])  field = SORT_EXTENSION;

    /* Toggle reverse if clicking same column */
    bool reverse = (_buffer->format.sort.field == field) ?
                   !(_buffer->format.sort.flags & SORTF_REVERSE) : false;

    dir_buffer_set_sort(_buffer, field, reverse, _buffer->format.sort.separation);
    [_tableView reloadData];
}

#pragma mark NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _buffer ? _buffer->stats.total_entries : 0;
}

#pragma mark NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView
    viewForTableColumn:(NSTableColumn *)tableColumn
                   row:(NSInteger)row {

    dir_entry_t *entry = _buffer ? dir_buffer_get_entry(_buffer, (int)row) : NULL;
    if (!entry) return nil;

    NSString *identifier = tableColumn.identifier;

    /* Build cell text */
    NSString *text = @"";

    if ([identifier isEqualToString:@"name"]) {
        text = [NSString stringWithUTF8String:entry->name ?: ""];
    }
    else if ([identifier isEqualToString:@"size"]) {
        if (dir_entry_is_dir(entry)) {
            text = @"<dir>";
        } else {
            char buf[32];
            pal_format_size(entry->size, buf, sizeof(buf));
            text = [NSString stringWithUTF8String:buf];
        }
    }
    else if ([identifier isEqualToString:@"date"]) {
        char buf[32];
        pal_format_date(entry->date_modified, buf, sizeof(buf));
        text = [NSString stringWithUTF8String:buf];
    }
    else if ([identifier isEqualToString:@"type"]) {
        const char *ext = pal_path_extension(entry->name);
        text = ext ? [NSString stringWithUTF8String:ext] : @"";
    }

    /* Build cell view with proper frame sizing */
    BOOL isNameColumn = [identifier isEqualToString:@"name"];
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:nil];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 20)];
        cell.identifier = identifier;

        CGFloat textLeft = 0;
        if (isNameColumn) {
            NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(2, 2, 18, 18)];
            iv.imageScaling = NSImageScaleProportionallyUpOrDown;
            iv.autoresizingMask = NSViewMaxXMargin;
            cell.imageView = iv;
            [cell addSubview:iv];
            textLeft = 24;
        }

        NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(textLeft, 0, cell.bounds.size.width - textLeft, 20)];
        tf.bordered = NO;
        tf.drawsBackground = NO;
        tf.editable = NO;
        tf.selectable = NO;
        tf.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
        tf.lineBreakMode = NSLineBreakByTruncatingTail;
        tf.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        cell.textField = tf;
        [cell addSubview:tf];
    }

    cell.textField.stringValue = text;
    if (isNameColumn) cell.imageView.image = [self iconForEntry:entry];

    /* Colour */
    if (dir_entry_is_selected(entry))
        cell.textField.textColor = [NSColor systemYellowColor];
    else if (dir_entry_is_dir(entry))
        cell.textField.textColor = [NSColor systemCyanColor];
    else
        cell.textField.textColor = [NSColor labelColor];

    return cell;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    return 22.0;
}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn {
    [self sortByColumn:tableColumn.identifier];
    if (_onColumnClick) _onColumnClick(tableColumn.identifier);
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [_owner updateStatusBar];
    [_owner.appDelegate refreshButtonBankEnablement];
}

/* Row tooltip — name, size, kind, modified date. Shown on hover. */
- (NSString *)tableView:(NSTableView *)tableView
         toolTipForCell:(NSCell *)cell
                   rect:(NSRectPointer)rect
            tableColumn:(NSTableColumn *)tc
                    row:(NSInteger)row
          mouseLocation:(NSPoint)mouseLocation {
    dir_entry_t *entry = _buffer ? dir_buffer_get_entry(_buffer, (int)row) : NULL;
    if (!entry || !entry->name) return nil;
    NSString *name = [NSString stringWithUTF8String:entry->name];
    NSString *sizeStr;
    if (dir_entry_is_dir(entry)) {
        sizeStr = NSLocalizedString(@"Folder", nil);
    } else {
        char buf[32];
        pal_format_size(entry->size, buf, sizeof(buf));
        sizeStr = [NSString stringWithUTF8String:buf];
    }
    char dateBuf[32];
    pal_format_date(entry->date_modified, dateBuf, sizeof(dateBuf));
    NSString *dateStr = [NSString stringWithUTF8String:dateBuf];
    const char *ext = pal_path_extension(entry->name);
    NSString *kind = ext && *ext ? [NSString stringWithUTF8String:ext] : @"";
    if (kind.length)
        return [NSString stringWithFormat:@"%@\n%@ · %@\n%@", name, sizeStr, kind, dateStr];
    return [NSString stringWithFormat:@"%@\n%@\n%@", name, sizeStr, dateStr];
}

#pragma mark NSTextFieldDelegate (inline rename)

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSTextField *tf = notification.object;
    if (!tf || !_owner) return;

    NSString *oldName = objc_getAssociatedObject(tf, "oldName");
    NSString *newName = [tf.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    /* Restore non-editable state either way so the next selection doesn't
     * accidentally enter edit mode. */
    tf.editable = NO;
    tf.drawsBackground = NO;
    tf.delegate = nil;
    objc_setAssociatedObject(tf, "oldName", nil, OBJC_ASSOCIATION_COPY);

    if (!oldName || [newName isEqualToString:oldName] || newName.length == 0) {
        tf.stringValue = oldName ?: @"";
        return;
    }

    NSString *fromPath = [_owner.currentPath stringByAppendingPathComponent:oldName];
    NSString *toPath   = [_owner.currentPath stringByAppendingPathComponent:newName];
    NSError *err = nil;
    if (![[NSFileManager defaultManager] moveItemAtPath:fromPath toPath:toPath error:&err]) {
        tf.stringValue = oldName;
        [_owner.appDelegate showAlert:@"Rename failed"
                                 info:err.localizedDescription
                                style:NSAlertStyleWarning];
        return;
    }
    [_owner.appDelegate refreshAllListersShowing:_owner.currentPath];
}

#pragma mark Drag-and-drop

/* Drag out: each row writes an NSURL for its file, so macOS and other apps
 * (Finder, Trash) can consume the drag naturally. */
- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView
             pasteboardWriterForRow:(NSInteger)row {
    dir_entry_t *e = dir_buffer_get_entry(_buffer, (int)row);
    if (!e || !e->name || !_owner) return nil;
    char full[4096];
    pal_path_join([_owner.currentPath fileSystemRepresentation],
                  e->name, full, sizeof(full));
    return [NSURL fileURLWithPath:[NSString stringWithUTF8String:full]];
}

/* Drop onto the table: always "drop on table" (not between rows) = drop into
 * this Lister's currentPath. Default = copy; Option held = move. */
- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)op {
    [tableView setDropRow:-1 dropOperation:NSTableViewDropOn];  /* always the whole table */

    /* Refuse drops from the same Lister (source == dest path). */
    NSArray<NSURL *> *urls = [info.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:nil];
    if (urls.count == 0) return NSDragOperationNone;
    NSString *firstParent = [urls.firstObject.path stringByDeletingLastPathComponent];
    if (_owner && [firstParent isEqualToString:_owner.currentPath]) {
        return NSDragOperationNone;
    }

    BOOL option = (info.draggingSourceOperationMask & NSDragOperationMove) &&
                  ([NSEvent modifierFlags] & NSEventModifierFlagOption);
    return option ? NSDragOperationMove : NSDragOperationCopy;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)op {
    if (!_owner) return NO;
    NSArray<NSURL *> *urls = [info.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:nil];
    if (urls.count == 0) return NO;
    BOOL isMove = ([NSEvent modifierFlags] & NSEventModifierFlagOption) != 0;
    [_owner.appDelegate performDropOntoLister:_owner fromURLs:urls asMove:isMove];
    return YES;
}

@end

#pragma mark - Lister Window Controller

@implementation ListerWindowController

- (instancetype)initWithPath:(NSString *)path frame:(NSRect)frame appDelegate:(IDOpusAppDelegate *)appDelegate {
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
                               NSWindowStyleMaskClosable |
                               NSWindowStyleMaskMiniaturizable |
                               NSWindowStyleMaskResizable;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                    styleMask:style
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    window.title = @"iDOpus";
    window.minSize = NSMakeSize(400, 300);
    /* Disable native macOS full-screen entirely. The green zoom button still
     * works (intercepted in windowShouldZoom:) but long-pressing it or
     * picking "Enter Full Screen" from the menu no longer lifts a single
     * Lister into its own space — that shatters the tiled workspace and
     * leaves the Button Bank in a broken state when coming back. Users who
     * want "fill the screen" use the zoom button, which tiles all three. */
    window.collectionBehavior |= NSWindowCollectionBehaviorFullScreenNone;
    /* Unique tabbingIdentifier so this Lister isn't auto-merged with sibling
     * Listers at startup (user may have "Prefer Tabs: Always" set). Explicit
     * New Tab still works via addTabbedWindow:. */
    window.tabbingIdentifier = [NSString stringWithFormat:@"idopus-lister-%p", (void *)window];

    self = [super initWithWindow:window];
    if (!self) return nil;

    _currentPath = path ?: NSHomeDirectory();
    _dataSource = [[ListerDataSource alloc] init];
    _appDelegate = appDelegate;
    _state = ListerStateOff;

    window.delegate = self;

    [self setupUI];
    [self loadPath:_currentPath];
    [self applyStateStyling];

    return self;
}

- (void)setupUI {
    NSView *content = self.window.contentView;
    content.wantsLayer = YES;

    /* Path field (edit mode — hidden by default, shown on double-click in control) */
    _pathField = [NSTextField textFieldWithString:_currentPath];
    _pathField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _pathField.translatesAutoresizingMaskIntoConstraints = NO;
    _pathField.target = self;
    _pathField.action = @selector(pathFieldAction:);
    _pathField.hidden = YES;
    [content addSubview:_pathField];

    /* Path control (breadcrumbs — default) */
    _pathControl = [[HoverPathControl alloc] init];
    _pathControl.URL = [NSURL fileURLWithPath:_currentPath];
    _pathControl.pathStyle = NSPathStyleStandard;
    _pathControl.backgroundColor = [NSColor controlBackgroundColor];
    _pathControl.target = self;
    _pathControl.action = @selector(pathControlAction:);
    _pathControl.doubleAction = @selector(pathControlDoubleClick:);
    _pathControl.translatesAutoresizingMaskIntoConstraints = NO;
    /* Don't let a long path push the window wider. NSPathControl otherwise
     * reports an intrinsic content size matching the full path, and autolayout
     * happily grows the window to fit. Low hugging + compression resistance
     * = it yields to the fixed window width and truncates its segments. */
    [_pathControl setContentHuggingPriority:NSLayoutPriorityDefaultLow
                            forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_pathControl setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1
                                            forOrientation:NSLayoutConstraintOrientationHorizontal];
    [content addSubview:_pathControl];

    /* Back / Forward (history) */
    _backButton = [NSButton buttonWithTitle:@"\u25C0" target:self action:@selector(goBack:)];
    _backButton.translatesAutoresizingMaskIntoConstraints = NO;
    _backButton.bezelStyle = NSBezelStyleAccessoryBarAction;
    _backButton.enabled = NO;
    [content addSubview:_backButton];

    _forwardButton = [NSButton buttonWithTitle:@"\u25B6" target:self action:@selector(goForward:)];
    _forwardButton.translatesAutoresizingMaskIntoConstraints = NO;
    _forwardButton.bezelStyle = NSBezelStyleAccessoryBarAction;
    _forwardButton.enabled = NO;
    [content addSubview:_forwardButton];

    /* Parent button (up-arrow) */
    NSButton *backBtn = [NSButton buttonWithTitle:@"\u2191" target:self action:@selector(goUp:)];
    backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    backBtn.bezelStyle = NSBezelStyleAccessoryBarAction;
    [content addSubview:backBtn];

    /* Refresh button */
    NSButton *refreshBtn = [NSButton buttonWithTitle:@"\u21BB" target:self action:@selector(refresh:)];
    refreshBtn.translatesAutoresizingMaskIntoConstraints = NO;
    refreshBtn.bezelStyle = NSBezelStyleAccessoryBarAction;
    [content addSubview:refreshBtn];

    /* Scroll view + table */
    NSScrollView *scrollView = [[NSScrollView alloc] init];
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = YES;
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;

    _tableView = [[ListerTableView alloc] init];
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.allowsMultipleSelection = YES;
    _tableView.doubleAction = @selector(tableDoubleClick:);
    _tableView.target = self;
    _tableView.style = NSTableViewStyleFullWidth;
    _tableView.autosaveName = @"iDOpus.ListerColumns";  /* shared across Listers */
    _tableView.autosaveTableColumns = YES;

    /* Columns */
    struct { NSString *ident; NSString *title; CGFloat width; CGFloat min; } cols[] = {
        { @"name", @"Name",   300, 150 },
        { @"size", @"Size",    80,  60 },
        { @"date", @"Date",   140, 100 },
        { @"type", @"Type",    60,  40 },
    };
    NSSet<NSString *> *hiddenCols = [NSSet setWithArray:
        ([[NSUserDefaults standardUserDefaults] arrayForKey:@"hiddenColumns"] ?: @[])];
    for (int i = 0; i < 4; i++) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:cols[i].ident];
        col.title = cols[i].title;
        col.width = cols[i].width;
        col.minWidth = cols[i].min;
        col.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:cols[i].ident ascending:YES];
        col.hidden = [hiddenCols containsObject:cols[i].ident];
        [_tableView addTableColumn:col];
    }

    _tableView.dataSource = _dataSource;
    _tableView.delegate = _dataSource;
    _dataSource.tableView = _tableView;
    _dataSource.owner = self;

    /* Right-click context menu — items route to appDelegate actions */
    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = self;    /* rebuild Open With / Actions / Extract dynamically per clicked row */
    [menu addItemWithTitle:L(@"Open")           action:@selector(openSelectionAction:) keyEquivalent:@""].target = self;
    NSMenuItem *actions = [menu addItemWithTitle:L(@"Actions") action:NULL keyEquivalent:@""];
    actions.submenu = [[NSMenu alloc] initWithTitle:L(@"Actions")];
    actions.tag = 2;  /* identify in menuNeedsUpdate */
    NSMenuItem *openWith = [menu addItemWithTitle:L(@"Open With") action:NULL keyEquivalent:@""];
    openWith.submenu = [[NSMenu alloc] initWithTitle:L(@"Open With")];
    openWith.tag = 3;  /* identify in menuNeedsUpdate */
    [menu addItemWithTitle:L(@"Reveal in Finder") action:@selector(revealInFinderAction:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:L(@"Open in Terminal") action:@selector(openInTerminalAction:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:L(@"Copy Path")       action:@selector(copyPathAction:) keyEquivalent:@""].target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:L(@"Copy to…")        action:@selector(copyToAction:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:L(@"Move to…")        action:@selector(moveToAction:) keyEquivalent:@""].target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:L(@"Duplicate")       action:@selector(duplicateAction:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:L(@"Compress")       action:@selector(compressAction:)  keyEquivalent:@""].target = self;
    NSMenuItem *extract = [menu addItemWithTitle:L(@"Extract") action:@selector(extractAction:) keyEquivalent:@""];
    extract.target = self;
    extract.tag = 1;  /* identify for menuNeedsUpdate */
    [menu addItem:[NSMenuItem separatorItem]];
    /* F-key hints — these keyEquivalents are DISPLAY-ONLY since context menus
     * are not part of the main menu hierarchy. The real key handling lives in
     * the Functions menu items. */
    unichar f3 = NSF3FunctionKey, f9 = NSF9FunctionKey, f8 = NSF8FunctionKey;
    NSMenuItem *infoItem = [menu addItemWithTitle:L(@"Info")    action:@selector(infoAction:)   keyEquivalent:[NSString stringWithCharacters:&f9 length:1]];
    infoItem.target = _appDelegate;
    infoItem.keyEquivalentModifierMask = 0;
    NSMenuItem *renameItem = [menu addItemWithTitle:L(@"Rename…") action:@selector(renameAction:) keyEquivalent:[NSString stringWithCharacters:&f3 length:1]];
    renameItem.target = _appDelegate;
    renameItem.keyEquivalentModifierMask = 0;
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *trashItem = [menu addItemWithTitle:L(@"Move to Trash") action:@selector(deleteAction:) keyEquivalent:[NSString stringWithCharacters:&f8 length:1]];
    trashItem.target = _appDelegate;
    trashItem.keyEquivalentModifierMask = 0;
    _tableView.menu = menu;

    /* Drag-and-drop — accept file URLs from anywhere (other Listers or Finder) */
    [_tableView registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    [_tableView setDraggingSourceOperationMask:NSDragOperationCopy | NSDragOperationMove
                                     forLocal:YES];
    [_tableView setDraggingSourceOperationMask:NSDragOperationCopy
                                     forLocal:NO];

    scrollView.documentView = _tableView;
    [content addSubview:scrollView];

    /* Empty-state overlay — shown when the table has zero entries. Appears
     * centered above the scroll view so the user gets a hint rather than an
     * empty grid of rows. Visibility toggled in updateStatusBar after reload. */
    _emptyStateLabel = [NSTextField wrappingLabelWithString:L(@"Empty folder")];
    _emptyStateLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    _emptyStateLabel.textColor = [NSColor tertiaryLabelColor];
    _emptyStateLabel.alignment = NSTextAlignmentCenter;
    _emptyStateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyStateLabel.hidden = YES;
    [content addSubview:_emptyStateLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateLabel.centerXAnchor constraintEqualToAnchor:scrollView.centerXAnchor],
        [_emptyStateLabel.centerYAnchor constraintEqualToAnchor:scrollView.centerYAnchor],
        [_emptyStateLabel.widthAnchor   constraintLessThanOrEqualToConstant:320],
    ]];

    /* Button bank (DOpus-style row of text buttons between path field and file list) */
    NSStackView *bank = [[NSStackView alloc] init];
    bank.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bank.spacing = 4;
    bank.translatesAutoresizingMaskIntoConstraints = NO;
    bank.distribution = NSStackViewDistributionFill;

    struct { NSString *title; SEL action; id target; } btns[] = {
        { L(@"Copy"),    @selector(copyAction:),    _appDelegate },
        { L(@"Move"),    @selector(moveAction:),    _appDelegate },
        { L(@"Delete"),  @selector(deleteAction:),  _appDelegate },
        { L(@"Rename"),  @selector(renameAction:),  _appDelegate },
        { L(@"MakeDir"), @selector(makeDirAction:), _appDelegate },
        { L(@"Info"),    @selector(infoAction:),    _appDelegate },
        { L(@"Filter"),  @selector(filterAction:),  _appDelegate },
        { @"",           NULL, nil },  /* separator */
        { L(@"Parent"),  @selector(goUp:),          self },
        { L(@"Root"),    @selector(goRoot:),        self },
        { @"",           NULL, nil },
        { L(@"All"),     @selector(selectAllFiles:),   self },
        { L(@"None"),    @selector(deselectAllFiles:), self },
    };
    for (size_t i = 0; i < sizeof(btns)/sizeof(btns[0]); i++) {
        if (btns[i].title.length == 0) {
            /* Visual separator: fixed-width spacer view */
            NSView *sep = [[NSView alloc] init];
            sep.translatesAutoresizingMaskIntoConstraints = NO;
            [sep.widthAnchor constraintEqualToConstant:8].active = YES;
            [bank addArrangedSubview:sep];
            continue;
        }
        NSButton *b = [NSButton buttonWithTitle:btns[i].title target:btns[i].target action:btns[i].action];
        b.bezelStyle = NSBezelStyleRounded;
        b.controlSize = NSControlSizeSmall;
        b.font = [NSFont systemFontOfSize:11];
        [bank addArrangedSubview:b];
    }
    /* Flexible trailing spacer so buttons stay left-aligned */
    NSView *flex = [[NSView alloc] init];
    flex.translatesAutoresizingMaskIntoConstraints = NO;
    [flex setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [bank addArrangedSubview:flex];

    [content addSubview:bank];
    _buttonBank = bank;

    /* Find bar — hidden by default, slides in on ⌘F */
    _findField = [[NSSearchField alloc] init];
    _findField.translatesAutoresizingMaskIntoConstraints = NO;
    _findField.placeholderString = @"Find in this directory";
    _findField.target = self;
    _findField.action = @selector(findFieldChanged:);
    _findField.delegate = self;
    _findField.sendsSearchStringImmediately = YES;
    _findField.hidden = YES;
    _findField.alphaValue = 0;
    [content addSubview:_findField];

    /* State label (bottom-left: SOURCE/DEST/OFF — mirrors original status area) */
    _stateLabel = [NSTextField labelWithString:L(@"OFF")];
    _stateLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightBold];
    _stateLabel.alignment = NSTextAlignmentCenter;
    _stateLabel.drawsBackground = YES;
    _stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_stateLabel];

    /* Status bar (bottom: counts) */
    _statusBar = [NSTextField labelWithString:@""];
    _statusBar.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _statusBar.textColor = [NSColor secondaryLabelColor];
    _statusBar.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_statusBar];

    /* Layout */
    [NSLayoutConstraint activateConstraints:@[
        [_backButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [_backButton.topAnchor constraintEqualToAnchor:content.topAnchor constant:8],
        [_backButton.widthAnchor constraintEqualToConstant:28],

        [_forwardButton.leadingAnchor constraintEqualToAnchor:_backButton.trailingAnchor constant:2],
        [_forwardButton.topAnchor constraintEqualToAnchor:content.topAnchor constant:8],
        [_forwardButton.widthAnchor constraintEqualToConstant:28],

        [backBtn.leadingAnchor constraintEqualToAnchor:_forwardButton.trailingAnchor constant:8],
        [backBtn.topAnchor constraintEqualToAnchor:content.topAnchor constant:8],
        [backBtn.widthAnchor constraintEqualToConstant:32],

        [refreshBtn.leadingAnchor constraintEqualToAnchor:backBtn.trailingAnchor constant:4],
        [refreshBtn.topAnchor constraintEqualToAnchor:content.topAnchor constant:8],
        [refreshBtn.widthAnchor constraintEqualToConstant:32],

        [_pathControl.leadingAnchor constraintEqualToAnchor:refreshBtn.trailingAnchor constant:8],
        [_pathControl.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        [_pathControl.centerYAnchor constraintEqualToAnchor:backBtn.centerYAnchor],

        [_pathField.leadingAnchor constraintEqualToAnchor:_pathControl.leadingAnchor],
        [_pathField.trailingAnchor constraintEqualToAnchor:_pathControl.trailingAnchor],
        [_pathField.centerYAnchor constraintEqualToAnchor:_pathControl.centerYAnchor],

        [_buttonBank.topAnchor constraintEqualToAnchor:backBtn.bottomAnchor constant:6],
        [_buttonBank.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [_buttonBank.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],

        [_findField.topAnchor constraintEqualToAnchor:_buttonBank.bottomAnchor constant:4],
        [_findField.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [_findField.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        (_findHeightConstraint = [_findField.heightAnchor constraintEqualToConstant:0]),

        [scrollView.topAnchor constraintEqualToAnchor:_findField.bottomAnchor constant:4],
        [scrollView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:_statusBar.topAnchor constant:-4],

        [_stateLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:4],
        [_stateLabel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-4],
        [_stateLabel.widthAnchor constraintEqualToConstant:64],
        [_stateLabel.heightAnchor constraintEqualToConstant:20],

        [_statusBar.leadingAnchor constraintEqualToAnchor:_stateLabel.trailingAnchor constant:8],
        [_statusBar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        [_statusBar.centerYAnchor constraintEqualToAnchor:_stateLabel.centerYAnchor],
        [_statusBar.heightAnchor constraintEqualToConstant:18],
    ]];

    /* Column click callback to update status bar */
    __weak typeof(self) weakSelf = self;
    _dataSource.onColumnClick = ^(NSString *ident) {
        [weakSelf updateStatusBar];
    };
}

- (BOOL)isRemote { return _remoteSpec.length > 0; }

- (void)loadPath:(NSString *)path {
    if (self.isRemote) { [self loadRemotePath:path]; return; }
    _currentPath = path;
    _pathField.stringValue = path;
    _pathControl.URL = [NSURL fileURLWithPath:path];
    self.window.title = [NSString stringWithFormat:@"iDOpus — %@", path.lastPathComponent];
    [_dataSource loadPath:path];
    [self updateStatusBar];

    /* History: forward-truncate on new navigation, push current, unless
     * we got here by pressing Back/Forward. */
    if (!_history) _history = [NSMutableArray array];
    if (!_navigatingInHistory) {
        if (_historyIndex < (NSInteger)_history.count - 1) {
            [_history removeObjectsInRange:NSMakeRange(_historyIndex + 1, _history.count - _historyIndex - 1)];
        }
        if (_history.count == 0 || ![_history.lastObject isEqualToString:path]) {
            [_history addObject:path];
            _historyIndex = (NSInteger)_history.count - 1;
        }
    }
    [self updateHistoryButtons];
    [self startWatchingPath:path];
}

/* Load a remote path via rclone lsjson. Populates the dataSource buffer with
 * synthetic dir_entry_t records so the existing rendering / selection / sort
 * pipeline works unchanged. FSEvents and pal_file are bypassed. */
- (void)loadRemotePath:(NSString *)path {
    if (!path.length) path = @"/";
    _currentPath = path;
    _pathField.stringValue = path;
    self.window.title = [NSString stringWithFormat:@"%@ — %@", _remoteLabel ?: @"remote", path];
    /* Build custom breadcrumb items so the path bar shows "SMB host > share"
     * instead of NSPathControl's default "Macintosh SSD" resolution of a
     * bogus file URL. Root item gets a server icon; each subdirectory is a
     * folder icon. */
    [self applyRemotePathItems];
    [self updateStatusBar];

    if (!_history) _history = [NSMutableArray array];
    if (!_navigatingInHistory) {
        if (_historyIndex < (NSInteger)_history.count - 1) {
            [_history removeObjectsInRange:NSMakeRange(_historyIndex + 1, _history.count - _historyIndex - 1)];
        }
        if (_history.count == 0 || ![_history.lastObject isEqualToString:path]) {
            [_history addObject:path];
            _historyIndex = (NSInteger)_history.count - 1;
        }
    }
    [self updateHistoryButtons];
    [self stopWatching];   /* no FSEvents on remote */

    __weak typeof(self) weakSelf = self;
    [IDOpusRclone listRemote:_remoteSpec path:path completion:^(NSArray<NSDictionary *> *entries, NSError *err) {
        typeof(self) s = weakSelf; if (!s) return;
        dir_buffer_t *buf = s->_dataSource.buffer;
        if (!buf) return;
        if (err) {
            [s->_appDelegate showAlert:@"Remote"
                                   info:err.localizedDescription ?: @"listing failed"
                                  style:NSAlertStyleWarning];
            return;
        }
        dir_buffer_clear(buf);
        strncpy(buf->path, path.UTF8String, sizeof(buf->path) - 1);
        buf->path[sizeof(buf->path) - 1] = 0;
        buf->flags |= DBUF_VALID;
        buf->disk_free = 0;
        buf->disk_total = 0;

        NSISO8601DateFormatter *fmt = [[NSISO8601DateFormatter alloc] init];
        fmt.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                             NSISO8601DateFormatWithFractionalSeconds;
        for (NSDictionary *e in entries) {
            NSString *name = e[@"Name"];
            if (!name.length) continue;
            uint64_t size = [e[@"Size"] unsignedLongLongValue];
            BOOL isDir = [e[@"IsDir"] boolValue];
            NSDate *date = nil;
            if ([e[@"ModTime"] isKindOfClass:[NSString class]]) {
                date = [fmt dateFromString:e[@"ModTime"]];
                if (!date) {
                    /* rclone sometimes emits without fractional seconds */
                    NSISO8601DateFormatter *plain = [[NSISO8601DateFormatter alloc] init];
                    plain.formatOptions = NSISO8601DateFormatWithInternetDateTime;
                    date = [plain dateFromString:e[@"ModTime"]];
                }
            }
            time_t mtime = date ? (time_t)date.timeIntervalSince1970 : 0;
            dir_entry_t *de = dir_entry_create(name.UTF8String, size,
                                                isDir ? ENTRY_DIRECTORY : ENTRY_FILE,
                                                mtime, isDir ? 0755 : 0644);
            if (de) dir_buffer_add_entry(buf, de);
        }
        dir_buffer_apply_filter(buf);
        dir_buffer_sort(buf);
        dir_buffer_update_stats(buf);
        [s->_dataSource.tableView reloadData];
        [s updateStatusBar];
    }];
}

#pragma mark FSEvents auto-refresh

static void _listerFSEventCallback(ConstFSEventStreamRef stream,
                                    void *info,
                                    size_t numEvents,
                                    void *eventPaths,
                                    const FSEventStreamEventFlags flags[],
                                    const FSEventStreamEventId ids[]) {
    ListerWindowController *ctrl = (__bridge ListerWindowController *)info;
    [ctrl reloadBuffer];
}

- (void)startWatchingPath:(NSString *)path {
    [self stopWatching];
    if (!path) return;
    FSEventStreamContext ctx = {0, (__bridge void *)self, NULL, NULL, NULL};
    _fsStream = FSEventStreamCreate(NULL,
                                     &_listerFSEventCallback,
                                     &ctx,
                                     (__bridge CFArrayRef)@[path],
                                     kFSEventStreamEventIdSinceNow,
                                     0.5,   /* latency seconds — coalesces bursts */
                                     kFSEventStreamCreateFlagNone);
    if (_fsStream) {
        FSEventStreamSetDispatchQueue(_fsStream, dispatch_get_main_queue());
        FSEventStreamStart(_fsStream);
    }
}

- (void)stopWatching {
    if (!_fsStream) return;
    FSEventStreamStop(_fsStream);
    FSEventStreamInvalidate(_fsStream);
    FSEventStreamRelease(_fsStream);
    _fsStream = NULL;
}

- (void)dealloc {
    [self stopWatching];
}

- (void)updateHistoryButtons {
    _backButton.enabled    = _historyIndex > 0;
    _forwardButton.enabled = _historyIndex >= 0 && _historyIndex < (NSInteger)_history.count - 1;
}

#pragma mark Find

/* Cmd-F: show the search field and focus it. Cmd-F again / Esc closes.
 * The search uses the existing filter.showPattern = *<text>* so it plugs
 * straight into the dir_buffer filter machinery. */
- (void)performFindPanelAction:(id)sender {
    if (_findField.isHidden) [self showFindBar];
    else                      [self.window makeFirstResponder:_findField];
}

- (void)showFindBar {
    _findField.hidden = NO;
    _findHeightConstraint.constant = 22;
    _findField.alphaValue = 1;
    [self.window makeFirstResponder:_findField];
    _findField.stringValue = @"";
}

- (void)hideFindBar {
    _findField.hidden = YES;
    _findHeightConstraint.constant = 0;
    _findField.alphaValue = 0;
    _findField.stringValue = @"";
    _dataSource.showPattern = nil;
    [_dataSource applyCurrentFilter];
    [self updateStatusBar];
    [self.window makeFirstResponder:_tableView];
}

- (void)findCancelAction:(id)sender { [self hideFindBar]; }

- (void)findFieldChanged:(NSSearchField *)sender {
    NSString *q = [sender.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    _dataSource.showPattern = q.length ? [NSString stringWithFormat:@"*%@*", q] : nil;
    [_dataSource applyCurrentFilter];
    [self updateStatusBar];
}

/* Esc in the search field → close search */
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)sel {
    if (control == _findField && sel == @selector(cancelOperation:)) {
        [self hideFindBar];
        return YES;
    }
    return NO;
}

- (void)goBack:(id)sender {
    if (_historyIndex <= 0) return;
    _historyIndex--;
    _navigatingInHistory = YES;
    [self loadPath:_history[_historyIndex]];
    _navigatingInHistory = NO;
}

- (void)goForward:(id)sender {
    if (_historyIndex < 0 || _historyIndex >= (NSInteger)_history.count - 1) return;
    _historyIndex++;
    _navigatingInHistory = YES;
    [self loadPath:_history[_historyIndex]];
    _navigatingInHistory = NO;
}

- (void)updateStatusBar {
    dir_buffer_t *buf = _dataSource.buffer;
    if (!buf) return;
    char sizeStr[32];
    pal_format_size(buf->stats.total_bytes, sizeStr, sizeof(sizeStr));
    char freeStr[32];
    pal_format_size(buf->disk_free, freeStr, sizeof(freeStr));

    NSIndexSet *sel = _tableView.selectedRowIndexes;
    NSString *prefix = @"";
    if (sel.count > 0) {
        uint64_t selBytes = 0;
        NSUInteger idx = sel.firstIndex;
        while (idx != NSNotFound) {
            dir_entry_t *e = dir_buffer_get_entry(buf, (int)idx);
            if (e && !dir_entry_is_dir(e)) selBytes += (uint64_t)e->size;
            idx = [sel indexGreaterThanIndex:idx];
        }
        char selBuf[32]; pal_format_size(selBytes, selBuf, sizeof(selBuf));
        prefix = [NSString stringWithFormat:@"%lu selected (%s) | ",
                  (unsigned long)sel.count, selBuf];
    }
    _statusBar.stringValue = [NSString stringWithFormat:
        @"%@%d files, %d dirs (%s) — %s free",
        prefix, buf->stats.total_files, buf->stats.total_dirs, sizeStr, freeStr];

    /* Empty-state: different message when the directory is actually empty vs.
     * when a filter has hidden everything (the underlying directory contents
     * aren't tracked here, but the per-buffer filter suppresses non-matches). */
    BOOL empty = (buf->stats.total_entries == 0);
    _emptyStateLabel.hidden = !empty;
    if (empty) {
        NSString *filter = [[NSUserDefaults standardUserDefaults] stringForKey:@"filterShow"];
        BOOL hasFilter = filter.length > 0;
        _emptyStateLabel.stringValue = hasFilter
            ? L(@"No items match the filter.")
            : L(@"Empty folder");
    }
}

#pragma mark Actions

- (void)goUp:(id)sender {
    if (self.isRemote) {
        if ([_currentPath isEqualToString:@"/"] || _currentPath.length == 0) return;
        NSString *parent = [_currentPath stringByDeletingLastPathComponent];
        if (parent.length == 0) parent = @"/";
        [self loadPath:parent];
        return;
    }
    char parent[4096];
    pal_path_parent([_currentPath fileSystemRepresentation], parent, sizeof(parent));
    [self loadPath:[NSString stringWithUTF8String:parent]];
}

- (void)refresh:(id)sender {
    [self loadPath:_currentPath];
}

- (void)goRoot:(id)sender {
    if (self.isRemote) { [self loadPath:@"/"]; return; }
    /* Volume root — walk parents until parent == self (fs root) */
    NSString *p = _currentPath;
    while (YES) {
        NSString *parent = [p stringByDeletingLastPathComponent];
        if ([parent isEqualToString:p] || parent.length == 0) break;
        p = parent;
    }
    [self loadPath:p];
}

- (void)selectAllFiles:(id)sender {
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _tableView.numberOfRows)]
            byExtendingSelection:NO];
}

- (void)deselectAllFiles:(id)sender {
    [_tableView deselectAll:nil];
}

/* Open: double-click behavior for the clicked row (or every selected row). */
- (void)openSelectionAction:(id)sender {
    NSInteger row = _tableView.clickedRow >= 0
                    ? _tableView.clickedRow
                    : _tableView.selectedRow;
    if (row < 0) return;

    dir_entry_t *entry = dir_buffer_get_entry(_dataSource.buffer, (int)row);
    if (!entry) return;

    if (self.isRemote) {
        /* Remote: only navigation into directories for now. Opening remote
         * files would require downloading to a temp path; deferred to v1.7. */
        if (dir_entry_is_dir(entry)) {
            NSString *next = [_currentPath stringByAppendingPathComponent:
                               [NSString stringWithUTF8String:entry->name]];
            [self loadPath:next];
        }
        return;
    }
    char fullpath[4096];
    pal_path_join([_currentPath fileSystemRepresentation],
                  entry->name, fullpath, sizeof(fullpath));
    NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:fullpath]];
    if (dir_entry_is_dir(entry)) {
        [self loadPath:url.path];
    } else {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

/* Rebuild Open With + Actions + Extract based on the right-clicked (or selected) row */
- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != _tableView.menu) return;
    NSMenuItem *openWithItem = nil;
    NSMenuItem *extractItem = nil;
    NSMenuItem *actionsItem = nil;
    for (NSMenuItem *it in menu.itemArray) {
        /* Match by tag — title is localized, so literal string comparison
         * would miss in any non-English locale. */
        if (it.tag == 1) extractItem = it;
        if (it.tag == 2) actionsItem = it;
        if (it.tag == 3) openWithItem = it;
    }

    NSString *path = [self pathForContextClick];

    /* Extract: visible only when the clicked file is a recognised archive */
    if (extractItem) {
        extractItem.hidden = !(path && [self pathIsArchive:path]);
    }

    /* Actions: populate with user-defined file type actions for this ext */
    if (actionsItem) {
        NSMenu *sub = actionsItem.submenu;
        [sub removeAllItems];
        NSString *ext = path.pathExtension;
        NSArray<NSDictionary *> *actions = ext.length
            ? [_appDelegate fileTypeActionsForExt:ext] : @[];
        actionsItem.hidden = actions.count == 0;
        for (NSDictionary *a in actions) {
            NSString *label = [a[@"default"] boolValue]
                ? [NSString stringWithFormat:@"%@ (default)", a[@"title"]] : a[@"title"];
            NSMenuItem *mi = [sub addItemWithTitle:label
                                            action:@selector(runFileTypeActionMenu:)
                                     keyEquivalent:@""];
            mi.target = self;
            mi.representedObject = @{ @"action": a, @"path": path };
        }
    }

    if (!openWithItem) return;
    NSMenu *sub = openWithItem.submenu;
    [sub removeAllItems];

    if (!path) {
        openWithItem.enabled = NO;
        return;
    }
    openWithItem.enabled = YES;

    NSURL *url = [NSURL fileURLWithPath:path];
    NSArray<NSURL *> *apps = [[NSWorkspace sharedWorkspace] URLsForApplicationsToOpenURL:url];
    NSURL *defaultApp = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:url];
    for (NSURL *app in apps) {
        NSString *name = [[NSFileManager defaultManager] displayNameAtPath:app.path];
        NSString *title = [app isEqual:defaultApp]
            ? [NSString stringWithFormat:@"%@ (default)", name] : name;
        NSMenuItem *it = [sub addItemWithTitle:title
                                        action:@selector(openWithAction:)
                                 keyEquivalent:@""];
        it.target = self;
        it.representedObject = @{ @"file": path, @"app": app };
        NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:app.path];
        icon.size = NSMakeSize(16, 16);
        it.image = icon;
    }
    if (apps.count > 0) [sub addItem:[NSMenuItem separatorItem]];
    NSMenuItem *other = [sub addItemWithTitle:@"Other…"
                                       action:@selector(openWithOtherAction:)
                                keyEquivalent:@""];
    other.target = self;
    other.representedObject = path;
}

- (void)runFileTypeActionMenu:(NSMenuItem *)sender {
    NSDictionary *d = sender.representedObject;
    NSDictionary *action = d[@"action"];
    NSString *path = d[@"path"];
    if (!action || !path) return;
    [_appDelegate runFileTypeAction:action onPath:path sourceLister:self];
}

- (NSString *)pathForContextClick {
    NSInteger row = _tableView.clickedRow >= 0 ? _tableView.clickedRow : _tableView.selectedRow;
    if (row < 0) return nil;
    dir_entry_t *e = dir_buffer_get_entry(_dataSource.buffer, (int)row);
    if (!e || !e->name) return nil;
    char full[4096];
    pal_path_join([_currentPath fileSystemRepresentation], e->name, full, sizeof(full));
    return [NSString stringWithUTF8String:full];
}

- (void)openWithAction:(NSMenuItem *)sender {
    NSDictionary *d = sender.representedObject;
    NSURL *fileURL = [NSURL fileURLWithPath:d[@"file"]];
    NSURL *appURL = d[@"app"];
    NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
    [[NSWorkspace sharedWorkspace] openURLs:@[fileURL]
                       withApplicationAtURL:appURL
                              configuration:cfg
                          completionHandler:nil];
}

/* Open a Terminal window at the clicked directory (or, if a file is clicked,
 * at its parent directory; or at the Lister's currentPath if nothing). */
- (void)openInTerminalAction:(id)sender {
    NSString *target = [self pathForContextClick];
    if (target) {
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:target isDirectory:&isDir];
        if (!isDir) target = [target stringByDeletingLastPathComponent];
    } else {
        target = _currentPath;
    }
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"];
    task.arguments = @[@"-a", @"Terminal", target];
    [task launchAndReturnError:nil];
}

- (void)copyPathAction:(id)sender {
    NSArray<NSString *> *paths = [self selectedPaths];
    if (paths.count == 0) {
        NSString *clickPath = [self pathForContextClick];
        if (!clickPath) return;
        paths = @[clickPath];
    }
    NSString *joined = [paths componentsJoinedByString:@"\n"];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:joined forType:NSPasteboardTypeString];
}

- (void)copyToAction:(id)sender { [self copyOrMoveToDialog:NO]; }
- (void)moveToAction:(id)sender { [self copyOrMoveToDialog:YES]; }

/* Prompt for a destination directory via NSOpenPanel, then copy/move the
 * current selection there. Works without a second Lister open. */
- (void)copyOrMoveToDialog:(BOOL)isMove {
    NSArray<NSString *> *paths = [self selectedPaths];
    if (paths.count == 0) {
        NSString *clickPath = [self pathForContextClick];
        if (clickPath) paths = @[clickPath];
    }
    if (paths.count == 0) return;

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.canCreateDirectories = YES;
    panel.prompt = isMove ? @"Move Here" : @"Copy Here";
    panel.message = isMove
        ? [NSString stringWithFormat:@"Choose destination to move %lu item%@ to",
           (unsigned long)paths.count, paths.count == 1 ? @"" : @"s"]
        : [NSString stringWithFormat:@"Choose destination to copy %lu item%@ to",
           (unsigned long)paths.count, paths.count == 1 ? @"" : @"s"];
    panel.directoryURL = [NSURL fileURLWithPath:_currentPath];

    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    if ([panel.URL.path isEqualToString:_currentPath]) {
        [self.appDelegate showAlert:isMove ? @"Move to…" : @"Copy to…"
                               info:@"Source and destination are the same directory."
                              style:NSAlertStyleInformational];
        return;
    }

    /* Build URL array so we can reuse performDropOntoLister: — it already
     * wires ProgressSheetController + source/dest refresh + conflict prompts. */
    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:paths.count];
    for (NSString *p in paths) [urls addObject:[NSURL fileURLWithPath:p]];

    /* Find any existing Lister at the destination (so it refreshes), else
     * synthesize a transient one just for the op's bookkeeping. */
    ListerWindowController *destLister = nil;
    for (ListerWindowController *lw in self.appDelegate.listerControllers) {
        if ([lw.currentPath isEqualToString:panel.URL.path]) { destLister = lw; break; }
    }

    if (destLister) {
        [self.appDelegate performDropOntoLister:destLister fromURLs:urls asMove:isMove];
    } else {
        /* Drop onto the source Lister — it's just used for the progress
         * sheet's parent window. The destination directory is the panel's
         * URL, not the lister's currentPath, so we inline the op here. */
        [self runToPanelOp:isMove urls:urls destDir:panel.URL.path];
    }
}

- (void)runToPanelOp:(BOOL)isMove urls:(NSArray<NSURL *> *)urls destDir:(NSString *)destDir {
    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:urls.count];
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:urls.count];
    for (NSURL *u in urls) { [paths addObject:u.path]; [names addObject:u.lastPathComponent]; }

    IDOpusAppDelegate *app = self.appDelegate;
    NSString *sourceParent = [urls.firstObject.path stringByDeletingLastPathComponent];

    ProgressSheetController *sheet = [[ProgressSheetController alloc] init];
    __block ProgressSheetController *keepAlive = sheet;
    [sheet runOperation:isMove
                  paths:paths
                  names:names
                destDir:destDir
           sourceWindow:self.window
             completion:^(NSArray<NSString *> *failed) {
        [app refreshAllListersShowing:destDir];
        if (isMove) [app refreshAllListersShowing:sourceParent];
        if (failed.count > 0) {
            [app showAlert:isMove ? @"Some items could not be moved" : @"Some items could not be copied"
                      info:[failed componentsJoinedByString:@"\n"]
                     style:NSAlertStyleWarning];
        }
        keepAlive = nil;
    }];
}

- (void)duplicateAction:(id)sender {
    NSArray<NSString *> *paths = [self selectedPaths];
    NSArray<NSString *> *names = [self selectedNames];
    if (paths.count == 0) {
        NSString *click = [self pathForContextClick];
        if (!click) return;
        paths = @[click];
        names = @[click.lastPathComponent];
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *failed = [NSMutableArray array];
    for (NSUInteger i = 0; i < paths.count; i++) {
        NSString *from = paths[i];
        NSString *name = names[i];
        NSString *base = [name stringByDeletingPathExtension];
        NSString *ext = name.pathExtension;
        NSString *newName = ext.length
            ? [NSString stringWithFormat:@"%@ copy.%@", base, ext]
            : [NSString stringWithFormat:@"%@ copy", base];
        NSString *to = [self.appDelegate uniqueChild:newName inDir:_currentPath];
        NSError *err = nil;
        if (![fm copyItemAtPath:from toPath:to error:&err]) {
            [failed addObject:[NSString stringWithFormat:@"%@: %@", name, err.localizedDescription]];
        }
    }
    [self.appDelegate refreshAllListersShowing:_currentPath];
    if (failed.count > 0) {
        [self.appDelegate showAlert:@"Some items could not be duplicated"
                               info:[failed componentsJoinedByString:@"\n"]
                              style:NSAlertStyleWarning];
    }
}

- (BOOL)pathIsArchive:(NSString *)path {
    NSString *lower = path.lowercaseString;
    return [lower hasSuffix:@".zip"] || [lower hasSuffix:@".tar"] ||
           [lower hasSuffix:@".tar.gz"] || [lower hasSuffix:@".tgz"] ||
           [lower hasSuffix:@".gz"];
}

/* Compress selected items to a single .zip next to them. Uses /usr/bin/ditto
 * which preserves macOS metadata and resource forks. */
- (void)compressAction:(id)sender {
    NSArray<NSString *> *paths = [self selectedPaths];
    NSArray<NSString *> *names = [self selectedNames];
    if (paths.count == 0) {
        NSString *clickPath = [self pathForContextClick];
        if (!clickPath) return;
        paths = @[clickPath];
        names = @[clickPath.lastPathComponent];
    }

    NSString *archiveName = paths.count == 1
        ? [NSString stringWithFormat:@"%@.zip", names[0]]
        : @"Archive.zip";
    NSString *dest = [_currentPath stringByAppendingPathComponent:archiveName];
    dest = [self uniqueDestinationPath:dest];

    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"-c", @"-k",
                            @"--sequesterRsrc", @"--keepParent", nil];
    for (NSString *p in paths) [args addObject:p];
    [args addObject:dest];

    __weak typeof(self) weakSelf = self;
    [self runTaskAsync:@"/usr/bin/ditto" args:args title:@"Compressing…"
            completion:^(int status, NSString *stderrOut) {
        typeof(self) s = weakSelf; if (!s) return;
        if (status == 0) [s.appDelegate refreshAllListersShowing:s.currentPath];
        else [s.appDelegate showAlert:@"Compress failed"
                                 info:stderrOut ?: @"ditto returned a non-zero status"
                                style:NSAlertStyleWarning];
    }];
}

- (void)extractAction:(id)sender {
    NSString *path = [self pathForContextClick];
    if (!path) {
        NSArray *sel = [self selectedPaths];
        if (sel.count == 1) path = sel.firstObject;
    }
    if (!path) return;

    NSString *base = [path.lastPathComponent stringByDeletingPathExtension];
    /* Handle .tar.gz → base loses .tar too */
    if ([base.pathExtension.lowercaseString isEqualToString:@"tar"]) {
        base = [base stringByDeletingPathExtension];
    }
    NSString *destDir = [_currentPath stringByAppendingPathComponent:base];
    destDir = [self uniqueDestinationPath:destDir];

    NSError *mkErr = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:destDir
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&mkErr]) {
        [self.appDelegate showAlert:@"Extract failed"
                               info:mkErr.localizedDescription
                              style:NSAlertStyleWarning];
        return;
    }

    NSString *launch;
    NSArray *args;
    NSString *lower = path.lowercaseString;
    if ([lower hasSuffix:@".zip"]) {
        launch = @"/usr/bin/ditto";
        args = @[@"-x", @"-k", path, destDir];
    } else if ([lower hasSuffix:@".tar.gz"] || [lower hasSuffix:@".tgz"]) {
        launch = @"/usr/bin/tar";
        args = @[@"-xzf", path, @"-C", destDir];
    } else if ([lower hasSuffix:@".tar"]) {
        launch = @"/usr/bin/tar";
        args = @[@"-xf", path, @"-C", destDir];
    } else if ([lower hasSuffix:@".gz"]) {
        launch = @"/usr/bin/gunzip";
        args = @[@"-k", path];   /* extracts next to original, keeps source */
        destDir = _currentPath;
    } else {
        [self.appDelegate showAlert:@"Extract" info:@"Unsupported archive format."
                              style:NSAlertStyleInformational];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self runTaskAsync:launch args:args title:@"Extracting…"
            completion:^(int status, NSString *stderrOut) {
        typeof(self) s = weakSelf; if (!s) return;
        if (status == 0) [s.appDelegate refreshAllListersShowing:s.currentPath];
        else [s.appDelegate showAlert:@"Extract failed"
                                 info:stderrOut ?: @"command returned a non-zero status"
                                style:NSAlertStyleWarning];
    }];
}

- (NSString *)uniqueDestinationPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return path;
    NSString *dir = [path stringByDeletingLastPathComponent];
    NSString *name = [path.lastPathComponent stringByDeletingPathExtension];
    NSString *ext = path.pathExtension;
    for (int i = 2; i < 1000; i++) {
        NSString *try = ext.length
            ? [NSString stringWithFormat:@"%@/%@ %d.%@", dir, name, i, ext]
            : [NSString stringWithFormat:@"%@/%@ %d",   dir, name, i];
        if (![fm fileExistsAtPath:try]) return try;
    }
    return path;
}

- (void)runTaskAsync:(NSString *)launchPath
                args:(NSArray<NSString *> *)args
               title:(NSString *)title
          completion:(void (^)(int status, NSString *stderr))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:launchPath];
        task.arguments = args;
        NSPipe *errPipe = [NSPipe pipe];
        task.standardError = errPipe;
        NSError *launchErr = nil;
        NSString *errOut = nil;
        int status = -1;
        if ([task launchAndReturnError:&launchErr]) {
            [task waitUntilExit];
            status = task.terminationStatus;
            NSData *d = [errPipe.fileHandleForReading readDataToEndOfFile];
            if (d.length) errOut = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        } else {
            errOut = launchErr.localizedDescription;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(status, errOut);
        });
    });
}

- (void)openWithOtherAction:(NSMenuItem *)sender {
    NSString *filePath = sender.representedObject;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.directoryURL = [NSURL fileURLWithPath:@"/Applications"];
    panel.allowedContentTypes = @[];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;
    panel.message = [NSString stringWithFormat:@"Choose an application to open %@", filePath.lastPathComponent];
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;

    NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
    [[NSWorkspace sharedWorkspace] openURLs:@[[NSURL fileURLWithPath:filePath]]
                       withApplicationAtURL:panel.URL
                              configuration:cfg
                          completionHandler:nil];
}

- (void)revealInFinderAction:(id)sender {
    NSArray<NSString *> *paths = [self selectedPaths];
    if (paths.count == 0) {
        /* Fall back to clicked row if context menu triggered without selection */
        NSInteger row = _tableView.clickedRow;
        if (row >= 0) {
            dir_entry_t *e = dir_buffer_get_entry(_dataSource.buffer, (int)row);
            if (e && e->name) {
                char full[4096];
                pal_path_join([_currentPath fileSystemRepresentation], e->name, full, sizeof(full));
                paths = @[[NSString stringWithUTF8String:full]];
            }
        }
    }
    if (paths.count == 0) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:_currentPath]];
        return;
    }
    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:paths.count];
    for (NSString *p in paths) [urls addObject:[NSURL fileURLWithPath:p]];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:urls];
}

#pragma mark Quick Look

- (BOOL)acceptsPreviewPanelControl:(QLPreviewPanel *)panel { return YES; }

- (void)beginPreviewPanelControl:(QLPreviewPanel *)panel {
    panel.dataSource = self;
    panel.delegate = self;
}

- (void)endPreviewPanelControl:(QLPreviewPanel *)panel {
    panel.dataSource = nil;
    panel.delegate = nil;
}

- (NSInteger)numberOfPreviewItemsInPreviewPanel:(QLPreviewPanel *)panel {
    return (NSInteger)[self selectedPaths].count;
}

- (id<QLPreviewItem>)previewPanel:(QLPreviewPanel *)panel previewItemAtIndex:(NSInteger)idx {
    NSArray<NSString *> *paths = [self selectedPaths];
    if (idx < 0 || idx >= (NSInteger)paths.count) return nil;
    return [NSURL fileURLWithPath:paths[idx]];
}

- (void)selectByPattern:(NSString *)pattern {
    if (!_dataSource.buffer || !pattern.length) return;
    NSMutableIndexSet *idx = [NSMutableIndexSet indexSet];
    int total = _dataSource.buffer->stats.total_entries;
    const char *cpat = [pattern UTF8String];
    for (int i = 0; i < total; i++) {
        dir_entry_t *e = dir_buffer_get_entry(_dataSource.buffer, i);
        if (!e || !e->name) continue;
        if (pal_path_match(cpat, e->name)) [idx addIndex:(NSUInteger)i];
    }
    [_tableView selectRowIndexes:idx byExtendingSelection:NO];
    if (idx.firstIndex != NSNotFound) {
        [_tableView scrollRowToVisible:(NSInteger)idx.firstIndex];
    }
}

/* Rebuild the breadcrumb path control for a remote Lister. First item is the
 * remote server labelled with its protocol (SFTP / SMB); subsequent items
 * are the path components. Clicks are routed via pathControlAction:. */
- (void)applyRemotePathItems {
    if (!self.isRemote) return;
    NSMutableArray<NSPathControlItem *> *items = [NSMutableArray array];

    NSString *proto = [_remoteSpec containsString:@":smb,"] ? @"SMB" : @"SFTP";
    NSPathControlItem *root = [[NSPathControlItem alloc] init];
    root.title = [NSString stringWithFormat:@"%@  %@", proto, _remoteLabel ?: @""];
    NSImage *serverIcon = [NSImage imageWithSystemSymbolName:@"server.rack"
                                        accessibilityDescription:nil];
    if (!serverIcon) serverIcon = [NSImage imageWithSystemSymbolName:@"network"
                                                accessibilityDescription:nil];
    root.image = serverIcon;
    [items addObject:root];

    NSImage *folderIcon = [NSImage imageWithSystemSymbolName:@"folder.fill"
                                        accessibilityDescription:nil];
    for (NSString *c in [_currentPath componentsSeparatedByString:@"/"]) {
        if (!c.length) continue;
        NSPathControlItem *it = [[NSPathControlItem alloc] init];
        it.title = c;
        it.image = folderIcon;
        [items addObject:it];
    }
    _pathControl.pathItems = items;
}

- (void)pathControlAction:(NSPathControl *)sender {
    NSPathControlItem *clicked = sender.clickedPathItem;
    if (!clicked) return;
    if (self.isRemote) {
        /* For remote Listers we render custom pathItems without file URLs.
         * Reconstruct the target path from the clicked item's index in the
         * array (item 0 = remote root = "/", then one segment per dir). */
        NSInteger idx = [sender.pathItems indexOfObject:clicked];
        if (idx == NSNotFound) return;
        if (idx == 0) { [self loadPath:@"/"]; return; }
        NSArray<NSString *> *comps = [_currentPath componentsSeparatedByString:@"/"];
        NSMutableArray<NSString *> *nonEmpty = [NSMutableArray array];
        for (NSString *c in comps) if (c.length) [nonEmpty addObject:c];
        if (idx > (NSInteger)nonEmpty.count) return;
        NSString *p = [@"/" stringByAppendingString:
            [[nonEmpty subarrayWithRange:NSMakeRange(0, idx)] componentsJoinedByString:@"/"]];
        [self loadPath:p];
        return;
    }
    if (clicked.URL) [self loadPath:clicked.URL.path];
}

/* Double-click anywhere on the path control (not a specific segment) → switch
 * to text-edit mode so the user can type an arbitrary path. */
- (void)pathControlDoubleClick:(NSPathControl *)sender {
    if (sender.clickedPathItem) return;   /* segment click, not bg */
    [self enterPathEditMode:self];
}

- (void)enterPathEditMode:(id)sender {
    _pathField.stringValue = _currentPath;
    _pathField.bezeled = YES;
    _pathField.drawsBackground = YES;
    _pathField.backgroundColor = [NSColor textBackgroundColor];
    _pathField.textColor = [NSColor labelColor];
    _pathField.hidden = NO;
    _pathControl.hidden = YES;
    /* Bring field on top of the (hidden) control so it's the visible/hit layer */
    [_pathField.superview addSubview:_pathField positioned:NSWindowAbove relativeTo:_pathControl];
    [self.window makeFirstResponder:_pathField];
    [_pathField selectText:nil];
}

- (void)exitPathEditMode {
    _pathField.hidden = YES;
    _pathControl.hidden = NO;
}

- (void)pathFieldAction:(NSTextField *)sender {
    NSString *path = [sender.stringValue stringByExpandingTildeInPath];
    [self exitPathEditMode];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path])
        [self loadPath:path];
}

#pragma mark State (SOURCE / DEST / OFF)

- (void)setState:(ListerState)state {
    if (_state == state) return;
    _state = state;
    [self applyStateStyling];
}

- (void)applyStateStyling {
    NSString *text;
    NSColor *fg, *bg, *borderColor;
    CGFloat borderWidth = 2.0;
    switch (_state) {
        case ListerStateSource:
            text = L(@"SOURCE");
            fg = [NSColor whiteColor];
            bg = [NSColor systemBlueColor];
            borderColor = [NSColor systemBlueColor];
            break;
        case ListerStateDest:
            text = L(@"DEST");
            fg = [NSColor whiteColor];
            bg = [NSColor systemOrangeColor];
            borderColor = [NSColor systemOrangeColor];
            break;
        case ListerStateOff:
        default:
            text = L(@"OFF");
            fg = [NSColor secondaryLabelColor];
            bg = [NSColor clearColor];
            borderColor = [NSColor clearColor];
            borderWidth = 0.0;
            break;
    }
    _stateLabel.stringValue = text;
    _stateLabel.textColor = fg;
    _stateLabel.backgroundColor = bg;

    /* Paint the content-view border to match — gives a clear at-a-glance signal
     * of which Lister is SOURCE vs DEST without having to read the corner tag. */
    NSView *cv = self.window.contentView;
    cv.wantsLayer = YES;
    cv.layer.borderWidth = borderWidth;
    cv.layer.borderColor = borderColor.CGColor;
}

#pragma mark NSWindowDelegate

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [_appDelegate promoteToSource:self];
    [_appDelegate raiseAllListerWindowsExcept:self];
}

- (void)windowDidMove:(NSNotification *)notification {
    [_appDelegate listerDidMove:self];
}

- (void)windowDidResize:(NSNotification *)notification {
    [_appDelegate enforceBankBetweenListers];
}

/* Intercept the standard zoom (green traffic-light button + "Zoom" menu
 * item). We don't want this single Lister to fill the screen on top of the
 * others — that looks chaotic. Instead, tile the whole workspace so all
 * three windows share the screen. Returning NO here cancels AppKit's own
 * zoom behaviour. */
- (BOOL)windowShouldZoom:(NSWindow *)window toFrame:(NSRect)newFrame {
    [_appDelegate zoomToTileWorkspace];
    return NO;
}

- (void)windowWillClose:(NSNotification *)notification {
    [_appDelegate listerClosing:self];
}

- (void)tableDoubleClick:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) return;
    dir_entry_t *entry = dir_buffer_get_entry(_dataSource.buffer, (int)row);
    if (!entry) return;

    if (dir_entry_is_dir(entry)) {
        char newpath[4096];
        pal_path_join([_currentPath fileSystemRepresentation],
                      entry->name, newpath, sizeof(newpath));
        [self loadPath:[NSString stringWithUTF8String:newpath]];
    } else {
        char fullpath[4096];
        pal_path_join([_currentPath fileSystemRepresentation],
                      entry->name, fullpath, sizeof(fullpath));
        NSString *path = [NSString stringWithUTF8String:fullpath];

        /* User-defined default action for this extension? */
        const char *ext = pal_path_extension(entry->name);
        if (ext && *ext) {
            NSDictionary *def = [_appDelegate defaultFileTypeActionForExt:
                                 [NSString stringWithUTF8String:ext]];
            if (def) {
                [_appDelegate runFileTypeAction:def onPath:path sourceLister:self];
                return;
            }
        }
        /* Fallback: macOS default app */
        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
    }
}

#pragma mark Selection + reload

- (NSArray<NSString *> *)selectedNames {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSIndexSet *rows = _tableView.selectedRowIndexes;
    [rows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        dir_entry_t *e = dir_buffer_get_entry(_dataSource.buffer, (int)row);
        if (e && e->name) [names addObject:[NSString stringWithUTF8String:e->name]];
    }];
    return names;
}

- (NSArray<NSString *> *)selectedPaths {
    NSArray<NSString *> *names = [self selectedNames];
    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:names.count];
    for (NSString *name in names) {
        char full[4096];
        pal_path_join([_currentPath fileSystemRepresentation],
                      [name fileSystemRepresentation], full, sizeof(full));
        [paths addObject:[NSString stringWithUTF8String:full]];
    }
    return paths;
}

- (void)reloadBuffer {
    /* Skip reload while the user is inline-renaming — the active field
     * editor would be destroyed when the table reloads its cells. The
     * rename commit (or cancel) triggers its own refresh afterwards. */
    NSResponder *fr = self.window.firstResponder;
    if ([fr isKindOfClass:[NSTextView class]]) {
        NSTextView *tv = (NSTextView *)fr;
        if ([tv isDescendantOf:_tableView]) return;
    }

    /* Preserve selection across reload. Without this, FSEvents firing for
     * unrelated changes (.DS_Store, Spotlight touches, etc.) would wipe the
     * user's marked items in the middle of an interaction. */
    NSArray<NSString *> *selectedNames = [self selectedNames];

    if (self.isRemote) {
        /* Re-fetch via rclone; selection restoration still works because the
         * completion handler runs asynchronously but the selection indexes
         * apply after reloadData (which happens inside loadRemotePath). */
        [self loadRemotePath:_currentPath];
        return;
    }
    [_dataSource loadPath:_currentPath];

    if (selectedNames.count > 0 && _dataSource.buffer) {
        NSMutableIndexSet *restored = [NSMutableIndexSet indexSet];
        NSSet<NSString *> *lookup = [NSSet setWithArray:selectedNames];
        int total = _dataSource.buffer->stats.total_entries;
        for (int i = 0; i < total; i++) {
            dir_entry_t *e = dir_buffer_get_entry(_dataSource.buffer, i);
            if (e && e->name && [lookup containsObject:[NSString stringWithUTF8String:e->name]]) {
                [restored addIndex:(NSUInteger)i];
            }
        }
        if (restored.count > 0) {
            [_tableView selectRowIndexes:restored byExtendingSelection:NO];
        }
    }

    [self updateStatusBar];
}

/* Start inline rename on the single selected row's name cell. Returns YES
 * if editing started, NO if multiple rows or nothing is selected (caller
 * falls back to the dialog-based rename). */
- (BOOL)startInlineRenameIfSingleSelection {
    if (_tableView.selectedRowIndexes.count != 1) return NO;
    NSInteger row = _tableView.selectedRow;
    if (row < 0) return NO;

    [_tableView scrollRowToVisible:row];
    NSTableCellView *cell = [_tableView viewAtColumn:0 row:row makeIfNecessary:YES];
    NSTextField *tf = cell.textField;
    if (!tf) return NO;

    /* Configure the text field for editing. Stash the old name + flag it as
     * being-renamed so controlTextDidEndEditing: knows to commit. */
    tf.editable = YES;
    tf.selectable = YES;
    tf.bezeled = YES;
    tf.drawsBackground = YES;
    tf.backgroundColor = [NSColor textBackgroundColor];
    tf.delegate = _dataSource;
    objc_setAssociatedObject(tf, "oldName", tf.stringValue, OBJC_ASSOCIATION_COPY);

    /* Make the window key if it isn't already, then focus the field and use
     * its field editor to pre-select the stem (everything before the last
     * dot). */
    [self.window makeKeyAndOrderFront:nil];
    if (![self.window makeFirstResponder:tf]) {
        /* Fallback — couldn't become first responder; let caller use the dialog */
        tf.editable = NO;
        tf.bezeled = NO;
        tf.drawsBackground = NO;
        tf.delegate = nil;
        objc_setAssociatedObject(tf, "oldName", nil, OBJC_ASSOCIATION_COPY);
        return NO;
    }

    NSText *editor = [self.window fieldEditor:YES forObject:tf];
    [editor setString:tf.stringValue];
    NSString *name = tf.stringValue;
    NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location != NSNotFound && dot.location > 0) {
        editor.selectedRange = NSMakeRange(0, dot.location);
    } else {
        editor.selectedRange = NSMakeRange(0, name.length);
    }
    return YES;
}

@end

#pragma mark - Progress Sheet (copy / move)

/* Modal sheet attached to the source Lister, shown during long copy/move
 * operations. Loop runs on a background queue; label and cancel button are
 * updated/checked on the main queue. @interface is declared above so
 * ListerWindowController can use it. */
@implementation ProgressSheetController

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    /* Mac-native file-operation row:
     *   filename (primary, bold)                              [X]
     *   ================  thin progress bar  ================
     *   381 MB of 6.5 GB — 11.5 MB/s — 9 min remaining       (tertiary)
     *
     * Matches the visual rhythm of AirDrop / Finder-copy sheets. */
    _rowView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 58)];
    _rowView.translatesAutoresizingMaskIntoConstraints = NO;

    _titleLabel = [NSTextField labelWithString:L(@"Copying…")];
    _titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    _titleLabel.textColor = [NSColor labelColor];
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_titleLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1
                                          forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_rowView addSubview:_titleLabel];

    /* fileLabel kept for legacy callers but hidden — stats go to statsLabel. */
    _fileLabel = [NSTextField labelWithString:@""];
    _fileLabel.hidden = YES;
    [_rowView addSubview:_fileLabel];

    _statsLabel = [NSTextField labelWithString:@""];
    _statsLabel.font = [NSFont systemFontOfSize:11];
    _statsLabel.textColor = [NSColor secondaryLabelColor];
    _statsLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _statsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_rowView addSubview:_statsLabel];

    _spinner = [[NSProgressIndicator alloc] init];
    _spinner.style = NSProgressIndicatorStyleBar;
    _spinner.indeterminate = YES;
    _spinner.controlSize = NSControlSizeSmall;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [_rowView addSubview:_spinner];

    /* Borderless X button, circular — matches macOS Notification/AirDrop close. */
    _cancelButton = [NSButton buttonWithImage:
        [NSImage imageWithSystemSymbolName:@"xmark.circle.fill"
                  accessibilityDescription:L(@"Cancel")]
                                      target:self
                                      action:@selector(cancel:)];
    _cancelButton.bezelStyle = NSBezelStyleInline;
    _cancelButton.bordered = NO;
    _cancelButton.imagePosition = NSImageOnly;
    _cancelButton.contentTintColor = [NSColor secondaryLabelColor];
    _cancelButton.toolTip = L(@"Cancel");
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_rowView addSubview:_cancelButton];

    /* Disclosure triangle on the left toggles the detail log. */
    _disclosureButton = [[NSButton alloc] init];
    _disclosureButton.bezelStyle = NSBezelStyleDisclosure;
    [_disclosureButton setButtonType:NSButtonTypePushOnPushOff];
    _disclosureButton.title = @"";
    _disclosureButton.state = NSControlStateValueOff;
    _disclosureButton.target = self;
    _disclosureButton.action = @selector(toggleDetails:);
    _disclosureButton.toolTip = L(@"Show transfer details");
    _disclosureButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_rowView addSubview:_disclosureButton];

    /* Structured detail panel — label:value rows, macOS-inspector style. */
    _detailsView = [[NSView alloc] init];
    _detailsView.translatesAutoresizingMaskIntoConstraints = NO;
    _detailsView.hidden = YES;
    _detailsView.wantsLayer = YES;
    _detailsView.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
    _detailsView.layer.cornerRadius = 6;
    [_rowView addSubview:_detailsView];

    _startTime = [NSDate date];
    [self _buildDetailFields];

    _detailsHeightConstraint = [_detailsView.heightAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        [_disclosureButton.leadingAnchor  constraintEqualToAnchor:_rowView.leadingAnchor constant:8],
        [_disclosureButton.centerYAnchor  constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [_disclosureButton.widthAnchor    constraintEqualToConstant:13],

        [_cancelButton.trailingAnchor  constraintEqualToAnchor:_rowView.trailingAnchor constant:-8],
        [_cancelButton.topAnchor       constraintEqualToAnchor:_rowView.topAnchor constant:6],
        [_cancelButton.widthAnchor     constraintEqualToConstant:18],
        [_cancelButton.heightAnchor    constraintEqualToConstant:18],

        [_titleLabel.leadingAnchor     constraintEqualToAnchor:_disclosureButton.trailingAnchor constant:6],
        [_titleLabel.trailingAnchor    constraintEqualToAnchor:_cancelButton.leadingAnchor constant:-8],
        [_titleLabel.topAnchor         constraintEqualToAnchor:_rowView.topAnchor constant:6],

        [_spinner.leadingAnchor        constraintEqualToAnchor:_rowView.leadingAnchor constant:12],
        [_spinner.trailingAnchor       constraintEqualToAnchor:_rowView.trailingAnchor constant:-12],
        [_spinner.topAnchor            constraintEqualToAnchor:_titleLabel.bottomAnchor constant:6],
        [_spinner.heightAnchor         constraintEqualToConstant:6],

        [_statsLabel.leadingAnchor     constraintEqualToAnchor:_rowView.leadingAnchor constant:12],
        [_statsLabel.trailingAnchor    constraintEqualToAnchor:_rowView.trailingAnchor constant:-12],
        [_statsLabel.topAnchor         constraintEqualToAnchor:_spinner.bottomAnchor constant:4],

        [_detailsView.leadingAnchor    constraintEqualToAnchor:_rowView.leadingAnchor constant:12],
        [_detailsView.trailingAnchor   constraintEqualToAnchor:_rowView.trailingAnchor constant:-12],
        [_detailsView.topAnchor        constraintEqualToAnchor:_statsLabel.bottomAnchor constant:6],
        [_detailsView.bottomAnchor     constraintEqualToAnchor:_rowView.bottomAnchor constant:-6],
        _detailsHeightConstraint,
    ]];

    return self;
}

/* Lay out the rows inside _detailsView as label:value pairs. Right-aligned
 * labels in the first column, values in the second — mirrors the macOS
 * Get Info / System Settings inspector style. */
- (void)_buildDetailFields {
    NSArray<NSString *> *labels = @[
        L(@"Server:"), L(@"From:"), L(@"To:"),
        L(@"Transferred:"), L(@"Speed:"),
        L(@"Remaining:"), L(@"Elapsed:"), L(@"Status:")
    ];
    NSMutableArray<NSTextField *> *values = [NSMutableArray array];
    CGFloat labelCol = 104;        /* right-aligned label column width */
    CGFloat rowH = 18;
    CGFloat y = 8;
    CGFloat totalH = 8 + labels.count * (rowH + 2) + 8;
    for (NSInteger i = (NSInteger)labels.count - 1; i >= 0; i--) {
        NSTextField *lbl = [NSTextField labelWithString:labels[i]];
        lbl.alignment = NSTextAlignmentRight;
        lbl.font = [NSFont systemFontOfSize:11];
        lbl.textColor = [NSColor secondaryLabelColor];
        lbl.frame = NSMakeRect(8, y, labelCol, rowH);
        lbl.autoresizingMask = NSViewMaxXMargin;
        [_detailsView addSubview:lbl];

        NSTextField *val = [NSTextField labelWithString:@"—"];
        val.font = [NSFont systemFontOfSize:11];
        val.textColor = [NSColor labelColor];
        val.lineBreakMode = NSLineBreakByTruncatingMiddle;
        val.selectable = YES;
        val.frame = NSMakeRect(labelCol + 16, y, 280, rowH);
        val.autoresizingMask = NSViewWidthSizable;
        [_detailsView addSubview:val];
        [values insertObject:val atIndex:0];
        y += rowH + 2;
    }
    _detailServer      = values[0];
    _detailFrom        = values[1];
    _detailTo          = values[2];
    _detailTransferred = values[3];
    _detailSpeed       = values[4];
    _detailRemaining   = values[5];
    _detailElapsed     = values[6];
    _detailError       = values[7];
    _detailError.stringValue = L(@"Running");
    /* Remember the target height so toggleDetails: can use it. */
    objc_setAssociatedObject(self, "detailsH", @(totalH), OBJC_ASSOCIATION_RETAIN);
}

- (void)toggleDetails:(id)sender {
    self.detailsExpanded = !self.detailsExpanded;
    self.detailsView.hidden = !self.detailsExpanded;
    CGFloat h = [objc_getAssociatedObject(self, "detailsH") doubleValue];
    self.detailsHeightConstraint.constant = self.detailsExpanded ? h : 0;
    self.disclosureButton.toolTip = self.detailsExpanded
        ? L(@"Hide transfer details") : L(@"Show transfer details");
    [[JobsPanelController shared] relayoutForExpandedRow];
}

/* Format elapsed seconds as "45 s", "2 min 15 s", "1 h 20 min". */
+ (NSString *)_formatDuration:(NSTimeInterval)sec {
    long s = (long)sec;
    if (s < 60) return [NSString stringWithFormat:@"%ld s", s];
    if (s < 3600) return [NSString stringWithFormat:@"%ld min %ld s", s/60, s%60];
    return [NSString stringWithFormat:@"%ld h %ld min", s/3600, (s%3600)/60];
}

- (void)updateElapsed {
    NSTimeInterval dt = [[NSDate date] timeIntervalSinceDate:_startTime ?: [NSDate date]];
    _detailElapsed.stringValue = [ProgressSheetController _formatDuration:dt];
}

/* No-op kept so existing callers that used the removed raw-log path compile. */
- (void)appendLogLine:(NSString *)line { (void)line; }

- (void)cancel:(id)sender {
    self.cancelled = YES;
    _cancelButton.enabled = NO;
    _titleLabel.stringValue = L(@"Cancelling…");
    if (self.cancelHandler) self.cancelHandler();
}

/* Returns: 1=Replace, 2=Skip, 3=Keep Both, 4=Cancel-all, 5=Merge.
 * Merge is only offered when both source and destination are directories.
 * If the "Apply to all remaining" checkbox is on, writes the choice into
 * applyAll so subsequent conflicts use it without prompting. */
- (int)askReplaceSkipKeepBothFor:(NSString *)name
                           isDir:(BOOL)bothAreDirs
                        applyAll:(int *)applyAll {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"\"%@\" already exists", name];
    alert.informativeText = bothAreDirs
        ? @"Both are folders. Merge = add source's contents into the existing folder (won't overwrite anything there)."
        : @"Choose how to handle this conflict.";
    alert.alertStyle = NSAlertStyleWarning;

    [alert addButtonWithTitle:L(@"Replace")];
    [alert addButtonWithTitle:L(@"Skip")];
    [alert addButtonWithTitle:L(@"Keep Both")];
    [alert addButtonWithTitle:L(@"Cancel All")];
    if (bothAreDirs) [alert addButtonWithTitle:L(@"Merge")];

    NSButton *applyToAll = [NSButton checkboxWithTitle:L(@"Apply to all remaining conflicts")
                                                target:nil action:nil];
    applyToAll.frame = NSMakeRect(0, 0, 300, 20);
    alert.accessoryView = applyToAll;

    NSModalResponse r = [alert runModal];
    int choice = 2;  /* default skip */
    if      (r == NSAlertFirstButtonReturn)        choice = 1;  /* Replace */
    else if (r == NSAlertSecondButtonReturn)       choice = 2;  /* Skip */
    else if (r == NSAlertThirdButtonReturn)        choice = 3;  /* Keep Both */
    else if (r == NSAlertThirdButtonReturn + 1)    choice = 4;  /* Cancel All */
    else if (r == NSAlertThirdButtonReturn + 2)    choice = 5;  /* Merge */

    if (applyToAll.state == NSControlStateValueOn && choice != 4) {
        *applyAll = choice;
    }
    return choice;
}

/* Non-destructive merge: walk source dir recursively and copy/move each
 * item into dest dir, skipping items that already exist at dest. Leaves
 * the user's existing files alone — good for "fill missing stuff in". */
- (BOOL)mergeSource:(NSString *)src
          intoDest:(NSString *)dst
            isMove:(BOOL)isMove
         fileManager:(NSFileManager *)fm
             failed:(NSMutableArray<NSString *> *)failed {
    NSError *err = nil;
    NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:src error:&err];
    if (!children) {
        [failed addObject:[NSString stringWithFormat:@"%@: %@",
                           src.lastPathComponent, err.localizedDescription]];
        return NO;
    }
    BOOL allOK = YES;
    for (NSString *child in children) {
        if (self.cancelled) return NO;
        NSString *fromChild = [src stringByAppendingPathComponent:child];
        NSString *toChild   = [dst stringByAppendingPathComponent:child];

        BOOL toExists = [fm fileExistsAtPath:toChild];
        BOOL fromIsDir = NO, toIsDir = NO;
        [fm fileExistsAtPath:fromChild isDirectory:&fromIsDir];
        if (toExists) [fm fileExistsAtPath:toChild isDirectory:&toIsDir];

        if (!toExists) {
            NSError *e = nil;
            BOOL ok = isMove
                ? [fm moveItemAtPath:fromChild toPath:toChild error:&e]
                : [fm copyItemAtPath:fromChild toPath:toChild error:&e];
            if (!ok) { [failed addObject:[NSString stringWithFormat:@"%@: %@", child, e.localizedDescription]]; allOK = NO; }
        } else if (fromIsDir && toIsDir) {
            /* recurse */
            BOOL rec = [self mergeSource:fromChild intoDest:toChild isMove:isMove fileManager:fm failed:failed];
            if (!rec) allOK = NO;
        }
        /* else: conflict on a file → skip (non-destructive merge) */
    }
    /* For move, if source is now empty we can remove it. */
    if (isMove && allOK && !self.cancelled) {
        NSArray *remain = [fm contentsOfDirectoryAtPath:src error:nil];
        if (remain.count == 0) [fm removeItemAtPath:src error:nil];
    }
    return allOK;
}

- (void)runOperation:(BOOL)isMove
               paths:(NSArray<NSString *> *)paths
               names:(NSArray<NSString *> *)names
             destDir:(NSString *)destDir
        sourceWindow:(NSWindow *)srcWin
          completion:(void (^)(NSArray<NSString *> *))completion {

    (void)srcWin;
    self.titleLabel.stringValue = isMove ? L(@"Moving…") : L(@"Copying…");
    [self.spinner startAnimation:nil];
    [[JobsPanelController shared] addJobRow:self.rowView];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableArray<NSString *> *failed = [NSMutableArray array];

        /* Conflict resolution strategy for this run. Initially "ask";
         * once the user picks "apply to all" we switch to the chosen
         * non-interactive mode. */
        __block int applyAll = 0;  /* 0=ask, 1=replace, 2=skip, 3=keepBoth */

        for (NSUInteger i = 0; i < paths.count; i++) {
            if (self.cancelled) break;

            NSString *name = names[i];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.titleLabel.stringValue = name;
                self.statsLabel.stringValue = [NSString stringWithFormat:L(@"Item %lu of %lu"),
                                                (unsigned long)(i + 1),
                                                (unsigned long)paths.count];
            });

            NSString *from = paths[i];
            NSString *to = [destDir stringByAppendingPathComponent:name];

            /* Conflict: target already exists → ask unless apply-all is set */
            if ([fm fileExistsAtPath:to]) {
                BOOL fromIsDir = NO, toIsDir = NO;
                [fm fileExistsAtPath:from isDirectory:&fromIsDir];
                [fm fileExistsAtPath:to   isDirectory:&toIsDir];
                BOOL bothDirs = fromIsDir && toIsDir;

                __block int choice = applyAll;
                if (choice == 0 || (choice == 5 && !bothDirs)) {
                    /* Re-prompt if the saved apply-all is Merge but this pair
                     * isn't dir-on-dir (Merge not applicable). */
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        choice = [self askReplaceSkipKeepBothFor:name
                                                           isDir:bothDirs
                                                        applyAll:&applyAll];
                    });
                }
                if (choice == 2) continue;   /* skip */
                if (choice == 4) { self.cancelled = YES; break; }  /* cancel all */
                if (choice == 5 && bothDirs) {
                    /* Merge dir-on-dir recursively. Loop's copy/move at the
                     * bottom is skipped for this iteration. */
                    [self mergeSource:from intoDest:to isMove:isMove
                          fileManager:fm failed:failed];
                    continue;
                }
                if (choice == 3) {
                    /* Keep both: resolve to a unique name */
                    NSString *base = [name stringByDeletingPathExtension];
                    NSString *ext = name.pathExtension;
                    for (int n = 2; n < 1000; n++) {
                        NSString *alt = ext.length
                            ? [NSString stringWithFormat:@"%@ %d.%@", base, n, ext]
                            : [NSString stringWithFormat:@"%@ %d", base, n];
                        NSString *altPath = [destDir stringByAppendingPathComponent:alt];
                        if (![fm fileExistsAtPath:altPath]) { to = altPath; break; }
                    }
                } else if (choice == 1) {
                    /* Replace: remove existing first */
                    NSError *rmErr = nil;
                    if (![fm removeItemAtPath:to error:&rmErr]) {
                        [failed addObject:[NSString stringWithFormat:@"%@: %@ (replace)",
                                           name, rmErr.localizedDescription]];
                        continue;
                    }
                }
            }

            NSError *err = nil;
            BOOL ok = isMove
                ? [fm moveItemAtPath:from toPath:to error:&err]
                : [fm copyItemAtPath:from toPath:to error:&err];
            if (!ok) {
                [failed addObject:[NSString stringWithFormat:@"%@: %@", name, err.localizedDescription]];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimation:nil];
            [[JobsPanelController shared] removeJobRow:self.rowView];
            if (completion) completion(failed);
        });
    });
}

@end

#pragma mark - Jobs Panel

@implementation JobsPanelController

+ (instancetype)shared {
    static JobsPanelController *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[JobsPanelController alloc] init]; });
    return s;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 460, 80);
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
                               NSWindowStyleMaskClosable |
                               NSWindowStyleMaskUtilityWindow |
                               NSWindowStyleMaskNonactivatingPanel;
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
                                                styleMask:style
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.title = L(@"File operations");
    panel.hidesOnDeactivate = NO;
    panel.becomesKeyOnlyIfNeeded = YES;
    panel.releasedWhenClosed = NO;

    self = [super initWithWindow:panel];
    if (!self) return nil;

    NSView *content = panel.contentView;

    _stack = [[NSStackView alloc] init];
    _stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _stack.alignment = NSLayoutAttributeLeading;
    _stack.distribution = NSStackViewDistributionGravityAreas;
    _stack.spacing = 8;
    _stack.edgeInsets = NSEdgeInsetsMake(8, 8, 8, 8);
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_stack];

    [NSLayoutConstraint activateConstraints:@[
        [_stack.leadingAnchor  constraintEqualToAnchor:content.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_stack.topAnchor      constraintEqualToAnchor:content.topAnchor],
        [_stack.bottomAnchor   constraintEqualToAnchor:content.bottomAnchor],
    ]];
    return self;
}

- (void)addJobRow:(NSView *)row {
    NSBox *divider = nil;
    if (_stack.arrangedSubviews.count > 0) {
        divider = [[NSBox alloc] init];
        divider.boxType = NSBoxSeparator;
        divider.translatesAutoresizingMaskIntoConstraints = NO;
        [_stack addArrangedSubview:divider];
        [divider.widthAnchor constraintEqualToAnchor:_stack.widthAnchor constant:-16].active = YES;
    }
    [_stack addArrangedSubview:row];
    [row.widthAnchor constraintEqualToAnchor:_stack.widthAnchor constant:-16].active = YES;
    [self.window setContentSize:[self fittingSize]];
    [self.window.contentView layoutSubtreeIfNeeded];
    [self.window center];
    [self.window orderFront:nil];
}

- (void)relayoutForExpandedRow {
    [self.window.contentView layoutSubtreeIfNeeded];
    [self.window setContentSize:[self fittingSize]];
}

- (void)removeJobRow:(NSView *)row {
    NSUInteger idx = [_stack.arrangedSubviews indexOfObject:row];
    if (idx == NSNotFound) return;
    /* Remove trailing separator too if present, else the leading one. */
    if (idx + 1 < _stack.arrangedSubviews.count) {
        NSView *sep = _stack.arrangedSubviews[idx + 1];
        if ([sep isKindOfClass:[NSBox class]]) [sep removeFromSuperview];
    } else if (idx > 0) {
        NSView *sep = _stack.arrangedSubviews[idx - 1];
        if ([sep isKindOfClass:[NSBox class]]) [sep removeFromSuperview];
    }
    [row removeFromSuperview];
    if (_stack.arrangedSubviews.count == 0) {
        [self.window orderOut:nil];
    } else {
        [self.window setContentSize:[self fittingSize]];
    }
}

- (NSSize)fittingSize {
    CGFloat height = 16;  /* insets */
    for (NSView *v in _stack.arrangedSubviews) {
        CGFloat h = [v fittingSize].height;
        if (h <= 0) h = [v isKindOfClass:[NSBox class]] ? 1 : 76;
        height += h + 8;
    }
    if (height < 80) height = 80;
    return NSMakeSize(460, height);
}

@end

#pragma mark - Button Bank Panel

/* Floating Magellan-style panel with a grid of action buttons, shared across
 * all Listers. Non-activating: clicking a button does NOT steal key focus from
 * the active source Lister, so source/dest semantics remain stable.
 * Buttons route to IDOpusAppDelegate methods that operate on activeSource. */
@interface ButtonBankPanelController : NSWindowController <NSWindowDelegate>
- (instancetype)initWithAppDelegate:(IDOpusAppDelegate *)appDelegate;
- (void)positionBetweenLeftFrame:(NSRect)leftFrame rightFrame:(NSRect)rightFrame;
- (void)rebuildGrid;
+ (CGFloat)desiredWidth;
@end

@implementation ButtonBankPanelController {
    __weak IDOpusAppDelegate *_appDelegate;
}

- (instancetype)initWithAppDelegate:(IDOpusAppDelegate *)appDelegate {
    NSRect frame = NSMakeRect(0, 0, 108, 400);
    /* Borderless + resizable: no title bar / close / min / zoom buttons, so
     * the user can't accidentally drag the bank out of the tile. Height is
     * enforced to match the neighbouring Listers in windowWillResize; only
     * horizontal resize is allowed (drag the right edge to widen/narrow). */
    NSWindowStyleMask style = NSWindowStyleMaskBorderless |
                               NSWindowStyleMaskResizable |
                               NSWindowStyleMaskNonactivatingPanel;
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
                                                styleMask:style
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    /* Attached to the SOURCE Lister as a child window — no floating/level tricks.
     * Non-activating so clicking a button doesn't steal focus from the Lister. */
    panel.becomesKeyOnlyIfNeeded = YES;
    panel.hidesOnDeactivate = NO;
    panel.movable = NO;   /* lock position — managed by app delegate's tile snap */
    panel.contentMinSize = NSMakeSize(70, 200);

    self = [super initWithWindow:panel];
    if (!self) return nil;
    _appDelegate = appDelegate;
    panel.delegate = self;

    [self buildGrid];
    return self;
}

#pragma mark NSWindowDelegate

/* Enforce "only horizontal resize". The height is locked to whatever the
 * adjacent Listers have; the user controls width by dragging the panel's
 * right edge. */
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)proposedSize {
    NSSize s = proposedSize;
    s.height = sender.frame.size.height;
    return s;
}

/* After a bank resize (user dragged the right edge), snap the DEST Lister
 * to the bank's new right edge so the tile stays tight. */
- (void)windowDidResize:(NSNotification *)note {
    [_appDelegate snapDestToBankRightEdge];
}

- (void)buildGrid {
    [self rebuildGrid];
}

/* (Re)build the vertical button column. Called on init and whenever user
 * custom buttons are added / removed. */
- (void)rebuildGrid {
    NSView *content = self.window.contentView;
    /* Remove any existing subviews so we can rebuild cleanly */
    for (NSView *v in [content.subviews copy]) [v removeFromSuperview];

    struct { NSString *title; SEL action; } builtIn[] = {
        { L(@"Copy"),    @selector(copyAction:)    },
        { L(@"Move"),    @selector(moveAction:)    },
        { L(@"Delete"),  @selector(deleteAction:)  },
        { L(@"Rename"),  @selector(renameAction:)  },
        { L(@"MakeDir"), @selector(makeDirAction:) },
        { L(@"Info"),    @selector(infoAction:)    },
        { L(@"Filter"),  @selector(filterAction:)  },
        { L(@"Parent"),  @selector(parentAction:)  },
        { L(@"Root"),    @selector(rootAction:)    },
        { L(@"Refresh"), @selector(refreshAction:) },
        { L(@"All"),     @selector(allAction:)     },
        { L(@"None"),    @selector(noneAction:)    },
    };

    NSStackView *column = [[NSStackView alloc] init];
    column.orientation = NSUserInterfaceLayoutOrientationVertical;
    column.spacing = 4;
    column.distribution = NSStackViewDistributionFillEqually;
    column.alignment = NSLayoutAttributeCenterX;
    column.translatesAutoresizingMaskIntoConstraints = NO;

    for (size_t i = 0; i < sizeof(builtIn)/sizeof(builtIn[0]); i++) {
        [self appendButton:builtIn[i].title
                    target:_appDelegate
                    action:builtIn[i].action
                  intoStack:column];
    }

    NSArray<NSDictionary *> *customs = [[NSUserDefaults standardUserDefaults] arrayForKey:@"customButtons"] ?: @[];
    for (NSDictionary *b in customs) {
        NSString *title = b[@"title"]; NSString *cmd = b[@"command"];
        if (!title.length || !cmd.length) continue;
        NSButton *btn = [self appendButton:title
                                    target:_appDelegate
                                    action:@selector(runCustomButton:)
                                 intoStack:column];
        btn.toolTip = cmd;
        btn.tag = 1;   /* mark as custom */
        objc_setAssociatedObject(btn, "cmd", cmd, OBJC_ASSOCIATION_COPY);
    }

    [content addSubview:column];
    [NSLayoutConstraint activateConstraints:@[
        [column.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:6],
        [column.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-6],
        [column.topAnchor constraintEqualToAnchor:content.topAnchor constant:6],
        [column.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-6],
    ]];
}

- (NSButton *)appendButton:(NSString *)title
                    target:(id)target
                    action:(SEL)action
                 intoStack:(NSStackView *)column {
    NSButton *b = [NSButton buttonWithTitle:title target:target action:action];
    b.bezelStyle = NSBezelStyleShadowlessSquare;
    b.font = [NSFont systemFontOfSize:11];
    [b setContentHuggingPriority:NSLayoutPriorityDefaultLow
                  forOrientation:NSLayoutConstraintOrientationVertical];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [column addArrangedSubview:b];
    [b.leadingAnchor constraintEqualToAnchor:column.leadingAnchor].active = YES;
    [b.trailingAnchor constraintEqualToAnchor:column.trailingAnchor].active = YES;
    return b;
}

/* Desired panel width when docked between two Listers */
+ (CGFloat)desiredWidth { return 108; }

- (void)positionBetweenLeftFrame:(NSRect)leftFrame rightFrame:(NSRect)rightFrame {
    /* Span the full Lister height — the panel fills the vertical gap exactly. */
    CGFloat x = NSMaxX(leftFrame);
    CGFloat w = rightFrame.origin.x - x;
    CGFloat h = leftFrame.size.height;

    /* Clear any min/max constraints that would clamp setFrame */
    self.window.contentMinSize = NSMakeSize(50, 100);
    self.window.contentMaxSize = NSMakeSize(10000, 10000);
    self.window.minSize = NSMakeSize(50, 100);
    self.window.maxSize = NSMakeSize(10000, 10000);

    NSRect frame = NSMakeRect(x, leftFrame.origin.y, w, h);
    [self.window setFrame:frame display:YES animate:NO];
}

@end

#pragma mark - Rsync Sheet

/* Sheet that runs rsync as an NSTask and streams stdout/stderr into an
 * NSTextView. Cancel terminates the task. The user sees exactly the
 * rsync log they'd see in a terminal. */
@interface RsyncSheetController : NSWindowController
@property (nonatomic, strong) NSTextField *currentFileLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSProgressIndicator *progressBar;
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, strong) NSView *summaryView;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSButton *toggleLogButton;
@property (nonatomic, strong) NSScrollView *logScrollView;
@property (nonatomic, strong) NSTask *task;
@property (atomic, assign) BOOL finished;
/* parser state */
@property (nonatomic, strong) NSMutableString *lineBuf;
@property (nonatomic, strong) NSString *pendingFilename;
@property (nonatomic, strong) NSMutableString *statsBuf;
@property (atomic, assign) BOOL inStatsBlock;
@property (atomic, assign) double totalFiles;
@property (atomic, assign) double filesDone;

- (void)runArgs:(NSArray<NSString *> *)args
          title:(NSString *)title
     sourceWindow:(NSWindow *)srcWin
     completion:(void (^)(int status))completion;
@end

@implementation RsyncSheetController

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 680, 460);
    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled |
                                                         NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self = [super initWithWindow:w];
    if (!self) return nil;
    _lineBuf = [NSMutableString string];
    _statsBuf = [NSMutableString string];

    NSView *c = w.contentView;

    _currentFileLabel = [NSTextField labelWithString:L(@"Preparing…")];
    _currentFileLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    _currentFileLabel.textColor = [NSColor labelColor];
    _currentFileLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _currentFileLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:_currentFileLabel];

    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:_statusLabel];

    _progressBar = [[NSProgressIndicator alloc] init];
    _progressBar.indeterminate = YES;
    _progressBar.style = NSProgressIndicatorStyleBar;
    _progressBar.minValue = 0.0;
    _progressBar.maxValue = 1.0;
    _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    [_progressBar startAnimation:nil];
    [c addSubview:_progressBar];

    _logScrollView = [[NSScrollView alloc] init];
    _logScrollView.hasVerticalScroller = YES;
    _logScrollView.autohidesScrollers = NO;
    _logScrollView.borderType = NSBezelBorder;
    _logScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _logScrollView.hidden = YES;

    _textView = [[NSTextView alloc] init];
    _textView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _textView.editable = NO;
    _textView.richText = NO;
    _textView.drawsBackground = YES;
    _textView.backgroundColor = [NSColor textBackgroundColor];
    _textView.autoresizingMask = NSViewWidthSizable;
    _textView.textContainer.widthTracksTextView = YES;
    _logScrollView.documentView = _textView;
    [c addSubview:_logScrollView];

    _summaryView = [[NSView alloc] init];
    _summaryView.translatesAutoresizingMaskIntoConstraints = NO;
    _summaryView.wantsLayer = YES;
    _summaryView.layer.backgroundColor = [NSColor.controlBackgroundColor CGColor];
    _summaryView.layer.cornerRadius = 8.0;
    _summaryView.hidden = YES;
    [c addSubview:_summaryView];

    _toggleLogButton = [NSButton buttonWithTitle:L(@"Show log") target:self action:@selector(toggleLog:)];
    _toggleLogButton.bezelStyle = NSBezelStyleRounded;
    _toggleLogButton.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:_toggleLogButton];

    _cancelButton = [NSButton buttonWithTitle:L(@"Cancel") target:self action:@selector(cancel:)];
    _cancelButton.keyEquivalent = @"\033";
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:_cancelButton];

    _closeButton = [NSButton buttonWithTitle:L(@"OK") target:self action:@selector(closeSheet:)];
    _closeButton.keyEquivalent = @"\r";
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    _closeButton.hidden = YES;
    [c addSubview:_closeButton];

    [NSLayoutConstraint activateConstraints:@[
        [_currentFileLabel.topAnchor      constraintEqualToAnchor:c.topAnchor constant:16],
        [_currentFileLabel.leadingAnchor  constraintEqualToAnchor:c.leadingAnchor constant:16],
        [_currentFileLabel.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-16],

        [_statusLabel.topAnchor      constraintEqualToAnchor:_currentFileLabel.bottomAnchor constant:4],
        [_statusLabel.leadingAnchor  constraintEqualToAnchor:c.leadingAnchor constant:16],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-16],

        [_progressBar.topAnchor      constraintEqualToAnchor:_statusLabel.bottomAnchor constant:8],
        [_progressBar.leadingAnchor  constraintEqualToAnchor:c.leadingAnchor constant:16],
        [_progressBar.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-16],

        [_summaryView.topAnchor      constraintEqualToAnchor:_progressBar.bottomAnchor constant:12],
        [_summaryView.leadingAnchor  constraintEqualToAnchor:c.leadingAnchor constant:16],
        [_summaryView.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-16],

        [_logScrollView.topAnchor      constraintEqualToAnchor:_progressBar.bottomAnchor constant:12],
        [_logScrollView.leadingAnchor  constraintEqualToAnchor:c.leadingAnchor constant:16],
        [_logScrollView.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-16],
        [_logScrollView.bottomAnchor   constraintEqualToAnchor:_cancelButton.topAnchor constant:-12],

        [_toggleLogButton.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
        [_toggleLogButton.bottomAnchor  constraintEqualToAnchor:c.bottomAnchor constant:-16],

        [_cancelButton.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-16],
        [_cancelButton.bottomAnchor   constraintEqualToAnchor:c.bottomAnchor constant:-16],

        [_closeButton.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-16],
        [_closeButton.bottomAnchor   constraintEqualToAnchor:c.bottomAnchor constant:-16],
    ]];
    return self;
}

- (void)appendText:(NSString *)s {
    NSAttributedString *a = [[NSAttributedString alloc] initWithString:s
        attributes:@{ NSFontAttributeName: self.textView.font,
                      NSForegroundColorAttributeName: [NSColor labelColor] }];
    [self.textView.textStorage appendAttributedString:a];
    [self.textView scrollRangeToVisible:NSMakeRange(self.textView.textStorage.length, 0)];
}

- (void)cancel:(id)sender {
    if (self.task.isRunning) [self.task terminate];
    self.cancelButton.enabled = NO;
    self.currentFileLabel.stringValue = L(@"Cancelling…");
}

- (void)toggleLog:(id)sender {
    BOOL show = self.logScrollView.hidden;
    self.logScrollView.hidden = !show;
    self.summaryView.hidden = show || !self.finished;
    self.toggleLogButton.title = show ? L(@"Hide log") : L(@"Show log");
}

- (void)closeSheet:(id)sender {
    NSWindow *parent = self.window.sheetParent;
    if (parent) [parent endSheet:self.window];
    else        [self.window close];
}

/* Parse a single rsync line (without trailing \n). */
- (void)handleRsyncLine:(NSString *)line {
    /* Collect --stats block at end. Starts with "Number of files:" for both old/new rsync. */
    if ([line hasPrefix:@"Number of files:"]) self.inStatsBlock = YES;
    if (self.inStatsBlock) {
        [self.statsBuf appendFormat:@"%@\n", line];
    }

    /* Progress line:  "   1234567  45%    5.00MB/s    0:00:12 [(xfer#N, to-check=X/Y)]" */
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    static NSRegularExpression *rxProgress = nil;
    static NSRegularExpression *rxToCheck = nil;
    static dispatch_once_t onceTok; dispatch_once(&onceTok, ^{
        rxProgress = [NSRegularExpression regularExpressionWithPattern:
            @"^([\\d,]+)\\s+(\\d+)%\\s+(\\S+)\\s+(\\d+:\\d+:\\d+)"
            options:0 error:nil];
        rxToCheck = [NSRegularExpression regularExpressionWithPattern:
            @"to-check=(\\d+)/(\\d+)"
            options:0 error:nil];
    });

    NSTextCheckingResult *m = [rxProgress firstMatchInString:trimmed
        options:0 range:NSMakeRange(0, trimmed.length)];
    if (m && m.numberOfRanges >= 5) {
        NSString *bytes = [trimmed substringWithRange:[m rangeAtIndex:1]];
        NSString *pct   = [trimmed substringWithRange:[m rangeAtIndex:2]];
        NSString *speed = [trimmed substringWithRange:[m rangeAtIndex:3]];
        NSString *eta   = [trimmed substringWithRange:[m rangeAtIndex:4]];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ B · %@%% · %@ · ETA %@",
                                         bytes, pct, speed, eta];
        NSTextCheckingResult *t = [rxToCheck firstMatchInString:trimmed
            options:0 range:NSMakeRange(0, trimmed.length)];
        if (t && t.numberOfRanges >= 3) {
            double remain = [[trimmed substringWithRange:[t rangeAtIndex:1]] doubleValue];
            double total  = [[trimmed substringWithRange:[t rangeAtIndex:2]] doubleValue];
            if (total > 0) {
                if (self.progressBar.indeterminate) {
                    [self.progressBar stopAnimation:nil];
                    self.progressBar.indeterminate = NO;
                    self.progressBar.minValue = 0;
                }
                self.progressBar.maxValue = total;
                self.progressBar.doubleValue = MAX(0.0, total - remain);
                self.totalFiles = total;
                self.filesDone = total - remain;
            }
        }
        return;  /* progress lines don't become filenames */
    }

    /* Candidate filename lines: ignore empty, headers, summary. */
    if (trimmed.length == 0) return;
    if ([trimmed hasPrefix:@"sending incremental"] ||
        [trimmed hasPrefix:@"receiving incremental"] ||
        [trimmed hasPrefix:@"sending file list"] ||
        [trimmed hasPrefix:@"receiving file list"] ||
        [trimmed hasPrefix:@"building file list"] ||
        [trimmed hasPrefix:@"sent "] ||
        [trimmed hasPrefix:@"total size is"] ||
        [trimmed hasPrefix:@"rsync:"] ||
        [trimmed hasPrefix:@"rsync error:"] ||
        self.inStatsBlock) return;

    /* Looks like a filename/path — update current file label. */
    self.currentFileLabel.stringValue = trimmed;
}

/* Consume an incoming chunk, split into complete lines, feed parser. */
- (void)ingest:(NSString *)chunk {
    [self.lineBuf appendString:chunk];
    while (YES) {
        NSRange r = [self.lineBuf rangeOfString:@"\n"];
        NSRange r2 = [self.lineBuf rangeOfString:@"\r"];
        NSRange split = r;
        if (r2.location != NSNotFound && (r.location == NSNotFound || r2.location < r.location)) split = r2;
        if (split.location == NSNotFound) break;
        NSString *line = [self.lineBuf substringToIndex:split.location];
        [self.lineBuf deleteCharactersInRange:NSMakeRange(0, split.location + split.length)];
        [self handleRsyncLine:line];
    }
    [self appendText:chunk];
}

/* Parse the collected --stats block and show summary view. */
- (NSDictionary *)parseStats {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *raw in [self.statsBuf componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!line.length) continue;
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location != NSNotFound) {
            NSString *k = [[line substringToIndex:colon.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *v = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (k && v) out[k] = v;
        }
        /* "sent X bytes  received Y bytes  Z bytes/sec" */
        if ([line hasPrefix:@"sent "]) out[@"__sentLine"] = line;
        if ([line hasPrefix:@"total size is"]) out[@"__totalLine"] = line;
    }
    return out;
}

- (NSTextField *)summaryKey:(NSString *)k value:(NSString *)v y:(CGFloat)y bold:(BOOL)bold {
    NSTextField *lk = [NSTextField labelWithString:k];
    lk.font = [NSFont systemFontOfSize:12 weight:bold ? NSFontWeightSemibold : NSFontWeightRegular];
    lk.textColor = [NSColor secondaryLabelColor];
    lk.frame = NSMakeRect(12, y, 200, 18);
    [self.summaryView addSubview:lk];

    NSTextField *lv = [NSTextField labelWithString:v ?: @"—"];
    lv.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:bold ? NSFontWeightSemibold : NSFontWeightRegular];
    lv.textColor = [NSColor labelColor];
    lv.frame = NSMakeRect(220, y, 400, 18);
    lv.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.summaryView addSubview:lv];
    return lv;
}

- (void)buildSummaryForStatus:(int)status {
    NSDictionary *s = [self parseStats];

    /* Clear previous */
    for (NSView *sub in [self.summaryView.subviews copy]) [sub removeFromSuperview];

    /* Header */
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(12, 150, 28, 28)];
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    icon.image = status == 0
        ? [NSImage imageWithSystemSymbolName:@"checkmark.circle.fill" accessibilityDescription:nil]
        : [NSImage imageWithSystemSymbolName:@"exclamationmark.triangle.fill" accessibilityDescription:nil];
    if (status == 0) icon.contentTintColor = [NSColor systemGreenColor];
    else             icon.contentTintColor = [NSColor systemOrangeColor];
    [self.summaryView addSubview:icon];

    NSTextField *hdr = [NSTextField labelWithString:
        status == 0 ? L(@"Sync complete")
                    : [NSString stringWithFormat:L(@"Sync finished with errors (status %d)"), status]];
    hdr.font = [NSFont systemFontOfSize:15 weight:NSFontWeightBold];
    hdr.textColor = [NSColor labelColor];
    hdr.frame = NSMakeRect(50, 152, 500, 22);
    [self.summaryView addSubview:hdr];

    /* Rows */
    CGFloat y = 122;
    CGFloat step = 22;
    NSString *files    = s[@"Number of files"] ?: s[@"Number of files transferred"] ?: @"—";
    NSString *xferred  = s[@"Number of regular files transferred"] ?: s[@"Number of files transferred"] ?: @"—";
    NSString *totalSz  = s[@"Total file size"] ?: @"—";
    NSString *xferSz   = s[@"Total transferred file size"] ?: @"—";
    NSString *sentLine = s[@"__sentLine"] ?: @"—";
    NSString *sizeLine = s[@"__totalLine"] ?: @"—";

    [self summaryKey:L(@"Files scanned:")        value:files    y:y bold:NO]; y -= step;
    [self summaryKey:L(@"Files transferred:")    value:xferred  y:y bold:YES]; y -= step;
    [self summaryKey:L(@"Total size:")           value:totalSz  y:y bold:NO]; y -= step;
    [self summaryKey:L(@"Transferred size:")     value:xferSz   y:y bold:YES]; y -= step;
    [self summaryKey:L(@"Throughput:")           value:sentLine y:y bold:NO]; y -= step;
    [self summaryKey:L(@"Overall:")              value:sizeLine y:y bold:NO]; y -= step;

    [NSLayoutConstraint activateConstraints:@[
        [self.summaryView.heightAnchor constraintGreaterThanOrEqualToConstant:190],
    ]];
}

- (void)runArgs:(NSArray<NSString *> *)args
          title:(NSString *)title
     sourceWindow:(NSWindow *)srcWin
     completion:(void (^)(int status))completion {

    self.window.title = title;
    [self appendText:[NSString stringWithFormat:@"$ /usr/bin/rsync %@\n\n",
                      [args componentsJoinedByString:@" "]]];
    [srcWin beginSheet:self.window completionHandler:nil];

    self.task = [[NSTask alloc] init];
    self.task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/rsync"];
    self.task.arguments = args;

    NSPipe *outPipe = [NSPipe pipe];
    NSPipe *errPipe = [NSPipe pipe];
    self.task.standardOutput = outPipe;
    self.task.standardError = errPipe;

    __weak typeof(self) weakSelf = self;
    NSFileHandle *outRd = outPipe.fileHandleForReading;
    NSFileHandle *errRd = errPipe.fileHandleForReading;
    outRd.readabilityHandler = ^(NSFileHandle *fh) {
        NSData *d = fh.availableData;
        if (d.length == 0) { fh.readabilityHandler = nil; return; }
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (!s.length) return;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf ingest:s]; });
    };
    errRd.readabilityHandler = ^(NSFileHandle *fh) {
        NSData *d = fh.availableData;
        if (d.length == 0) { fh.readabilityHandler = nil; return; }
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (!s.length) return;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf ingest:s]; });
    };
    self.task.terminationHandler = ^(NSTask *t) {
        int status = t.terminationStatus;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) s = weakSelf; if (!s) return;
            s.finished = YES;
            [s appendText:[NSString stringWithFormat:@"\n[rsync exited with status %d]\n", status]];
            /* Flush any remaining buffered line */
            if (s.lineBuf.length) { [s handleRsyncLine:s.lineBuf]; [s.lineBuf setString:@""]; }
            [s.progressBar stopAnimation:nil];
            if (!s.progressBar.indeterminate && status == 0) {
                s.progressBar.doubleValue = s.progressBar.maxValue;
            }
            s.currentFileLabel.stringValue = status == 0 ? L(@"Sync complete") : L(@"Sync finished with errors");
            s.statusLabel.stringValue = @"";
            [s buildSummaryForStatus:status];
            s.summaryView.hidden = NO;
            s.progressBar.hidden = YES;
            s.cancelButton.hidden = YES;
            s.closeButton.hidden = NO;
            [s.window makeFirstResponder:s.closeButton];
            if (completion) completion(status);
        });
    };

    NSError *err = nil;
    if (![self.task launchAndReturnError:&err]) {
        [self appendText:[NSString stringWithFormat:@"\n[launch failed: %@]\n", err.localizedDescription]];
        self.finished = YES;
        self.cancelButton.hidden = YES;
        self.closeButton.hidden = NO;
    }
}

@end

#pragma mark - Preferences Window

/* Simple preferences panel bound to NSUserDefaults. Each checkbox writes its
 * key on change — settings take effect on next relevant trigger (next launch
 * for startup flags, next filter apply for display flags). */
@interface PreferencesWindowController : NSWindowController
- (instancetype)initWithAppDelegate:(IDOpusAppDelegate *)app;
@end

@implementation PreferencesWindowController {
    __weak IDOpusAppDelegate *_app;
}

- (instancetype)initWithAppDelegate:(IDOpusAppDelegate *)app {
    NSRect frame = NSMakeRect(0, 0, 460, 280);
    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled |
                                                         NSWindowStyleMaskClosable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    w.title = L(@"Preferences");
    w.releasedWhenClosed = NO;

    self = [super initWithWindow:w];
    if (!self) return nil;
    _app = app;

    NSView *c = w.contentView;
    NSStackView *col = [[NSStackView alloc] init];
    col.orientation = NSUserInterfaceLayoutOrientationVertical;
    col.alignment = NSLayoutAttributeLeading;
    col.spacing = 10;
    col.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:col];

    NSTextField *header = [NSTextField labelWithString:L(@"General")];
    header.font = [NSFont boldSystemFontOfSize:13];
    [col addArrangedSubview:header];

    [col addArrangedSubview:[self makeCheckbox:L(@"Hide dotfiles by default")
                                           key:@"prefHideDotfilesDefault" defaultOn:YES]];
    [col addArrangedSubview:[self makeCheckbox:L(@"Restore last-open paths at launch")
                                           key:@"prefRestoreLastPaths" defaultOn:YES]];
    [col addArrangedSubview:[self makeCheckbox:L(@"Open dual-pane at launch")
                                           key:@"prefDualPaneStartup" defaultOn:YES]];
    [col addArrangedSubview:[self makeCheckbox:L(@"Show Button Bank at launch")
                                           key:@"prefButtonBankVisible" defaultOn:YES]];

    NSTextField *deleteHeader = [NSTextField labelWithString:L(@"File operations")];
    deleteHeader.font = [NSFont boldSystemFontOfSize:13];
    [col addArrangedSubview:deleteHeader];

    [col addArrangedSubview:[self makeCheckbox:L(@"Delete sends items to Trash (recommended)")
                                           key:@"prefDeleteToTrash" defaultOn:YES]];

    NSTextField *remoteHeader = [NSTextField labelWithString:L(@"Remote transfers (rclone)")];
    remoteHeader.font = [NSFont boldSystemFontOfSize:13];
    [col addArrangedSubview:remoteHeader];

    [col addArrangedSubview:[self makeStepperWithLabel:L(@"Parallel file transfers:")
                                                  key:@"rcloneTransfers"
                                              defaultValue:8
                                                  min:1 max:32]];
    [col addArrangedSubview:[self makeStepperWithLabel:L(@"Streams per large file:")
                                                  key:@"rcloneMultiThreadStreams"
                                              defaultValue:8
                                                  min:1 max:32]];
    NSTextField *hint = [NSTextField wrappingLabelWithString:
        L(@"Defaults tuned for Wi-Fi 5 / Wi-Fi 6 Macs. Raise if your link is faster than transfers × speed; lower if the server gets overloaded.")];
    hint.textColor = [NSColor secondaryLabelColor];
    hint.font = [NSFont systemFontOfSize:11];
    [col addArrangedSubview:hint];

    /* Footer: Reset button */
    NSButton *reset = [NSButton buttonWithTitle:L(@"Reset All Preferences…")
                                         target:self
                                         action:@selector(resetAction:)];
    reset.bezelStyle = NSBezelStyleRounded;
    [col addArrangedSubview:reset];

    [NSLayoutConstraint activateConstraints:@[
        [col.leadingAnchor  constraintEqualToAnchor:c.leadingAnchor  constant:20],
        [col.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-20],
        [col.topAnchor      constraintEqualToAnchor:c.topAnchor      constant:20],
        [col.bottomAnchor   constraintLessThanOrEqualToAnchor:c.bottomAnchor constant:-20],
    ]];

    return self;
}

- (NSButton *)makeCheckbox:(NSString *)title key:(NSString *)key defaultOn:(BOOL)defaultOn {
    NSButton *b = [NSButton checkboxWithTitle:title target:self action:@selector(toggleChanged:)];
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    id stored = [u objectForKey:key];
    BOOL on = stored ? [stored boolValue] : defaultOn;
    b.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    objc_setAssociatedObject(b, "prefKey", key, OBJC_ASSOCIATION_COPY);
    return b;
}

- (void)toggleChanged:(NSButton *)sender {
    NSString *key = objc_getAssociatedObject(sender, "prefKey");
    if (!key) return;
    [[NSUserDefaults standardUserDefaults] setBool:(sender.state == NSControlStateValueOn) forKey:key];
}

/* Label + number field + stepper in a horizontal row, bound to an integer
 * NSUserDefaults key. Used for rclone transfer tuning where 1–32 is the
 * useful range. */
- (NSView *)makeStepperWithLabel:(NSString *)title
                             key:(NSString *)key
                    defaultValue:(NSInteger)defaultVal
                             min:(NSInteger)minV max:(NSInteger)maxV {
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    NSInteger current = [u integerForKey:key];
    if (current <= 0) current = defaultVal;

    NSView *row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *lbl = [NSTextField labelWithString:title];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:lbl];

    NSTextField *field = [[NSTextField alloc] init];
    field.integerValue = current;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:field];

    NSStepper *stepper = [[NSStepper alloc] init];
    stepper.minValue = minV; stepper.maxValue = maxV;
    stepper.integerValue = current;
    stepper.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:stepper];

    objc_setAssociatedObject(stepper, "prefKey", key, OBJC_ASSOCIATION_COPY);
    objc_setAssociatedObject(field,   "prefKey", key, OBJC_ASSOCIATION_COPY);
    objc_setAssociatedObject(stepper, "pairField",   field, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(field,   "pairStepper", stepper, OBJC_ASSOCIATION_ASSIGN);

    stepper.target = self;
    stepper.action = @selector(stepperChanged:);
    field.target = self;
    field.action = @selector(stepperFieldChanged:);

    [NSLayoutConstraint activateConstraints:@[
        [lbl.leadingAnchor  constraintEqualToAnchor:row.leadingAnchor],
        [lbl.centerYAnchor  constraintEqualToAnchor:row.centerYAnchor],
        [field.leadingAnchor constraintEqualToAnchor:lbl.trailingAnchor constant:8],
        [field.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [field.widthAnchor   constraintEqualToConstant:50],
        [stepper.leadingAnchor constraintEqualToAnchor:field.trailingAnchor constant:4],
        [stepper.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [stepper.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor],
        [row.heightAnchor constraintEqualToConstant:24],
    ]];
    return row;
}

- (void)stepperChanged:(NSStepper *)sender {
    NSString *key = objc_getAssociatedObject(sender, "prefKey");
    NSTextField *field = objc_getAssociatedObject(sender, "pairField");
    field.integerValue = sender.integerValue;
    [[NSUserDefaults standardUserDefaults] setInteger:sender.integerValue forKey:key];
}

- (void)stepperFieldChanged:(NSTextField *)sender {
    NSString *key = objc_getAssociatedObject(sender, "prefKey");
    NSStepper *stepper = objc_getAssociatedObject(sender, "pairStepper");
    NSInteger v = sender.integerValue;
    if (v < stepper.minValue) v = (NSInteger)stepper.minValue;
    if (v > stepper.maxValue) v = (NSInteger)stepper.maxValue;
    sender.integerValue = v;
    stepper.integerValue = v;
    [[NSUserDefaults standardUserDefaults] setInteger:v forKey:key];
}

- (void)resetAction:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Reset all preferences?";
    alert.informativeText = @"Custom buttons, bookmarks, file type actions, hidden columns and all other iDOpus settings will be cleared. This cannot be undone.";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"Reset"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"se.bamsejon.idopus";
    [u removePersistentDomainForName:bundleID];
    [u synchronize];

    [self.window close];

    NSAlert *done = [[NSAlert alloc] init];
    done.messageText = @"Preferences reset";
    done.informativeText = @"Quit iDOpus and relaunch to pick up the defaults.";
    [done addButtonWithTitle:@"OK"];
    [done runModal];
}

@end

#pragma mark - App Delegate

@implementation IDOpusAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _bufferCache = buffer_cache_create(20);
    _listerControllers = [NSMutableArray array];

    [self createMainMenu];

    /* Default layout: Button Bank in the middle, two Listers flanking it.
     * Matches classic DOpus Magellan "buttons between listers" arrangement. */
    NSRect screen = [[NSScreen mainScreen] visibleFrame];
    CGFloat totalW = MIN(1400, screen.size.width - 100);
    CGFloat h = MIN(800, screen.size.height - 100);
    CGFloat bankW = [ButtonBankPanelController desiredWidth];
    CGFloat listerW = floor((totalW - bankW) / 2);
    CGFloat x = screen.origin.x + (screen.size.width  - totalW) / 2;
    CGFloat y = screen.origin.y + (screen.size.height - h) / 2;

    NSRect leftFrame  = NSMakeRect(x,                       y, listerW, h);
    NSRect bankFrame  = NSMakeRect(x + listerW,             y, bankW,   h);
    NSRect rightFrame = NSMakeRect(x + listerW + bankW,     y, listerW, h);

    /* Startup preferences */
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    BOOL restore  = [u objectForKey:@"prefRestoreLastPaths"]  ? [u boolForKey:@"prefRestoreLastPaths"]  : YES;
    BOOL dualPane = [u objectForKey:@"prefDualPaneStartup"]   ? [u boolForKey:@"prefDualPaneStartup"]   : YES;
    BOOL showBank = [u objectForKey:@"prefButtonBankVisible"] ? [u boolForKey:@"prefButtonBankVisible"] : YES;

    NSFileManager *fileMgr = [NSFileManager defaultManager];
    /* New format: lastListerStates = [{path, remoteSpec?, remoteLabel?}, ...].
     * Old format: lastPaths = [path, path]. Fall back to the old key so
     * existing users keep their restored state without reconfiguration. */
    NSArray *lastStates = restore ? [u arrayForKey:@"lastListerStates"] : nil;
    if (!lastStates) {
        NSArray *oldPaths = restore ? [u arrayForKey:@"lastPaths"] : nil;
        NSMutableArray *converted = [NSMutableArray array];
        for (NSString *p in oldPaths) {
            if ([p isKindOfClass:[NSString class]]) [converted addObject:@{@"path": p}];
        }
        lastStates = converted;
    }

    NSDictionary *leftState = lastStates.count >= 1 ? lastStates[0] : nil;
    NSDictionary *rightState = lastStates.count >= 2 ? lastStates[1] : nil;

    NSString *leftPath  = [self _startupPathForState:leftState fileManager:fileMgr];
    NSString *rightPath = [self _startupPathForState:rightState fileManager:fileMgr];
    (void)bankFrame;

    if (dualPane) {
        ListerWindowController *left  = [self newListerWindow:leftPath  frame:leftFrame];
        ListerWindowController *right = [self newListerWindow:rightPath frame:rightFrame];
        [left.window setFrame:leftFrame display:YES animate:NO];
        [right.window setFrame:rightFrame display:YES animate:NO];
        [self _restoreRemoteIfNeeded:left fromState:leftState];
        [self _restoreRemoteIfNeeded:right fromState:rightState];

        _buttonBankPanel = [[ButtonBankPanelController alloc] initWithAppDelegate:self];
        [_buttonBankPanel positionBetweenLeftFrame:leftFrame rightFrame:rightFrame];
        [right.window makeKeyAndOrderFront:nil];
        [self attachButtonBankToSource];
        if (showBank) [_buttonBankPanel.window orderFront:nil];
        [self enforceBankBetweenListers];
    } else {
        NSRect single = NSMakeRect(x, y, totalW, h);
        ListerWindowController *one = [self newListerWindow:leftPath frame:single];
        [one.window setFrame:single display:YES animate:NO];
        [self _restoreRemoteIfNeeded:one fromState:leftState];

        _buttonBankPanel = [[ButtonBankPanelController alloc] initWithAppDelegate:self];
        [one.window makeKeyAndOrderFront:nil];
        [self attachButtonBankToSource];
        if (showBank) [_buttonBankPanel.window orderFront:nil];
    }
}

/* Pick the startup path for a Lister. For remote state, use root-of-remote
 * (the path load happens after remoteSpec is attached via _restoreRemoteIfNeeded).
 * For local state, use the saved path only if it still exists; otherwise home. */
- (NSString *)_startupPathForState:(NSDictionary *)s fileManager:(NSFileManager *)fm {
    if (!s) return NSHomeDirectory();
    NSString *spec = s[@"remoteSpec"];
    NSString *path = s[@"path"] ?: @"/";
    if (spec.length) return path;  /* remote — skip local fileExists check */
    if (path.length && [fm fileExistsAtPath:path]) return path;
    return NSHomeDirectory();
}

/* If the saved state was a remote Lister, re-attach the rclone spec and
 * reload via loadRemotePath so the window picks up where it left off. No
 * password is stored — rclone falls back to ssh-agent/keys for SFTP and
 * guest or Keychain for SMB, which is fine for the common case. If auth
 * fails we just show an error and the user reconnects manually. */
- (void)_restoreRemoteIfNeeded:(ListerWindowController *)lw
                     fromState:(NSDictionary *)s {
    NSString *spec = s[@"remoteSpec"];
    if (!spec.length) return;
    lw.remoteSpec  = spec;
    lw.remoteLabel = s[@"remoteLabel"] ?: @"remote";
    [lw.history removeAllObjects];
    lw.historyIndex = -1;
    [lw loadRemotePath:s[@"path"] ?: @"/"];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    /* Save each Lister's path + remote metadata so next launch can restore
     * both local folders and remote connections. Note: the remoteSpec
     * already contains the obscured password for SFTP, so saving it in
     * NSUserDefaults effectively persists the password too. That matches
     * the user's expectation of "reconnect automatically" but is a mild
     * security tradeoff vs. the original session-only storage. */
    NSMutableArray<NSDictionary *> *states = [NSMutableArray array];
    NSMutableArray<NSString *> *pathsLegacy = [NSMutableArray array];
    for (ListerWindowController *lw in _listerControllers) {
        if (!lw.currentPath) continue;
        NSMutableDictionary *s = [@{ @"path": lw.currentPath } mutableCopy];
        if (lw.remoteSpec.length)  s[@"remoteSpec"]  = lw.remoteSpec;
        if (lw.remoteLabel.length) s[@"remoteLabel"] = lw.remoteLabel;
        [states addObject:s];
        if (!lw.isRemote) [pathsLegacy addObject:lw.currentPath];
    }
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    if (states.count > 0) {
        [u setObject:states forKey:@"lastListerStates"];
        /* Keep the legacy key in sync for downgrades. */
        [u setObject:pathsLegacy forKey:@"lastPaths"];
    }

    if (_bufferCache) buffer_cache_free(_bufferCache);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)createMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    /* App menu */
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"iDOpus"];
    [appMenu addItemWithTitle:L(@"About iDOpus") action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *prefsItem = [appMenu addItemWithTitle:L(@"Preferences…")
                                               action:@selector(showPreferencesAction:)
                                        keyEquivalent:@","];
    prefsItem.target = self;
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:L(@"Quit iDOpus") action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [mainMenu addItem:appItem];

    /* File menu */
    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:L(@"File")];
    [fileMenu addItemWithTitle:L(@"New Lister") action:@selector(newListerAction:) keyEquivalent:@"n"];
    NSMenuItem *newFileMenu = [fileMenu addItemWithTitle:L(@"New File…")
                                                  action:@selector(newFileAction:)
                                           keyEquivalent:@"n"];
    newFileMenu.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [fileMenu addItemWithTitle:L(@"New Tab")
                        action:@selector(newTabAction:)
                 keyEquivalent:@"t"];
    NSMenuItem *splitItem = [fileMenu addItemWithTitle:L(@"Split Display")
                                                action:@selector(splitDisplayAction:)
                                         keyEquivalent:@"N"];
    splitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:L(@"Back")    action:@selector(goBack:)    keyEquivalent:@"["];
    [fileMenu addItemWithTitle:L(@"Forward") action:@selector(goForward:) keyEquivalent:@"]"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:L(@"Find")      action:@selector(performFindPanelAction:) keyEquivalent:@"f"];
    NSMenuItem *gotoItem = [fileMenu addItemWithTitle:L(@"Go to Path…")
                                               action:@selector(goToPathAction:)
                                        keyEquivalent:@"l"];
    gotoItem.target = self;
    [fileMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *connectItem = [fileMenu addItemWithTitle:L(@"Connect to Server…")
                                                   action:@selector(connectToServerAction:)
                                            keyEquivalent:@"k"];
    connectItem.target = self;
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:L(@"Close") action:@selector(performClose:) keyEquivalent:@"w"];
    fileItem.submenu = fileMenu;
    [mainMenu addItem:fileItem];

    /* Functions menu — matches DOpus F-key bindings */
    NSMenuItem *funcItem = [[NSMenuItem alloc] init];
    NSMenu *funcMenu = [[NSMenu alloc] initWithTitle:L(@"Functions")];
    [self addFunctionItem:funcMenu title:L(@"Rename")  action:@selector(renameAction:)  fkey:NSF3FunctionKey];
    [self addFunctionItem:funcMenu title:L(@"Copy")    action:@selector(copyAction:)    fkey:NSF5FunctionKey];
    [self addFunctionItem:funcMenu title:L(@"Move")    action:@selector(moveAction:)    fkey:NSF6FunctionKey];
    [self addFunctionItem:funcMenu title:L(@"MakeDir") action:@selector(makeDirAction:) fkey:NSF7FunctionKey];
    [self addFunctionItem:funcMenu title:L(@"Delete")  action:@selector(deleteAction:)  fkey:NSF8FunctionKey];
    [self addFunctionItem:funcMenu title:L(@"Info")    action:@selector(infoAction:)    fkey:NSF9FunctionKey];
    [funcMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *filterItem = [funcMenu addItemWithTitle:L(@"Filter…")
                                                 action:@selector(filterAction:)
                                          keyEquivalent:@"f"];
    filterItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    NSMenuItem *selectItem = [funcMenu addItemWithTitle:L(@"Select By Pattern…")
                                                 action:@selector(selectPatternAction:)
                                          keyEquivalent:@"a"];
    selectItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [funcMenu addItemWithTitle:L(@"Compare With Destination")
                        action:@selector(compareSourceWithDestAction:)
                 keyEquivalent:@""];
    [funcMenu addItem:[NSMenuItem separatorItem]];
    [funcMenu addItemWithTitle:L(@"Add Custom Button…")    action:@selector(addCustomButtonAction:)    keyEquivalent:@""];
    [funcMenu addItemWithTitle:L(@"Edit Custom Button…")   action:@selector(editCustomButtonAction:)   keyEquivalent:@""];
    [funcMenu addItemWithTitle:L(@"Remove Custom Button…") action:@selector(removeCustomButtonAction:) keyEquivalent:@""];
    [funcMenu addItem:[NSMenuItem separatorItem]];
    [funcMenu addItemWithTitle:L(@"Add File Type Action…")    action:@selector(addFileTypeActionAction:)    keyEquivalent:@""];
    [funcMenu addItemWithTitle:L(@"Remove File Type Action…") action:@selector(manageFileTypeActionsAction:) keyEquivalent:@""];

    /* Sync submenu (rsync) */
    [funcMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *syncItem = [funcMenu addItemWithTitle:L(@"Sync") action:NULL keyEquivalent:@""];
    NSMenu *syncSub = [[NSMenu alloc] initWithTitle:L(@"Sync")];
    syncSub.delegate = self;      /* rebuild with saved profiles on open */
    syncSub.autoenablesItems = NO;
    syncItem.submenu = syncSub;
    funcItem.submenu = funcMenu;
    [mainMenu addItem:funcItem];

    /* Bookmarks menu */
    NSMenuItem *bmItem = [[NSMenuItem alloc] init];
    NSMenu *bmMenu = [[NSMenu alloc] initWithTitle:L(@"Bookmarks")];
    bmMenu.autoenablesItems = NO;
    bmMenu.delegate = self;     /* rebuild on open */
    bmItem.submenu = bmMenu;
    [mainMenu addItem:bmItem];

    /* Window menu */
    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:L(@"Window")];
    [windowMenu addItemWithTitle:L(@"Minimize") action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:L(@"Zoom") action:@selector(performZoom:) keyEquivalent:@""];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:L(@"Bring All to Front") action:@selector(arrangeInFront:) keyEquivalent:@""];
    windowItem.submenu = windowMenu;
    [mainMenu addItem:windowItem];
    [NSApp setWindowsMenu:windowMenu];

    /* View menu */
    NSMenuItem *viewItem = [[NSMenuItem alloc] init];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:L(@"View")];
    [viewMenu addItemWithTitle:L(@"Show Hidden Files") action:@selector(toggleHidden:) keyEquivalent:@"."];

    /* Sort By submenu */
    NSMenuItem *sortItem = [viewMenu addItemWithTitle:L(@"Sort By") action:NULL keyEquivalent:@""];
    NSMenu *sortSub = [[NSMenu alloc] initWithTitle:L(@"Sort By")];
    struct { NSString *title; int field; } sorts[] = {
        { L(@"Name"),      SORT_NAME      },
        { L(@"Size"),      SORT_SIZE      },
        { L(@"Date"),      SORT_DATE      },
        { L(@"Type"),      SORT_EXTENSION },
    };
    for (size_t i = 0; i < sizeof(sorts)/sizeof(sorts[0]); i++) {
        NSMenuItem *mi = [sortSub addItemWithTitle:sorts[i].title
                                            action:@selector(sortByAction:)
                                     keyEquivalent:@""];
        mi.tag = sorts[i].field;
    }
    [sortSub addItem:[NSMenuItem separatorItem]];
    [sortSub addItemWithTitle:L(@"Reverse")      action:@selector(toggleReverseSortAction:) keyEquivalent:@""];
    [sortSub addItemWithTitle:L(@"Files Mixed")  action:@selector(toggleFilesMixedAction:) keyEquivalent:@""];
    sortItem.submenu = sortSub;

    /* Show Columns submenu */
    NSMenuItem *colsItem = [viewMenu addItemWithTitle:L(@"Show Columns") action:NULL keyEquivalent:@""];
    NSMenu *colsSub = [[NSMenu alloc] initWithTitle:L(@"Show Columns")];
    colsSub.autoenablesItems = NO;
    NSArray<NSString *> *colIds = @[@"name", @"size", @"date", @"type"];
    NSArray<NSString *> *colTitles = @[L(@"Name"), L(@"Size"), L(@"Date"), L(@"Type")];
    NSSet<NSString *> *hidden = [NSSet setWithArray:
        ([[NSUserDefaults standardUserDefaults] arrayForKey:@"hiddenColumns"] ?: @[])];
    for (NSUInteger i = 0; i < colIds.count; i++) {
        NSMenuItem *mi = [colsSub addItemWithTitle:colTitles[i]
                                            action:@selector(toggleColumnVisibility:)
                                     keyEquivalent:@""];
        mi.representedObject = colIds[i];
        mi.state = [hidden containsObject:colIds[i]] ? NSControlStateValueOff : NSControlStateValueOn;
        if ([colIds[i] isEqualToString:@"name"]) mi.enabled = NO;
    }
    colsItem.submenu = colsSub;

    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *qlItem = [viewMenu addItemWithTitle:L(@"Quick Look")
                                             action:@selector(toggleQuickLook:)
                                      keyEquivalent:@" "];
    qlItem.keyEquivalentModifierMask = 0;
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:L(@"Show/Hide Buttons") action:@selector(toggleButtonBank:) keyEquivalent:@"b"];
    viewItem.submenu = viewMenu;
    [mainMenu addItem:viewItem];

    [NSApp setMainMenu:mainMenu];
}

- (void)addFunctionItem:(NSMenu *)menu title:(NSString *)title action:(SEL)action fkey:(unichar)fkey {
    NSString *key = [NSString stringWithCharacters:&fkey length:1];
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:key];
    item.keyEquivalentModifierMask = 0;  /* bare F-key, matching DOpus */
}

/* New Tab: open another Lister at the current source's path and attach it
 * as a native macOS window tab to the current window. Falls back to a
 * standalone window if there's no key Lister to attach to. */
- (void)newTabAction:(id)sender {
    ListerWindowController *current = (ListerWindowController *)[NSApp keyWindow].windowController;
    if (![current isKindOfClass:[ListerWindowController class]]) {
        current = _activeSource ?: _listerControllers.lastObject;
    }
    if (!current) { [self newListerAction:sender]; return; }

    ListerWindowController *newCtrl = [self newListerWindow:current.currentPath
                                                      frame:current.window.frame];
    [current.window addTabbedWindow:newCtrl.window ordered:NSWindowAbove];
    [newCtrl.window makeKeyAndOrderFront:nil];
}

- (void)newListerAction:(id)sender {
    NSRect frame = NSMakeRect(100 + _listerControllers.count * 20,
                              400 - _listerControllers.count * 20,
                              700, 500);
    [self newListerWindow:NSHomeDirectory() frame:frame];
}

/* Split Display — original DOpus: halves the current lister's space,
 * opens a second lister tiled alongside. Horizontal split if wider than tall.
 * Both windows share an edge exactly — no overlap, no gap. */
- (void)splitDisplayAction:(id)sender {
    ListerWindowController *current = (ListerWindowController *)
        [NSApp keyWindow].windowController;
    if (![current isKindOfClass:[ListerWindowController class]]) {
        current = _activeSource ?: _listerControllers.lastObject;
    }
    if (!current) {
        [self newListerAction:sender];
        return;
    }

    NSRect frame = current.window.frame;
    NSRect leftOrTop, rightOrBottom;
    if (frame.size.width >= frame.size.height) {
        /* Horizontal split: round to whole pixels so edges meet exactly */
        CGFloat half = floor(frame.size.width / 2.0);
        leftOrTop     = NSMakeRect(frame.origin.x,        frame.origin.y, half,                     frame.size.height);
        rightOrBottom = NSMakeRect(frame.origin.x + half, frame.origin.y, frame.size.width - half,  frame.size.height);
    } else {
        /* Vertical split */
        CGFloat half = floor(frame.size.height / 2.0);
        leftOrTop     = NSMakeRect(frame.origin.x, frame.origin.y + (frame.size.height - half), frame.size.width, half);
        rightOrBottom = NSMakeRect(frame.origin.x, frame.origin.y,                              frame.size.width, frame.size.height - half);
    }

    [current.window setFrame:leftOrTop display:YES animate:NO];

    ListerWindowController *new = [self newListerWindow:current.currentPath frame:rightOrBottom];
    /* initWithContentRect: treats frame as content rect — set the full frame after creation
     * so both windows use identical frame semantics and meet exactly. */
    [new.window setFrame:rightOrBottom display:YES animate:NO];
}

- (ListerWindowController *)newListerWindow:(NSString *)path frame:(NSRect)frame {
    ListerWindowController *ctrl = [[ListerWindowController alloc] initWithPath:path
                                                                          frame:frame
                                                                    appDelegate:self];
    [_listerControllers addObject:ctrl];
    [ctrl showWindow:self];
    /* Match original DOpus: new Listers are created with LISTERF_MAKE_SOURCE —
     * promote unconditionally rather than relying on window key-focus notifications. */
    [self promoteToSource:ctrl];
    return ctrl;
}

/* Promote a Lister to SOURCE. Previous source becomes DEST (unless already a dest
 * elsewhere). Globally at most one SOURCE and one DEST. Mirrors lister_check_source()
 * + lister_check_dest() in original lister_activate.c. */
- (void)promoteToSource:(ListerWindowController *)newSource {
    if (!newSource || newSource.state == ListerStateSource) return;

    ListerWindowController *prevSource = _activeSource;
    ListerWindowController *prevDest = _activeDest;

    /* Case: new source was the dest — its slot becomes free */
    if (prevDest == newSource) {
        _activeDest = nil;
        prevDest = nil;
    }

    /* Promote */
    [newSource setState:ListerStateSource];
    _activeSource = newSource;

    /* Old source → becomes new DEST (unless we already have a different dest) */
    if (prevSource && prevSource != newSource) {
        if (!prevDest) {
            [prevSource setState:ListerStateDest];
            _activeDest = prevSource;
        } else {
            [prevSource setState:ListerStateOff];
        }
    }

    [self attachButtonBankToSource];
    [self refreshButtonBankEnablement];
}

- (void)listerClosing:(ListerWindowController *)ctrl {
    if (_activeSource == ctrl) _activeSource = nil;
    if (_activeDest == ctrl) _activeDest = nil;
    [_listerControllers removeObject:ctrl];
    [self attachButtonBankToSource];
    [self refreshButtonBankEnablement];
}

- (void)showPreferencesAction:(id)sender {
    if (!_preferencesWindow) {
        _preferencesWindow = [[PreferencesWindowController alloc] initWithAppDelegate:self];
    }
    [_preferencesWindow.window center];
    [_preferencesWindow.window makeKeyAndOrderFront:sender];
}

#pragma mark Unified Button Bank actions (operate on active SOURCE)

/* Operations that target a single Lister — fall back to activeSource when
 * invoked from the floating Button Bank panel (which is non-activating, so
 * the source Lister keeps its SOURCE state while the user clicks the panel). */
- (ListerWindowController *)sourceOrOperating {
    return _activeSource ?: [self operatingLister];
}

- (void)parentAction:(id)sender  { [[self sourceOrOperating] goUp:sender]; }
- (void)rootAction:(id)sender    { [[self sourceOrOperating] goRoot:sender]; }
- (void)refreshAction:(id)sender { [[self sourceOrOperating] refresh:sender]; }
- (void)allAction:(id)sender     { [[self sourceOrOperating] selectAllFiles:sender]; }
- (void)noneAction:(id)sender    { [[self sourceOrOperating] deselectAllFiles:sender]; }

#pragma mark Bookmarks

/* Standard system locations, plus user additions persisted to NSUserDefaults.
 * User additions are stored as an NSArray of NSDictionary{name, path} under
 * "bookmarks" in standardUserDefaults. */
- (NSArray<NSDictionary *> *)builtInBookmarks {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSNumber *> *dirs = @[ @(NSDesktopDirectory), @(NSDocumentDirectory),
                                    @(NSDownloadsDirectory), @(NSApplicationDirectory),
                                    @(NSPicturesDirectory), @(NSMoviesDirectory),
                                    @(NSMusicDirectory) ];
    NSArray<NSString *> *names = @[ L(@"Desktop"), L(@"Documents"), L(@"Downloads"),
                                     L(@"Applications"), L(@"Pictures"), L(@"Movies"), L(@"Music") ];
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    [out addObject:@{ @"name": L(@"Home"), @"path": NSHomeDirectory() }];
    for (NSUInteger i = 0; i < dirs.count; i++) {
        NSArray<NSURL *> *u = [fm URLsForDirectory:dirs[i].unsignedIntegerValue
                                         inDomains:NSUserDomainMask];
        if (u.count > 0) [out addObject:@{ @"name": names[i], @"path": u.firstObject.path }];
    }
    return out;
}

- (NSArray<NSDictionary *> *)userBookmarks {
    return [[NSUserDefaults standardUserDefaults] arrayForKey:@"bookmarks"] ?: @[];
}

- (void)setUserBookmarks:(NSArray<NSDictionary *> *)bookmarks {
    [[NSUserDefaults standardUserDefaults] setObject:bookmarks forKey:@"bookmarks"];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    /* Sync submenu — rebuild with saved rsync profiles */
    if ([menu.title isEqualToString:L(@"Sync")]) {
        [menu removeAllItems];
        NSMenuItem *sync = [menu addItemWithTitle:L(@"Sync Source → Dest…")
                                           action:@selector(syncSourceToDestAction:)
                                    keyEquivalent:@""];
        sync.target = self;

        NSArray<NSDictionary *> *profiles = [[NSUserDefaults standardUserDefaults]
                                              arrayForKey:@"rsyncProfiles"] ?: @[];
        if (profiles.count > 0) {
            [menu addItem:[NSMenuItem separatorItem]];
            NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:@"Saved profiles"
                                                            action:NULL
                                                     keyEquivalent:@""];
            header.enabled = NO;
            [menu addItem:header];
            for (NSDictionary *p in profiles) {
                NSString *t = p[@"name"] ?: [NSString stringWithFormat:@"%@ → %@",
                                             p[@"source"], p[@"dest"]];
                if ([p[@"dryRun"] boolValue]) t = [NSString stringWithFormat:@"%@ (dry run)", t];
                NSMenuItem *it = [menu addItemWithTitle:t
                                                 action:@selector(runSyncProfile:)
                                          keyEquivalent:@""];
                it.target = self;
                it.representedObject = p;
            }
        }
        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *add = [menu addItemWithTitle:L(@"Add Sync Profile…")
                                          action:@selector(addSyncProfileAction:)
                                   keyEquivalent:@""];
        add.target = self;
        if (profiles.count > 0) {
            NSMenuItem *rm = [menu addItemWithTitle:L(@"Remove Sync Profile…")
                                             action:@selector(removeSyncProfileAction:)
                                      keyEquivalent:@""];
            rm.target = self;
        }
        return;
    }

    /* Bookmarks submenu */
    if (![menu.title isEqualToString:L(@"Bookmarks")]) return;
    [menu removeAllItems];

    for (NSDictionary *bm in [self builtInBookmarks]) {
        NSMenuItem *it = [menu addItemWithTitle:bm[@"name"]
                                         action:@selector(navigateToBookmark:)
                                  keyEquivalent:@""];
        it.representedObject = bm[@"path"];
        it.target = self;
    }

    NSArray<NSDictionary *> *userBm = [self userBookmarks];
    if (userBm.count > 0) {
        [menu addItem:[NSMenuItem separatorItem]];
        for (NSDictionary *bm in userBm) {
            NSMenuItem *it = [menu addItemWithTitle:bm[@"name"] ?: bm[@"path"]
                                             action:@selector(navigateToBookmark:)
                                      keyEquivalent:@""];
            it.representedObject = bm[@"path"];
            it.target = self;
        }
    }

    /* Mounted volumes (DOpus "Devices") — only user-browsable ones.
     * NSVolumeEnumerationSkipHiddenVolumes filters out APFS system
     * containers like /System/Volumes/VM, Preboot, xarts, etc. */
    NSArray<NSURL *> *volUrls = [[NSFileManager defaultManager]
        mountedVolumeURLsIncludingResourceValuesForKeys:@[NSURLVolumeNameKey,
                                                          NSURLVolumeTotalCapacityKey,
                                                          NSURLVolumeIsBrowsableKey]
                                                options:NSVolumeEnumerationSkipHiddenVolumes];
    NSMutableArray<NSURL *> *userVols = [NSMutableArray array];
    for (NSURL *u in volUrls) {
        NSNumber *browsable = nil;
        [u getResourceValue:&browsable forKey:NSURLVolumeIsBrowsableKey error:nil];
        if (browsable.boolValue) [userVols addObject:u];
    }
    if (userVols.count > 0) {
        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:L(@"Devices") action:NULL keyEquivalent:@""];
        header.enabled = NO;
        [menu addItem:header];
        for (NSURL *u in userVols) {
            NSString *name = nil;
            NSNumber *cap = nil;
            [u getResourceValue:&name forKey:NSURLVolumeNameKey error:nil];
            [u getResourceValue:&cap forKey:NSURLVolumeTotalCapacityKey error:nil];
            char szBuf[32]; pal_format_size(cap.unsignedLongLongValue, szBuf, sizeof(szBuf));
            NSString *title = [NSString stringWithFormat:@"  %@ (%s)",
                               name ?: u.path.lastPathComponent, szBuf];
            NSMenuItem *it = [menu addItemWithTitle:title
                                             action:@selector(navigateToBookmark:)
                                      keyEquivalent:@""];
            it.representedObject = u.path;
            it.target = self;
        }
    }

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *add = [menu addItemWithTitle:L(@"Add Current…")
                                      action:@selector(addCurrentBookmark:)
                               keyEquivalent:@"d"];
    add.target = self;

    if (userBm.count > 0) {
        NSMenuItem *rm = [menu addItemWithTitle:L(@"Remove Bookmark…")
                                         action:@selector(removeBookmark:)
                                  keyEquivalent:@""];
        rm.target = self;
    }
}

- (void)navigateToBookmark:(NSMenuItem *)sender {
    NSString *path = sender.representedObject;
    ListerWindowController *target = [self sourceOrOperating];
    if (!target || !path) return;
    [target loadPath:path];
}

- (void)addCurrentBookmark:(id)sender {
    ListerWindowController *src = [self sourceOrOperating];
    if (!src) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Add Bookmark";
    alert.informativeText = [NSString stringWithFormat:@"Path: %@", src.currentPath];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    input.stringValue = src.currentPath.lastPathComponent;
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"Add"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert.window setInitialFirstResponder:input];
    [input selectText:nil];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *name = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (name.length == 0) return;

    NSMutableArray *bms = [[self userBookmarks] mutableCopy];
    [bms addObject:@{ @"name": name, @"path": src.currentPath }];
    [self setUserBookmarks:bms];
}

- (void)removeBookmark:(id)sender {
    NSArray<NSDictionary *> *bms = [self userBookmarks];
    if (bms.count == 0) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Remove Bookmark";
    alert.informativeText = @"Select which bookmark to remove.";

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 320, 26)];
    for (NSDictionary *bm in bms) {
        [popup addItemWithTitle:[NSString stringWithFormat:@"%@ — %@",
                                 bm[@"name"] ?: @"(unnamed)", bm[@"path"]]];
    }
    alert.accessoryView = popup;
    [alert addButtonWithTitle:@"Remove"];
    [alert addButtonWithTitle:@"Cancel"];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSInteger idx = popup.indexOfSelectedItem;
    if (idx < 0 || idx >= (NSInteger)bms.count) return;
    NSMutableArray *updated = [bms mutableCopy];
    [updated removeObjectAtIndex:idx];
    [self setUserBookmarks:updated];
}

- (void)toggleQuickLook:(id)sender {
    QLPreviewPanel *panel = [QLPreviewPanel sharedPreviewPanel];
    if (panel.isVisible) {
        [panel orderOut:nil];
    } else {
        /* Make the key Lister window the first responder chain root for the panel.
         * QLPreviewPanel will query the responder chain for acceptsPreviewPanelControl:,
         * which our ListerWindowController answers YES. */
        [panel makeKeyAndOrderFront:nil];
    }
}

- (void)toggleButtonBank:(id)sender {
    if (!_buttonBankPanel) return;
    NSWindow *w = _buttonBankPanel.window;
    if (w.isVisible) [w orderOut:nil];
    else {
        [self attachButtonBankToSource];
        if (!w.isVisible) [w orderFront:nil];
    }
}

/* Re-parent the Button Bank panel as a child window of the current SOURCE.
 * Must run every time the SOURCE changes so the bank tracks move/minimize/z-order
 * with the Lister it serves. No-ops cleanly if no SOURCE is available yet. */
- (void)attachButtonBankToSource {
    if (!_buttonBankPanel) return;
    NSWindow *bank = _buttonBankPanel.window;
    ListerWindowController *host = _activeSource ?: _activeDest ?: _listerControllers.lastObject;
    NSWindow *newParent = host.window;
    NSWindow *oldParent = bank.parentWindow;
    if (oldParent == newParent) return;
    if (oldParent) [oldParent removeChildWindow:bank];
    if (newParent) [newParent addChildWindow:bank ordered:NSWindowAbove];
}

/* Info — DOpus "Read Info". Single selection: show all properties.
 * Multi-selection: show aggregate count and total size. */
- (void)infoAction:(id)sender {
    ListerWindowController *src = [self operatingLister];
    if (!src) return;
    NSArray<NSString *> *paths = [src selectedPaths];
    NSArray<NSString *> *names = [src selectedNames];
    if (paths.count == 0) {
        [self showAlert:@"Info" info:@"No items selected." style:NSAlertStyleInformational];
        return;
    }

    /* Quick check: are any of the selected items directories? If so, compute
     * recursive size on a background queue with a busy sheet; otherwise no
     * background work needed. */
    BOOL anyDir = NO;
    for (NSString *p in paths) {
        struct stat st;
        if (lstat(p.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode)) { anyDir = YES; break; }
    }

    if (!anyDir) {
        [self showInfoAlertWithPaths:paths names:names sizes:nil];
        return;
    }

    /* Show a busy sheet while we walk the trees */
    NSWindow *sheet = [self makeBusySheetWithTitle:@"Calculating size…"
                                        onWindow:src.window];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableArray<NSNumber *> *sizes = [NSMutableArray arrayWithCapacity:paths.count];
        for (NSString *p in paths) [sizes addObject:@([self recursiveSizeOfPath:p])];

        dispatch_async(dispatch_get_main_queue(), ^{
            [src.window endSheet:sheet];
            [self showInfoAlertWithPaths:paths names:names sizes:sizes];
        });
    });
}

- (void)showInfoAlertWithPaths:(NSArray<NSString *> *)paths
                         names:(NSArray<NSString *> *)names
                         sizes:(NSArray<NSNumber *> *)precomputedSizes {
    NSAlert *alert = [[NSAlert alloc] init];

    if (paths.count == 1) {
        alert.messageText = [NSString stringWithFormat:@"Info — %@", names[0]];
        NSString *baseInfo = [self infoTextForPath:paths[0]];
        if (precomputedSizes.count == 1) {
            uint64_t sz = precomputedSizes[0].unsignedLongLongValue;
            char szBuf[32]; pal_format_size(sz, szBuf, sizeof(szBuf));
            baseInfo = [baseInfo stringByAppendingFormat:
                @"\nRecursive:   %s (%llu bytes)", szBuf, (unsigned long long)sz];
        }
        alert.informativeText = baseInfo;
    } else {
        uint64_t totalBytes = 0;
        int files = 0, dirs = 0, other = 0;
        for (NSUInteger i = 0; i < paths.count; i++) {
            NSString *p = paths[i];
            struct stat st;
            if (lstat(p.fileSystemRepresentation, &st) != 0) { other++; continue; }
            if (S_ISDIR(st.st_mode))      dirs++;
            else if (S_ISREG(st.st_mode)) files++;
            else                          other++;

            if (precomputedSizes && i < precomputedSizes.count) {
                totalBytes += precomputedSizes[i].unsignedLongLongValue;
            } else {
                totalBytes += (uint64_t)st.st_size;
            }
        }
        char sizeBuf[32];
        pal_format_size(totalBytes, sizeBuf, sizeof(sizeBuf));
        alert.messageText = [NSString stringWithFormat:@"Info — %lu items selected",
                             (unsigned long)paths.count];
        alert.informativeText = [NSString stringWithFormat:
            @"%d file%@, %d director%@%@\nTotal size (recursive): %s",
            files, files == 1 ? @"" : @"s",
            dirs,  dirs  == 1 ? @"y" : @"ies",
            other ? [NSString stringWithFormat:@", %d other", other] : @"",
            sizeBuf];
    }

    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

/* Walk a path and return total byte count. For files, returns file size.
 * For directories, recursively sums all contained files. Symlinks not
 * followed. Runs on the calling thread; call from a background queue. */
- (uint64_t)recursiveSizeOfPath:(NSString *)path {
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) return 0;
    if (!S_ISDIR(st.st_mode)) return (uint64_t)st.st_size;

    uint64_t total = 0;
    NSDirectoryEnumerator *en = [[NSFileManager defaultManager]
        enumeratorAtURL:[NSURL fileURLWithPath:path]
        includingPropertiesForKeys:@[NSURLFileSizeKey, NSURLIsRegularFileKey]
        options:NSDirectoryEnumerationSkipsHiddenFiles
        errorHandler:nil];
    for (NSURL *u in en) {
        NSNumber *reg = nil;
        [u getResourceValue:&reg forKey:NSURLIsRegularFileKey error:nil];
        if (!reg.boolValue) continue;
        NSNumber *sz = nil;
        [u getResourceValue:&sz forKey:NSURLFileSizeKey error:nil];
        total += sz.unsignedLongLongValue;
    }
    return total;
}

- (NSWindow *)makeBusySheetWithTitle:(NSString *)title onWindow:(NSWindow *)parent {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 100)
                                              styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    NSView *c = w.contentView;
    NSTextField *lbl = [NSTextField labelWithString:title];
    lbl.font = [NSFont boldSystemFontOfSize:13];
    lbl.alignment = NSTextAlignmentCenter;
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:lbl];

    NSProgressIndicator *spinner = [[NSProgressIndicator alloc] init];
    spinner.style = NSProgressIndicatorStyleSpinning;
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimation:nil];
    [c addSubview:spinner];

    [NSLayoutConstraint activateConstraints:@[
        [lbl.centerXAnchor constraintEqualToAnchor:c.centerXAnchor],
        [lbl.topAnchor constraintEqualToAnchor:c.topAnchor constant:18],
        [spinner.centerXAnchor constraintEqualToAnchor:c.centerXAnchor],
        [spinner.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:10],
        [spinner.widthAnchor constraintEqualToConstant:24],
        [spinner.heightAnchor constraintEqualToConstant:24],
    ]];
    [parent beginSheet:w completionHandler:nil];
    return w;
}

/* Filter — DOpus Show/Hide pattern. Scope: active source Lister.
 * Pattern uses pal_path_match glob syntax (e.g. *.txt, .*, [abc]*).
 * Empty field = no restriction on that direction. */
- (void)filterAction:(id)sender {
    ListerWindowController *src = [self sourceOrOperating];
    if (!src) return;
    ListerDataSource *ds = src.dataSource;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Filter";
    alert.informativeText = @"Glob patterns. Leave blank to clear.";

    NSView *acc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 96)];

    NSTextField *showLabel = [NSTextField labelWithString:@"Show:"];
    showLabel.frame = NSMakeRect(0, 72, 60, 20);
    [acc addSubview:showLabel];
    NSTextField *showField = [[NSTextField alloc] initWithFrame:NSMakeRect(64, 68, 256, 24)];
    showField.stringValue = ds.showPattern ?: @"";
    [acc addSubview:showField];

    NSTextField *hideLabel = [NSTextField labelWithString:@"Hide:"];
    hideLabel.frame = NSMakeRect(0, 40, 60, 20);
    [acc addSubview:hideLabel];
    NSTextField *hideField = [[NSTextField alloc] initWithFrame:NSMakeRect(64, 36, 256, 24)];
    hideField.stringValue = ds.hidePattern ?: @"";
    [acc addSubview:hideField];

    NSButton *dotBox = [NSButton checkboxWithTitle:@"Hide dotfiles (.*)" target:nil action:nil];
    dotBox.frame = NSMakeRect(0, 4, 320, 24);
    dotBox.state = ds.hideDotfiles ? NSControlStateValueOn : NSControlStateValueOff;
    [acc addSubview:dotBox];

    alert.accessoryView = acc;
    [alert addButtonWithTitle:@"Apply"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert.window setInitialFirstResponder:showField];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    ds.showPattern  = [showField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    ds.hidePattern  = [hideField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    ds.hideDotfiles = dotBox.state == NSControlStateValueOn;
    [ds applyCurrentFilter];
    [src updateStatusBar];
}

/* Custom Button Bank buttons — each stores a shell command template.
 * Placeholder {FILES} expands to the SOURCE Lister's current selection
 * (POSIX-escaped, space-separated); {PATH} to the currentPath. */
- (void)runCustomButton:(NSButton *)sender {
    NSString *cmd = objc_getAssociatedObject(sender, "cmd");
    if (!cmd.length) return;
    ListerWindowController *src = [self sourceOrOperating];
    if (!src) return;

    NSArray<NSString *> *paths = [src selectedPaths];
    NSMutableArray<NSString *> *quoted = [NSMutableArray array];
    for (NSString *p in paths) {
        NSString *escaped = [p stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
        [quoted addObject:[NSString stringWithFormat:@"'%@'", escaped]];
    }
    NSString *filesArg = [quoted componentsJoinedByString:@" "];
    NSString *pathArg = [NSString stringWithFormat:@"'%@'",
                         [src.currentPath stringByReplacingOccurrencesOfString:@"'"
                                                                    withString:@"'\\''"]];

    NSString *expanded = [cmd stringByReplacingOccurrencesOfString:@"{FILES}" withString:filesArg];
    expanded = [expanded stringByReplacingOccurrencesOfString:@"{PATH}" withString:pathArg];

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    task.arguments = @[@"-c", expanded];
    task.currentDirectoryURL = [NSURL fileURLWithPath:src.currentPath];
    NSError *err = nil;
    if (![task launchAndReturnError:&err]) {
        [self showAlert:@"Custom button failed" info:err.localizedDescription style:NSAlertStyleWarning];
    }
}

- (NSString *)customButtonHelpText {
    return
        @"Placeholders\n"
        @"   {FILES}   space-separated, quoted paths of the current selection\n"
        @"   {PATH}    the active Lister's directory\n"
        @"\n"
        @"The command runs via /bin/sh -c with the Lister's directory as cwd,\n"
        @"inheriting iDOpus's environment (which is the macOS GUI PATH).\n"
        @"\n"
        @"To open a Mac app reliably, prefer macOS's own /usr/bin/open:\n"
        @"   open -a \"Visual Studio Code\" {FILES}\n"
        @"   open -a TextEdit {FILES}\n"
        @"   open -a Terminal {PATH}\n"
        @"\n"
        @"CLI tools need to be in PATH or referenced by full path:\n"
        @"   /usr/bin/tar czf archive.tar.gz {FILES}\n"
        @"   /opt/homebrew/bin/rg pattern {PATH}\n"
        @"\n"
        @"Anything you can type in Terminal (with quoted filenames already\n"
        @"substituted) works. Remember to quote your own args if they may\n"
        @"contain spaces.";
}

- (void)showCustomButtonHelp:(id)sender {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"Custom Button — How it works";
    a.informativeText = [self customButtonHelpText];
    [a addButtonWithTitle:@"OK"];
    [a runModal];
}

/* Build the shared accessory view used by Add + Edit dialogs. Returns a
 * dictionary with the title/command fields for the caller to read. */
- (NSDictionary *)buildCustomButtonFormWithTitle:(NSString *)initialTitle
                                          command:(NSString *)initialCommand
                                         intoView:(out NSView **)outView {
    NSView *acc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 440, 104)];

    NSTextField *titleLbl = [NSTextField labelWithString:@"Title:"];
    titleLbl.frame = NSMakeRect(0, 78, 72, 20);
    NSTextField *titleField = [[NSTextField alloc] initWithFrame:NSMakeRect(76, 74, 320, 24)];
    titleField.stringValue = initialTitle ?: @"";

    /* Help button (ⓘ) to the right of Title */
    NSButton *helpBtn = [NSButton buttonWithTitle:@""
                                           target:self
                                           action:@selector(showCustomButtonHelp:)];
    helpBtn.bezelStyle = NSBezelStyleHelpButton;
    helpBtn.frame = NSMakeRect(404, 74, 24, 24);
    helpBtn.toolTip = @"How custom buttons work";

    NSTextField *cmdLbl = [NSTextField labelWithString:@"Command:"];
    cmdLbl.frame = NSMakeRect(0, 42, 72, 20);
    NSTextField *cmdField = [[NSTextField alloc] initWithFrame:NSMakeRect(76, 38, 352, 24)];
    cmdField.stringValue = initialCommand ?: @"";
    cmdField.placeholderString = @"e.g. open -a \"Visual Studio Code\" {FILES}";

    NSTextField *hint = [NSTextField wrappingLabelWithString:
        @"Placeholders: {FILES} = selection, {PATH} = directory. Click ⓘ for examples."];
    hint.font = [NSFont systemFontOfSize:10];
    hint.textColor = [NSColor secondaryLabelColor];
    hint.frame = NSMakeRect(76, 0, 352, 30);

    [acc addSubview:titleLbl]; [acc addSubview:titleField]; [acc addSubview:helpBtn];
    [acc addSubview:cmdLbl];   [acc addSubview:cmdField];
    [acc addSubview:hint];

    if (outView) *outView = acc;
    return @{ @"title": titleField, @"command": cmdField };
}

- (void)addCustomButtonAction:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Add Custom Button";
    alert.informativeText = @"Title and shell command for the new button.";

    NSView *acc = nil;
    NSDictionary *fields = [self buildCustomButtonFormWithTitle:nil command:nil intoView:&acc];
    alert.accessoryView = acc;
    [alert addButtonWithTitle:@"Add"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert.window setInitialFirstResponder:fields[@"title"]];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSString *title = [((NSTextField *)fields[@"title"]).stringValue
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *cmd = [((NSTextField *)fields[@"command"]).stringValue
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (title.length == 0 || cmd.length == 0) return;

    NSMutableArray *all = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"customButtons"] mutableCopy] ?: [NSMutableArray array];
    [all addObject:@{ @"title": title, @"command": cmd }];
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:@"customButtons"];
    [_buttonBankPanel rebuildGrid];
}

- (void)editCustomButtonAction:(id)sender {
    NSArray<NSDictionary *> *all = [[NSUserDefaults standardUserDefaults] arrayForKey:@"customButtons"] ?: @[];
    if (all.count == 0) {
        [self showAlert:@"Edit Custom Button" info:@"No custom buttons yet." style:NSAlertStyleInformational];
        return;
    }

    /* Step 1: pick which one */
    NSAlert *pick = [[NSAlert alloc] init];
    pick.messageText = @"Edit Custom Button";
    pick.informativeText = @"Which button do you want to edit?";
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 360, 26)];
    for (NSDictionary *b in all) {
        [popup addItemWithTitle:[NSString stringWithFormat:@"%@ — %@", b[@"title"], b[@"command"]]];
    }
    pick.accessoryView = popup;
    [pick addButtonWithTitle:@"Edit…"];
    [pick addButtonWithTitle:@"Cancel"];
    if ([pick runModal] != NSAlertFirstButtonReturn) return;
    NSInteger idx = popup.indexOfSelectedItem;
    if (idx < 0 || idx >= (NSInteger)all.count) return;
    NSDictionary *current = all[idx];

    /* Step 2: show the edit form pre-filled */
    NSAlert *form = [[NSAlert alloc] init];
    form.messageText = @"Edit Custom Button";
    form.informativeText = @"Update the title or command.";
    NSView *acc = nil;
    NSDictionary *fields = [self buildCustomButtonFormWithTitle:current[@"title"]
                                                         command:current[@"command"]
                                                        intoView:&acc];
    form.accessoryView = acc;
    [form addButtonWithTitle:@"Save"];
    [form addButtonWithTitle:@"Cancel"];
    [form.window setInitialFirstResponder:fields[@"title"]];
    if ([form runModal] != NSAlertFirstButtonReturn) return;

    NSString *title = [((NSTextField *)fields[@"title"]).stringValue
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *cmd = [((NSTextField *)fields[@"command"]).stringValue
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (title.length == 0 || cmd.length == 0) return;

    NSMutableArray *updated = [all mutableCopy];
    updated[idx] = @{ @"title": title, @"command": cmd };
    [[NSUserDefaults standardUserDefaults] setObject:updated forKey:@"customButtons"];
    [_buttonBankPanel rebuildGrid];
}

- (void)removeCustomButtonAction:(id)sender {
    NSArray<NSDictionary *> *all = [[NSUserDefaults standardUserDefaults] arrayForKey:@"customButtons"] ?: @[];
    if (all.count == 0) {
        [self showAlert:@"Remove Custom Button" info:@"No custom buttons to remove." style:NSAlertStyleInformational];
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Remove Custom Button";
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 360, 26)];
    for (NSDictionary *b in all) {
        [popup addItemWithTitle:[NSString stringWithFormat:@"%@ — %@", b[@"title"], b[@"command"]]];
    }
    alert.accessoryView = popup;
    [alert addButtonWithTitle:@"Remove"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSInteger idx = popup.indexOfSelectedItem;
    if (idx < 0 || idx >= (NSInteger)all.count) return;
    NSMutableArray *updated = [all mutableCopy];
    [updated removeObjectAtIndex:idx];
    [[NSUserDefaults standardUserDefaults] setObject:updated forKey:@"customButtons"];
    [_buttonBankPanel rebuildGrid];
}

/* Compare Source with Destination — DOpus classic. Selects, in the SOURCE
 * Lister, every entry whose name doesn't appear in the DEST Lister's
 * visible buffer. Quick way to see "what's missing over there". */
- (void)goToPathAction:(id)sender {
    ListerWindowController *src = [self sourceOrOperating];
    if (!src) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Go to Path";
    alert.informativeText = @"Type a path — ~/ and $HOME expand.";
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 420, 24)];
    input.stringValue = src.currentPath;
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"Go"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert.window setInitialFirstResponder:input];
    [input selectText:nil];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSString *path = [input.stringValue stringByExpandingTildeInPath];
    path = [path stringByStandardizingPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self showAlert:@"Go to Path" info:[NSString stringWithFormat:@"No such path: %@", path]
                  style:NSAlertStyleWarning];
        return;
    }
    [src loadPath:path];
}

- (void)compareSourceWithDestAction:(id)sender {
    ListerWindowController *src = _activeSource;
    ListerWindowController *dst = _activeDest;
    if (!src || !dst) {
        [self showAlert:@"Compare"
                   info:@"Need both a SOURCE and DEST Lister. Open a second Lister (⌘N) or use Split Display (⇧⌘N)."
                  style:NSAlertStyleInformational];
        return;
    }
    if (!src.dataSource.buffer || !dst.dataSource.buffer) return;

    /* Build a name set from the destination buffer */
    NSMutableSet<NSString *> *destNames = [NSMutableSet set];
    int dtotal = dst.dataSource.buffer->stats.total_entries;
    for (int i = 0; i < dtotal; i++) {
        dir_entry_t *e = dir_buffer_get_entry(dst.dataSource.buffer, i);
        if (e && e->name) [destNames addObject:[NSString stringWithUTF8String:e->name]];
    }

    /* Select source entries whose name isn't in destNames */
    NSMutableIndexSet *idx = [NSMutableIndexSet indexSet];
    int stotal = src.dataSource.buffer->stats.total_entries;
    for (int i = 0; i < stotal; i++) {
        dir_entry_t *e = dir_buffer_get_entry(src.dataSource.buffer, i);
        if (!e || !e->name) continue;
        NSString *name = [NSString stringWithUTF8String:e->name];
        if (![destNames containsObject:name]) [idx addIndex:(NSUInteger)i];
    }

    [src.tableView selectRowIndexes:idx byExtendingSelection:NO];
    if (idx.firstIndex != NSNotFound) {
        [src.tableView scrollRowToVisible:(NSInteger)idx.firstIndex];
    }
    [src.window makeKeyAndOrderFront:nil];

    [self showAlert:@"Compare Source with Destination"
               info:[NSString stringWithFormat:@"%lu item%@ in SOURCE not present in DEST (by name).",
                     (unsigned long)idx.count, idx.count == 1 ? @"" : @"s"]
              style:NSAlertStyleInformational];
}

#pragma mark Rsync

- (NSArray<NSString *> *)rsyncArgsFromProfile:(NSDictionary *)p {
    NSMutableArray *args = [NSMutableArray array];
    if ([p[@"archive"]  boolValue]) [args addObject:@"-a"];
    [args addObject:@"-v"];               /* always verbose so user sees what's happening */
    [args addObject:@"--human-readable"];
    [args addObject:@"--progress"];       /* per-file progress (compatible with macOS /usr/bin/rsync 2.6.9) */
    [args addObject:@"--stats"];          /* summary block for post-run graphical summary */
    if ([p[@"compress"] boolValue]) [args addObject:@"-z"];
    if ([p[@"update"]   boolValue]) [args addObject:@"-u"];
    if ([p[@"checksum"] boolValue]) [args addObject:@"-c"];
    if ([p[@"delete"]   boolValue]) [args addObject:@"--delete"];
    if ([p[@"dryRun"]   boolValue]) [args addObject:@"-n"];
    if ([p[@"excludeDS"]   boolValue]) [args addObject:@"--exclude=.DS_Store"];
    if ([p[@"excludeGit"]  boolValue]) [args addObject:@"--exclude=.git"];
    if ([p[@"excludeNode"] boolValue]) [args addObject:@"--exclude=node_modules"];
    NSString *bw = [p[@"bwlimit"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (bw.length) [args addObject:[NSString stringWithFormat:@"--bwlimit=%@", bw]];
    NSString *extra = [p[@"extraArgs"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (extra.length) {
        /* naive split on whitespace — good enough for simple flags / --exclude='x' */
        for (NSString *a in [extra componentsSeparatedByString:@" "]) {
            if (a.length) [args addObject:a];
        }
    }
    NSString *dst = p[@"dest"];
    if (!dst.length) return nil;
    NSArray<NSString *> *sources = p[@"sources"];
    if ([sources isKindOfClass:[NSArray class]] && sources.count > 0) {
        /* Selection-based sync: copy each selected item into dest as-is (no trailing /). */
        for (NSString *s in sources) {
            if (!s.length) continue;
            [args addObject:[s stringByExpandingTildeInPath]];
        }
    } else {
        NSString *src = p[@"source"];
        if (!src.length) return nil;
        /* rsync semantics: trailing / on source = copy contents; without = copy the dir itself.
         * Users usually want "mirror the contents", so append / if not there. */
        if (![src hasSuffix:@"/"]) src = [src stringByAppendingString:@"/"];
        [args addObject:[src stringByExpandingTildeInPath]];
    }
    [args addObject:[dst stringByExpandingTildeInPath]];
    return args;
}

- (void)runRsyncWithProfile:(NSDictionary *)profile
               sourceWindow:(NSWindow *)srcWin {
    NSArray<NSString *> *args = [self rsyncArgsFromProfile:profile];
    if (!args) {
        [self showAlert:@"Sync" info:@"Source and destination are required."
                  style:NSAlertStyleWarning];
        return;
    }
    NSString *title = profile[@"name"]
        ? [NSString stringWithFormat:@"Sync — %@%@", profile[@"name"],
           [profile[@"dryRun"] boolValue] ? @" (dry run)" : @""]
        : [NSString stringWithFormat:@"rsync%@",
           [profile[@"dryRun"] boolValue] ? @" (dry run)" : @""];

    RsyncSheetController *sheet = [[RsyncSheetController alloc] init];
    __block RsyncSheetController *keepAlive = sheet;
    [sheet runArgs:args title:title sourceWindow:srcWin completion:^(int status) {
        /* Refresh affected listers — dest might have changed. */
        NSString *dest = [profile[@"dest"] stringByExpandingTildeInPath];
        if ([dest rangeOfString:@":"].location == NSNotFound) {
            /* local dest → refresh */
            [self refreshAllListersShowing:dest];
        }
        (void)keepAlive;
    }];
    /* Keep sheet alive until close */
    objc_setAssociatedObject(srcWin, "activeRsyncSheet", sheet, OBJC_ASSOCIATION_RETAIN);
    (void)keepAlive;
}

/* Build shared accessory for sync dialog (source, dest, options, extraArgs) */
- (NSDictionary *)buildSyncForm:(NSView **)outView profile:(NSDictionary *)p {
    NSView *acc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];

    CGFloat labelX = 0, fieldX = 74, fieldW = 520, H = 22;

    NSTextField *nameLbl = [NSTextField labelWithString:L(@"Name:")];
    nameLbl.frame = NSMakeRect(labelX, 372, 70, 20);
    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(fieldX, 368, fieldW, 24)];
    nameField.placeholderString = L(@"e.g. Backup Documents");
    nameField.stringValue = p[@"name"] ?: @"";

    NSTextField *srcLbl = [NSTextField labelWithString:L(@"Source:")];
    srcLbl.frame = NSMakeRect(labelX, 340, 70, 20);
    NSTextField *srcField = [[NSTextField alloc] initWithFrame:NSMakeRect(fieldX, 336, fieldW, 24)];
    srcField.placeholderString = L(@"local path or user@host:/path");
    srcField.stringValue = p[@"source"] ?: @"";
    NSArray<NSString *> *seededSources = p[@"sources"];
    if ([seededSources isKindOfClass:[NSArray class]] && seededSources.count > 0) {
        srcField.editable = NO;
        srcField.drawsBackground = NO;
        srcField.bezeled = NO;
        srcField.selectable = YES;
    }

    NSTextField *dstLbl = [NSTextField labelWithString:L(@"Dest:")];
    dstLbl.frame = NSMakeRect(labelX, 308, 70, 20);
    NSTextField *dstField = [[NSTextField alloc] initWithFrame:NSMakeRect(fieldX, 304, fieldW, 24)];
    dstField.placeholderString = L(@"local path or user@host:/path");
    dstField.stringValue = p[@"dest"] ?: @"";

    /* ── Transfer ── */
    NSTextField *hTransfer = [NSTextField labelWithString:L(@"Transfer")];
    hTransfer.font = [NSFont boldSystemFontOfSize:12];
    hTransfer.frame = NSMakeRect(0, 272, 200, 18);

    NSButton *archive  = [NSButton checkboxWithTitle:L(@"Archive (-a: recursive, preserve)") target:nil action:nil];
    archive.frame  = NSMakeRect(fieldX, 248, 280, H);
    archive.state = ([p objectForKey:@"archive"] ? [p[@"archive"] boolValue] : YES) ? NSControlStateValueOn : NSControlStateValueOff;

    NSButton *compress = [NSButton checkboxWithTitle:L(@"Compress (-z)") target:nil action:nil];
    compress.frame = NSMakeRect(360, 248, 234, H);
    compress.state = [p[@"compress"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;

    NSButton *update_  = [NSButton checkboxWithTitle:L(@"Update only — skip newer at dest (-u)") target:nil action:nil];
    update_.frame  = NSMakeRect(fieldX, 222, 280, H);
    update_.state = [p[@"update"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;

    NSButton *checksum = [NSButton checkboxWithTitle:L(@"Checksum compare (-c)") target:nil action:nil];
    checksum.frame = NSMakeRect(360, 222, 234, H);
    checksum.state = [p[@"checksum"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;

    /* ── Safety ── */
    NSTextField *hSafety = [NSTextField labelWithString:L(@"Safety")];
    hSafety.font = [NSFont boldSystemFontOfSize:12];
    hSafety.frame = NSMakeRect(0, 192, 200, 18);

    NSButton *dryRun   = [NSButton checkboxWithTitle:L(@"Dry run — preview only (-n)") target:nil action:nil];
    dryRun.frame   = NSMakeRect(fieldX, 168, 280, H);
    dryRun.state = [p[@"dryRun"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;

    NSButton *delete_  = [NSButton checkboxWithTitle:L(@"Delete extras at dest (--delete) ⚠︎") target:nil action:nil];
    delete_.frame  = NSMakeRect(360, 168, 234, H);
    delete_.state = [p[@"delete"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;

    /* ── Exclude ── */
    NSTextField *hExclude = [NSTextField labelWithString:L(@"Exclude")];
    hExclude.font = [NSFont boldSystemFontOfSize:12];
    hExclude.frame = NSMakeRect(0, 138, 200, 18);

    NSButton *exDS = [NSButton checkboxWithTitle:@".DS_Store" target:nil action:nil];
    exDS.frame = NSMakeRect(fieldX, 114, 160, H);
    exDS.state = [p[@"excludeDS"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;

    NSButton *exGit = [NSButton checkboxWithTitle:@".git" target:nil action:nil];
    exGit.frame = NSMakeRect(fieldX + 170, 114, 120, H);
    exGit.state = [p[@"excludeGit"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;

    NSButton *exNode = [NSButton checkboxWithTitle:@"node_modules" target:nil action:nil];
    exNode.frame = NSMakeRect(fieldX + 300, 114, 200, H);
    exNode.state = [p[@"excludeNode"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;

    /* ── Advanced ── */
    NSTextField *hAdv = [NSTextField labelWithString:L(@"Advanced")];
    hAdv.font = [NSFont boldSystemFontOfSize:12];
    hAdv.frame = NSMakeRect(0, 84, 200, 18);

    NSTextField *bwLbl = [NSTextField labelWithString:L(@"Limit:")];
    bwLbl.frame = NSMakeRect(labelX, 56, 70, 20);
    NSTextField *bwField = [[NSTextField alloc] initWithFrame:NSMakeRect(fieldX, 52, 120, 24)];
    bwField.placeholderString = @"0 = no limit";
    bwField.stringValue = p[@"bwlimit"] ?: @"";
    NSTextField *bwUnit = [NSTextField labelWithString:L(@"KB/s")];
    bwUnit.textColor = [NSColor secondaryLabelColor];
    bwUnit.frame = NSMakeRect(fieldX + 128, 56, 140, 20);

    NSTextField *extraLbl = [NSTextField labelWithString:L(@"Extra:")];
    extraLbl.frame = NSMakeRect(labelX, 24, 70, 20);
    NSTextField *extraField = [[NSTextField alloc] initWithFrame:NSMakeRect(fieldX, 20, fieldW, 24)];
    extraField.placeholderString = L(@"extra rsync flags");
    extraField.stringValue = p[@"extraArgs"] ?: @"";

    for (NSView *v in @[nameLbl, nameField, srcLbl, srcField, dstLbl, dstField,
                        hTransfer, archive, compress, update_, checksum,
                        hSafety, dryRun, delete_,
                        hExclude, exDS, exGit, exNode,
                        hAdv, bwLbl, bwField, bwUnit, extraLbl, extraField])
        [acc addSubview:v];

    if (outView) *outView = acc;
    NSMutableDictionary *out = [@{ @"name": nameField, @"source": srcField, @"dest": dstField,
              @"archive": archive, @"compress": compress, @"update": update_, @"checksum": checksum,
              @"delete": delete_, @"dryRun": dryRun,
              @"excludeDS": exDS, @"excludeGit": exGit, @"excludeNode": exNode,
              @"bwlimit": bwField, @"extraArgs": extraField } mutableCopy];
    if ([seededSources isKindOfClass:[NSArray class]] && seededSources.count > 0) {
        out[@"sources"] = seededSources;
    }
    return out;
}

- (NSDictionary *)readSyncForm:(NSDictionary *)fields {
    NSString *(^tv)(NSString *) = ^(NSString *k) {
        return [((NSTextField *)fields[k]).stringValue
                 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    };
    BOOL (^cv)(NSString *) = ^(NSString *k) {
        return (BOOL)(((NSButton *)fields[k]).state == NSControlStateValueOn);
    };
    NSMutableDictionary *out = [@{
        @"name":        tv(@"name")      ?: @"",
        @"source":      tv(@"source")    ?: @"",
        @"dest":        tv(@"dest")      ?: @"",
        @"archive":     @(cv(@"archive")),
        @"compress":    @(cv(@"compress")),
        @"update":      @(cv(@"update")),
        @"checksum":    @(cv(@"checksum")),
        @"delete":      @(cv(@"delete")),
        @"dryRun":      @(cv(@"dryRun")),
        @"excludeDS":   @(cv(@"excludeDS")),
        @"excludeGit":  @(cv(@"excludeGit")),
        @"excludeNode": @(cv(@"excludeNode")),
        @"bwlimit":     tv(@"bwlimit")   ?: @"",
        @"extraArgs":   tv(@"extraArgs") ?: @"",
    } mutableCopy];
    NSArray *srcs = fields[@"sources"];
    if ([srcs isKindOfClass:[NSArray class]] && srcs.count > 0) {
        out[@"sources"] = srcs;
    }
    return out;
}

/* Present the sync form inside a proper NSPanel run as a modal, returns
 * 0=cancel, 1=run, 2=save; writes fields into *outProfile on run/save. */
- (int)runSyncDialogWithTitle:(NSString *)title
                          info:(NSString *)info
                      allowRun:(BOOL)allowRun
                          seed:(NSDictionary *)seed
                    outProfile:(NSDictionary **)outProfile {
    NSRect frame = NSMakeRect(0, 0, 640, 540);
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
        backing:NSBackingStoreBuffered defer:NO];
    panel.title = title;

    NSView *content = panel.contentView;

    NSTextField *hdr = [NSTextField labelWithString:title];
    hdr.font = [NSFont boldSystemFontOfSize:14];
    hdr.frame = NSMakeRect(20, 506, 600, 22);
    [content addSubview:hdr];

    NSTextField *sub = [NSTextField wrappingLabelWithString:info];
    sub.textColor = [NSColor secondaryLabelColor];
    sub.font = [NSFont systemFontOfSize:11];
    sub.frame = NSMakeRect(20, 472, 600, 32);
    [content addSubview:sub];

    NSView *acc = nil;
    NSDictionary *fields = [self buildSyncForm:&acc profile:seed];
    acc.frame = NSMakeRect(20, 60, 600, 400);
    [content addSubview:acc];

    IDOpusDialogHandler *handler = [[IDOpusDialogHandler alloc] init];
    objc_setAssociatedObject(panel, "dlgHandler", handler, OBJC_ASSOCIATION_RETAIN);

    NSButton *cancel = [NSButton buttonWithTitle:L(@"Cancel") target:handler action:@selector(stopCancel:)];
    cancel.keyEquivalent = @"\033";
    cancel.bezelStyle = NSBezelStyleRounded;
    cancel.frame = NSMakeRect(520, 14, 100, 32);
    [content addSubview:cancel];

    if (allowRun) {
        NSButton *save = [NSButton buttonWithTitle:L(@"Save Profile") target:handler action:@selector(stopSave:)];
        save.bezelStyle = NSBezelStyleRounded;
        save.frame = NSMakeRect(380, 14, 130, 32);
        [content addSubview:save];

        NSButton *run = [NSButton buttonWithTitle:L(@"Run") target:handler action:@selector(stopRun:)];
        run.bezelStyle = NSBezelStyleRounded;
        run.keyEquivalent = @"\r";
        run.frame = NSMakeRect(270, 14, 100, 32);
        [content addSubview:run];
    } else {
        NSButton *save = [NSButton buttonWithTitle:L(@"Save") target:handler action:@selector(stopSave:)];
        save.bezelStyle = NSBezelStyleRounded;
        save.keyEquivalent = @"\r";
        save.frame = NSMakeRect(410, 14, 100, 32);
        [content addSubview:save];
    }

    panel.initialFirstResponder = fields[@"name"];
    [panel center];
    NSInteger action = [NSApp runModalForWindow:panel];
    [panel orderOut:nil];

    if (action == 0) return 0;
    NSDictionary *profile = [self readSyncForm:fields];
    if (outProfile) *outProfile = profile;
    return (int)action;
}

- (void)syncSourceToDestAction:(id)sender {
    ListerWindowController *src = _activeSource;
    ListerWindowController *dst = _activeDest;
    NSArray<NSString *> *selection = [src selectedPaths];
    NSMutableDictionary *seed = [@{
        @"name":     @"",
        @"source":   src.currentPath ?: @"",
        @"dest":     dst.currentPath ?: @"",
        @"archive":  @YES,
        @"compress": @NO,
        @"delete":   @NO,
        @"dryRun":   @NO,
        @"extraArgs": @"",
    } mutableCopy];
    if (selection.count > 0) {
        seed[@"sources"] = selection;
        seed[@"source"] = [NSString stringWithFormat:L(@"%lu selected item(s) in %@"),
                           (unsigned long)selection.count,
                           src.currentPath ?: @""];
    }

    NSDictionary *profile = nil;
    int action = [self runSyncDialogWithTitle:L(@"Sync with rsync")
        info:L(@"Source / Dest can be local or remote (user@host:/path). Uses /usr/bin/rsync — existing SSH keys in ~/.ssh/ apply to remote targets.")
        allowRun:YES seed:seed outProfile:&profile];
    if (action == 0) return;

    if (!((NSString *)profile[@"source"]).length || !((NSString *)profile[@"dest"]).length) {
        [self showAlert:L(@"Sync") info:L(@"Source and destination are required.") style:NSAlertStyleWarning];
        return;
    }

    if (action == 2) {
        if (!((NSString *)profile[@"name"]).length) {
            [self showAlert:L(@"Save Profile") info:L(@"Profile needs a name.") style:NSAlertStyleInformational];
            return;
        }
        if ([profile[@"sources"] isKindOfClass:[NSArray class]]) {
            [self showAlert:L(@"Save Profile")
                       info:L(@"Profiles can't be saved from a selection. Run the sync now, or clear the selection and reopen the dialog to save a folder-level profile.")
                      style:NSAlertStyleWarning];
            return;
        }
        NSMutableArray *all = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"rsyncProfiles"] mutableCopy] ?: [NSMutableArray array];
        [all addObject:profile];
        [[NSUserDefaults standardUserDefaults] setObject:all forKey:@"rsyncProfiles"];
        return;
    }

    NSWindow *parent = src.window ?: dst.window ?: [NSApp keyWindow];
    [self runRsyncWithProfile:profile sourceWindow:parent];
}

- (void)runSyncProfile:(NSMenuItem *)sender {
    NSDictionary *p = sender.representedObject;
    if (!p) return;
    NSWindow *parent = (_activeSource.window ?: _activeDest.window ?: [NSApp keyWindow]);
    [self runRsyncWithProfile:p sourceWindow:parent];
}

- (void)addSyncProfileAction:(id)sender {
    ListerWindowController *src = _activeSource;
    ListerWindowController *dst = _activeDest;
    NSDictionary *seed = @{
        @"name":     @"",
        @"source":   src.currentPath ?: @"",
        @"dest":     dst.currentPath ?: @"",
        @"archive":  @YES,
        @"compress": @NO,
        @"delete":   @NO,
        @"dryRun":   @NO,
        @"extraArgs": @"",
    };
    NSDictionary *profile = nil;
    int action = [self runSyncDialogWithTitle:L(@"Add Sync Profile")
        info:L(@"Save a reusable sync definition. Run it later from Functions → Sync.")
        allowRun:NO seed:seed outProfile:&profile];
    if (action != 2) return;
    if (!((NSString *)profile[@"name"]).length ||
        !((NSString *)profile[@"source"]).length ||
        !((NSString *)profile[@"dest"]).length) {
        [self showAlert:L(@"Save Profile")
                   info:L(@"Name, source and destination are all required.")
                  style:NSAlertStyleWarning];
        return;
    }
    NSMutableArray *all = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"rsyncProfiles"] mutableCopy] ?: [NSMutableArray array];
    [all addObject:profile];
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:@"rsyncProfiles"];
}

- (void)removeSyncProfileAction:(id)sender {
    NSArray<NSDictionary *> *all = [[NSUserDefaults standardUserDefaults] arrayForKey:@"rsyncProfiles"] ?: @[];
    if (all.count == 0) {
        [self showAlert:@"Remove Sync Profile" info:@"No profiles to remove." style:NSAlertStyleInformational];
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Remove Sync Profile";
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 360, 26)];
    for (NSDictionary *p in all) {
        [popup addItemWithTitle:[NSString stringWithFormat:@"%@ — %@ → %@",
                                 p[@"name"], p[@"source"], p[@"dest"]]];
    }
    alert.accessoryView = popup;
    [alert addButtonWithTitle:@"Remove"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSInteger idx = popup.indexOfSelectedItem;
    if (idx < 0 || idx >= (NSInteger)all.count) return;
    NSMutableArray *updated = [all mutableCopy];
    [updated removeObjectAtIndex:idx];
    [[NSUserDefaults standardUserDefaults] setObject:updated forKey:@"rsyncProfiles"];
}

#pragma mark File type actions

/* Storage: NSUserDefaults "fileTypeActions" =
 *   { "<ext>": [ { title, command, default(BOOL) }, ... ], ... }
 * Extension keys are lowercase, leading dot stripped. */

- (NSArray<NSDictionary *> *)fileTypeActionsForExt:(NSString *)ext {
    if (!ext.length) return @[];
    NSString *key = ext.lowercaseString;
    if ([key hasPrefix:@"."]) key = [key substringFromIndex:1];
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"fileTypeActions"];
    return all[key] ?: @[];
}

- (NSDictionary *)defaultFileTypeActionForExt:(NSString *)ext {
    for (NSDictionary *a in [self fileTypeActionsForExt:ext]) {
        if ([a[@"default"] boolValue]) return a;
    }
    return nil;
}

- (void)runFileTypeAction:(NSDictionary *)action
                   onPath:(NSString *)path
             sourceLister:(ListerWindowController *)src {
    NSString *cmd = action[@"command"];
    if (!cmd.length) return;

    /* {FILE} = the single path; {FILES} = if src has selection, quoted list;
     * {PATH} = src.currentPath */
    NSString *fileArg = [NSString stringWithFormat:@"'%@'",
                         [path stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
    NSArray<NSString *> *paths = [src selectedPaths];
    NSMutableArray<NSString *> *quoted = [NSMutableArray array];
    for (NSString *p in paths) {
        NSString *e = [p stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
        [quoted addObject:[NSString stringWithFormat:@"'%@'", e]];
    }
    NSString *filesArg = quoted.count ? [quoted componentsJoinedByString:@" "] : fileArg;
    NSString *pathArg = [NSString stringWithFormat:@"'%@'",
                         [src.currentPath stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];

    NSString *expanded = [cmd stringByReplacingOccurrencesOfString:@"{FILE}" withString:fileArg];
    expanded = [expanded stringByReplacingOccurrencesOfString:@"{FILES}" withString:filesArg];
    expanded = [expanded stringByReplacingOccurrencesOfString:@"{PATH}" withString:pathArg];

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    task.arguments = @[@"-c", expanded];
    task.currentDirectoryURL = [NSURL fileURLWithPath:src.currentPath];
    NSError *err = nil;
    if (![task launchAndReturnError:&err]) {
        [self showAlert:@"Action failed" info:err.localizedDescription style:NSAlertStyleWarning];
    }
}

/* Shared Add/Edit form accessory view */
- (NSDictionary *)buildFileTypeForm:(NSView **)outView
                          extension:(NSString *)initialExt
                              title:(NSString *)initialTitle
                            command:(NSString *)initialCommand
                          isDefault:(BOOL)initialDefault {
    NSView *acc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 460, 156)];

    NSTextField *extLbl = [NSTextField labelWithString:@"Extension:"];
    extLbl.frame = NSMakeRect(0, 128, 90, 20);
    NSTextField *extField = [[NSTextField alloc] initWithFrame:NSMakeRect(94, 124, 120, 24)];
    extField.placeholderString = @"txt (no dot)";
    extField.stringValue = initialExt ?: @"";

    NSTextField *titleLbl = [NSTextField labelWithString:@"Title:"];
    titleLbl.frame = NSMakeRect(0, 96, 90, 20);
    NSTextField *titleField = [[NSTextField alloc] initWithFrame:NSMakeRect(94, 92, 310, 24)];
    titleField.stringValue = initialTitle ?: @"";

    /* Help button (ⓘ) — opens examples sheet */
    NSButton *helpBtn = [NSButton buttonWithTitle:@""
                                           target:self
                                           action:@selector(showFileTypeHelp:)];
    helpBtn.bezelStyle = NSBezelStyleHelpButton;
    helpBtn.frame = NSMakeRect(412, 92, 24, 24);
    helpBtn.toolTip = @"How file type actions work";

    NSTextField *cmdLbl = [NSTextField labelWithString:@"Command:"];
    cmdLbl.frame = NSMakeRect(0, 64, 90, 20);
    NSTextField *cmdField = [[NSTextField alloc] initWithFrame:NSMakeRect(94, 60, 240, 24)];
    cmdField.placeholderString = @"open -a TextEdit {FILE}";
    cmdField.stringValue = initialCommand ?: @"";
    cmdField.identifier = @"fileTypeCmdField";  /* so the app-picker can find it */

    NSButton *pickBtn = [NSButton buttonWithTitle:@"Choose App…"
                                           target:self
                                           action:@selector(pickAppForFileTypeAction:)];
    pickBtn.frame = NSMakeRect(338, 60, 98, 24);
    pickBtn.bezelStyle = NSBezelStyleRounded;

    NSTextField *hint = [NSTextField wrappingLabelWithString:
        @"{FILE}=clicked path, {FILES}=selection, {PATH}=directory. Or click “Choose App…”."];
    hint.font = [NSFont systemFontOfSize:10];
    hint.textColor = [NSColor secondaryLabelColor];
    hint.frame = NSMakeRect(94, 28, 342, 28);

    NSButton *defBox = [NSButton checkboxWithTitle:@"Default action (runs on double-click)"
                                            target:nil action:nil];
    defBox.frame = NSMakeRect(94, 4, 342, 20);
    defBox.state = initialDefault ? NSControlStateValueOn : NSControlStateValueOff;

    for (NSView *v in @[extLbl, extField, titleLbl, titleField, helpBtn,
                        cmdLbl, cmdField, pickBtn, hint, defBox])
        [acc addSubview:v];

    if (outView) *outView = acc;
    return @{ @"ext": extField, @"title": titleField, @"cmd": cmdField, @"default": defBox };
}

- (NSString *)fileTypeHelpText {
    return
        @"How file type actions work\n"
        @"\n"
        @"Each action runs as a shell command via /bin/sh -c with the\n"
        @"active Lister's directory as cwd.\n"
        @"\n"
        @"Placeholders\n"
        @"   {FILE}   the single path you double-clicked or right-clicked\n"
        @"   {FILES}  space-separated, quoted paths of the current selection\n"
        @"   {PATH}   the Lister's current directory\n"
        @"\n"
        @"To open a Mac app, prefer macOS's own /usr/bin/open:\n"
        @"   open -a \"Visual Studio Code\" {FILE}\n"
        @"   open -a Preview {FILES}\n"
        @"   open -a VLC {FILES}\n"
        @"\n"
        @"CLI tools need to be in PATH or referenced by full path:\n"
        @"   /usr/bin/ditto -x -k {FILE} ~/Desktop\n"
        @"   /opt/homebrew/bin/ffmpeg -i {FILE} out.mp4\n"
        @"\n"
        @"If \"Default action\" is checked, this runs on double-click of\n"
        @"any file with matching extension. Otherwise the action is only\n"
        @"available in the right-click → Actions submenu.";
}

- (void)showFileTypeHelp:(id)sender {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"File Type Action — How it works";
    a.informativeText = [self fileTypeHelpText];
    [a addButtonWithTitle:@"OK"];
    [a runModal];
}

/* "Choose App…" — pick any .app bundle from /Applications (or anywhere) and
 * auto-fill the command field with   open -a "AppName" {FILE} */
- (void)pickAppForFileTypeAction:(NSButton *)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.directoryURL = [NSURL fileURLWithPath:@"/Applications"];
    panel.allowedContentTypes = @[];   /* any file; filter manually */
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.treatsFilePackagesAsDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.message = @"Choose an application";
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    if (![panel.URL.pathExtension.lowercaseString isEqualToString:@"app"]) {
        [self showAlert:@"Choose App" info:@"Please pick a .app bundle." style:NSAlertStyleInformational];
        return;
    }

    NSString *appName = [panel.URL.lastPathComponent stringByDeletingPathExtension];
    NSString *cmd = [NSString stringWithFormat:@"open -a \"%@\" {FILE}", appName];

    /* Walk up from the button to find the accessory view, then the cmd field by id. */
    NSView *acc = sender.superview;
    for (NSView *sub in acc.subviews) {
        if ([sub isKindOfClass:[NSTextField class]] &&
            [sub.identifier isEqualToString:@"fileTypeCmdField"]) {
            ((NSTextField *)sub).stringValue = cmd;
            break;
        }
    }
}

- (void)addFileTypeActionAction:(id)sender {
    /* Pre-fill extension from the active Lister's selection if a single file
     * is selected — convenient for the typical "I just saw a file, add an
     * action for its type" flow. */
    NSString *prefilledExt = nil;
    ListerWindowController *src = [self sourceOrOperating];
    NSArray<NSString *> *selNames = [src selectedNames];
    if (selNames.count == 1) {
        NSString *ext = selNames.firstObject.pathExtension.lowercaseString;
        if (ext.length) prefilledExt = ext;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Add File Type Action";
    alert.informativeText = prefilledExt
        ? [NSString stringWithFormat:@"Placeholders: {FILE} / {FILES} / {PATH}. Extension pre-filled from your selection (.%@). Click ⓘ for examples.", prefilledExt]
        : @"Placeholders: {FILE} / {FILES} / {PATH}. Click ⓘ for examples.";
    NSView *acc = nil;
    NSDictionary *fields = [self buildFileTypeForm:&acc extension:prefilledExt title:nil command:nil isDefault:NO];
    alert.accessoryView = acc;
    [alert addButtonWithTitle:@"Add"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert.window setInitialFirstResponder:fields[@"ext"]];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSString *ext = [((NSTextField *)fields[@"ext"]).stringValue stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceCharacterSet]].lowercaseString;
    if ([ext hasPrefix:@"."]) ext = [ext substringFromIndex:1];
    NSString *title = [((NSTextField *)fields[@"title"]).stringValue stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceCharacterSet]];
    NSString *cmd = [((NSTextField *)fields[@"cmd"]).stringValue stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceCharacterSet]];
    BOOL isDefault = ((NSButton *)fields[@"default"]).state == NSControlStateValueOn;
    if (!ext.length || !title.length || !cmd.length) return;

    NSMutableDictionary *all = [([[NSUserDefaults standardUserDefaults] dictionaryForKey:@"fileTypeActions"] ?: @{}) mutableCopy];
    NSMutableArray *list = [(all[ext] ?: @[]) mutableCopy];
    /* If adding a new default, clear existing defaults in this extension. */
    if (isDefault) {
        NSMutableArray *cleared = [NSMutableArray array];
        for (NSDictionary *a in list) {
            NSMutableDictionary *m = [a mutableCopy];
            m[@"default"] = @NO;
            [cleared addObject:m];
        }
        list = cleared;
    }
    [list addObject:@{ @"title": title, @"command": cmd, @"default": @(isDefault) }];
    all[ext] = list;
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:@"fileTypeActions"];
}

- (void)manageFileTypeActionsAction:(id)sender {
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"fileTypeActions"];
    if (all.count == 0) {
        [self showAlert:@"Manage File Type Actions"
                   info:@"No file type actions defined yet. Use “Add File Type Action…” to create one."
                  style:NSAlertStyleInformational];
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Remove File Type Action";
    alert.informativeText = @"Pick an action to remove.";

    /* Flatten (ext, action) pairs into a single popup */
    NSMutableArray *flat = [NSMutableArray array];
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 460, 26)];
    for (NSString *ext in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        for (NSDictionary *a in all[ext]) {
            [flat addObject:@{ @"ext": ext, @"action": a }];
            NSString *title = [NSString stringWithFormat:@".%@ — %@%@",
                               ext, a[@"title"],
                               [a[@"default"] boolValue] ? @" (default)" : @""];
            [popup addItemWithTitle:title];
        }
    }
    alert.accessoryView = popup;
    [alert addButtonWithTitle:@"Remove"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSInteger idx = popup.indexOfSelectedItem;
    if (idx < 0 || idx >= (NSInteger)flat.count) return;
    NSString *ext = flat[idx][@"ext"];
    NSDictionary *action = flat[idx][@"action"];

    NSMutableDictionary *mAll = [all mutableCopy];
    NSMutableArray *list = [mAll[ext] mutableCopy];
    [list removeObject:action];
    if (list.count == 0) [mAll removeObjectForKey:ext];
    else                 mAll[ext] = list;
    [[NSUserDefaults standardUserDefaults] setObject:mAll forKey:@"fileTypeActions"];
}

- (void)selectPatternAction:(id)sender {
    ListerWindowController *src = [self sourceOrOperating];
    if (!src) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Select By Pattern";
    alert.informativeText = @"Glob (e.g. *.txt, img_*.jpg). Empty = no-op.";

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    input.stringValue = @"*";
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"Select"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert.window setInitialFirstResponder:input];
    [input selectText:nil];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *pattern = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (pattern.length == 0) return;
    [src selectByPattern:pattern];
}

- (void)sortByAction:(NSMenuItem *)sender {
    ListerWindowController *src = [self sourceOrOperating];
    if (!src || !src.dataSource.buffer) return;
    sort_field_t field = (sort_field_t)sender.tag;
    dir_buffer_t *b = src.dataSource.buffer;
    dir_buffer_set_sort(b, field,
                        (b->format.sort.flags & SORTF_REVERSE) != 0,
                        b->format.sort.separation);
    [src.tableView reloadData];
}

- (void)toggleReverseSortAction:(id)sender {
    ListerWindowController *src = [self sourceOrOperating];
    if (!src || !src.dataSource.buffer) return;
    dir_buffer_t *b = src.dataSource.buffer;
    bool currentRev = (b->format.sort.flags & SORTF_REVERSE) != 0;
    dir_buffer_set_sort(b, b->format.sort.field, !currentRev, b->format.sort.separation);
    [src.tableView reloadData];
}

- (void)toggleColumnVisibility:(NSMenuItem *)sender {
    NSString *colId = sender.representedObject;
    if (!colId) return;

    NSMutableSet<NSString *> *hidden = [NSMutableSet setWithArray:
        ([[NSUserDefaults standardUserDefaults] arrayForKey:@"hiddenColumns"] ?: @[])];
    BOOL wasHidden = [hidden containsObject:colId];
    if (wasHidden) [hidden removeObject:colId]; else [hidden addObject:colId];
    sender.state = wasHidden ? NSControlStateValueOn : NSControlStateValueOff;

    [[NSUserDefaults standardUserDefaults] setObject:hidden.allObjects forKey:@"hiddenColumns"];

    /* Apply to every live Lister */
    for (ListerWindowController *lw in _listerControllers) {
        for (NSTableColumn *c in lw.tableView.tableColumns) {
            if ([c.identifier isEqualToString:colId]) c.hidden = !wasHidden;
        }
    }
}

- (void)toggleFilesMixedAction:(id)sender {
    ListerWindowController *src = [self sourceOrOperating];
    if (!src || !src.dataSource.buffer) return;
    dir_buffer_t *b = src.dataSource.buffer;
    separation_t next = (b->format.sort.separation == SEPARATE_MIX) ? SEPARATE_DIRS_FIRST : SEPARATE_MIX;
    dir_buffer_set_sort(b, b->format.sort.field,
                        (b->format.sort.flags & SORTF_REVERSE) != 0,
                        next);
    [src.tableView reloadData];
}

- (void)toggleHidden:(id)sender {
    /* Global: flip hideDotfiles on every Lister, keeping per-Lister patterns. */
    BOOL anyShowing = NO;
    for (ListerWindowController *lw in _listerControllers) {
        if (!lw.dataSource.hideDotfiles) { anyShowing = YES; break; }
    }
    BOOL newHide = anyShowing;  /* if any is showing, hide all — uniform toggle */
    for (ListerWindowController *lw in _listerControllers) {
        lw.dataSource.hideDotfiles = newHide;
        [lw.dataSource applyCurrentFilter];
        [lw updateStatusBar];
    }
}

- (NSString *)infoTextForPath:(NSString *)path {
    const char *cpath = path.fileSystemRepresentation;
    struct stat st;
    if (lstat(cpath, &st) != 0) {
        return [NSString stringWithFormat:@"Cannot stat: %s", strerror(errno)];
    }

    const char *kind = "File";
    if      (S_ISDIR(st.st_mode))  kind = "Directory";
    else if (S_ISLNK(st.st_mode))  kind = "Symlink";
    else if (S_ISCHR(st.st_mode))  kind = "Char device";
    else if (S_ISBLK(st.st_mode))  kind = "Block device";
    else if (S_ISFIFO(st.st_mode)) kind = "FIFO";
    else if (S_ISSOCK(st.st_mode)) kind = "Socket";

    char sizeBuf[32];
    pal_format_size((uint64_t)st.st_size, sizeBuf, sizeof(sizeBuf));

    char modeBuf[16];
    snprintf(modeBuf, sizeof(modeBuf), "%o", st.st_mode & 07777);

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *mtime = [df stringFromDate:[NSDate dateWithTimeIntervalSince1970:st.st_mtime]];
    NSString *ctime = [df stringFromDate:[NSDate dateWithTimeIntervalSince1970:st.st_ctime]];

    struct passwd *pw = getpwuid(st.st_uid);
    struct group  *gr = getgrgid(st.st_gid);
    NSString *owner = pw ? [NSString stringWithUTF8String:pw->pw_name]
                         : [NSString stringWithFormat:@"%u", st.st_uid];
    NSString *group = gr ? [NSString stringWithUTF8String:gr->gr_name]
                         : [NSString stringWithFormat:@"%u", st.st_gid];

    return [NSString stringWithFormat:
        @"Path:        %@\n"
        @"Kind:        %s\n"
        @"Size:        %s (%lld bytes)\n"
        @"Modified:    %@\n"
        @"Changed:     %@\n"
        @"Permissions: %s\n"
        @"Owner:       %@ (%@)",
        path, kind, sizeBuf, (long long)st.st_size,
        mtime, ctime, modeBuf, owner, group];
}

#pragma mark File operations (Functions menu)

/* Refresh all listers displaying the given path (after copy/move/delete changes it) */
- (void)refreshAllListersShowing:(NSString *)path {
    for (ListerWindowController *lw in _listerControllers) {
        if ([lw.currentPath isEqualToString:path]) [lw reloadBuffer];
    }
}

/* Find the lister we should operate on. Prefer key window, else active source. */
- (ListerWindowController *)operatingLister {
    NSWindowController *wc = [NSApp keyWindow].windowController;
    if ([wc isKindOfClass:[ListerWindowController class]]) {
        return (ListerWindowController *)wc;
    }
    return _activeSource;
}

- (void)showAlert:(NSString *)title info:(NSString *)info style:(NSAlertStyle)style {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = info ?: @"";
    alert.alertStyle = style;
    [alert runModal];
}

- (void)deleteAction:(id)sender {
    ListerWindowController *src = [self operatingLister];
    if (!src) return;
    NSArray<NSString *> *paths = [src selectedPaths];
    if (paths.count == 0) {
        [self showAlert:@"Delete" info:@"No items selected." style:NSAlertStyleInformational];
        return;
    }

    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    BOOL toTrash = [u objectForKey:@"prefDeleteToTrash"] ? [u boolForKey:@"prefDeleteToTrash"] : YES;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = toTrash
        ? [NSString stringWithFormat:@"Move %lu item%@ to Trash?",
                    (unsigned long)paths.count, paths.count == 1 ? @"" : @"s"]
        : [NSString stringWithFormat:@"Permanently delete %lu item%@? This cannot be undone.",
                    (unsigned long)paths.count, paths.count == 1 ? @"" : @"s"];
    NSArray<NSString *> *names = [src selectedNames];
    NSMutableArray *preview = [NSMutableArray array];
    for (NSUInteger i = 0; i < MIN(5u, names.count); i++) [preview addObject:names[i]];
    if (names.count > 5) [preview addObject:[NSString stringWithFormat:@"… and %lu more", (unsigned long)(names.count - 5)]];
    alert.informativeText = [preview componentsJoinedByString:@"\n"];
    alert.alertStyle = toTrash ? NSAlertStyleWarning : NSAlertStyleCritical;
    [alert addButtonWithTitle:toTrash ? @"Move to Trash" : @"Delete"];
    [alert addButtonWithTitle:@"Cancel"];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *failed = [NSMutableArray array];
    for (NSString *p in paths) {
        NSError *err = nil;
        BOOL ok = toTrash
            ? [fm trashItemAtURL:[NSURL fileURLWithPath:p] resultingItemURL:nil error:&err]
            : [fm removeItemAtURL:[NSURL fileURLWithPath:p] error:&err];
        if (!ok) {
            [failed addObject:[NSString stringWithFormat:@"%@: %@", p.lastPathComponent, err.localizedDescription]];
        }
    }
    [self refreshAllListersShowing:src.currentPath];
    if (failed.count > 0) {
        [self showAlert:@"Some items could not be deleted"
                   info:[failed componentsJoinedByString:@"\n"]
                  style:NSAlertStyleWarning];
    }
}

- (NSString *)uniqueChild:(NSString *)name inDir:(NSString *)dir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *p = [dir stringByAppendingPathComponent:name];
    if (![fm fileExistsAtPath:p]) return p;
    NSString *base = [name stringByDeletingPathExtension];
    NSString *ext = name.pathExtension;
    for (int i = 2; i < 1000; i++) {
        NSString *cand = ext.length
            ? [NSString stringWithFormat:@"%@ %d.%@", base, i, ext]
            : [NSString stringWithFormat:@"%@ %d",   base, i];
        NSString *try = [dir stringByAppendingPathComponent:cand];
        if (![fm fileExistsAtPath:try]) return try;
    }
    return p;
}

- (void)newFileAction:(id)sender {
    ListerWindowController *src = [self operatingLister];
    if (!src) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"New File";
    alert.informativeText = [NSString stringWithFormat:@"In: %@", src.currentPath];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    input.stringValue = @"Untitled.txt";
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"Create"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert.window setInitialFirstResponder:input];
    [input selectText:nil];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *name = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (name.length == 0) return;

    NSString *newPath = [self uniqueChild:name inDir:src.currentPath];
    NSError *err = nil;
    if (![[NSData data] writeToFile:newPath options:NSDataWritingWithoutOverwriting error:&err]) {
        [self showAlert:@"New File failed" info:err.localizedDescription style:NSAlertStyleWarning];
        return;
    }
    [self refreshAllListersShowing:src.currentPath];
}

- (void)makeDirAction:(id)sender {
    ListerWindowController *src = [self operatingLister];
    if (!src) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Make Directory";
    alert.informativeText = [NSString stringWithFormat:@"In: %@", src.currentPath];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    input.stringValue = @"";
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"Create"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert.window setInitialFirstResponder:input];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *name = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (name.length == 0) return;

    NSString *newPath = [src.currentPath stringByAppendingPathComponent:name];
    NSError *err = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:newPath
                                   withIntermediateDirectories:NO
                                                    attributes:nil
                                                         error:&err]) {
        [self showAlert:@"MakeDir failed" info:err.localizedDescription style:NSAlertStyleWarning];
        return;
    }
    [self refreshAllListersShowing:src.currentPath];
}

- (void)renameAction:(id)sender {
    ListerWindowController *src = [self operatingLister];
    if (!src) return;
    NSArray<NSString *> *names = [src selectedNames];
    if (names.count != 1) {
        [self showAlert:@"Rename" info:@"Select exactly one item to rename." style:NSAlertStyleInformational];
        return;
    }
    /* Try inline rename first — faster and more macOS-native. */
    if ([src startInlineRenameIfSingleSelection]) return;

    NSString *oldName = names.firstObject;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Rename";
    alert.informativeText = [NSString stringWithFormat:@"In: %@", src.currentPath];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    input.stringValue = oldName;
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"Rename"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert.window setInitialFirstResponder:input];
    [input selectText:nil];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *newName = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (newName.length == 0 || [newName isEqualToString:oldName]) return;

    NSString *oldPath = [src.currentPath stringByAppendingPathComponent:oldName];
    NSString *newPath = [src.currentPath stringByAppendingPathComponent:newName];
    NSError *err = nil;
    if (![[NSFileManager defaultManager] moveItemAtPath:oldPath toPath:newPath error:&err]) {
        [self showAlert:@"Rename failed" info:err.localizedDescription style:NSAlertStyleWarning];
        return;
    }
    [self refreshAllListersShowing:src.currentPath];
}

- (void)copyAction:(id)sender { [self copyOrMove:NO]; }
- (void)moveAction:(id)sender { [self copyOrMove:YES]; }

/* Drag-and-drop entry point: files dragged from somewhere (another Lister
 * or an external app like Finder) dropped onto `dest`. */
- (void)performDropOntoLister:(ListerWindowController *)dest
                     fromURLs:(NSArray<NSURL *> *)urls
                       asMove:(BOOL)isMove {
    if (!dest || urls.count == 0) return;

    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:urls.count];
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:urls.count];
    for (NSURL *u in urls) {
        [paths addObject:u.path];
        [names addObject:u.lastPathComponent];
    }
    NSString *destDir = dest.currentPath;
    NSString *sourceParent = [urls.firstObject.path stringByDeletingLastPathComponent];

    __weak typeof(self) weakSelf = self;
    ProgressSheetController *sheet = [[ProgressSheetController alloc] init];
    __block ProgressSheetController *keepAlive = sheet;
    [sheet runOperation:isMove
                  paths:paths
                  names:names
                destDir:destDir
           sourceWindow:dest.window
             completion:^(NSArray<NSString *> *failed) {
        typeof(self) s = weakSelf;
        if (!s) { keepAlive = nil; return; }
        [s refreshAllListersShowing:destDir];
        if (isMove) [s refreshAllListersShowing:sourceParent];
        if (failed.count > 0) {
            [s showAlert:isMove ? @"Some items could not be moved" : @"Some items could not be copied"
                    info:[failed componentsJoinedByString:@"\n"]
                   style:NSAlertStyleWarning];
        }
        keepAlive = nil;
    }];
}

- (void)copyOrMove:(BOOL)isMove {
    ListerWindowController *src = _activeSource;
    ListerWindowController *dst = _activeDest;
    if (!src || !dst) {
        [self showAlert:isMove ? @"Move" : @"Copy"
                   info:@"Need both a SOURCE and DEST Lister. Open a second Lister (⌘N) or use Split Display (⇧⌘N)."
                  style:NSAlertStyleInformational];
        return;
    }

    /* Remote-aware routing. The existing pal_file / NSFileManager pipeline
     * only works on local paths, so any operation where either side is
     * remote has to go through rclone. v1.6 ships remote→local only;
     * remote→remote and local→remote land in v1.7. */
    if (src.isRemote || dst.isRemote) {
        if (isMove) {
            [self showAlert:@"Move"
                       info:L(@"Move to/from remote servers arrives in v1.7. Use Copy for now, then remove the remote file manually.")
                      style:NSAlertStyleInformational];
            return;
        }
        if (src.isRemote && dst.isRemote) {
            [self showAlert:@"Copy"
                       info:L(@"Remote-to-remote copy arrives in v1.7.")
                      style:NSAlertStyleInformational];
            return;
        }
        if (!src.isRemote && dst.isRemote) {
            [self showAlert:@"Copy"
                       info:L(@"Upload from local to remote arrives in v1.7. Download (remote → local) works today.")
                      style:NSAlertStyleInformational];
            return;
        }
        /* remote → local */
        NSArray<NSString *> *names = [src selectedNames];
        if (names.count == 0) {
            [self showAlert:@"Copy" info:L(@"No items selected in source lister.") style:NSAlertStyleInformational];
            return;
        }
        [self remoteDownloadNames:names fromLister:src toLocalDir:dst.currentPath];
        return;
    }

    if ([src.currentPath isEqualToString:dst.currentPath]) {
        [self showAlert:isMove ? @"Move" : @"Copy"
                   info:@"Source and destination are the same directory."
                  style:NSAlertStyleInformational];
        return;
    }
    NSArray<NSString *> *paths = [src selectedPaths];
    NSArray<NSString *> *names = [src selectedNames];
    if (paths.count == 0) {
        [self showAlert:isMove ? @"Move" : @"Copy"
                   info:@"No items selected in source lister."
                  style:NSAlertStyleInformational];
        return;
    }

    ProgressSheetController *sheet = [[ProgressSheetController alloc] init];
    __weak typeof(self) weakSelf = self;
    __block ProgressSheetController *keepAlive = sheet;  /* retain until completion */
    [sheet runOperation:isMove
                  paths:paths
                  names:names
                destDir:dst.currentPath
           sourceWindow:src.window
             completion:^(NSArray<NSString *> *failed) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { keepAlive = nil; return; }

        [strongSelf refreshAllListersShowing:dst.currentPath];
        if (isMove) [strongSelf refreshAllListersShowing:src.currentPath];

        if (failed.count > 0) {
            [strongSelf showAlert:isMove ? @"Some items could not be moved"
                                         : @"Some items could not be copied"
                             info:[failed componentsJoinedByString:@"\n"]
                            style:NSAlertStyleWarning];
        }
        keepAlive = nil;
    }];
}

/* Stream selected items from a remote SOURCE Lister into a local directory
 * via rclone copy. Shows a row in the Jobs panel per run. */
- (void)remoteDownloadNames:(NSArray<NSString *> *)names
                 fromLister:(ListerWindowController *)src
                 toLocalDir:(NSString *)destDir {
    ProgressSheetController *job = [[ProgressSheetController alloc] init];
    job.titleLabel.stringValue = names.count == 1 ? names.firstObject
        : [NSString stringWithFormat:L(@"%lu items from %@"),
           (unsigned long)names.count, src.remoteLabel ?: @"remote"];
    job.statsLabel.stringValue = L(@"Preparing…");
    job.startTime = [NSDate date];
    /* Seed the detail panel with the static metadata. Dynamic values
     * (Transferred / Speed / Remaining / Elapsed) are written from the
     * progress callback and the elapsed-tick timer below. */
    job.detailServer.stringValue = src.remoteLabel ?: @"—";
    job.detailFrom.stringValue   = src.currentPath ?: @"—";
    job.detailTo.stringValue     = destDir ?: @"—";
    [job.spinner startAnimation:nil];
    [[JobsPanelController shared] addJobRow:job.rowView];

    /* 1 Hz tick to refresh the "Elapsed:" field. Invalidated on completion. */
    __weak ProgressSheetController *weakJob = job;
    __block NSTimer *elapsedTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
        repeats:YES block:^(NSTimer *t) {
        ProgressSheetController *j = weakJob;
        if (!j) { [t invalidate]; return; }
        [j updateElapsed];
    }];

    /* Regex cached once — matches rclone's `Transferred:` progress line, e.g.
     *   Transferred:       64 MiB / 128 MiB, 50%, 10.23 MiB/s, ETA 6s
     * Groups: 1=done bytes+unit, 2=total bytes+unit, 3=pct, 4=speed, 5=ETA */
    static NSRegularExpression *rxProgress = nil;
    static dispatch_once_t onceTok; dispatch_once(&onceTok, ^{
        rxProgress = [NSRegularExpression regularExpressionWithPattern:
            @"Transferred:\\s+([\\d.]+\\s*\\S+)\\s*/\\s*([\\d.]+\\s*\\S+),\\s*(\\d+)%,?\\s*([\\d.]+\\s*\\S+/s)?(?:,\\s*ETA\\s+(\\S+))?"
            options:0 error:nil];
    });

    __block NSUInteger remaining = names.count;
    __block BOOL anyFailed = NO;
    NSUInteger total = names.count;
    NSUInteger i = 0;
    NSMutableArray<NSTask *> *runningTasks = [NSMutableArray array];
    job.cancelHandler = ^{
        for (NSTask *t in [runningTasks copy]) {
            if (t.isRunning) [t terminate];
        }
    };
    for (NSString *name in names) {
        i++;
        NSString *remotePath = [src.currentPath stringByAppendingPathComponent:name];
        /* Title shows the filename for single-file runs, or "(k/N) name" for
         * multi-file. Stats line holds the numbers. */
        NSString *titleValue = total == 1 ? name
            : [NSString stringWithFormat:@"(%lu/%lu) %@",
               (unsigned long)i, (unsigned long)total, name];
        job.titleLabel.stringValue = titleValue;
        NSTask *task = [IDOpusRclone copyFromRemote:src.remoteSpec
                          remotePath:remotePath
                             toLocal:destDir
                            progress:^(NSString *line) {
            NSTextCheckingResult *m = [rxProgress firstMatchInString:line
                options:0 range:NSMakeRange(0, line.length)];
            if (!m) return;
            NSString *done  = [line substringWithRange:[m rangeAtIndex:1]];
            NSString *tot   = [line substringWithRange:[m rangeAtIndex:2]];
            NSString *pct   = [line substringWithRange:[m rangeAtIndex:3]];
            NSString *speed = [m rangeAtIndex:4].location != NSNotFound
                ? [line substringWithRange:[m rangeAtIndex:4]] : @"";
            NSString *eta   = [m rangeAtIndex:5].location != NSNotFound
                ? [line substringWithRange:[m rangeAtIndex:5]] : @"";

            double pctVal = pct.doubleValue;
            if (job.spinner.indeterminate) {
                [job.spinner stopAnimation:nil];
                job.spinner.indeterminate = NO;
                job.spinner.minValue = 0;
                job.spinner.maxValue = 100;
            }
            job.spinner.doubleValue = pctVal;

            /* Top stats line (Finder/AirDrop phrasing). */
            NSMutableString *stats = [NSMutableString string];
            [stats appendFormat:L(@"%@ of %@"), done, tot];
            if (speed.length) [stats appendFormat:@" — %@", speed];
            if (eta.length)   [stats appendFormat:@" — %@ %@",
                               eta, L(@"remaining")];
            job.statsLabel.stringValue = stats;

            /* Expanded details panel — split into its own labeled fields. */
            job.detailTransferred.stringValue = [NSString stringWithFormat:L(@"%@ of %@"), done, tot];
            job.detailSpeed.stringValue       = speed.length ? speed : @"—";
            job.detailRemaining.stringValue   = eta.length ? eta : @"—";
        } completion:^(int status) {
            if (status != 0) anyFailed = YES;
            if (--remaining == 0) {
                [elapsedTimer invalidate];
                [job.spinner stopAnimation:nil];
                [[JobsPanelController shared] removeJobRow:job.rowView];
                [self refreshAllListersShowing:destDir];
                if (anyFailed && !job.cancelled) {
                    [self showAlert:L(@"Download")
                               info:L(@"Some items could not be downloaded.")
                              style:NSAlertStyleWarning];
                }
            }
        }];
        if (task) [runningTasks addObject:task];
    }
}

#pragma mark Contextual enablement

/* Check whether `sel` can be fired meaningfully right now. Used both by
 * validateMenuItem: (for the Functions + context menus) and by
 * refreshButtonBankEnablement (for Button Bank buttons). Keeping the logic
 * in one place avoids drift between menu and button greyout. */
- (BOOL)canPerformAction:(SEL)sel {
    ListerWindowController *op = [self operatingLister];
    NSUInteger selCount = op ? op.selectedPaths.count : 0;
    BOOL haveSource = _activeSource != nil;
    BOOL haveDest = _activeDest != nil && _activeDest != _activeSource;

    if (sel == @selector(copyAction:) || sel == @selector(moveAction:)) {
        NSUInteger srcSelCount = _activeSource ? _activeSource.selectedPaths.count : 0;
        return haveSource && haveDest && srcSelCount > 0;
    }
    if (sel == @selector(deleteAction:) ||
        sel == @selector(infoAction:) ||
        sel == @selector(copyToAction:) ||
        sel == @selector(moveToAction:) ||
        sel == @selector(duplicateAction:) ||
        sel == @selector(compressAction:) ||
        sel == @selector(extractAction:) ||
        sel == @selector(openSelectionAction:) ||
        sel == @selector(revealInFinderAction:) ||
        sel == @selector(openInTerminalAction:) ||
        sel == @selector(copyPathAction:)) {
        return selCount > 0;
    }
    if (sel == @selector(renameAction:)) {
        return selCount == 1;
    }
    if (sel == @selector(allAction:) || sel == @selector(noneAction:)) {
        return op != nil && op.tableView.numberOfRows > 0;
    }
    if (sel == @selector(makeDirAction:) ||
        sel == @selector(filterAction:) ||
        sel == @selector(parentAction:) ||
        sel == @selector(rootAction:) ||
        sel == @selector(refreshAction:) ||
        sel == @selector(selectPatternAction:) ||
        sel == @selector(compareSourceWithDestAction:)) {
        return op != nil;
    }
    if (sel == @selector(syncSourceToDestAction:)) {
        return haveSource && haveDest;
    }
    /* Unknown selectors: default to enabled so we don't accidentally lock the
     * user out of a new action that hasn't been wired here yet. */
    return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    return [self canPerformAction:item.action];
}

/* Walk every NSButton inside the Button Bank and set enabled based on the
 * same rules the menus use, so the user sees what's actionable right now
 * without having to try-and-fail. Called on selection / source / dest / path
 * changes. Cheap — the bank has ~12 buttons. */
- (void)refreshButtonBankEnablement {
    if (!_buttonBankPanel) return;
    NSView *root = _buttonBankPanel.window.contentView;
    NSMutableArray<NSView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        NSView *v = stack.lastObject;
        [stack removeLastObject];
        if ([v isKindOfClass:[NSButton class]]) {
            NSButton *b = (NSButton *)v;
            if (b.action && b.tag != 1) {
                /* tag 1 = custom shell-command button; leave enabled always */
                b.enabled = [self canPerformAction:b.action];
            }
        }
        [stack addObjectsFromArray:v.subviews];
    }
}

/* Rigid-trio snap: when one of the two Listers is dragged, translate the
 * other by the same delta so the Button Bank keeps sitting exactly in the
 * gap between them (it's a child window of SOURCE, so it tags along for
 * free). Mirrors the original DOpus Magellan "workspace moves as one" feel.
 * No-op for 1 or 3+ visible Listers — the two-pane case is the one users
 * consistently want tiled. */
- (void)snapshotListerFrames {
    if (!_lastListerFrames) _lastListerFrames = [NSMutableDictionary dictionary];
    for (ListerWindowController *l in _listerControllers) {
        _lastListerFrames[[NSValue valueWithNonretainedObject:l.window]] =
            [NSValue valueWithRect:l.window.frame];
    }
}

/* Called by Button Bank's windowDidResize: keep the right-hand Lister flush
 * against the bank's new right edge. No-op for non-two-pane setups. */
- (void)snapDestToBankRightEdge {
    if (!_buttonBankPanel) return;
    NSMutableArray<ListerWindowController *> *visible = [NSMutableArray array];
    for (ListerWindowController *l in _listerControllers) {
        if (l.window.isVisible && !l.window.isMiniaturized) [visible addObject:l];
    }
    if (visible.count != 2) return;
    ListerWindowController *left = visible[0], *right = visible[1];
    if (left.window.frame.origin.x > right.window.frame.origin.x) {
        ListerWindowController *t = left; left = right; right = t;
    }
    NSRect bank = _buttonBankPanel.window.frame;
    NSPoint newOrigin = NSMakePoint(NSMaxX(bank), right.window.frame.origin.y);
    if (fabs(newOrigin.x - right.window.frame.origin.x) < 0.5) return;
    _suppressSnap = YES;
    [right.window setFrameOrigin:newOrigin];
    NSRect f = right.window.frame;
    _lastListerFrames[[NSValue valueWithNonretainedObject:right.window]] =
        [NSValue valueWithRect:f];
    _suppressSnap = NO;
}

/* Tile the three workspace windows across the full usable screen: Listers
 * split the horizontal space evenly, bank keeps its current width, all three
 * share the screen's full height. Second click restores the pre-zoom layout
 * so the green zoom button toggles like NSWindow's native zoom does. */
- (void)zoomToTileWorkspace {
    if (!_buttonBankPanel) return;
    NSMutableArray<ListerWindowController *> *visible = [NSMutableArray array];
    for (ListerWindowController *l in _listerControllers) {
        if (l.window.isVisible && !l.window.isMiniaturized) [visible addObject:l];
    }
    if (visible.count != 2) return;
    ListerWindowController *left = visible[0], *right = visible[1];
    if (left.window.frame.origin.x > right.window.frame.origin.x) {
        ListerWindowController *t = left; left = right; right = t;
    }

    /* Toggle: if we have a stored pre-zoom snapshot, we're currently zoomed
     * and should restore. Otherwise, snapshot-then-tile. */
    if (_preZoomFrames.count > 0) {
        _suppressSnap = YES;
        NSValue *lv = _preZoomFrames[[NSValue valueWithNonretainedObject:left.window]];
        NSValue *rv = _preZoomFrames[[NSValue valueWithNonretainedObject:right.window]];
        NSValue *bv = _preZoomFrames[[NSValue valueWithNonretainedObject:_buttonBankPanel.window]];
        if (lv) [left.window  setFrame:lv.rectValue display:YES animate:YES];
        if (rv) [right.window setFrame:rv.rectValue display:YES animate:YES];
        if (bv) [_buttonBankPanel.window setFrame:bv.rectValue display:YES animate:NO];
        _suppressSnap = NO;
        _preZoomFrames = nil;
        [self snapshotListerFrames];
        return;
    }

    _preZoomFrames = [NSMutableDictionary dictionary];
    _preZoomFrames[[NSValue valueWithNonretainedObject:left.window]]
        = [NSValue valueWithRect:left.window.frame];
    _preZoomFrames[[NSValue valueWithNonretainedObject:right.window]]
        = [NSValue valueWithRect:right.window.frame];
    _preZoomFrames[[NSValue valueWithNonretainedObject:_buttonBankPanel.window]]
        = [NSValue valueWithRect:_buttonBankPanel.window.frame];

    NSScreen *screen = left.window.screen ?: [NSScreen mainScreen];
    NSRect vis = screen.visibleFrame;
    CGFloat bankW = MAX(80, MIN(400, _buttonBankPanel.window.frame.size.width));
    CGFloat listerW = floor((vis.size.width - bankW) / 2);

    _suppressSnap = YES;
    NSRect lf = NSMakeRect(vis.origin.x, vis.origin.y, listerW, vis.size.height);
    NSRect bf = NSMakeRect(NSMaxX(lf), vis.origin.y, bankW, vis.size.height);
    NSRect rf = NSMakeRect(NSMaxX(bf), vis.origin.y,
                            vis.size.width - listerW - bankW, vis.size.height);
    /* Parent (right) first — bank is its child and would otherwise be
     * dragged along when right moves, undoing the explicit bank setFrame. */
    [left.window setFrame:lf display:YES animate:YES];
    [right.window setFrame:rf display:YES animate:YES];
    [_buttonBankPanel.window setFrame:bf display:YES animate:NO];
    _suppressSnap = NO;
    [self snapshotListerFrames];
}

- (void)listerDidMove:(ListerWindowController *)lw {
    if (_suppressSnap) return;
    if (!_lastListerFrames) _lastListerFrames = [NSMutableDictionary dictionary];

    NSValue *key = [NSValue valueWithNonretainedObject:lw.window];
    NSRect newF = lw.window.frame;
    NSValue *oldVal = _lastListerFrames[key];
    if (!oldVal) {
        /* First observation ever — we need the pre-move frame to compute a
         * delta, and we don't have it. Snapshot NOW so subsequent events
         * have a baseline, and bail on this one. Losing the very first
         * pixel of a drag is acceptable; losing a 200-pixel jump is not. */
        [self snapshotListerFrames];
        return;
    }

    /* Collect the currently-visible Listers. We only snap when there are
     * exactly two so we don't accidentally drag unrelated windows around. */
    NSMutableArray<ListerWindowController *> *visible = [NSMutableArray array];
    for (ListerWindowController *l in _listerControllers) {
        if (l.window.isVisible && !l.window.isMiniaturized) [visible addObject:l];
    }

    NSRect oldF = oldVal.rectValue;
    CGFloat dx = newF.origin.x - oldF.origin.x;
    CGFloat dy = newF.origin.y - oldF.origin.y;
    _lastListerFrames[key] = [NSValue valueWithRect:newF];
    if (visible.count != 2) return;
    if (fabs(dx) < 0.5 && fabs(dy) < 0.5) return;

    _suppressSnap = YES;
    /* Batch the sibling move into the same screen refresh as the user-driven
     * window. Without this wrap, setFrame schedules a redraw on the next
     * runloop pass, so the sibling visibly lags one frame behind the mouse.
     * setFrameOrigin is the cheapest move primitive — no size recompute, no
     * invalidation pass. */
    NSDisableScreenUpdates();
    for (ListerWindowController *other in visible) {
        if (other == lw) continue;
        NSRect f = other.window.frame;
        NSPoint p = NSMakePoint(f.origin.x + dx, f.origin.y + dy);
        [other.window setFrameOrigin:p];
        f.origin = p;
        _lastListerFrames[[NSValue valueWithNonretainedObject:other.window]] =
            [NSValue valueWithRect:f];
    }
    NSEnableScreenUpdates();
    _suppressSnap = NO;
}

/* Keep the Button Bank docked flush to the left Lister's right edge, at its
 * *current* width (not stretched to fill the gap — that was the v1.6.6 bug
 * that produced giant half-screen-wide banks). Height matches the left
 * Lister. DEST is snapped to the bank's right edge via snapDestToBankRightEdge.
 * No-op for 1 or 3+ Listers. */
- (void)enforceBankBetweenListers {
    if (!_buttonBankPanel) return;
    NSMutableArray<ListerWindowController *> *visible = [NSMutableArray array];
    for (ListerWindowController *l in _listerControllers) {
        if (l.window.isVisible && !l.window.isMiniaturized) [visible addObject:l];
    }
    if (visible.count != 2) return;

    ListerWindowController *left = visible[0], *right = visible[1];
    if (left.window.frame.origin.x > right.window.frame.origin.x) {
        ListerWindowController *t = left; left = right; right = t;
    }
    NSRect lf = left.window.frame;
    NSRect bankOld = _buttonBankPanel.window.frame;

    /* Preserve the bank's existing width (clamp to [80, 400]) — it's what
     * the user has configured by dragging the edge. */
    CGFloat bankW = MAX(80, MIN(400, bankOld.size.width));
    if (bankW < 80) bankW = [ButtonBankPanelController desiredWidth];
    NSRect bank = NSMakeRect(NSMaxX(lf), lf.origin.y, bankW, lf.size.height);
    NSRect newR = right.window.frame;
    newR.origin.x = NSMaxX(bank);
    newR.origin.y = lf.origin.y;
    newR.size.height = lf.size.height;

    _suppressSnap = YES;
    /* ORDER MATTERS. If the bank is a child of `right`, moving `right` also
     * drags the bank by the stale parent→child offset — which would undo
     * the bank position we set a line earlier. So: set the parent (right)
     * first, then snap the bank into place; the bank's new offset is then
     * recorded correctly for future parent moves. */
    [right.window setFrame:newR display:YES animate:NO];
    [_buttonBankPanel.window setFrame:bank display:YES animate:NO];
    _lastListerFrames[[NSValue valueWithNonretainedObject:right.window]] =
        [NSValue valueWithRect:newR];
    _suppressSnap = NO;
    [self snapshotListerFrames];
}

/* When any Lister becomes key, surface every sibling Lister too so the whole
 * iDOpus workspace comes forward as one unit. orderFront: doesn't touch key
 * state (so the clicked window keeps focus) and skips the window that just
 * became key to avoid a redundant re-order. */
- (void)raiseAllListerWindowsExcept:(ListerWindowController *)primary {
    for (ListerWindowController *lw in _listerControllers) {
        if (lw == primary) continue;
        if (lw.window.isMiniaturized) continue;   /* leave dock-miniaturised windows alone */
        [lw.window orderFront:nil];
    }
}

/* App-level activation: whenever iDOpus comes to the foreground from another
 * app, bring every Lister window up together rather than just the key one. */
- (void)applicationDidBecomeActive:(NSNotification *)notification {
    for (ListerWindowController *lw in _listerControllers) {
        if (lw.window.isMiniaturized) continue;
        [lw.window orderFront:nil];
    }
}

- (void)connectToServerAction:(id)sender {
    /* Remember which Lister was in focus when Connect was invoked — that's
     * the one we'll flip to the remote on OK, instead of opening a third
     * window. Fall back to active SOURCE, then operating Lister. */
    ListerWindowController *target = [self operatingLister] ?: _activeSource ?: _activeDest;
    _connectDialog = [[ConnectDialogController alloc] init];
    __weak typeof(self) weakSelf = self;
    __weak ListerWindowController *weakTarget = target;
    _connectDialog.onConnect = ^(NSString *name, NSString *spec, NSString *path) {
        typeof(self) s = weakSelf; if (!s) return;
        ListerWindowController *lister = weakTarget;
        if (!lister) {
            /* No open Lister to reuse — open a fresh one as a last resort. */
            NSRect frame = NSMakeRect(100, 100, 800, 600);
            lister = [s newListerWindow:path frame:frame];
        }
        /* Reset history — mixing local and remote paths in the back/forward
         * list is confusing. */
        [lister.history removeAllObjects];
        lister.historyIndex = -1;
        lister.remoteSpec = spec;
        lister.remoteLabel = name;
        [lister loadRemotePath:path];
        [lister.window makeKeyAndOrderFront:nil];
    };
    NSWindow *parent = [NSApp keyWindow] ?: _activeSource.window;
    if (parent) {
        [parent beginSheet:_connectDialog.window completionHandler:^(NSModalResponse r) { (void)r; }];
    } else {
        [_connectDialog.window center];
        [_connectDialog.window makeKeyAndOrderFront:nil];
    }
}

@end

#pragma mark - Rclone wrapper

/* Thin wrapper around the bundled rclone binary. Public entry points run
 * rclone as a detached NSTask and deliver results on the main queue. Only
 * covers the operations v1.6 needs: list (lsjson) and copy-to-local.
 * Additional verbs (copyto, moveto, delete, mkdir) land in later releases.
 *
 * Remotes are expressed as *inline* rclone specs so we don't have to persist
 * credentials to rclone.conf. Example for SFTP:
 *   :sftp,host=192.168.4.10,user=jon,pass=<obscured>:/path
 * Password is passed through `rclone obscure` first.
 * (Class interface declared at the top of the file as a forward declaration.) */

@implementation IDOpusRclone

+ (NSString *)binaryPath {
    NSString *p = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"rclone"];
    if (p && [[NSFileManager defaultManager] isExecutableFileAtPath:p]) return p;
    /* Fallback to Contents/MacOS/rclone — auxiliaryExecutable looks there but
     * early in development it might not be registered yet. */
    NSString *alt = [[[NSBundle mainBundle] bundlePath]
        stringByAppendingPathComponent:@"Contents/MacOS/rclone"];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:alt]) return alt;
    /* Dev convenience: repo checkout */
    NSString *dev = [@"~/claude/idopus/third_party/rclone/rclone" stringByExpandingTildeInPath];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:dev]) return dev;
    return nil;
}

+ (NSTask *)_taskWithArgs:(NSArray<NSString *> *)args {
    NSString *bin = [self binaryPath];
    if (!bin) return nil;
    NSTask *t = [[NSTask alloc] init];
    t.executableURL = [NSURL fileURLWithPath:bin];
    t.arguments = args;
    return t;
}

+ (void)obscurePassword:(NSString *)plaintext
             completion:(void (^)(NSString *obscured, NSError *err))completion {
    NSTask *t = [self _taskWithArgs:@[@"obscure", plaintext]];
    if (!t) { completion(nil, [NSError errorWithDomain:@"iDOpus" code:1
        userInfo:@{NSLocalizedDescriptionKey:@"rclone binary not found"}]); return; }
    NSPipe *out = [NSPipe pipe];
    t.standardOutput = out;
    t.standardError = [NSPipe pipe];
    t.terminationHandler = ^(NSTask *task) {
        NSData *d = [out.fileHandleForReading readDataToEndOfFile];
        NSString *s = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (task.terminationStatus == 0 && s.length) completion(s, nil);
            else completion(nil, [NSError errorWithDomain:@"iDOpus" code:2
                userInfo:@{NSLocalizedDescriptionKey:@"rclone obscure failed"}]);
        });
    };
    NSError *err = nil;
    if (![t launchAndReturnError:&err]) completion(nil, err);
}

+ (void)listRemote:(NSString *)remoteSpec
              path:(NSString *)remotePath
        completion:(void (^)(NSArray<NSDictionary *> *entries, NSError *err))completion {
    if (!remotePath.length) remotePath = @"/";
    NSString *target = [NSString stringWithFormat:@"%@%@", remoteSpec, remotePath];
    NSTask *t = [self _taskWithArgs:@[@"lsjson", target, @"--no-modtime=false"]];
    if (!t) { completion(nil, [NSError errorWithDomain:@"iDOpus" code:1
        userInfo:@{NSLocalizedDescriptionKey:@"rclone binary not found"}]); return; }
    NSPipe *out = [NSPipe pipe];
    NSPipe *err = [NSPipe pipe];
    t.standardOutput = out;
    t.standardError = err;
    t.terminationHandler = ^(NSTask *task) {
        NSData *d = [out.fileHandleForReading readDataToEndOfFile];
        NSData *e = [err.fileHandleForReading readDataToEndOfFile];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (task.terminationStatus != 0) {
                NSString *msg = [[NSString alloc] initWithData:e encoding:NSUTF8StringEncoding];
                completion(nil, [NSError errorWithDomain:@"iDOpus" code:3
                    userInfo:@{NSLocalizedDescriptionKey:msg.length ? msg : @"rclone lsjson failed"}]);
                return;
            }
            NSError *jerr = nil;
            id parsed = [NSJSONSerialization JSONObjectWithData:d options:0 error:&jerr];
            if ([parsed isKindOfClass:[NSArray class]]) completion(parsed, nil);
            else completion(@[], jerr);
        });
    };
    NSError *launchErr = nil;
    if (![t launchAndReturnError:&launchErr]) completion(nil, launchErr);
}

+ (NSTask *)copyFromRemote:(NSString *)remoteSpec
                remotePath:(NSString *)remotePath
                   toLocal:(NSString *)localDir
                  progress:(void (^)(NSString *line))progress
                completion:(void (^)(int status))completion {
    NSString *src = [NSString stringWithFormat:@"%@%@", remoteSpec, remotePath];
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    /* Defaults tuned for a typical Mac on modern Wi-Fi (802.11ac / Wi-Fi 6)
     * where a single SMB/SFTP stream leaves throughput on the table.
     * transfers=8 doubles parallel file copies (matters with many small
     * files); multi-thread-streams=8 splits a single large file across
     * 8 TCP streams so big videos saturate the link.
     * Both overridable via Preferences → File operations. */
    NSInteger transfers = [u integerForKey:@"rcloneTransfers"];
    if (transfers <= 0) transfers = 8;
    NSInteger streams   = [u integerForKey:@"rcloneMultiThreadStreams"];
    if (streams <= 0) streams = 8;
    NSArray<NSString *> *args = @[@"copy", src, localDir,
                                   @"--progress", @"--stats=1s",
                                   [NSString stringWithFormat:@"--transfers=%ld", (long)transfers],
                                   [NSString stringWithFormat:@"--multi-thread-streams=%ld", (long)streams],
                                   @"--multi-thread-cutoff=128M"];
    NSTask *t = [self _taskWithArgs:args];
    if (!t) { completion(-1); return nil; }
    NSPipe *out = [NSPipe pipe];
    NSPipe *err = [NSPipe pipe];
    t.standardOutput = out;
    t.standardError = err;
    __block NSMutableString *buf = [NSMutableString string];
    void (^drain)(NSFileHandle *) = ^(NSFileHandle *fh) {
        NSData *d = fh.availableData;
        if (!d.length) { fh.readabilityHandler = nil; return; }
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (!s.length) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [buf appendString:s];
            while (YES) {
                NSRange r = [buf rangeOfString:@"\n"];
                if (r.location == NSNotFound) break;
                NSString *line = [buf substringToIndex:r.location];
                [buf deleteCharactersInRange:NSMakeRange(0, r.location + 1)];
                if (progress && line.length) progress(line);
            }
        });
    };
    out.fileHandleForReading.readabilityHandler = drain;
    err.fileHandleForReading.readabilityHandler = drain;
    t.terminationHandler = ^(NSTask *task) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(task.terminationStatus);
        });
    };
    NSError *launchErr = nil;
    if (![t launchAndReturnError:&launchErr]) { completion(-1); return nil; }
    return t;
}

@end

#pragma mark - Connect dialog

/* Small panel that collects a SFTP connection (protocol picker reserved for
 * future releases — v1.6 ships SFTP only). Returns an inline rclone spec and
 * a starting path on OK. Password is obscured via rclone before being embedded
 * in the spec so it's not trivially readable by anyone seeing the command line. */
@implementation ConnectDialogController {
    NSPopUpButton *_protocolPopup;
    NSTextField *_hostField;
    NSTextField *_portField;
    NSTextField *_userField;
    NSSecureTextField *_passField;
    NSTextField *_pathField;
    NSTextField *_statusLabel;
    NSButton *_connectBtn;
    NSTableView *_sideTable;
    /* sidebarRows: flat mix of header strings (NSString) and entry dicts.
     * Section headers are unselectable and render in small caps. Entry dicts
     * have keys: host, port, user, source ("nearby" or "saved"), displayName,
     * protocol ("sftp" or "smb"). */
    NSMutableArray *_sidebarRows;
    NSMutableArray<NSDictionary *> *_discovered;   /* live NSNetService results */
    NSNetServiceBrowser *_sshBrowser;
    NSNetServiceBrowser *_smbBrowser;
    NSMutableArray<NSNetService *> *_resolving;
    /* When the user clicks a SAVED row that has a stored obscured password,
     * this is set so Connect can reuse it without re-prompting. Cleared if
     * the user types anything fresh in the password field. */
    NSString *_savedObscured;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 760, 480);
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
        backing:NSBackingStoreBuffered defer:NO];
    panel.title = L(@"Connect to Server");
    self = [super initWithWindow:panel];
    if (!self) return nil;
    _sidebarRows = [NSMutableArray array];
    _discovered  = [NSMutableArray array];
    _resolving   = [NSMutableArray array];

    NSView *c = panel.contentView;

    NSTextField *hdr = [NSTextField labelWithString:L(@"Connect to Server")];
    hdr.font = [NSFont boldSystemFontOfSize:14];
    hdr.frame = NSMakeRect(20, 446, 720, 22);
    [c addSubview:hdr];

    NSTextField *sub = [NSTextField wrappingLabelWithString:
        L(@"Supports SFTP (SSH file transfer) and SMB (Windows/Samba shares). Uses the bundled rclone helper — no external install needed. Cloud storage arrives in v1.8.")];
    sub.textColor = [NSColor secondaryLabelColor];
    sub.font = [NSFont systemFontOfSize:11];
    sub.frame = NSMakeRect(20, 408, 720, 34);
    [c addSubview:sub];

    /* Left sidebar — scrollable NSTableView with Nearby + Saved rows. */
    NSScrollView *sideScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 64, 260, 336)];
    sideScroll.borderType = NSBezelBorder;
    sideScroll.hasVerticalScroller = YES;
    _sideTable = [[NSTableView alloc] init];
    _sideTable.headerView = nil;
    _sideTable.allowsEmptySelection = YES;
    _sideTable.rowHeight = 24;
    _sideTable.dataSource = self;
    _sideTable.delegate = self;
    _sideTable.intercellSpacing = NSMakeSize(0, 0);
    _sideTable.backgroundColor = [NSColor clearColor];
    _sideTable.usesAlternatingRowBackgroundColors = NO;
    _sideTable.style = NSTableViewStyleSourceList;
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"row"];
    col.width = 240;
    [_sideTable addTableColumn:col];
    _sideTable.action = @selector(sidebarClicked:);
    _sideTable.target = self;
    /* Context menu for Saved rows → Remove. */
    NSMenu *sideMenu = [[NSMenu alloc] init];
    [sideMenu addItemWithTitle:L(@"Remove") action:@selector(removeSavedAction:) keyEquivalent:@""].target = self;
    _sideTable.menu = sideMenu;
    sideScroll.documentView = _sideTable;
    [c addSubview:sideScroll];

    /* Right form — protocol / host / port / user / pass / path. */
    CGFloat fx = 300;    /* form-column x */
    CGFloat flw = 100;   /* label width */
    CGFloat fiw = 340;   /* input width */

    /* Protocol picker at the top. Changing it updates the port placeholder
     * so the user sees a sensible default (22 for SFTP, 445 for SMB). */
    NSTextField *protoLbl = [NSTextField labelWithString:L(@"Protocol:")];
    protoLbl.alignment = NSTextAlignmentRight;
    protoLbl.frame = NSMakeRect(fx, 376, flw, 22);
    [c addSubview:protoLbl];
    _protocolPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fx + flw + 8, 372, 180, 26)];
    [_protocolPopup addItemWithTitle:@"SFTP"];
    [_protocolPopup addItemWithTitle:@"SMB"];
    _protocolPopup.target = self;
    _protocolPopup.action = @selector(protocolChanged:);
    [c addSubview:_protocolPopup];

    CGFloat y = 336;
    NSArray<NSString *> *labels = @[L(@"Host:"), L(@"Port:"), L(@"User:"), L(@"Password:"), L(@"Remote path:")];
    NSMutableArray<NSTextField *> *fields = [NSMutableArray array];
    for (NSUInteger i = 0; i < labels.count; i++) {
        NSTextField *lbl = [NSTextField labelWithString:labels[i]];
        lbl.alignment = NSTextAlignmentRight;
        lbl.frame = NSMakeRect(fx, y, flw, 22);
        [c addSubview:lbl];
        NSTextField *tf = (i == 3)
            ? (NSTextField *)[[NSSecureTextField alloc] initWithFrame:NSMakeRect(fx + flw + 8, y - 2, fiw, 24)]
            : [[NSTextField alloc] initWithFrame:NSMakeRect(fx + flw + 8, y - 2, fiw, 24)];
        [c addSubview:tf];
        [fields addObject:tf];
        y -= 36;
    }
    _hostField = fields[0]; _hostField.placeholderString = @"e.g. fileserver.local";
    _portField = fields[1]; _portField.placeholderString = @"22 (default)";
    _userField = fields[2]; _userField.placeholderString = NSUserName();
    _passField = (NSSecureTextField *)fields[3];
    _pathField = fields[4]; _pathField.placeholderString = @"/ (root)";

    /* Explicit tab chain so Tab moves from Host → Port → User → Password →
     * Path → Host. AppKit's auto-chain sometimes skips NSSecureTextField
     * when fields are created bare in a for-loop. */
    _hostField.nextKeyView = _portField;
    _portField.nextKeyView = _userField;
    _userField.nextKeyView = _passField;
    _passField.nextKeyView = _pathField;
    _pathField.nextKeyView = _hostField;

    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.frame = NSMakeRect(fx, 64, fiw + flw + 8, 20);
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [c addSubview:_statusLabel];

    NSButton *cancel = [NSButton buttonWithTitle:L(@"Cancel") target:self action:@selector(cancel:)];
    cancel.keyEquivalent = @"\033";
    cancel.bezelStyle = NSBezelStyleRounded;
    cancel.frame = NSMakeRect(540, 16, 100, 32);
    [c addSubview:cancel];

    _connectBtn = [NSButton buttonWithTitle:L(@"Connect") target:self action:@selector(connect:)];
    _connectBtn.keyEquivalent = @"\r";
    _connectBtn.bezelStyle = NSBezelStyleRounded;
    _connectBtn.frame = NSMakeRect(648, 16, 100, 32);
    [c addSubview:_connectBtn];

    panel.initialFirstResponder = _hostField;

    [self rebuildSidebar];
    [self startBonjour];
    return self;
}

- (void)dealloc {
    [self stopBonjour];
}

#pragma mark Sidebar data

+ (NSArray<NSDictionary *> *)savedConnections {
    NSArray *raw = [[NSUserDefaults standardUserDefaults] arrayForKey:@"sftpSavedConnections"] ?: @[];
    /* Filter out corrupt entries (missing host) that older builds may have
     * written — they render as a bare "SMB" / "SFTP" row and can't be used. */
    NSMutableArray *clean = [NSMutableArray array];
    for (NSDictionary *c in raw) {
        NSString *h = c[@"host"];
        if ([h isKindOfClass:[NSString class]] && h.length) [clean addObject:c];
    }
    if (clean.count != raw.count) {
        [[NSUserDefaults standardUserDefaults] setObject:clean forKey:@"sftpSavedConnections"];
    }
    return clean;
}

+ (void)rememberConnection:(NSDictionary *)conn {
    /* Refuse to persist a connection without a host — one of those would
     * render as a bare "SMB" / "SFTP" row in SAVED and do nothing useful. */
    NSString *host = conn[@"host"];
    if (![host isKindOfClass:[NSString class]] || host.length == 0) return;

    NSMutableArray *all = [[self savedConnections] mutableCopy] ?: [NSMutableArray array];
    /* Dedup by protocol+host+user+port — same server over different protocols
     * is two logical entries, not one. */
    NSString *key = [NSString stringWithFormat:@"%@|%@@%@:%@",
                      conn[@"protocol"] ?: @"sftp",
                      conn[@"user"] ?: @"", host, conn[@"port"] ?: @""];
    for (NSDictionary *c in [all copy]) {
        NSString *k = [NSString stringWithFormat:@"%@|%@@%@:%@",
                        c[@"protocol"] ?: @"sftp",
                        c[@"user"] ?: @"", c[@"host"] ?: @"", c[@"port"] ?: @""];
        if ([k isEqualToString:key]) [all removeObject:c];
    }
    [all insertObject:conn atIndex:0];  /* most recent first */
    if (all.count > 20) [all removeObjectsInRange:NSMakeRange(20, all.count - 20)];
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:@"sftpSavedConnections"];
}

- (void)rebuildSidebar {
    [_sidebarRows removeAllObjects];
    [_sidebarRows addObject:L(@"NEARBY")];
    if (_discovered.count == 0) {
        [_sidebarRows addObject:@{@"placeholder": L(@"Scanning…")}];
    } else {
        for (NSDictionary *d in _discovered) [_sidebarRows addObject:d];
    }
    NSArray *saved = [ConnectDialogController savedConnections];
    [_sidebarRows addObject:L(@"SAVED")];
    if (saved.count == 0) {
        [_sidebarRows addObject:@{@"placeholder": L(@"No saved connections yet")}];
    } else {
        for (NSDictionary *s in saved) [_sidebarRows addObject:s];
    }
    [_sideTable reloadData];
}

#pragma mark Bonjour + port-scan discovery

- (void)startBonjour {
    _sshBrowser = [[NSNetServiceBrowser alloc] init];
    _sshBrowser.delegate = self;
    /* _ssh._tcp catches macOS with Remote Login enabled and Linux boxes that
     * register via Avahi; _smb._tcp catches file-sharing servers. Machines
     * that run sshd/smbd but don't advertise via Avahi are caught by the
     * parallel port scan below. */
    [_sshBrowser searchForServicesOfType:@"_ssh._tcp." inDomain:@"local."];
    _smbBrowser = [[NSNetServiceBrowser alloc] init];
    _smbBrowser.delegate = self;
    [_smbBrowser searchForServicesOfType:@"_smb._tcp." inDomain:@"local."];
    [self startPortScan];
    [self loadKnownHosts];
}

/* Harvest hosts the user has already interacted with elsewhere on the Mac —
 * no typing required. Catches cases Bonjour/port-scan miss (different
 * subnet, no PTR, or just a domain name in ~/.ssh/config). Sources:
 *   ~/.ssh/known_hosts  — every host the user has SSH'd to
 *   ~/.ssh/config       — explicit Host/HostName entries (skip wildcards)
 *   /etc/hosts          — non-loopback entries */
- (void)loadKnownHosts {
    NSMutableSet<NSString *> *sshNames = [NSMutableSet set];
    NSMutableSet<NSString *> *ambiguousNames = [NSMutableSet set];

    NSString *kh = [@"~/.ssh/known_hosts" stringByExpandingTildeInPath];
    NSString *khData = [NSString stringWithContentsOfFile:kh encoding:NSUTF8StringEncoding error:nil];
    for (NSString *raw in [khData componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!line.length || [line hasPrefix:@"#"]) continue;
        if ([line hasPrefix:@"|1|"]) continue;   /* HashKnownHosts — can't recover name */
        NSArray *parts = [line componentsSeparatedByString:@" "];
        if (parts.count < 2) continue;
        for (NSString *h in [parts[0] componentsSeparatedByString:@","]) {
            NSString *hh = [h stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([hh hasPrefix:@"["]) {
                NSRange r = [hh rangeOfString:@"]"];
                if (r.location != NSNotFound && r.location > 1)
                    hh = [hh substringWithRange:NSMakeRange(1, r.location - 1)];
            }
            if (hh.length && ![self _isBareIP:hh]) [sshNames addObject:hh];
        }
    }

    NSString *cfg = [@"~/.ssh/config" stringByExpandingTildeInPath];
    NSString *cfgData = [NSString stringWithContentsOfFile:cfg encoding:NSUTF8StringEncoding error:nil];
    for (NSString *raw in [cfgData componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!line.length || [line hasPrefix:@"#"]) continue;
        NSArray *parts = [[line componentsSeparatedByString:@" "]
            filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        if (parts.count < 2) continue;
        NSString *kw = [parts[0] lowercaseString];
        if ([kw isEqualToString:@"host"]) {
            for (NSUInteger i = 1; i < parts.count; i++) {
                NSString *h = [parts[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (!h.length) continue;
                if ([h containsString:@"*"] || [h containsString:@"?"]) continue;
                if (![self _isBareIP:h]) [sshNames addObject:h];
            }
        } else if ([kw isEqualToString:@"hostname"] && parts.count >= 2) {
            NSString *h = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (h.length && ![self _isBareIP:h]) [sshNames addObject:h];
        }
    }

    NSString *hostsData = [NSString stringWithContentsOfFile:@"/etc/hosts"
                                                    encoding:NSUTF8StringEncoding error:nil];
    for (NSString *raw in [hostsData componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!line.length || [line hasPrefix:@"#"]) continue;
        NSArray *parts = [[line componentsSeparatedByString:@" "]
            filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        if (parts.count < 2) continue;
        NSString *ip = parts[0];
        if ([ip isEqualToString:@"127.0.0.1"] || [ip isEqualToString:@"::1"] ||
            [ip hasPrefix:@"fe80"] || [ip isEqualToString:@"255.255.255.255"]) continue;
        for (NSUInteger i = 1; i < parts.count; i++) {
            NSString *h = [parts[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (h.length && ![h isEqualToString:@"localhost"] &&
                ![self _isBareIP:h]) [ambiguousNames addObject:h];
        }
    }

    /* SSH-origin hosts surface as SFTP immediately (we know they speak SSH).
     * /etc/hosts get the SFTP entry too — the SMB entry is added only if
     * the host actually responds on 445 (see _probeKnownHostForSMB). This
     * avoids polluting the list with github.com-as-SMB while still picking
     * up genuine SMB servers that live outside the local /24. */
    for (NSString *name in sshNames) {
        [self _addKnownHost:name protocol:@"sftp"];
        [self _probeKnownHostForSMB:name];
    }
    for (NSString *name in ambiguousNames) {
        [self _addKnownHost:name protocol:@"sftp"];
        [self _probeKnownHostForSMB:name];
    }
    [self rebuildSidebar];
}

/* For each named host, resolve to IP and probe port 445 — but only if the
 * resolved IP is in RFC1918 private space. That skips github.com and the
 * internet at large (we don't want to hammer random public IPs) while
 * catching servers on any reachable private subnet. */
- (void)_probeKnownHostForSMB:(NSString *)host {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        struct addrinfo hints = {0}, *res = NULL;
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;
        if (getaddrinfo(host.UTF8String, NULL, &hints, &res) != 0 || !res) return;
        struct in_addr a = ((struct sockaddr_in *)res->ai_addr)->sin_addr;
        uint32_t ip = ntohl(a.s_addr);
        freeaddrinfo(res);

        BOOL privateIP =
            (ip & 0xFF000000u) == 0x0A000000u ||   /* 10.0.0.0/8 */
            (ip & 0xFFF00000u) == 0xAC100000u ||   /* 172.16.0.0/12 */
            (ip & 0xFFFF0000u) == 0xC0A80000u;     /* 192.168.0.0/16 */
        if (!privateIP) return;
        if (![weakSelf _probeHost:ip port:445]) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) s = weakSelf; if (!s) return;
            [s _addKnownHost:host protocol:@"smb"];
            [s rebuildSidebar];
        });
    });
}

- (BOOL)_isBareIP:(NSString *)s {
    struct in_addr a;
    return inet_pton(AF_INET, s.UTF8String, &a) == 1;
}

- (void)_addKnownHost:(NSString *)host protocol:(NSString *)proto {
    if (!host.length || !proto.length) return;
    for (NSDictionary *e in _discovered) {
        if ([e[@"host"] isEqualToString:host] &&
            [e[@"protocol"] isEqualToString:proto]) return;
    }
    [_discovered addObject:@{
        @"displayName": host,
        @"host":        host,
        @"port":        [proto isEqualToString:@"smb"] ? @"445" : @"22",
        @"user":        @"",
        @"source":      @"nearby",
        @"protocol":    proto,
    }];
}

/* Parallel non-blocking connect() to port 22 across the local /24 subnet(s).
 * Catches Linux boxes that run sshd without advertising via Avahi — most of
 * them. Finishes in ~1 s for a typical home LAN. */
- (void)startPortScan {
    struct ifaddrs *ifa_head = NULL;
    if (getifaddrs(&ifa_head) != 0) return;

    NSMutableSet<NSNumber *> *seenNets = [NSMutableSet set];
    NSMutableArray *targets = [NSMutableArray array];   /* array of @{net24, myHost} */
    for (struct ifaddrs *ifa = ifa_head; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) continue;
        if ((ifa->ifa_flags & IFF_LOOPBACK) || !(ifa->ifa_flags & IFF_UP)) continue;
        struct sockaddr_in *sa = (struct sockaddr_in *)ifa->ifa_addr;
        uint32_t ip = ntohl(sa->sin_addr.s_addr);
        /* Skip link-local 169.254/16 — no SSH there realistically. */
        if ((ip & 0xFFFF0000) == 0xA9FE0000) continue;
        uint32_t net24 = ip & 0xFFFFFF00;
        if ([seenNets containsObject:@(net24)]) continue;
        [seenNets addObject:@(net24)];
        [targets addObject:@{@"net": @(net24), @"my": @(ip & 0xFF)}];
    }
    freeifaddrs(ifa_head);
    if (targets.count == 0) return;

    __weak typeof(self) weakSelf = self;
    dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

    for (NSDictionary *t in targets) {
        uint32_t net24 = ((NSNumber *)t[@"net"]).unsignedIntValue;
        uint32_t myHost = ((NSNumber *)t[@"my"]).unsignedIntValue;
        for (uint32_t h = 1; h <= 254; h++) {
            if (h == myHost) continue;
            uint32_t target = net24 | h;
            /* Probe both SSH (22) and SMB (445). A host may answer on either
             * or both — we register each hit as its own sidebar entry. */
            struct { uint16_t port; NSString *proto; } probes[] = {
                { 22,  @"sftp" },
                { 445, @"smb"  },
            };
            for (size_t i = 0; i < sizeof(probes)/sizeof(probes[0]); i++) {
                uint16_t port = probes[i].port;
                NSString *proto = probes[i].proto;
                dispatch_async(q, ^{
                    if ([weakSelf _probeHost:target port:port]) {
                        struct in_addr a = { .s_addr = htonl(target) };
                        char buf[INET_ADDRSTRLEN];
                        inet_ntop(AF_INET, &a, buf, sizeof(buf));
                        NSString *ipStr = [NSString stringWithUTF8String:buf];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [weakSelf _addScanHit:ipStr port:port protocol:proto];
                        });
                    }
                });
            }
        }
    }
    /* Pure fire-and-forget: the dialog stays interactive while results trickle in. */
}

/* Single non-blocking connect attempt with a 300 ms total budget. Returns
 * YES if the port is accepting connections. */
- (BOOL)_probeHost:(uint32_t)hostOrder port:(uint16_t)port {
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) return NO;
    int flags = fcntl(s, F_GETFL, 0);
    fcntl(s, F_SETFL, flags | O_NONBLOCK);

    struct sockaddr_in sa = {0};
    sa.sin_family = AF_INET;
    sa.sin_port = htons(port);
    sa.sin_addr.s_addr = htonl(hostOrder);

    int r = connect(s, (struct sockaddr *)&sa, sizeof(sa));
    BOOL ok = NO;
    if (r == 0) {
        ok = YES;
    } else if (errno == EINPROGRESS) {
        fd_set wfds; FD_ZERO(&wfds); FD_SET(s, &wfds);
        struct timeval tv = { 0, 300 * 1000 };
        if (select(s + 1, NULL, &wfds, NULL, &tv) > 0) {
            int err = 0; socklen_t len = sizeof(err);
            if (getsockopt(s, SOL_SOCKET, SO_ERROR, &err, &len) == 0 && err == 0) ok = YES;
        }
    }
    close(s);
    return ok;
}

/* Record a port-scan hit in the _discovered array. Dedupes against any
 * Bonjour-resolved entry with the same host *and* protocol — a single host
 * can legitimately have both an SSH and an SMB entry. Show the IP
 * immediately, then upgrade the displayName once reverse-DNS returns. */
- (void)_addScanHit:(NSString *)ip port:(uint16_t)port protocol:(NSString *)proto {
    for (NSDictionary *e in _discovered) {
        if ([e[@"host"] isEqualToString:ip] &&
            [e[@"protocol"] isEqualToString:proto]) return;
    }
    NSMutableDictionary *entry = [@{
        @"displayName": ip,
        @"host":        ip,
        @"port":        [NSString stringWithFormat:@"%u", port],
        @"user":        @"",
        @"source":      @"nearby",
        @"protocol":    proto,
    } mutableCopy];
    [_discovered addObject:entry];
    [self rebuildSidebar];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *name = [weakSelf _reverseDNSForIPString:ip];
        if (!name.length || [name isEqualToString:ip]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) s = weakSelf; if (!s) return;
            for (NSUInteger i = 0; i < s->_discovered.count; i++) {
                NSMutableDictionary *d = [s->_discovered[i] mutableCopy];
                if ([d[@"host"] isEqualToString:ip] &&
                    [d[@"protocol"] isEqualToString:proto]) {
                    d[@"displayName"] = name;
                    d[@"host"] = name;
                    s->_discovered[i] = d;
                    [s rebuildSidebar];
                    break;
                }
            }
        });
    });
}

/* Blocking reverse DNS via getnameinfo() with NI_NAMEREQD — returns nil when
 * no PTR record exists. Called on a utility queue so it doesn't stall the
 * scan or the main thread. */
- (NSString *)_reverseDNSForIPString:(NSString *)ipStr {
    struct sockaddr_in sa = {0};
    sa.sin_family = AF_INET;
    sa.sin_len = sizeof(sa);
    if (inet_pton(AF_INET, ipStr.UTF8String, &sa.sin_addr) != 1) return nil;
    char host[NI_MAXHOST];
    int r = getnameinfo((struct sockaddr *)&sa, sizeof(sa),
                        host, sizeof(host),
                        NULL, 0,
                        NI_NAMEREQD);
    if (r != 0) return nil;
    return [NSString stringWithUTF8String:host];
}

- (void)stopBonjour {
    [_sshBrowser stop]; _sshBrowser.delegate = nil; _sshBrowser = nil;
    [_smbBrowser stop]; _smbBrowser.delegate = nil; _smbBrowser = nil;
    for (NSNetService *s in _resolving) { s.delegate = nil; [s stop]; }
    [_resolving removeAllObjects];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)b
            didFindService:(NSNetService *)service
                moreComing:(BOOL)moreComing {
    service.delegate = self;
    /* Tag the service with its originating protocol so resolveAddress knows
     * how to label the sidebar entry — NSNetService itself only carries the
     * raw service type, which we'd have to parse. */
    BOOL isSMB = (b == _smbBrowser);
    objc_setAssociatedObject(service, "idopusProto", isSMB ? @"smb" : @"sftp",
                              OBJC_ASSOCIATION_RETAIN);
    [_resolving addObject:service];
    [service resolveWithTimeout:5.0];
    if (!moreComing) [self rebuildSidebar];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)b
          didRemoveService:(NSNetService *)service
                moreComing:(BOOL)moreComing {
    NSString *name = service.name;
    [_discovered filterUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(NSDictionary *d, NSDictionary *bd) {
            return ![d[@"displayName"] isEqualToString:name];
        }]];
    if (!moreComing) [self rebuildSidebar];
}

- (void)netServiceDidResolveAddress:(NSNetService *)service {
    NSString *host = service.hostName;
    if ([host hasSuffix:@"."]) host = [host substringToIndex:host.length - 1];
    if (!host.length) return;
    NSString *proto = objc_getAssociatedObject(service, "idopusProto") ?: @"sftp";
    NSDictionary *d = @{
        @"displayName": service.name ?: host,
        @"host":        host,
        @"port":        @(service.port).stringValue,
        @"user":        @"",
        @"source":      @"nearby",
        @"protocol":    proto,
    };
    /* Dedup by host + protocol — the same host might advertise both ssh and smb. */
    for (NSDictionary *e in [_discovered copy]) {
        if ([e[@"host"] isEqualToString:host] &&
            [e[@"protocol"] isEqualToString:proto]) return;
    }
    [_discovered addObject:d];
    [self rebuildSidebar];
}

- (void)netService:(NSNetService *)s didNotResolve:(NSDictionary *)err {
    s.delegate = nil;
    [_resolving removeObject:s];
}

#pragma mark NSTableViewDataSource / Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _sidebarRows.count;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    id item = _sidebarRows[row];
    if ([item isKindOfClass:[NSString class]]) return NO;
    if ([item isKindOfClass:[NSDictionary class]] && ((NSDictionary *)item)[@"placeholder"]) return NO;
    return YES;
}

- (NSView *)tableView:(NSTableView *)tv
    viewForTableColumn:(NSTableColumn *)col
                   row:(NSInteger)row {
    id item = _sidebarRows[row];
    NSTableCellView *cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, col.width, 24)];
    NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 0, col.width - 12, 24)];
    tf.bordered = NO; tf.drawsBackground = NO; tf.editable = NO; tf.selectable = NO;
    tf.autoresizingMask = NSViewWidthSizable;
    if ([item isKindOfClass:[NSString class]]) {
        tf.stringValue = (NSString *)item;
        tf.font = [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
        tf.textColor = [NSColor secondaryLabelColor];
    } else {
        NSDictionary *d = item;
        if (d[@"placeholder"]) {
            tf.stringValue = d[@"placeholder"];
            tf.font = [NSFont systemFontOfSize:12];
            tf.textColor = [NSColor tertiaryLabelColor];
        } else {
            NSString *user = d[@"user"] ?: @"";
            NSString *host = d[@"host"] ?: @"";
            NSString *proto = d[@"protocol"] ?: @"sftp";
            NSString *base = user.length ? [NSString stringWithFormat:@"%@@%@", user, host] : host;
            NSString *disp = [NSString stringWithFormat:@"%@  %@",
                               [proto uppercaseString], base];
            tf.stringValue = disp;
            tf.font = [NSFont systemFontOfSize:12];
            tf.textColor = [NSColor labelColor];
        }
    }
    cell.textField = tf;
    [cell addSubview:tf];
    return cell;
}

- (void)sidebarClicked:(id)sender {
    NSInteger row = _sideTable.clickedRow;
    if (row < 0 || row >= (NSInteger)_sidebarRows.count) return;
    id item = _sidebarRows[row];
    if (![item isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *d = item;
    if (d[@"placeholder"]) return;
    NSString *proto = d[@"protocol"] ?: @"sftp";
    NSString *host  = d[@"host"] ?: @"";
    NSString *user  = d[@"user"] ?: @"";
    NSString *port  = d[@"port"] ?: @"";
    NSString *path  = d[@"path"] ?: @"";

    /* NEARBY and discovered rows don't carry credentials. Auto-fill from any
     * matching SAVED entry so the user doesn't have to retype username (and
     * path) on every reconnect to a server they've used before. */
    if (!user.length || !path.length) {
        for (NSDictionary *saved in [ConnectDialogController savedConnections]) {
            NSString *sproto = saved[@"protocol"] ?: @"sftp";
            if (![saved[@"host"] isEqualToString:host]) continue;
            if (![sproto isEqualToString:proto]) continue;
            if (!user.length && [saved[@"user"] length]) user = saved[@"user"];
            if (!path.length && [saved[@"path"] length]) path = saved[@"path"];
            if (!port.length && [saved[@"port"] length]) port = saved[@"port"];
            break;
        }
    }

    [_protocolPopup selectItemWithTitle:[proto isEqualToString:@"smb"] ? @"SMB" : @"SFTP"];
    [self protocolChanged:nil];
    _hostField.stringValue = host;
    _portField.stringValue = port;
    _userField.stringValue = user;
    if (path.length) _pathField.stringValue = path;

    /* Pick up a stored obscured password from the matching SAVED row, if any.
     * Clear the password field and drop a hint placeholder so the user
     * knows a credential is on file — they hit Connect, we reuse the spec. */
    _savedObscured = nil;
    _passField.stringValue = @"";
    _passField.placeholderString = L(@"(enter password)");
    NSString *obscured = d[@"obscuredPass"];
    if (!obscured.length) {
        for (NSDictionary *saved in [ConnectDialogController savedConnections]) {
            NSString *sproto = saved[@"protocol"] ?: @"sftp";
            if (![saved[@"host"] isEqualToString:host]) continue;
            if (![sproto isEqualToString:proto]) continue;
            if ([saved[@"user"] length] && user.length &&
                ![saved[@"user"] isEqualToString:user]) continue;
            obscured = saved[@"obscuredPass"];
            if (obscured.length) break;
        }
    }
    if (obscured.length) {
        _savedObscured = [obscured copy];
        _passField.placeholderString = L(@"(saved — leave blank to reuse)");
    }
    [self.window makeFirstResponder:_passField];
}

- (void)removeSavedAction:(id)sender {
    NSInteger row = _sideTable.clickedRow;
    if (row < 0 || row >= (NSInteger)_sidebarRows.count) return;
    id item = _sidebarRows[row];
    if (![item isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *d = item;
    if (![d[@"source"] isEqualToString:@"saved"]) return;   /* only saved rows are removable */
    NSMutableArray *all = [[ConnectDialogController savedConnections] mutableCopy];
    NSString *key = [NSString stringWithFormat:@"%@@%@:%@", d[@"user"] ?: @"", d[@"host"] ?: @"", d[@"port"] ?: @""];
    for (NSDictionary *c in [all copy]) {
        NSString *k = [NSString stringWithFormat:@"%@@%@:%@", c[@"user"] ?: @"", c[@"host"] ?: @"", c[@"port"] ?: @""];
        if ([k isEqualToString:key]) [all removeObject:c];
    }
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:@"sftpSavedConnections"];
    [self rebuildSidebar];
}

- (void)cancel:(id)sender {
    [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseCancel];
    [self.window close];
}

- (void)protocolChanged:(id)sender {
    BOOL smb = [self _isSMB];
    _portField.placeholderString = smb ? @"445 (default)" : @"22 (default)";
    _pathField.placeholderString = smb ? @"share/subpath" : @"/ (root)";
}

- (BOOL)_isSMB {
    return [_protocolPopup.selectedItem.title isEqualToString:@"SMB"];
}

- (void)connect:(id)sender {
    NSString *host = [_hostField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!host.length) { _statusLabel.stringValue = L(@"Host is required."); return; }
    NSString *port = [_portField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *user = [_userField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!user.length) user = NSUserName();
    NSString *pass = _passField.stringValue ?: @"";
    NSString *path = [_pathField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!path.length) path = @"/";

    _connectBtn.enabled = NO;
    _statusLabel.stringValue = L(@"Probing…");

    BOOL smb = [self _isSMB];
    NSString *proto = smb ? @"smb" : @"sftp";
    /* If the user supplied a password, obscure it via rclone first so it's
     * not a clear-text argv entry. Otherwise assume ssh-agent / key auth. */
    void (^build)(NSString *) = ^(NSString *obscured) {
        NSMutableString *spec = [NSMutableString stringWithFormat:@":%@,host=%@,user=%@", proto, host, user];
        if (port.length) [spec appendFormat:@",port=%@", port];
        if (obscured.length) [spec appendFormat:@",pass=%@", obscured];
        [spec appendString:@":"];
        /* SMB paths are share-relative: "share/subpath". rclone lsjson wants
         * "/share/subpath" so prepend a slash if the user didn't. SFTP paths
         * are plain filesystem paths and already handled above. */
        NSString *probe = path;
        if (smb && ![probe hasPrefix:@"/"]) probe = [@"/" stringByAppendingString:probe];
        /* Smoke-test by listing the target path — confirms auth + reachability. */
        [IDOpusRclone listRemote:spec path:probe completion:^(NSArray *entries, NSError *err) {
            if (err) {
                self->_connectBtn.enabled = YES;
                self->_statusLabel.stringValue = err.localizedDescription ?: L(@"Connection failed");
                return;
            }
            (void)entries;
            NSString *display = [NSString stringWithFormat:@"%@ %@@%@", [proto uppercaseString], user, host];
            /* Persist the connection including the obscured password so next
             * launch / next dialog open can one-click reconnect. rclone's
             * obscure is not real encryption — just reversible obfuscation —
             * so treat it as "at least not clear-text", not as secure. */
            NSMutableDictionary *record = [@{
                @"host": host, @"port": port ?: @"", @"user": user,
                @"path": path, @"protocol": proto, @"source": @"saved",
                @"displayName": display,
            } mutableCopy];
            if (obscured.length) record[@"obscuredPass"] = obscured;
            [ConnectDialogController rememberConnection:record];
            NSWindow *parent = self.window.sheetParent;
            [parent endSheet:self.window returnCode:NSModalResponseOK];
            [self.window close];
            if (self.onConnect) self.onConnect(display, spec, probe);
        }];
    };
    if (pass.length) {
        [IDOpusRclone obscurePassword:pass completion:^(NSString *obscured, NSError *err) {
            if (err) {
                self->_connectBtn.enabled = YES;
                self->_statusLabel.stringValue = err.localizedDescription ?: L(@"Could not obscure password");
                return;
            }
            build(obscured);
        }];
    } else if (_savedObscured.length) {
        /* Blank field + we have a stored credential → reuse it directly. */
        build(_savedObscured);
    } else {
        build(nil);
    }
}

@end

#pragma mark - Remote Browser

/* Minimal remote-browsing window for v1.6. Lists entries via rclone lsjson,
 * supports navigation and a "Download to…" action that copies the selection
 * via rclone copy and surfaces progress in the JobsPanel. Full edit semantics
 * (move, delete, mkdir, rename on remote) land in later releases. */
@implementation RemoteBrowserWindowController {
    NSString *_rcloneSpec;
    NSString *_currentPath;
    NSString *_displayName;
    __weak IDOpusAppDelegate *_appDelegate;
    NSMutableArray<NSDictionary *> *_entries;
    NSTableView *_tableView;
    NSTextField *_pathLabel;
    NSProgressIndicator *_spinner;
    NSTextField *_statusLabel;
}

- (instancetype)initWithDisplayName:(NSString *)name
                           spec:(NSString *)spec
                           path:(NSString *)path
                    appDelegate:(IDOpusAppDelegate *)app {
    NSRect frame = NSMakeRect(0, 0, 720, 480);
    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                   NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable)
        backing:NSBackingStoreBuffered defer:NO];
    w.title = [NSString stringWithFormat:@"%@ — %@", name, path];
    w.releasedWhenClosed = NO;
    self = [super initWithWindow:w];
    if (!self) return nil;
    _rcloneSpec = [spec copy];
    _currentPath = [path copy];
    _displayName = [name copy];
    _appDelegate = app;
    _entries = [NSMutableArray array];

    NSView *c = w.contentView;

    _pathLabel = [NSTextField labelWithString:path];
    _pathLabel.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium];
    _pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _pathLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:_pathLabel];

    NSButton *up = [NSButton buttonWithTitle:L(@"Parent") target:self action:@selector(goUp:)];
    up.bezelStyle = NSBezelStyleRounded;
    up.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:up];

    NSButton *refresh = [NSButton buttonWithTitle:L(@"Refresh") target:self action:@selector(refresh:)];
    refresh.bezelStyle = NSBezelStyleRounded;
    refresh.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:refresh];

    NSButton *download = [NSButton buttonWithTitle:L(@"Download to DEST…") target:self action:@selector(downloadSelection:)];
    download.bezelStyle = NSBezelStyleRounded;
    download.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:download];

    _spinner = [[NSProgressIndicator alloc] init];
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.controlSize = NSControlSizeSmall;
    _spinner.displayedWhenStopped = NO;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:_spinner];

    NSScrollView *sv = [[NSScrollView alloc] init];
    sv.hasVerticalScroller = YES;
    sv.borderType = NSBezelBorder;
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView = [[NSTableView alloc] init];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.doubleAction = @selector(openSelection:);
    _tableView.target = self;
    _tableView.allowsMultipleSelection = YES;
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.style = NSTableViewStyleFullWidth;

    struct { NSString *ident; NSString *title; CGFloat w; } cols[] = {
        {@"name", L(@"Name"), 360},
        {@"size", L(@"Size"), 100},
        {@"date", L(@"Date"), 180},
    };
    for (int i = 0; i < 3; i++) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:cols[i].ident];
        col.title = cols[i].title;
        col.width = cols[i].w;
        [_tableView addTableColumn:col];
    }
    sv.documentView = _tableView;
    [c addSubview:sv];

    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:_statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [up.topAnchor       constraintEqualToAnchor:c.topAnchor constant:12],
        [up.leadingAnchor   constraintEqualToAnchor:c.leadingAnchor constant:12],
        [refresh.topAnchor      constraintEqualToAnchor:up.topAnchor],
        [refresh.leadingAnchor  constraintEqualToAnchor:up.trailingAnchor constant:8],
        [download.topAnchor     constraintEqualToAnchor:up.topAnchor],
        [download.leadingAnchor constraintEqualToAnchor:refresh.trailingAnchor constant:8],
        [_spinner.centerYAnchor constraintEqualToAnchor:up.centerYAnchor],
        [_spinner.leadingAnchor constraintEqualToAnchor:download.trailingAnchor constant:8],
        [_pathLabel.centerYAnchor constraintEqualToAnchor:up.centerYAnchor],
        [_pathLabel.leadingAnchor constraintEqualToAnchor:_spinner.trailingAnchor constant:12],
        [_pathLabel.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-12],

        [sv.topAnchor       constraintEqualToAnchor:up.bottomAnchor constant:12],
        [sv.leadingAnchor   constraintEqualToAnchor:c.leadingAnchor constant:12],
        [sv.trailingAnchor  constraintEqualToAnchor:c.trailingAnchor constant:-12],
        [sv.bottomAnchor    constraintEqualToAnchor:_statusLabel.topAnchor constant:-8],

        [_statusLabel.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:12],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-12],
        [_statusLabel.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-10],
    ]];

    [self reload];
    return self;
}

- (void)reload {
    [_spinner startAnimation:nil];
    _statusLabel.stringValue = L(@"Loading…");
    [IDOpusRclone listRemote:_rcloneSpec path:_currentPath completion:^(NSArray<NSDictionary *> *entries, NSError *err) {
        [self->_spinner stopAnimation:nil];
        if (err) {
            self->_statusLabel.stringValue = err.localizedDescription;
            return;
        }
        [self->_entries setArray:entries];
        /* Sort: dirs first, then by name case-insensitively. */
        [self->_entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            BOOL ad = [a[@"IsDir"] boolValue], bd = [b[@"IsDir"] boolValue];
            if (ad != bd) return ad ? NSOrderedAscending : NSOrderedDescending;
            return [(NSString *)a[@"Name"] caseInsensitiveCompare:(NSString *)b[@"Name"]];
        }];
        [self->_tableView reloadData];
        self->_statusLabel.stringValue = [NSString stringWithFormat:L(@"%lu items"),
            (unsigned long)self->_entries.count];
        self.window.title = [NSString stringWithFormat:@"%@ — %@", self->_displayName, self->_currentPath];
        self->_pathLabel.stringValue = self->_currentPath;
    }];
}

- (void)goUp:(id)sender {
    if ([_currentPath isEqualToString:@"/"] || _currentPath.length == 0) return;
    NSString *parent = [_currentPath stringByDeletingLastPathComponent];
    if (parent.length == 0) parent = @"/";
    _currentPath = [parent copy];
    [self reload];
}

- (void)refresh:(id)sender { [self reload]; }

- (void)openSelection:(id)sender {
    NSInteger row = _tableView.clickedRow >= 0 ? _tableView.clickedRow : _tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_entries.count) return;
    NSDictionary *e = _entries[row];
    if (![e[@"IsDir"] boolValue]) return;
    NSString *next = [_currentPath stringByAppendingPathComponent:e[@"Name"]];
    _currentPath = [next copy];
    [self reload];
}

- (void)downloadSelection:(id)sender {
    NSIndexSet *sel = _tableView.selectedRowIndexes;
    if (sel.count == 0) { _statusLabel.stringValue = L(@"No items selected."); return; }
    ListerWindowController *dest = _appDelegate.activeDest ?: _appDelegate.activeSource;
    if (!dest) {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.canChooseFiles = NO;
        panel.canChooseDirectories = YES;
        panel.allowsMultipleSelection = NO;
        panel.prompt = L(@"Download here");
        if ([panel runModal] != NSModalResponseOK) return;
        [self _downloadSelectedIndexes:sel toDir:panel.URL.path];
    } else {
        [self _downloadSelectedIndexes:sel toDir:dest.currentPath];
    }
}

- (void)_downloadSelectedIndexes:(NSIndexSet *)sel toDir:(NSString *)destDir {
    ProgressSheetController *job = [[ProgressSheetController alloc] init];
    job.titleLabel.stringValue = [NSString stringWithFormat:L(@"Downloading from %@"), _displayName];
    [job.spinner startAnimation:nil];
    [[JobsPanelController shared] addJobRow:job.rowView];

    __block NSUInteger remaining = sel.count;
    __block BOOL anyFailed = NO;
    __block NSUInteger i = 0;
    NSUInteger total = sel.count;

    [sel enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSDictionary *entry = self->_entries[idx];
        NSString *name = entry[@"Name"];
        NSString *remotePath = [self->_currentPath stringByAppendingPathComponent:name];
        i++;
        job.fileLabel.stringValue = [NSString stringWithFormat:@"(%lu/%lu) %@",
            (unsigned long)i, (unsigned long)total, name];
        [IDOpusRclone copyFromRemote:self->_rcloneSpec
                          remotePath:remotePath
                             toLocal:destDir
                            progress:^(NSString *line) {
            job.fileLabel.stringValue = line;
        } completion:^(int status) {
            if (status != 0) anyFailed = YES;
            if (--remaining == 0) {
                [job.spinner stopAnimation:nil];
                [[JobsPanelController shared] removeJobRow:job.rowView];
                [self->_appDelegate refreshAllListersShowing:destDir];
                if (anyFailed) {
                    [self->_appDelegate showAlert:L(@"Download")
                                             info:L(@"Some items could not be downloaded. See JobsPanel log for details.")
                                            style:NSAlertStyleWarning];
                }
            }
        }];
    }];
}

#pragma mark NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return _entries.count; }

- (NSView *)tableView:(NSTableView *)tv
    viewForTableColumn:(NSTableColumn *)col
                   row:(NSInteger)row {
    NSDictionary *e = _entries[row];
    NSString *ident = col.identifier;
    NSString *text = @"";
    if ([ident isEqualToString:@"name"]) {
        text = e[@"Name"];
        if ([e[@"IsDir"] boolValue]) text = [text stringByAppendingString:@"/"];
    } else if ([ident isEqualToString:@"size"]) {
        if ([e[@"IsDir"] boolValue]) text = @"—";
        else {
            char buf[32];
            pal_format_size([e[@"Size"] longLongValue], buf, sizeof(buf));
            text = [NSString stringWithUTF8String:buf];
        }
    } else if ([ident isEqualToString:@"date"]) {
        text = e[@"ModTime"] ?: @"";
        /* rclone returns RFC3339; trim the fractional seconds + Z for display */
        NSRange dot = [text rangeOfString:@"."];
        if (dot.location != NSNotFound) text = [text substringToIndex:dot.location];
        text = [text stringByReplacingOccurrencesOfString:@"T" withString:@" "];
    }
    NSTableCellView *cell = [tv makeViewWithIdentifier:ident owner:nil];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, col.width, 20)];
        cell.identifier = ident;
        NSTextField *tf = [[NSTextField alloc] initWithFrame:cell.bounds];
        tf.bordered = NO; tf.drawsBackground = NO; tf.editable = NO;
        tf.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
        tf.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        tf.lineBreakMode = NSLineBreakByTruncatingTail;
        cell.textField = tf;
        [cell addSubview:tf];
    }
    cell.textField.stringValue = text ?: @"";
    if ([ident isEqualToString:@"name"] && [e[@"IsDir"] boolValue]) {
        cell.textField.textColor = [NSColor systemCyanColor];
    } else {
        cell.textField.textColor = [NSColor labelColor];
    }
    return cell;
}

@end

#pragma mark - Main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        IDOpusAppDelegate *delegate = [[IDOpusAppDelegate alloc] init];
        app.delegate = delegate;

        [app activateIgnoringOtherApps:YES];
        [app run];
    }
    return 0;
}
