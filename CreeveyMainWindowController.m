//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "CreeveyMainWindowController.h"
#import "DYCarbonGoodies.h"
#import "NSMutableArray+DYMovable.h"
#import "DirBrowserDelegate.h"
#import "DYFileWatcher.h"

#import "CreeveyController.h"
#import "KeyBindings.h"
#import "DYCreeveyBrowser.h"
#import "DYImageCache.h"
#import "DYWrappingMatrix.h"
#import <sys/stat.h>
#include <sys/attr.h>
#import "DYExiftags.h"
@import Quartz; // QLPreviewPanel

@implementation NSString (DateModifiedCompare)

/* Using file attributes to sort file paths and then rely on the sort order staying the same
 * is somewhat dangerous because the file might have been modified (changing the modification date)
 * or moved (making the path invalid). We try to mitigate this by watching for changes to the filesystem. */

- (NSComparisonResult)lastPathComponentCompare:(NSString *)other {
	NSString *aName = self.lastPathComponent, *bName = other.lastPathComponent;
	NSComparisonResult result = [aName localizedStandardCompare:bName];
	if (result != NSOrderedSame)
		return result;
	return [self localizedStandardCompare:other];
}

- (NSComparisonResult)dateModifiedCompare:(NSString *)other
{
	struct stat aBuf, bBuf;
	if (stat(self.fileSystemRepresentation, &aBuf) == 0 &&
		stat(other.fileSystemRepresentation, &bBuf) == 0) {
		time_t aTime = aBuf.st_mtimespec.tv_sec;
		time_t bTime = bBuf.st_mtimespec.tv_sec;
		if (aTime != bTime)
			return aTime < bTime ? NSOrderedAscending : NSOrderedDescending;
	}
	// use file name comparison as fallback; filenames are guaranteed to be unique, but mod times are not
	return [self localizedStandardCompare:other];
}

- (NSComparisonResult)fileSizeCompare:(NSString *)other {
	struct stat aBuf, bBuf;
	if (stat(self.fileSystemRepresentation, &aBuf) == 0 &&
		stat(other.fileSystemRepresentation, &bBuf) == 0) {
		off_t aSize = aBuf.st_size;
		off_t bSize = bBuf.st_size;
		if (aSize != bSize)
			return aSize < bSize ? NSOrderedAscending : NSOrderedDescending;
	}
	return [self localizedStandardCompare:other];
}

- (NSComparisonResult)fileTypeCompare:(NSString *)other {
	NSString *aPath = ResolveAliasToPath(self);
	NSString *bPath = ResolveAliasToPath(other);
	NSString *aType = aPath.pathExtension.lowercaseString ?: NSHFSTypeOfFile(aPath);
	NSString *bType = bPath.pathExtension.lowercaseString ?: NSHFSTypeOfFile(bPath);
	if (aType != bType) {
		if (!aType) return NSOrderedAscending;
		if (!bType) return NSOrderedDescending;
		NSComparisonResult result = [aType compare:bType];
		if (result != NSOrderedSame)
			return result;
	}
	return [self localizedStandardCompare:other];
}

//#define LOGSORT

static time_t ExifDateFromFile(NSString *s) {
	s = ResolveAliasToPath(s);
	NSString *x = s.pathExtension.lowercaseString;
	const char *c = s.fileSystemRepresentation;
	time_t t;
#ifdef LOGSORT
	static NSMutableSet *seen;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		seen = [NSMutableSet set];
	});
	BOOL w = [seen containsObject:s];
	[seen addObject:s];
#endif
	if (IsRaw(x) &&
		(t = ExifDateFromRawFile(c)) != -1) {
#ifdef LOGSORT
		if (!w) NSLog(@"raw %@:%@", [NSDate dateWithTimeIntervalSince1970:t], s.lastPathComponent);
#endif
		return t;
	}
	if ((IsJPEG(x) || [NSHFSTypeOfFile(s) isEqualToString:@"JPEG"]) &&
		(t = ExifDatetimeForFile(c, JPEG)) != -1) {
#ifdef LOGSORT
		if (!w) NSLog(@"jpg %@:%@", [NSDate dateWithTimeIntervalSince1970:t], s.lastPathComponent);
#endif
		return t;
	}
	if (IsHeif(x) &&
		(t = ExifDatetimeForFile(c, HEIF)) != -1) {
#ifdef LOGSORT
		if (!w) NSLog(@"heic %@:%@", [NSDate dateWithTimeIntervalSince1970:t], s.lastPathComponent);
#endif
		return t;
	}
	struct stat buf;
	t = stat(c, &buf) ? -1 : buf.st_birthtimespec.tv_sec;
#ifdef LOGSORT
		if (!w) NSLog(@"stat %@:%@", [NSDate dateWithTimeIntervalSince1970:t], s.lastPathComponent);
#endif
	return t;
}

- (NSComparisonResult)exifDateCompare:(NSString *)other {
	time_t aTime, bTime;
	if ((aTime = ExifDateFromFile(self)) != -1 &&
		(bTime = ExifDateFromFile(other)) != -1 &&
		aTime != bTime) {
		return aTime < bTime ? NSOrderedAscending : NSOrderedDescending;
	}
	return [self localizedStandardCompare:other];
}

typedef struct {
	u_int32_t length;
	struct timespec c, a;
} __attribute__((aligned(4), packed)) times_buf_t;

- (NSComparisonResult)dateAddedCompare:(NSString *)other {
	struct attrlist attrlist;
	memset(&attrlist, 0, sizeof(attrlist));
	attrlist.bitmapcount = ATTR_BIT_MAP_COUNT;
	attrlist.commonattr = ATTR_CMN_CRTIME|ATTR_CMN_ADDEDTIME;
	times_buf_t aBuf, bBuf;
	if (getattrlist(self.fileSystemRepresentation, &attrlist, &aBuf, sizeof(aBuf), 0) == 0 &&
		getattrlist(other.fileSystemRepresentation, &attrlist, &bBuf, sizeof(bBuf), 0) == 0) {
		time_t aTime = aBuf.a.tv_sec;
		time_t bTime = bBuf.a.tv_sec;
		if (aTime != bTime)
			return aTime < bTime ? NSOrderedAscending : NSOrderedDescending;
		// fall back to creation time
		aTime = aBuf.c.tv_sec;
		bTime = bBuf.c.tv_sec;
		if (aTime != bTime)
			return aTime < bTime ? NSOrderedAscending : NSOrderedDescending;
	}
	return [self localizedStandardCompare:other];
}

@end


@interface CreeveyMainWindowController () <DYFileWatcherDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate>
@property (nonatomic, readonly) NSSplitView *splitView;
@property BOOL wantsSubfolders;
@property (nonatomic, strong) NSString *recurseRoot;
@end

@implementation CreeveyMainWindowController
{
	NSMutableArray *filenames, *displayedFilenames;
	NSLock *loadImageLock; NSTimeInterval lastThreadTime;
	CreeveyController * __weak appDelegate;
	DirBrowserDelegate * __weak dirBrowserDelegate;
	_Atomic char stopCaching;
	
	NSConditionLock *imageCacheQueueLock;
	NSMutableArray<DYMatrixFileInfo *> *imageCacheQueue, *secondaryImageCacheQueue;
	_Atomic BOOL imageCacheQueueRunning;
	_Atomic NSInteger _maxCellWidth;
	BOOL exifWindowNeedsUpdate;
	
	BOOL currentFilesDeletable;
	BOOL filenamesDone, loadingDone, // loadingDone only meaningful if filenamesDone is true, always check both!
	startSlideshowWhenReady;
	NSMutableSet *filesBeingOpened; // to be selected
	short int sortOrder;
	time_t matrixModTime;
	
	short int currCat;
	
	_Atomic BOOL _background;
	BOOL _wantsSubfolders;
	NSImage *_brokenDoc, *_loadingImage;
	NSMutableSet *_accessedFiles;
	NSLock *_accessedLock, *_internalLock;
	_Atomic(NSTimeInterval) _statusTime;
	DYFileWatcher *_fileWatcher;

	// base (design) font sizes for the controls we scale with the interface text size
	CGFloat _statusBaseSize, _bottomStatusBaseSize;
	BOOL _textBasesCaptured;

	NSPathControl *_pathControl;         // Finder-style path bar at the bottom
	NSLayoutConstraint *_pathBarHeight;  // toggled between a row height and 0 to show/hide
	CGFloat _savedBrowserHeight;         // last non-zero directory-browser height, for restore
	BOOL _togglingBrowser;               // set while show/hide runs, to protect _savedBrowserHeight
	BOOL _directoryBrowserHidden;        // YES when only the control strip shows (browser hidden)
	NSLayoutConstraint *_browserMinHeight, *_browserGap, *_browserZeroHeight;
	BOOL _quickLookActive;               // YES while the Quick Look panel has control
	NSSearchField *_searchField;         // filters the displayed thumbnails by filename
	NSString *_searchQuery;              // current filter text ("" / nil = no filter)
	NSString *_lastLoadedPath;           // folder the filter applies to; changing it clears the filter
	BOOL _searchRegex;                   // treat the query as a regular expression
	NSRegularExpression *_searchRegexCompiled; // compiled query when in regex mode (nil if invalid)
	NSWindow *_searchTipWindow;          // instant (no-delay) hover tip for the filter field
	NSTextField *_searchTipField;
	NSString *_archiveTempDir;           // temp dir a .zip is extracted into while browsing it
	NSString *_archivePath;              // the original .zip path (remembered in Open Recent)
	NSString *_archiveDisplayPath;       // clean logical path (zips shown as folders), for the path bar
	NSString *_archiveDisplayName;       // the .zip's filename, shown as the window title
	NSProgressIndicator *_archiveSpinner; // shown over the grid while an archive is extracting
}
@synthesize dirBrowser, slidesBtn, imgMatrix, statusFld, bottomStatusFld;

- (instancetype)initWithWindowNibName:(NSString *)windowNibName {
	if (self = [super initWithWindowNibName:windowNibName]) {
		filenames = [[NSMutableArray alloc] init];
		displayedFilenames = [[NSMutableArray alloc] init];
		loadImageLock = [[NSLock alloc] init];
		filesBeingOpened = [[NSMutableSet alloc] init];
		sortOrder = 1; // by name
		imageCacheQueueLock = [[NSConditionLock alloc] initWithCondition:0];
		imageCacheQueue = [[NSMutableArray alloc] init];
		secondaryImageCacheQueue = [[NSMutableArray alloc] init];
		imageCacheQueueRunning = YES;
		appDelegate = (CreeveyController *)NSApp.delegate;
		_accessedFiles = [[NSMutableSet alloc] init];
		_accessedLock = [[NSLock alloc] init];
		_internalLock = [[NSLock alloc] init];
		_fileWatcher = [[DYFileWatcher alloc] initWithDelegate:self];
	}
    return self;
}

