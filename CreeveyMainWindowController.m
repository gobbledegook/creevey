//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#include "stdlib.h"

#import "CreeveyMainWindowController.h"
#import "EpegWrapper.h"
#import "DYCarbonGoodies.h"
#import "DirBrowserDelegate.h"
#import "NSStringDYBasePathExtension.h"

#import "CreeveyController.h"
#import "DYCreeveyBrowser.h"
#import "DYImageCache.h"
#import "DYWrappingMatrix.h"

@implementation NSString (DateModifiedCompare)

- (NSComparisonResult)dateModifiedCompare:(NSString *)other
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSComparisonResult r = NSOrderedSame;
	NSDate *aDate = [[fm attributesOfItemAtPath:[self stringByResolvingSymlinksInPath] error:NULL] fileModificationDate];
	NSDate *bDate = [[fm attributesOfItemAtPath:[other stringByResolvingSymlinksInPath] error:NULL] fileModificationDate];
	// dates will be nil on error
	if (aDate != nil || bDate != nil)
		r = [aDate compare:bDate];
	if (r == NSOrderedSame) { // use file name comparison as fallback; filenames are guaranteed to be unique, but mod times are not
		return [self localizedStandardCompare:other];
	}
	return r;
}

@end


@interface CreeveyMainWindowController ()
- (void)updateStatusFld;
@property (nonatomic, readonly) NSSplitView *splitView;
@property (nonatomic, retain) NSString *recurseRoot;
@end

@implementation CreeveyMainWindowController

- (id)initWithWindowNibName:(NSString *)windowNibName {
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
		appDelegate = (CreeveyController *)[NSApp delegate];
		[NSThread detachNewThreadSelector:@selector(thumbLoader:) toTarget:self withObject:nil];
	}
    return self;
}

- (void)awakeFromNib {
	[[self window] setFrameUsingName:@"MainWindowLoc"];
	// otherwise it uses the frame in the nib
	
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	NSSplitView *splitView = self.splitView;
	float height = [u floatForKey:@"MainWindowSplitViewTopHeight"];
	if (height > 0.0) [splitView setPosition:height ofDividerAtIndex:0];
	[splitView setDelegate:self]; // must set delegate after restoring position so the didResize notification doesn't save the height from the nib

	[imgMatrix setFrameSize:[[imgMatrix superview] frame].size];
	[imgMatrix setMaxCellWidth:[u integerForKey:@"DYWrappingMatrixMaxCellWidth"]];
	[imgMatrix setCellWidth:[u floatForKey:@"thumbCellWidth"]];
	[[self window] setRestorationClass:[CreeveyController class]];
	
	dirBrowserDelegate = [dirBrowser delegate];
}

- (void)window:(NSWindow *)window willEncodeRestorableState:(NSCoder *)state
{
	NSDictionary *data = @{@"path":[self path], @"split1":@(statusFld.superview.frame.size.height)};
	[state encodeObject:data forKey:@"creeveyWindowState"];
}

- (void)window:(NSWindow *)window didDecodeRestorableState:(NSCoder *)state
{
	NSDictionary *data = [state decodeObjectForKey:@"creeveyWindowState"];
	if (![data isKindOfClass:[NSDictionary class]]) data = @{};
	NSString *path = data[@"path"];
	if (![path isKindOfClass:[NSString class]]) path = nil;
	if (path == nil || ![self setPath:path])
		if (![self setPath:[[NSUserDefaults standardUserDefaults] stringForKey:@"picturesFolderPath"]])
			[self setPath:NSHomeDirectory()];
	NSNumber *heightObj = data[@"split1"];
	float height;
	if ([heightObj isKindOfClass:[NSNumber class]]) {
		height = [heightObj floatValue];
	} else {
		height = 0;
	}
	if (height > 0.0)
		[self.splitView setPosition:height ofDividerAtIndex:0];
}

- (NSSplitView *)splitView
{
	return [[[self window] contentView] subviews][0];
}

- (void)dealloc {
	[_recurseRoot release];
	[filenames release];
	[displayedFilenames release];
	[loadImageLock release];
	[filesBeingOpened release];
	[imageCacheQueueLock release];
	[imageCacheQueue release];
	[secondaryImageCacheQueue release];
	[super dealloc];
}

