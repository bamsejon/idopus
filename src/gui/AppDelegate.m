/*
 * iDOpus — GUI: Application Delegate
 *
 * Sets up the macOS app: main menu, initial window, buffer cache.
 */

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
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

/* --- App Delegate --- */

@interface IDOpusAppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic) buffer_cache_t *bufferCache;
@property (nonatomic, strong) NSMutableArray<ListerWindowController *> *listerControllers;
@property (nonatomic, weak) ListerWindowController *activeSource;
@property (nonatomic, weak) ListerWindowController *activeDest;
@property (nonatomic, strong) ButtonBankPanelController *buttonBankPanel;

- (void)refreshAllListersShowing:(NSString *)path;
- (void)showAlert:(NSString *)title info:(NSString *)info style:(NSAlertStyle)style;
- (void)performDropOntoLister:(ListerWindowController *)dest
                     fromURLs:(NSArray<NSURL *> *)urls
                       asMove:(BOOL)isMove;
@end

@interface IDOpusAppDelegate ()
- (void)createMainMenu;
- (ListerWindowController *)newListerWindow:(NSString *)path frame:(NSRect)frame;
- (void)promoteToSource:(ListerWindowController *)ctrl;
- (void)listerClosing:(ListerWindowController *)ctrl;

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
- (void)toggleQuickLook:(id)sender;
@end

#pragma mark - Lister Table Data

#pragma mark - Lister Window Controller (interface)

@class ListerDataSource;

@interface ListerWindowController : NSWindowController <NSWindowDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate>
@property (nonatomic, strong) ListerDataSource *dataSource;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSTextField *pathField;
@property (nonatomic, strong) NSTextField *stateLabel;  /* SOURCE/DEST/OFF */
@property (nonatomic, strong) NSTextField *statusBar;   /* file/dir counts */
@property (nonatomic, strong) NSStackView *buttonBank;
@property (nonatomic, copy) NSString *currentPath;
@property (nonatomic, assign) ListerState state;
@property (nonatomic, weak) IDOpusAppDelegate *appDelegate;
- (void)setState:(ListerState)state;
- (NSArray<NSString *> *)selectedPaths;
- (NSArray<NSString *> *)selectedNames;
- (void)reloadBuffer;
- (void)updateStatusBar;
@end

#pragma mark - Lister Table Data

/* Wraps a dir_buffer_t for NSTableView display */
@interface ListerDataSource : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic) dir_buffer_t *buffer;
@property (nonatomic, assign) NSTableView *tableView;
@property (nonatomic, copy) void (^onColumnClick)(NSString *identifier);
@property (nonatomic, copy) NSString *showPattern;   /* nil = show all */
@property (nonatomic, copy) NSString *hidePattern;   /* nil = hide none */
@property (nonatomic, assign) BOOL hideDotfiles;     /* default YES */
@property (nonatomic, weak) ListerWindowController *owner;  /* for drag-drop access */
- (void)loadPath:(NSString *)path;
- (void)sortByColumn:(NSString *)identifier;
- (void)applyCurrentFilter;
@end

@implementation ListerDataSource

