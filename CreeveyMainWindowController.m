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
#import "DYCreeveyBrowser.h"
#import "DYImageCache.h"
#import "DYWrappingMatrix.h"
#import <sys/stat.h>
#import "DYExiftags.h"

@implementation NSString (DateModifiedCompare)

/* Using file attributes to sort file paths and then rely on the sort order staying the same
 * is somewhat dangerous because the file might have been modified (changing the modification date)
 * or moved (making the path invalid). We try to mitigate this by watching for changes to the filesystem. */

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

@end


@interface CreeveyMainWindowController () <DYFileWatcherDelegate>
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
	NSMutableArray *imageCacheQueue, *secondaryImageCacheQueue;
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
}

- (void)dealloc {
	[NSUserDefaultsController.sharedUserDefaultsController removeObserver:self forKeyPath:@"values.DYWrappingMatrixMaxCellWidth"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)c context:(void *)context
{
	if ([keyPath isEqualToString:@"values.DYWrappingMatrixMaxCellWidth"]) {
		_maxCellWidth = [NSUserDefaults.standardUserDefaults integerForKey:@"DYWrappingMatrixMaxCellWidth"];
	}
}

- (void)window:(NSWindow *)window willEncodeRestorableState:(NSCoder *)state
{
	BOOL collapsed = statusFld.superview.hidden;
	NSDictionary *data = @{@"path":self.path, @"split1":@(collapsed ? 0.0 : statusFld.superview.frame.size.height)};
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

// returns NO if doesn't exist, useful for applicationDidFinishLaunching
- (BOOL)setPath:(NSString *)s {
	NSFileManager *fm = NSFileManager.defaultManager;
	BOOL isDir;
	if (![fm fileExistsAtPath:s isDirectory:&isDir])
		return NO;
	if (!isDir)
		s = s.stringByDeletingLastPathComponent;
	[dirBrowserDelegate setPath:s];
	[dirBrowser sendAction];
	[self.window invalidateRestorableState];
	return YES;
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
	NSString *browserPath = dirBrowserDelegate.currPath;
	if (self.wantsSubfolders) return [filename hasPrefix:[browserPath stringByAppendingString:@"/"]];
	return [filename.stringByDeletingLastPathComponent isEqualToString:browserPath];
}

- (void)updateDefaults {
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	if ([u integerForKey:@"startupOption"] == 0)
		[u setObject:[dirBrowserDelegate path] forKey:@"lastFolderPath"];
	[u setFloat:imgMatrix.cellWidth forKey:@"thumbCellWidth"];
	float height = statusFld.superview.hidden ? 0 : statusFld.superview.frame.size.height;
	[u setFloat:height forKey:@"MainWindowSplitViewTopHeight"];
	[self.window saveFrameUsingName:@"MainWindowLoc"];
}


- (BOOL)currentFilesDeletable { return currentFilesDeletable; }
- (BOOL)filenamesDone { return filenamesDone; }
- (NSArray *)displayedFilenames { return displayedFilenames; }
- (NSUInteger)indexOfFilename:(NSString *)s {
	return [displayedFilenames indexOfObject:s inSortedRange:NSMakeRange(0, displayedFilenames.count) options:0 usingComparator:self.comparator];
}
NSComparator ComparatorForSortOrder(short sortOrder) {
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
		case 3:
			return ^NSComparisonResult(id a, id b) {
				return [a exifDateCompare:b];
			};
		case -3:
			return ^NSComparisonResult(id a, id b) {
				return [b exifDateCompare:a];
			};
	}
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

- (void)openFiles:(NSArray *)a withSlideshow:(BOOL)doSlides{
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

- (void)watcherFiles:(NSArray *)files deleted:(NSArray *)deleted {
	if (!filenamesDone) return;
	BOOL sortByModTime = abs(self.sortOrder) == 2;
	for (NSString *s in files) {
		NSUInteger count = filenames.count;
		struct stat buf;
		if (sortByModTime && !stat(s.fileSystemRepresentation, &buf) && buf.st_mtimespec.tv_sec > matrixModTime) {
			// when sorting by mod time, file list needs to be adjusted if the file's mod time has changed!
			NSUInteger oldIdx, idx = [filenames updateIndexOfObject:s usingComparator:self.comparator oldIndex:&oldIdx];
			if (idx != NSNotFound) {
				if (displayedFilenames.count != filenames.count)
					idx = [displayedFilenames updateIndexOfObject:s usingComparator:self.comparator oldIndex:&oldIdx];
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
	} else { // ** dup
		if ([thumbsCache attemptLockOnFile:theFile]) {
			DYImageInfo *result = [[DYImageInfo alloc] initWithPath:theFile];
			[thumbsCache createScaledImage:result];
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
			[appDelegate.thumbsCache endAccess:s];
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
	NSString *status = currCat
		? [NSString stringWithFormat:@"%@: %@",
			[NSString stringWithFormat:NSLocalizedString(@"Group %i", @""), currCat],
			[NSString stringWithFormat:s, displayedFilenames.count]]
		: [NSString stringWithFormat:s, filenames.count];
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
			NSDirectoryEnumerator *e = CreeveyEnumerator(thePath, recurseSubfolders);
			for (NSURL *url in e) {
				@autoreleasepool {
					if ([appDelegate handledDirectory:url subfolders:recurseSubfolders e:e])
						continue;
					if ([appDelegate shouldShowFile:url]) {
						NSString *aPath = url.path;
						[filenames addObject:aPath];
						if (startSlideshowWhenReady && [filesBeingOpened containsObject:aPath])
							[filesForSlideshow addObject:aPath];
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
	slidesBtn.enabled = NO;
	NSString *currentPath = [dirBrowserDelegate path];
	_subfoldersButton.enabled = ![currentPath isEqualToString:@"/"]; // let's not ever load up the entire file system
	if (self.wantsSubfolders && sender) { // sender is dirBrowserDelegate when non-nil
		if (![currentPath hasPrefix:_recurseRoot]) {
			self.wantsSubfolders = NO;
			_subfoldersButton.state = NSControlStateValueOff;
		}
	}
	[self updateStatusString:NSLocalizedString(@"Getting filenames...", @"")];
	[self.window setTitleWithRepresentedFilename:currentPath];
	[NSThread detachNewThreadSelector:@selector(loadImages:)
							 toTarget:self withObject:currentPath];
}

- (IBAction)setRecurseSubfolders:(id)sender {
	NSButton *button = sender;
	self.wantsSubfolders = (button.state == NSOnState);
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
- (void)selectAll:(id)sender{
	[self.window makeFirstResponder:imgMatrix];
	[imgMatrix selectAll:sender];
}

- (void)selectNone:(id)sender{
	[imgMatrix selectNone:sender];
}


#pragma mark event stuff
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
	float height = statusFld.superview.hidden ? 0 : statusFld.superview.frame.size.height;
	[NSUserDefaults.standardUserDefaults setFloat:height forKey:@"MainWindowSplitViewTopHeight"];
}

-(BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
	return subview == dirBrowser.superview;
}

#pragma mark wrapping matrix methods
- (void)wrappingMatrixSelectionDidChange:(NSIndexSet *)selectedIndexes {
	NSString *s;
	NSUInteger count = selectedIndexes.count;
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
						}
						CFRelease(imgSrc);
					} else
						pixelSize = NSZeroSize;
				}
			}
			NSUInteger idx = [dirBrowserDelegate path].length+1;
			NSString *fileName = idx > path.length ? path : [path substringFromIndex:idx];
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
				 [NSString stringWithFormat:NSLocalizedString(@"%d images selected.", @""), (unsigned int)selectedIndexes.count],
				 FileSize2String(totalSize)];
		}
	}
	bottomStatusFld.stringValue = s;
	[self updateExifInfo];
}

- (NSImage *)wrappingMatrixWantsImageForFile:(NSString *)filename atIndex:(NSUInteger)i {
	DYImageCache *thumbsCache = appDelegate.thumbsCache;
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
	DYImageCache *thumbsCache = appDelegate.thumbsCache;
	// only use exif thumbs if we're at the smallest thumbnail  setting
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
				currState = imgMatrix.currentState;
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
			NSArray *d;
			NSString *origPath;
			// discard any items in the queue that are no longer in the browser's directory.
			// prioritize important files (the visible ones) by putting them in a higher-priority array.
			if (!visibleQueue.count                   // nothing in the priority queue, so search for more items to add to it...
				&& imageCacheQueue.count != lastCount // but skip this if nothing has been added to the queue
				)
			{
				i = imageCacheQueue.count;
				while (i--) {
					d = imageCacheQueue[i];
					origPath = d[0];
					//NSLog(@"considering %@ for priority queue", [d objectForKey:@"index"]);
					if (![self pathIsVisibleThreaded:origPath]) {
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
					origPath = d[0];
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
				origPath = d[0];
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
			
			NSString *theFile = ResolveAliasToPath(origPath);
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
				if ([thumbsCache attemptLockOnFile:theFile]) { // will sleep if pending
					char *data;
					size_t len;
					unsigned short thumbW, thumbH, rawW, rawH, orientation;
					enum dcraw_type thumbType;
					DYImageInfo *result = [[DYImageInfo alloc] initWithPath:theFile];
					if (IsRaw(theFile.pathExtension.lowercaseString) &&
							   (data = ExtractThumbnailFromRawFile(theFile.fileSystemRepresentation, &len, &thumbW, &thumbH, &thumbType, &rawW, &rawH, &orientation))) {
						result->exifOrientation = orientation; // this needs to be set before
						[thumbsCache createScaledImage:result fromData:[NSData dataWithBytesNoCopy:data length:len freeWhenDone:NO] ofType:thumbType];
						result->pixelSize.width = rawW; // these need to be set after (otherwise the width/height are for the thumb)
						result->pixelSize.height = rawH;
						free(data);
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
						if (exifWindowNeedsUpdate && self.window.isMainWindow && [imgMatrix.firstSelectedFilename isEqualToString:origPath]) {
							[self updateExifInfo];
						}
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
