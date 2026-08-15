//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

@import UniformTypeIdentifiers;
@import Quartz; // QLPreviewPanel
#import "CreeveyController.h"
#import "KeyBindings.h"
#import <objc/runtime.h>
#import "DYJpegtran.h"
#import "DYCarbonGoodies.h"

#import "DYWrappingMatrix.h"
#import "CreeveyMainWindowController.h"
#import "DYImageCache.h"
#import "SlideshowWindow.h"
#import "DYJpegtranPanel.h"
#import "DYVersChecker.h"
#import "DYExiftags.h"

// The thumbs cache should always store images using the resolved filename as the key.
// This prevents duplication somewhat, but it means when you look things up
// you need to make a call to ResolveAliasToPath.

#define MAX_THUMBS 2000
#define DYVERSCHECKINTERVAL 604800
#define MAX_FILES_TO_CHECK_FOR_JPEG 100

static BOOL FilesContainJPEG(NSArray *paths) {
	// find out if at least one file is a JPEG
	if (paths.count > MAX_FILES_TO_CHECK_FOR_JPEG) return YES; // but give up there's too many to check
	for (NSString *path in paths) {
		if (FileIsJPEG(path))
			return YES;
	}
	return NO;
}

#define TAB(x,y)	[[NSTextTab alloc] initWithType:x location:y]
NSMutableAttributedString* Fileinfo2EXIFString(NSString *origPath, DYImageCache *cache, BOOL moreExif) {
	NSString *path = ResolveAliasToPath(origPath);
	// header = file name (+ alias) + size + dimensions; these are plain lines
	NSMutableString *header = [origPath.lastPathComponent mutableCopy];
	if (path != origPath)
		[header appendFormat:@"\n[%@->%@]", NSLocalizedString(@"Alias", @""), path];
	DYImageInfo *i = [cache infoForKey:path];
	NSString *exifStr = nil;
	if (i) {
		exifStr = [DYExiftags tagsForFile:path moreTags:moreExif];
		[header appendFormat:@"\n%@ (%qu bytes)\n%@: %d %@: %d",
			FileSize2String(i->fileSize), i->fileSize,
			NSLocalizedString(@"Width", @""), (int)i->pixelSize.width,
			NSLocalizedString(@"Height", @""), (int)i->pixelSize.height];
	} else {
		unsigned long long fsize;
		fsize = [[NSFileManager.defaultManager attributesOfItemAtPath:path.stringByResolvingSymlinksInPath error:NULL] fileSize];
		// fsize will be 0 on error
		[header appendFormat:@"\n%@ (%qu bytes)", FileSize2String(fsize), fsize];
	}

	static NSDictionary *headerAtts, *exifAtts;
	if (headerAtts == nil) {
		NSFont *font = [NSFont userFontOfSize:12];
		// header: plain and left-aligned, so a long file name that wraps stays at
		// the margin instead of indenting under the EXIF value column
		headerAtts = @{
			NSFontAttributeName: font,
			NSParagraphStyleAttributeName: [[NSMutableParagraphStyle alloc] init],
		};
		// EXIF tags: two columns (label tab value); wrapped values align at the value column
		float x = 160;
		NSMutableParagraphStyle *styl = [[NSMutableParagraphStyle alloc] init];
		styl.headIndent = x;
		styl.tabStops = @[TAB(NSRightTabStopType,x-5), TAB(NSLeftTabStopType,x)];
		styl.defaultTabInterval = 5;
		exifAtts = @{ NSFontAttributeName: font, NSParagraphStyleAttributeName: styl };
	}
	NSMutableAttributedString *out = [[NSMutableAttributedString alloc] initWithString:header attributes:headerAtts];
	if (exifStr)
		[out appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\n" stringByAppendingString:exifStr] attributes:exifAtts]];
	return out;
}

@interface TimeIntervalPlusWeekToStringTransformer : NSValueTransformer
// using a val xformer means the field gets updated automatically
@end
@implementation TimeIntervalPlusWeekToStringTransformer
+ (Class)transformedValueClass { return [NSString class]; }
- (id)transformedValue:(id)v {
	return [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:[v floatValue]+DYVERSCHECKINTERVAL]
										  dateStyle:NSDateFormatterLongStyle timeStyle:NSDateFormatterMediumStyle];
}
@end

@interface DYColorToDataTransformer : NSSecureUnarchiveFromDataTransformer
@end
@implementation DYColorToDataTransformer
+ (NSArray<Class> *)allowedTopLevelClasses {
	return [[super allowedTopLevelClasses] arrayByAddingObject:[NSColor class]];
}
@end

// YES only when the interface text size is "Custom" (index 3); used to enable the
// custom point-size field/stepper in Preferences
@interface DYTextSizeIsCustomTransformer : NSValueTransformer
@end
@implementation DYTextSizeIsCustomTransformer
+ (Class)transformedValueClass { return [NSNumber class]; }
- (id)transformedValue:(id)v { return @([v integerValue] == 3); }
@end

static NSString *DYCharacterCountString(NSUInteger n) {
	return [NSString stringWithFormat:(n == 1 ? NSLocalizedString(@"%lu character", @"")
											  : NSLocalizedString(@"%lu characters", @"")), (unsigned long)n];
}

// Return/Enter in the multi-line rename field confirms the dialog (clicks "Rename")
// instead of inserting a newline, and the character count updates as the user types.
@interface DYRenameFieldDelegate : NSObject <NSTextViewDelegate>
@property (weak) NSAlert *alert;
@property (weak) NSTextField *countLabel;
@property (strong) NSUndoManager *undoManager; // dedicated undo stack for the rename field
@end
@implementation DYRenameFieldDelegate
// give the text view its own undo manager so Cmd-Z/Shift-Cmd-Z work inside the modal alert,
// where the alert window doesn't vend one of its own
- (NSUndoManager *)undoManagerForTextView:(NSTextView *)view {
	if (!_undoManager) _undoManager = [[NSUndoManager alloc] init];
	return _undoManager;
}
- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
	if (commandSelector == @selector(insertNewline:)) {
		[self.alert.buttons.firstObject performClick:nil];
		return YES;
	}
	return NO;
}
- (void)textDidChange:(NSNotification *)notification {
	self.countLabel.stringValue = DYCharacterCountString([[notification.object string] length]);
}
@end

#pragma mark Go to Folder sheet
// A Finder-style "Go to the folder:" sheet: a path field with ~ expansion and a
// list of matching sub-folders below. Enter goes to the typed path (or the
// selected match); Tab / double-click completes; Esc cancels. Directories only.
// Field editor that also pastes file URLs (e.g. a folder copied in Finder) as their POSIX
// path, so ⌘V works like Finder's Go to Folder — not only plain-text paths.
@interface PathFieldEditor : NSTextView
@end
@implementation PathFieldEditor
- (void)paste:(id)sender {
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	// a real file URL (e.g. a folder copied in Finder) → its POSIX path
	NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[NSURL.class]
		options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
	NSString *p = urls.firstObject.path;
	if (p.length) { [self insertText:p replacementRange:self.selectedRange]; return; }
	// plain-text path (e.g. `pwd | pbcopy`) → insert as-is, minus stray newlines
	NSString *s = [pb stringForType:NSPasteboardTypeString];
	if (s.length) {
		s = [s stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
		[self insertText:s replacementRange:self.selectedRange];
		return;
	}
	[super paste:sender];
}
@end

@interface GoToFolderController : NSObject <NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
@end
@implementation GoToFolderController {
	NSWindow *_parent, *_sheet;
	NSTextField *_field;
	PathFieldEditor *_fieldEditor;
	NSTableView *_table;
	NSProgressIndicator *_spinner; // shown while a slow folder is scanned in the background
	NSMutableArray<NSString *> *_matches;
	void (^_completion)(NSString *);
	BOOL _userPickedRow; // YES once the user arrows/clicks a row, so Enter honors it
	NSUInteger _scanToken; // bumped per scan so a stale background result can be discarded
	BOOL _scanning;        // YES while the current scan is still running
	NSString *_typedPrefix; // the real user-typed text, without any inline-completion ghost tail
	BOOL _suppressChange;   // YES while we programmatically edit the field (ghost insert/clear)
	BOOL _deleting;         // set by delete keys so we don't re-suggest while erasing
	BOOL _wantGhost;        // whether the next scan result should show an inline completion
	BOOL _ghostShowing;     // YES while an inline completion tail is actually displayed
}
static NSMutableArray *_dyGoToFolderLive; // keep controllers alive while their sheet is up

+ (void)presentForWindow:(NSWindow *)parent startingPath:(NSString *)start completion:(void(^)(NSString *))completion {
	GoToFolderController *c = [[GoToFolderController alloc] init];
	c->_parent = parent;
	c->_completion = [completion copy];
	c->_matches = [NSMutableArray array];
	[c presentStartingAt:start];
}

- (void)presentStartingAt:(NSString *)start {
	if (!_dyGoToFolderLive) _dyGoToFolderLive = [NSMutableArray array];
	[_dyGoToFolderLive addObject:self];

	_sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 300)
										 styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
	_sheet.delegate = self; // for windowWillReturnFieldEditor:toObject:
	NSView *cv = _sheet.contentView;

	NSTextField *label = [NSTextField labelWithString:NSLocalizedString(@"Go to the folder:", @"")];
	label.frame = NSMakeRect(20, 268, 520, 17);
	[cv addSubview:label];

	_field = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 238, 520, 24)];
	_field.delegate = self;
	_field.stringValue = start ?: @"~/";
	_typedPrefix = _field.stringValue; // no inline ghost until the user interacts
	_wantGhost = NO;
	[cv addSubview:_field];

	NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 52, 520, 178)];
	sv.hasVerticalScroller = YES;
	sv.borderType = NSBezelBorder;
	_table = [[NSTableView alloc] initWithFrame:sv.bounds];
	NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"path"];
	col.width = 500;
	[_table addTableColumn:col];
	_table.headerView = nil;
	_table.dataSource = self;
	_table.delegate = self;
	_table.target = self;
	_table.action = @selector(rowClicked:);
	_table.doubleAction = @selector(accept:);
	sv.documentView = _table;
	[cv addSubview:sv];

	_spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(NSMidX(sv.frame)-10, NSMidY(sv.frame)-10, 20, 20)];
	_spinner.style = NSProgressIndicatorStyleSpinning;
	_spinner.displayedWhenStopped = NO; // only visible while animating
	[cv addSubview:_spinner];

	NSButton *cancel = [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", @"") target:self action:@selector(cancel:)];
	cancel.frame = NSMakeRect(366, 12, 90, 32);
	[cv addSubview:cancel];
	NSButton *go = [NSButton buttonWithTitle:NSLocalizedString(@"Go", @"") target:self action:@selector(accept:)];
	go.frame = NSMakeRect(458, 12, 84, 32);
	[cv addSubview:go];

	_sheet.initialFirstResponder = _field;
	[self updateMatches];
	[_parent beginSheet:_sheet completionHandler:^(NSModalResponse r){}];
	// select the whole path so typing immediately replaces it (Finder-style); press → to
	// deselect and keep browsing from the current folder
	_field.currentEditor.selectedRange = NSMakeRange(0, _field.stringValue.length);
}

- (void)finishWithPath:(NSString *)path {
	void (^completion)(NSString *) = _completion;
	[_parent endSheet:_sheet];
	[_dyGoToFolderLive removeObject:self];
	if (completion) completion(path);
}

- (void)cancel:(id)sender { [self finishWithPath:nil]; }

- (void)accept:(id)sender {
	NSString *chosen = nil;
	BOOL haveRow = _table.selectedRow >= 0 && _table.selectedRow < (NSInteger)_matches.count;
	if (_userPickedRow && haveRow) {
		chosen = _matches[_table.selectedRow]; // a folder you arrowed/clicked to wins
	} else {
		NSFileManager *fm = NSFileManager.defaultManager;
		NSString *typed = _field.stringValue.stringByExpandingTildeInPath;
		BOOL isDir;
		if (typed.length && [fm fileExistsAtPath:typed isDirectory:&isDir] && isDir)
			chosen = typed; // otherwise the typed path wins if it's a real directory
		else if (haveRow)
			chosen = _matches[_table.selectedRow];
	}
	if (chosen) [self finishWithPath:chosen];
	else NSBeep();
}

- (void)updateMatches {
	NSString *raw = _field.stringValue;
	NSString *text = raw.stringByExpandingTildeInPath;
	NSString *dir, *prefix;
	// expanding ~ strips a trailing slash, so test the raw text for it: a trailing
	// slash means "list everything in this folder" (empty prefix)
	if (raw.length == 0)           { dir = NSHomeDirectory(); prefix = @""; }
	else if ([raw hasSuffix:@"/"]) { dir = text; prefix = @""; }
	else                           { dir = text.stringByDeletingLastPathComponent; prefix = text.lastPathComponent; }
	_field.toolTip = text; // the field scrolls with the caret; show the full path on hover
	NSString *lp = prefix.lowercaseString;
	BOOL showHidden = [prefix hasPrefix:@"."]; // reveal dot-folders once the user types a dot
	// Scan in the background: a folder with many entries needs a stat() per item, which
	// would otherwise freeze the sheet. A token discards results from superseded scans.
	NSUInteger token = ++_scanToken;
	_scanning = YES;
	// only reveal the spinner if the scan is slow enough to notice, so typing doesn't flash it
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (self->_scanning && token == self->_scanToken) [self->_spinner startAnimation:nil];
	});
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSFileManager *fm = [[NSFileManager alloc] init]; // a private instance is thread-safe
		NSMutableArray<NSString *> *found = [NSMutableArray array];
		for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL]) {
			if (!showHidden && [name hasPrefix:@"."]) continue;
			if (lp.length && ![name.lowercaseString hasPrefix:lp]) continue;
			NSString *full = [dir stringByAppendingPathComponent:name];
			BOOL isDir;
			if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir)
				[found addObject:full];
		}
		[found sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b){
			return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
		}];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (token != self->_scanToken) return; // a newer scan superseded this one
			self->_scanning = NO;
			[self->_spinner stopAnimation:nil];
			[self->_matches setArray:found];
			[self->_table reloadData];
			if (self->_matches.count) {
				[self->_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
				if (self->_wantGhost) [self showInlineCompletionForRow:0]; // Finder-style ghost of the top match
			} else {
				[self clearGhost]; // no matches: strip any leftover ghost
			}
		});
	});
}

