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
#import "DYFileWatcher.h"

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


@interface CreeveyMainWindowController () <DYFileWatcherDelegate>
{
	volatile BOOL _background, _wantsSubfolders;
	NSImage *_brokenDoc, *_loadingImage;
	NSMutableSet *_accessedFiles;
	NSLock *_accessedLock, *_statusLock, *_internalLock;
	volatile NSTimeInterval _statusTime;
	DYFileWatcher *_fileWatcher;
}
@property (nonatomic, readonly) NSSplitView *splitView;
@property BOOL wantsSubfolders;
@property (nonatomic, strong) NSString *recurseRoot;
@end

@implementation CreeveyMainWindowController
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
		appDelegate = (CreeveyController *)[NSApp delegate];
		_accessedFiles = [[NSMutableSet alloc] init];
		_accessedLock = [[NSLock alloc] init];
		_statusLock = [[NSLock alloc] init];
		_internalLock = [[NSLock alloc] init];
		_fileWatcher = [[DYFileWatcher alloc] initWithDelegate:self];
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
	dirBrowserDelegate.revealedDirectories = appDelegate.revealedDirectories;

	_brokenDoc = [NSImage imageNamed:@"brokendoc.tif"];
	_loadingImage = [NSImage imageNamed:@"loading.png"];
	[imgMatrix setLoadingImage:_loadingImage];
	[NSThread detachNewThreadSelector:@selector(thumbLoader:) toTarget:self withObject:nil];
}