- (instancetype)init {
    self = [super init];
    if (self) {
        _buffer = dir_buffer_create();
        _hideDotfiles = YES;    /* DOpus default: dotfiles filtered out */
    }
    return self;
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
        NSString *name = [NSString stringWithUTF8String:entry->name ?: ""];
        if (dir_entry_is_dir(entry))
            text = [NSString stringWithFormat:@"\U0001F4C1 %@", name];
        else
            text = [NSString stringWithFormat:@"   %@", name];
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
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:nil];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 20)];
        cell.identifier = identifier;

        NSTextField *tf = [[NSTextField alloc] initWithFrame:cell.bounds];
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
    return 20.0;
}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn {
    [self sortByColumn:tableColumn.identifier];
    if (_onColumnClick) _onColumnClick(tableColumn.identifier);
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

    /* Path field (top) */
    _pathField = [NSTextField textFieldWithString:_currentPath];
    _pathField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _pathField.translatesAutoresizingMaskIntoConstraints = NO;
    _pathField.target = self;
    _pathField.action = @selector(pathFieldAction:);
    [content addSubview:_pathField];

    /* Back button */
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

    _tableView = [[NSTableView alloc] init];
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.allowsMultipleSelection = YES;
    _tableView.doubleAction = @selector(tableDoubleClick:);
    _tableView.target = self;
    _tableView.style = NSTableViewStyleFullWidth;

    /* Columns */
    struct { NSString *ident; NSString *title; CGFloat width; CGFloat min; } cols[] = {
        { @"name", @"Name",   300, 150 },
        { @"size", @"Size",    80,  60 },
        { @"date", @"Date",   140, 100 },
        { @"type", @"Type",    60,  40 },
    };
    for (int i = 0; i < 4; i++) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:cols[i].ident];
        col.title = cols[i].title;
        col.width = cols[i].width;
        col.minWidth = cols[i].min;
        col.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:cols[i].ident ascending:YES];
        [_tableView addTableColumn:col];
    }

    _tableView.dataSource = _dataSource;
    _tableView.delegate = _dataSource;
    _dataSource.tableView = _tableView;
    _dataSource.owner = self;

    /* Right-click context menu — items route to appDelegate actions */
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Open"           action:@selector(openSelectionAction:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:@"Reveal in Finder" action:@selector(revealInFinderAction:) keyEquivalent:@""].target = self;
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
        [backBtn.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [backBtn.topAnchor constraintEqualToAnchor:content.topAnchor constant:8],
        [backBtn.widthAnchor constraintEqualToConstant:32],

        [refreshBtn.leadingAnchor constraintEqualToAnchor:backBtn.trailingAnchor constant:4],
        [refreshBtn.topAnchor constraintEqualToAnchor:content.topAnchor constant:8],
        [refreshBtn.widthAnchor constraintEqualToConstant:32],

        [_pathField.leadingAnchor constraintEqualToAnchor:refreshBtn.trailingAnchor constant:8],
        [_pathField.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        [_pathField.centerYAnchor constraintEqualToAnchor:backBtn.centerYAnchor],

        [_buttonBank.topAnchor constraintEqualToAnchor:backBtn.bottomAnchor constant:6],
        [_buttonBank.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [_buttonBank.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],

        [scrollView.topAnchor constraintEqualToAnchor:_buttonBank.bottomAnchor constant:6],
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
    self.window.title = [NSString stringWithFormat:@"iDOpus — %@", path.lastPathComponent];
    [_dataSource loadPath:path];
    [self updateStatusBar];
}

- (void)updateStatusBar {
    dir_buffer_t *buf = _dataSource.buffer;
    if (!buf) return;
    char sizeStr[32];
    pal_format_size(buf->stats.total_bytes, sizeStr, sizeof(sizeStr));
    char freeStr[32];
    pal_format_size(buf->disk_free, freeStr, sizeof(freeStr));
    _statusBar.stringValue = [NSString stringWithFormat:
        @"%d files, %d dirs (%s) — %s free",
        buf->stats.total_files, buf->stats.total_dirs, sizeStr, freeStr];
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

- (void)pathFieldAction:(NSTextField *)sender {
    NSString *path = sender.stringValue;
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
        /* Open file with default app */
        char fullpath[4096];
        pal_path_join([_currentPath fileSystemRepresentation],
                      entry->name, fullpath, sizeof(fullpath));
        [[NSWorkspace sharedWorkspace] openURL:
            [NSURL fileURLWithPath:[NSString stringWithUTF8String:fullpath]]];
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
    [_dataSource loadPath:_currentPath];
    [self updateStatusBar];
}

@end

#pragma mark - Progress Sheet (copy / move)

/* Modal sheet attached to the source Lister, shown during long copy/move
 * operations. Loop runs on a background queue; label and cancel button are
 * updated/checked on the main queue. */
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
    NSView *content = self.window.contentView;

    /* Vertical stack of single-button rows — DOpus Magellan default layout
     * when the Button Bank sits between two side-by-side Listers. */
    struct { NSString *title; SEL action; } buttons[] = {
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
    NSInteger n = sizeof(buttons)/sizeof(buttons[0]);

    NSStackView *column = [[NSStackView alloc] init];
    column.orientation = NSUserInterfaceLayoutOrientationVertical;
    column.spacing = 4;
    column.distribution = NSStackViewDistributionFillEqually;
    column.alignment = NSLayoutAttributeCenterX;
    column.translatesAutoresizingMaskIntoConstraints = NO;

    for (NSInteger i = 0; i < n; i++) {
        NSButton *b = [NSButton buttonWithTitle:buttons[i].title
                                         target:_appDelegate
                                         action:buttons[i].action];
        /* ShadowlessSquare + low vertical hugging lets buttons stretch to
         * fill the panel height — needed so the bank spans full Lister height. */
        b.bezelStyle = NSBezelStyleShadowlessSquare;
        b.font = [NSFont systemFontOfSize:11];
        [b setContentHuggingPriority:NSLayoutPriorityDefaultLow
                      forOrientation:NSLayoutConstraintOrientationVertical];
        b.translatesAutoresizingMaskIntoConstraints = NO;
        [column addArrangedSubview:b];
        [b.leadingAnchor constraintEqualToAnchor:column.leadingAnchor].active = YES;
        [b.trailingAnchor constraintEqualToAnchor:column.trailingAnchor].active = YES;
    }

    [content addSubview:column];
    [NSLayoutConstraint activateConstraints:@[
        [column.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:6],
        [column.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-6],
        [column.topAnchor constraintEqualToAnchor:content.topAnchor constant:6],
        [column.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-6],
    ]];
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

    ListerWindowController *left  = [self newListerWindow:NSHomeDirectory() frame:leftFrame];
    ListerWindowController *right = [self newListerWindow:NSHomeDirectory() frame:rightFrame];
    [left.window setFrame:leftFrame display:YES animate:NO];
    [right.window setFrame:rightFrame display:YES animate:NO];

    /* Button Bank panel docked between the two Listers */
    _buttonBankPanel = [[ButtonBankPanelController alloc] initWithAppDelegate:self];
    (void)bankFrame;
    [_buttonBankPanel.window orderFront:nil];
    [_buttonBankPanel positionBetweenLeftFrame:leftFrame rightFrame:rightFrame];

    /* Keep the SOURCE Lister key after bringing up the panel */
    [right.window makeKeyAndOrderFront:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
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
    [appMenu addItemWithTitle:@"Quit iDOpus" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [mainMenu addItem:appItem];

    /* File menu */
    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"New Lister" action:@selector(newListerAction:) keyEquivalent:@"n"];
    NSMenuItem *splitItem = [fileMenu addItemWithTitle:@"Split Display"
                                                action:@selector(splitDisplayAction:)
                                         keyEquivalent:@"N"];
    splitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
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
    funcItem.submenu = funcMenu;
    [mainMenu addItem:funcItem];

    /* View menu */
    NSMenuItem *viewItem = [[NSMenuItem alloc] init];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItemWithTitle:@"Show Hidden Files" action:@selector(toggleHidden:) keyEquivalent:@"."];
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

    NSAlert *alert = [[NSAlert alloc] init];

    if (paths.count == 1) {
        alert.messageText = [NSString stringWithFormat:@"Info — %@", names[0]];
        alert.informativeText = [self infoTextForPath:paths[0]];
    } else {
        uint64_t totalBytes = 0;
        int files = 0, dirs = 0, other = 0;
        for (NSString *p in paths) {
            struct stat st;
            if (lstat(p.fileSystemRepresentation, &st) != 0) { other++; continue; }
            if (S_ISDIR(st.st_mode))      dirs++;
            else if (S_ISREG(st.st_mode)) files++;
            else                          other++;
            totalBytes += (uint64_t)st.st_size;
        }
        char sizeBuf[32];
        pal_format_size(totalBytes, sizeBuf, sizeof(sizeBuf));
        alert.messageText = [NSString stringWithFormat:@"Info — %lu items selected",
                             (unsigned long)paths.count];
        alert.informativeText = [NSString stringWithFormat:
            @"%d file%@, %d director%@%@\nTotal size: %s",
            files, files == 1 ? @"" : @"s",
            dirs,  dirs  == 1 ? @"y" : @"ies",
            other ? [NSString stringWithFormat:@", %d other", other] : @"",
            sizeBuf];
    }

    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
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

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Move %lu item%@ to Trash?",
                         (unsigned long)paths.count, paths.count == 1 ? @"" : @"s"];
    NSArray<NSString *> *names = [src selectedNames];
    NSMutableArray *preview = [NSMutableArray array];
    for (NSUInteger i = 0; i < MIN(5u, names.count); i++) [preview addObject:names[i]];
    if (names.count > 5) [preview addObject:[NSString stringWithFormat:@"… and %lu more", (unsigned long)(names.count - 5)]];
    alert.informativeText = [preview componentsJoinedByString:@"\n"];
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"Move to Trash"];
    [alert addButtonWithTitle:@"Cancel"];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *failed = [NSMutableArray array];
    for (NSString *p in paths) {
        NSError *err = nil;
        if (![fm trashItemAtURL:[NSURL fileURLWithPath:p] resultingItemURL:nil error:&err]) {
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