- (void)windowWillClose:(NSNotification *)notification {
	imageCacheQueueRunning = NO;
	[imageCacheQueueLock lock];
	[imageCacheQueueLock unlockWithCondition:1];
}


#pragma mark sorting stuff
- (DYWrappingMatrix *)imageMatrix { return imgMatrix; }
- (short int)sortOrder {	return sortOrder; }
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

// returns NO if doesn't exist, useful for applicationDidFinishLaunching
- (BOOL)setPath:(NSString *)s {
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL isDir;
	if (![fm fileExistsAtPath:s isDirectory:&isDir])
		return NO;
	if (!isDir)
		s = [s stringByDeletingLastPathComponent];
	[dirBrowserDelegate setPath:s];
	[dirBrowser sendAction];
	[[self window] invalidateRestorableState];
	return YES;
}

- (void)setDefaultPath {
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	NSString *s = [u integerForKey:@"startupOption"] == 0
		? [u stringForKey:@"lastFolderPath"]
		: [u stringForKey:@"picturesFolderPath"];
	if (![self setPath:s])
		if (![self setPath:CREEVEY_DEFAULT_PATH])
				[self setPath:NSHomeDirectory()];
	[[self window] makeFirstResponder:dirBrowser]; //another stupid workaround, for hiliting
	
}

- (BOOL)pathIsVisible:(NSString *)filename {
	NSString *browserPath = [dirBrowserDelegate path];
	if (recurseSubfolders) return [filename hasPrefix:browserPath];
	return [[filename stringByDeletingLastPathComponent] isEqualToString:browserPath];
}

- (BOOL)pathIsVisibleThreaded:(NSString *)filename {
	NSString *browserPath = dirBrowserDelegate.savedPath;
	if (recurseSubfolders) return [filename hasPrefix:browserPath];
	return [[filename stringByDeletingLastPathComponent] isEqualToString:browserPath];
}

- (void)updateDefaults {
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	if ([u integerForKey:@"startupOption"] == 0)
		[u setObject:[dirBrowserDelegate path] forKey:@"lastFolderPath"];
	[u setFloat:[imgMatrix cellWidth] forKey:@"thumbCellWidth"];
	[[self window] saveFrameUsingName:@"MainWindowLoc"];
}


- (BOOL)currentFilesDeletable { return currentFilesDeletable; }
- (BOOL)filenamesDone { return filenamesDone; }
- (NSArray *)displayedFilenames { return displayedFilenames; }

- (NSString *)firstSelectedFilename {
	return [imgMatrix firstSelectedFilename];
}
- (NSArray *)currentSelection {
	return [imgMatrix selectedFilenames];
}
- (NSIndexSet *)selectedIndexes {
	return [imgMatrix selectedIndexes];
}
- (void)selectIndex:(NSUInteger)i {
	[imgMatrix selectIndex:i];
}

- (void)openFiles:(NSArray *)a withSlideshow:(BOOL)doSlides{
	if (doSlides) {
		startSlideshowWhenReady = YES;
		for (NSString *theFile in a) {
			if ([appDelegate shouldShowFile:ResolveAliasToPath(theFile)])
				[filesBeingOpened addObject:theFile];
		}
	} else {
		startSlideshowWhenReady = NO;
		[filesBeingOpened addObjectsFromArray:a];
	}

	[self setPath:a[0]];
}

- (void)fileWasChanged:(NSString *)s {
	if (![self pathIsVisible:s]) return;
	// update thumb
	DYImageCache *thumbsCache = [appDelegate thumbsCache];
	NSString *theFile = ResolveAliasToPath(s);
	NSImage *thumb = [thumbsCache imageForKey:theFile];
	if (!thumb) { // ** dup
		if ([thumbsCache attemptLockOnFile:theFile]) {
			DYImageInfo *result;
			result = [[DYImageInfo alloc] initWithPath:theFile];
			result->image =
				[EpegWrapper imageWithPath:theFile
							   boundingBox:[DYWrappingMatrix maxCellSize]
								   getSize:&result->pixelSize
								 exifThumb:NO
							getOrientation:&result->exifOrientation];
			if (!result->image) [thumbsCache createScaledImage:result];
			if (result->image) [thumbsCache addImage:result forFile:theFile];
			else [thumbsCache dontAddFile:theFile];
			thumb = result->image;
			[result release];
		} else {
			thumb = [thumbsCache imageForKey:theFile];
		}
	}
	if (!thumb) thumb = [NSImage imageNamed:@"brokendoc.tif"];
	NSUInteger mtrxIdx = [[imgMatrix filenames] indexOfObject:s];
	if (mtrxIdx != NSNotFound)
		[imgMatrix setImage:thumb forIndex:mtrxIdx];
}
	