- (void)windowDidLoad {
	[self.window setFrameUsingName:@"MainWindowLoc"];
	// otherwise it uses the frame in the nib
	
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	NSSplitView *splitView = self.splitView;
	float height = [u floatForKey:@"MainWindowSplitViewTopHeight"];
	if (height > 0.0) [splitView setPosition:height ofDividerAtIndex:0];
	else dispatch_async(dispatch_get_main_queue(), ^{
		// apparently the splitview can't be collapsed until after windowDidLoad returns
		[splitView setPosition:0 ofDividerAtIndex:0];
	});
	splitView.delegate = self; // must set delegate after restoring position so the didResize notification doesn't save the height from the nib

	[imgMatrix setFrameSize:imgMatrix.superview.frame.size];
	imgMatrix.maxCellWidth = _maxCellWidth = [u integerForKey:@"DYWrappingMatrixMaxCellWidth"];
	imgMatrix.cellWidth = [u floatForKey:@"thumbCellWidth"];
	self.window.restorationClass = [CreeveyController class];
	
	dirBrowserDelegate = dirBrowser.delegate;
	dirBrowserDelegate.revealedDirectories = appDelegate.revealedDirectories;

	_brokenDoc = [NSImage imageNamed:@"brokendoc.tif"];
	_loadingImage = [NSImage imageNamed:@"loading.png"];
	imgMatrix.loadingImage = _loadingImage;
	[NSThread detachNewThreadSelector:@selector(thumbLoader:) toTarget:self withObject:nil];
	[NSUserDefaultsController.sharedUserDefaultsController addObserver:self forKeyPath:@"values.DYWrappingMatrixMaxCellWidth" options:0 context:NULL];
	[self applyInterfaceTextSize];
	[self setupPathBar];
	[self setupSearchField];
}

#pragma mark search field
// A filename filter in the control strip: statusFld | search | Unsupported | Subfolders | Slideshow.
// Regex mode lives in the magnifier's menu (the strip has no room for another checkbox).
- (void)setupSearchField {
	NSView *pane = statusFld.superview;
	_searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
	_searchField.translatesAutoresizingMaskIntoConstraints = NO;
	_searchField.controlSize = NSControlSizeRegular;
	_searchField.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
	((NSSearchFieldCell *)_searchField.cell).placeholderString = NSLocalizedString(@"Filter", @"");
	// instant (no system delay) hover tip explaining the regex option; see mouseEntered:/showSearchTip
	[_searchField addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
		options:NSTrackingMouseEnteredAndExited|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect
		owner:self userInfo:nil]];
	_searchField.sendsWholeSearchString = NO;
	_searchField.sendsSearchStringImmediately = NO; // debounce a touch while typing
	_searchField.target = self;
	_searchField.action = @selector(searchFieldChanged:);
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
	NSMenuItem *rx = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Regular Expression", @"")
												action:@selector(toggleSearchRegex:) keyEquivalent:@""];
	rx.target = self;
	rx.tag = 1;
	[menu addItem:rx];
	_searchField.searchMenuTemplate = menu; // magnifier dropdown → Regex toggle
	[statusFld setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal]; // let the count text yield to the field
	[pane addSubview:_searchField];
	// splice the field into the row between the status text and the Unsupported checkbox
	for (NSLayoutConstraint *c in pane.constraints.copy)
		if (c.firstItem == self.unsupportedButton && c.firstAttribute == NSLayoutAttributeLeading &&
			c.secondItem == statusFld && c.secondAttribute == NSLayoutAttributeTrailing) {
			c.active = NO; break;
		}
	NSLayoutConstraint *preferredWidth = [_searchField.widthAnchor constraintEqualToConstant:160];
	preferredWidth.priority = 250; // grow to ~160 if there's room, shrink otherwise
	[NSLayoutConstraint activateConstraints:@[
		[_searchField.leadingAnchor constraintEqualToAnchor:statusFld.trailingAnchor constant:8],
		[self.unsupportedButton.leadingAnchor constraintEqualToAnchor:_searchField.trailingAnchor constant:8],
		[_searchField.centerYAnchor constraintEqualToAnchor:self.unsupportedButton.centerYAnchor],
		[_searchField.widthAnchor constraintGreaterThanOrEqualToConstant:70],
		preferredWidth,
	]];
}

// Focus the filter field, selecting any existing text so it can be retyped or edited.
- (void)focusSearchField {
	[self.window makeFirstResponder:_searchField];
	[_searchField selectText:nil];
}

// Instant hover tip for the filter field (the system tool tip's delay hides the regex option).
- (void)mouseEntered:(NSEvent *)e { [self showSearchTip]; }
- (void)mouseExited:(NSEvent *)e { [_searchTipWindow orderOut:nil]; }
- (void)windowDidResignKey:(NSNotification *)n { [_searchTipWindow orderOut:nil]; } // don't linger when unfocused

