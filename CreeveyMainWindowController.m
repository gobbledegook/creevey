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
#import "DYImageCache.h"
#import "DYWrappingMatrix.h"
#import "FinderCompare.h"

@implementation NSString (DateModifiedCompare)

- (NSComparisonResult)dateModifiedCompare:(NSString *)other
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSComparisonResult r;
	r = [[[fm fileAttributesAtPath:self traverseLink:YES] fileModificationDate]
			compare:[[fm fileAttributesAtPath:other traverseLink:YES] fileModificationDate]];
	if (r == NSOrderedSame) { // use file name comparison as fallback; filenames are guaranteed to be unique, but mod times are not
		return [self finderCompare:other];
	}
	return r;
}

@end


@interface CreeveyMainWindowController (Private)
- (void)updateStatusFld;
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
		[NSThread detachNewThreadSelector:@selector(thumbLoader:) toTarget:self withObject:nil];
	}
    return self;
}

- (void)awakeFromNib {
	[[self window] setFrameUsingName:@"MainWindowLoc"];
	// otherwise it uses the frame in the nib
	
	[imgMatrix setFrameSize:[[imgMatrix superview] frame].size];
	[imgMatrix setCellWidth:[[NSUserDefaults standardUserDefaults] floatForKey:@"thumbCellWidth"]];
}

