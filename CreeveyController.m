//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "CreeveyController.h"
#import "EpegWrapper.h"
#import "DYCarbonGoodies.h"
#import "NSArrayIndexSetExtension.h"
#import "DirBrowserDelegate.h"

#define MAX_THUMBS 2000

// work around ugly threaded drawing
@implementation DYStatusField
- (void)drawRect:(NSRect)r {
	if (statusText) [self setStringValue:statusText];
	[super drawRect:r];
}

- (void)setStatusText:(NSString *)s {
	[statusText release];
	statusText = [s retain];
	[self setNeedsDisplay:YES];
}

@end

#define DEFAULT_PATH [@"~/Pictures" stringByResolvingSymlinksInPath]

@implementation CreeveyController

+(void)initialize
{
    NSMutableDictionary *dict;
    NSUserDefaults *defaults;
	
    defaults=[NSUserDefaults standardUserDefaults];
	
    dict=[NSMutableDictionary dictionary];
	NSString *s = DEFAULT_PATH;
    [dict setObject:s forKey:@"picturesFolderPath"];
    [dict setObject:s forKey:@"lastFolderPath"];
    [dict setObject:[NSNumber numberWithShort:0] forKey:@"startupOption"];
    [defaults registerDefaults:dict];
	
	[RBSplitView class];
}

- (id)init {
	if (self = [super init]) {
		filetypes = [[NSSet alloc] initWithArray:[NSImage imageFileTypes]];
			//@"jpg", @"jpeg," @"gif",
			//@"tif", @"tiff", @"pict", @"pdf", @"icns", nil];
		//hfstypes = [[NSSet alloc] initWithObjects:@"'PICT'", @"'JPEG'", @"'GIFf'",
		//	@"'TIFF'", @"'PDF '", nil]; // need those single quotes
		//NSLog(@"%@", [NSImage imageFileTypes]);
		filenames = [[NSMutableArray alloc] init];
		thumbsCacheLock = [[NSLock alloc] init];
		filesBeingOpened = [[NSMutableSet alloc] init];
	}
    return self;
}

- (void)awakeFromNib {
	[imgMatrix setFrameSize:[[imgMatrix superview] frame].size];
	thumbsCache = [[DYImageCache alloc] initWithCapacity:MAX_THUMBS];
	[thumbsCache setBoundingSize:[imgMatrix cellSize]];
	[dirBrowser loadColumnZero]; // or else NSBrowser chokes if it's in a collapsed subview
	[splitView restoreState:YES];
	[splitView adjustSubviews];
}

- (void)dealloc {
	[filenames release];
	[thumbsCache release];
	[thumbsCacheLock release];
	[super dealloc];
}

- (void)updateStatusFld {
	[statusFld setStatusText:[NSString stringWithFormat:NSLocalizedString(@"%u images", @""),
		[filenames count]]];
}

