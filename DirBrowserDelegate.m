//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "DirBrowserDelegate.h"
#import "DYCreeveyBrowser.h"
#import "VDKQueue.h"

static NSString * const _Volumes = @"/Volumes";

static NSString *defaultPath(void) {
	NSFileManager *fm = NSFileManager.defaultManager;
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	NSString *path = [u stringForKey:@"picturesFolderPath"];
	if (![fm fileExistsAtPath:path])
		path = NSHomeDirectory();
	return path;
}

@interface DirBrowserDelegate () <VDKQueueDelegate, DYCreeveyBrowserDelegate>
@property (nonatomic, strong) NSString *rootVolumeName;
@property (strong) NSString *currPath;
@property (nonatomic, strong) NSURL *currFileRef;
@end

@implementation DirBrowserDelegate
{
	NSMutableArray *cols, *colsInternal;
	BOOL browserInited; // work around NSBrowser bug

	NSArray *currBrowserPathComponents;
	
	VDKQueue *kq;
	id _mountVolumeObserver, _unmountVolumeObserver, _renameVolumeObserver;
}
@synthesize rootVolumeName, currPath, currFileRef, revealedDirectories;

- (instancetype)init {
    if (self = [super init]) {
		cols = [[NSMutableArray alloc] init];
		colsInternal = [[NSMutableArray alloc] init];
		
		kq = [[VDKQueue alloc] init];
		kq.delegate = self;
    }
    return self;
}
- (void)dealloc {
	NSNotificationCenter *w = NSWorkspace.sharedWorkspace.notificationCenter;
	[w removeObserver:_mountVolumeObserver];
	[w removeObserver:_unmountVolumeObserver];
	[w removeObserver:_renameVolumeObserver];
	[kq stopWatching];
}

- (void)awakeFromNib {
	DirBrowserDelegate * __weak zelf = self;
	NSBrowser * __weak b = _b;
	NSNotificationCenter *w = NSWorkspace.sharedWorkspace.notificationCenter;
	_mountVolumeObserver = [w addObserverForName:NSWorkspaceDidMountNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
		[b reloadColumn:0];
	}];
	_unmountVolumeObserver = [w addObserverForName:NSWorkspaceDidUnmountNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
		NSString *unmountedPath = n.userInfo[@"NSDevicePath"];
		if ([zelf.currPath hasPrefix:unmountedPath]) {
			[b loadColumnZero];
			[zelf setPathAndInitBrowser:defaultPath()];
			[b sendAction];
		} else {
			[b reloadColumn:0];
			// it might be more efficient to directly modify our "cols" arrays, then set some switch to indicate that
			// browser:numberOfRowsInColumn: doesn't need to get a new directory listing, resort, etc., but probably only if the user has a gazillion volumes
		}
	}];
	_renameVolumeObserver = [w addObserverForName:NSWorkspaceDidRenameVolumeNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
		[b reloadColumn:0];
		id volId, currFileVolId;
		NSURL *vol = n.userInfo[NSWorkspaceVolumeURLKey];
		NSURL *cfr = zelf.currFileRef;
		if ([vol getResourceValue:&volId forKey:NSURLVolumeIdentifierKey error:NULL] &&
			[cfr getResourceValue:&currFileVolId forKey:NSURLVolumeIdentifierKey error:NULL] &&
			[volId isEqual:currFileVolId]) {
			[zelf setPathAndInitBrowser:cfr.path];
			[zelf browserWillSendAction:b];
			NSInteger col = b.selectedColumn;
			[b selectRow:[b selectedRowInColumn:col] inColumn:col];
		}
	}];
}

- (void)VDKQueue:(VDKQueue *)q receivedNotification:(u_int)flags forPath:(NSString *)fpath
{
	// we get delete/rename notifications for anything that is not in /Volumes
	BOOL isRenamed = flags & VDKQueueNotifyAboutRename;
	BOOL isTrashed = NO;
	if (isRenamed) {
		// check if the "rename" is actually a move-to-trash
		NSString *newPath = currFileRef.path;
		NSString *trashPath = ([NSFileManager.defaultManager URLsForDirectory:NSTrashDirectory inDomains:NSLocalDomainMask][0]).path;
		if ([newPath hasPrefix:trashPath]) {
			isTrashed = YES;
		}
	}
	NSString *newPath = nil;
	// if a directory was renamed, currFileRef should be able to resolve it to the new path
	if (!isRenamed || isTrashed) {
		// if we get here, something was deleted (or worse, expelled)
		newPath = fpath.stringByDeletingLastPathComponent;
		while (![NSFileManager.defaultManager fileExistsAtPath:newPath] && newPath.length > 1) {
			newPath = fpath.stringByDeletingLastPathComponent;
		}
		if (newPath.length == 1) newPath = defaultPath();
	}

	NSString *path = newPath ?: currFileRef.path;
	browserInited = NO;
	[self setPath:path];
	if (newPath) {
		[_b sendAction];
	} else {
		// avoid sending the action, which would reload the thumbs and reset the scrollview
		[self browserWillSendAction:_b];
		// this can cause the active selection to go back to column zero, so force it back to the last column
		NSInteger col = _b.selectedColumn;
		[_b selectRow:[_b selectedRowInColumn:col] inColumn:col];
	}
}

