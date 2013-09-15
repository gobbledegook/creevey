//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "CreeveyController.h"
#import "EpegWrapper.h"
#import "DYJpegtran.h"
#import "DYCarbonGoodies.h"
#import "NSArrayIndexSetExtension.h"

#import "DYWrappingMatrix.h"
#import "CreeveyMainWindowController.h"
#import "DYImageCache.h"
#import "SlideshowWindow.h"
#import "DYJpegtranPanel.h"
#import "DYVersChecker.h"

#define MAX_THUMBS 2000
#define DYVERSCHECKINTERVAL 604800

inline BOOL FileIsJPEG(NSString *s) {
	return [[[s pathExtension] lowercaseString] isEqualToString:@"jpg"]
	|| [NSHFSTypeOfFile(s) isEqualToString:@"JPEG"];
}

@interface TimeIntervalPlusWeekToStringTransformer : NSObject
// using a val xformer means the field gets updated automatically
@end
@implementation TimeIntervalPlusWeekToStringTransformer
+ (Class)transformedValueClass { return [NSString class]; }
- (id)transformedValue:(id)v {
	return [[NSDate dateWithTimeIntervalSinceReferenceDate:
		[v floatValue]+DYVERSCHECKINTERVAL] description];
}
@end

@implementation CreeveyController

+(void)initialize
{
    NSMutableDictionary *dict;
    NSUserDefaults *defaults;
	
    defaults=[NSUserDefaults standardUserDefaults];
	
    dict=[NSMutableDictionary dictionary];
	NSString *s = CREEVEY_DEFAULT_PATH;
    [dict setObject:s forKey:@"picturesFolderPath"];
    [dict setObject:s forKey:@"lastFolderPath"];
    [dict setObject:[NSNumber numberWithShort:0] forKey:@"startupOption"];
	[dict setObject:[NSNumber numberWithFloat:120] forKey:@"thumbCellWidth"];
	[dict setObject:[NSNumber numberWithBool:YES] forKey:@"getInfoVisible"];
	[dict setObject:[NSNumber numberWithBool:YES] forKey:@"autoVersCheck"];
    [defaults registerDefaults:dict];

	id t = [[[TimeIntervalPlusWeekToStringTransformer alloc] init] autorelease];
	[NSValueTransformer setValueTransformer:t
									forName:@"TimeIntervalPlusWeekToStringTransformer"];
}

- (id)init {
	if (self = [super init]) {
		filetypes = [[NSSet alloc] initWithArray:[NSImage imageFileTypes]];
			//@"jpg", @"jpeg," @"gif",
			//@"tif", @"tiff", @"pict", @"pdf", @"icns", nil];
		//hfstypes = [[NSSet alloc] initWithObjects:@"'PICT'", @"'JPEG'", @"'GIFf'",
		//	@"'TIFF'", @"'PDF '", nil]; // need those single quotes
		//NSLog(@"%@", [NSImage imageFileTypes]);
		creeveyWindows = [[NSMutableArray alloc] initWithCapacity:5];
		
		thumbsCache = [[DYImageCache alloc] initWithCapacity:MAX_THUMBS];
		[thumbsCache setBoundingSize:[DYWrappingMatrix maxCellSize]];
		[thumbsCache setInterpolationType:NSImageInterpolationNone];
		
		short int i;
		for (i=0; i<NUM_FNKEY_CATS; ++i) {
			cats[i] = [[NSMutableSet alloc] initWithCapacity:0];
		}
		
		exifWasVisible = [[NSUserDefaults standardUserDefaults] boolForKey:@"getInfoVisible"];
	}
    return self;
}


- (void)awakeFromNib { // ** warning: this gets called when loading nibs too!
	[(NSPanel *)[exifTextView window] setBecomesKeyOnlyIfNeeded:YES];
	[slidesWindow setCats:cats];
}

- (void)dealloc {
	[thumbsCache release];
	[filetypes release];
	[creeveyWindows release];
	short int i;
	for (i=0; i<NUM_FNKEY_CATS; ++i)
		[cats[i] release];
	[super dealloc];
}