- (void)moveSelectionBy:(NSInteger)delta {
	if (!_matches.count) return;
	_userPickedRow = YES;
	NSInteger row = _table.selectedRow + delta;
	if (row < 0) row = 0; else if (row >= (NSInteger)_matches.count) row = _matches.count - 1;
	[_table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	[_table scrollRowToVisible:row];
	[self showInlineCompletionForRow:row]; // ghost follows the highlighted row (Finder-style)
}

// Show the highlighted match's remaining characters as selected "ghost" text after what the user
// typed; → / Tab accept it. Reverts to the typed text if the match no longer shares that prefix.
- (void)showInlineCompletionForRow:(NSInteger)row {
	NSString *typed = _typedPrefix ?: @"";
	NSTextView *ed = (NSTextView *)_field.currentEditor;
	if (!ed) return;
	NSString *sugg = (row >= 0 && row < (NSInteger)_matches.count)
		? ([typed hasPrefix:@"~"] ? _matches[row].stringByAbbreviatingWithTildeInPath : _matches[row])
		: nil;
	if (typed.length && sugg.length > typed.length &&
		[[sugg substringToIndex:typed.length] caseInsensitiveCompare:typed] == NSOrderedSame) {
		_suppressChange = YES;
		ed.string = sugg;
		ed.selectedRange = NSMakeRange(typed.length, sugg.length - typed.length); // select the ghost tail
		_suppressChange = NO;
		_ghostShowing = YES;
	} else {
		[self clearGhost];
	}
}

- (void)clearGhost {
	_ghostShowing = NO;
	NSTextView *ed = (NSTextView *)_field.currentEditor;
	NSString *typed = _typedPrefix ?: @"";
	if (!ed || [ed.string isEqualToString:typed]) return;
	_suppressChange = YES;
	ed.string = typed;
	ed.selectedRange = NSMakeRange(typed.length, 0);
	_suppressChange = NO;
}

- (void)completeSelection {
	if (_table.selectedRow < 0 || _table.selectedRow >= (NSInteger)_matches.count) return;
	_field.stringValue = [_matches[_table.selectedRow].stringByAbbreviatingWithTildeInPath stringByAppendingString:@"/"];
	_field.currentEditor.selectedRange = NSMakeRange(_field.stringValue.length, 0);
	_typedPrefix = _field.stringValue; // the drilled path is now the user's text
	_userPickedRow = NO; // drilled in: back to typed-path mode for the new folder
	_wantGhost = YES;    // preview the first child of the new folder
	[self updateMatches];
}

- (void)rowClicked:(id)sender { _userPickedRow = YES; [self showInlineCompletionForRow:_table.selectedRow]; }

- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client {
	if (client != _field) return nil; // default editor for anything else
	if (!_fieldEditor) { _fieldEditor = [[PathFieldEditor alloc] init]; _fieldEditor.fieldEditor = YES; }
	return _fieldEditor;
}

- (void)controlTextDidChange:(NSNotification *)n {
	if (_suppressChange) return; // our own ghost edit, not a user keystroke
	_userPickedRow = NO;
	_ghostShowing = NO;                 // the edit replaced any ghost; re-shown by the scan below
	_typedPrefix = _field.stringValue; // any previous ghost was just replaced by the edit
	_wantGhost = !_deleting;            // don't re-suggest while the user is erasing
	_deleting = NO;
	[self updateMatches];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)tv doCommandBySelector:(SEL)sel {
	// Finder-style: the path field always keeps focus. ↑/↓ move the highlighted suggestion (and
	// its inline "ghost" completion), Return goes, Esc cancels. Tab completes the highlighted
	// suggestion into the path (drilling one level, staying in edit mode); → does the same when the
	// selection reaches the end of the text — mid-text → just moves the caret.
	if (sel == @selector(deleteBackward:) || sel == @selector(deleteForward:)) { _deleting = YES; return NO; }
	if (sel == @selector(insertNewline:))   { [self accept:nil];        return YES; }
	if (sel == @selector(cancelOperation:)) { [self cancel:nil];        return YES; }
	if (sel == @selector(moveDown:))        { [self moveSelectionBy:1];  return YES; }
	if (sel == @selector(moveUp:))          { [self moveSelectionBy:-1]; return YES; }
	if (sel == @selector(insertTab:))       { [self completeSelection];  return YES; }
	if (sel == @selector(moveRight:)) {
		// only accept when an inline ghost is actually showing; a fully-selected path with no
		// suggestion (e.g. just after opening) should just deselect and move the caret to the end
		if (_ghostShowing) { [self completeSelection]; return YES; }
		return NO;
	}
	// any other command (←, Home, word-nav, …): drop a showing ghost first so no stray
	// completion text is left behind, then let the editor act on the real typed text
	if (tv.selectedRange.length && NSMaxRange(tv.selectedRange) >= tv.string.length && _typedPrefix.length)
		[self clearGhost];
	return NO;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return _matches.count; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row {
	return _matches[row].stringByAbbreviatingWithTildeInPath;
}
@end

CGFloat DYInterfaceTextScale(void) {
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	switch ([u integerForKey:@"interfaceTextSize"]) {
		case 1:  return 1.2;
		case 2:  return 1.4;
		case 3: { // custom: a point size relative to the system font (13pt ≈ Small/1.0×)
			CGFloat pt = MAX(10, MIN(25, [u floatForKey:@"interfaceTextCustomSize"]));
			return pt / NSFont.systemFontSize;
		}
		default: return 1.0;
	}
}

// Run an alert with no window animation, so it pops open instantly instead of
// fading/scaling in.
static NSModalResponse DYRunAlert(NSAlert *alert) {
	alert.window.animationBehavior = NSWindowAnimationBehaviorNone;
	return [alert runModal];
}

@interface CreeveyController () <NSMenuItemValidation>
@property (nonatomic) BOOL appDidFinishLaunching;
@property (nonatomic) BOOL filesWereOpenedAtLaunch;
@property (nonatomic) BOOL windowsWereRestoredAtLaunch;
@end

// Report files an operation couldn't process in a compact, scrollable alert. A plain informativeText
// grows the alert past the screen when many paths fail; this caps the size and scrolls instead.
void DYReportFileErrors(NSString *messageText, NSArray<NSString *> *files) {
	if (files.count == 0) return;
	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = messageText;
	alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"%lu file(s) could not be processed:", @""), (unsigned long)files.count];
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 380, 140)];
	scroll.hasVerticalScroller = YES;
	scroll.borderType = NSBezelBorder;
	NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 380, 140)];
	tv.editable = NO;
	tv.drawsBackground = NO;
	tv.string = [files componentsJoinedByString:@"\n"];
	tv.autoresizingMask = NSViewWidthSizable;
	tv.textContainerInset = NSMakeSize(4, 4);
	scroll.documentView = tv;
	alert.accessoryView = scroll;
	[alert addButtonWithTitle:NSLocalizedString(@"OK", @"")];
	[alert runModal];
}

@implementation CreeveyController
{
	NSMutableSet *cats[NUM_FNKEY_CATS];
	NSUserDefaults *catDefaults;
	BOOL exifWasVisible;

	NSMutableSet *filetypes;
	NSMutableSet *disabledFiletypes;
	NSMutableSet *fileostypes;
	NSArray *fileextensions;
	NSMutableDictionary *filetypeDescriptions;

	NSMutableArray *creeveyWindows;
	CreeveyMainWindowController * __weak frontWindow;
	NSArray *_prefWinNibItems;

	NSMutableArray<NSDictionary *> *_recentFolders; // Open Recent: in-memory, most-recent-first
	BOOL _recentFoldersDirty;                        // unsaved changes since last flush
	NSMenu *_moveRecentMenu, *_copyRecentMenu;       // File ▸ Move/Copy To Recent submenus

	DYImageCache *thumbsCache;
	
	id localeChangeObserver;
	
	NSArray<NSURL*> *_movedUrls;
	NSArray<NSString*> *_originalPaths;

	NSMutableArray *_coalescedFilesToOpen;
}
@synthesize slidesWindow, jpegProgressBar, exifTextView, exifThumbnailDiscloseBtn, prefsWin, slideshowApplyBtn;
@synthesize keyBindings = _keyBindings;

+(void)initialize
{
	if (self != [CreeveyController class]) return;

	dcraw_init();

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
	NSString *s = CREEVEY_DEFAULT_PATH;
	[defaults registerDefaults:@{
		@"picturesFolderPath": s,
		@"lastFolderPath": s,
		@"startupOption": @0,
		@"appearance": @0,
		@"thumbCellWidth": @120.0f,
		@"getInfoVisible": @NO,
		@"autoVersCheck": @YES,
		@"jpegPreserveModDate": @NO,
		@"slideshowAutoadvance": @NO,
		@"slideshowAutoadvanceTime": @5.5f,
		@"slideshowLoop": @NO,
		@"slideshowRandom": @NO,
		@"slideshowScaleUp": @NO,
		@"slideshowActualSize": @NO,
		@"slideshowBgColor": [NSKeyedArchiver archivedDataWithRootObject:NSColor.blackColor requiringSecureCoding:YES error:NULL],
		@"transparentImageBgColor": [NSKeyedArchiver archivedDataWithRootObject:NSColor.clearColor requiringSecureCoding:YES error:NULL],
		@"slideshowWindowFitToImage": @NO,
		@"exifThumbnailShow": @NO,
		@"showFilenames": @YES,
		@"showPathBar": @NO,
		@"sortBy": @1, // sort by filename, ascending
		@"Slideshow:RerandomizeOnLoop": @YES,
		@"SlideshowSuppressLoopIndicator": @NO,
		@"maxThumbsToLoad": @100,
		@"autoRotateByOrientationTag": @YES,
		@"openFilesDoSlideshow": @YES,
		@"openFilesIgnoreAutoadvance": @NO,
		@"openFilesOpensBrowserWindowIfNone": @YES,
		@"startupSlideshowFromFolder":@NO,
		@"startupSlideshowSubfolders":@NO,
		@"startupSlideshowSuppressNewWindows":@NO,
		@"slideshowDefaultMode":@0,
		@"MainWindowSplitViewTopHeight":@151.0f,
		@"interfaceTextSize":@0, // 0 small (current), 1 medium, 2 large, 3 custom
		@"interfaceTextCustomSize":@13, // point size when interfaceTextSize == 3 (custom)
		@"copyPathnameShellQuoted":@YES, // Copy as Pathname: YES = shell-quoted, NO = Finder-style raw
		@"recentFolders":@[],            // Open Recent list (array of state dicts, most-recent-first)
		@"recentFoldersMax":@10,         // how many recent paths to keep (Open Recent + Move/Copy To Recent)
		@"recentMoveToFolders":@[],      // Move To Recent: recent destination folders, most-recent-first
		@"recentCopyToFolders":@[],      // Copy To Recent: recent destination folders, most-recent-first
	}];

	[NSValueTransformer setValueTransformer:[[TimeIntervalPlusWeekToStringTransformer alloc] init]
									forName:@"TimeIntervalPlusWeekToStringTransformer"];
	[NSValueTransformer setValueTransformer:[[DYTextSizeIsCustomTransformer alloc] init]
									forName:@"DYTextSizeIsCustomTransformer"];
}

- (instancetype)init {
	if (self = [super init]) {
		filetypes = [[NSMutableSet alloc] init];
		fileostypes = [[NSMutableSet alloc] init];
		disabledFiletypes = [[NSMutableSet alloc] init];
		for (NSString *identifier in NSImage.imageUnfilteredTypes) {
			// easier to use UTType class from UniformTypeIdentifiers, but that's only available in macOS 11
			// wait actually UTType doesn't include ostypes because apparently "HFS file types are obsolete." :(
			// YOU CAN PRY MY HFS FILE TYPES OUT OF MY COLD DEAD HANDS
			CFDictionaryRef t = UTTypeCopyDeclaration((__bridge CFStringRef)identifier);
			if (t == NULL) continue;
			CFDictionaryRef tags = CFDictionaryGetValue(t, kUTTypeTagSpecificationKey);
			if (tags) {
				NSArray *exts = CFDictionaryGetValue(tags, kUTTagClassFilenameExtension);
				if (exts)
					[filetypes addObjectsFromArray:exts];
				CFArrayRef ostypes = CFDictionaryGetValue(tags, kUTTagClassOSType);
				if (ostypes) for (NSString *s in (__bridge NSArray *)ostypes) {
					// enclose HFS file types in single quotes, e.g. "'PICT'"
					[fileostypes addObject:[NSString stringWithFormat:@"'%@'", s]];
				}
			}
			CFRelease(t);
		}
		_revealedDirectories = [[NSMutableSet alloc] initWithObjects:[NSURL fileURLWithPath:(@"~/Desktop/").stringByResolvingSymlinksInPath isDirectory:YES], nil];
		fileextensions = [filetypes.allObjects sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
		creeveyWindows = [[NSMutableArray alloc] initWithCapacity:5];
		_coalescedFilesToOpen = [[NSMutableArray alloc] init];
		
		thumbsCache = [[DYImageCache alloc] initWithCapacity:MAX_THUMBS];
		thumbsCache.boundingSize = DYWrappingMatrix.maxCellSize;
		thumbsCache.fastThumbnails = YES;
		
		short int i;
		for (i=0; i<NUM_FNKEY_CATS; ++i) {
			cats[i] = [[NSMutableSet alloc] initWithCapacity:0];
		}
		catDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"net.blyt.phoenixslides.categories"];
		
		exifWasVisible = [NSUserDefaults.standardUserDefaults boolForKey:@"getInfoVisible"];
	}
    return self;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
	[CreeveyMainWindowController sweepLeftoverArchiveTemps]; // clear any extracted-archive leftovers from a prior run
	[(NSPanel *)exifTextView.window setBecomesKeyOnlyIfNeeded:YES];
	//[[exifTextView window] setHidesOnDeactivate:NO];
	// this causes problems b/c the window can be foregrounded without the app
	// coming to the front (oops)
	[slidesWindow setCats:cats];
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	slidesWindow.autoRotate = [u boolForKey:@"autoRotateByOrientationTag"];
	[disabledFiletypes addObjectsFromArray:[u stringArrayForKey:@"ignoredFileTypes"]];
	for (NSString *type in disabledFiletypes) {
		[filetypes removeObject:type];
	}
	[self setupRecentDestinationMenus];
	[self updateAlternateSlideshowMenuItem];
	[self updateAppearance];
	
	NSUserDefaultsController *ud = NSUserDefaultsController.sharedUserDefaultsController;
	[ud addObserver:self forKeyPath:@"values.slideshowBgColor" options:0 context:NULL];
	[ud addObserver:self forKeyPath:@"values.transparentImageBgColor" options:0 context:NULL];
	[ud addObserver:self forKeyPath:@"values.slideshowWindowFitToImage" options:0 context:NULL];
	[ud addObserver:self forKeyPath:@"values.DYWrappingMatrixMaxCellWidth" options:0 context:NULL];
	[ud addObserver:self forKeyPath:@"values.appearance" options:0 context:NULL];
	[ud addObserver:self forKeyPath:@"values.interfaceTextSize" options:0 context:NULL];
	[ud addObserver:self forKeyPath:@"values.interfaceTextCustomSize" options:0 context:NULL];
	localeChangeObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSCurrentLocaleDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
		[u setDouble:[u doubleForKey:@"lastVersCheckTime"] forKey:@"lastVersCheckTime"];
	}];
}

- (void)dealloc {
	NSUserDefaultsController *u = NSUserDefaultsController.sharedUserDefaultsController;
	[u removeObserver:self forKeyPath:@"values.slideshowBgColor"];
	[u removeObserver:self forKeyPath:@"values.transparentImageBgColor"];
	[u removeObserver:self forKeyPath:@"values.slideshowWindowFitToImage"];
	[u removeObserver:self forKeyPath:@"values.DYWrappingMatrixMaxCellWidth"];
	[u removeObserver:self forKeyPath:@"values.appearance"];
	[u removeObserver:self forKeyPath:@"values.interfaceTextSize"];
	[u removeObserver:self forKeyPath:@"values.interfaceTextCustomSize"];
	[NSNotificationCenter.defaultCenter removeObserver:localeChangeObserver];
	short int i;
	for (i=0; i<NUM_FNKEY_CATS; ++i)
		cats[i] = nil;
}