- (void)window:(NSWindow *)window willEncodeRestorableState:(NSCoder *)state
{
	NSDictionary *data = @{@"path":[self path], @"split1":@(statusFld.superview.frame.size.height)};
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

- (void)windowWillClose:(NSNotification *)notification {
	[_accessedLock lock];
	DYImageCache *thumbsCache = [appDelegate thumbsCache];
	for (NSString *s in _accessedFiles) {
		[thumbsCache endAccess:ResolveAliasToPath(s)];
	}
	[_accessedFiles removeAllObjects];
	[_accessedLock unlock];

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

- (BOOL)pathIsCurrentDirectory:(NSString *)filename {
	NSString *browserPath = [dirBrowserDelegate path];
	if (self.wantsSubfolders) return [filename hasPrefix:browserPath];
	return [[filename stringByDeletingLastPathComponent] isEqualToString:browserPath];
}

- (BOOL)pathIsVisibleThreaded:(NSString *)filename {
	NSString *browserPath = dirBrowserDelegate.currPath;
	if (self.wantsSubfolders) return [filename hasPrefix:browserPath];
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
- (NSUInteger)indexOfFilename:(NSString *)s {
	return [displayedFilenames indexOfObject:s inSortedRange:NSMakeRange(0, displayedFilenames.count) options:0 usingComparator:[self comparator]];
}
- (NSComparator)comparator {
	switch (sortOrder) {
		case 1:
		default:
			return ^NSComparisonResult(id a, id b) {
				return [a localizedStandardCompare:b];
			};
		case 2:
			return ^NSComparisonResult(id a, id b) {
				return [a dateModifiedCompare:b];
			};
		case -1:
			return ^NSComparisonResult(id a, id b) {
				return [b localizedStandardCompare:a];
			};
		case -2:
			return ^NSComparisonResult(id a, id b) {
				return [b dateModifiedCompare:a];
			};
	}
}

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

- (void)watcherFiles:(NSArray *)files {
	if (!filenamesDone) return;
	NSFileManager *fm = NSFileManager.defaultManager;
	for (NSString *s in files) {
		NSUInteger count = filenames.count;
		BOOL fileExists = [fm fileExistsAtPath:s];
		NSUInteger idx = [filenames indexOfObject:s inSortedRange:NSMakeRange(0, count) options:NSBinarySearchingInsertionIndex usingComparator:[self comparator]];
		if (idx < count && [filenames[idx] isEqualToString:s]) {
			if (fileExists)
				[self fileWasChanged:s];
			else
				[self fileWasDeleted:s atIndex:idx];
		} else {
			if (fileExists)
				[self addFile:s atIndex:idx];
		}
	}
}

- (void)addFile:(NSString *)s atIndex:(NSUInteger)idx {
	if (displayedFilenames.count == filenames.count) {
		[displayedFilenames insertObject:s atIndex:idx];
		[imgMatrix addImage:nil withFilename:s atIndex:idx];
	}
	[filenames insertObject:s atIndex:idx];
	[self updateStatusFld];
}

- (void)fileWasChanged:(NSString *)s {
	if (![self pathIsCurrentDirectory:s]) return;
	// update thumb
	DYImageCache *thumbsCache = [appDelegate thumbsCache];
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
	} else { // ** dup
		if ([thumbsCache attemptLockOnFile:theFile]) {
			DYImageInfo *result;
			result = [[DYImageInfo alloc] initWithPath:theFile];
			result.image =
				[EpegWrapper imageWithPath:theFile
							   boundingBox:[DYWrappingMatrix maxCellSize]
								   getSize:&result->pixelSize
								 exifThumb:NO
							getOrientation:&result->exifOrientation];
			if (!result.image) [thumbsCache createScaledImage:result];
			if (result.image) {
				[thumbsCache addImage:result forFile:theFile];
				addedToCache = YES;
			}
			else [thumbsCache dontAddFile:theFile];
			thumb = result.image;
		} else {
			thumb = [thumbsCache imageForKey:theFile];
			if (thumb) {
				[thumbsCache beginAccess:theFile];
				addedToCache = YES;
			}
		}
	}
	if (!thumb) thumb = _brokenDoc;
	// since we already checked if the file is in the current directory, we can assume the matrix's files have the same sort order
	NSUInteger mtrxIdx = [[imgMatrix filenames] indexOfObject:s inSortedRange:NSMakeRange(0, [imgMatrix filenames].count) options:0 usingComparator:[self comparator]];
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
	NSUInteger mtrxIdx;
	if (i == NSNotFound)
		i = [filenames indexOfObject:s inSortedRange:NSMakeRange(0, filenames.count) options:0 usingComparator:[self comparator]];
	if (i != NSNotFound) {
		stopCaching = 1;
		[loadImageLock lock];
		if ((mtrxIdx = [[imgMatrix filenames] indexOfObject:s inSortedRange:NSMakeRange(0, [imgMatrix filenames].count) options:0 usingComparator:[self comparator]]) != NSNotFound) {
			[imgMatrix removeImageAtIndex:mtrxIdx];
			[displayedFilenames removeObjectAtIndex:mtrxIdx];
		}
		[filenames removeObjectAtIndex:i];
		[loadImageLock unlock];

		[_accessedLock lock];
		if ([_accessedFiles containsObject:s]) {
			[_accessedFiles removeObject:s];
			[[appDelegate thumbsCache] endAccess:s];
		}
		[_accessedLock unlock];

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

- (void)filesWereUndeleted:(NSArray *)a {
	NSString *currentPath = [self path];
	BOOL needsRefresh = NO;
	for (NSString *s in a) {
		if ([s hasPrefix:currentPath])
			needsRefresh = YES;
	}
	if (needsRefresh)
		[self setPath:currentPath];
}

- (void)updateStatusFld {
	id s = NSLocalizedString(@"%u images", @"");
	NSString *status = currCat
		? [NSString stringWithFormat:@"%@: %@",
			[NSString stringWithFormat:NSLocalizedString(@"Group %i", @""), currCat],
			[NSString stringWithFormat:s, [displayedFilenames count]]]
		: [NSString stringWithFormat:s, filenames.count];
	[self updateStatusString:status];
}

- (void)updateStatusString:(NSString *)s {
	[_statusLock lock];
	_statusTime = NSDate.timeIntervalSinceReferenceDate;
	[_statusLock unlock];
	[statusFld setStringValue:s];
}

- (void)updateStatusOnMainThread:(NSString * (^)(void))f {
	[_statusLock lock];
	NSTimeInterval timeStamp = _statusTime = NSDate.timeIntervalSinceReferenceDate;
	[_statusLock unlock];
	dispatch_async(dispatch_get_main_queue(), ^{
		[_statusLock lock];
		NSTimeInterval latestStatusTime = _statusTime;
		[_statusLock unlock];
		if (latestStatusTime > timeStamp) return;
		NSString *s = f();
		if (s) [statusFld setStringValue:s];
	});
}

#pragma mark load thread
- (void)loadImages:(NSString *)thePath { // called in a separate thread
										 //NSLog(@"loadImages thread started for %@", thePath);
	// assume (incorrectly?) that threads will be executed in the order detached
	// better to set in loadDir and pass it in?
	NSTimeInterval myThreadTime;
	@autoreleasepool {
		myThreadTime = lastThreadTime = [NSDate timeIntervalSinceReferenceDate];
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
		//NSTimeInterval imgloadstarttime = [NSDate timeIntervalSinceReferenceDate];
	
		dispatch_async(dispatch_get_main_queue(), ^{
			[imgMatrix removeAllImages];
		});
		if (thePath) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[_fileWatcher stop];
			});
			[filenames removeAllObjects];
			[displayedFilenames removeAllObjects];
			[imageCacheQueueLock lock];
			[imageCacheQueue removeAllObjects];
			[secondaryImageCacheQueue removeAllObjects];
			[imageCacheQueueLock unlockWithCondition:0];
			BOOL recurseSubfolders = self.wantsSubfolders;
			NSDirectoryEnumerationOptions options = recurseSubfolders ? 0 : NSDirectoryEnumerationSkipsSubdirectoryDescendants;
			options |= NSDirectoryEnumerationSkipsHiddenFiles;
			NSFileManager *fm = NSFileManager.defaultManager;
			NSDirectoryEnumerator *e = [fm enumeratorAtURL:[NSURL fileURLWithPath:thePath isDirectory:YES]
								includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsAliasFileKey]
												   options:options errorHandler:nil];
			//NSLog(@"getting filenames...");
			for (NSURL *url in e) {
				NSString *aPath = url.path;
				NSNumber *val;
				if ([url getResourceValue:&val forKey:NSURLIsDirectoryKey error:NULL] && val.boolValue) {
					if (recurseSubfolders && [[aPath lastPathComponent] isEqualToString:@"Thumbs"])
						[e skipDescendents]; // special addition for mbatch
					continue;
				}

				NSString *theFile = aPath;
				if ([url getResourceValue:&val forKey:NSURLIsAliasFileKey error:NULL] && val.boolValue) {
					NSString *resolved = ResolveAliasURLToPath(url);
					if (resolved) theFile = resolved;
				}
				if ([appDelegate shouldShowFile:theFile])
				{
					[filenames addObject:aPath];
					if (++i % 100 == 0)
						[self updateStatusOnMainThread:^NSString *{
							return [NSString stringWithFormat:@"%@ (%lu)", loadingMsg, i];
						}];
				}
				if (stopCaching) {
					[filenames removeAllObjects]; // so it fails count > 0 test below
					break;
				}
			}
			[displayedFilenames addObjectsFromArray:filenames];
			dispatch_async(dispatch_get_main_queue(), ^{
				[_fileWatcher watchDirectory:thePath];
			});
		} else if (currCat) { // currCat > 0 whenever cat changes (see keydown)
			// this means deleting when a cat is displayed will cause unsightly flashing
			// but we can live with that for now. maybe temp set currcat to 0?
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
			[imageCacheQueueLock lock];
			[imageCacheQueue removeAllObjects];
			[secondaryImageCacheQueue removeAllObjects];
			[imageCacheQueueLock unlockWithCondition:0];
		}
		[displayedFilenames sortUsingComparator:[self comparator]];
		if (startSlideshowWhenReady) {
			startSlideshowWhenReady = NO;
			// set this back to NO so we don't get infinite slideshow looping if a category is selected (initiated by windowDidBecomeMain:)
			if ([filesBeingOpened count]) {
				NSArray *files = [filesBeingOpened.allObjects sortedArrayUsingComparator:[self comparator]];
				[appDelegate performSelectorOnMainThread:@selector(slideshowFromAppOpen:) withObject:files waitUntilDone:NO]; // this must be called after displayedFilenames is sorted in case it calls back for indexOfFilename:
			}
		}
		if (thePath)
			[filenames setArray:displayedFilenames]; // save the sorted list
		filenamesDone = YES;
		//NSLog(@"got %d files.", [filenames count]);
	}
#pragma mark populate matrix
	@autoreleasepool {
		DYImageCache *thumbsCache = [appDelegate thumbsCache];
		[_accessedLock lock];
		for (NSString *s in _accessedFiles) {
			[thumbsCache endAccess:ResolveAliasToPath(s)];
		}
		[_accessedFiles removeAllObjects];
		[_accessedLock unlock];

		NSUInteger i = 0;
		NSMutableIndexSet *selectedIndexes = [NSMutableIndexSet indexSet];
		if ([displayedFilenames count] > 0) {
			loadingDone = NO;
			dispatch_async(dispatch_get_main_queue(), ^{
				[slidesBtn setEnabled:YES];
			});
			currentFilesDeletable = [NSFileManager.defaultManager isDeletableFileAtPath:displayedFilenames[0]];
		
			NSUInteger numFiles = [displayedFilenames count];
			NSUInteger maxThumbs = [[NSUserDefaults standardUserDefaults]
									integerForKey:@"maxThumbsToLoad"];
		
			for (; i<numFiles; ++i) {
				if (stopCaching) {
					//NSLog(@"aborted1 %@", origPath);
					break;
				}
				NSString *origPath = displayedFilenames[i];
				NSString *resolvedPath = ResolveAliasToPath(origPath);
				NSImage *cachedImage = [thumbsCache imageForKeyInvalidatingCacheIfNecessary:resolvedPath]; // remember the thumbsCache's key is the resolved path!
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
					[secondaryImageCacheQueue addObject:@[origPath, @(i)]];
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
			[self performSelectorOnMainThread:@selector(updateStatusFld) withObject:nil waitUntilDone:NO];
		if (loadingDone && filesBeingOpened.count) {
			[filesBeingOpened removeAllObjects];
			if (myThreadTime == lastThreadTime && selectedIndexes.count)
				dispatch_async(dispatch_get_main_queue(), ^{
					if ([thePath isEqualToString:dirBrowserDelegate.currPath])
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
	[slidesBtn setEnabled:NO];
	NSString *currentPath = [dirBrowserDelegate path];
	_subfoldersButton.enabled = ![currentPath isEqualToString:@"/"]; // let's not ever load up the entire file system
	if (self.wantsSubfolders && sender) { // sender is dirBrowserDelegate when non-nil
		if (![currentPath hasPrefix:_recurseRoot]) {
			self.wantsSubfolders = NO;
			[_subfoldersButton setState:NSControlStateValueOff];
		}
	}
	[self updateStatusString:NSLocalizedString(@"Getting filenames...", @"")];
	[[self window] setTitleWithRepresentedFilename:currentPath];
	[NSThread detachNewThreadSelector:@selector(loadImages:)
							 toTarget:self withObject:currentPath];
}

- (IBAction)setRecurseSubfolders:(id)sender {
	self.wantsSubfolders = ([sender state] == NSOnState);
	// remember where we started recursing subfolders
	if (self.wantsSubfolders) {
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
			
			NSMutableSet * __strong *cats = [appDelegate cats];
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
				[self updateStatusString:[NSString stringWithFormat:
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
		[filesBeingOpened addObjectsFromArray:[imgMatrix selectedFilenames]];
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
	NSTextView *exifTextView = [appDelegate exifTextView];
	NSView *mainView = [[exifTextView window] contentView];
	NSButton *moreBtn = [mainView viewWithTag:1];
	NSImageView *thumbView = [mainView viewWithTag:2];
	NSMutableAttributedString *attStr;
	NSMutableIndexSet *selectedIndexes = [imgMatrix selectedIndexes];
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
			attStr = [[NSMutableAttributedString alloc] initWithString:s attributes:atts];
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
				 info = [[DYImageInfo alloc] initWithPath:ResolveAliasToPath(path)];
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
				 if (!info) info = [[DYImageInfo alloc] initWithPath:ResolveAliasToPath(path)];
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
	NSImage *thumb = [thumbsCache imageForKeyInvalidatingCacheIfNecessary:ResolveAliasToPath(filename)];
	if (thumb) return thumb;
	[imageCacheQueueLock lock];
	[imageCacheQueue insertObject:@[filename, @(i)] atIndex:0];
	[imageCacheQueueLock unlockWithCondition:1];
	return nil;
}

// this thread runs forever, waiting for objects to be added to its queue
- (void)thumbLoader:(id)arg {
	NSThread.currentThread.name = @"thumbLoader:";
	DYImageCache *thumbsCache = [appDelegate thumbsCache];
	// only use exif thumbs if we're at the smallest thumbnail  setting
	BOOL useExifThumbs = [[NSUserDefaults standardUserDefaults]
						  integerForKey:@"DYWrappingMatrixMaxCellWidth"] == 160;
	NSUInteger i, lastCount = 0;
	NSMutableArray *visibleQueue = [[NSMutableArray alloc] initWithCapacity:100];
	NSString *loadingMsg = NSLocalizedString(@"Loading %lu of %lu...", @"");
	BOOL workToDo = YES;
	while (YES) {
		@autoreleasepool {
			// all calls to the thumbnail view must be on the main thread, which we wait for synchronously
			// to avoid a deadlock (where the view's drawRect calls our loadImageForFile, which modifies the cache queue),
			// we save the state of the view before acquiring the lock (we can't use NSRecursiveLock since we need NSConditionLock)
			DYMatrixState * __block currState;
			dispatch_sync(dispatch_get_main_queue(), ^{
				currState = [imgMatrix currentState];
			});
			[imageCacheQueueLock lockWhenCondition:1];
			if (!imageCacheQueueRunning) {
				// final cleanup before terminating thread
				[imageCacheQueueLock unlockWithCondition:0];
				break;
			}
			// use secondary queue if primary queue is empty
			// note: the secondary queue may be empty if all items are in the visibleQueue
			if ([imageCacheQueue count] == 0 && [secondaryImageCacheQueue count]) {
				[imageCacheQueue addObject:secondaryImageCacheQueue[0]];
				[secondaryImageCacheQueue removeObjectAtIndex:0];
			}
			NSArray *d;
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
					origPath = d[0];
					//NSLog(@"considering %@ for priority queue", [d objectForKey:@"index"]);
					if (![self pathIsVisibleThreaded:origPath]) {
						if ([imageCacheQueue count] > 1) // leave at least one item so it won't crash later (the next while loop assumes there's at least one item)
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
			lastCount = [imageCacheQueue count];
			// skip any files that are not visible in the matrix view.
			i = 0;
			while (YES) {
				if ([visibleQueue count]) {
					// run through this "pre-approved" array before touching the main queue
					d = visibleQueue[0];
					origPath = d[0];
					if ([currState imageWithFileInfoNeedsDisplay:d] || [visibleQueue count] == 1) {
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
				origPath = d[0];
				//NSLog(@"considering %@ in main loop", [d objectForKey:@"index"]);
				if ([imageCacheQueue count]-1 == i) { // if we've reached the last item of the array, we have to process it
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
			workToDo = ([imageCacheQueue count] || [visibleQueue count] || [secondaryImageCacheQueue count]);
			[imageCacheQueueLock unlockWithCondition:workToDo ? 1 : 0]; // keep the condition as 1 (more work needs to be done) if there's still stuff in the array
			
			NSString *theFile = ResolveAliasToPath(origPath);
			NSSize cellSize = [DYWrappingMatrix maxCellSize];
			NSImage *thumb = [thumbsCache imageForKey:theFile];
			BOOL addedToCache = NO;
			if (thumb) {
				[thumbsCache beginAccess:theFile];
				addedToCache = YES;
			} else {
				// we're rolling our own cancelPreviousPerformRequestsWithTarget here
				// before updating the status field in the main thread, we check if anyone else has modified it (or dispatched a block to modify it) after the timeStamp
				[self updateStatusOnMainThread:^NSString *{
					if ([imgMatrix numCells] == 0) return nil; // don't set status string if there are no thumbs (could happen if a file is in the queue when the path changes)
					[_accessedLock lock];
					NSUInteger i = _accessedFiles.count;
					[_accessedLock unlock];
					return [NSString stringWithFormat:loadingMsg, i+1, [imgMatrix numCells]];
				}];
				if ([thumbsCache attemptLockOnFile:theFile]) { // will sleep if pending
					DYImageInfo *result = [[DYImageInfo alloc] initWithPath:theFile];
					if (FileIsJPEG(theFile)) {
						result.image =
						[EpegWrapper imageWithPath:theFile
									   boundingBox:cellSize
										   getSize:&result->pixelSize
										 exifThumb:useExifThumbs
									getOrientation:&result->exifOrientation];
						//	NSLog(@"Epeg error: %@", [EpegWrapper jpegErrorMessage]); // ** this isn't cleared between invocations
					}
					if (!result.image)
						[thumbsCache createScaledImage:result];

					if (result.image) {
						[thumbsCache addImage:result forFile:theFile];
						addedToCache = YES;
					}
					else
						[thumbsCache dontAddFile:theFile]; //NSLog(@"couldn't load image %@", origPath);
					thumb = result.image;
				} else {
					// someone beat us to it
					thumb = [thumbsCache imageForKey:theFile];
					if (thumb) {
						[thumbsCache beginAccess:theFile];
						addedToCache = YES;
					}
				}
			}

			if (!thumb) thumb = _brokenDoc;
			dispatch_async(dispatch_get_main_queue(), ^{
				if ([imgMatrix setImage:thumb atIndex:[d[1] unsignedIntegerValue] forFilename:origPath]) {
					if (addedToCache) {
						[_accessedLock lock];
						[_accessedFiles addObject:origPath];
						[_accessedLock unlock];
					}
				} else if (addedToCache) {
					[thumbsCache endAccess:origPath];
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
}

@end