- (BOOL)mouseIsOverSearchField {
	NSPoint p = [_searchField convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
	return NSMouseInRect(p, _searchField.bounds, _searchField.isFlipped);
}

- (void)showSearchTip {
	if (![self mouseIsOverSearchField]) { [_searchTipWindow orderOut:nil]; return; } // only when truly hovering the field
	if (!_searchTipWindow) {
		NSView *bg = [[NSView alloc] initWithFrame:NSZeroRect];
		bg.wantsLayer = YES;
		bg.layer.cornerRadius = 4;
		bg.layer.borderWidth = 0.5;
		_searchTipField = [NSTextField labelWithString:@""];
		_searchTipField.font = [NSFont toolTipsFontOfSize:0];
		[bg addSubview:_searchTipField];
		_searchTipWindow = [[NSWindow alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
		_searchTipWindow.opaque = NO;
		_searchTipWindow.backgroundColor = NSColor.clearColor;
		_searchTipWindow.hasShadow = YES;
		_searchTipWindow.level = NSPopUpMenuWindowLevel;
		_searchTipWindow.ignoresMouseEvents = YES;
		_searchTipWindow.contentView = bg;
	}
	_searchTipWindow.appearance = self.window.effectiveAppearance;
	NSView *bg = _searchTipWindow.contentView;
	bg.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
	bg.layer.borderColor = [NSColor.gridColor colorWithAlphaComponent:0.8].CGColor;
	_searchTipField.textColor = NSColor.controlTextColor;
	_searchTipField.stringValue = NSLocalizedString(@"Type to filter by name; click the magnifier for a regular-expression option.", @"");
	[_searchTipField sizeToFit];
	const CGFloat padX = 6, padY = 3;
	NSSize fs = _searchTipField.frame.size;
	_searchTipField.frameOrigin = NSMakePoint(padX, padY);
	NSRect wf = NSMakeRect(0, 0, ceil(fs.width) + padX*2, ceil(fs.height) + padY*2);
	NSRect field = [self.window convertRectToScreen:[_searchField convertRect:_searchField.bounds toView:nil]];
	wf.origin.x = round(NSMinX(field));
	wf.origin.y = round(NSMinY(field) - wf.size.height - 3); // just below the field
	NSRect vis = (self.window.screen ?: NSScreen.mainScreen).visibleFrame;
	if (NSMaxX(wf) > NSMaxX(vis)) wf.origin.x = NSMaxX(vis) - wf.size.width;
	if (wf.origin.x < NSMinX(vis)) wf.origin.x = NSMinX(vis);
	if (wf.origin.y < NSMinY(vis)) wf.origin.y = round(NSMaxY(field) + 3); // flip above if no room below
	[_searchTipWindow setFrame:wf display:YES];
	[_searchTipWindow orderFront:nil];
}

- (IBAction)searchFieldChanged:(id)sender {
	[_searchTipWindow orderOut:nil]; // dismiss the hint once the user starts typing
	NSString *q = _searchField.stringValue;
	_searchQuery = q.length ? q : nil;
	[self recompileSearch];
	[self refilter];
}

- (IBAction)toggleSearchRegex:(id)sender {
	_searchRegex = !_searchRegex;
	[self recompileSearch];
	[self refilter];
}

// checkmark the "Regular Expression" item when the magnifier menu opens
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if (menuItem.action == @selector(toggleSearchRegex:)) {
		menuItem.state = _searchRegex ? NSControlStateValueOn : NSControlStateValueOff;
		return YES;
	}
	return YES;
}

- (void)recompileSearch {
	_searchRegexCompiled = nil;
	if (_searchRegex && _searchQuery.length)
		_searchRegexCompiled = [NSRegularExpression regularExpressionWithPattern:_searchQuery
																		 options:NSRegularExpressionCaseInsensitive error:NULL];
}

// Re-filter the already-loaded files without re-reading the disk (same path loadImages: takes for sort/category).
- (void)refilter {
	[NSThread detachNewThreadSelector:@selector(loadImages:) toTarget:self withObject:nil];
}

// YES if a filename passes the current filter (no filter → always YES).
- (BOOL)filenamePassesSearch:(NSString *)path {
	if (!_searchQuery.length) return YES;
	NSString *name = path.lastPathComponent;
	if (_searchRegex) {
		if (!_searchRegexCompiled) return YES; // invalid pattern: don't hide anything
		return [_searchRegexCompiled numberOfMatchesInString:name options:0 range:NSMakeRange(0, name.length)] > 0;
	}
	return [name rangeOfString:_searchQuery options:NSCaseInsensitiveSearch].location != NSNotFound;
}

#pragma mark path bar
// Add a Finder-style NSPathControl across the bottom of the window and re-pin the
// split view's bottom to it (it was pinned to the window's bottom).
- (void)setupPathBar {
	NSScrollView *scroll = imgMatrix.enclosingScrollView; // the thumbnail grid's scroll view
	NSView *pane = scroll.superview;                       // the split view's bottom pane
	NSView *status = bottomStatusFld;                      // the file-info + slider row
	_pathControl = [[NSPathControl alloc] initWithFrame:NSZeroRect];
	_pathControl.translatesAutoresizingMaskIntoConstraints = NO;
	_pathControl.pathStyle = NSPathStyleStandard;
	_pathControl.focusRingType = NSFocusRingTypeNone;
	// a long path (e.g. a nested archive) must never widen the window or block shrinking it;
	// let the control be compressed so it truncates/collapses segments to fit, like Finder
	[_pathControl setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow-1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	[_pathControl setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	_pathControl.target = self;
	_pathControl.action = @selector(pathBarClicked:);
	[pane addSubview:_pathControl positioned:NSWindowBelow relativeTo:status];
	// the status row's top is pinned to the grid's bottom; slot the path bar between them
	for (NSLayoutConstraint *c in pane.constraints.copy) {
		BOOL statusToGrid =
			(c.firstItem == status && c.firstAttribute == NSLayoutAttributeTop && c.secondItem == scroll) ||
			(c.firstItem == scroll && c.firstAttribute == NSLayoutAttributeBottom && c.secondItem == status);
		if (statusToGrid) { c.active = NO; break; }
	}
	_pathBarHeight = [_pathControl.heightAnchor constraintEqualToConstant:0];
	[NSLayoutConstraint activateConstraints:@[
		[_pathControl.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor],
		[_pathControl.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor],
		[_pathControl.topAnchor constraintEqualToAnchor:scroll.bottomAnchor],
		[status.topAnchor constraintEqualToAnchor:_pathControl.bottomAnchor constant:1],
		_pathBarHeight,
	]];
	[self setPathBarVisible:[NSUserDefaults.standardUserDefaults boolForKey:@"showPathBar"]];
}

- (void)updatePathBar {
	if (_pathControl.hidden) return;
	// for a mounted archive show the clean logical path (each .zip shown as a folder),
	// never the raw extraction temp dir
	NSString *p = _archiveTempDir ? _archiveDisplayPath : self.path;
	_pathControl.URL = p.length ? [NSURL fileURLWithPath:p] : nil;
}

- (void)pathBarClicked:(NSPathControl *)sender {
	NSURL *u = sender.clickedPathItem.URL;
	if (!u) return;
	if (NSApp.currentEvent.modifierFlags & NSEventModifierFlagShift)
		[self showSubfolderMenuForURL:u inControl:sender]; // Finder-style: list that folder's sub-folders
	else
		[self setPath:u.path];
}

- (void)showSubfolderMenuForURL:(NSURL *)dir inControl:(NSPathControl *)control {
	NSFileManager *fm = NSFileManager.defaultManager;
	NSArray<NSURL *> *contents = [fm contentsOfDirectoryAtURL:dir
								  includingPropertiesForKeys:@[NSURLIsDirectoryKey]
													 options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
	NSMutableArray<NSURL *> *subdirs = [NSMutableArray array];
	for (NSURL *u in contents) {
		NSNumber *isDir = nil;
		[u getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:NULL];
		if (isDir.boolValue) [subdirs addObject:u];
	}
	[subdirs sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b){
		return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
	}];
	NSMenu *menu = [[NSMenu alloc] init];
	for (NSURL *u in subdirs) {
		NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:u.lastPathComponent
													action:@selector(goToSubfolder:) keyEquivalent:@""];
		mi.target = self;
		mi.representedObject = u.path;
		NSImage *icon = [NSWorkspace.sharedWorkspace iconForFile:u.path];
		icon.size = NSMakeSize(16, 16);
		mi.image = icon;
		[menu addItem:mi];
	}
	if (menu.numberOfItems == 0) {
		NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"No Folders", @"") action:NULL keyEquivalent:@""];
		none.enabled = NO;
		[menu addItem:none];
	}
	NSEvent *e = NSApp.currentEvent;
	NSPoint p = e ? [control convertPoint:e.locationInWindow fromView:nil] : NSMakePoint(0, control.bounds.size.height);
	[menu popUpMenuPositioningItem:nil atLocation:p inView:control];
}

- (void)goToSubfolder:(NSMenuItem *)sender {
	[self setPath:sender.representedObject];
}

- (BOOL)pathBarVisible { return _pathBarHeight.constant > 0; }

- (void)setPathBarVisible:(BOOL)b {
	_pathBarHeight.constant = b ? 24 : 0;
	_pathControl.hidden = !b;
	[self updatePathBar];
}

- (void)dealloc {
	[NSUserDefaultsController.sharedUserDefaultsController removeObserver:self forKeyPath:@"values.DYWrappingMatrixMaxCellWidth"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)c context:(void *)context
{
	if ([keyPath isEqualToString:@"values.DYWrappingMatrixMaxCellWidth"]) {
		_maxCellWidth = [NSUserDefaults.standardUserDefaults integerForKey:@"DYWrappingMatrixMaxCellWidth"];
	} else if ([keyPath isEqualToString:@"currentPreviewItemIndex"]) {
		// Quick Look changed its current item (e.g. its own left/right nav) — follow it in the grid
		NSInteger idx = ((QLPreviewPanel *)object).currentPreviewItemIndex;
		if (idx >= 0 && idx < (NSInteger)displayedFilenames.count && imgMatrix.selectedIndexes.firstIndex != (NSUInteger)idx)
			[self selectIndex:idx];
	}
}

- (void)window:(NSWindow *)window willEncodeRestorableState:(NSCoder *)state
{
	BOOL collapsed = statusFld.superview.hidden;
	NSDictionary *data = @{@"path":dirBrowserDelegate.unresolvedPath, @"split1":@(collapsed ? 0.0 : statusFld.superview.frame.size.height)};
	[state encodeObject:data forKey:@"creeveyWindowState"];
}

- (void)window:(NSWindow *)window didDecodeRestorableState:(NSCoder *)state
{
	// as of macOS 12, apps must support secure restorable state (apparently malicious attacks could happen if there was bad data masquerading as your saved state)
	// the fix is apparently to give a list of secure classes when you ask to decode the data. See the AppKit release notes for macOS 12.
	NSDictionary *data = [state decodeObjectOfClasses:[NSSet setWithArray:@[[NSDictionary class],[NSString class],[NSNumber class]]] forKey:@"creeveyWindowState"];
	if (![data isKindOfClass:[NSDictionary class]]) data = @{};
	NSString *path = data[@"path"];
	if (![path isKindOfClass:[NSString class]]) path = nil;
	if (path == nil || ![self setPath:path])
		if (![self setPath:[NSUserDefaults.standardUserDefaults stringForKey:@"picturesFolderPath"]])
			[self setPath:NSHomeDirectory()];
	NSNumber *heightObj = data[@"split1"];
	if ([heightObj isKindOfClass:[NSNumber class]]) {
		float height = heightObj.floatValue;
		[self.splitView setPosition:height ofDividerAtIndex:0];
	}
}

- (NSSplitView *)splitView
{
	return self.window.contentView.subviews[0];
}

- (void)windowWillClose:(NSNotification *)notification {
	[self cleanupArchiveTemp]; // don't leave an extracted archive behind
	[self removeAllPathsFromAccessedFilesArray];
	imageCacheQueueRunning = NO;
	[imageCacheQueueLock lock];
	[imageCacheQueueLock unlockWithCondition:1];
}


#pragma mark sorting stuff
- (DYWrappingMatrix *)imageMatrix { return imgMatrix; }
- (short int)sortOrder { return sortOrder; }
- (void)setSortOrder:(short int)n {
	sortOrder = n;
}
- (void)changeSortOrder:(short int)n {
	sortOrder = n;
	[NSThread detachNewThreadSelector:@selector(loadImages:)
							 toTarget:self
						   withObject:nil];
}

- (NSString *)path { return [dirBrowserDelegate path]; }
- (NSURL *)URL { return [NSURL fileURLWithPath:[dirBrowserDelegate path] isDirectory:YES]; }

// returns NO if doesn't exist, useful for applicationDidFinishLaunching
- (BOOL)setPath:(NSString *)s {
	NSFileManager *fm = NSFileManager.defaultManager;
	BOOL isDir;
	NSString *resolvedPath = ResolveAliasToPath(s);
	if (![fm fileExistsAtPath:resolvedPath isDirectory:&isDir])
		return NO;
	if (!isDir)
		s = s.stringByDeletingLastPathComponent;
	if (_archiveTempDir && ![resolvedPath hasPrefix:_archiveTempDir])
		[self cleanupArchiveTemp]; // navigated out of a mounted archive — discard its temp files
	[dirBrowserDelegate setPath:s];
	[dirBrowser sendAction];
	[self.window invalidateRestorableState];
	return YES;
}

#pragma mark archive (.zip) browsing
- (BOOL)isArchivePath:(NSString *)path {
	NSString *ext = path.pathExtension.lowercaseString;
	return [ext isEqualToString:@"zip"] || [ext isEqualToString:@"cbz"];
}

// Extract a .zip/.cbz into a temp folder in the background and browse it immediately; the file
// watcher streams entries into the grid as they extract, and a spinner shows work is ongoing.
- (void)openArchive:(NSString *)zipPath {
	NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
		[@"PhoenixSlidesArchive-" stringByAppendingString:NSProcessInfo.processInfo.globallyUniqueString]];
	if (![NSFileManager.defaultManager createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:NULL]) {
		NSBeep(); return;
	}
	tmp = ResolveAliasToPath(tmp); // NSTemporaryDirectory lives under /var → /private/var; resolve so
	                               // the setPath: cleanup guard below compares like-for-like
	// Don't delete the previously-mounted archive yet: for a nested archive, zipPath lives *inside*
	// it, so it must survive until ditto has finished reading it (below). Deleting it up front is
	// what made "a .zip inside a .zip" extract nothing.
	NSString *previousTemp = _archiveTempDir;
	NSString *previousDisplay = _archiveDisplayPath;
	[self showArchiveSpinner:NO];
	// Clean logical path for the UI: a nested archive extends the outer archive's display path
	// (treating each .zip as a folder) so we never surface a raw extraction temp path.
	if (previousTemp && [zipPath hasPrefix:[previousTemp stringByAppendingString:@"/"]])
		_archiveDisplayPath = [previousDisplay stringByAppendingString:[zipPath substringFromIndex:previousTemp.length]];
	else
		_archiveDisplayPath = zipPath; // top-level archive: its real .zip path
	_archiveTempDir = tmp;
	_archivePath = zipPath;
	_archiveDisplayName = zipPath.lastPathComponent;
	[self showArchiveSpinner:YES];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSTask *task = [[NSTask alloc] init];
		task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
		task.arguments = @[@"-x", @"-k", zipPath, tmp]; // ditto -x -k = extract PKZip
		[task launchAndReturnError:NULL];
		[task waitUntilExit];
		if (previousTemp) // safe now: we've finished reading zipPath (which may live inside it)
			[NSFileManager.defaultManager removeItemAtPath:previousTemp error:NULL];
		dispatch_async(dispatch_get_main_queue(), ^{
			if ([self->_archiveTempDir isEqualToString:tmp]) { // still viewing this archive
				[self showArchiveSpinner:NO];
				[self displayDir:nil]; // final re-scan so nothing extracted early is missed
			}
		});
	});
	// point the directory browser at the .zip's own folder so the column browser and path bar
	// agree (the grid itself loads from the temp dir below). Skip when the .zip lives inside an
	// extraction temp dir — i.e. a nested archive — since that folder isn't a real location.
	NSString *zipParent = zipPath.stringByDeletingLastPathComponent;
	if ([zipParent rangeOfString:@"/PhoenixSlidesArchive-"].location == NSNotFound)
		[dirBrowserDelegate setPath:zipParent]; // updates the browser columns without reloading the grid
	// browse the temp dir directly via displayDir (the directory browser can't reliably navigate
	// into a deep hidden temp path); the file watcher streams entries in as they extract
	[self displayDir:nil];
}

// Remove every PhoenixSlidesArchive-* temp dir. Safe to call only when no archive is mounted
// (i.e. at launch or termination); it's the safety net for leftovers from a crash or force-quit.
+ (void)sweepLeftoverArchiveTemps {
	NSString *tmpRoot = NSTemporaryDirectory();
	NSFileManager *fm = NSFileManager.defaultManager;
	for (NSString *name in [fm contentsOfDirectoryAtPath:tmpRoot error:NULL])
		if ([name hasPrefix:@"PhoenixSlidesArchive-"])
			[fm removeItemAtPath:[tmpRoot stringByAppendingPathComponent:name] error:NULL];
}

- (void)cleanupArchiveTemp {
	[self showArchiveSpinner:NO];
	if (_archiveTempDir) {
		[NSFileManager.defaultManager removeItemAtPath:_archiveTempDir error:NULL];
		_archiveTempDir = nil;
		_archivePath = nil;
		_archiveDisplayPath = nil;
		_archiveDisplayName = nil;
	}
}