- (void)slideshowFromAppOpen:(NSArray *)files {
	BOOL fullscreen = slidesWindow.visible ? slidesWindow.fullscreenMode : [NSUserDefaults.standardUserDefaults integerForKey:@"slideshowDefaultMode"] == 0;
	[self startSlideshowFullscreen:fullscreen withFiles:files];
}

- (void)startSlideshowFullscreen:(BOOL)flag {
	[self startSlideshowFullscreen:flag withFiles:nil];
}

- (void)startSlideshowFullscreen:(BOOL)flag withFiles:(nullable NSArray *)files {
	slidesWindow.fullscreenMode = flag;
	BOOL wantsUpdates;
	NSUInteger startIdx = NSNotFound;
	if (files) {
		if ((wantsUpdates = files.count <= 1)) {
			if (files.count == 1) startIdx = [frontWindow indexOfFilename:files[0]];
			files = frontWindow.displayedFilenames;
		}
	} else {
		NSIndexSet *s = frontWindow.selectedIndexes;
		if ((wantsUpdates = s.count <= 1)) {
			files = frontWindow.displayedFilenames;
			if (s.count == 1) startIdx = s.firstIndex;
		} else {
			files = frontWindow.currentSelection;
		}
	}
	{
		// the slideshow can't display archives (or, when shown, other unsupported files), so drop
		// them from the list; if the file the user started on is one of them, open/enter it and bail
		NSString *startFile = (startIdx != NSNotFound && startIdx < files.count) ? files[startIdx] : nil;
		if (startFile && ![self shouldShowFile:[NSURL fileURLWithPath:startFile]]) {
			if ([frontWindow isArchivePath:startFile])
				[frontWindow openArchive:startFile];
			else
				[NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:startFile]];
			return;
		}
		NSUInteger n = files.count;
		NSMutableArray *supported = [NSMutableArray arrayWithCapacity:n];
		for (NSString *p in files)
			if ([self shouldShowFile:[NSURL fileURLWithPath:p]]) [supported addObject:p];
		if (supported.count != n) { // something (an archive or unsupported file) was dropped
			if (!supported.count) return;
			files = supported;
			startIdx = startFile ? [files indexOfObject:startFile] : startIdx;
		}
	}
	if (wantsUpdates) {
		[slidesWindow setFilenames:files basePath:frontWindow.path wantsSubfolders:frontWindow.wantsSubfolders comparator:frontWindow.comparator sortOrder:frontWindow.sortOrder];
	} else {
		[slidesWindow setFilenames:files basePath:frontWindow.path comparator:frontWindow.comparator sortOrder:frontWindow.sortOrder];
	}
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	slidesWindow.autoRotate = frontWindow.imageMatrix.autoRotate;
	// if files != nil these files are being opened from the finder, so check the relevant pref
	float aaInterval;
	if ([u boolForKey:@"slideshowAutoadvance"] && (files == nil || ![u boolForKey:@"openFilesIgnoreAutoadvance"]))
		aaInterval = [u floatForKey:@"slideshowAutoadvanceTime"];
	else
		aaInterval = 0;
	slidesWindow.autoadvanceTime = aaInterval;
	[slidesWindow startSlideshowAtIndex:startIdx];
}

- (IBAction)slideshow:(id)sender
{
	[self startSlideshowFullscreen:[NSUserDefaults.standardUserDefaults integerForKey:@"slideshowDefaultMode"] == 0];
}

- (IBAction)slideshowAlternateMode:(id)sender {
	[self startSlideshowFullscreen:[NSUserDefaults.standardUserDefaults integerForKey:@"slideshowDefaultMode"] != 0];
}

- (IBAction)openSelectedFiles:(id)sender {
	// files that the app can't display (shown via "Show Unsupported Files") open in their
	// default app instead of the slideshow; a mixed selection still starts a slideshow of
	// the supported files (unsupported ones are filtered out in startSlideshowFullscreen:)
	NSArray *sel = frontWindow.currentSelection;
	if (sel.count == 1 && [frontWindow isArchivePath:sel[0]]) { // open a .zip as a browsable folder
		[frontWindow openArchive:sel[0]];
		return;
	}
	if (sel.count) {
		NSMutableArray *unsupported = [NSMutableArray array];
		for (NSString *p in sel)
			if (![self shouldShowFile:[NSURL fileURLWithPath:p]]) [unsupported addObject:p];
		if (unsupported.count == sel.count) {
			for (NSString *p in unsupported)
				[NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:p]];
			return;
		}
	}
	// double-click (or Enter) opens a windowed slideshow; hold Option for full screen
	BOOL fullscreen = (NSApp.currentEvent.modifierFlags & NSEventModifierFlagOption) != 0;
	[self startSlideshowFullscreen:fullscreen];
}

- (IBAction)quickLook:(id)sender {
	QLPreviewPanel *panel = QLPreviewPanel.sharedPreviewPanel;
	panel.animationBehavior = NSWindowAnimationBehaviorNone; // open/close instantly, no zoom/fade
	if (QLPreviewPanel.sharedPreviewPanelExists && panel.isVisible)
		[panel orderOut:nil];
	else
		[panel makeKeyAndOrderFront:nil];
}

static void ShowDirectoryContentsIfPossible(NSURL *u) {
	// apparently it's not possible to tell the Finder to show the top level contents of a package like .app or .rtfd?
	NSWorkspace *ws = NSWorkspace.sharedWorkspace;
	if ([ws isFilePackageAtPath:u.path])
		[ws activateFileViewerSelectingURLs:@[u]];
	else
		[ws openURL:u];
}

- (IBAction)revealSelectedFilesInFinder:(id)sender {
	if (slidesWindow.isMainWindow) {
		if (slidesWindow.currentFile) {
			NSString *s = slidesWindow.currentFile;
			[NSWorkspace.sharedWorkspace selectFile:s inFileViewerRootedAtPath:s.stringByDeletingLastPathComponent];
		} else {
			ShowDirectoryContentsIfPossible(slidesWindow.baseURL);
		}
	} else {
		NSArray *a = frontWindow.currentSelection;
		if (a.count) {
			[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:a.asFileURLs];
		} else {
			ShowDirectoryContentsIfPossible(frontWindow.URL);
		}
	}
}


- (IBAction)copySelectedFilePaths:(id)sender {
	NSArray<NSString *> *paths = frontWindow.currentSelection;
	if (!paths.count) { NSBeep(); return; }
	NSString *text;
	if ([NSUserDefaults.standardUserDefaults boolForKey:@"copyPathnameShellQuoted"]) {
		// shell-quoted: single-quote each path (escaping embedded quotes), space-separated
		NSMutableArray *quoted = [NSMutableArray arrayWithCapacity:paths.count];
		for (NSString *p in paths)
			[quoted addObject:[NSString stringWithFormat:@"'%@'", [p stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]]];
		text = [quoted componentsJoinedByString:@" "];
	} else {
		// Finder-style: the raw POSIX path(s), one per line
		text = [paths componentsJoinedByString:@"\n"];
	}
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	[pb clearContents];
	[pb setString:text forType:NSPasteboardTypeString];
}

#pragma mark Open Recent
- (NSMutableArray<NSDictionary *> *)recentFolders {
	if (!_recentFolders) {
		NSArray *saved = [NSUserDefaults.standardUserDefaults arrayForKey:@"recentFolders"];
		_recentFolders = saved ? [saved mutableCopy] : [NSMutableArray array];
	}
	return _recentFolders;
}

// Upsert the window's current folder to the top of the list with its full state.
- (void)noteRecentFolderForWindow:(CreeveyMainWindowController *)wc {
	NSDictionary *state = wc.currentStateDictionary;
	if (!state) return;
	NSString *path = state[@"path"];
	NSMutableArray *list = self.recentFolders;
	NSUInteger existing = [list indexOfObjectPassingTest:^BOOL(NSDictionary *e, NSUInteger idx, BOOL *stop){
		return [e[@"path"] isEqual:path];
	}];
	if (existing != NSNotFound) [list removeObjectAtIndex:existing];
	[list insertObject:state atIndex:0];
	NSInteger max = MAX(1, [NSUserDefaults.standardUserDefaults integerForKey:@"recentFoldersMax"]);
	while ((NSInteger)list.count > max) [list removeLastObject];
	_recentFoldersDirty = YES;
}

- (void)flushRecentFolders {
	if (!_recentFoldersDirty) return;
	[NSUserDefaults.standardUserDefaults setObject:_recentFolders forKey:@"recentFolders"];
	_recentFoldersDirty = NO;
}

// NSMenuDelegate for the File > Open Recent submenu (delegate wired in MainMenu.xib).
- (void)menuNeedsUpdate:(NSMenu *)menu {
	if (frontWindow) [self noteRecentFolderForWindow:frontWindow]; // reflect the current folder's latest state
	[self flushRecentFolders];
	menu.autoenablesItems = NO; // we set each item's enabled state explicitly
	[menu removeAllItems];
	NSMutableArray *list = self.recentFolders;
	NSFileManager *fm = NSFileManager.defaultManager;
	BOOL hasInvalid = NO;
	if (list.count == 0) {
		NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"No Recent Folders", @"") action:NULL keyEquivalent:@""];
		none.enabled = NO;
		[menu addItem:none];
	} else {
		for (NSDictionary *e in list) {
			NSString *path = e[@"path"];
			BOOL exists = [fm fileExistsAtPath:path];
			if (!exists) hasInvalid = YES;
			NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:(e[@"displayPath"] ?: path)
														action:@selector(openRecentFolder:) keyEquivalent:@""];
			mi.target = self;
			mi.representedObject = e;
			mi.enabled = exists; // missing folders greyed out
			NSImage *icon = [NSWorkspace.sharedWorkspace iconForFile:path];
			icon.size = NSMakeSize(16, 16);
			mi.image = icon;
			[menu addItem:mi];
		}
	}
	[menu addItem:NSMenuItem.separatorItem];
	NSMenuItem *removeInvalid = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Remove Invalid", @"")
														   action:@selector(removeInvalidRecent:) keyEquivalent:@""];
	removeInvalid.target = self;
	removeInvalid.enabled = hasInvalid;
	[menu addItem:removeInvalid];
	NSMenuItem *clear = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Clear Menu", @"")
												   action:@selector(clearRecentMenu:) keyEquivalent:@""];
	clear.target = self;
	clear.enabled = list.count > 0;
	[menu addItem:clear];
}

- (IBAction)openRecentFolder:(NSMenuItem *)sender {
	NSDictionary *e = sender.representedObject;
	if (![e isKindOfClass:NSDictionary.class]) return;
	if (![NSFileManager.defaultManager fileExistsAtPath:e[@"path"]]) { NSBeep(); return; }
	CreeveyMainWindowController *wc = frontWindow;
	if (!wc || !creeveyWindows.count) {
		[self newWindow:nil]; // open a browser window if none exists (init:NO — restoreState sets the path)
		wc = creeveyWindows.lastObject;
	}
	[wc showWindow:nil];
	[wc.window makeKeyAndOrderFront:nil];
	[wc restoreState:e];
}

- (IBAction)clearRecentMenu:(id)sender {
	[self.recentFolders removeAllObjects];
	_recentFoldersDirty = YES;
	[self flushRecentFolders];
}

- (IBAction)removeInvalidRecent:(id)sender {
	NSFileManager *fm = NSFileManager.defaultManager;
	NSMutableArray *list = self.recentFolders;
	NSIndexSet *invalid = [list indexesOfObjectsPassingTest:^BOOL(NSDictionary *e, NSUInteger idx, BOOL *stop){
		return ![fm fileExistsAtPath:e[@"path"]];
	}];
	if (invalid.count) {
		[list removeObjectsAtIndexes:invalid];
		_recentFoldersDirty = YES;
		[self flushRecentFolders];
	}
}

- (IBAction)setDesktopPicture:(id)sender {
	NSString *s = slidesWindow.isMainWindow
		? slidesWindow.currentFile
		: frontWindow.currentSelection[0];
	NSError * __autoreleasing error = nil;
	[NSWorkspace.sharedWorkspace setDesktopImageURL:[NSURL fileURLWithPath:s isDirectory:NO]
											forScreen:NSScreen.mainScreen
											  options:@{}
												error:&error];
	if (error)  {
		NSAlert *alert = [[NSAlert alloc] init];
		alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"Could not set the desktop because an error occurred. %@", @""), error.localizedDescription];
		[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
		DYRunAlert(alert);
	};
}