- (void)loadImages:(NSString *)thePath { // called in a separate thread
	//NSLog(@"loadImages thread started for %@", thePath);
	[thePath retain];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSTimeInterval myThreadTime; // assume (incorrectly?) that threads will be executed in the order detached
	myThreadTime = lastThreadTime = [NSDate timeIntervalSinceReferenceDate];
	[thumbsCacheLock lock];
	if (myThreadTime < lastThreadTime) {
		//NSLog(@"stale thread aborted, %@", thePath);
		[filesBeingOpened removeAllObjects];
		[thePath release];
		[pool release];
		[thumbsCacheLock unlock];
		return;
	}
	stopCaching = NO;
	
	int i = 0;
	NSFileManager *fm = [NSFileManager defaultManager];
	if (thePath) {
		[imgMatrix removeAllImages];
		[filenames removeAllObjects];
		NSDirectoryEnumerator *e = [fm enumeratorAtPath:thePath];
		id obj;
		//NSLog(@"getting filenames...");
		while (obj = [e nextObject]) {
			NSString *aPath = [thePath stringByAppendingPathComponent:obj];
			NSString *theFile = ResolveAliasToPath(aPath);
			BOOL isInvisible = [obj characterAtIndex:0] == '.' || FileIsInvisible(aPath);
			// don't need to worry about top level .hidden here
			
			if ([[[e fileAttributes] fileType] isEqualToString:NSFileTypeDirectory]) {
				if (!recurseSubfolders || (!showInvisibles && isInvisible))
					[e skipDescendents];
				continue;
			}
			if (!showInvisibles && isInvisible)
				continue; // skip invisible files
			if (([filetypes containsObject:[theFile pathExtension]]
				 || [filetypes containsObject:NSHFSTypeOfFile(theFile)]))
			{	
				[filenames addObject:aPath];
				if (++i % 100 == 0)
					[statusFld setStatusText:[NSString stringWithFormat:@"%@ (%i)",
						NSLocalizedString(@"Getting filenames...", @""), i]];
			}
			//		  NSFileTypeForHFSTypeCode([[atts objectForKey:NSFileHFSCreatorCode] unsignedLongValue]),
			if (stopCaching) {
				[filenames removeAllObjects];
				break;
			}
		}
		filenamesDone = YES;
	}
	//NSLog(@"got %d files.", [filenames count]);
	if ([filenames count] > 0) {

	[slidesBtn setEnabled:YES];
	currentFilesDeletable = [fm isDeletableFileAtPath:[filenames objectAtIndex:0]];
	
	int numFiles = [filenames count];
	// ** int maxThumbs = MAX(MAX_THUMBS,numFiles+numToDelete);
	NSSize cellSize = [imgMatrix cellSize];
	NSImage *thumb;
	NSString *origPath, *theFile;
	
	for (i=thePath ? 0 : [imgMatrix numCells]; i<numFiles; ++i) {
		if (stopCaching || myThreadTime < lastThreadTime) {
			//NSLog(@"aborted %@", origPath);
			break; // stop if user has moved on
		}
		
		origPath = [filenames objectAtIndex:i];
		theFile = ResolveAliasToPath(origPath);
		//[thumbsCache sleepIfPending:theFile]; // ** could also move on and callback?
		thumb = [thumbsCache imageForKey:theFile];
		if (!thumb) {
			//NSLog(@"caching %d", i);
			[statusFld setStatusText:[NSString stringWithFormat:NSLocalizedString(@"Loading %i of %u...", @""), i+1, numFiles]];
			if ([[[theFile pathExtension] lowercaseString] isEqualToString:@"jpg"]
				|| [NSHFSTypeOfFile(theFile) isEqualToString:@"JPEG"]) {
				thumb = [EpegWrapper imageWithPath:theFile boundingBox:cellSize];
				if (!thumb)
					NSLog(@"Epeg error: %@", [EpegWrapper jpegErrorMessage]);
				else
					[thumbsCache addImage:thumb forFile:theFile];
			} else {
				[thumbsCache cacheFile:theFile]; // will sleep if pending
				thumb = [thumbsCache imageForKey:theFile];
			}
			if (!thumb) {
				NSLog(@"couldn't load image %@", origPath);
				thumb = [NSImage imageNamed:@"brokendoc"];
			}
		}
		// check after a long caching op
		if (stopCaching || myThreadTime < lastThreadTime) {
			//NSLog(@"aborted2 %@", origPath);
			break; // stop if user has moved on
		}
		[imgMatrix addImage:thumb withFilename:origPath];
		if ([filesBeingOpened containsObject:origPath])
			[imgMatrix addSelectedIndex:i];
		//NSLog(@"%@", thumb);
	}
	}
	if (myThreadTime == lastThreadTime)
		[self performSelectorOnMainThread:@selector(updateStatusFld)
							   withObject:nil
							waitUntilDone:NO];
	[filesBeingOpened removeAllObjects];
	[thumbsCacheLock unlock];
	[pool release];
	[thePath release];
}

- (IBAction)displayDir:(id)sender {
	// appkit drawing issues
	// nsbrowser animation hangs the app!
	stopCaching = YES;	
	currentFilesDeletable = NO;
	filenamesDone = NO;
	[slidesBtn setEnabled:NO];
	NSString *currentPath = [dirBrowser path];
	[statusFld setStatusText:NSLocalizedString(@"Getting filenames...", @"")];
	[[dirBrowser window] setTitleWithRepresentedFilename:currentPath];
	[slidesWindow setBasePath:currentPath];
	[NSThread detachNewThreadSelector:@selector(loadImages:)
							 toTarget:self withObject:currentPath];
}