- (void)fileWasDeleted:(NSString *)s {
	if (![self pathIsVisible:s]) return;
	NSUInteger mtrxIdx, i = [filenames indexOfObject:s];
	// ** linear search; should we make faster?
	if (i != NSNotFound) {
		stopCaching = 1;
		[loadImageLock lock];
		
		if ((mtrxIdx = [[imgMatrix filenames] indexOfObject:s]) != NSNotFound)
			[imgMatrix removeImageAtIndex:mtrxIdx]; // more linear searches
		[displayedFilenames removeObject:s];
		[filenames removeObjectAtIndex:i];
		
		[loadImageLock unlock];
		if (!filenamesDone || !loadingDone) //[imgMatrix numCells] < [filenames count])
			[NSThread detachNewThreadSelector:@selector(loadImages:)
									 toTarget:self
								   withObject:filenamesDone ? [dirBrowserDelegate path] : nil];
		// must check filenamesDone in case interrupted
		[self updateStatusFld];
		if ([imgMatrix numCells] == 0)
			[slidesBtn setEnabled:NO]; // **
	}
}


- (void)setStatusString:(NSString *)s {
	[NSObject cancelPreviousPerformRequestsWithTarget:statusFld];
	// this fixes weird display issues
	[statusFld performSelectorOnMainThread:@selector(setStringValue:)
								withObject:s
							 waitUntilDone:NO];
}

- (void)updateStatusFld {
	id s = NSLocalizedString(@"%u images", @"");
	[statusFld setStringValue:currCat
		? [NSString stringWithFormat:@"%@: %@",
			[NSString stringWithFormat:NSLocalizedString(@"Group %i", @""), currCat],
			[NSString stringWithFormat:s, [displayedFilenames count]]]
		: [NSString stringWithFormat:s, [filenames count]]];
}

