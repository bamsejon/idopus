/*
 * iDOpus — GUI: Application Delegate
 *
 * Sets up the macOS app: main menu, initial window, buffer cache.
 */

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import <QuickLookThumbnailing/QuickLookThumbnailing.h>
#import <CoreServices/CoreServices.h>
#import <objc/runtime.h>
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

/* --- App Delegate --- */

@interface IDOpusAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (nonatomic) buffer_cache_t *bufferCache;
@property (nonatomic, strong) NSMutableArray<ListerWindowController *> *listerControllers;
@property (nonatomic, weak) ListerWindowController *activeSource;
@property (nonatomic, weak) ListerWindowController *activeDest;
@property (nonatomic, strong) ButtonBankPanelController *buttonBankPanel;
@property (nonatomic, strong) PreferencesWindowController *preferencesWindow;

- (void)refreshAllListersShowing:(NSString *)path;
- (void)showAlert:(NSString *)title info:(NSString *)info style:(NSAlertStyle)style;
- (void)performDropOntoLister:(ListerWindowController *)dest
                     fromURLs:(NSArray<NSURL *> *)urls
                       asMove:(BOOL)isMove;
- (NSString *)uniqueChild:(NSString *)name inDir:(NSString *)dir;
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

/* Forward-declared: used inside ListerWindowController before its own
 * @implementation. Full @interface + @implementation follow below. */