- (void)startSlideshow {
	// check for nil?
	// clever disabling of items should be ok
	[slidesWindow setBasePath:[frontWindow path]];
	NSIndexSet *s = [frontWindow selectedIndexes];
	[slidesWindow setFilenames:[s count] > 1
		? [frontWindow currentSelection]
		: [frontWindow displayedFilenames]];
	[slidesWindow startSlideshowAtIndex: [s count] == 1 ? [s firstIndex] : -1];
}

- (IBAction)slideshow:(id)sender
{
	[self startSlideshow];
}

- (IBAction)openSelectedFiles:(id)sender {
	[self startSlideshow];
}

- (IBAction)revealSelectedFilesInFinder:(id)sender {
	if ([slidesWindow isKeyWindow]) {
		RevealItemsInFinder([NSArray arrayWithObject:[slidesWindow currentFile]]);
	} else {
		NSArray *a = [frontWindow currentSelection];
		if ([a count])
			RevealItemsInFinder(a);
		else
			[[NSWorkspace sharedWorkspace] openFile:[frontWindow path]];
	}
}


- (IBAction)setDesktopPicture:(id)sender {
	NSString *s = [slidesWindow isKeyWindow]
		? [slidesWindow currentFile]
		: [[frontWindow currentSelection] objectAtIndex:0];
	OSErr err = SetDesktopPicture(ResolveAliasToPath(s),0);
	if (err != noErr) {
		NSRunAlertPanel(nil, //title
						NSLocalizedString(@"Could not set the desktop because an error of type %i occurred.", @""),
						@"Cancel", nil, nil,
						err);
	}
}

- (IBAction)rotateTest:(id)sender {
	DYJpegtranInfo jinfo;
	int t = [sender tag] - 100;
	if (t == 0) {
		if (!jpegController)
			if (![NSBundle loadNibNamed:@"DYJpegtranPanel" owner:self]) return;
		if (![jpegController runOptionsPanel:&jinfo]) return;
		if (jinfo.tinfo.force_grayscale || jinfo.cp != JCOPYOPT_ALL || jinfo.tinfo.trim)
			if (NSRunCriticalAlertPanel(NSLocalizedString(@"Warning", @""),
									NSLocalizedString(@"This operation cannot be undone! Are you sure you want to continue?", @""),
									NSLocalizedString(@"Continue", @""), NSLocalizedString(@"Cancel", @""), nil)
				!= NSAlertDefaultReturn)
				return; // user cancelled
	} else {
		jinfo.tinfo.transform = t < DYJPEGTRAN_XFORM_PROGRESSIVE ? t : JXFORM_NONE;
		jinfo.tinfo.trim = FALSE;
		jinfo.tinfo.force_grayscale = t == DYJPEGTRAN_XFORM_GRAYSCALE;
		jinfo.cp = JCOPYOPT_ALL;
		jinfo.progressive = t == DYJPEGTRAN_XFORM_PROGRESSIVE;
		jinfo.optimize = 0;
	}
	
	NSArray *a;
	BOOL slidesWasKey = [slidesWindow isKeyWindow];
	a = slidesWasKey
		? [NSArray arrayWithObject:[slidesWindow currentFile]]
		: [frontWindow currentSelection];
	
	[jpegProgressBar setUsesThreadedAnimation:YES];
	[jpegProgressBar setIndeterminate:YES];
	[jpegProgressBar setDoubleValue:0];
	[jpegProgressBar setMaxValue:[a count]];
	[[[[jpegProgressBar window] contentView] viewWithTag:1] setEnabled:[a count] > 1]; // cancel btn
	NSModalSession session = [NSApp beginModalSessionForWindow:[jpegProgressBar window]];
	[NSApp runModalSession:session];
	[jpegProgressBar startAnimation:self];

	unsigned int n;
	NSString *s;
	for (n = 0; n < [a count]; ++n) {
		s = [a objectAtIndex:n];
		if ([DYJpegtran transformImage:ResolveAliasToPath(s) transform:&jinfo]) {
			[thumbsCache removeImageForKey:ResolveAliasToPath(s)];
			[creeveyWindows makeObjectsPerformSelector:@selector(fileWasChanged:) withObject:s];
			// slower, but easier code
			if (slidesWasKey) // remember, progress window is now key
				[slidesWindow displayImage];
		} else {
			// ** fail silently
			//NSLog(@"rot failed!");
		}
		if ([jpegProgressBar isIndeterminate]) {
			[jpegProgressBar stopAnimation:self];
			[jpegProgressBar setIndeterminate:NO];
		}
		[jpegProgressBar incrementBy:1];
		if ([NSApp runModalSession:session] != NSRunContinuesResponse) break;
	}
	[frontWindow updateExifInfo];

	[NSApp endModalSession:session];
	[[jpegProgressBar window] orderOut:self];
}