#pragma mark load thread
- (void)loadImages:(NSString *)thePath { // called in a separate thread
										 //NSLog(@"loadImages thread started for %@", thePath);
	[thePath retain];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	// assume (incorrectly?) that threads will be executed in the order detached
	// better to set in loadDir and pass it in?
	NSTimeInterval myThreadTime;
	myThreadTime = lastThreadTime = [NSDate timeIntervalSinceReferenceDate];
	// setting stopCaching stops only one thread (see below)
	// if there's a backlog of several threads, need to check thread time instead
	[loadImageLock lock];
	if (myThreadTime < lastThreadTime) {
		//NSLog(@"stale thread aborted, %@", thePath);
		[filesBeingOpened removeAllObjects];
		[thePath release];
		[pool release];
		[loadImageLock unlock];
		return;
	}
	stopCaching = 0;
	
	NSUInteger i = 0;
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *loadingMsg = NSLocalizedString(@"Getting filenames...", @"");
		// pull this function call out of the loop
	//NSTimeInterval imgloadstarttime = [NSDate timeIntervalSinceReferenceDate];
	
	if (thePath) {
		[imgMatrix removeAllImages];
		[filenames removeAllObjects];
		[displayedFilenames removeAllObjects];
		[imageCacheQueueLock lock];
		[imageCacheQueue removeAllObjects];
		[secondaryImageCacheQueue removeAllObjects];
		[imageCacheQueueLock unlockWithCondition:0];
		NSDirectoryEnumerationOptions options = recurseSubfolders ? 0 : NSDirectoryEnumerationSkipsSubdirectoryDescendants;
		options |= NSDirectoryEnumerationSkipsHiddenFiles;
		NSDirectoryEnumerator *e = [fm enumeratorAtURL:[NSURL fileURLWithPath:thePath isDirectory:YES]
							includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLNameKey]
											   options:options errorHandler:nil];
		//NSLog(@"getting filenames...");
		for (NSURL *url in e) {
			NSNumber *isDirectory;
			[url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
			if ([isDirectory boolValue]) {
				NSString *filename;
				[url getResourceValue:&filename forKey:NSURLNameKey error:NULL];
				if ([filename isEqualToString:@"Thumbs"])
					[e skipDescendents]; // special addition for mbatch
				continue;
			}

			NSString *aPath = [url path];
			NSString *theFile = ResolveAliasToPath(aPath);
			if ([appDelegate shouldShowFile:theFile])
			{
				[filenames addObject:aPath];
				if (++i % 100 == 0)
					[self setStatusString:[NSString stringWithFormat:@"%@ (%lu)",
						loadingMsg, (unsigned long)i]];
			}
			if (stopCaching == 1) {
				[filenames removeAllObjects]; // so it fails count > 0 test below
				break;
			}
		}
		[displayedFilenames addObjectsFromArray:filenames];
	} else if (currCat) { // currCat > 0 whenever cat changes (see keydown)
		// this means deleting when a cat is displayed will cause unsightly flashing
		// but we can live with that for now. maybe temp set currcat to 0?
		[imgMatrix removeAllImages];
		[imageCacheQueueLock lock];
		[imageCacheQueue removeAllObjects];
		[secondaryImageCacheQueue removeAllObjects];
		[imageCacheQueueLock unlockWithCondition:0];
		[displayedFilenames removeAllObjects];
		if (currCat == 1) {
			currCat = 0;
			[displayedFilenames addObjectsFromArray:filenames];
		} else {
			for (NSString *path in filenames) {
				if ([[appDelegate cats][currCat-2] containsObject:path])
					[displayedFilenames addObject:path];
			}
		}
	} else { // if we got here, that means the sort order changed and currCat == 0
		[imgMatrix removeAllImages];
		[imageCacheQueueLock lock];
		[imageCacheQueue removeAllObjects];
		[secondaryImageCacheQueue removeAllObjects];
		[imageCacheQueueLock unlockWithCondition:0];
	}
	if (startSlideshowWhenReady) {
		startSlideshowWhenReady = NO;
		// set this back to NO so we don't get infinite slideshow looping if a category is selected (initiated by windowDidBecomeMain:)
		if ([filesBeingOpened count]) {
			[appDelegate performSelectorOnMainThread:@selector(slideshowFromAppOpen:)
											   withObject:[filesBeingOpened allObjects] // make a copy
											waitUntilDone:NO];
		}
	}
	if (abs(sortOrder) == 1) {
		[displayedFilenames sortUsingSelector:@selector(localizedStandardCompare:)];
	} else {
		[displayedFilenames sortUsingSelector:@selector(dateModifiedCompare:)];
	}
	if (sortOrder < 0 && [displayedFilenames count]) {
		// reverse the array
		NSUInteger a, b;
		a = 0;
		b = [displayedFilenames count]-1;
		while (a < b) {
			[displayedFilenames exchangeObjectAtIndex:a withObjectAtIndex:b];
			a++; b--;
		}
	}
	filenamesDone = YES;

	//NSLog(@"got %d files.", [filenames count]);
	[pool release];
	pool = [[NSAutoreleasePool alloc] init];
		
	NSMutableIndexSet *selectedIndexes = [NSMutableIndexSet indexSet];
	if ([displayedFilenames count] > 0) {
		loadingDone = NO;
		dispatch_async(dispatch_get_main_queue(), ^{
			[slidesBtn setEnabled:YES];
		});
		currentFilesDeletable = [fm isDeletableFileAtPath:displayedFilenames[0]];
		
		NSUInteger numFiles = [displayedFilenames count];
		NSUInteger maxThumbs = [[NSUserDefaults standardUserDefaults]
								  integerForKey:@"maxThumbsToLoad"];
		
		[NSThread setThreadPriority:0.2];
		for (i=thePath ? 0 : [imgMatrix numCells]; i<numFiles; ++i) {
			if (stopCaching) {
				//NSLog(@"aborted1 %@", origPath);
				if (stopCaching == 1)
					break;
				[NSThread sleepForTimeInterval:0.1];
			}
			
			NSString *origPath = displayedFilenames[i];
			[imgMatrix addImage:nil withFilename:origPath];
			if ([filesBeingOpened containsObject:origPath])
				[selectedIndexes addIndex:i];

			// now, to simulate the original behavior, add a certain number of
			// images to the queue automatically
			if (i < maxThumbs) {
				[imageCacheQueueLock lock];
				NSMutableDictionary *d = [[NSMutableDictionary alloc] initWithCapacity:3];
				d[@"filename"] = origPath;
				d[@"index"] = @(i);
				[secondaryImageCacheQueue addObject:[d autorelease]];
				[imageCacheQueueLock unlockWithCondition:1];
			}
		}
	}
	loadingDone = (i==[displayedFilenames count]);
	/*if (i) {
		NSTimeInterval delta = [NSDate timeIntervalSinceReferenceDate] - imgloadstarttime;
		NSLog(@"%d files/%f secs = %f/s; %f s/file", i, delta,
			  i / delta, delta/i);
	}*/
	if (myThreadTime == lastThreadTime)
		[self performSelectorOnMainThread:@selector(updateStatusFld)
							   withObject:nil
							waitUntilDone:NO];
	if (loadingDone && filesBeingOpened.count) {
		[filesBeingOpened removeAllObjects];
		if (myThreadTime == lastThreadTime && selectedIndexes.count)
			dispatch_async(dispatch_get_main_queue(), ^{
				[imgMatrix scrollToFirstSelected:selectedIndexes];
			});
	}
	[loadImageLock unlock];
	[pool release];
	[thePath release];
}