- (void)startSlideshow {
	stopCaching = YES;
	NSIndexSet *s = [imgMatrix selectedIndexes];
	[slidesWindow setFilenames:[s count] > 1
		? [filenames subarrayWithIndexSet:s]
		: filenames];
	[slidesWindow startSlideshowAtIndex: [s count] == 1 ? [s firstIndex] : 0];
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
		NSIndexSet *s = [imgMatrix selectedIndexes];
		if ([s count])
			RevealItemsInFinder([filenames subarrayWithIndexSet:s]);
		else
			[[NSWorkspace sharedWorkspace] openFile:[dirBrowser path]];
	}
}

- (IBAction)setRecurseSubfolders:(id)sender {
	recurseSubfolders = [sender state] == NSOnState;
	[self displayDir:nil];
}

- (IBAction)setDesktopPicture:(id)sender {
	NSString *s = [slidesWindow isKeyWindow]
	? [slidesWindow currentFile]
	: [filenames objectAtIndex:[[imgMatrix selectedIndexes] firstIndex]];
	OSErr err = SetDesktopPicture(ResolveAliasToPath(s),0);
	if (err != noErr) {
		NSLog(@"couldn't set desktop, err %d", err);
		// **
	}
}

- (void)selectAll:(id)sender{
	[imgMatrix selectAll:sender];
}

- (void)selectNone:(id)sender{
	[imgMatrix selectNone:sender];
}

// returns YES if successful
// unsuccessful: 0 user wants to continue; -1 cancel/abort
- (char)trashFile:(NSString *)fullpath numLeft:(unsigned int)numFiles {
	int tag;
	if ([[NSWorkspace sharedWorkspace]
performFileOperation:NSWorkspaceRecycleOperation
			  source:[fullpath stringByDeletingLastPathComponent]
		 destination:@""
			   files:[NSArray arrayWithObject:[fullpath lastPathComponent]]
				 tag:&tag]) {
		return YES;
	}
	if (NSRunAlertPanel(nil, //title
						NSLocalizedString(@"The file %@ could not be moved to the trash because an error of %i occurred.", @""),
						@"Cancel", (numFiles > 1 ? @"Continue" : nil), nil,
						[fullpath lastPathComponent], tag) == NSAlertDefaultReturn)
		return -1;
	return 0;
}

- (IBAction)moveToTrash:(id)sender {
	if ([slidesWindow isKeyWindow]) {
		NSString *s = [slidesWindow currentFile];
		if ([self trashFile:s numLeft:1]) {
			unsigned i = [filenames indexOfObject:[slidesWindow currentFile]];
			if (i != NSNotFound) {
				if (i < [imgMatrix numCells]) // ** copied from below
					[imgMatrix removeImageAtIndex:i];
				[filenames removeObjectAtIndex:i];
			}
			[thumbsCache removeImageForKey:s];
			[slidesWindow removeImageForFile:s];
		}
	} else {
		stopCaching = YES;
		[thumbsCacheLock lock];
		NSIndexSet *s = [imgMatrix selectedIndexes];
		unsigned int i, n = [s count];
		// not the most efficient code, but it's amusing
		// we have to go backwards b/c we're deleting from the imgMatrix
		for (i=[s lastIndex]; i != NSNotFound; i = [s indexLessThanIndex:i]) {
			NSString *fullpath = [filenames objectAtIndex:i];
			char result = [self trashFile:fullpath numLeft:n--];
			if (result) {
				if (i < [imgMatrix numCells]) // imgMatrix might not have loaded it yet!
					[imgMatrix removeImageAtIndex:i];
				[thumbsCache removeImageForKey:fullpath]; // we don't resolve alias here, but that's OK
				[filenames removeObjectAtIndex:i]; // do this last, it invalidates fullpath!
			} else if (result == -1)
				break;
		}
		//NSLog(@"%@", [[NSWorkspace sharedWorkspace] mountedRemovableMedia]);
		[thumbsCacheLock unlock];
		if ([imgMatrix numCells] < [filenames count])
			[NSThread detachNewThreadSelector:@selector(loadImages:)
									 toTarget:self withObject:nil]; // **
	}
	[self updateStatusFld];
	if ([imgMatrix numCells] == 0)
		[slidesBtn setEnabled:NO];
}

- (void)keyDown:(NSEvent *)e {
	NSWindow *w = [imgMatrix window];
	[w makeFirstResponder:imgMatrix];
	[imgMatrix keyDown:e];
	[w makeFirstResponder:dirBrowser];
}