- (void)showArchiveSpinner:(BOOL)show {
	if (show && !_archiveSpinner) {
		_archiveSpinner = [[NSProgressIndicator alloc] init];
		_archiveSpinner.style = NSProgressIndicatorStyleSpinning;
		_archiveSpinner.displayedWhenStopped = NO;
		_archiveSpinner.translatesAutoresizingMaskIntoConstraints = NO;
		NSView *host = imgMatrix.enclosingScrollView;
		[host.superview addSubview:_archiveSpinner positioned:NSWindowAbove relativeTo:host];
		[NSLayoutConstraint activateConstraints:@[
			[_archiveSpinner.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
			[_archiveSpinner.centerYAnchor constraintEqualToAnchor:host.centerYAnchor],
		]];
	}
	if (show) [_archiveSpinner startAnimation:nil];
	else [_archiveSpinner stopAnimation:nil];
}

- (void)setDefaultPath {
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	NSString *s = [u integerForKey:@"startupOption"] == 0
		? [u stringForKey:@"lastFolderPath"]
		: [u stringForKey:@"picturesFolderPath"];
	if (![self setPath:s])
		if (![self setPath:CREEVEY_DEFAULT_PATH])
				[self setPath:NSHomeDirectory()];
	[self.window makeFirstResponder:dirBrowser]; //another stupid workaround, for hiliting
	
}

- (BOOL)pathIsCurrentDirectory:(NSString *)filename {
	NSString *browserPath = [dirBrowserDelegate path];
	if (self.wantsSubfolders) return [filename hasPrefix:[browserPath stringByAppendingString:@"/"]];
	return [filename.stringByDeletingLastPathComponent isEqualToString:browserPath];
}

- (BOOL)pathIsVisibleThreaded:(NSString *)filename {
	NSString *browserPath = dirBrowserDelegate.currentResolvedPath;
	if (self.wantsSubfolders) return [filename hasPrefix:[browserPath stringByAppendingString:@"/"]];
	return [filename.stringByDeletingLastPathComponent isEqualToString:browserPath];
}

- (void)updateDefaults {
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	if ([u integerForKey:@"startupOption"] == 0)
		[u setObject:dirBrowserDelegate.unresolvedPath forKey:@"lastFolderPath"];
	[u setFloat:imgMatrix.cellWidth forKey:@"thumbCellWidth"];
	float height = statusFld.superview.hidden ? 0 : statusFld.superview.frame.size.height;
	[u setFloat:height forKey:@"MainWindowSplitViewTopHeight"];
	[self.window saveFrameUsingName:@"MainWindowLoc"];
}


#pragma mark Open Recent state
// Snapshot the window's full navigable state (nil if no folder is loaded yet).
- (NSDictionary *)currentStateDictionary {
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	if (_archiveTempDir) {
		// a nested archive's source .zip lives in a temp dir that won't survive — don't record it
		// (it could never be reopened, and its path is ugly)
		if ([_archivePath rangeOfString:@"/PhoenixSlidesArchive-"].location != NSNotFound) return nil;
		// a mounted archive is remembered by its .zip path and re-extracted when reopened
		d[@"isArchive"] = @YES;
		d[@"path"] = ResolveAliasToPath(_archivePath);
		d[@"displayPath"] = _archivePath.stringByAbbreviatingWithTildeInPath;
		d[@"focusedFile"] = @""; // temp-dir paths don't survive a remount
	} else {
		NSString *unresolved = dirBrowserDelegate.unresolvedPath;
		if (!unresolved.length) return nil;
		NSString *focused = imgMatrix.firstSelectedFilename;
		d[@"path"] = ResolveAliasToPath(unresolved);            // resolved: identity / existence
		d[@"displayPath"] = unresolved.stringByAbbreviatingWithTildeInPath; // ~-abbreviated: menu title
		d[@"focusedFile"] = focused ?: @"";
	}
	d[@"sortOrder"] = @(sortOrder);
	d[@"wantsSubfolders"] = @(self.wantsSubfolders);
	if (self.recurseRoot) d[@"recurseRoot"] = self.recurseRoot;
	d[@"showUnsupportedFiles"] = @(_showUnsupportedFiles);
	d[@"showFilenames"] = @(imgMatrix.showFilenames);
	d[@"autoRotate"] = @(imgMatrix.autoRotate);
	d[@"directoryBrowserVisible"] = @(self.directoryBrowserVisible);
	d[@"browserHeight"] = @(_savedBrowserHeight);
	d[@"pathBarVisible"] = @(self.pathBarVisible);
	d[@"cellWidth"] = @(imgMatrix.cellWidth);
	return d;
}

// Apply a saved state: set list-affecting bits first (no reload), then navigate once and
// let the loader select the remembered file, then apply the view-only toggles.
- (void)restoreState:(NSDictionary *)e {
	if (e[@"sortOrder"]) self.sortOrder = [e[@"sortOrder"] shortValue];
	self.recurseRoot = e[@"recurseRoot"]; // may be nil
	[self setWantsSubfolders:[e[@"wantsSubfolders"] boolValue]];
	self.subfoldersButton.state = self.wantsSubfolders ? NSControlStateValueOn : NSControlStateValueOff;
	_showUnsupportedFiles = [e[@"showUnsupportedFiles"] boolValue]; // direct: avoid a redundant reload
	self.unsupportedButton.state = _showUnsupportedFiles ? NSControlStateValueOn : NSControlStateValueOff;
	// view-only toggles (no directory reload needed)
	if ([e[@"browserHeight"] doubleValue] > 0) _savedBrowserHeight = [e[@"browserHeight"] doubleValue];
	imgMatrix.showFilenames = [e[@"showFilenames"] boolValue];
	imgMatrix.autoRotate = [e[@"autoRotate"] boolValue];
	if ([e[@"cellWidth"] floatValue] > 0) imgMatrix.cellWidth = [e[@"cellWidth"] floatValue];
	self.pathBarVisible = [e[@"pathBarVisible"] boolValue];
	self.directoryBrowserVisible = [e[@"directoryBrowserVisible"] boolValue];
	if ([e[@"isArchive"] boolValue]) { // re-extract and browse the .zip
		[self openArchive:e[@"path"]];
		return;
	}
	// navigate + select the remembered file after the async load (reuses openFiles:)
	NSString *focused = e[@"focusedFile"];
	if ([focused isKindOfClass:NSString.class] && focused.length)
		[self openFiles:@[focused] withSlideshow:NO];
	else
		[self setPath:e[@"path"]];
}

- (BOOL)currentFilesDeletable { return currentFilesDeletable; }
- (BOOL)filenamesDone { return filenamesDone; }
- (NSArray *)displayedFilenames { return displayedFilenames; }
- (NSUInteger)indexOfFilename:(NSString *)s {
	return [displayedFilenames indexOfObject:s inSortedRange:NSMakeRange(0, displayedFilenames.count) options:0 usingComparator:self.comparator];
}
typedef NSComparisonResult (*compIMP)(id, SEL, id);
NSComparator ComparatorForSortOrder(short sortOrder) {
	BOOL descending = sortOrder < 0;
	if (descending) sortOrder = -sortOrder;
	SEL sel; switch (sortOrder) {
		case 1: sel = @selector(lastPathComponentCompare:); break;
		case 2: sel = @selector(dateModifiedCompare:); break;
		case 3: sel = @selector(exifDateCompare:); break;
		case 4: sel = @selector(dateAddedCompare:); break;
		case 5: sel = @selector(fileTypeCompare:); break;
		case 6: sel = @selector(fileSizeCompare:); break;
		case 7: sel = @selector(localizedStandardCompare:); break;
		default: sel = @selector(compare:);
	}
	compIMP f = (compIMP)[NSString instanceMethodForSelector:sel];
	if (descending)
		return ^NSComparisonResult(id a, id b) { return f(b, sel, a); };
	return ^NSComparisonResult(id a, id b) { return f(a, sel, b); };
}
- (NSComparator)comparator {
	return ComparatorForSortOrder(sortOrder);
}

- (NSArray *)currentSelection {
	return imgMatrix.selectedFilenames;
}
- (NSIndexSet *)selectedIndexes {
	return imgMatrix.selectedIndexes;
}
- (void)selectIndex:(NSUInteger)i {
	[imgMatrix selectIndex:i];
}

#pragma mark Quick Look panel

- (BOOL)acceptsPreviewPanelControl:(QLPreviewPanel *)panel {
	return filenamesDone && displayedFilenames.count > 0;
}

- (void)beginPreviewPanelControl:(QLPreviewPanel *)panel {
	panel.delegate = self;
	panel.dataSource = self;
	_quickLookActive = YES; // suppress the browser's per-selection status/EXIF work; it's hidden behind the panel
	imgMatrix.selectionUpdatesSuppressed = YES; // and don't scroll/redraw the hidden grid (avoids background thumbnailing that competes with quicklookd)
	NSUInteger sel = imgMatrix.selectedIndexes.firstIndex;
	panel.currentPreviewItemIndex = (sel == NSNotFound) ? 0 : sel;
	// Quick Look navigates left/right itself (those keys never reach handleEvent:), so watch
	// its index and mirror it in the grid to keep the highlighted thumbnail in lock-step
	[panel addObserver:self forKeyPath:@"currentPreviewItemIndex" options:0 context:NULL];
}

- (void)endPreviewPanelControl:(QLPreviewPanel *)panel {
	[panel removeObserver:self forKeyPath:@"currentPreviewItemIndex"];
	panel.delegate = nil;
	panel.dataSource = nil;
	_quickLookActive = NO;
	imgMatrix.selectionUpdatesSuppressed = NO;
	[imgMatrix setNeedsDisplay:YES]; // clear any stale highlight left while suppressed
	NSUInteger i = imgMatrix.selectedIndexes.firstIndex;
	if (i != NSNotFound)
		[imgMatrix selectIndex:i]; // scroll the landed image into view and refresh status/EXIF
	else
		[self wrappingMatrixSelectionDidChange:imgMatrix.selectedIndexes];
}

- (NSInteger)numberOfPreviewItemsInPreviewPanel:(QLPreviewPanel *)panel {
	return displayedFilenames.count;
}

- (id <QLPreviewItem>)previewPanel:(QLPreviewPanel *)panel previewItemAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)displayedFilenames.count) return nil;
	return [NSURL fileURLWithPath:ResolveAliasToPath(displayedFilenames[index])];
}

// Forward the arrow keys to the grid so it tracks the panel in lock-step;
// closing Quick Look then leaves the browsed image selected (Finder-style).
- (BOOL)previewPanel:(QLPreviewPanel *)panel handleEvent:(NSEvent *)event {
	if (event.type != NSEventTypeKeyDown || event.characters.length == 0) return NO;
	unichar c = [event.characters characterAtIndex:0];
	// arrow keys: move the grid selection and keep the panel in sync
	if (c == NSLeftArrowFunctionKey || c == NSRightArrowFunctionKey ||
		c == NSUpArrowFunctionKey || c == NSDownArrowFunctionKey) {
		[imgMatrix keyDown:event];
		NSUInteger sel = imgMatrix.selectedIndexes.firstIndex;
		if (sel != NSNotFound) panel.currentPreviewItemIndex = sel;
		return YES;
	}
	NSEventModifierFlags mods = event.modifierFlags &
		(NSEventModifierFlagCommand|NSEventModifierFlagControl|NSEventModifierFlagOption);
	if (mods == 0) {
		// unmodified single-key browser actions (trash / delete / rename), per the
		// config; leave Space, Esc, Return, etc. for Quick Look itself
		if ([appDelegate.keyBindings browserActionForEvent:event] == BrowserActionNone)
			return NO;
		[self keyDown:event];
		[self reloadQuickLook:panel];
		return YES;
	}
	// keep window/app-management keys with Quick Look and the system, so the browser
	// window isn't closed/minimized/hidden out from under the preview
	if ((mods & NSEventModifierFlagCommand) && event.charactersIgnoringModifiers.length == 1
		&& [@"wmhqnt" containsString:event.charactersIgnoringModifiers.lowercaseString])
		return NO;
	// forward every other shortcut to the app's menu (Get Info, Reveal, Rotate, Set
	// Desktop, Move/Copy To, Sort, …), then refresh in case the file list changed
	if ([NSApp.mainMenu performKeyEquivalent:event]) {
		[self reloadQuickLook:panel];
		return YES;
	}
	return NO;
}