#pragma mark public
// use to convert result from path or pathToColumn
-(NSString*)browserpath2syspath:(NSString *)s {
	if (!rootVolumeName)
		[self loadDir:_Volumes inCol:0]; // init rootVolumeName
	if ([rootVolumeName isEqualToString:s])
		return @"/";
	if ([rootVolumeName isEqualToString:[_b pathToColumn:1]]) {
		return [s substringFromIndex:rootVolumeName.length];
	}
	return [_Volumes stringByAppendingString:s];
}

-(NSString*)path {
	NSString *s = [_b path];
	if (!_b.loaded) return s;
	return [self browserpath2syspath:s];
}

-(void)setPathAndInitBrowser:(NSString *)s {
	browserInited = NO;
	[self setPath:s];
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
	currBrowserPathComponents = s.pathComponents;
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
	NSFileManager *fm = NSFileManager.defaultManager;
	while (cols.count < n+1) {
		[cols addObject:[NSMutableArray arrayWithCapacity:15]];
		[colsInternal addObject:[NSMutableArray arrayWithCapacity:15]];
	}
	NSMutableArray *sortArray = [NSMutableArray arrayWithCapacity:15];
	NSString *nextColumn = nil;
	if (currBrowserPathComponents.count > n+1)
		nextColumn = currBrowserPathComponents[n+1];
	
	// ignore NSError here, forin can handle both nil and empty arrays
	for (NSURL *url in [fm contentsOfDirectoryAtURL:[NSURL fileURLWithPath:path isDirectory:YES] includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsHiddenKey] options:0 error:NULL]) {
		NSString *filename = url.lastPathComponent;
		if (n==0 && [[fm destinationOfSymbolicLinkAtPath:url.path error:NULL] isEqualToString:@"/"]) {
			// initialize rootVolumeName here
			self.rootVolumeName = [@"/" stringByAppendingString:filename];
		}
		if (n==1 && [url.path isEqualToString:_Volumes]) continue; // always skip /Volumes
		NSNumber *val;
		if (([filename characterAtIndex:0] == '.' && n > 0) || ([url getResourceValue:&val forKey:NSURLIsHiddenKey error:NULL] && val.boolValue)) {
			if (nextColumn && [filename isEqualToString:nextColumn])
				[revealedDirectories addObject:url];
			// skip invisible directories unless we've specifically navigated to one
			if (![revealedDirectories containsObject:url]) continue;
		}
		NSString *displayName = filename;
		if (n == 0 || ([url getResourceValue:&val forKey:NSURLIsDirectoryKey error:NULL] && val.boolValue)) {
			[url getResourceValue:&displayName forKey:NSURLLocalizedNameKey error:NULL];
			[sortArray addObject:@[displayName, filename]];
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
	return displayNames.count;
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
	NSUInteger i, n = a.count;
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

// when the path changes, we need to update the paths that kqueue is watching. This will be called
// from DYBrowser's sendAction: method, or (if you change the path without calling sendAction:) you can call this directly
- (void)browserWillSendAction:(NSBrowser *)b {
	NSString *newPath = [self path];
	if ([currPath isEqualToString:newPath]) return;
	
	// currPath will be nil if the window is first being instantiated. In this case we skip the removal process, and initialize s to /
	NSString *s = currPath ?: @"/";
	if (currPath) {
		// keep removing path components from the old path (and deregistering them from kqueue)
		// until you find a directory that is also a directory on the new path (could be root, newPath exactly, or some parent directory of both)
		while (!([newPath hasPrefix:s] &&
				 (s.length == 1 // @"/"
				  || newPath.length == s.length
				  || [newPath characterAtIndex:s.length] == '/'))) {
			[kq removePath:s];
			s = s.stringByDeletingLastPathComponent;
		}
	}
	// s is now the shared prefix
	// we will register with kqueue all the new path components
	// but skip anything directly inside /Volumes. We will use NSWorkspace notifications to watch for mounted/renamed volumes instead.
	if ([s isEqualToString:@"/"] && [newPath hasPrefix:@"/Volumes/"]) {
		NSRange r = [newPath rangeOfString:@"/" options:0 range:NSMakeRange(9,newPath.length-9)]; // 9 is length of @"/Volumes/"
		if (r.location != NSNotFound)
			s = [newPath substringToIndex:r.location];
		else
			s = newPath;
	}
	NSString *newPathTmp = newPath;
	while (!([newPathTmp isEqualToString:s])) {
		[kq addPath:newPathTmp notifyingAbout:NOTE_RENAME|NOTE_DELETE];
		newPathTmp = newPathTmp.stringByDeletingLastPathComponent;
	}

	self.currPath = newPath;
	self.currFileRef = [NSURL fileURLWithPath:currPath isDirectory:YES].fileReferenceURL;
}
@end