// returns NO if doesn't exist, useful for applicationDidFinishLaunching
- (BOOL)openFile:(NSString *)filename {
	//NSLog(@"openfile called");
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL isDir;
	if (![fm fileExistsAtPath:filename isDirectory:&isDir])
		return NO;
	//NSLog(@"file exists");
	if (!isDir)
		filename = [filename stringByDeletingLastPathComponent];
	if (![dirBrowser setPath:filename]) {
		//NSLog(@"retrying as invisible");
		showInvisibles = YES;
		[[dirBrowser delegate] setShowInvisibles:YES];
		[dirBrowser loadColumnZero]; // ** i guess this should be in the delegate class
		[dirBrowser setPath:filename];
	}
	//NSLog(@"sending action");
	[dirBrowser sendAction];
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
	return YES;
}

// app delegate methods
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	//NSLog(@"appdidfinlaunch called");
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	//NSLog(@"got userdefaults");
	NSString *s = [u integerForKey:@"startupOption"] == 0
		? [u stringForKey:@"lastFolderPath"]
		: [u stringForKey:@"picturesFolderPath"];
	//NSLog(@"got my path");
	if (lastThreadTime == 0) // user didn't drop icons onto app when opening
		if (![self openFile:s])
			if (![self openFile:DEFAULT_PATH])
				[self openFile:NSHomeDirectory()];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	if ([u integerForKey:@"startupOption"] == 0)
		[u setObject:[dirBrowser path] forKey:@"lastFolderPath"];
}


- (void)applicationDidResignActive:(NSNotification *)aNotification {
	[slidesWindow sendToBackground];
}

- (BOOL)application:(NSApplication *)sender
		   openFile:(NSString *)filename {
	[filesBeingOpened addObject:filename];
	[self openFile:filename];
	if (sender) {
		[[imgMatrix window] makeKeyAndOrderFront:nil];
		//[sender activateIgnoringOtherApps:YES]; // for expose'
	}
	return YES;
}

- (void)application:(NSApplication *)sender
		  openFiles:(NSArray *)files {
	[filesBeingOpened addObjectsFromArray:files];
	[self openFile:[files objectAtIndex:0]];
	if (sender) {
		[sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
		[[imgMatrix window] makeKeyAndOrderFront:nil];
		//[sender activateIgnoringOtherApps:YES]; // for expose'
	}
}

// window delegate methods
- (void)windowDidBecomeKey:(NSNotification *)aNotification {
//	if ([slidesWindow isVisible])
//		[slidesWindow endSlideshow];
	if ([imgMatrix numCells] < [filenames count] && stopCaching)
		[NSThread detachNewThreadSelector:@selector(loadImages:)
								 toTarget:self withObject:nil];
	//reload if unfinished, but let current thread finish if there is one
	//pass nil to mean continue where we left off
}

// menu methods
enum {
	REVEAL_IN_FINDER = 1,
	MOVE_TO_TRASH,
	LOOP,
	BEGIN_SLIDESHOW,
	SET_DESKTOP
};

- (BOOL)validateMenuItem:(id <NSMenuItem>)menuItem {
	int t = [menuItem tag];
	unsigned int numSelected = [[imgMatrix selectedIndexes] count];
	switch (t) {
		case MOVE_TO_TRASH:
			// only when slides isn't loading cache!
			// only if writeable (we just test the first file in the list)
			if ([slidesWindow isKeyWindow]) {
				return [slidesWindow currentImageLoaded] &&
				[[NSFileManager defaultManager] isDeletableFileAtPath:
					[slidesWindow currentFile]];
			}
			return numSelected > 0 && currentFilesDeletable;
			// I don't like the idea of accessing the disk every time the menu
			// is accessed
		case REVEAL_IN_FINDER:
			return YES;// [slidesWindow isKeyWindow] || numSelected > 0;
		case BEGIN_SLIDESHOW:
			if (![[imgMatrix window] isKeyWindow]) return NO;
			return filenamesDone && [filenames count] > 0;
		case SET_DESKTOP:
			return [slidesWindow isKeyWindow] || numSelected == 1;
		default:
			return [[imgMatrix window] isKeyWindow];
	}
	// select all here
}


// prefs stuff
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

#pragma mark splitview delegate methods
- (void)splitView:(RBSplitView*)sender wasResizedFrom:(float)oldDimension to:(float)newDimension {
	[sender adjustSubviewsExcepting:[sender subviewAtPosition:0]];
}
@end