// after a Quick Look action that may have trashed/renamed/reordered files, refresh
// the panel and follow the grid selection (or close the panel if nothing remains)
- (void)reloadQuickLook:(QLPreviewPanel *)panel {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (!panel.isVisible) return;
		if (displayedFilenames.count == 0) { [panel orderOut:nil]; return; }
		[panel reloadData];
		NSUInteger sel = imgMatrix.selectedIndexes.firstIndex;
		panel.currentPreviewItemIndex = (sel == NSNotFound) ? 0 : MIN(sel, displayedFilenames.count - 1);
	});
}

- (void)openFiles:(NSArray *)a withSlideshow:(BOOL)doSlides{
	if (a.count == 1 && [self isArchivePath:a[0]]) { // dragged/opened a .zip — browse its contents
		[self openArchive:a[0]];
		return;
	}
	startSlideshowWhenReady = doSlides;
	[filesBeingOpened addObjectsFromArray:a];
	BOOL isDir;
	NSString *aPath = a[0];
	if ([NSFileManager.defaultManager fileExistsAtPath:aPath isDirectory:&isDir] && !isDir)
		aPath = aPath.stringByDeletingLastPathComponent;
	if ([aPath isEqualToString:self.path]) {
		// special case where the path is the same. Don't reload, just change the selection
		[imgMatrix selectFilenames:a comparator:self.comparator];
		if (doSlides)
			dispatch_async(dispatch_get_main_queue(), ^{
				// need to dispatch this otherwise the slideshow comes up behind this window
				[appDelegate slideshowFromAppOpen:imgMatrix.selectedFilenames];
			});
	} else {
		[self setPath:aPath];
	}
}

#pragma mark FSEvents stuff

- (BOOL)wantsSubfolders {
	[_internalLock lock];
	BOOL result = _wantsSubfolders;
	[_internalLock unlock];
	return result;
}
- (void)setWantsSubfolders:(BOOL)b {
	[_internalLock lock];
	_wantsSubfolders = b;
	_fileWatcher.wantsSubfolders = b;
	[_internalLock unlock];
}

// we handle reasonable real-world scenarios here:
// if the name changes, it will be deleted and added
// if we are sorted by mod time/size and that attribute changes, we need to update the list
// we do *not* handle the case where the EXIF date has changed (why would you ever do this?),
// or where "date added" changes without the user actually moving the file away and back into the folder,
// nor do we handle the user changing a file modification date to *before* the previous value
- (void)watcherFiles:(NSArray *)files deleted:(NSArray *)deleted {
	if (!filenamesDone) return;
	short int sortType = abs(self.sortOrder);
	BOOL sortByModTime = sortType == 2, sortBySize = sortType == 6;
	for (NSString *s in files) {
		NSUInteger count = filenames.count;
		struct stat buf;
		if (sortBySize || (sortByModTime && !stat(s.fileSystemRepresentation, &buf) && buf.st_mtimespec.tv_sec > matrixModTime)) {
			// when sorting by mod time, file list needs to be adjusted if the file's mod time has changed!
			NSUInteger oldIdx, idx = [filenames updateIndexOfObject:s usingComparator:self.comparator oldIndex:&oldIdx];
			if (idx != NSNotFound) {
				if (displayedFilenames.count != filenames.count)
					idx = [displayedFilenames updateIndexOfObject:s usingComparator:self.comparator oldIndex:&oldIdx];
				else
					[displayedFilenames moveObjectAtIndex:oldIdx toIndex:idx];
				if (idx != NSNotFound)
					[imgMatrix moveImageAtIndex:oldIdx toIndex:idx];
				[self fileWasChanged:s];
				continue;
			}
		}
		NSUInteger idx = [filenames indexOfObject:s inSortedRange:NSMakeRange(0, count) options:NSBinarySearchingInsertionIndex usingComparator:self.comparator];
		if (idx < count && [filenames[idx] isEqualToString:s]) {
			[self fileWasChanged:s];
		} else {
			[self addFile:s atIndex:idx];
		}
	}
	for (NSString *s in deleted) {
		NSUInteger idx = (sortOrder == 1 || sortOrder == -1) ? [filenames indexOfObject:s inSortedRange:NSMakeRange(0, filenames.count) options:0 usingComparator:self.comparator] : [filenames indexOfObject:s];
		if (idx != NSNotFound)
			[self fileWasDeleted:s atIndex:idx];
	}
	if (sortByModTime) time(&matrixModTime);
}

- (void)watcherRootChanged:(NSURL *)fileRef {
	if (!filenamesDone) return;
	[self removeAllPathsFromAccessedFilesArray];
	[self clearImageCacheQueue];
	NSString *s = _fileWatcher.path, *newPath = fileRef.path;
	if (newPath == nil) return;
	[self.window setTitleWithRepresentedFilename:newPath];
	[filenames changeBase:s toPath:newPath];
	[displayedFilenames changeBase:s toPath:newPath];
	[imgMatrix changeBase:s toPath:newPath];
}

- (void)addFile:(NSString *)s atIndex:(NSUInteger)idx {
	[filenames insertObject:s atIndex:idx];
	// show it in the grid too — but when a filter or category is active, only if it belongs there,
	// inserted at the sort-correct spot within the (possibly smaller) displayed list
	BOOL shows = [self filenamePassesSearch:s] &&
		(currCat == 0 || (currCat >= 2 && [appDelegate.cats[currCat-2] containsObject:s]));
	if (shows) {
		NSUInteger didx = [displayedFilenames indexOfObject:s inSortedRange:NSMakeRange(0, displayedFilenames.count)
											options:NSBinarySearchingInsertionIndex usingComparator:self.comparator];
		[displayedFilenames insertObject:s atIndex:didx];
		[imgMatrix addImage:nil withFilename:s atIndex:didx];
	}
	[self updateStatusFld];
}

- (void)fileWasChanged:(NSString *)s {
	if (![self pathIsCurrentDirectory:s]) return;
	// update thumb
	DYImageCache *thumbsCache = appDelegate.thumbsCache;
	NSString *theFile = ResolveAliasToPath(s);

	[_accessedLock lock];
	if ([_accessedFiles containsObject:s]) {
		[_accessedFiles removeObject:s];
		[thumbsCache endAccess:theFile];
	}
	[_accessedLock unlock];

	BOOL addedToCache = NO;
	NSImage *thumb = [thumbsCache imageForKeyInvalidatingCacheIfNecessary:theFile];
	if (thumb) {
		[thumbsCache beginAccess:theFile];
		addedToCache = YES;
	} else {
		addedToCache = [thumbsCache cacheFile:theFile fullSize:NO];
		thumb = [thumbsCache imageForKey:theFile];
		if (thumb && !addedToCache) {
			[thumbsCache beginAccess:theFile];
			addedToCache = YES;
		}
	}
	if (!thumb) thumb = _brokenDoc;
	// since we already checked if the file is in the current directory, we can assume the matrix's files have the same sort order
	NSUInteger mtrxIdx = [imgMatrix.filenames indexOfObject:s inSortedRange:NSMakeRange(0, imgMatrix.filenames.count) options:0 usingComparator:self.comparator];
	if (mtrxIdx != NSNotFound) {
		[imgMatrix updateImage:thumb atIndex:mtrxIdx];
		if (addedToCache) {
			[_accessedLock lock];
			[_accessedFiles addObject:s];
			[_accessedLock unlock];
		}
	} else if (addedToCache) {
		[thumbsCache endAccess:theFile];
	}
}
	
- (void)fileWasDeleted:(NSString *)s {
	[self fileWasDeleted:s atIndex:NSNotFound];
}
- (void)fileWasDeleted:(NSString *)s atIndex:(NSUInteger)i {
	if (![self pathIsCurrentDirectory:s]) return;
	BOOL linearSearch = abs(self.sortOrder) != 1;
	NSUInteger mtrxIdx;
	if (i == NSNotFound) {
		i = linearSearch ? [filenames indexOfObject:s] : [filenames indexOfObject:s inSortedRange:NSMakeRange(0, filenames.count) options:0 usingComparator:self.comparator];
	}
	if (i != NSNotFound) {
		stopCaching = 1;
		[loadImageLock lock];
		if ((mtrxIdx = linearSearch ? [imgMatrix.filenames indexOfObject:s] : [imgMatrix.filenames indexOfObject:s inSortedRange:NSMakeRange(0, imgMatrix.filenames.count) options:0 usingComparator:self.comparator]) != NSNotFound) {
			[imgMatrix removeImageAtIndex:mtrxIdx];
			[displayedFilenames removeObjectAtIndex:mtrxIdx];
		}
		[filenames removeObjectAtIndex:i];
		[loadImageLock unlock];

		[_accessedLock lock];
		if ([_accessedFiles containsObject:s]) {
			[_accessedFiles removeObject:s];
			[appDelegate.thumbsCache endAccess:ResolveAliasToPath(s)];
		}
		[_accessedLock unlock];

		if (!filenamesDone || !loadingDone) //[imgMatrix numCells] < [filenames count])
			[NSThread detachNewThreadSelector:@selector(loadImages:)
									 toTarget:self
								   withObject:filenamesDone ? [dirBrowserDelegate path] : nil];
		// must check filenamesDone in case interrupted
		[self updateStatusFld];
		if (imgMatrix.numCells == 0)
			slidesBtn.enabled = NO; // **
	}
}

- (void)filesWereUndeleted:(NSArray *)a {
	NSString *currentPath = self.path;
	BOOL subfolders = self.wantsSubfolders;
	for (NSString *s in a) {
		if (subfolders ? [s hasPrefix:currentPath] : [s.stringByDeletingLastPathComponent isEqualToString:currentPath])
			dispatch_async(dispatch_get_main_queue(), ^{
				if (!filenamesDone) return;
				NSUInteger count = filenames.count;
				NSUInteger idx = [filenames indexOfObject:s inSortedRange:NSMakeRange(0, count) options:NSBinarySearchingInsertionIndex usingComparator:self.comparator];
				if (idx == count || ![filenames[idx] isEqualToString:s])
					[self addFile:s atIndex:idx];
			});
	}
}

- (void)updateStatusFld {
	id s = NSLocalizedString(@"%u images", @"");
	NSString *status;
	if (currCat)
		status = [NSString stringWithFormat:@"%@: %@",
			[NSString stringWithFormat:NSLocalizedString(@"Group %i", @""), currCat],
			[NSString stringWithFormat:s, displayedFilenames.count]];
	else if (_searchQuery.length) // filtering: show matches of the folder total
		status = [NSString stringWithFormat:NSLocalizedString(@"%u of %u images", @""),
			(unsigned)displayedFilenames.count, (unsigned)filenames.count];
	else
		status = [NSString stringWithFormat:s, filenames.count];
	[self updateStatusString:status];
}