- (IBAction)stopModal:(id)sender {
	[NSApp stopModal];
}

// returns 1 if successful
// unsuccessful: 0 user wants to continue; 2 cancel/abort
- (char)trashFile:(NSString *)fullpath numLeft:(unsigned int)numFiles {
	int tag;
	if ([[NSWorkspace sharedWorkspace]
performFileOperation:NSWorkspaceRecycleOperation
			  source:[fullpath stringByDeletingLastPathComponent]
		 destination:@""
			   files:[NSArray arrayWithObject:[fullpath lastPathComponent]]
				 tag:&tag]) {
		return 1;
	}
	if (NSRunAlertPanel(nil, //title
						NSLocalizedString(@"The file %@ could not be moved to the trash because an error of %i occurred.", @""),
						NSLocalizedString(@"Cancel", @""),
						(numFiles > 1 ? NSLocalizedString(@"Continue", @"") : nil),
						nil,
						[fullpath lastPathComponent], tag) == NSAlertDefaultReturn)
		return 2;
	return 0;
}

- (IBAction)moveToTrash:(id)sender {
	if ([slidesWindow isKeyWindow]) {
		NSString *s = [slidesWindow currentFile];
		if ([self trashFile:s numLeft:1]) {
			[creeveyWindows makeObjectsPerformSelector:@selector(fileWasDeleted:) withObject:s];
			[thumbsCache removeImageForKey:s];
			[slidesWindow removeImageForFile:s];
		}
	} else {
		NSArray *a = [frontWindow currentSelection];
		unsigned int i, n = [a count];
		// we have to go backwards b/c we're deleting from the imgMatrix
		// wait... we don't, because we're not using indexes anymore
		for (i=0; i < n; ++i) {
			NSString *fullpath = [a objectAtIndex:i];
			char result = [self trashFile:fullpath numLeft:n-i];
			if (result == 1) {
				[thumbsCache removeImageForKey:fullpath]; // we don't resolve alias here, but that's OK
				[creeveyWindows makeObjectsPerformSelector:@selector(fileWasDeleted:) withObject:fullpath];
			} else if (result == 2)
				break;
		}
		[frontWindow updateExifInfo];
	}
}

#pragma mark app delegate methods
//int col = [dirBrowser selectedColumn];
// it's "selected" but not actually first responder
// hence the following convolutions
//	//NSLog(@"setting firstresponder");
//	NSWindow *w = [dirBrowser window];
//	id r = [w firstResponder];
//	do {
//		if (r == dirBrowser) {
//			[w makeFirstResponder:dirBrowser];
//			break;
//		}
//	} while ((r = [r nextResponder]) != w);
//	// i hate NSBrowser
//	//NSLog(@"DONE setting firstresponder");

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	//NSLog(@"appdidfinlaunch called");
	if (!frontWindow) // user didn't drop icons onto app when opening
		[self newWindow:self];
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate];
	if ([u boolForKey:@"autoVersCheck"]
		&& (t - [u floatForKey:@"lastVersCheckTime"] > DYVERSCHECKINTERVAL)) // one week
		if ([[DYVersChecker alloc] initWithNotify:NO])
			[u setFloat:t forKey:@"lastVersCheckTime"];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	if ([creeveyWindows count])
		[frontWindow updateDefaults];
	[u setBool:([slidesWindow isKeyWindow] || [creeveyWindows count] == 0) ? exifWasVisible : [[exifTextView window] isVisible]
		forKey:@"getInfoVisible"];
	[u synchronize];
}