- (IBAction)displayDir:(id)sender {
	stopCaching = 1;
	currentFilesDeletable = NO;
	filenamesDone = NO;
	currCat = 0;
	[slidesBtn setEnabled:NO];
	NSString *currentPath = [dirBrowserDelegate path];
	if (recurseSubfolders && sender) { // sender is dirBrowserDelegate when non-nil
		if (![currentPath hasPrefix:_recurseRoot]) {
			recurseSubfolders = NO;
			[_subfoldersButton setState:NSControlStateValueOff];
		}
	}
	[statusFld setStringValue:NSLocalizedString(@"Getting filenames...", @"")];
	[[self window] setTitleWithRepresentedFilename:currentPath];
	[NSThread detachNewThreadSelector:@selector(loadImages:)
							 toTarget:self withObject:currentPath];
}

- (IBAction)setRecurseSubfolders:(id)sender {
	recurseSubfolders = [sender state] == NSOnState;
	// remember where we started recursing subfolders
	if (recurseSubfolders) {
		NSString *path = [dirBrowserDelegate path];
		// but don't reset if we're still in a subfolder from the last time this was set
		if (_recurseRoot == nil || ![path hasPrefix:_recurseRoot])
			// add a slash so we continue recursing for any sibling folders, but not the parent folder
			self.recurseRoot = [[[dirBrowserDelegate path] stringByDeletingLastPathComponent] stringByAppendingString:@"/"];
	} else {
		// if user aborted, assume that's not a good place to recurse
		if (!filenamesDone)
			self.recurseRoot = nil;
	}
	[self displayDir:nil];
}


#pragma mark menu stuff
- (void)selectAll:(id)sender{
	[[self window] makeFirstResponder:imgMatrix];
	[imgMatrix selectAll:sender];
}

- (void)selectNone:(id)sender{
	[imgMatrix selectNone:sender];
}


#pragma mark event stuff
- (void)fakeKeyDown:(NSEvent *)e {
	[[self window] makeFirstResponder:imgMatrix];
	[imgMatrix keyDown:e];
	[[self window] makeFirstResponder:dirBrowser];
}