- (void)updateStatusString:(NSString *)s {
	_statusTime = NSDate.timeIntervalSinceReferenceDate;
	statusFld.stringValue = s;
}

- (void)updateStatusOnMainThread:(NSString * (^)(void))f {
	NSTimeInterval timeStamp = _statusTime = NSDate.timeIntervalSinceReferenceDate;
	dispatch_async(dispatch_get_main_queue(), ^{
		if (_statusTime > timeStamp) return;
		NSString *s = f();
		if (s) statusFld.stringValue = s;
	});
}

- (void)clearImageCacheQueue {
	[imageCacheQueueLock lock];
	[imageCacheQueue removeAllObjects];
	[secondaryImageCacheQueue removeAllObjects];
	[imageCacheQueueLock unlockWithCondition:0];
}

- (void)removeAllPathsFromAccessedFilesArray {
	DYImageCache *thumbsCache = appDelegate.thumbsCache;
	[_accessedLock lock];
	for (NSString *s in _accessedFiles) {
		[thumbsCache endAccess:ResolveAliasToPath(s)];
	}
	[_accessedFiles removeAllObjects];
	[_accessedLock unlock];
}

#pragma mark load thread
- (void)loadImages:(NSString *)thePath { // called in a separate thread
										 //NSLog(@"loadImages thread started for %@", thePath);
	// assume (incorrectly?) that threads will be executed in the order detached
	// better to set in loadDir and pass it in?
	NSTimeInterval myThreadTime;
	@autoreleasepool {
		myThreadTime = lastThreadTime = NSDate.timeIntervalSinceReferenceDate;
		// setting stopCaching stops only one thread (see below)
		// if there's a backlog of several threads, need to check thread time instead
		[loadImageLock lock];
		if (myThreadTime < lastThreadTime) {
			//NSLog(@"stale thread aborted, %@", thePath);
			[filesBeingOpened removeAllObjects];
			[loadImageLock unlock];
			return;
		}
		stopCaching = 0;
		NSThread.currentThread.name = [NSString stringWithFormat:@"loadImages:%@", thePath.lastPathComponent];

		NSUInteger i = 0;
		NSString *loadingMsg = NSLocalizedString(@"Getting filenames...", @"");
		//NSTimeInterval imgloadstarttime = NSDate.timeIntervalSinceReferenceDate;
	
		dispatch_async(dispatch_get_main_queue(), ^{
			[imgMatrix removeAllImages];
		});
		NSMutableSet *filesForSlideshow = startSlideshowWhenReady ? [NSMutableSet setWithCapacity:filesBeingOpened.count] : nil;
		if (thePath) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[_fileWatcher stop];
			});
			[filenames removeAllObjects];
			[self clearImageCacheQueue];
			BOOL recurseSubfolders = self.wantsSubfolders;
			BOOL inclUnsupported = self.showUnsupportedFiles;
			NSDirectoryEnumerator *e = CreeveyEnumerator(thePath, recurseSubfolders);
			for (NSURL *url in e) {
				@autoreleasepool {
					if ([appDelegate handledDirectory:url subfolders:recurseSubfolders e:e])
						continue;
					if ([appDelegate shouldShowFile:url includingUnsupported:inclUnsupported]) {
						NSString *aPath = url.path;
						[filenames addObject:aPath];
						if (startSlideshowWhenReady && [filesBeingOpened containsObject:aPath])
							[filesForSlideshow addObject:aPath];
						if ((++i & 127) == 0)
							[self updateStatusOnMainThread:^NSString *{
								return [NSString stringWithFormat:@"%@ (%lu)", loadingMsg, i];
							}];
					}
					if (stopCaching) {
						[filenames removeAllObjects]; // so it fails count > 0 test below
						break;
					}
				}
			}
		}
		if (filenames.count) {
			[self updateStatusOnMainThread:^NSString *{
				return [NSString stringWithFormat:NSLocalizedString(@"Sorting %lu filenames…", @""), filenames.count];
			}];
			[filenames sortUsingComparator:self.comparator];
		}
		if (currCat) { // currCat > 0 whenever cat changes (see keydown)
			// this means deleting when a cat is displayed will cause unsightly flashing
			// but we can live with that for now. maybe temp set currcat to 0?
			[self clearImageCacheQueue];
			[displayedFilenames removeAllObjects];
			if (currCat == 1) {
				currCat = 0;
				[displayedFilenames addObjectsFromArray:filenames];
			} else {
				for (NSString *path in filenames) {
					if ([appDelegate.cats[currCat-2] containsObject:path])
						[displayedFilenames addObject:path];
				}
			}
		} else {
			[displayedFilenames setArray:filenames];
		}
		if (_searchQuery.length) { // filename filter (regex or case-insensitive substring)
			NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:displayedFilenames.count];
			for (NSString *path in displayedFilenames)
				if ([self filenamePassesSearch:path]) [filtered addObject:path];
			[displayedFilenames setArray:filtered];
		}
		time(&matrixModTime);
		if (startSlideshowWhenReady) {
			startSlideshowWhenReady = NO;
			// set this back to NO so we don't get infinite slideshow looping if a category is selected (initiated by windowDidBecomeMain:)
			if (filesForSlideshow.count) {
				NSArray *files = [filesForSlideshow.allObjects sortedArrayUsingComparator:self.comparator];
				[appDelegate performSelectorOnMainThread:@selector(slideshowFromAppOpen:) withObject:files waitUntilDone:NO]; // this must be called after displayedFilenames is sorted in case it calls back for indexOfFilename:
			}
		}
		filenamesDone = YES;
		//NSLog(@"got %d files.", [filenames count]);
		dispatch_async(dispatch_get_main_queue(), ^{ [appDelegate noteRecentFolderForWindow:self]; }); // Open Recent: record the folder we just loaded
	}
#pragma mark populate matrix
	@autoreleasepool {
		DYImageCache *thumbsCache = appDelegate.thumbsCache;
		[self removeAllPathsFromAccessedFilesArray];

		NSUInteger i = 0;
		NSMutableIndexSet *selectedIndexes = [NSMutableIndexSet indexSet];
		if (displayedFilenames.count > 0) {
			loadingDone = NO;
			dispatch_async(dispatch_get_main_queue(), ^{
				slidesBtn.enabled = YES;
			});
			currentFilesDeletable = [NSFileManager.defaultManager isDeletableFileAtPath:displayedFilenames[0]];
		
			NSUInteger numFiles = displayedFilenames.count;
			NSUInteger maxThumbs = [NSUserDefaults.standardUserDefaults
									integerForKey:@"maxThumbsToLoad"];
		
			for (; i<numFiles; ++i) {
				if (stopCaching) {
					//NSLog(@"aborted1 %@", origPath);
					break;
				}
				NSString *origPath = displayedFilenames[i];
				NSString *resolvedPath = ResolveAliasToPath(origPath);
				NSImage *cachedImage = [thumbsCache imageForKeyInvalidatingCacheIfNecessary:resolvedPath];
				// what happens if another window happens to invalidate a thumb that we started "access" to?
				// Actually it won't matter if we make too many calls to endAccess:, worst case is we'll have to recache it at some point.
				dispatch_async(dispatch_get_main_queue(), ^{
					[imgMatrix addImage:cachedImage withFilename:origPath];
				});
				if (cachedImage != nil) {
					[thumbsCache beginAccess:resolvedPath];
					[_accessedLock lock];
					[_accessedFiles addObject:origPath];
					[_accessedLock unlock];
				}
				if ([filesBeingOpened containsObject:origPath])
					[selectedIndexes addIndex:i];

				// now, to simulate the original behavior, add a certain number of
				// images to the queue automatically
				if (cachedImage == nil && i < maxThumbs) {
					[imageCacheQueueLock lock];
					[secondaryImageCacheQueue addObject:[[DYMatrixFileInfo alloc] initWithPath:origPath index:i]];
					[imageCacheQueueLock unlockWithCondition:1];
				}
			}
		}
		loadingDone = (i==displayedFilenames.count);
		/*if (i) {
		 NSTimeInterval delta = NSDate.timeIntervalSinceReferenceDate - imgloadstarttime;
		 NSLog(@"%d files/%f secs = %f/s; %f s/file", i, delta,
		 i / delta, delta/i);
		 }*/
		if (myThreadTime == lastThreadTime) {
			[self performSelectorOnMainThread:@selector(updateStatusFld) withObject:nil waitUntilDone:NO];
			if (thePath)
				dispatch_async(dispatch_get_main_queue(), ^{
					[_fileWatcher watchDirectory:thePath];
				});
		}
		if (loadingDone && filesBeingOpened.count) {
			[filesBeingOpened removeAllObjects];
			if (myThreadTime == lastThreadTime && selectedIndexes.count)
				dispatch_async(dispatch_get_main_queue(), ^{
					if ([thePath isEqualToString:dirBrowserDelegate.currentResolvedPath])
						[imgMatrix scrollToFirstSelected:selectedIndexes];
				});
		}
		[loadImageLock unlock];
	}
}

- (IBAction)displayDir:(id)sender {
	stopCaching = 1;
	currentFilesDeletable = NO;
	filenamesDone = NO;
	currCat = 0;
	slidesBtn.enabled = NO;
	// A mounted archive is browsed straight from its temp dir (the NSBrowser can't reliably
	// navigate into a deep hidden temp path). Our own refresh calls pass sender==nil; a non-nil
	// sender means the user drove the directory browser, i.e. navigated out of the archive.
	NSString *currentPath;
	if (_archiveTempDir && sender == nil) {
		currentPath = _archiveTempDir;
	} else {
		if (_archiveTempDir) [self cleanupArchiveTemp]; // user navigated the browser → leave the archive
		currentPath = [dirBrowserDelegate path];
	}
	// the filter is per-folder: clear it only on a real folder change, not on same-folder
	// re-scans (toggling Unsupported/Subfolders, etc.)
	if (![currentPath isEqualToString:_lastLoadedPath]) {
		if (_searchQuery.length) { _searchQuery = nil; _searchField.stringValue = @""; }
		_lastLoadedPath = currentPath;
	}
	_subfoldersButton.enabled = ![currentPath isEqualToString:@"/"]; // let's not ever load up the entire file system
	if (self.wantsSubfolders && sender) { // sender is dirBrowserDelegate when non-nil
		if (![currentPath hasPrefix:_recurseRoot]) {
			self.wantsSubfolders = NO;
			_subfoldersButton.state = NSControlStateValueOff;
		}
	}
	[self updateStatusString:NSLocalizedString(@"Getting filenames...", @"")];
	if (_archiveTempDir && sender == nil && _archiveDisplayName)
		self.window.title = _archiveDisplayName; // show the archive name, not the temp path
	else
		[self.window setTitleWithRepresentedFilename:currentPath];
	[self updatePathBar];
	[NSThread detachNewThreadSelector:@selector(loadImages:)
							 toTarget:self withObject:currentPath];
}

- (IBAction)setRecurseSubfolders:(id)sender {
	NSButton *button = sender;
	self.wantsSubfolders = (button.state == NSControlStateValueOn);
	// remember where we started recursing subfolders
	if (self.wantsSubfolders) {
		NSString *path = [dirBrowserDelegate path];
		// but don't reset if we're still in a subfolder from the last time this was set
		if (_recurseRoot == nil || ![path hasPrefix:_recurseRoot])
			// add a slash so we continue recursing for any sibling folders, but not the parent folder
			self.recurseRoot = [[dirBrowserDelegate path].stringByDeletingLastPathComponent stringByAppendingString:@"/"];
	} else {
		// if user aborted, assume that's not a good place to recurse
		if (!filenamesDone)
			self.recurseRoot = nil;
	}
	[self displayDir:nil];
}