@interface ProgressSheetController : NSWindowController
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *fileLabel;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, strong) NSButton *cancelButton;
@property (atomic, assign) BOOL cancelled;
- (void)runOperation:(BOOL)isMove
               paths:(NSArray<NSString *> *)paths
               names:(NSArray<NSString *> *)names
              destDir:(NSString *)destDir
          sourceWindow:(NSWindow *)srcWin
           completion:(void (^)(NSArray<NSString *> *failed))completion;
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
    _pathControl = [[NSPathControl alloc] init];
    _pathControl.URL = [NSURL fileURLWithPath:_currentPath];
    _pathControl.pathStyle = NSPathStyleStandard;
    _pathControl.backgroundColor = [NSColor controlBackgroundColor];
    _pathControl.target = self;
    _pathControl.action = @selector(pathControlAction:);
    _pathControl.doubleAction = @selector(pathControlDoubleClick:);
    _pathControl.translatesAutoresizingMaskIntoConstraints = NO;
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
    [menu addItemWithTitle:@"Open"           action:@selector(openSelectionAction:) keyEquivalent:@""].target = self;
    NSMenuItem *actions = [menu addItemWithTitle:@"Actions" action:NULL keyEquivalent:@""];
    actions.submenu = [[NSMenu alloc] initWithTitle:@"Actions"];
    actions.tag = 2;  /* identify in menuNeedsUpdate */
    NSMenuItem *openWith = [menu addItemWithTitle:@"Open With" action:NULL keyEquivalent:@""];
    openWith.submenu = [[NSMenu alloc] initWithTitle:@"Open With"];
    [menu addItemWithTitle:@"Reveal in Finder" action:@selector(revealInFinderAction:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:@"Open in Terminal" action:@selector(openInTerminalAction:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:@"Copy Path"       action:@selector(copyPathAction:) keyEquivalent:@""].target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Copy to…"        action:@selector(copyToAction:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:@"Move to…"        action:@selector(moveToAction:) keyEquivalent:@""].target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Duplicate"       action:@selector(duplicateAction:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:@"Compress"       action:@selector(compressAction:)  keyEquivalent:@""].target = self;
    NSMenuItem *extract = [menu addItemWithTitle:@"Extract" action:@selector(extractAction:) keyEquivalent:@""];
    extract.target = self;
    extract.tag = 1;  /* identify for menuNeedsUpdate */
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Info"           action:@selector(infoAction:)    keyEquivalent:@""].target = _appDelegate;
    [menu addItemWithTitle:@"Rename…"        action:@selector(renameAction:)  keyEquivalent:@""].target = _appDelegate;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Move to Trash"  action:@selector(deleteAction:)  keyEquivalent:@""].target = _appDelegate;
    _tableView.menu = menu;

    /* Drag-and-drop — accept file URLs from anywhere (other Listers or Finder) */
    [_tableView registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    [_tableView setDraggingSourceOperationMask:NSDragOperationCopy | NSDragOperationMove
                                     forLocal:YES];
    [_tableView setDraggingSourceOperationMask:NSDragOperationCopy
                                     forLocal:NO];

    scrollView.documentView = _tableView;
    [content addSubview:scrollView];

    /* Button bank (DOpus-style row of text buttons between path field and file list) */
    NSStackView *bank = [[NSStackView alloc] init];
    bank.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bank.spacing = 4;
    bank.translatesAutoresizingMaskIntoConstraints = NO;
    bank.distribution = NSStackViewDistributionFill;

    struct { NSString *title; SEL action; id target; } btns[] = {
        { @"Copy",    @selector(copyAction:),    _appDelegate },
        { @"Move",    @selector(moveAction:),    _appDelegate },
        { @"Delete",  @selector(deleteAction:),  _appDelegate },
        { @"Rename",  @selector(renameAction:),  _appDelegate },
        { @"MakeDir", @selector(makeDirAction:), _appDelegate },
        { @"Info",    @selector(infoAction:),    _appDelegate },
        { @"Filter",  @selector(filterAction:),  _appDelegate },
        { @"",        NULL, nil },  /* separator */
        { @"Parent",  @selector(goUp:),          self },
        { @"Root",    @selector(goRoot:),        self },
        { @"",        NULL, nil },
        { @"All",     @selector(selectAllFiles:),   self },
        { @"None",    @selector(deselectAllFiles:), self },
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
    _stateLabel = [NSTextField labelWithString:@"OFF"];
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

- (void)loadPath:(NSString *)path {
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
}

#pragma mark Actions

- (void)goUp:(id)sender {
    char parent[4096];
    pal_path_parent([_currentPath fileSystemRepresentation], parent, sizeof(parent));
    [self loadPath:[NSString stringWithUTF8String:parent]];
}

- (void)refresh:(id)sender {
    [self loadPath:_currentPath];
}

- (void)goRoot:(id)sender {
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
        if ([it.title isEqualToString:@"Open With"]) openWithItem = it;
        if (it.tag == 1 && [it.title isEqualToString:@"Extract"]) extractItem = it;
        if (it.tag == 2 && [it.title isEqualToString:@"Actions"]) actionsItem = it;
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

- (void)pathControlAction:(NSPathControl *)sender {
    NSPathControlItem *clicked = sender.clickedPathItem;
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
    NSColor *fg, *bg;
    switch (_state) {
        case ListerStateSource:
            text = @"SOURCE";
            fg = [NSColor whiteColor];
            bg = [NSColor systemBlueColor];
            break;
        case ListerStateDest:
            text = @"DEST";
            fg = [NSColor whiteColor];
            bg = [NSColor systemOrangeColor];
            break;
        case ListerStateOff:
        default:
            text = @"OFF";
            fg = [NSColor secondaryLabelColor];
            bg = [NSColor clearColor];
            break;
    }
    _stateLabel.stringValue = text;
    _stateLabel.textColor = fg;
    _stateLabel.backgroundColor = bg;
}

#pragma mark NSWindowDelegate

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [_appDelegate promoteToSource:self];
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
    NSRect frame = NSMakeRect(0, 0, 440, 120);
    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self = [super initWithWindow:w];
    if (!self) return nil;

    NSView *content = w.contentView;
    _titleLabel = [NSTextField labelWithString:@"Copying…"];
    _titleLabel.font = [NSFont boldSystemFontOfSize:13];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_titleLabel];

    _fileLabel = [NSTextField labelWithString:@""];
    _fileLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _fileLabel.textColor = [NSColor secondaryLabelColor];
    _fileLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _fileLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_fileLabel];

    _spinner = [[NSProgressIndicator alloc] init];
    _spinner.style = NSProgressIndicatorStyleBar;
    _spinner.indeterminate = YES;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_spinner];

    _cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
    _cancelButton.keyEquivalent = @"\033";  /* Esc */
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_cancelButton];

    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [_titleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:12],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],

        [_fileLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [_fileLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [_fileLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],

        [_spinner.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [_spinner.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [_spinner.topAnchor constraintEqualToAnchor:_fileLabel.bottomAnchor constant:8],

        [_cancelButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [_cancelButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-12],
    ]];

    return self;
}

- (void)cancel:(id)sender {
    self.cancelled = YES;
    _cancelButton.enabled = NO;
    _titleLabel.stringValue = @"Cancelling…";
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

    [alert addButtonWithTitle:@"Replace"];
    [alert addButtonWithTitle:@"Skip"];
    [alert addButtonWithTitle:@"Keep Both"];
    [alert addButtonWithTitle:@"Cancel All"];
    if (bothAreDirs) [alert addButtonWithTitle:@"Merge"];

    NSButton *applyToAll = [NSButton checkboxWithTitle:@"Apply to all remaining conflicts"
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

    self.titleLabel.stringValue = isMove ? @"Moving…" : @"Copying…";
    [self.spinner startAnimation:nil];

    [srcWin beginSheet:self.window completionHandler:nil];

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
                self.fileLabel.stringValue = [NSString stringWithFormat:@"(%lu/%lu) %@",
                                              (unsigned long)(i + 1),
                                              (unsigned long)paths.count,
                                              name];
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
            [srcWin endSheet:self.window];
            if (completion) completion(failed);
        });
    });
}

