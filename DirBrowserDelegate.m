//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "DirBrowserDelegate.h"
#import "DYCarbonGoodies.h"
#import "VDKQueue.h"

NSString *_Volumes = @"/Volumes";

NSString *defaultPath(void) {
	NSFileManager *fm = NSFileManager.defaultManager;
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	NSString *path = [u stringForKey:@"picturesFolderPath"];
	if (![fm fileExistsAtPath:path])
		path = NSHomeDirectory();
	return path;
}

@interface DirBrowserDelegate () <VDKQueueDelegate>
@end

@implementation DirBrowserDelegate
{
	NSMutableArray *cols, *colsInternal;
	NSString *rootVolumeName;
	BOOL browserInited; // work around NSBrowser bug
	
	NSString *currPath;
	NSData *currAlias;
	NSArray *currBrowserPathComponents;
	NSMutableSet *revealedDirectories;
	
	VDKQueue *kq;
}
@synthesize _b;

- (id)init {
    if (self = [super init]) {
		cols = [[NSMutableArray alloc] init];
		colsInternal = [[NSMutableArray alloc] init];
		
		kq = [[VDKQueue alloc] init];
		kq.delegate = self;
		[kq addPath:_Volumes notifyingAbout:NOTE_WRITE];
		revealedDirectories = [[NSMutableSet alloc] initWithObjects:[@"~/Desktop/" stringByResolvingSymlinksInPath], nil];
    }
    return self;
}

- (void)dealloc {
	[kq stopWatching];
	[kq release];
	[cols release];
	[colsInternal release];
	[rootVolumeName release];
	[currPath release];
	[currAlias release];
	[revealedDirectories release];
	[super dealloc];
}

- (void)VDKQueue:(VDKQueue *)q receivedNotification:(NSString *)nm forPath:(NSString *)fpath
{
	// we get "write" notifications for /Volumes, and delete/rename notifications for everything else
	BOOL isRenamed = nm == VDKQueueRenameNotification;
	BOOL isTrashed = NO;
	if (isRenamed) {
		// check if the "rename" is actually a move-to-trash
		NSString *newPath = [[NSURL URLByResolvingBookmarkData:currAlias options:(NSURLBookmarkResolutionWithoutUI|NSURLBookmarkResolutionWithoutMounting) relativeToURL:nil bookmarkDataIsStale:NULL error:NULL] path];
		NSString *trashPath = [[NSFileManager.defaultManager URLsForDirectory:NSTrashDirectory inDomains:NSLocalDomainMask][0] path];
		if ([newPath hasPrefix:trashPath]) {
			isTrashed = YES;
		}
	}
	NSString *newPath = nil;
	if (isRenamed && !isTrashed) {
		// if a directory was renamed, currAlias should be able to resolve it to the new path
	} else if (![fpath isEqual:_Volumes]) {
		// if we get here, something was deleted (or worse, expelled)
		newPath = [fpath stringByDeletingLastPathComponent];
		while (![NSFileManager.defaultManager fileExistsAtPath:newPath] && newPath.length > 1) {
			newPath = [fpath stringByDeletingLastPathComponent];
		}
		if (newPath.length == 1) newPath = defaultPath();
	} else if (![NSFileManager.defaultManager fileExistsAtPath:currPath]) {
		newPath = defaultPath();
	}

	// the display name doesn't update immediately, it seems
	// so we wait a fraction of a second
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(100 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
		[_b loadColumnZero];
		NSString *path = newPath ?: [[NSURL URLByResolvingBookmarkData:currAlias options:(NSURLBookmarkResolutionWithoutUI|NSURLBookmarkResolutionWithoutMounting) relativeToURL:nil bookmarkDataIsStale:NULL error:NULL] path];
		browserInited = NO;
		[self setPath:path];
		[_b sendAction];
	});
}

#pragma mark public
// use to convert result from path or pathToColumn
-(NSString*)browserpath2syspath:(NSString *)s {
	//return s;
	if (!rootVolumeName)
		[self loadDir:_Volumes inCol:0]; // init rootVolumeName
	if ([rootVolumeName isEqualToString:s])
		return @"/";
	if ([rootVolumeName isEqualToString:[_b pathToColumn:1]]) {
		return [s substringFromIndex:[rootVolumeName length]];
	}
	return [_Volumes stringByAppendingString:s];
}

-(NSString*)path {
	NSString *s = [_b path];
	//return s;
	if (![_b isLoaded]) return s;
	return [self browserpath2syspath:s];
}

-(NSString *)savedPath {
	// safe to call from outside main thread
	return currPath;
}

-(void)setPath:(NSString *)aPath {
	NSString *s;
	NSRange r = [aPath rangeOfString:_Volumes];
	if (r.location == 0) {
		s = [aPath substringFromIndex:r.length];
	} else {
		if (!rootVolumeName)
			[self loadDir:_Volumes inCol:0]; // init rootVolumeName
		if ([aPath isEqualToString:@"/"])
			s = rootVolumeName;
		else
			s = [rootVolumeName stringByAppendingString:aPath];
	}
	// save currPath here so browser can look ahead for invisible directories when loading
	currBrowserPathComponents = [s pathComponents];
	if (!browserInited) {
		[_b selectRow:0 inColumn:0];
		browserInited = YES;
	}
	if (![_b setPath:s]) {
		// we need to call setPath a second time if the first attempt fails.
		// a failure could occur if you try to set the path to one that is not currently shown in the browser
		// e.g., a new folder has been created, or we're trying to load something in an invisible folder that wasn't loaded before
		[_b selectRow:0 inColumn:0];
		[_b setPath:s];
	}
	currBrowserPathComponents = nil;
}