#pragma mark menu stuff
- (void)copy:(id)sender {
	[imgMatrix copy:sender]; // so Cmd-C copies the grid selection even from the directory browser
}
- (void)selectAll:(id)sender{
	[self.window makeFirstResponder:imgMatrix];
	[imgMatrix selectAll:sender];
}

- (void)selectNone:(id)sender{
	[imgMatrix selectNone:sender];
}


#pragma mark event stuff
- (void)reloadInterfaceTextSize {
	[imgMatrix reloadTextSize];
	[dirBrowser reloadTextSize];
	[self applyInterfaceTextSize];
}

// scale the window's status line and file-info line with the interface text
// size setting. Base sizes are captured once so repeated changes don't compound.
- (void)applyInterfaceTextSize {
	if (!_textBasesCaptured) {
		_statusBaseSize = statusFld.font.pointSize;
		_bottomStatusBaseSize = bottomStatusFld.font.pointSize;
		_textBasesCaptured = YES;
	}
	CGFloat s = DYInterfaceTextScale();
	statusFld.font = [NSFont fontWithDescriptor:statusFld.font.fontDescriptor size:_statusBaseSize * s];
	bottomStatusFld.font = [NSFont fontWithDescriptor:bottomStatusFld.font.fontDescriptor size:_bottomStatusBaseSize * s];
}

- (void)fakeKeyDown:(NSEvent *)e {
	[self.window makeFirstResponder:imgMatrix];
	[imgMatrix keyDown:e];
	[self.window makeFirstResponder:dirBrowser];
}

- (void)keyDown:(NSEvent *)e {
	if (e.characters.length == 0) return;
	unichar c = [e.characters characterAtIndex:0];
	if (filenamesDone && c >= NSF1FunctionKey && c <= NSF12FunctionKey) {
		c = c - NSF1FunctionKey + 1;
		if ((e.modifierFlags & NSEventModifierFlagCommand) != 0) {
			NSUInteger i;
			short j;
			NSArray *a = imgMatrix.selectedFilenames;
			if (!a.count) {
				NSBeep();
				return;
			}
			
			NSMutableSet * __strong *cats = appDelegate.cats;
			for (i=a.count-1; i != -1; i--) { // TODO: this code is suspect
				id fname = a[i];
				if (c == 1) {
					for (j=0; j<NUM_FNKEY_CATS; ++j)
						[cats[j] removeObject:fname];
				} else {
					if ([cats[c-2] containsObject:fname])
						[cats[c-2] removeObject:fname];
					else
						[cats[c-2] addObject:fname];
				}
			}
			[appDelegate updateCats];
			if (!currCat || (c && c != currCat)) {
				[self updateStatusString:[NSString stringWithFormat:
					NSLocalizedString(@"%u image(s) updated for Group %i", @""),
					(unsigned int)a.count, c]];
				[self performSelector:@selector(updateStatusFld)
						   withObject:nil
						   afterDelay:2];
				return;
			} // but reload, below, if displaying a cat
		} else {
			if (c==1) c = 0;
			if (currCat == c) return;
			currCat = c ? c : 1; // strictly speaking, should go after the lock
			// but we're reloading anyway, it's OK
		}
		
		stopCaching = 1; // don't need to lock, not changing anything
		currentFilesDeletable = NO; // dup code from displayDir?
		filenamesDone = NO;
		slidesBtn.enabled = NO;
		[NSThread detachNewThreadSelector:@selector(loadImages:)
								 toTarget:self
							   withObject:nil];
		return;
	}
	if (filenamesDone) {
		switch ([appDelegate.keyBindings browserActionForEvent:e]) {
			case BrowserActionMoveToTrash:
				[appDelegate moveToTrash:nil];
				return;
			case BrowserActionDeletePermanently:
				[appDelegate deleteSelectedFilesPermanently:nil];
				return;
			case BrowserActionRename:
				[appDelegate renameSelectedFile:nil];
				return;
			case BrowserActionNone:
				break;
		}
	}
	[super keyDown:e];
}


#pragma mark window delegate methods
- (void)windowDidResignMain:(NSNotification *)aNotification {
	_background = YES;
}

- (void)windowDidBecomeMain:(NSNotification *)aNotification {
	[self updateExifInfo];
	_background = NO;
	if (filenamesDone && currCat) { // reload in case category membership of certain files changed;
		// ** we should probably notify when cats change instead
		// ** and also handle the case where you change something's category so it no longer belongs in the current view
		stopCaching = 1;
		[loadImageLock lock];
		// make reloading less bad by saving selection
		[filesBeingOpened addObjectsFromArray:imgMatrix.selectedFilenames];
		[loadImageLock unlock];
		[NSThread detachNewThreadSelector:@selector(loadImages:)
								 toTarget:self
							   withObject:nil];
	}
}

// the existence of this method enables the '+' button in the tab bar
- (void)newWindowForTab:(id)sender {
	[appDelegate newTab:self];
}

- (void)updateExifInfo:(id)sender {
	NSTextView *exifTextView = appDelegate.exifTextView;
	if (!exifTextView.window.visible) return;
	NSView *mainView = exifTextView.window.contentView;
	NSImageView *thumbView = [mainView viewWithTag:2];
	NSMutableAttributedString *attStr;
	NSMutableIndexSet *selectedIndexes = imgMatrix.selectedIndexes;
	if (selectedIndexes.count == 1) {
		DYImageCache *cache = appDelegate.thumbsCache;
		NSString *path = imgMatrix.firstSelectedFilename;
		NSButton *moreBtn = [mainView viewWithTag:1];
		attStr = Fileinfo2EXIFString(path, cache, moreBtn.state);
		NSString *resolvedPath = ResolveAliasToPath(path);
		exifWindowNeedsUpdate = [cache infoForKey:resolvedPath] == nil;
		if (!exifWindowNeedsUpdate)
			thumbView.image = [DYExiftags exifThumbForPath:resolvedPath];
	} else {
		id s = selectedIndexes.count
		? [NSString stringWithFormat:NSLocalizedString(@"%d images selected.", @""),
		   (unsigned int)selectedIndexes.count]
		: NSLocalizedString(@"No images selected.", @"");
		attStr = [[NSMutableAttributedString alloc] initWithString:s attributes:@{NSFontAttributeName:[NSFont userFontOfSize:12]}];
		thumbView.image = nil;
		exifWindowNeedsUpdate = NO;
	}
	[attStr addAttribute:NSForegroundColorAttributeName value:NSColor.labelColor range:NSMakeRange(0,attStr.length)];
	[exifTextView.textStorage setAttributedString:attStr];
}

- (void)updateExifInfo {
	[self updateExifInfo:nil];
}

#pragma mark splitview delegate

- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
	// only persist/remember the height while the browser is actually shown — when it's
	// hidden the pane is shrunk to the control strip, which isn't a height worth restoring
	if (_directoryBrowserHidden) return;
	float height = statusFld.superview.hidden ? 0 : statusFld.superview.frame.size.height;
	[NSUserDefaults.standardUserDefaults setFloat:height forKey:@"MainWindowSplitViewTopHeight"];
	// remember heights from real user drags only; the show/hide toggle sets _togglingBrowser
	// so the intermediate resize as the pane clamps to its minimum can't clobber the saved size
	if (height > 0 && !_togglingBrowser) _savedBrowserHeight = height;
}

- (BOOL)directoryBrowserVisible {
	return !_directoryBrowserHidden;
}

// The directory browser and the control strip (file count, Unsupported/Subfolders, Slideshow)
// share the top split pane. To keep the strip visible when the browser is hidden, we drop just
// the browser view and shrink the pane to the strip, instead of collapsing the whole pane.
- (void)ensureBrowserToggleConstraints {
	if (_browserZeroHeight) return;
	NSView *pane = dirBrowser.superview;
	for (NSLayoutConstraint *c in dirBrowser.constraints)
		if (c.firstItem == dirBrowser && c.firstAttribute == NSLayoutAttributeHeight && c.relation == NSLayoutRelationGreaterThanOrEqual)
			_browserMinHeight = c; // browser's height >= 30
	for (NSLayoutConstraint *c in pane.constraints)
		if (c.firstItem == slidesBtn && c.firstAttribute == NSLayoutAttributeTop && c.secondItem == dirBrowser && c.secondAttribute == NSLayoutAttributeBottom)
			_browserGap = c; // control strip sits below the browser
	_browserZeroHeight = [dirBrowser.heightAnchor constraintEqualToConstant:0]; // inactive until hidden
}

- (void)setShowUnsupportedFiles:(BOOL)b {
	if (b == _showUnsupportedFiles) return;
	_showUnsupportedFiles = b;
	_unsupportedButton.state = b ? NSControlStateValueOn : NSControlStateValueOff; // sync the checkbox (menu-driven toggles land here too)
	[self displayDir:nil]; // re-scan the folder to add or drop the unsupported files
}

- (IBAction)toggleUnsupportedFilesButton:(id)sender {
	self.showUnsupportedFiles = ([(NSButton *)sender state] == NSControlStateValueOn);
}

- (void)setDirectoryBrowserVisible:(BOOL)show {
	if (show == !_directoryBrowserHidden) return;
	[self ensureBrowserToggleConstraints];
	_directoryBrowserHidden = !show;
	_togglingBrowser = YES; // guard _savedBrowserHeight against the resize passes below
	NSView *pane = dirBrowser.superview;
	if (show) {
		dirBrowser.hidden = NO;
		_browserZeroHeight.active = NO;
		_browserGap.active = YES;
		_browserMinHeight.active = YES;
		CGFloat h = _savedBrowserHeight > 0 ? _savedBrowserHeight : 151;
		[self.splitView setPosition:h ofDividerAtIndex:0];
	} else {
		// keep the control strip: hide only the browser and shrink the pane to the strip below it
		CGFloat strip = pane.frame.size.height - dirBrowser.frame.size.height;
		if (pane.frame.size.height > strip) _savedBrowserHeight = pane.frame.size.height;
		dirBrowser.hidden = YES;
		_browserMinHeight.active = NO; // let the browser go to zero height
		_browserGap.active = NO;       // unlink the strip from the (now hidden) browser
		_browserZeroHeight.active = YES;
		[self.splitView setPosition:strip ofDividerAtIndex:0];
	}
	dispatch_async(dispatch_get_main_queue(), ^{ self->_togglingBrowser = NO; }); // clear after this cycle's resizes
}

-(BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
	return subview == dirBrowser.superview;
}

#pragma mark wrapping matrix methods
- (void)wrappingMatrixSelectionDidChange:(NSIndexSet *)selectedIndexes {
	// While Quick Look is up, the status line and Get Info panel are hidden behind it, so skip
	// this work (it can decode an image just to report its dimensions). endPreviewPanelControl
	// calls us once when the panel closes to refresh for the file we landed on.
	if (_quickLookActive) return;
	// Coalesce the heavy work below (summing sizes stat()s every selected file; EXIF; the Open
	// Recent note) so a rapid multi-select — mouse drag or shift+arrow — doesn't do O(files)
	// syscalls on each change. A single/empty selection is cheap, so refresh it immediately.
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateSelectionInfo) object:nil];
	if (selectedIndexes.count > 1)
		[self performSelector:@selector(updateSelectionInfo) withObject:nil afterDelay:0.12];
	else
		[self updateSelectionInfo];
}