- (void)keyDown:(NSEvent *)e {
	if ([[e characters] length] == 0) return;
	unichar c = [[e characters] characterAtIndex:0];
	if (filenamesDone && c >= NSF1FunctionKey && c <= NSF12FunctionKey) {
		c = c - NSF1FunctionKey + 1;
		if (([e modifierFlags] & NSEventModifierFlagCommand) != 0) {
			NSUInteger i;
			short j;
			NSArray *a = [imgMatrix selectedFilenames];
			if (![a count]) {
				NSBeep();
				return;
			}
			
			NSMutableSet **cats = [appDelegate cats];
			for (i=[a count]-1; i != -1; i--) { // TODO: this code is suspect
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
			if (!currCat || (c && c != currCat)) {
				[statusFld setStringValue:[NSString stringWithFormat:
					NSLocalizedString(@"%u image(s) updated for Group %i", @""),
					(unsigned int)[a count], c]];
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
		[slidesBtn setEnabled:NO];
		[NSThread detachNewThreadSelector:@selector(loadImages:)
								 toTarget:self
							   withObject:nil];
		return;
	}
	[super keyDown:e];
}


#pragma mark window delegate methods
- (void)windowDidResignMain:(NSNotification *)aNotification {
	if (!filenamesDone || !loadingDone) {
		stopCaching = 2;
	}
}

- (void)windowDidBecomeMain:(NSNotification *)aNotification {
	[self updateExifInfo];
	if (!filenamesDone || !loadingDone)// && stopCaching)
		stopCaching = 0;
	if (filenamesDone && currCat) { // reload in case category membership of certain files changed;
		// ** we should probably notify when cats change instead
		// ** and also handle the case where you change something's category so it no longer belongs in the current view
		stopCaching = 1;
		[loadImageLock lock];
		// make reloading less bad by saving selection
		[filesBeingOpened addObjectsFromArray:[imgMatrix selectedFilenames]];
		[loadImageLock unlock];
		[NSThread detachNewThreadSelector:@selector(loadImages:)
								 toTarget:self
							   withObject:nil];
	}
//		[NSThread detachNewThreadSelector:@selector(loadImages:)
//								 toTarget:self withObject:nil];
	//reload if unfinished, but let current thread finish if there is one
	//pass nil to mean continue where we left off
}

- (void)updateExifInfo:(id)sender {
	NSTextView *exifTextView = [appDelegate exifTextView];
	NSView *mainView = [[exifTextView window] contentView];
	NSButton *moreBtn = [mainView viewWithTag:1];
	NSImageView *thumbView = [mainView viewWithTag:2];
	NSMutableAttributedString *attStr;
	id selectedIndexes = [imgMatrix selectedIndexes];
	if ([[exifTextView window] isVisible]) {
		if ([selectedIndexes count] == 1) {
			attStr = Fileinfo2EXIFString([imgMatrix firstSelectedFilename],
										 [appDelegate thumbsCache],
										 [moreBtn state]);
			// exif thumbnail
			[thumbView setImage:
				[EpegWrapper exifThumbForPath:ResolveAliasToPath([imgMatrix firstSelectedFilename])]];
		} else {
			id s = [selectedIndexes count]
			? [NSString stringWithFormat:NSLocalizedString(@"%d images selected.", @""),
				(unsigned int)[selectedIndexes count]]
			: NSLocalizedString(@"No images selected.", @"");
			NSMutableDictionary *atts = [NSMutableDictionary dictionaryWithObject:
												[NSFont userFontOfSize:12] forKey:NSFontAttributeName];
			attStr =
				[[[NSMutableAttributedString alloc] initWithString:s
													   attributes:atts] autorelease];
			[thumbView setImage:nil];
		}
		[attStr addAttribute:NSForegroundColorAttributeName value:[NSColor labelColor] range:NSMakeRange(0,[attStr length])];
		[[exifTextView textStorage] setAttributedString:attStr];
	}
}

- (void)updateExifInfo {
	[self updateExifInfo:nil];
}

#pragma mark splitview delegate

- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
	[[NSUserDefaults standardUserDefaults] setFloat:statusFld.superview.frame.size.height forKey:@"MainWindowSplitViewTopHeight"];
}

#pragma mark wrapping matrix methods
 - (void)wrappingMatrix:(DYWrappingMatrix *)m selectionDidChange:(NSIndexSet *)selectedIndexes {
	 NSString *s, *path, *basePath;
	 DYImageInfo *info;
	 DYImageCache *thumbsCache = [appDelegate thumbsCache];
	 unsigned long long totalSize = 0;
	 switch ([selectedIndexes count]) {
		 case 0:
			 s = @"";
			 break;
		 case 1:
			 basePath = [[dirBrowserDelegate path] stringByAppendingString:@"/"];
			 path = [imgMatrix firstSelectedFilename];
			 info = [thumbsCache infoForKey:ResolveAliasToPath(path)];
			 // must resolve alias here b/c that's what we do in loadImages
			 // see also modTime in DYImageCache
			 if (!info) {
				 // in case the thumbnail hasn't loaded into the cache yet, retrieve the file info ourselves.
				 info = [[[DYImageInfo alloc] initWithPath:ResolveAliasToPath(path)] autorelease];
			 }
			 s = info ? [[path stringByDeletingBasePath:basePath] stringByAppendingFormat:@" %dx%d (%@)",
				 (int)info->pixelSize.width,
				 (int)info->pixelSize.height,
				 FileSize2String(info->fileSize)]
				   : [[path stringByDeletingBasePath:basePath] stringByAppendingString:
					   @" - bad image file!"];
			 break;
		 default:
			 for (NSString *path in [imgMatrix selectedFilenames]) {
				 info = [thumbsCache infoForKey:ResolveAliasToPath(path)];
				 if (!info) info = [[[DYImageInfo alloc] initWithPath:ResolveAliasToPath(path)] autorelease];
				 if (info)
					 totalSize += info->fileSize;
			 }
			 s = [NSString stringWithFormat:@"%@ (%@)",
					 [NSString stringWithFormat:NSLocalizedString(@"%d images selected.", @""),
					 (unsigned int)[selectedIndexes count]],
				 FileSize2String(totalSize)];
			 break;
	 }
	 [bottomStatusFld setStringValue:s];
	 [self updateExifInfo];
}

- (NSImage *)wrappingMatrix:(DYWrappingMatrix *)m loadImageForFile:(NSString *)filename atIndex:(NSUInteger)i {
	DYImageCache *thumbsCache = [appDelegate thumbsCache];
	NSImage *thumb = [thumbsCache imageForKey:filename];
	if (thumb) return thumb;
	[imageCacheQueueLock lock];
	NSMutableDictionary *d = [[NSMutableDictionary alloc] initWithCapacity:3];
	d[@"filename"] = filename;
	d[@"index"] = @(i);
	[imageCacheQueue insertObject:[d autorelease] atIndex:0];
	[imageCacheQueueLock unlockWithCondition:1];
	return nil;
}

- (void)thumbLoader:(id)arg {
	DYImageCache *thumbsCache = [appDelegate thumbsCache];
	// only use exif thumbs if we're at the smallest thumbnail  setting
	BOOL useExifThumbs = [[NSUserDefaults standardUserDefaults]
						  integerForKey:@"DYWrappingMatrixMaxCellWidth"] == 160;
	NSUInteger i, lastCount = 0;
	NSMutableArray *visibleQueue = [[NSMutableArray alloc] initWithCapacity:100];
	NSString *loadingMsg = NSLocalizedString(@"Loading %i of %u...", @"");
	while (YES) {
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		[imageCacheQueueLock lockWhenCondition:1];
		if (!imageCacheQueueRunning) {
			// final cleanup before terminating thread
			[imageCacheQueueLock unlockWithCondition:0];
			[pool drain];
			break;
		}
		// use secondary queue if primary queue is empty
		// note: the secondary queue may be empty if all items are in the visibleQueue
		if ([imageCacheQueue count] == 0 && [secondaryImageCacheQueue count]) {
			[imageCacheQueue addObject:secondaryImageCacheQueue[0]];
			[secondaryImageCacheQueue removeObjectAtIndex:0];
		}
		NSMutableDictionary *d;
		NSString *origPath;
		// discard any items in the queue that are no longer in the browser's directory.
		// prioritize important files (the visible ones) by putting them in a higher-priority array.
		if (![visibleQueue count]                   // nothing in the priority queue, so search for more items to add to it...
			&& [imageCacheQueue count] != lastCount // but skip this if nothing has been added to the queue
			)
		{
			i = [imageCacheQueue count];
			while (i--) {
				d = imageCacheQueue[i];
				origPath = d[@"filename"];
				//NSLog(@"considering %@ for priority queue", [d objectForKey:@"index"]);
				if (![self pathIsVisibleThreaded:origPath]) {
					if ([imageCacheQueue count] > 1) // leave at least one item so it won't crash later (the next while loop assumes there's at least one item)
						//NSLog(@"skipping %@ because path has changed", [d objectForKey:@"index"]),
						[imageCacheQueue removeObjectAtIndex:i];
					continue;
				}
				if ([imgMatrix imageWithFileInfoNeedsDisplay:d]) {
					[visibleQueue addObject:d];
					[imageCacheQueue removeObjectAtIndex:i];
					//NSLog(@"prioritizing %@ because it is visible", [d objectForKey:@"index"]);
				}
			}
		}
		lastCount = [imageCacheQueue count];
		// skip any files that are not visible in the matrix view.
		i = 0;
		while (YES) {
			if ([visibleQueue count]) {
				// run through this "pre-approved" array before touching the main queue
				d = visibleQueue[0];
				origPath = d[@"filename"];
				if ([imgMatrix imageWithFileInfoNeedsDisplay:d] || [visibleQueue count] == 1) {
					[d retain];
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
			origPath = d[@"filename"];
			//NSLog(@"considering %@ in main loop", [d objectForKey:@"index"]);
			if ([imageCacheQueue count]-1 == i) { // if we've reached the last item of the array, we have to process it
				[d retain];
				[imageCacheQueue removeObjectAtIndex:i];
				//NSLog(@"processing %@ because it is the last item", [d objectForKey:@"index"]);
				break;
			}
			if ([imgMatrix imageWithFileInfoNeedsDisplay:d]) {
				[d retain];
				[imageCacheQueue removeObjectAtIndex:i];
				//NSLog(@"processing %@ as visible item", [d objectForKey:@"index"]);
				break;
			}
			++i;
		}
		BOOL workToDo = ([imageCacheQueue count] || [visibleQueue count] || [secondaryImageCacheQueue count]);
		[imageCacheQueueLock unlockWithCondition:workToDo ? 1 : 0]; // keep the condition as 1 (more work needs to be done) if there's still stuff in the array

		NSString *theFile = ResolveAliasToPath(origPath);
		NSSize cellSize = [DYWrappingMatrix maxCellSize];
		NSImage *thumb = [thumbsCache imageForKey:theFile];
		if (!thumb) {
			if ([imgMatrix numCells]) {
				// don't set status string if there are no thumbs (could happen if a file is in the queue when the path changes)
				[self setStatusString:[NSString stringWithFormat:loadingMsg, [imgMatrix numThumbsLoaded]+1, [imgMatrix numCells]]];
			}
			if ([thumbsCache attemptLockOnFile:theFile]) { // will sleep if pending
				DYImageInfo *result;
				result = [[DYImageInfo alloc] initWithPath:theFile];
				//if (FileIsJPEG(theFile)) {
				// try as jpeg first
				result->image = //EpegImageWithPath(theFile, cellSize, &result->pixelSize);
					[EpegWrapper imageWithPath:theFile
								   boundingBox:cellSize
									   getSize:&result->pixelSize
									 exifThumb:useExifThumbs
								getOrientation:&result->exifOrientation];

					//	NSLog(@"Epeg error: %@", [EpegWrapper jpegErrorMessage]); // ** this isn't cleared between invocations
				if (!result->image)
					[thumbsCache createScaledImage:result];

				if (result->image)
					[thumbsCache addImage:result forFile:theFile];
				else
					[thumbsCache dontAddFile:theFile]; //NSLog(@"couldn't load image %@", origPath);
				thumb = result->image;
				[result release];
			} else {
				// someone beat us to it
				thumb = [thumbsCache imageForKey:theFile];
			}
		}
		if (!thumb) thumb = [NSImage imageNamed:@"brokendoc.tif"];
		d[@"image"] = thumb;
		[imgMatrix performSelectorOnMainThread:@selector(setImageWithFileInfo:) withObject:d waitUntilDone:NO];
		[d release];
		[pool drain];
		if (!workToDo)
			[self performSelectorOnMainThread:@selector(updateStatusFld)
								   withObject:nil
								waitUntilDone:NO];
	}
	[visibleQueue release];
}

@end
