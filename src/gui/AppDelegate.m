/*
 * iDOpus — GUI: Application Delegate
 *
 * Sets up the macOS app: main menu, initial window, buffer cache.
 */

#import <Cocoa/Cocoa.h>
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
- (void)toggleButtonBank:(id)sender;
@end

#pragma mark - Lister Table Data

/* Wraps a dir_buffer_t for NSTableView display */
@interface ListerDataSource : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic) dir_buffer_t *buffer;
@property (nonatomic, assign) NSTableView *tableView;
@property (nonatomic, copy) void (^onColumnClick)(NSString *identifier);
- (void)loadPath:(NSString *)path;
- (void)sortByColumn:(NSString *)identifier;
@end

@implementation ListerDataSource

- (instancetype)init {
    self = [super init];
    if (self) {
        _buffer = dir_buffer_create();
    }
    return self;
}

- (void)dealloc {
    if (_buffer) dir_buffer_free(_buffer);
}

- (void)loadPath:(NSString *)path {
    if (!_buffer || !path) return;
    dir_buffer_read(_buffer, [path fileSystemRepresentation]);
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

@end

#pragma mark - Lister Window Controller

@interface ListerWindowController : NSWindowController <NSWindowDelegate>
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
@end

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

#pragma mark - Button Bank Panel

/* Floating Magellan-style panel with a grid of action buttons, shared across
 * all Listers. Non-activating: clicking a button does NOT steal key focus from
 * the active source Lister, so source/dest semantics remain stable.
 * Buttons route to IDOpusAppDelegate methods that operate on activeSource. */
@interface ButtonBankPanelController : NSWindowController
- (instancetype)initWithAppDelegate:(IDOpusAppDelegate *)appDelegate;
- (void)positionBetweenListers;
@end

@implementation ButtonBankPanelController {
    __weak IDOpusAppDelegate *_appDelegate;
}

- (instancetype)initWithAppDelegate:(IDOpusAppDelegate *)appDelegate {
    NSRect frame = NSMakeRect(0, 0, 420, 76);
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
                               NSWindowStyleMaskClosable |
                               NSWindowStyleMaskUtilityWindow |
                               NSWindowStyleMaskHUDWindow |
                               NSWindowStyleMaskNonactivatingPanel;
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
                                                styleMask:style
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.title = @"Buttons";
    panel.floatingPanel = YES;
    panel.hidesOnDeactivate = NO;
    panel.level = NSFloatingWindowLevel;
    panel.becomesKeyOnlyIfNeeded = YES;

    self = [super initWithWindow:panel];
    if (!self) return nil;
    _appDelegate = appDelegate;

    [self buildGrid];
    return self;
}

- (void)buildGrid {
    NSView *content = self.window.contentView;

    /* Two rows × five buttons each — DOpus Magellan defaults trimmed to what we support */
    struct { NSString *title; SEL action; } row1[] = {
        { @"Copy",    @selector(copyAction:) },
        { @"Move",    @selector(moveAction:) },
        { @"Delete",  @selector(deleteAction:) },
        { @"Rename",  @selector(renameAction:) },
        { @"MakeDir", @selector(makeDirAction:) },
    };
    struct { NSString *title; SEL action; } row2[] = {
        { @"Parent",  @selector(parentAction:) },
        { @"Root",    @selector(rootAction:) },
        { @"Refresh", @selector(refreshAction:) },
        { @"All",     @selector(allAction:) },
        { @"None",    @selector(noneAction:) },
    };

    NSStackView *r1 = [self makeRow:row1 count:5];
    NSStackView *r2 = [self makeRow:row2 count:5];

    NSStackView *column = [[NSStackView alloc] init];
    column.orientation = NSUserInterfaceLayoutOrientationVertical;
    column.spacing = 4;
    column.distribution = NSStackViewDistributionFillEqually;
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [column addArrangedSubview:r1];
    [column addArrangedSubview:r2];
    [content addSubview:column];

    [NSLayoutConstraint activateConstraints:@[
        [column.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [column.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        [column.topAnchor constraintEqualToAnchor:content.topAnchor constant:6],
        [column.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-6],
    ]];
}

- (NSStackView *)makeRow:(void *)specsPtr count:(int)n {
    struct Spec { NSString *title; SEL action; };
    struct Spec *specs = (struct Spec *)specsPtr;

    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 4;
    row.distribution = NSStackViewDistributionFillEqually;
    for (int i = 0; i < n; i++) {
        NSButton *b = [NSButton buttonWithTitle:specs[i].title
                                         target:_appDelegate
                                         action:specs[i].action];
        b.bezelStyle = NSBezelStyleRounded;
        b.controlSize = NSControlSizeSmall;
        b.font = [NSFont systemFontOfSize:11];
        [row addArrangedSubview:b];
    }
    return row;
}

- (void)positionBetweenListers {
    /* Center the panel near the top of the screen, above the Listers. */
    NSRect screen = [[NSScreen mainScreen] visibleFrame];
    NSRect frame = self.window.frame;
    frame.origin.x = screen.origin.x + (screen.size.width - frame.size.width) / 2;
    frame.origin.y = screen.origin.y + screen.size.height - frame.size.height - 12;
    [self.window setFrame:frame display:YES animate:NO];
}

@end

#pragma mark - App Delegate

@implementation IDOpusAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _bufferCache = buffer_cache_create(20);
    _listerControllers = [NSMutableArray array];

    [self createMainMenu];

    /* Default layout: two tiled Listers side-by-side, matching classic DOpus
     * dual-pane presentation. Right Lister becomes SOURCE (opened last),
     * left becomes DEST. */
    NSRect screen = [[NSScreen mainScreen] visibleFrame];
    CGFloat w = MIN(1400, screen.size.width - 100);
    CGFloat h = MIN(800,  screen.size.height - 100);
    CGFloat x = screen.origin.x + (screen.size.width  - w) / 2;
    CGFloat y = screen.origin.y + (screen.size.height - h) / 2;
    CGFloat halfW = floor(w / 2);

    NSRect leftFrame  = NSMakeRect(x,         y, halfW,     h);
    NSRect rightFrame = NSMakeRect(x + halfW, y, w - halfW, h);

    ListerWindowController *left  = [self newListerWindow:NSHomeDirectory() frame:leftFrame];
    ListerWindowController *right = [self newListerWindow:NSHomeDirectory() frame:rightFrame];
    [left.window setFrame:leftFrame display:YES animate:NO];
    [right.window setFrame:rightFrame display:YES animate:NO];

    /* Floating Button Bank panel — classic Magellan feature */
    _buttonBankPanel = [[ButtonBankPanelController alloc] initWithAppDelegate:self];
    [_buttonBankPanel positionBetweenListers];
    [_buttonBankPanel.window orderFront:nil];

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
    funcItem.submenu = funcMenu;
    [mainMenu addItem:funcItem];

    /* View menu */
    NSMenuItem *viewItem = [[NSMenuItem alloc] init];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItemWithTitle:@"Show Hidden Files" action:@selector(toggleHidden:) keyEquivalent:@"."];
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

- (void)toggleButtonBank:(id)sender {
    if (!_buttonBankPanel) return;
    NSWindow *w = _buttonBankPanel.window;
    if (w.isVisible) [w orderOut:nil];
    else             [w orderFront:nil];
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

    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *failed = [NSMutableArray array];
    for (NSUInteger i = 0; i < paths.count; i++) {
        NSString *from = paths[i];
        NSString *to = [dst.currentPath stringByAppendingPathComponent:names[i]];
        NSError *err = nil;
        BOOL ok;
        if (isMove) {
            ok = [fm moveItemAtPath:from toPath:to error:&err];
        } else {
            ok = [fm copyItemAtPath:from toPath:to error:&err];
        }
        if (!ok) {
            [failed addObject:[NSString stringWithFormat:@"%@: %@", names[i], err.localizedDescription]];
        }
    }

    [self refreshAllListersShowing:dst.currentPath];
    if (isMove) [self refreshAllListersShowing:src.currentPath];

    if (failed.count > 0) {
        [self showAlert:isMove ? @"Some items could not be moved" : @"Some items could not be copied"
                   info:[failed componentsJoinedByString:@"\n"]
                  style:NSAlertStyleWarning];
    }
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