@end

#pragma mark - Button Bank Panel

/* Floating Magellan-style panel with a grid of action buttons, shared across
 * all Listers. Non-activating: clicking a button does NOT steal key focus from
 * the active source Lister, so source/dest semantics remain stable.
 * Buttons route to IDOpusAppDelegate methods that operate on activeSource. */
@interface ButtonBankPanelController : NSWindowController
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
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
                               NSWindowStyleMaskClosable |
                               NSWindowStyleMaskResizable |
                               NSWindowStyleMaskNonactivatingPanel;
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
                                                styleMask:style
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.title = @"Buttons";
    panel.floatingPanel = YES;
    panel.hidesOnDeactivate = YES;   /* only float while iDOpus is the active app */
    panel.level = NSFloatingWindowLevel;
    panel.becomesKeyOnlyIfNeeded = YES;
    panel.contentMinSize = NSMakeSize(70, 200);

    self = [super initWithWindow:panel];
    if (!self) return nil;
    _appDelegate = appDelegate;

    [self buildGrid];
    return self;
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
        { @"Copy",    @selector(copyAction:)    },
        { @"Move",    @selector(moveAction:)    },
        { @"Delete",  @selector(deleteAction:)  },
        { @"Rename",  @selector(renameAction:)  },
        { @"MakeDir", @selector(makeDirAction:) },
        { @"Info",    @selector(infoAction:)    },
        { @"Filter",  @selector(filterAction:)  },
        { @"Parent",  @selector(parentAction:)  },
        { @"Root",    @selector(rootAction:)    },
        { @"Refresh", @selector(refreshAction:) },
        { @"All",     @selector(allAction:)     },
        { @"None",    @selector(noneAction:)    },
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
    w.title = @"Preferences";
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

    NSTextField *header = [NSTextField labelWithString:@"General"];
    header.font = [NSFont boldSystemFontOfSize:13];
    [col addArrangedSubview:header];

    [col addArrangedSubview:[self makeCheckbox:@"Hide dotfiles by default"
                                           key:@"prefHideDotfilesDefault" defaultOn:YES]];
    [col addArrangedSubview:[self makeCheckbox:@"Restore last-open paths at launch"
                                           key:@"prefRestoreLastPaths" defaultOn:YES]];
    [col addArrangedSubview:[self makeCheckbox:@"Open dual-pane at launch"
                                           key:@"prefDualPaneStartup" defaultOn:YES]];
    [col addArrangedSubview:[self makeCheckbox:@"Show Button Bank at launch"
                                           key:@"prefButtonBankVisible" defaultOn:YES]];

    NSTextField *deleteHeader = [NSTextField labelWithString:@"File operations"];
    deleteHeader.font = [NSFont boldSystemFontOfSize:13];
    [col addArrangedSubview:deleteHeader];

    [col addArrangedSubview:[self makeCheckbox:@"Delete sends items to Trash (recommended)"
                                           key:@"prefDeleteToTrash" defaultOn:YES]];

    /* Footer: Reset button */
    NSButton *reset = [NSButton buttonWithTitle:@"Reset All Preferences…"
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
    NSArray<NSString *> *lastPaths = restore ? [u arrayForKey:@"lastPaths"] : nil;
    NSString *leftPath  = (lastPaths.count >= 1 && [fileMgr fileExistsAtPath:lastPaths[0]])
                          ? lastPaths[0] : NSHomeDirectory();
    NSString *rightPath = (lastPaths.count >= 2 && [fileMgr fileExistsAtPath:lastPaths[1]])
                          ? lastPaths[1] : NSHomeDirectory();
    (void)bankFrame;

    if (dualPane) {
        ListerWindowController *left  = [self newListerWindow:leftPath  frame:leftFrame];
        ListerWindowController *right = [self newListerWindow:rightPath frame:rightFrame];
        [left.window setFrame:leftFrame display:YES animate:NO];
        [right.window setFrame:rightFrame display:YES animate:NO];

        _buttonBankPanel = [[ButtonBankPanelController alloc] initWithAppDelegate:self];
        [_buttonBankPanel positionBetweenLeftFrame:leftFrame rightFrame:rightFrame];
        if (showBank) [_buttonBankPanel.window orderFront:nil];

        [right.window makeKeyAndOrderFront:nil];
    } else {
        NSRect single = NSMakeRect(x, y, totalW, h);
        ListerWindowController *one = [self newListerWindow:leftPath frame:single];
        [one.window setFrame:single display:YES animate:NO];

        _buttonBankPanel = [[ButtonBankPanelController alloc] initWithAppDelegate:self];
        if (showBank) [_buttonBankPanel.window orderFront:nil];

        [one.window makeKeyAndOrderFront:nil];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    /* Save the currentPath of each live Lister so next launch can restore */
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (ListerWindowController *lw in _listerControllers) {
        if (lw.currentPath) [paths addObject:lw.currentPath];
    }
    if (paths.count > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:paths forKey:@"lastPaths"];
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
    [appMenu addItemWithTitle:@"About iDOpus" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *prefsItem = [appMenu addItemWithTitle:@"Preferences…"
                                               action:@selector(showPreferencesAction:)
                                        keyEquivalent:@","];
    prefsItem.target = self;
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit iDOpus" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [mainMenu addItem:appItem];

    /* File menu */
    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"New Lister" action:@selector(newListerAction:) keyEquivalent:@"n"];
    NSMenuItem *newFileMenu = [fileMenu addItemWithTitle:@"New File…"
                                                  action:@selector(newFileAction:)
                                           keyEquivalent:@"n"];
    newFileMenu.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [fileMenu addItemWithTitle:@"New Tab"
                        action:@selector(newTabAction:)
                 keyEquivalent:@"t"];
    NSMenuItem *splitItem = [fileMenu addItemWithTitle:@"Split Display"
                                                action:@selector(splitDisplayAction:)
                                         keyEquivalent:@"N"];
    splitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Back"    action:@selector(goBack:)    keyEquivalent:@"["];
    [fileMenu addItemWithTitle:@"Forward" action:@selector(goForward:) keyEquivalent:@"]"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Find"      action:@selector(performFindPanelAction:) keyEquivalent:@"f"];
    NSMenuItem *gotoItem = [fileMenu addItemWithTitle:@"Go to Path…"
                                               action:@selector(goToPathAction:)
                                        keyEquivalent:@"l"];
    gotoItem.target = self;
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    fileItem.submenu = fileMenu;
    [mainMenu addItem:fileItem];

    /* Functions menu — matches DOpus F-key bindings */
    NSMenuItem *funcItem = [[NSMenuItem alloc] init];
    NSMenu *funcMenu = [[NSMenu alloc] initWithTitle:@"Functions"];
    [self addFunctionItem:funcMenu title:@"Rename"  action:@selector(renameAction:)  fkey:NSF3FunctionKey];
    [self addFunctionItem:funcMenu title:@"Copy"    action:@selector(copyAction:)    fkey:NSF5FunctionKey];
    [self addFunctionItem:funcMenu title:@"Move"    action:@selector(moveAction:)    fkey:NSF6FunctionKey];
    [self addFunctionItem:funcMenu title:@"MakeDir" action:@selector(makeDirAction:) fkey:NSF7FunctionKey];
    [self addFunctionItem:funcMenu title:@"Delete"  action:@selector(deleteAction:)  fkey:NSF8FunctionKey];
    [self addFunctionItem:funcMenu title:@"Info"    action:@selector(infoAction:)    fkey:NSF9FunctionKey];
    [funcMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *filterItem = [funcMenu addItemWithTitle:@"Filter…"
                                                 action:@selector(filterAction:)
                                          keyEquivalent:@"f"];
    filterItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    NSMenuItem *selectItem = [funcMenu addItemWithTitle:@"Select By Pattern…"
                                                 action:@selector(selectPatternAction:)
                                          keyEquivalent:@"a"];
    selectItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [funcMenu addItemWithTitle:@"Compare With Destination"
                        action:@selector(compareSourceWithDestAction:)
                 keyEquivalent:@""];
    [funcMenu addItem:[NSMenuItem separatorItem]];
    [funcMenu addItemWithTitle:@"Add Custom Button…"    action:@selector(addCustomButtonAction:)    keyEquivalent:@""];
    [funcMenu addItemWithTitle:@"Edit Custom Button…"   action:@selector(editCustomButtonAction:)   keyEquivalent:@""];
    [funcMenu addItemWithTitle:@"Remove Custom Button…" action:@selector(removeCustomButtonAction:) keyEquivalent:@""];
    [funcMenu addItem:[NSMenuItem separatorItem]];
    [funcMenu addItemWithTitle:@"Add File Type Action…"    action:@selector(addFileTypeActionAction:)    keyEquivalent:@""];
    [funcMenu addItemWithTitle:@"Remove File Type Action…" action:@selector(manageFileTypeActionsAction:) keyEquivalent:@""];
    funcItem.submenu = funcMenu;
    [mainMenu addItem:funcItem];

    /* Bookmarks menu */
    NSMenuItem *bmItem = [[NSMenuItem alloc] init];
    NSMenu *bmMenu = [[NSMenu alloc] initWithTitle:@"Bookmarks"];
    bmMenu.autoenablesItems = NO;
    bmMenu.delegate = self;     /* rebuild on open */
    bmItem.submenu = bmMenu;
    [mainMenu addItem:bmItem];

    /* Window menu — AppKit auto-populates Minimize, Zoom, Bring All to Front,
     * Show Next/Previous Tab (⌃Tab / ⌃⇧Tab), Move Tab to New Window, etc.
     * once we register the menu via setWindowsMenu:. */
    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
    windowItem.submenu = windowMenu;
    [mainMenu addItem:windowItem];
    [NSApp setWindowsMenu:windowMenu];

    /* View menu */
    NSMenuItem *viewItem = [[NSMenuItem alloc] init];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItemWithTitle:@"Show Hidden Files" action:@selector(toggleHidden:) keyEquivalent:@"."];

    /* Sort By submenu */
    NSMenuItem *sortItem = [viewMenu addItemWithTitle:@"Sort By" action:NULL keyEquivalent:@""];
    NSMenu *sortSub = [[NSMenu alloc] initWithTitle:@"Sort By"];
    struct { NSString *title; int field; } sorts[] = {
        { @"Name",      SORT_NAME      },
        { @"Size",      SORT_SIZE      },
        { @"Date",      SORT_DATE      },
        { @"Type",      SORT_EXTENSION },
    };
    for (size_t i = 0; i < sizeof(sorts)/sizeof(sorts[0]); i++) {
        NSMenuItem *mi = [sortSub addItemWithTitle:sorts[i].title
                                            action:@selector(sortByAction:)
                                     keyEquivalent:@""];
        mi.tag = sorts[i].field;
    }
    [sortSub addItem:[NSMenuItem separatorItem]];
    [sortSub addItemWithTitle:@"Reverse"      action:@selector(toggleReverseSortAction:) keyEquivalent:@""];
    [sortSub addItemWithTitle:@"Files Mixed"  action:@selector(toggleFilesMixedAction:) keyEquivalent:@""];
    sortItem.submenu = sortSub;

    /* Show Columns submenu (hide/show columns) — applies to all Listers */
    NSMenuItem *colsItem = [viewMenu addItemWithTitle:@"Show Columns" action:NULL keyEquivalent:@""];
    NSMenu *colsSub = [[NSMenu alloc] initWithTitle:@"Show Columns"];
    colsSub.autoenablesItems = NO;
    NSArray<NSString *> *colIds = @[@"name", @"size", @"date", @"type"];
    NSArray<NSString *> *colTitles = @[@"Name", @"Size", @"Date", @"Type"];
    NSSet<NSString *> *hidden = [NSSet setWithArray:
        ([[NSUserDefaults standardUserDefaults] arrayForKey:@"hiddenColumns"] ?: @[])];
    for (NSUInteger i = 0; i < colIds.count; i++) {
        NSMenuItem *mi = [colsSub addItemWithTitle:colTitles[i]
                                            action:@selector(toggleColumnVisibility:)
                                     keyEquivalent:@""];
        mi.representedObject = colIds[i];
        mi.state = [hidden containsObject:colIds[i]] ? NSControlStateValueOff : NSControlStateValueOn;
        /* Name column should not be hide-able */
        if ([colIds[i] isEqualToString:@"name"]) mi.enabled = NO;
    }
    colsItem.submenu = colsSub;

    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *qlItem = [viewMenu addItemWithTitle:@"Quick Look"
                                             action:@selector(toggleQuickLook:)
                                      keyEquivalent:@" "];
    qlItem.keyEquivalentModifierMask = 0;  /* bare Space */
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Show/Hide Buttons" action:@selector(toggleButtonBank:) keyEquivalent:@"b"];
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
}

- (void)listerClosing:(ListerWindowController *)ctrl {
    if (_activeSource == ctrl) _activeSource = nil;
    if (_activeDest == ctrl) _activeDest = nil;
    [_listerControllers removeObject:ctrl];
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
    NSArray<NSString *> *names = @[ @"Desktop", @"Documents", @"Downloads",
                                     @"Applications", @"Pictures", @"Movies", @"Music" ];
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    [out addObject:@{ @"name": @"Home", @"path": NSHomeDirectory() }];
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
    if (![menu.title isEqualToString:@"Bookmarks"]) return;
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
        NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:@"Devices" action:NULL keyEquivalent:@""];
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
    NSMenuItem *add = [menu addItemWithTitle:@"Add Current…"
                                      action:@selector(addCurrentBookmark:)
                               keyEquivalent:@"d"];
    add.target = self;

    if (userBm.count > 0) {
        NSMenuItem *rm = [menu addItemWithTitle:@"Remove Bookmark…"
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
    else             [w orderFront:nil];
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