- (void)applicationDidResignActive:(NSNotification *)aNotification {
	[slidesWindow sendToBackground];
}

- (BOOL)application:(NSApplication *)sender
		   openFile:(NSString *)filename {
	if (![creeveyWindows count]) [self newWindow:nil];
	[frontWindow openFiles:[NSArray arrayWithObject:filename]];
	if (sender) {
		[[frontWindow window] makeKeyAndOrderFront:nil];
		//[sender activateIgnoringOtherApps:YES]; // for expose'
	}
	return YES;
}

- (void)application:(NSApplication *)sender
		  openFiles:(NSArray *)files {
	if (![creeveyWindows count]) [self newWindow:nil];
	[frontWindow openFiles:files];
	if (sender) {
		[sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
		[[frontWindow window] makeKeyAndOrderFront:nil];
	}
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag {
	if (![creeveyWindows count]) {
		[self newWindow:self];
		return NO;
	}
	return YES;
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
	JPEG_OP = 100,
	ROTATE_L = 107,
	ROTATE_R = 105
};


- (BOOL)validateMenuItem:(id <NSMenuItem>)menuItem {
	int t = [menuItem tag];
	if (![NSApp mainWindow]) {
		// menu items with tags only enabled if there's a window
		return !t;
	}
	if (t>JPEG_OP) t=JPEG_OP;
	if (![creeveyWindows count]) frontWindow = nil;
	unsigned int numSelected = [[frontWindow selectedIndexes] count];
	BOOL writable, isjpeg;
	
	switch (t) {
		case MOVE_TO_TRASH:
		case JPEG_OP:
			// only when slides isn't loading cache!
			// only if writeable (we just test the first file in the list)
			writable = [slidesWindow isKeyWindow]
				? [slidesWindow currentImageLoaded] &&
					[[NSFileManager defaultManager] isDeletableFileAtPath:
						[slidesWindow currentFile]]
				: numSelected > 0 && [frontWindow currentFilesDeletable];
			isjpeg = [slidesWindow isKeyWindow]
				? FileIsJPEG([slidesWindow currentFile])
				: numSelected > 0 && FileIsJPEG([frontWindow firstSelectedFilename]);
			
			if (t == JPEG_OP) return writable && isjpeg;
			return writable;
			// I don't like the idea of accessing the disk every time the menu
			// is accessed
		case REVEAL_IN_FINDER:
			return YES;
		case BEGIN_SLIDESHOW:
			if ([slidesWindow isKeyWindow] ) return NO;
			return [frontWindow filenamesDone] && [[frontWindow displayedFilenames] count];
		case SET_DESKTOP:
			return [slidesWindow isKeyWindow] || numSelected == 1;
		default:
			return YES;
	}
}

#pragma mark prefs stuff
- (IBAction)openPrefWin:(id)sender; {
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	[startupDirFld setStringValue:[u stringForKey:@"picturesFolderPath"]];
	int i, n = [u integerForKey:@"startupOption"];
	for (i=0; i<2; ++i) {
		[[startupOptionMatrix cellWithTag:i] setState:i==n];
	}
    [prefsWin makeKeyAndOrderFront:nil];
}
- (IBAction)chooseStartupDir:(id)sender; {
    NSOpenPanel *op=[NSOpenPanel openPanel];
	
    [op setCanChooseDirectories:YES];
    [op setCanChooseFiles:NO];
    [op beginSheetForDirectory:[[NSUserDefaults standardUserDefaults] stringForKey:@"picturesFolderPath"]
						  file:NULL types:NULL
				modalForWindow:prefsWin modalDelegate:self
				didEndSelector:@selector(openPanelDidEnd:returnCode:contextInfo:)
				   contextInfo:NULL];
}
- (void)openPanelDidEnd:(NSOpenPanel *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo
{
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	if (returnCode == NSOKButton) {
		NSString *s = [[sheet filenames] objectAtIndex:0];
		[startupDirFld setStringValue:s];
		[u setObject:s forKey:@"picturesFolderPath"];
		[u setInteger:1 forKey:@"startupOption"];
		[[startupOptionMatrix cellWithTag:0] setState:0];
		[[startupOptionMatrix cellWithTag:1] setState:1];
	}
	[sheet orderOut:self];
	[prefsWin makeKeyAndOrderFront:nil]; // otherwise unkeys
}

- (IBAction)changeStartupOption:(id)sender; {
	[[NSUserDefaults standardUserDefaults] setInteger:[[sender selectedCell] tag]
											   forKey:@"startupOption"];
}


- (IBAction)openAboutPanel:(id)sender {
	[NSApp orderFrontStandardAboutPanelWithOptions:
		[NSDictionary dictionaryWithObject:[NSImage imageNamed:@"logo"]
									forKey:@"ApplicationIcon"]];
}





- (IBAction)openGetInfoPanel:(id)sender {
	NSWindow *w = [exifTextView window];
	if ([w isVisible])
		[w orderOut:self];
	else {
		[w orderFront:self];
		if ([creeveyWindows count]) [frontWindow updateExifInfo]; // ** validate if count
	}
}

- (IBAction)newWindow:(id)sender {
	if (![creeveyWindows count]) {
		if (exifWasVisible)
			[[exifTextView window] orderFront:self];
	}
	id wc = [[CreeveyMainWindowController alloc] initWithWindowNibName:@"CreeveyWindow"];
	[creeveyWindows addObject:wc];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowClosed:) name:NSWindowWillCloseNotification object:[wc window]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowChanged:) name:NSWindowDidBecomeMainNotification object:[wc window]];
	[wc showWindow:self]; // or override wdidload
	if (sender)
		[wc setDefaultPath];
}