- (IBAction)transformJpeg:(id)sender {
	DYJpegtranInfo jinfo;
	NSInteger t = [sender tag] - 100;
	if (t == 0) {
		if (!self.jpegController)
			if (![NSBundle.mainBundle loadNibNamed:@"DYJpegtranPanel" owner:self topLevelObjects:NULL]) return;
		if (![self.jpegController runOptionsPanel:&jinfo]) return;
	} else {
		jinfo.thumbOnly = t > 30;
		if (jinfo.thumbOnly) t -= 30;
		jinfo.tinfo.transform = t < DYJPEGTRAN_XFORM_PROGRESSIVE ? (JXFORM_CODE)t : JXFORM_NONE;
		jinfo.tinfo.trim = FALSE;
		jinfo.tinfo.force_grayscale = t == DYJPEGTRAN_XFORM_GRAYSCALE;
		jinfo.cp = JCOPYOPT_ALL;
		jinfo.progressive = t == DYJPEGTRAN_XFORM_PROGRESSIVE;
		jinfo.optimize = 0;
		jinfo.autorotate = t == DYJPEGTRAN_XFORM_AUTOROTATE;
		jinfo.resetOrientation = t == DYJPEGTRAN_XFORM_RESETORIENT;
		jinfo.replaceThumb = t == DYJPEGTRAN_XFORM_REGENTHUMB;
		jinfo.delThumb = t == DYJPEGTRAN_XFORM_DELETETHUMB;
	}
	// throw up warning if necessary
	if (jinfo.tinfo.force_grayscale || jinfo.cp != JCOPYOPT_ALL || jinfo.tinfo.trim
		|| jinfo.resetOrientation || jinfo.replaceThumb || jinfo.delThumb) {
		NSAlert *alert = [[NSAlert alloc] init];
		alert.messageText = NSLocalizedString(@"Warning", @"");
		alert.informativeText = NSLocalizedString(@"This operation cannot be undone! Are you sure you want to continue?", @"");
		[alert addButtonWithTitle:NSLocalizedString(@"Continue", @"")];
		[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
		NSModalResponse response = DYRunAlert(alert);
		if (response != NSAlertFirstButtonReturn)
			return; // user cancelled
		jinfo.preserveModificationDate = jinfo.resetOrientation ? [NSUserDefaults.standardUserDefaults boolForKey:@"jpegPreserveModDate"]
																: NO;
										 // make an exception for reset orientation,
										 // since it doesn't _really_ change anything
	} else {
		jinfo.preserveModificationDate = [NSUserDefaults.standardUserDefaults boolForKey:@"jpegPreserveModDate"];
	}
	
	NSArray *a;
	DYImageInfo *imgInfo;
	BOOL slidesWasKey = slidesWindow.isMainWindow; // ** test for main is better than key
	BOOL autoRotate = YES; // set this to yes, if the browser is active and not autorotating we change it below. I.e., autorotate will be true if we're in a slideshow
	if (slidesWasKey) {
		NSString *slidesFile = slidesWindow.currentFile;
		a = @[slidesFile];
		// we need to get the current (viewing) orientation of the slide
		// we *don't* need to save the current cached thumbnail info since it's going to get deleted
		unsigned short orientation = slidesWindow.currentOrientation;
		if (orientation != 0) {
			imgInfo = [thumbsCache infoForKey:ResolveAliasToPath(slidesFile)];
			if (imgInfo)
				imgInfo->exifOrientation = slidesWindow.currentOrientation;
		}
	} else {
		a = frontWindow.currentSelection;
		autoRotate = frontWindow.imageMatrix.autoRotate;
	}
	
	jpegProgressBar.usesThreadedAnimation = YES;
	jpegProgressBar.indeterminate = YES;
	jpegProgressBar.doubleValue = 0;
	jpegProgressBar.maxValue = a.count;
	((NSButton *)[jpegProgressBar.window.contentView viewWithTag:1]).enabled = a.count > 1; // cancel btn
	NSModalSession session = [NSApp beginModalSessionForWindow:jpegProgressBar.window];
	[NSApp runModalSession:session];
	[jpegProgressBar startAnimation:self];

	for (NSString *s in a) {
		NSString *resolvedPath = ResolveAliasToPath(s);
		if (FileIsJPEG(resolvedPath)) {
			if (jinfo.replaceThumb) {
				NSSize tmpSize;
				NSData *i = [DYImageCache createNewThumbFromFile:resolvedPath getSize:&tmpSize];
				if (i) {
					jinfo.newThumb = i;
					jinfo.newThumbSize = tmpSize;
				} else {
					jinfo.newThumb = NULL;
				}
			}
			imgInfo = [thumbsCache infoForKey:resolvedPath];
			jinfo.starting_exif_orientation = autoRotate
				? (imgInfo ? imgInfo->exifOrientation : 0) // thumbsCache should always have the info we want, but just in case it doesn't don't crash!
				: 0;
			if ([DYJpegtran transformImage:resolvedPath transform:jinfo]) {
				[thumbsCache removeImageForKey:resolvedPath];
				[creeveyWindows makeObjectsPerformSelector:@selector(fileWasChanged:) withObject:s];
				[slidesWindow uncacheImage:s];
			} else {
				// ** fail silently
				//NSLog(@"rot failed!");
			}
		}
		if (jpegProgressBar.indeterminate) {
			[jpegProgressBar stopAnimation:self];
			jpegProgressBar.indeterminate = NO;
		}
		[jpegProgressBar incrementBy:1];
		if ([NSApp runModalSession:session] != NSModalResponseContinue) break;
	}
	[frontWindow updateExifInfo];

	[NSApp endModalSession:session];
	[jpegProgressBar.window orderOut:self];
	// the slideshow refreshes via uncacheImage above; do the same for Quick Look, whose
	// out-of-process render otherwise keeps showing the pre-transform image
	if (QLPreviewPanel.sharedPreviewPanelExists && QLPreviewPanel.sharedPreviewPanel.isVisible)
		[QLPreviewPanel.sharedPreviewPanel refreshCurrentPreviewItem];
}

- (IBAction)stopModal:(id)sender {
	[NSApp stopModal];
}

#pragma mark Move/Copy To Recent (submenus of recent destination folders)

// Number of recent items to keep — shared with Open Recent (Preferences ▸ "Recent paths to keep").
- (NSInteger)recentItemsMax {
	return MAX(1, [NSUserDefaults.standardUserDefaults integerForKey:@"recentFoldersMax"]);
}

- (NSArray<NSString *> *)recentDestinationsForKey:(NSString *)key {
	return [NSUserDefaults.standardUserDefaults arrayForKey:key] ?: @[];
}

// Push a destination to the top of a recent list (dedup, cap at recentItemsMax), mirror it to the
// single "last used" default (used for validation), and rebuild the submenus.
- (void)recordRecentDestination:(NSString *)path listKey:(NSString *)listKey lastKey:(NSString *)lastKey {
	if (path.length == 0) return;
	NSMutableArray<NSString *> *list = [[self recentDestinationsForKey:listKey] mutableCopy];
	[list removeObject:path];
	[list insertObject:path atIndex:0];
	while ((NSInteger)list.count > self.recentItemsMax) [list removeLastObject];
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	[u setObject:list forKey:listKey];
	[u setObject:path forKey:lastKey];
	[self rebuildRecentDestinationMenus];
}
- (void)recordRecentMoveDestination:(NSString *)path { [self recordRecentDestination:path listKey:@"recentMoveToFolders" lastKey:@"lastUsedMoveToFolder"]; }
- (void)recordRecentCopyDestination:(NSString *)path { [self recordRecentDestination:path listKey:@"recentCopyToFolders" lastKey:@"lastUsedCopyToFolder"]; }

// Attach fresh submenus to the "Move To Recent" / "Copy To Recent" items (called once at launch).
- (void)setupRecentDestinationMenus {
	NSMenu *file = [NSApp.mainMenu itemWithTag:FILE_MENU].submenu;
	NSMenuItem *mv = [file itemWithTag:MOVE_TO_AGAIN], *cp = [file itemWithTag:COPY_TO_AGAIN];
	_moveRecentMenu = [[NSMenu alloc] initWithTitle:mv.title]; _moveRecentMenu.autoenablesItems = NO;
	_copyRecentMenu = [[NSMenu alloc] initWithTitle:cp.title]; _copyRecentMenu.autoenablesItems = NO;
	mv.submenu = _moveRecentMenu;
	cp.submenu = _copyRecentMenu;
	[self rebuildRecentDestinationMenus];
}

- (void)rebuildRecentDestinationMenus {
	[self fillRecentMenu:_moveRecentMenu listKey:@"recentMoveToFolders" action:@selector(moveToRecentFolder:) shortcut:@"m"];
	[self fillRecentMenu:_copyRecentMenu listKey:@"recentCopyToFolders" action:@selector(copyToRecentFolder:) shortcut:@"c"];
}

// Fill one recent-destination submenu. The most-recent item carries the original ⌃⌘M / ⌃⌘C shortcut
// so it still repeats the last destination. Built eagerly (not on open) so the shortcut stays live.
- (void)fillRecentMenu:(NSMenu *)menu listKey:(NSString *)listKey action:(SEL)action shortcut:(NSString *)shortcut {
	if (!menu) return;
	[menu removeAllItems];
	NSArray<NSString *> *list = [self recentDestinationsForKey:listKey];
	if (list.count == 0) {
		NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"None", @"") action:NULL keyEquivalent:@""];
		none.enabled = NO;
		[menu addItem:none];
		return;
	}
	NSFileManager *fm = NSFileManager.defaultManager;
	NSUInteger i = 0;
	for (NSString *path in list) {
		if ((NSInteger)i >= self.recentItemsMax) break; // already capped, but stay safe if max shrank
		NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:path.stringByAbbreviatingWithTildeInPath
													action:action keyEquivalent:(i == 0 ? shortcut : @"")];
		if (i == 0) mi.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagCommand;
		mi.target = self;
		mi.representedObject = path;
		mi.enabled = [fm fileExistsAtPath:path]; // grey out folders that no longer exist
		NSImage *icon = [NSWorkspace.sharedWorkspace iconForFile:path];
		icon.size = NSMakeSize(16, 16);
		mi.image = icon;
		[menu addItem:mi];
		i++;
	}
}

- (IBAction)moveToRecentFolder:(NSMenuItem *)sender {
	NSString *path = sender.representedObject;
	if (![path isKindOfClass:NSString.class]) return;
	[self moveSelectedFilesTo:[NSURL fileURLWithPath:path isDirectory:YES]];
	[self recordRecentMoveDestination:path]; // bump to the top
}

- (IBAction)copyToRecentFolder:(NSMenuItem *)sender {
	NSString *path = sender.representedObject;
	if (![path isKindOfClass:NSString.class]) return;
	[self copySelectedFilesTo:[NSURL fileURLWithPath:path isDirectory:YES]];
	[self recordRecentCopyDestination:path];
}

- (void)updateAlternateSlideshowMenuItem {
	NSMenu *m = [NSApp.mainMenu itemWithTag:SLIDESHOW_MENU].submenu;
	NSMenuItem *item = [m itemWithTag:BEGIN_SLIDESHOW_ALTERNATE];
	item.title = [NSUserDefaults.standardUserDefaults integerForKey:@"slideshowDefaultMode"] == 0 ? NSLocalizedString(@"Begin Slideshow In Window", @"Slideshow menu") : NSLocalizedString(@"Begin Slideshow (Full Screen)", @"Slideshow menu");
}

// Batch file-operation progress, reusing the shared "Progress Panel" (bar + label + Cancel) that
// JPEG transforms use. Only worth showing for multi-file operations; a single file is instant.
// Returns a modal session to pump, or NULL when no panel is shown (count <= 1).
- (NSModalSession)beginFileProgress:(NSUInteger)count title:(NSString *)title {
	if (count <= 1) return NULL;
	jpegProgressBar.window.title = title;
	jpegProgressBar.usesThreadedAnimation = NO; // step immediately per file, not eased/animated (no bounce)
	jpegProgressBar.indeterminate = NO;
	jpegProgressBar.minValue = 0;
	jpegProgressBar.doubleValue = 0;
	jpegProgressBar.maxValue = count;
	NSTextField *label = [jpegProgressBar.window.contentView viewWithTag:2];
	label.stringValue = title;
	((NSButton *)[jpegProgressBar.window.contentView viewWithTag:1]).enabled = YES; // Cancel
	NSModalSession s = [NSApp beginModalSessionForWindow:jpegProgressBar.window];
	[NSApp runModalSession:s];
	return s;
}
// Advance the bar one step and show the current file name; returns NO if the user pressed Cancel.
- (BOOL)stepFileProgress:(NSModalSession)s name:(NSString *)name {
	if (!s) return YES;
	NSTextField *label = [jpegProgressBar.window.contentView viewWithTag:2];
	label.stringValue = name;
	[jpegProgressBar incrementBy:1];
	[jpegProgressBar display]; // redraw the exact proportion now, so the fill steps smoothly L→R
	return [NSApp runModalSession:s] == NSModalResponseContinue;
}
- (void)endFileProgress:(NSModalSession)s {
	if (!s) return;
	[NSApp endModalSession:s];
	[jpegProgressBar.window orderOut:self];
}

- (void)moveSelectedFilesTo:(NSURL *)dest {
	NSURL *curr = slidesWindow.isMainWindow ? slidesWindow.baseURL : frontWindow.URL;
	if ([dest isEqual:curr]) return;

	NSArray *files = slidesWindow.isMainWindow ? @[slidesWindow.currentFile] : frontWindow.currentSelection;
	NSMutableArray<NSString*> *paths = [NSMutableArray array];
	NSMutableArray<NSURL*> *moved = [NSMutableArray arrayWithCapacity:files.count];
	NSMutableArray<NSString*> *notMoved = [NSMutableArray array];

	NSFileManager *fm = NSFileManager.defaultManager;
	NSModalSession prog = [self beginFileProgress:files.count title:NSLocalizedString(@"Moving Files…", @"")];
	for (NSString *f in files) {
		NSURL *destUrl = [dest URLByAppendingPathComponent:f.lastPathComponent];
		// Skip files already at the destination (same folder, or a copy of the same name already
		// there) — that's not an error, so don't report it.
		if ([destUrl.path isEqualToString:f] || [fm fileExistsAtPath:destUrl.path]) {
			if (![self stepFileProgress:prog name:f.lastPathComponent]) break;
			continue;
		}
		if ([fm moveItemAtPath:f toPath:destUrl.path error:NULL]) {
			[paths addObject:f];
			[moved addObject:destUrl];
		} else {
			[notMoved addObject:f];
		}
		if (![self stepFileProgress:prog name:f.lastPathComponent]) break; // Cancel: keep what moved
	}
	[self endFileProgress:prog];
	DYReportFileErrors(NSLocalizedString(@"Some files couldn’t be moved.", @""), notMoved);
	_originalPaths = [paths copy];
	_movedUrls = [moved copy];
	[self removePicsAndTrash:NO];
	[creeveyWindows makeObjectsPerformSelector:@selector(filesWereUndeleted:) withObject:[moved valueForKey:@"path"]];
}

- (void)copySelectedFilesTo:(NSURL *)dest {
	NSURL *curr = slidesWindow.isMainWindow ? slidesWindow.baseURL : frontWindow.URL;
	if ([dest isEqual:curr]) return;

	NSArray *files = slidesWindow.isMainWindow ? @[slidesWindow.currentFile] : frontWindow.currentSelection;
	NSMutableArray<NSString*> *notCopied = [NSMutableArray array];

	NSFileManager *fm = NSFileManager.defaultManager;
	NSModalSession prog = [self beginFileProgress:files.count title:NSLocalizedString(@"Copying Files…", @"")];
	for (NSString *f in files) {
		NSURL *destUrl = [dest URLByAppendingPathComponent:f.lastPathComponent];
		// Skip files already at the destination (copying a file onto itself, or a same-named file
		// already there) rather than failing with an "already exists" error.
		if ([destUrl.path isEqualToString:f] || [fm fileExistsAtPath:destUrl.path]) {
			if (![self stepFileProgress:prog name:f.lastPathComponent]) break;
			continue;
		}
		if (![fm copyItemAtPath:f toPath:destUrl.path error:NULL])
			[notCopied addObject:f];
		if (![self stepFileProgress:prog name:f.lastPathComponent]) break; // Cancel: keep what copied
	}
	[self endFileProgress:prog];
	DYReportFileErrors(NSLocalizedString(@"Some files couldn’t be copied.", @""), notCopied);
}

- (IBAction)moveSelectedFiles:(id)sender {
	NSOpenPanel *op = [NSOpenPanel openPanel];
	op.canChooseFiles = NO;
	op.canChooseDirectories = YES;
	op.animationBehavior = NSWindowAnimationBehaviorNone;
	if ([op runModal] != NSModalResponseOK) return;
	NSURL *dest = op.URL;
	[self moveSelectedFilesTo:dest];
	[self recordRecentMoveDestination:dest.path];
}

- (IBAction)copySelectedFiles:(id)sender {
	NSOpenPanel *op = [NSOpenPanel openPanel];
	op.canChooseFiles = NO;
	op.canChooseDirectories = YES;
	op.animationBehavior = NSWindowAnimationBehaviorNone;
	if ([op runModal] != NSModalResponseOK) return;
	NSURL *dest = op.URL;
	[self copySelectedFilesTo:dest];
	[self recordRecentCopyDestination:dest.path];
}