- (void)dealloc {
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

- (NSString *)path { return [[dirBrowser delegate] path]; }

// returns NO if doesn't exist, useful for applicationDidFinishLaunching
- (BOOL)setPath:(NSString *)s {
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL isDir;
	if (![fm fileExistsAtPath:s isDirectory:&isDir])
		return NO;
	if (!isDir)
		s = [s stringByDeletingLastPathComponent];
	if (![[dirBrowser delegate] setPath:s]) {
		//NSLog(@"retrying as invisible");
		[[dirBrowser delegate] setShowInvisibles:showInvisibles = YES];
		[[dirBrowser delegate] setPath:s];
	}
	[dirBrowser sendAction];
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
	NSString *browserPath = [[dirBrowser delegate] path];
	if (recurseSubfolders) return [filename hasPrefix:browserPath];
	return [[filename stringByDeletingLastPathComponent] isEqualToString:browserPath];
}

- (void)updateDefaults {
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	if ([u integerForKey:@"startupOption"] == 0)
		[u setObject:[[dirBrowser delegate] path] forKey:@"lastFolderPath"];
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
- (void)selectIndex:(unsigned int)i {
	[imgMatrix selectIndex:i];
}

- (void)openFiles:(NSArray *)a withSlideshow:(BOOL)doSlides{
	if (doSlides) {
		startSlideshowWhenReady = YES;
		NSSet *filetypes = [[NSApp delegate] filetypes];
		unsigned int i, n = [a count];
		NSString *theFile;
		for (i=0; i<n; ++i) {
			theFile = [a objectAtIndex:i];
			if ([filetypes containsObject:[theFile pathExtension]] || [filetypes containsObject:NSHFSTypeOfFile(theFile)])
				[filesBeingOpened addObject:theFile];
		}
	} else {
		startSlideshowWhenReady = NO;
		[filesBeingOpened addObjectsFromArray:a];
	}

	[self setPath:[a objectAtIndex:0]];
}

- (void)fileWasChanged:(NSString *)s {
	if (![self pathIsVisible:s]) return;
	// update thumb
	DYImageCache *thumbsCache = [[NSApp delegate] thumbsCache];
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
		stopCaching = YES;
		[loadImageLock lock];
		
		if ((mtrxIdx = [[imgMatrix filenames] indexOfObject:s]) != NSNotFound)
			[imgMatrix removeImageAtIndex:mtrxIdx]; // more linear searches
		[displayedFilenames removeObject:s];
		[filenames removeObjectAtIndex:i];
		
		[loadImageLock unlock];
		if (!filenamesDone || !loadingDone) //[imgMatrix numCells] < [filenames count])
			[NSThread detachNewThreadSelector:@selector(loadImages:)
									 toTarget:self
								   withObject:filenamesDone ? [[dirBrowser delegate] path] : nil];
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
	stopCaching = NO;
	
	NSUInteger i = 0;
	NSUInteger numFiles;
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *origPath, *loadingMsg = NSLocalizedString(@"Getting filenames...", @"");
		// pull this function call out of the loop
	//NSTimeInterval imgloadstarttime = [NSDate timeIntervalSinceReferenceDate];
	
	if (thePath) {
		NSSet *filetypes = [[NSApp delegate] filetypes];
		[imgMatrix removeAllImages];
		[filenames removeAllObjects];
		[displayedFilenames removeAllObjects];
		[imageCacheQueueLock lock];
		[imageCacheQueue removeAllObjects];
		[secondaryImageCacheQueue removeAllObjects];
		[imageCacheQueueLock unlockWithCondition:0];
		NSDirectoryEnumerator *e = [fm enumeratorAtPath:thePath];
		id obj;
		//NSLog(@"getting filenames...");
		while (obj = [e nextObject]) {
			NSString *aPath = [thePath stringByAppendingPathComponent:obj];
			NSString *theFile = ResolveAliasToPath(aPath);
			BOOL isInvisible = [obj characterAtIndex:0] == '.' || FileIsInvisible(aPath);
			// don't worry about top level .hidden here
			
			if ([[[e fileAttributes] fileType] isEqualToString:NSFileTypeDirectory]) {
				if (!recurseSubfolders || (!showInvisibles && isInvisible))
					[e skipDescendents];
				else if ([[theFile lastPathComponent] isEqualToString:@"Thumbs"])
					[e skipDescendents]; // special addition for mbatch
				continue;
			}
			if (!showInvisibles && isInvisible)
				continue; // skip invisible files
			if ([filetypes containsObject:[theFile pathExtension]]
				 || [filetypes containsObject:NSHFSTypeOfFile(theFile)]
				 || [filetypes containsObject:[[theFile pathExtension] lowercaseString]])
			{
				[filenames addObject:aPath];
				if (++i % 100 == 0)
					[self setStatusString:[NSString stringWithFormat:@"%@ (%lu)",
						loadingMsg, (unsigned long)i]];
			}
			// NSFileTypeForHFSTypeCode([[atts objectForKey:NSFileHFSCreatorCode] unsignedLongValue]),
			if (stopCaching == YES) {
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
			numFiles = [filenames count];
			for (i=0; i<numFiles; ++i) {
				origPath = [filenames objectAtIndex:i];
				if ([[[NSApp delegate] cats][currCat-2] containsObject:origPath])
					[displayedFilenames addObject:origPath];
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
			[[NSApp delegate] performSelectorOnMainThread:@selector(slideshowFromAppOpen:)
											   withObject:[filesBeingOpened allObjects] // make a copy
											waitUntilDone:NO];
		}
	}
	if (abs(sortOrder) == 1) {
		[displayedFilenames sortUsingSelector:@selector(finderCompare:)];
	} else {
		[displayedFilenames sortUsingSelector:@selector(dateModifiedCompare:)];
	}
	if (sortOrder < 0 && [displayedFilenames count]) {
		// reverse the array
		unsigned int a, b;
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
		
	if ([displayedFilenames count] > 0) {
		loadingDone = NO;
		[slidesBtn setEnabled:YES]; // ** not main thread?
		currentFilesDeletable = [fm isDeletableFileAtPath:[displayedFilenames objectAtIndex:0]];
		
		numFiles = [displayedFilenames count];
		unsigned int maxThumbs = [[NSUserDefaults standardUserDefaults]
								  integerForKey:@"maxThumbsToLoad"];
		
		[NSThread setThreadPriority:0.2];
		for (i=thePath ? 0 : [imgMatrix numCells]; i<numFiles; ++i) {
			if (stopCaching) {
				//NSLog(@"aborted1 %@", origPath);
				if (stopCaching == YES)
					break;
				[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
			}
			
			origPath = [displayedFilenames objectAtIndex:i];
			[imgMatrix addImage:nil withFilename:origPath];
			if ([filesBeingOpened containsObject:origPath])
				[imgMatrix addSelectedIndex:i];

			// now, to simulate the original behavior, add a certain number of
			// images to the queue automatically
			if (i < maxThumbs) {
				[imageCacheQueueLock lock];
				NSMutableDictionary *d = [[NSMutableDictionary alloc] initWithCapacity:3];
				[d setObject:origPath forKey:@"filename"];
				[d setObject:[NSNumber numberWithUnsignedInteger:i] forKey:@"index"];
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
	if (loadingDone) [filesBeingOpened removeAllObjects];
	[loadImageLock unlock];
	[pool release];
	[thePath release];
}

- (IBAction)displayDir:(id)sender {
	// appkit drawing issues
	// nsbrowser animation hangs the app!
	stopCaching = YES;	
	currentFilesDeletable = NO;
	filenamesDone = NO;
	currCat = 0;
	[slidesBtn setEnabled:NO];
	NSString *currentPath = [[dirBrowser delegate] path];
	[statusFld setStringValue:NSLocalizedString(@"Getting filenames...", @"")];
	[[self window] setTitleWithRepresentedFilename:currentPath];
	[NSThread detachNewThreadSelector:@selector(loadImages:)
							 toTarget:self withObject:currentPath];
}

- (IBAction)setRecurseSubfolders:(id)sender {
	recurseSubfolders = [sender state] == NSOnState;
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
		if (([e modifierFlags] & NSCommandKeyMask) != 0) {
			int i; // not unsigned b/c we decrement
			short j;
			NSArray *a = [imgMatrix selectedFilenames];
			if (![a count]) {
				NSBeep();
				return;
			}
			
			NSMutableSet **cats = [[NSApp delegate] cats];
			for (i=[a count]-1; i>=0; i--) {
				id fname = [a objectAtIndex:i];
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
			if (!currCat || c && c != currCat) {
				[statusFld setStringValue:[NSString stringWithFormat:
					NSLocalizedString(@"%u image(s) updated for Group %i", @""),
					[a count], c]];
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
		
		stopCaching = YES; // don't need to lock, not changing anything
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
		stopCaching = 2; // **
	}
}

- (void)windowDidBecomeMain:(NSNotification *)aNotification {
	[self updateExifInfo];
	if (!filenamesDone || !loadingDone)// && stopCaching)
		stopCaching = NO;
	if (filenamesDone && currCat) { // reload in case category membership of certain files changed;
		// ** we should probably notify when cats change instead
		// ** and also handle the case where you change something's category so it no longer belongs in the current view
		stopCaching = YES;
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
	NSTextView *exifTextView = [[NSApp delegate] exifTextView];
	NSView *mainView = [[exifTextView window] contentView];
	NSButton *moreBtn = [mainView viewWithTag:1];
	NSImageView *thumbView = [mainView viewWithTag:2];
	NSMutableAttributedString *attStr;
	id selectedIndexes = [imgMatrix selectedIndexes];
	if ([[exifTextView window] isVisible]) {
		if ([selectedIndexes count] == 1) {
			attStr = Fileinfo2EXIFString([imgMatrix firstSelectedFilename],
										 [[NSApp delegate] thumbsCache],
										 [moreBtn state], YES);
			// exif thumbnail
			[thumbView setImage:
				[EpegWrapper exifThumbForPath:ResolveAliasToPath([imgMatrix firstSelectedFilename])]];
		} else {
			id s = [selectedIndexes count]
			? [NSString stringWithFormat:NSLocalizedString(@"%d images selected.", @""),
				[selectedIndexes count]]
			: NSLocalizedString(@"No images selected.", @"");
			NSMutableDictionary *atts = [NSMutableDictionary dictionaryWithObject:
												[NSFont userFontOfSize:12] forKey:NSFontAttributeName];
			attStr =
				[[[NSMutableAttributedString alloc] initWithString:s
													   attributes:atts] autorelease];
			[thumbView setImage:nil];
		}
		[exifTextView replaceCharactersInRange:NSMakeRange(0,[[exifTextView string] length])
									   withRTF:[attStr RTFFromRange:NSMakeRange(0,[attStr length])
												 documentAttributes:nil]];
	}
}

- (void)updateExifInfo {
	[self updateExifInfo:nil];
}

#pragma mark wrapping matrix methods
 - (void)wrappingMatrix:(DYWrappingMatrix *)m selectionDidChange:(NSIndexSet *)selectedIndexes {
	 NSString *s, *path, *basePath;
	 DYImageInfo *i;
	 DYImageCache *thumbsCache = [[NSApp delegate] thumbsCache];
	 unsigned long long totalSize = 0;
	 id obj; NSEnumerator *e;
	 switch ([selectedIndexes count]) {
		 case 0:
			 s = @"";
			 break;
		 case 1:
			 basePath = [[[dirBrowser delegate] path] stringByAppendingString:@"/"];
			 path = [imgMatrix firstSelectedFilename];
			 i = [thumbsCache infoForKey:ResolveAliasToPath(path)];
			 // must resolve alias here b/c that's what we do in loadImages
			 // see also modTime in DYImageCache
			 if (!i) {
				 // in case the thumbnail hasn't loaded into the cache yet, retrieve the file info ourselves.
				 i = [[[DYImageInfo alloc] initWithPath:ResolveAliasToPath(path)] autorelease];
			 }
			 s = i ? [[path stringByDeletingBasePath:basePath] stringByAppendingFormat:@" %dx%d (%@)",
				 (int)i->pixelSize.width,
				 (int)i->pixelSize.height,
				 FileSize2String(i->fileSize)]
				   : [[path stringByDeletingBasePath:basePath] stringByAppendingString:
					   @" - bad image file!"];
			 break;
		 default:
			 e = [[imgMatrix selectedFilenames] objectEnumerator];
			 while (obj = [e nextObject]) {
				 i = [thumbsCache infoForKey:ResolveAliasToPath(obj)];
				 if (!i) i = [[[DYImageInfo alloc] initWithPath:ResolveAliasToPath(obj)] autorelease];
				 if (i)
					 totalSize += i->fileSize;
			 }
			 s = [NSString stringWithFormat:@"%@ (%@)",
					 [NSString stringWithFormat:NSLocalizedString(@"%d images selected.", @""),
					 [selectedIndexes count]],
				 FileSize2String(totalSize)];
			 break;
	 }
	 [bottomStatusFld setStringValue:s];
	 [self updateExifInfo];
}

- (NSImage *)wrappingMatrix:(DYWrappingMatrix *)m loadImageForFile:(NSString *)filename atIndex:(NSUInteger)i {
	DYImageCache *thumbsCache = [[NSApp delegate] thumbsCache];
	NSImage *thumb = [thumbsCache imageForKey:filename];
	if (thumb) return thumb;
	[imageCacheQueueLock lock];
	NSMutableDictionary *d = [[NSMutableDictionary alloc] initWithCapacity:3];
	[d setObject:filename forKey:@"filename"];
	[d setObject:[NSNumber numberWithUnsignedInteger:i] forKey:@"index"];
	[imageCacheQueue insertObject:[d autorelease] atIndex:0];
	[imageCacheQueueLock unlockWithCondition:1];
	return nil;
}

- (void)thumbLoader:(id)arg {
	DYImageCache *thumbsCache = [[NSApp delegate] thumbsCache];
	// only use exif thumbs if we're at the smallest thumbnail  setting
	BOOL useExifThumbs = [[NSUserDefaults standardUserDefaults]
						  integerForKey:@"DYWrappingMatrixMaxCellWidth"] == 160;
	unsigned int i, lastCount = 0;
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
			[imageCacheQueue addObject:[secondaryImageCacheQueue objectAtIndex:0]];
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
				d = [imageCacheQueue objectAtIndex:i];
				origPath = [d objectForKey:@"filename"];
				//NSLog(@"considering %@ for priority queue", [d objectForKey:@"index"]);
				if (![self pathIsVisible:origPath]) {
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
				d = [visibleQueue objectAtIndex:0];
				origPath = [d objectForKey:@"filename"];
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
			d = [imageCacheQueue objectAtIndex:i];
			origPath = [d objectForKey:@"filename"];
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
			[self setStatusString:[NSString stringWithFormat:loadingMsg, [imgMatrix numThumbsLoaded]+1, [imgMatrix numCells]]];
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
		[d setObject:thumb forKey:@"image"];
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