#pragma mark private
// puts array of directory names located in path
// into our display and internal arrays
- (NSInteger)loadDir:(NSString *)path inCol:(NSInteger)n {
	NSFileManager *fm = [NSFileManager defaultManager];
	while ([cols count] < n+1) {
		[cols addObject:[NSMutableArray arrayWithCapacity:15]];
		[colsInternal addObject:[NSMutableArray arrayWithCapacity:15]];
	}
	NSMutableArray *sortArray = [NSMutableArray arrayWithCapacity:15];
	NSString *nextColumn = nil;
	if ([currBrowserPathComponents count] > n+1)
		nextColumn = currBrowserPathComponents[n+1];
	
	// ignore NSError here, forin can handle both nil and empty arrays
	for (NSString *filename in [fm contentsOfDirectoryAtPath:path error:NULL]) {
		NSString *fullpath = [path stringByAppendingPathComponent:filename];
		if (n==0 && [[fm destinationOfSymbolicLinkAtPath:fullpath error:NULL] isEqualToString:@"/"]) {
			// initialize rootVolumeName here
			// executes only on loadColumnZero, saves @"/Macintosh HD" or so
			[rootVolumeName release];
			rootVolumeName = [[@"/" stringByAppendingString:filename] retain];
		}
		if (n==1 && [fullpath isEqualToString:_Volumes]) continue; // always skip /Volumes
		BOOL isInvisible = FileIsInvisible(fullpath) || [filename characterAtIndex:0] == '.';
		if (isInvisible) {
			if (nextColumn && [filename isEqualToString:nextColumn])
				[revealedDirectories addObject:fullpath];
			// skip invisible directories unless we've specifically navigated to one
			if (![revealedDirectories containsObject:fullpath]) continue;
		}
		BOOL isDir;
		[fm fileExistsAtPath:fullpath isDirectory:&isDir];
		if (isDir) {
			[sortArray addObject:@[[fm displayNameAtPath:fullpath], filename]];
		}
	}
	// sort it so it makes sense! the OS doesn't always give directory contents in a convenient order
	[sortArray sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
		return [a[0] localizedStandardCompare:b[0]];
	}];
	NSMutableArray *displayNames = cols[n];
	NSMutableArray *filesystemNames = colsInternal[n];
	[displayNames removeAllObjects];
	[filesystemNames removeAllObjects];
	for (NSArray *nameArray in sortArray) {
		[displayNames addObject:nameArray[0]];
		[filesystemNames addObject:nameArray[1]];
	}
	return [displayNames count];
}

#pragma mark NSBrowser delegate methods
- (NSInteger)browser:(NSBrowser *)b numberOfRowsInColumn:(NSInteger)c {
	return [self loadDir:(c == 0
						  ? _Volumes
						  : [self browserpath2syspath:[b pathToColumn:c]])
				   inCol:c];
}

- (void)browser:(NSBrowser *)b willDisplayCell:(id)cell atRow:(NSInteger)row column:(NSInteger)column {
	[cell setStringValue:colsInternal[column][row]];
	[cell setTitle:cols[column][row]];
}

#pragma mark DYCreeveyBrowserDelegate methods
- (void)browser:(NSBrowser *)b typedString:(NSString *)s inColumn:(NSInteger)column {
	NSMutableArray *a = cols[column]; // use cols, not colsInternal here, since we sort by display names
	NSUInteger i, n = [a count];
	NSUInteger inputLength = s.length;
	for (i=0; i<n; ++i) {
		NSString *label = a[i];
		NSString *labelSubstring = [label substringToIndex:MIN(label.length, inputLength)];
		if ([labelSubstring localizedStandardCompare:s] >= 0)
			break;
	}
	if (i==n) --i;
	[b selectRow:i inColumn:column];
	[b sendAction];
}

- (void)browserWillSendAction:(NSBrowser *)b {
	// we assume that every time the path changes, browser will send action
	// that means if you change the path programmatically, you should also call sendAction right away to make sure this code executes
	NSString *newPath = [self path];
	if ([currPath isEqualToString:newPath]) return;
	
	NSString *s = currPath ? currPath : @"/";
	if (currPath) {
		// read like perl until(...)
		while (!([newPath hasPrefix:s] &&
				 ([s length] == 1 // @"/"
				  || [newPath length] == [s length]
				  || [newPath characterAtIndex:[s length]] == '/'))) {
			if (![s isEqualToString:_Volumes]) {
				[kq removePath:s];
			}
			s = [s stringByDeletingLastPathComponent];
		}
	}
	// s is now the shared prefix
	if ([s isEqualToString:@"/"] && [newPath hasPrefix:@"/Volumes/"]) {
		// ** 9 is length of @"/Volumes/"
		NSRange r = [newPath rangeOfString:@"/" options:0 range:NSMakeRange(9,[newPath length]-9)];
		if (r.location != NSNotFound)
			s = [newPath substringToIndex:r.location];
		else
			s = newPath;
	}
	NSString *newPathTmp = newPath;
	while (!([newPathTmp isEqualToString:s])) {
		[kq addPath:newPathTmp notifyingAbout:NOTE_RENAME|NOTE_DELETE];
		if ([newPathTmp isEqualToString:@"/"])
			break;
		newPathTmp = [newPathTmp stringByDeletingLastPathComponent];
	}

	[currPath release];
	currPath = [newPath retain];
	[currAlias release];
	currAlias = [[[NSURL fileURLWithPath:currPath isDirectory:YES] bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:NULL] retain];
}
@end