- (void)windowClosed:(NSNotification *)n {
	id wc = [[n object] windowController];
	if ([creeveyWindows indexOfObjectIdenticalTo:wc] != NSNotFound) {
		if ([creeveyWindows count] == 1) {
			[frontWindow updateDefaults];
			if (exifWasVisible = [[exifTextView window] isVisible]) {
				[[exifTextView window] orderOut:self];
			}
			frontWindow = nil;
		}
		[[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:[wc window]];
		[creeveyWindows removeObject:wc];
		[wc autorelease];
	}
}

- (void)windowChanged:(NSNotification *)n {
	frontWindow = [[n object] windowController];
}

- (IBAction)versionCheck:(id)sender {
	if ([[DYVersChecker alloc] initWithNotify:YES])
		[[NSUserDefaults standardUserDefaults] setFloat:[NSDate timeIntervalSinceReferenceDate]
												 forKey:@"lastVersCheckTime"];
}
- (IBAction)sendFeedback:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://blyt.net/phxslides/feedback.html"]];
}

#pragma mark slideshow window delegate method
- (void)windowDidBecomeKey:(NSNotification *)aNotification {
	if (exifWasVisible = [[exifTextView window] isVisible])
		[[exifTextView window] orderOut:nil];
	// only needed in case user cycles through windows; see startSlideshow above
}
- (void)windowDidResignKey:(NSNotification *)aNotification {
	if (exifWasVisible)
		[[exifTextView window] orderFront:nil];
}


- (DYImageCache *)thumbsCache { return thumbsCache; }
- (NSTextView *)exifTextView { return exifTextView; }
- (NSSet *)filetypes { return filetypes; }
- (NSMutableSet **)cats { return cats; }

@end