- (void)updateSelectionInfo {
	if (_quickLookActive) return;
	NSString *s;
	NSUInteger count = imgMatrix.selectedIndexes.count;
	if (count == 0) {
		s = @"";
	} else {
		DYImageInfo *info;
		DYImageCache *thumbsCache = appDelegate.thumbsCache;
		if (count == 1) {
			NSString *path = imgMatrix.firstSelectedFilename;
			NSString *theFile = ResolveAliasToPath(path);
			info = [thumbsCache infoForKey:theFile];
			NSSize pixelSize;
			off_t fileSize;
			if (info) {
				pixelSize = info->pixelSize;
				fileSize = info->fileSize;
			} else {
				struct stat buf;
				if (!stat(theFile.fileSystemRepresentation, &buf))
					fileSize = buf.st_size;
				else
					fileSize = 0;
				if (IsNotCGImage(theFile.pathExtension.lowercaseString)) {
					NSImage *img = [[NSImage alloc] initByReferencingFile:theFile];
					pixelSize = img ? img.size : NSZeroSize;
				} else {
					CGImageSourceRef imgSrc = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:theFile isDirectory:NO], NULL);
					if (imgSrc) {
						NSDictionary *opts = @{(__bridge NSString *)kCGImageSourceShouldCache: @NO};
						CGImageRef ref = CGImageSourceCreateImageAtIndex(imgSrc, 0, (__bridge CFDictionaryRef)opts);
						if (ref) {
							pixelSize.width = CGImageGetWidth(ref);
							pixelSize.height = CGImageGetHeight(ref);
							CFRelease(ref);
						} else
							pixelSize = NSZeroSize;
						CFRelease(imgSrc);
					} else
						pixelSize = NSZeroSize;
				}
			}
			// show the file's name relative to the folder being browsed; for an archive that's
			// the extraction temp dir, not the directory browser's path. If the file isn't under
			// that base (e.g. a transient/other-archive entry), fall back to the bare filename so
			// we never surface a raw temp-path fragment.
			NSString *base = _archiveTempDir ?: [dirBrowserDelegate path];
			NSString *fileName = [path hasPrefix:[base stringByAppendingString:@"/"]]
				? [path substringFromIndex:base.length+1]
				: path.lastPathComponent;
			s = [fileName stringByAppendingFormat:@" %dx%d (%@)",
				 (int)pixelSize.width, (int)pixelSize.height, FileSize2String(fileSize)];
		} else {
			unsigned long long totalSize = 0;
			for (NSString *path in imgMatrix.selectedFilenames) {
				NSString *theFile = ResolveAliasToPath(path);
				info = [thumbsCache infoForKey:theFile];
				if (info)
					totalSize += info->fileSize;
				else {
					struct stat buf;
					if (!stat(theFile.fileSystemRepresentation, &buf))
						totalSize += buf.st_size;
				}
			}
			s = [NSString stringWithFormat:@"%@ (%@)",
				 [NSString stringWithFormat:NSLocalizedString(@"%d images selected.", @""), (unsigned int)count],
				 FileSize2String(totalSize)];
		}
	}
	bottomStatusFld.stringValue = s;
	[self updateExifInfo];
	[appDelegate noteRecentFolderForWindow:self]; // Open Recent: keep the folder's focused-file current
}

- (NSImage *)wrappingMatrixWantsImageForFile:(NSString *)filename atIndex:(NSUInteger)i {
	DYImageCache *thumbsCache = appDelegate.thumbsCache;
	NSImage *thumb = [thumbsCache imageForKeyInvalidatingCacheIfNecessary:ResolveAliasToPath(filename)];
	if (thumb) return thumb;
	[imageCacheQueueLock lock];
	[imageCacheQueue insertObject:[[DYMatrixFileInfo alloc] initWithPath:filename index:i] atIndex:0];
	[imageCacheQueueLock unlockWithCondition:1];
	return nil;
}

// this thread runs forever, waiting for objects to be added to its queue
- (void)thumbLoader:(id)arg { @autoreleasepool {
	NSThread.currentThread.name = @"thumbLoader:";
	NSThread.currentThread.qualityOfService = NSQualityOfServiceDefault;
	DYImageCache *thumbsCache = appDelegate.thumbsCache;
	// only use exif thumbs if we're at the smallest thumbnail  setting
	NSUInteger i, lastCount = 0;
	NSMutableArray<DYMatrixFileInfo *> *visibleQueue = [[NSMutableArray alloc] initWithCapacity:100];
	NSString *loadingMsg = NSLocalizedString(@"Loading %lu of %lu...", @"");
	BOOL workToDo = YES;
	DYMatrixState *currState = [[DYMatrixState alloc] init];
	while (YES) {
		@autoreleasepool {
			// decode at higher priority for the window the user is looking at, and
			// lower for background windows, so the visible grid fills in first
			NSThread.currentThread.qualityOfService = _background ? NSQualityOfServiceUtility : NSQualityOfServiceUserInitiated;
			// all calls to the thumbnail view must be on the main thread, which we wait for synchronously
			// to avoid a deadlock (where the view's drawRect calls our loadImageForFile, which modifies the cache queue),
			// we save the state of the view before acquiring the lock (we can't use NSRecursiveLock since we need NSConditionLock)
			dispatch_sync(dispatch_get_main_queue(), ^{
				[imgMatrix loadCurrentState:currState];
			});
			[imageCacheQueueLock lockWhenCondition:1];
			if (!imageCacheQueueRunning) {
				// final cleanup before terminating thread
				[imageCacheQueueLock unlockWithCondition:0];
				break;
			}
			// use secondary queue if primary queue is empty
			// note: the secondary queue may be empty if all items are in the visibleQueue
			if (imageCacheQueue.count == 0 && secondaryImageCacheQueue.count) {
				[imageCacheQueue addObject:secondaryImageCacheQueue[0]];
				[secondaryImageCacheQueue removeObjectAtIndex:0];
			}
			DYMatrixFileInfo *d;
			// discard any items in the queue that are no longer in the browser's directory.
			// prioritize important files (the visible ones) by putting them in a higher-priority array.
			if (!visibleQueue.count                   // nothing in the priority queue, so search for more items to add to it...
				&& imageCacheQueue.count != lastCount // but skip this if nothing has been added to the queue
				)
			{
				i = imageCacheQueue.count;
				while (i--) {
					d = imageCacheQueue[i];
					//NSLog(@"considering %@ for priority queue", [d objectForKey:@"index"]);
					if (![self pathIsVisibleThreaded:d->path]) {
						if (imageCacheQueue.count > 1) // leave at least one item so it won't crash later (the next while loop assumes there's at least one item)
							//NSLog(@"skipping %@ because path has changed", [d objectForKey:@"index"]),
							[imageCacheQueue removeObjectAtIndex:i];
						continue;
					}
					if ([currState imageWithFileInfoNeedsDisplay:d]) {
						[visibleQueue addObject:d];
						[imageCacheQueue removeObjectAtIndex:i];
						//NSLog(@"prioritizing %@ because it is visible", [d objectForKey:@"index"]);
					}
				}
			}
			lastCount = imageCacheQueue.count;
			// skip any files that are not visible in the matrix view.
			i = 0;
			while (YES) {
				if (visibleQueue.count) {
					// run through this "pre-approved" array before touching the main queue
					d = visibleQueue[0];
					if ([currState imageWithFileInfoNeedsDisplay:d] || visibleQueue.count == 1) {
						[visibleQueue removeObjectAtIndex:0];
						//if ([imgMatrix imageWithFileInfoNeedsDisplay:d])
						//	NSLog(@"processing %@ because needsDisplay", [d objectForKey:@"index"]);
						//else NSLog(@"processing %@ as last item of priority queue", [d objectForKey:@"index"]);
						break;
					} else {
						// if the cell is no longer visible, invalidate the visibleQueue
						//NSLog(@"dropping %@ and removing %u items from visibleQueue", [d objectForKey:@"index"], [visibleQueue count]);
						[imageCacheQueue addObjectsFromArray:visibleQueue];
						[visibleQueue removeAllObjects];
						continue;
					}
				}
				d = imageCacheQueue[i];
				//NSLog(@"considering %@ in main loop", [d objectForKey:@"index"]);
				if (imageCacheQueue.count-1 == i) { // if we've reached the last item of the array, we have to process it
					[imageCacheQueue removeObjectAtIndex:i];
					//NSLog(@"processing %@ because it is the last item", [d objectForKey:@"index"]);
					break;
				}
				if ([currState imageWithFileInfoNeedsDisplay:d]) {
					[imageCacheQueue removeObjectAtIndex:i];
					//NSLog(@"processing %@ as visible item", [d objectForKey:@"index"]);
					break;
				}
				++i;
			}
			workToDo = (imageCacheQueue.count || visibleQueue.count || secondaryImageCacheQueue.count);
			[imageCacheQueueLock unlockWithCondition:workToDo ? 1 : 0]; // keep the condition as 1 (more work needs to be done) if there's still stuff in the array
			
			NSString *origPath = d->path, *theFile = ResolveAliasToPath(origPath);
			NSImage *thumb = [thumbsCache imageForKey:theFile];
			BOOL addedToCache = NO;
			if (thumb) {
				[thumbsCache beginAccess:theFile];
				addedToCache = YES;
			} else {
				// we're rolling our own cancelPreviousPerformRequestsWithTarget here
				// before updating the status field in the main thread, we check if anyone else has modified it (or dispatched a block to modify it) after the timeStamp
				[self updateStatusOnMainThread:^NSString *{
					if (imgMatrix.numCells == 0) return nil; // don't set status string if there are no thumbs (could happen if a file is in the queue when the path changes)
					[_accessedLock lock];
					NSUInteger k = _accessedFiles.count;
					[_accessedLock unlock];
					return [NSString stringWithFormat:loadingMsg, k+1, imgMatrix.numCells];
				}];
				addedToCache = [thumbsCache cacheFile:theFile fullSize:NO]; // will sleep if pending
				thumb = [thumbsCache imageForKey:theFile];
				if (thumb && !addedToCache) {
					// someone beat us to it
					[thumbsCache beginAccess:theFile];
					addedToCache = YES;
				}
			}
			
			if (!thumb)
				thumb = _brokenDoc;
			dispatch_async(dispatch_get_main_queue(), ^{
				if ([imgMatrix setImage:thumb atIndex:d->idx forFilename:origPath]) {
					if (addedToCache) {
						[_accessedLock lock];
						[_accessedFiles addObject:origPath];
						[_accessedLock unlock];
						if (exifWindowNeedsUpdate && self.window.isMainWindow && [imgMatrix.firstSelectedFilename isEqualToString:origPath]) {
							[self updateExifInfo];
						}
					}
				} else if (addedToCache) {
					[thumbsCache endAccess:theFile];
				}
			});
			if (_background)
				[NSThread sleepForTimeInterval:0.1];
		}
		if (!workToDo)
			[self performSelectorOnMainThread:@selector(updateStatusFld)
								   withObject:nil
								waitUntilDone:NO];
	}
}}

@end
