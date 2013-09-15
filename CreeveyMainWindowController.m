//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "CreeveyMainWindowController.h"
#import "EpegWrapper.h"
#import "DYCarbonGoodies.h"
#import "NSArrayIndexSetExtension.h"
#import "DirBrowserDelegate.h"

#import "CreeveyController.h"
#import "DYImageCache.h"
#import "RBSplitView.h"
#import "DYWrappingMatrix.h"
#import "FinderCompare.h"

@interface CreeveyMainWindowController (Private)
- (void)updateStatusFld;
@end

@implementation CreeveyMainWindowController

+(void)initialize { [RBSplitView class]; } // force linker

- (id)initWithWindowNibName:(NSString *)windowNibName {
	if (self = [super initWithWindowNibName:windowNibName]) {
		filenames = [[NSMutableArray alloc] init];
		displayedFilenames = [[NSMutableArray alloc] init];
		loadImageLock = [[NSLock alloc] init];
		filesBeingOpened = [[NSMutableSet alloc] init];
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
	[super dealloc];
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
	if (![s hasPrefix:[[dirBrowser delegate] path]]) return;
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
								 exifThumb:NO];
			if (!result->image) [thumbsCache createScaledImage:result];
			if (result->image) [thumbsCache addImage:result forFile:theFile];
			else [thumbsCache dontAddFile:theFile];
			thumb = result->image;
			[result release];
		} else {
			thumb = [thumbsCache imageForKey:theFile];
		}
	}
	if (!thumb) thumb = [NSImage imageNamed:@"brokendoc"];
	unsigned int mtrxIdx = [[imgMatrix filenames] indexOfObject:s];
	if (mtrxIdx != NSNotFound)
		[imgMatrix setImage:thumb forIndex:mtrxIdx];
}
	
- (void)fileWasDeleted:(NSString *)s {
	if (![s hasPrefix:[[dirBrowser delegate] path]]) return;
	unsigned mtrxIdx, i = [filenames indexOfObject:s];
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
	
	unsigned int i = 0;
	unsigned int numFiles;
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *origPath, *loadingMsg = NSLocalizedString(@"Getting filenames...", @"");
		// pull this function call out of the loop
	//NSTimeInterval imgloadstarttime = [NSDate timeIntervalSinceReferenceDate];
	
	if (thePath) {
		NSSet *filetypes = [[NSApp delegate] filetypes];
		[imgMatrix removeAllImages];
		[filenames removeAllObjects];
		[displayedFilenames removeAllObjects];
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
				 || [filetypes containsObject:NSHFSTypeOfFile(theFile)])
			{	
				[filenames addObject:aPath];
				if (++i % 100 == 0)
					[self setStatusString:[NSString stringWithFormat:@"%@ (%i)",
						loadingMsg, i]];
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
	}
	if (startSlideshowWhenReady && [filesBeingOpened count]) {
		[[NSApp delegate] performSelectorOnMainThread:@selector(slideshowFromAppOpen:)
										   withObject:[filesBeingOpened allObjects] // make a copy
										waitUntilDone:NO];
	}
	[displayedFilenames sortUsingSelector:@selector(finderCompare:)];
	filenamesDone = YES;

	//NSLog(@"got %d files.", [filenames count]);
	[pool release];
	pool = [[NSAutoreleasePool alloc] init];
		
	if ([displayedFilenames count] > 0) {
		loadingDone = NO;
		DYImageCache *thumbsCache = [[NSApp delegate] thumbsCache];
		BOOL useExifThumbs = [[NSUserDefaults standardUserDefaults]
							  integerForKey:@"DYWrappingMatrixMaxCellWidth"] == 160;
		// only use exif thumbs if we're at the smallest thumbnail  setting
		[slidesBtn setEnabled:YES]; // ** not main thread?
		currentFilesDeletable = [fm isDeletableFileAtPath:[displayedFilenames objectAtIndex:0]];
		
		numFiles = [displayedFilenames count];
		// ** int maxThumbs = MAX(MAX_THUMBS,numFiles+numToDelete);
		NSSize cellSize = [DYWrappingMatrix maxCellSize];
		NSImage *thumb;
		NSString *theFile;
		loadingMsg = NSLocalizedString(@"Loading %i of %u...", @"");
		
		[NSThread setThreadPriority:0.2];
		for (i=thePath ? 0 : [imgMatrix numCells]; i<numFiles; ++i) {
			if (stopCaching) {
				//NSLog(@"aborted1 %@", origPath);
				if (stopCaching == YES)
					break;
				[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
			}
			
			origPath = [displayedFilenames objectAtIndex:i];
			theFile = ResolveAliasToPath(origPath);
			//[thumbsCache sleepIfPending:theFile]; // ** could also move on and callback?
			thumb = [thumbsCache imageForKey:theFile];
			if (!thumb) {
				//NSLog(@"caching %d", i);
				[self setStatusString:[NSString stringWithFormat:loadingMsg, i+1, numFiles]];
				
				if ([thumbsCache attemptLockOnFile:theFile]) { // will sleep if pending
					DYImageInfo *result;
					result = [[DYImageInfo alloc] initWithPath:theFile];
					//if (FileIsJPEG(theFile)) {
					// try as jpeg first
					result->image = //EpegImageWithPath(theFile, cellSize, &result->pixelSize);
						[EpegWrapper imageWithPath:theFile
									   boundingBox:cellSize
										   getSize:&result->pixelSize
										 exifThumb:useExifThumbs];
						
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
			// check after a long caching op
			if (stopCaching == YES) { //  || myThreadTime < lastThreadTime not necessary?
				//NSLog(@"aborted2 %@", origPath);
				break; // stop if user has moved on
			}
			if (!thumb)
				thumb = [NSImage imageNamed:@"brokendoc"];
			[imgMatrix addImage:thumb withFilename:origPath];
			if ([filesBeingOpened containsObject:origPath])
				[imgMatrix addSelectedIndex:i];
			//NSLog(@"%@", thumb);
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
	if (filenamesDone && currCat) { // reload in case cats changed; ** we should probably notify when cats change instead
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


#pragma mark splitview delegate methods
- (void)splitView:(RBSplitView*)sender wasResizedFrom:(float)oldDimension to:(float)newDimension {
	[sender adjustSubviewsExcepting:[sender subviewAtPosition:0]];
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
	 NSString *s, *path;
	 DYImageInfo *i;
	 DYImageCache *thumbsCache = [[NSApp delegate] thumbsCache];
	 unsigned long long totalSize = 0;
	 id obj; NSEnumerator *e;
	 switch ([selectedIndexes count]) {
		 case 0:
			 s = @"";
			 break;
		 case 1:
			 path = [imgMatrix firstSelectedFilename];
			 i = [thumbsCache infoForKey:ResolveAliasToPath(path)];
			 // must resolve alias here b/c that's what we do in loadImages
			 // see also modTime in DYImageCache
			 s = i ? [[path lastPathComponent] stringByAppendingFormat:@" %dx%d (%@)",
				 (int)i->pixelSize.width,
				 (int)i->pixelSize.height,
				 FileSize2String(i->fileSize)]
				   : [[path lastPathComponent] stringByAppendingString:
					   @" - bad image file!"];
			 break;
		 default:
			 e = [[imgMatrix selectedFilenames] objectEnumerator];
			 while (obj = [e nextObject]) {
				 if (i = [thumbsCache infoForKey:ResolveAliasToPath(obj)])
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

@end