// returns 1 if successful
// unsuccessful: 0 user wants to continue; 2 cancel/abort
- (char)trashFile:(NSString *)fullpath numLeft:(NSUInteger)numFiles resultingURL:(NSURL **)newURL {
	NSURL *url = [NSURL fileURLWithPath:fullpath isDirectory:NO];
	NSError * __autoreleasing error = nil;
	[NSFileManager.defaultManager trashItemAtURL:url resultingItemURL:newURL error:&error];
	if (!error)
		return 1;
	NSAlert *alert = [[NSAlert alloc] init];
	alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The file %@ could not be moved to the trash because an error occurred: %@\n\nDo you want to delete the file immediately? This operation cannot be undone!", @""), fullpath.lastPathComponent, error.localizedDescription];
	alert.icon = [thumbsCache imageForKey:ResolveAliasToPath(fullpath)];
	[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
	NSButton *deleteButton = [alert addButtonWithTitle:NSLocalizedString(@"Delete", @"Delete Immediately Button")];
	deleteButton.hasDestructiveAction = YES;
	if (numFiles > 1)
		[alert addButtonWithTitle:NSLocalizedString(@"Skip", @"after move to trash failed")];
	NSModalResponse response = DYRunAlert(alert);
	if (response == NSAlertFirstButtonReturn)
		return 2;
	if (response == NSAlertSecondButtonReturn) {
		if ([NSFileManager.defaultManager removeItemAtURL:url error:&error]) {
			*newURL = nil;
			return 1;
		}
		alert = [[NSAlert alloc] init];
		alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The file %@ could not be deleted because an error occurred: %@", @""), fullpath.lastPathComponent, error.localizedDescription];
		DYRunAlert(alert);
	}
	return 0;
}

// pass YES to move to trash; pass NO if this was a drag-to-Finder operation
- (void)removePicsAndTrash:(BOOL)doTrash {
	// *** to be more efficient, we should change the path in the cache instead of deleting it
	if (slidesWindow.isMainWindow) {
		NSString *s = slidesWindow.currentFile;
		NSURL *u;
		if (doTrash ? [self trashFile:s numLeft:1 resultingURL:&u] : (u = _movedUrls[0]) != nil) {
			[creeveyWindows makeObjectsPerformSelector:@selector(fileWasDeleted:) withObject:s];
			if (!IsAliasFilePath(s))
				[thumbsCache removeImageForKey:s];
			[slidesWindow removeImageForFile:s];
			// u will be nil if the user deleted the file successfully after a failed move-to-trash attempt
			if (u) {
				NSUInteger idx = slidesWindow.currentIndex;
				NSUndoManager *um = slidesWindow.undoManager;
				[um registerUndoWithTarget:self handler:^(id target) {
					NSError * __autoreleasing err;
					if ([NSFileManager.defaultManager moveItemAtPath:u.path toPath:s error:&err]) {
						if (slidesWindow.isMainWindow)
							[slidesWindow insertFile:s atIndex:idx];
						[creeveyWindows makeObjectsPerformSelector:@selector(filesWereUndeleted:) withObject:@[s]];
						if (!doTrash) {
							[creeveyWindows makeObjectsPerformSelector:@selector(fileWasDeleted:) withObject:u.path];
							if (slidesWindow.isMainWindow)
								[slidesWindow removeImageForFile:u.path];
						}
					} else {
						NSAlert *alert = [[NSAlert alloc] init];
						alert.informativeText = [NSString stringWithFormat:doTrash ? NSLocalizedString(@"The file \"%@\" could not be restored from the trash because of an error: %@", @"") : NSLocalizedString(@"The file “%@” could not be moved because of an error: %@", @""), s.lastPathComponent, err.localizedDescription];
						DYRunAlert(alert);
					}
				}];
				[um setActionName:[NSString stringWithFormat:doTrash ? NSLocalizedString(@"Move to Trash",@"") : NSLocalizedString(@"Move File",@"for undo")]];
			}
		}
	} else {
		NSUInteger oldIndex = frontWindow.selectedIndexes.firstIndex;
		NSArray *selectedPaths = frontWindow.currentSelection;
		NSUInteger n = selectedPaths.count;
		NSMutableArray<NSArray *> *trashedFiles = [NSMutableArray arrayWithCapacity:n];
		for (NSUInteger i=0; i < n; ++i) {
			NSString *fullpath = selectedPaths[i];
			NSURL * __autoreleasing newURL;
			char result = (doTrash ? [self trashFile:fullpath numLeft:n-i resultingURL:&newURL] : 1);
			if (result == 1) {
				if (!IsAliasFilePath(fullpath))
					[thumbsCache removeImageForKey:fullpath];
				[creeveyWindows makeObjectsPerformSelector:@selector(fileWasDeleted:) withObject:fullpath];
				if (slidesWindow.visible)
					[slidesWindow removeImageForFile:fullpath];
				if (doTrash && newURL)
					[trashedFiles addObject:@[fullpath, newURL]]; // this is a pair representing the old and new file locations
			} else if (result == 2)
				break;
		}
		NSUndoManager *um = frontWindow.window.undoManager;
		n = trashedFiles.count;
		if (n) {
			[um registerUndoWithTarget:self handler:^(id target) {
				NSMutableArray *moved = [NSMutableArray arrayWithCapacity:n];
				for (NSArray *a in trashedFiles) {
					if ([NSFileManager.defaultManager moveItemAtPath:[a[1] path] toPath:a[0] error:NULL])
						[moved addObject:a[0]];
				}
				[creeveyWindows makeObjectsPerformSelector:@selector(filesWereUndeleted:) withObject:moved];
				if (slidesWindow.visible)
					[slidesWindow filesWereUndeleted:moved];
				if (moved.count < n) {
					NSAlert *alert = [[NSAlert alloc] init];
					alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"%lu file(s) could not be restored from the trash because of an error. You should probably check your Trash.",@""), n-moved.count];
					DYRunAlert(alert);
				}
			}];
			[um setActionName:[NSString stringWithFormat:NSLocalizedString(@"Move to Trash (%lu File(s))",@"for undo"), n]];
		} else if (!doTrash) {
			NSArray<NSURL *> *urls = _movedUrls; // nonmutable copy, suitable to be captured by block below
			// these are file reference URLs so we will be able to resolve the new paths
			n = urls.count;
			if (n) {
				NSArray *paths = _originalPaths;
				[um registerUndoWithTarget:self handler:^(id target) {
					NSMutableArray *moved = [NSMutableArray arrayWithCapacity:n];
					for (NSUInteger i=0; i<n; ++i) {
						NSString *fromPath = urls[i].path;
						if ([NSFileManager.defaultManager moveItemAtPath:fromPath toPath:paths[i] error:NULL]) {
							[moved addObject:paths[i]];
							[creeveyWindows makeObjectsPerformSelector:@selector(fileWasDeleted:) withObject:fromPath];
							if (slidesWindow.visible)
								[slidesWindow removeImageForFile:fromPath];
						}
					}
					[creeveyWindows makeObjectsPerformSelector:@selector(filesWereUndeleted:) withObject:moved];
					if (slidesWindow.visible)
						[slidesWindow filesWereUndeleted:moved];
					if (moved.count < n) {
						NSAlert *alert = [[NSAlert alloc] init];
						alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"%lu file(s) could not be moved back because of an error.",@""), n-moved.count];
						DYRunAlert(alert);
					}
				}];
				[um setActionName:[NSString stringWithFormat:NSLocalizedString(@"Move Files (%lu File(s))",@"for undo"), n]];
			}
		}
		[frontWindow updateExifInfo];
		// no selection means all files were successfully deleted; select the next image if possible
		if (frontWindow.selectedIndexes.firstIndex == NSNotFound && oldIndex < frontWindow.displayedFilenames.count) {
			[frontWindow selectIndex:oldIndex];
		}
	}
}

- (IBAction)moveToTrash:(id)sender {
	[self removePicsAndTrash:YES];
}

// permanently delete the selected file(s), bypassing the trash. This cannot be undone,
// so we always ask for confirmation first.
- (IBAction)deleteSelectedFilesPermanently:(id)sender {
	NSArray *files;
	if (slidesWindow.isMainWindow) {
		NSString *s = slidesWindow.currentFile;
		files = s ? @[s] : @[];
	} else {
		files = frontWindow.currentSelection;
	}
	NSUInteger n = files.count;
	if (n == 0) {
		NSBeep();
		return;
	}

	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = n == 1
		? [NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to permanently delete “%@”?", @""), [files[0] lastPathComponent]]
		: [NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to permanently delete these %lu items?", @""), (unsigned long)n];
	alert.informativeText = NSLocalizedString(@"This operation cannot be undone.", @"");
	if (n == 1)
		alert.icon = [thumbsCache imageForKey:ResolveAliasToPath(files[0])];
	[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
	NSButton *deleteButton = [alert addButtonWithTitle:NSLocalizedString(@"Delete", @"Delete Immediately Button")];
	deleteButton.hasDestructiveAction = YES;
	if (DYRunAlert(alert) != NSAlertSecondButtonReturn)
		return;

	BOOL slideshowMain = slidesWindow.isMainWindow;
	NSUInteger oldIndex = slideshowMain ? NSNotFound : frontWindow.selectedIndexes.firstIndex;
	NSMutableArray<NSString *> *notDeleted = [NSMutableArray array];
	for (NSString *fullpath in files) {
		NSURL *url = [NSURL fileURLWithPath:fullpath isDirectory:NO];
		NSError * __autoreleasing error = nil;
		if ([NSFileManager.defaultManager removeItemAtURL:url error:&error]) {
			if (!IsAliasFilePath(fullpath))
				[thumbsCache removeImageForKey:fullpath];
			[creeveyWindows makeObjectsPerformSelector:@selector(fileWasDeleted:) withObject:fullpath];
			if (slidesWindow.visible)
				[slidesWindow removeImageForFile:fullpath];
		} else {
			[notDeleted addObject:fullpath];
		}
	}
	if (notDeleted.count) {
		alert = [[NSAlert alloc] init];
		alert.informativeText = notDeleted.count == 1
			? [NSString stringWithFormat:NSLocalizedString(@"The file “%@” could not be deleted because an error occurred.", @""), [notDeleted[0] lastPathComponent]]
			: [NSString stringWithFormat:NSLocalizedString(@"%lu file(s) could not be deleted because an error occurred.", @""), (unsigned long)notDeleted.count];
		DYRunAlert(alert);
	}
	if (!slideshowMain) {
		[frontWindow updateExifInfo];
		// no selection means all files were successfully deleted; select the next image if possible
		if (frontWindow.selectedIndexes.firstIndex == NSNotFound && oldIndex != NSNotFound && oldIndex < frontWindow.displayedFilenames.count)
			[frontWindow selectIndex:oldIndex];
	}
}

// rename the single selected file. Undoable.
- (IBAction)renameSelectedFile:(id)sender {
	NSString *oldPath;
	if (slidesWindow.isMainWindow) {
		oldPath = slidesWindow.currentFile;
	} else {
		NSArray *sel = frontWindow.currentSelection;
		if (sel.count != 1) {
			NSBeep();
			return;
		}
		oldPath = sel[0];
	}
	if (oldPath == nil) {
		NSBeep();
		return;
	}

	NSString *oldName = oldPath.lastPathComponent;
	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = NSLocalizedString(@"Rename File", @"");
	// keep the message constant (the current name is shown in the field below) so it
	// stays one line no matter how long the file name is
	alert.informativeText = NSLocalizedString(@"Enter a new name for this file.", @"");
	alert.icon = [thumbsCache imageForKey:ResolveAliasToPath(oldPath)];
	// Word-wrapping field, fixed width, whose height grows to show the ENTIRE name so
	// nothing is ever hidden, plus a live character count so the true length is always
	// explicit — before and after editing.
	CGFloat width = 340;
	NSFont *font = [NSFont systemFontOfSize:NSFont.systemFontSize];
	NSSize inset = NSMakeSize(4, 3);
	NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, width, 54)];
	sv.borderType = NSBezelBorder;
	sv.hasVerticalScroller = YES;
	NSSize probeContent = [NSScrollView contentSizeForFrameSize:NSMakeSize(width, 54)
										horizontalScrollerClass:Nil verticalScrollerClass:Nil
													 borderType:NSBezelBorder controlSize:NSControlSizeRegular
												  scrollerStyle:NSScrollerStyleOverlay];
	CGFloat contentWidth = probeContent.width;
	CGFloat borderChrome = 54 - probeContent.height; // frame height beyond the text area

	NSTextView *input = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, contentWidth, 54)];
	input.font = font;
	input.richText = NO;
	input.allowsUndo = YES; // enable Cmd-Z / Shift-Cmd-Z for typed text
	// never let macOS "helpfully" rewrite a file name
	input.automaticQuoteSubstitutionEnabled = NO;
	input.automaticDashSubstitutionEnabled = NO;
	input.automaticTextReplacementEnabled = NO;
	input.automaticSpellingCorrectionEnabled = NO;
	input.textContainerInset = inset;
	input.minSize = NSMakeSize(0, 0);
	input.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
	input.verticallyResizable = YES;
	input.horizontallyResizable = NO;
	input.textContainer.widthTracksTextView = YES;
	input.textContainer.size = NSMakeSize(contentWidth, FLT_MAX);
	input.string = oldName;

	// count the ACTUAL wrapped lines at the display width (line fragments, not a rounded
	// height) and grow the box to show them all, bounded to ~1/3 of the screen
	NSLayoutManager *lm = input.layoutManager;
	NSTextContainer *tc = input.textContainer;
	[lm ensureLayoutForTextContainer:tc];
	CGFloat lineHeight = [lm defaultLineHeightForFont:font];
	NSUInteger numLines = 0, glyphIndex = 0, glyphCount = lm.numberOfGlyphs;
	while (glyphIndex < glyphCount) {
		NSRange lineRange;
		[lm lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:&lineRange];
		glyphIndex = NSMaxRange(lineRange);
		++numLines;
	}
	CGFloat screenAvail = (NSScreen.mainScreen ? NSScreen.mainScreen.visibleFrame.size.height : 800) / 3.0;
	NSUInteger maxRows = MAX((NSUInteger)1, (NSUInteger)floor(screenAvail / lineHeight));
	NSUInteger rows = MAX((NSUInteger)1, MIN(maxRows, numLines));
	sv.autohidesScrollers = (rows >= numLines); // persistent bar only if (improbably) clipped
	CGFloat contentHeight = rows * lineHeight + 2 * inset.height;
	CGFloat scrollHeight = contentHeight + borderChrome;
	input.frame = NSMakeRect(0, 0, contentWidth, contentHeight);
	sv.documentView = input;

	// live character count under the field
	NSTextField *countLabel = [NSTextField labelWithString:DYCharacterCountString(oldName.length)];
	countLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
	countLabel.textColor = NSColor.secondaryLabelColor;
	countLabel.alignment = NSTextAlignmentRight;
	CGFloat labelHeight = ceil(countLabel.intrinsicContentSize.height);
	CGFloat gap = 4;
	countLabel.frame = NSMakeRect(0, 0, width, labelHeight);
	sv.frame = NSMakeRect(0, labelHeight + gap, width, scrollHeight);

	NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, scrollHeight + gap + labelHeight)];
	[accessory addSubview:sv];
	[accessory addSubview:countLabel];
	alert.accessoryView = accessory;

	DYRenameFieldDelegate *fieldDelegate = [[DYRenameFieldDelegate alloc] init];
	fieldDelegate.alert = alert;
	fieldDelegate.countLabel = countLabel;
	input.delegate = fieldDelegate;
	// NSTextView.delegate is weak, so tie the delegate's lifetime to the alert
	objc_setAssociatedObject(alert, _cmd, fieldDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	// preselect the base name (without the extension), like the Finder
	NSString *ext = oldName.pathExtension;
	input.selectedRange = NSMakeRange(0, ext.length ? oldName.length - ext.length - 1 : oldName.length);
	[alert addButtonWithTitle:NSLocalizedString(@"Rename", @"")];
	[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
	alert.window.initialFirstResponder = input;
	if (DYRunAlert(alert) != NSAlertFirstButtonReturn) {
		// cancelled: keep the same image selected in the browser
		if (!slidesWindow.isMainWindow)
			[frontWindow.window makeFirstResponder:frontWindow.imageMatrix];
		return;
	}

	// file names are single-line; drop any newlines that slipped in (e.g. via paste)
	NSString *newName = [[input.string componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@""];
	if (newName.length == 0 || [newName isEqualToString:oldName])
		return; // nothing to do
	if ([newName containsString:@"/"] || [newName hasPrefix:@"."]) {
		alert = [[NSAlert alloc] init];
		alert.informativeText = NSLocalizedString(@"File names cannot contain “/” or begin with a period.", @"");
		DYRunAlert(alert);
		return;
	}
	NSString *newPath = [oldPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:newName];
	if ([NSFileManager.defaultManager fileExistsAtPath:newPath]) {
		alert = [[NSAlert alloc] init];
		alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"An item named “%@” already exists in this location.", @""), newName];
		DYRunAlert(alert);
		return;
	}

	NSUndoManager *um = slidesWindow.isMainWindow ? slidesWindow.undoManager : frontWindow.window.undoManager;
	[self performRenameFrom:oldPath to:newPath undoManager:um];

	// keep the just-renamed file selected in the browser. It is re-added asynchronously
	// (via filesWereUndeleted:), so defer the selection to run right after that.
	if (!slidesWindow.isMainWindow) {
		CreeveyMainWindowController *wc = frontWindow;
		dispatch_async(dispatch_get_main_queue(), ^{
			NSUInteger idx = [wc indexOfFilename:newPath];
			if (idx != NSNotFound) {
				[wc.window makeFirstResponder:wc.imageMatrix];
				[wc selectIndex:idx];
			}
		});
	}
}

// does the actual file rename, updates the UI, and registers the inverse for undo/redo
- (void)performRenameFrom:(NSString *)oldPath to:(NSString *)newPath undoManager:(NSUndoManager *)um {
	NSError * __autoreleasing err = nil;
	if (![NSFileManager.defaultManager moveItemAtPath:oldPath toPath:newPath error:&err]) {
		NSAlert *alert = [[NSAlert alloc] init];
		alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The file “%@” could not be renamed because of an error: %@", @""), oldPath.lastPathComponent, err.localizedDescription];
		DYRunAlert(alert);
		return;
	}
	[self fileWasRenamedFrom:oldPath to:newPath];
	[um registerUndoWithTarget:self handler:^(id target) {
		[target performRenameFrom:newPath to:oldPath undoManager:um];
	}];
	[um setActionName:NSLocalizedString(@"Rename", @"for undo")];
}

// propagate a completed rename to the open windows (a rename looks like a delete + re-add)
- (void)fileWasRenamedFrom:(NSString *)oldPath to:(NSString *)newPath {
	if (!IsAliasFilePath(oldPath))
		[thumbsCache removeImageForKey:oldPath];
	[creeveyWindows makeObjectsPerformSelector:@selector(fileWasDeleted:) withObject:oldPath];
	[creeveyWindows makeObjectsPerformSelector:@selector(filesWereUndeleted:) withObject:@[newPath]];
	if (slidesWindow.visible) {
		if (slidesWindow.isMainWindow && [slidesWindow.currentFile isEqualToString:oldPath]) {
			// keep the slideshow showing the renamed file: insert the new name, then drop the old one
			[slidesWindow insertFile:newPath atIndex:slidesWindow.currentIndex];
			[slidesWindow removeImageForFile:oldPath];
		} else {
			[slidesWindow removeImageForFile:oldPath];
			[slidesWindow filesWereUndeleted:@[newPath]];
		}
	}
}

#pragma mark matrix view methods

- (void)moveElsewhere {
	_movedUrls = frontWindow.imageMatrix.movedUrls;
	_originalPaths = frontWindow.imageMatrix.originPaths;
	[self removePicsAndTrash:NO];
}

- (unsigned short)exifOrientationForFile:(NSString *)s {
	NSString *path = ResolveAliasToPath(s);
	DYImageInfo *i = [thumbsCache infoForKey:path];
	return i ? i->exifOrientation : [DYExiftags orientationForFile:path];
}

#pragma mark app delegate methods

- (BOOL)slideshowFromStartupPreference {
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	NSString *path = [u integerForKey:@"startupOption"] == 0 ? [u stringForKey:@"lastFolderPath"] : [u stringForKey:@"picturesFolderPath"];
	BOOL isDir;
	if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir] && isDir) {
		BOOL fullScreen = ![u boolForKey:@"startupSlideshowInWindow"];
		short int sortOrder = [u integerForKey:@"sortBy"];
		[slidesWindow loadFilenames:nil fromPath:path fullScreen:fullScreen wantsSubfolders:[u boolForKey:@"startupSlideshowSubfolders"] comparator:ComparatorForSortOrder(sortOrder) sortOrder:sortOrder];
		return YES;
	}
	return NO;
}

- (void)slideshowFromDraggedPaths:(NSArray *)filenames {
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	BOOL fullScreen = slidesWindow.visible ? slidesWindow.fullscreenMode : [u integerForKey:@"slideshowDefaultMode"] == 0;
	short int sortOrder = [u integerForKey:@"sortBy"];
	NSString *dir = nil;
	if (filenames.count == 1) {
		NSString *thePath = filenames[0];
		BOOL isDir;
		if ([NSFileManager.defaultManager fileExistsAtPath:thePath isDirectory:&isDir] && isDir) {
			dir = thePath;
			filenames = nil;
		} else {
			dir = [thePath stringByDeletingLastPathComponent];
		}
	}
	[slidesWindow loadFilenames:filenames fromPath:dir fullScreen:fullScreen wantsSubfolders:NO comparator:ComparatorForSortOrder(sortOrder) sortOrder:sortOrder];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;

	// load the keybinding config and apply it to the menu (also creates a template
	// on first launch so the file is there to edit)
	_keyBindings = [[KeyBindings alloc] init];
	[_keyBindings writeTemplateIfMissing]; // migrate/create before reading
	[_keyBindings load];
	[_keyBindings applyToMainMenu];
	[_keyBindings reportErrorsIfAny];

	// warm up Quick Look after launch so the first Space press doesn't also pay the
	// QuickLookUI framework load / panel creation cost on top of rendering
	dispatch_async(dispatch_get_main_queue(), ^{
		(void)QLPreviewPanel.sharedPreviewPanel;
	});

	[self showExifThumbnail:[u boolForKey:@"exifThumbnailShow"]
			   shrinkWindow:NO];

	_appDidFinishLaunching = YES;
	if (_windowsWereRestoredAtLaunch && _filesWereOpenedAtLaunch) {
		// ugly hack to force the slideshow window to be on top of the restored windows
		BOOL wasVisible = slidesWindow.isVisible;
		[slidesWindow orderFront:nil];
		if (!wasVisible) [slidesWindow orderOut:nil];
	}

	[self applySlideshowPrefs:nil];
	[self updateSlideshowBgColor];
	[self updateTransparentImageBgColor];
	[self updateSlideshowFitToImage];
	BOOL doSlideshow = [u boolForKey:@"startupSlideshowFromFolder"];
	BOOL suppressNewWindow = doSlideshow && [u boolForKey:@"startupSlideshowSuppressNewWindows"];
	if (doSlideshow) {
		if (![self slideshowFromStartupPreference]) {
			// fail silently and open a new window if necessary
			suppressNewWindow = NO;
		}
	} else if (![u boolForKey:@"openFilesOpensBrowserWindowIfNone"] && _filesWereOpenedAtLaunch) {
		suppressNewWindow = YES;
	}

	// between version 1.5.3 and 1.5.8, new users would get the splitview collapsed by default,
	// which was unintentional and made certain features undiscoverable
	if (0.0 == [u floatForKey:@"MainWindowSplitViewTopHeight"] && ![u integerForKey:@"zSplitViewZeroHeightFixed"]) {
		if (creeveyWindows.count) {
			// as a hint to the user, set the frontmost window's splitview position to something non-zero
			NSSplitView *splitView = ((NSWindowController *)creeveyWindows.lastObject).window.contentView.subviews[0];
			dispatch_async(dispatch_get_main_queue(), ^{
				[splitView setPosition:151.0 ofDividerAtIndex:0];
			});
		} else {
			[u setFloat:151.0 forKey:@"MainWindowSplitViewTopHeight"];
		}
		// only ever do this once
		[u setInteger:1 forKey:@"zSplitViewZeroHeightFixed"];
	}

	// open a new window if there isn't one (either from dropping icons onto app at launch, or from restoring saved state)
	if (!frontWindow && !_windowsWereRestoredAtLaunch && !suppressNewWindow)
		[self newWindow:self];

	NSTimeInterval t = NSDate.timeIntervalSinceReferenceDate;
	if ([u boolForKey:@"autoVersCheck"]
		&& (t - [u doubleForKey:@"lastVersCheckTime"] > DYVERSCHECKINTERVAL)) // one week
		DYVersCheckForUpdateAndNotify(NO);

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
		// because screw thread safety
		@autoreleasepool {
			NSArray<NSArray *> *savedCats = [catDefaults arrayForKey:@"cats"];
			short i = 0;
			for (NSArray *a in savedCats) {
				NSMutableArray *readable = [NSMutableArray arrayWithCapacity:a.count];
				for (NSString *path in a) {
					if (0 == access(path.fileSystemRepresentation, R_OK))
						[readable addObject:path];
				}
				[cats[i++] addObjectsFromArray:readable];
			}
			[self updateCats];
		}
	});
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	if (creeveyWindows.count)
		[frontWindow updateDefaults];
	if (frontWindow) [self noteRecentFolderForWindow:frontWindow]; // capture the current folder's final state
	[self flushRecentFolders];
	[u setBool:(slidesWindow.isMainWindow || creeveyWindows.count == 0) ? exifWasVisible : exifTextView.window.visible
		forKey:@"getInfoVisible"];
	[u synchronize];
	[CreeveyMainWindowController sweepLeftoverArchiveTemps]; // remove any extracted-archive temp dirs on quit
}

- (void)openFilesCoalesced {
	BOOL doSlideshow = [NSUserDefaults.standardUserDefaults boolForKey:@"openFilesDoSlideshow"];
	if (creeveyWindows.count)
		[frontWindow openFiles:_coalescedFilesToOpen withSlideshow:doSlideshow];
	else
		[self slideshowFromDraggedPaths:[_coalescedFilesToOpen copy]];
	[_coalescedFilesToOpen removeAllObjects];
}

- (void)openFiles:(NSArray *)files {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	if (![ud boolForKey:@"openFilesDoSlideshow"] || [ud boolForKey:@"openFilesOpensBrowserWindowIfNone"]) {
		if (!creeveyWindows.count) [self newWindow:nil];
		[frontWindow.window makeKeyAndOrderFront:nil];
	}
	if (!_appDidFinishLaunching)
		_filesWereOpenedAtLaunch = YES;
	[_coalescedFilesToOpen addObjectsFromArray:files];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[self performSelector:@selector(openFilesCoalesced) withObject:nil afterDelay:0.5];
}

- (BOOL)application:(NSApplication *)sender
		   openFile:(NSString *)filename {
	[self openFiles:@[filename]];
	return YES;
}

- (void)application:(NSApplication *)sender
		  openFiles:(NSArray *)files {
	[self openFiles:files];
	[sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag {
	if (!creeveyWindows.count) {
		NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
		if ([u boolForKey:@"startupSlideshowFromFolder"]) {
			if ([self slideshowFromStartupPreference])
				if ([u boolForKey:@"startupSlideshowSuppressNewWindows"])
					return NO;
		}
		[self newWindow:self];
		return NO;
	}
	return YES;
}

-(void)applicationDidChangeScreenParameters:(NSNotification *)notification {
	[slidesWindow resetScreen];
}

#pragma mark menu methods
enum {
	REVEAL_IN_FINDER = 1,
	MOVE_TO_TRASH,
	LOOP, // Embiggen is also 3
	BEGIN_SLIDESHOW,
	SET_DESKTOP,
	GET_INFO,
	RANDOM_MODE,
	SLIDESHOW_SCALE_UP,
	SLIDESHOW_ACTUAL_SIZE,
	NEW_TAB,
	BEGIN_SLIDESHOW_ALTERNATE,
	MOVE_TO,
	MOVE_TO_AGAIN,
	COPY_TO,
	COPY_TO_AGAIN,
	RENAME,
	DELETE_PERMANENTLY,
	QUICK_LOOK = 20, // 18=New Window, 19=Select None (tags live only in MainMenu.xib)
	GO_TO_FOLDER = 24, // 21=Preferences, 22=End Slideshow, 23=Cheat Sheet (tags in MainMenu.xib)
	SHOW_DIRECTORY_BROWSER = 25,
	SHOW_PATH_BAR = 26,
	SHOW_UNSUPPORTED = 27,
	COPY_PATHNAME = 28,
	SEARCH = 29,
	SUBFOLDERS = 30,
	ZOOM_IN = 31,
	ZOOM_OUT = 32,
	ZOOM_ACTUAL = 32+1,
	ZOOM_FIT = 32+2,
	JPEG_OP = 100,
	ROTATE_L = 107,
	ROTATE_R = 105,
	EXIF_ORIENT_ROTATE = 113,
	EXIF_ORIENT_RESET = 114,
	EXIF_THUMB_DELETE = 116,
	ROTATE_SAVE = 117,
	SORT_NAME = 201,
	SORT_DATE_MODIFIED = 202,
	SORT_EXIF_DATE = 203,
	SORT_ADDED_DATE,
	SORT_TYPE,
	SORT_SIZE,
	SORT_FILEPATH,
	SHOW_FILE_NAMES = 251,
	AUTO_ROTATE = 261,
	SLIDESHOW_MENU = 1001,
	VIEW_MENU = 200,
	FILE_MENU = 300,
};


// View ▸ Zoom menu commands (⌘+ / ⌘− / ⌘0 / ⌘9). Forward to the slideshow; validateMenuItem:
// keeps them enabled only while a slideshow image is showing.
- (IBAction)zoomIn:(id)sender          { [slidesWindow performSlideshowAction:SlideshowActionZoomIn]; }
- (IBAction)zoomOut:(id)sender         { [slidesWindow performSlideshowAction:SlideshowActionZoomOut]; }
- (IBAction)zoomActualSize:(id)sender  { [slidesWindow performSlideshowAction:SlideshowActionActualSize]; }
- (IBAction)zoomFitToWindow:(id)sender { [slidesWindow performSlideshowAction:SlideshowActionResetView]; }

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	// Preferences carries a tag only so it can be rebound; it's always available,
	// so validate it by action rather than falling into the tag-based gates below.
	if (menuItem.action == @selector(openPrefWin:)) return YES;
	NSInteger t = menuItem.tag;
	NSInteger test_t = t;
	if (!NSApp.mainWindow) {
		// menu items with tags only enabled if there's a window
		return !t;
	}
	if (t>JPEG_OP && t < SORT_NAME) {
		if ((t > JPEG_OP + 30 || t == EXIF_THUMB_DELETE) &&
			!menuItem.menu.supermenu && // only for contextual menu
			![[exifThumbnailDiscloseBtn.window.contentView viewWithTag:2] image]) {
			return NO;
		}
		test_t = JPEG_OP;
	}
	if (t > SORT_NAME && t <= SORT_FILEPATH)
		test_t = SORT_NAME;
	if (!creeveyWindows.count) frontWindow = nil;
	NSUInteger numSelected = frontWindow ? frontWindow.selectedIndexes.count : 0;
	BOOL writable, isjpeg;
	switch (test_t) {
		case NEW_TAB:
			return frontWindow.window.isMainWindow;
		case MOVE_TO_AGAIN:
		case MOVE_TO:
		case COPY_TO_AGAIN:
		case COPY_TO:
		case MOVE_TO_TRASH:
		case DELETE_PERMANENTLY:
		case JPEG_OP:
			// only when slides isn't loading cache!
			// only if writeable (we just test the first file in the list)
			writable = slidesWindow.isMainWindow
				? slidesWindow.currentFile &&
					slidesWindow.currentImageLoaded &&
					[NSFileManager.defaultManager isDeletableFileAtPath:
					 slidesWindow.currentFile]
				: numSelected > 0 && frontWindow && frontWindow.currentFilesDeletable;
			if (!writable) return NO;
			if (test_t != JPEG_OP) {
				// Move/Copy To Recent (submenu parents): enable only when the recent list isn't empty.
				if (t == MOVE_TO_AGAIN) return [self recentDestinationsForKey:@"recentMoveToFolders"].count > 0;
				if (t == COPY_TO_AGAIN) return [self recentDestinationsForKey:@"recentCopyToFolders"].count > 0;
				return YES;
			}
			isjpeg = slidesWindow.isMainWindow
				? slidesWindow.currentFile && FileIsJPEG(slidesWindow.currentFile)
				: numSelected > 0 && frontWindow && FilesContainJPEG(frontWindow.currentSelection);
			if (!isjpeg) return NO;
			if (t == ROTATE_SAVE) { // only allow saving rotations during the slideshow
				return slidesWindow.isMainWindow && slidesWindow.currentOrientation > 1;
			}
			if ((t == EXIF_ORIENT_ROTATE || t == EXIF_ORIENT_RESET) && slidesWindow.isMainWindow) {
				return slidesWindow.currentFileExifOrientation > 1;
			}
			return isjpeg;
		case REVEAL_IN_FINDER:
			return YES;
		case BEGIN_SLIDESHOW:
		case BEGIN_SLIDESHOW_ALTERNATE:
			if (slidesWindow.isMainWindow ) return NO;
			return frontWindow && frontWindow.filenamesDone && frontWindow.displayedFilenames.count;
		case QUICK_LOOK:
			// SPACE only previews when a browser window with a selection is frontmost,
			// so it won't hijack SPACE in the slideshow, Prefs, or text fields
			if (slidesWindow.isMainWindow) return NO;
			return numSelected > 0 && frontWindow && frontWindow.window.isMainWindow && frontWindow.filenamesDone;
		case ZOOM_IN:
		case ZOOM_OUT:
		case ZOOM_ACTUAL:
		case ZOOM_FIT:
			// image zoom is a slideshow-only command
			return slidesWindow.isMainWindow && slidesWindow.currentImageLoaded;
		case GO_TO_FOLDER:
			return !slidesWindow.isMainWindow && frontWindow != nil;
		case SEARCH:
			return !slidesWindow.isMainWindow && frontWindow != nil;
		case SUBFOLDERS:
			menuItem.state = frontWindow.wantsSubfolders;
			return !slidesWindow.isMainWindow && frontWindow != nil;
		case COPY_PATHNAME:
			return !slidesWindow.isMainWindow && numSelected > 0;
		case SHOW_PATH_BAR:
			// Show/Hide verb-swap (Finder convention for toggling a UI element), no checkmark
			menuItem.title = frontWindow.pathBarVisible ? @"Hide Path Bar" : @"Show Path Bar";
			menuItem.state = NSControlStateValueOff;
			return !slidesWindow.isMainWindow && frontWindow != nil;
		case SHOW_DIRECTORY_BROWSER:
			menuItem.title = frontWindow.directoryBrowserVisible ? @"Hide Directory Browser" : @"Show Directory Browser";
			menuItem.state = NSControlStateValueOff;
			return !slidesWindow.isMainWindow && frontWindow != nil;
		case SHOW_FILE_NAMES:
			menuItem.title = frontWindow.imageMatrix.showFilenames ? @"Hide File Names" : @"Show File Names";
			menuItem.state = NSControlStateValueOff;
			return !slidesWindow.isMainWindow && frontWindow != nil;
		case SHOW_UNSUPPORTED:
			// a content-filter option, so a checkmark (not a Show/Hide verb-swap)
			menuItem.state = frontWindow.showUnsupportedFiles;
			return !slidesWindow.isMainWindow && frontWindow != nil;
		case SET_DESKTOP:
			return slidesWindow.isMainWindow
				? (slidesWindow.currentFile != nil)
				: numSelected == 1;
		case RENAME:
			// renaming operates on a single file
			return slidesWindow.isMainWindow
				? (slidesWindow.currentFile &&
					slidesWindow.currentImageLoaded &&
					[NSFileManager.defaultManager isDeletableFileAtPath:slidesWindow.currentFile])
				: numSelected == 1 && frontWindow && frontWindow.currentFilesDeletable;
		case AUTO_ROTATE:
			return YES;
		case GET_INFO:
		case SORT_NAME:
			return !slidesWindow.isMainWindow;
		default:
			return YES;
	}
}

- (void)updateMenuItemsForSorting:(short int)sortNum {
	short int sortType = abs(sortNum);
	NSInteger tag = 200 + sortType;
	NSMenu *m = [NSApp.mainMenu itemWithTag:VIEW_MENU].submenu;
	for (NSInteger i = 201; i <= SORT_FILEPATH; ++i) {
		NSMenuItem *item = [m itemWithTag:i];
		if (i == tag) {
			item.state = sortNum > 0 ? NSControlStateValueOn : NSControlStateValueMixed;
		} else {
			item.state = NSControlStateValueOff;
		}
	}
}

- (IBAction)sortThumbnails:(id)sender {
	NSInteger tag = [sender tag];
	short int oldSort = frontWindow.sortOrder, newSort = tag - 200;
	
	if (newSort == abs(oldSort)) {
		newSort = -oldSort; // reverse the sort if user selects it again
	} else {
		if (tag >= SORT_DATE_MODIFIED && tag <= SORT_ADDED_DATE) newSort = -newSort; // default to reverse sort if sorting by date
	}
	[self updateMenuItemsForSorting:newSort];
	[frontWindow changeSortOrder:newSort];
	if (creeveyWindows.count == 1) // save as default if this is the only window
		[NSUserDefaults.standardUserDefaults setInteger:newSort forKey:@"sortBy"];
}

- (IBAction)doShowFilenames:(id)sender {
	// title flips Show/Hide in validateMenuItem, so no checkmark to set here
	BOOL b = !frontWindow.imageMatrix.showFilenames;
	frontWindow.imageMatrix.showFilenames = b;
	if (creeveyWindows.count == 1) // save as default if this is the only window
		[NSUserDefaults.standardUserDefaults setBool:b forKey:@"showFilenames"];
	[self noteRecentFolderForWindow:frontWindow];
}

- (IBAction)togglePathBar:(id)sender {
	frontWindow.pathBarVisible = !frontWindow.pathBarVisible;
	[NSUserDefaults.standardUserDefaults setBool:frontWindow.pathBarVisible forKey:@"showPathBar"];
	[self noteRecentFolderForWindow:frontWindow];
}

- (IBAction)toggleDirectoryBrowser:(id)sender {
	// the split view persists its own position (MainWindowSplitViewTopHeight), so the
	// collapsed state is remembered across launches without a separate preference
	frontWindow.directoryBrowserVisible = !frontWindow.directoryBrowserVisible;
	[self noteRecentFolderForWindow:frontWindow];
}

- (IBAction)toggleUnsupportedFiles:(id)sender {
	// the window re-scans its folder when this flips (see setShowUnsupportedFiles:)
	frontWindow.showUnsupportedFiles = !frontWindow.showUnsupportedFiles;
}

- (IBAction)doAutoRotateDisplayedImage:(id)sender {
	BOOL b = slidesWindow.isMainWindow ? !slidesWindow.autoRotate : !frontWindow.imageMatrix.autoRotate;
	NSMenuItem *item = sender;
	item.state = b;
	frontWindow.imageMatrix.autoRotate = b;
	slidesWindow.autoRotate = b;
	if (creeveyWindows.count == 1 || slidesWindow.isMainWindow)
		[NSUserDefaults.standardUserDefaults setBool:b forKey:@"autoRotateByOrientationTag"];
	if (!slidesWindow.isMainWindow) [self noteRecentFolderForWindow:frontWindow];
}

- (IBAction)searchImages:(id)sender {
	[frontWindow focusSearchField];
}

- (IBAction)toggleSubfolders:(id)sender {
	// flip the Subfolders checkbox and run its normal action (sets recurseRoot, reloads)
	NSButton *b = frontWindow.subfoldersButton;
	b.state = b.state == NSControlStateValueOn ? NSControlStateValueOff : NSControlStateValueOn;
	[frontWindow setRecurseSubfolders:b];
}

#pragma mark prefs stuff
- (IBAction)goToFolder:(id)sender {
	CreeveyMainWindowController *wc = frontWindow;
	if (!wc) return;
	NSString *abbrev = wc.path.stringByAbbreviatingWithTildeInPath;
	// append a trailing slash (so the field lists the folder's contents) unless the path is
	// already slash-terminated, e.g. root "/" — otherwise we'd produce "//"
	NSString *start = wc.path.length ? ([abbrev hasSuffix:@"/"] ? abbrev : [abbrev stringByAppendingString:@"/"]) : @"~/";
	[GoToFolderController presentForWindow:wc.window startingPath:start completion:^(NSString *chosen){
		if (chosen) [wc setPath:chosen];
	}];
}

- (IBAction)openPrefWin:(id)sender {
	if (!prefsWin) {
		NSArray * __autoreleasing arr;
		if (![NSBundle.mainBundle loadNibNamed:@"PrefsWin" owner:self topLevelObjects:&arr]) return;
		_prefWinNibItems = arr;
		// non-NSMatrix based radio buttons don't seem to have a way to bind values
		NSButton *btn = [NSUserDefaults.standardUserDefaults integerForKey:@"slideshowDefaultMode"] ? [self.slideshowDefaultModeFullscreenBtn.superview viewWithTag:1] : self.slideshowDefaultModeFullscreenBtn;
		btn.state = NSControlStateValueOn;
	}
    [prefsWin makeKeyAndOrderFront:nil];
}
- (IBAction)chooseStartupDir:(id)sender {
    NSOpenPanel *op=[NSOpenPanel openPanel];
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	
    op.canChooseDirectories = YES;
    op.canChooseFiles = NO;
	op.directoryURL = [NSURL fileURLWithPath:[u stringForKey:@"picturesFolderPath"] isDirectory:YES];
	[op beginSheetModalForWindow:prefsWin completionHandler:^(NSInteger result) {
		if (result == NSModalResponseOK) {
			[u setObject:(op.URLs[0]).path forKey:@"picturesFolderPath"];
			[u setInteger:1 forKey:@"startupOption"];
		}
	}];
}

- (IBAction)openAboutPanel:(id)sender {
	NSMutableDictionary *opts = [@{NSAboutPanelOptionApplicationIcon: [NSImage imageNamed:@"logo"]} mutableCopy];
	// append the short git commit hash (stamped into GitInfo.plist at build time) to the build number
	NSBundle *b = NSBundle.mainBundle;
	NSURL *gitInfoURL = [b URLForResource:@"GitInfo" withExtension:@"plist"];
	NSString *hash = gitInfoURL ? [NSDictionary dictionaryWithContentsOfURL:gitInfoURL][@"GitCommitHash"] : nil;
	NSString *build = [b objectForInfoDictionaryKey:@"CFBundleVersion"];
	if (hash.length && build.length)
		opts[NSAboutPanelOptionVersion] = [NSString stringWithFormat:@"%@ · %@", build, hash];
	[NSApp orderFrontStandardAboutPanelWithOptions:opts];
}

#pragma mark configuration

- (IBAction)reloadConfiguration:(id)sender {
	[_keyBindings load];
	[_keyBindings applyToMainMenu];
	[_keyBindings reportErrorsIfAny];
}

- (IBAction)editConfiguration:(id)sender {
	[_keyBindings openInEditor];
}

- (IBAction)revealConfiguration:(id)sender {
	[_keyBindings revealInFinder];
}

// avoid warning "PerformSelector may cause a leak because its selector is unknown"
// ARC can't handle performSelector: with an unknown selector, so we explicitly convert the selector to a C function
static void SendAction(NSMenuItem *sender) {
	id target = sender.target;
	if (target) {
		SEL action = sender.action;
		void (*func)(id, SEL, id) = (void *)[target methodForSelector:action];
		func(target, action, sender);
	}
}

// This gets called in three circumstances: (1) at startup, to set up our menu/slideshow window,
// (2) always, when the slideshow window is closed and a setting is changed, and
// (3) when the "Apply" button is clicked (only enabled when the slideshow window is visible)
- (IBAction)applySlideshowPrefs:(id)sender {
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	NSMenu *m = [NSApp.mainMenu itemWithTag:SLIDESHOW_MENU].submenu;
	NSMenuItem *i;
	i = [m itemWithTag:LOOP];
	i.state = ![u boolForKey:@"slideshowLoop"];
	SendAction(i);
	
	i = [m itemWithTag:RANDOM_MODE];
	i.state = ![u boolForKey:@"slideshowRandom"];
	SendAction(i);

	i = [m itemWithTag:SLIDESHOW_SCALE_UP];
	i.state = ![u boolForKey:@"slideshowScaleUp"];
	SendAction(i);

	i = [m itemWithTag:SLIDESHOW_ACTUAL_SIZE];
	i.state = ![u boolForKey:@"slideshowActualSize"];
	SendAction(i);

	if (slidesWindow.visible) {
		slidesWindow.autoadvanceTime = [u boolForKey:@"slideshowAutoadvance"] ? [u floatForKey:@"slideshowAutoadvanceTime"] : 0;
		[slidesWindow updateTimer];
	}
	
	slideshowApplyBtn.enabled = NO;
}

- (void)updateSlideshowBgColor {
	slidesWindow.backgroundColor = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSColor class] fromData:[NSUserDefaults.standardUserDefaults dataForKey:@"slideshowBgColor"] error:NULL];
	slidesWindow.contentView.needsDisplay = YES;
}

- (void)updateTransparentImageBgColor {
	NSColor *theColor = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSColor class] fromData:[NSUserDefaults.standardUserDefaults dataForKey:@"transparentImageBgColor"] error:NULL];
	for (CreeveyMainWindowController *w in creeveyWindows) {
		w.imgMatrix.imageBackgroundColor = theColor;
	}
	[slidesWindow setTransparentImageBgColor:theColor];
}

- (void)updateSlideshowFitToImage {
	slidesWindow.fitWindowToImage = [NSUserDefaults.standardUserDefaults boolForKey:@"slideshowWindowFitToImage"];
}

- (void)updateAppearance {
	switch ([NSUserDefaults.standardUserDefaults integerForKey:@"appearance"]) {
		case 1: NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua]; break;
		case 2: NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]; break;
		default: NSApp.appearance = nil; break;
	}
}

- (IBAction)slideshowDefaultsChanged:(id)sender {
	if (slidesWindow.visible)
		slideshowApplyBtn.enabled = YES;
	else
		[self applySlideshowPrefs:nil];
}

- (IBAction)chooseDefaultSlideshowMode:(id)sender {
	[NSUserDefaults.standardUserDefaults setInteger:[sender tag] forKey:@"slideshowDefaultMode"];
	[self updateAlternateSlideshowMenuItem];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:(id)object 
                        change:(NSDictionary *)c
                       context:(void *)context
{
    if ([keyPath isEqual:@"values.DYWrappingMatrixMaxCellWidth"]) {
		if (thumbsCache.boundingWidth
			< [NSUserDefaults.standardUserDefaults integerForKey:@"DYWrappingMatrixMaxCellWidth"]) {
			[thumbsCache removeAllImages];
			thumbsCache.boundingSize = [DYWrappingMatrix maxCellSize];
		}
	} else if ([keyPath isEqualToString:@"values.slideshowBgColor"]) {
		[self updateSlideshowBgColor];
	} else if ([keyPath isEqualToString:@"values.transparentImageBgColor"]) {
		[self updateTransparentImageBgColor];
	} else if ([keyPath isEqualToString:@"values.slideshowWindowFitToImage"]) {
		[self updateSlideshowFitToImage];
	} else if ([keyPath isEqualToString:@"values.appearance"]) {
		[self updateAppearance];
	} else if ([keyPath isEqualToString:@"values.interfaceTextSize"]
			   || [keyPath isEqualToString:@"values.interfaceTextCustomSize"]) {
		for (CreeveyMainWindowController *wc in creeveyWindows)
			[wc reloadInterfaceTextSize];
		[slidesWindow reloadInterfaceTextSize];
	}
}


#pragma mark exif thumb
- (IBAction)toggleExifThumbnail:(id)sender {
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	BOOL b = ![u boolForKey:@"exifThumbnailShow"];
	[self showExifThumbnail:b shrinkWindow:YES];
	[u setBool:b forKey:@"exifThumbnailShow"];
}

- (void)showExifThumbnail:(BOOL)b shrinkWindow:(BOOL)shrink {
	NSWindow *w = exifThumbnailDiscloseBtn.window;
	NSView *v = w.contentView;
	NSImageView *imageView = [v viewWithTag:2];
	NSTextView *placeholderTextView = [v viewWithTag:3];
	NSPopUpButton *popdownMenu = [v viewWithTag:6];
	exifThumbnailDiscloseBtn.state = b;
	b = !b;
	if (imageView.hidden != b) {
		NSRect r = w.frame;
		NSRect q;
		if (!shrink)
			q = exifTextView.enclosingScrollView.frame; // get the scrollview, not the textview
		if (b) { // hiding
			if (shrink) {
				r.size.height -= 160;
				r.origin.y += 160;
			} else
				q.size.height += 160;
			placeholderTextView.hidden = b;
			imageView.hidden = b;
			for (NSLayoutConstraint *constraint in imageView.constraints) {
				if (constraint.firstAttribute == NSLayoutAttributeHeight)
					constraint.constant = 0;
			}
			popdownMenu.hidden = b;
		} else { // showing
			if (shrink) {
				r.size.height += 160;
				r.origin.y -= 160;
			} else
				q.size.height -= 160;
		}
		NSView *v2 = exifTextView.enclosingScrollView;
		if (!shrink)
			v2.frame = q;
		else {
			NSUInteger oldMask = v2.autoresizingMask;
			v2.autoresizingMask = NSViewMaxXMargin;
			[w setFrame:r display:YES animate:YES];
			v2.autoresizingMask = oldMask;
		}
		if (!b) {
			placeholderTextView.hidden = b;
			imageView.hidden = b;
			for (NSLayoutConstraint *constraint in imageView.constraints) {
				if (constraint.firstAttribute == NSLayoutAttributeHeight)
					constraint.constant = 160;
			}
			popdownMenu.hidden = b;
		}
	}
}


#pragma mark new window stuff
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
	// opt in to secure behavior in macOS 12 and later. See the AppKit release notes for macOS 14.
	return YES;
}
+ (void)restoreWindowWithIdentifier:(NSString *)identifier
							  state:(NSCoder *)state
				  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler
{
	CreeveyController *appDelegate = (CreeveyController *)NSApp.delegate;
	[appDelegate newWindow:nil];
	CreeveyMainWindowController *wc = [appDelegate windowControllers].lastObject;
	completionHandler(wc.window, nil);
	appDelegate.windowsWereRestoredAtLaunch = YES;
}
- (NSArray *)windowControllers { return creeveyWindows; }

- (IBAction)openGetInfoPanel:(id)sender {
	NSWindow *w = exifTextView.window;
	if (w.visible)
		[w orderOut:self];
	else {
		[w orderFront:self];
		if (creeveyWindows.count) [frontWindow updateExifInfo];
	}
}

- (void)newWindow:(BOOL)asTab init:(BOOL)needsPath {
	if (!creeveyWindows.count) {
		if (exifWasVisible)
			[exifTextView.window orderFront:self]; // only check for first window
	}
	CreeveyMainWindowController *wc = [[CreeveyMainWindowController alloc] initWithWindowNibName:@"CreeveyWindow"];
	[creeveyWindows addObject:wc];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowClosed:) name:NSWindowWillCloseNotification object:wc.window];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowChanged:) name:NSWindowDidBecomeMainNotification object:wc.window];
	if (asTab)
		[frontWindow.window addTabbedWindow:wc.window ordered:NSWindowAbove];
	[wc showWindow:nil]; // or override wdidload
	short int sortOrder = [NSUserDefaults.standardUserDefaults integerForKey:@"sortBy"];
	wc.sortOrder = sortOrder;
	wc.imageMatrix.showFilenames = [NSUserDefaults.standardUserDefaults boolForKey:@"showFilenames"];
	wc.imageMatrix.autoRotate = [NSUserDefaults.standardUserDefaults boolForKey:@"autoRotateByOrientationTag"];
	if (needsPath)
		[wc setDefaultPath];

	// make sure menu items are checked properly (code copied from windowChanged:)
	NSMenu *m = [NSApp.mainMenu itemWithTag:VIEW_MENU].submenu;
	[self updateMenuItemsForSorting:sortOrder];
	// Show File Names uses a Show/Hide title (set in validateMenuItem), so no checkmark here
	[m itemWithTag:AUTO_ROTATE].state = wc.imageMatrix.autoRotate ? NSControlStateValueOn : NSControlStateValueOff;
}

- (IBAction)newWindow:(id)sender {
	[self newWindow:NO init:(sender != nil)];
}

- (IBAction)newTab:(id)sender {
	[self newWindow:YES init:YES];
}

- (void)windowClosed:(NSNotification *)n {
	NSWindowController *wc = [n.object windowController];
	if ([creeveyWindows indexOfObjectIdenticalTo:wc] != NSNotFound) {
		[self noteRecentFolderForWindow:(CreeveyMainWindowController *)wc]; // capture the closing window's folder+state
		[self flushRecentFolders];
		if (wc.window == frontWindow.window) {
			// for some reason closing a tab will call windowChanged: (with the new window) before windowClosed: (with the old window)
			frontWindow = nil;
		}
		if (creeveyWindows.count == 1) {
			[creeveyWindows[0] updateDefaults];
			if ((exifWasVisible = exifTextView.window.visible)) {
				[exifTextView.window orderOut:nil];
			}
		}
		[NSNotificationCenter.defaultCenter removeObserver:self name:nil object:wc.window];
		[creeveyWindows removeObject:wc];
	}
}

- (void)windowChanged:(NSNotification *)n {
	frontWindow = [n.object windowController];
	
	short int sortOrder = frontWindow.sortOrder;
	NSMenu *m = [NSApp.mainMenu itemWithTag:VIEW_MENU].submenu;
	[self updateMenuItemsForSorting:sortOrder];
	// Show File Names uses a Show/Hide title (set in validateMenuItem), so no checkmark here
	[m itemWithTag:AUTO_ROTATE].state = frontWindow.imageMatrix.autoRotate ? NSControlStateValueOn : NSControlStateValueOff;
}

- (IBAction)versionCheck:(id)sender {
	DYVersCheckForUpdateAndNotify(YES);
}
- (IBAction)sendFeedback:(id)sender {
	[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"http://blyt.net/phxslides/feedback.html"]];
}

#pragma mark slideshow window delegate method
- (void)windowDidBecomeMain:(NSNotification *)aNotification {
	if (creeveyWindows.count && (exifWasVisible = exifTextView.window.visible))
		[exifTextView.window orderOut:nil];
	[[NSApp.mainMenu itemWithTag:VIEW_MENU].submenu itemWithTag:AUTO_ROTATE].state = slidesWindow.autoRotate;
	// only needed in case user cycles through windows; see startSlideshow above
}
- (void)windowDidResignMain:(NSNotification *)aNotification {
	// do this here, not in windowChanged, to avoid app switch problems
	if (creeveyWindows.count && exifWasVisible)
		[exifTextView.window orderFront:nil];
	if (creeveyWindows.count && frontWindow.currentSelection.count <= 1) {
		// select the last-shown file by name, not index: after deletions/renames (or random/
		// subset), the slideshow's list and the browser's displayedFilenames diverge, so the
		// old index cross-check failed and left the pre-slideshow (start) file selected
		NSString *endFile = slidesWindow.currentFile;
		NSUInteger i = endFile ? [frontWindow indexOfFilename:endFile] : NSNotFound;
		if (i != NSNotFound)
			[frontWindow selectIndex:i];
	}
}
- (void)windowDidChangeBackingProperties:(NSNotification *)notification {
	[slidesWindow resetScreen];
}


- (DYImageCache *)thumbsCache { return thumbsCache; }
- (NSMutableSet * __strong *)cats { return cats; }
- (void)updateCats {
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:NUM_FNKEY_CATS];
	for (short i=0; i<NUM_FNKEY_CATS; ++i)
		[result addObject:cats[i].allObjects];
	[catDefaults setObject:result forKey:@"cats"];
}

NSDirectoryEnumerator *CreeveyEnumerator(NSString *path, BOOL recurseSubfolders) {
	return [NSFileManager.defaultManager
			enumeratorAtURL:[NSURL fileURLWithPath:path isDirectory:YES]
			includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsHiddenKey,NSURLIsAliasFileKey,NSURLIsSymbolicLinkKey]
			options:recurseSubfolders ? 0 : NSDirectoryEnumerationSkipsSubdirectoryDescendants
			errorHandler:nil];
}

#define IS_URL_DIRECTORY ([url getResourceValue:&val forKey:NSURLIsDirectoryKey error:NULL] && val.boolValue)
#define IS_URL_HIDDEN    ([url getResourceValue:&val forKey:NSURLIsHiddenKey error:NULL] && val.boolValue)

- (BOOL)handledDirectory:(NSURL *)url subfolders:(BOOL)recurse e:(NSDirectoryEnumerator *)e {
	NSNumber * __autoreleasing val;
	if (IS_URL_DIRECTORY) {
		if (recurse && ((IS_URL_HIDDEN && ![_revealedDirectories containsObject:url]) || [url.lastPathComponent isEqualToString:@"Thumbs"]))
			[e skipDescendents]; // special addition for mbatch
		return YES;
	}
	return NO;
}

- (BOOL)shouldShowFile:(NSURL *)url {
	NSNumber * __autoreleasing val;
	if (IS_URL_HIDDEN) return NO;
	url = ResolveAliasURL(url);
	NSString *path = url.path;
	NSString *pathExtension = url.pathExtension.lowercaseString;
	if (pathExtension.length == 0) return [fileostypes containsObject:NSHFSTypeOfFile(path)];
	return [filetypes containsObject:pathExtension] || ([fileostypes containsObject:NSHFSTypeOfFile(path)] && ![disabledFiletypes containsObject:pathExtension]);
}

- (BOOL)isArchiveURL:(NSURL *)url {
	NSString *ext = url.pathExtension.lowercaseString;
	return [ext isEqualToString:@"zip"] || [ext isEqualToString:@"cbz"];
}

- (BOOL)shouldShowFile:(NSURL *)url includingUnsupported:(BOOL)includeUnsupported {
	if ([self shouldShowFile:url]) return YES;
	if ([self isArchiveURL:url]) return YES; // archives are always browsable (double-click to enter)
	if (!includeUnsupported) return NO;
	// admit any other non-hidden file (directories are already handled by the caller); these
	// can't be shown in-app but can be Quick Looked / opened in their default app
	NSNumber * __autoreleasing val;
	if (IS_URL_HIDDEN) return NO;
	return YES;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return fileextensions.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	if (filetypeDescriptions == nil) {
		filetypeDescriptions = [[NSMutableDictionary alloc] init];
		for (NSString *identifier in NSImage.imageUnfilteredTypes) {
			UTType *t = [UTType typeWithIdentifier:identifier];
			NSString *description = t.localizedDescription;
			for (NSString *ext in t.tags[UTTagClassFilenameExtension]) {
				NSString *s = filetypeDescriptions[ext];
				filetypeDescriptions[ext] = s ? [s stringByAppendingFormat:@" / %@", description] : description;
			}
		}
	}
	if ([tableColumn.identifier isEqualToString:@"enabled"]) return @([filetypes containsObject:fileextensions[row]]);
	if ([tableColumn.identifier isEqualToString:@"description"]) return filetypeDescriptions[fileextensions[row]];
	return fileextensions[row];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	NSString *type = fileextensions[row];
	if ([object boolValue]) {
		[filetypes addObject:type];
		[disabledFiletypes removeObject:type];
	} else {
		[filetypes removeObject:type];
		[disabledFiletypes addObject:type];
	}
	[NSUserDefaults.standardUserDefaults setObject:disabledFiletypes.allObjects forKey:@"ignoredFileTypes"];
}

@end
