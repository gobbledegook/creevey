//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "DirBrowserDelegate.h"
#import "DYCarbonGoodies.h"
#import "UKKQueue.h"

#define BROWSER_ROOT @"/Volumes"

// our special comparator which takes instead of a string,
// an array where we're interested in the first item.
@implementation NSArray (EmbeddedFinderCompare)
- (NSComparisonResult)embeddedFinderCompare:(NSArray *)anArray
{
	NSString *aString = [anArray objectAtIndex:0];
	NSString *myString = [self objectAtIndex:0];
	SInt32 compareResult;
	
	CFIndex lhsLen = [myString length];;
    CFIndex rhsLen = [aString length];
	
	UniChar *lhsBuf = malloc(lhsLen * sizeof(UniChar));
	UniChar *rhsBuf = malloc(rhsLen * sizeof(UniChar));
	
	[myString getCharacters:lhsBuf];
	[aString getCharacters:rhsBuf];
	
	(void) UCCompareTextDefault(kUCCollateComposeInsensitiveMask | kUCCollateWidthInsensitiveMask | kUCCollateCaseInsensitiveMask | kUCCollateDigitsOverrideMask | kUCCollateDigitsAsNumberMask| kUCCollatePunctuationSignificantMask,lhsBuf,lhsLen,rhsBuf,rhsLen,NULL,&compareResult);
	
	free(lhsBuf);
	free(rhsBuf);
	
	return (CFComparisonResult) compareResult;
}
@end


@interface DirBrowserDelegate (Private)
- (int)loadDir:(NSString *)path inCol:(int)n;
@end

@implementation DirBrowserDelegate
- (id)init {
    if (self = [super init]) {
		cols = [[NSMutableArray alloc] init];
		colsInternal = [[NSMutableArray alloc] init];
		
		kq = [[UKKQueue alloc] init];
		[kq addPathToQueue:BROWSER_ROOT notifyingAbout:NOTE_WRITE];
		[kq setDelegate:self];
		revealedDirectories = [[NSMutableSet alloc] initWithObjects:[@"~/Desktop/" stringByResolvingSymlinksInPath], nil];
    }
    return self;
}

- (void)dealloc {
	[kq release];
	[cols release];
	[colsInternal release];
	[rootVolumeName release];
	[currPath release];
	DisposeHandle((Handle)currAlias);
	[revealedDirectories release];
	[super dealloc];
}

- (void)watcher:(id<UKFileWatcher>)q receivedNotification:(NSString *)nm forPath:(NSString *)fpath
{
	if ([nm isEqualToString:UKFileWatcherRenameNotification]) {
		[kq removePathFromQueue:fpath];
	}
	// the display name doesn't update immediately, it seems
	// so we wait a fraction of a second
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[self performSelector:@selector(reload) withObject:nil afterDelay:0.1];
}

-(void)reload {
	[_b loadColumnZero];
	NSString *newPath = AliasToPath(currAlias);
	// if no newPath (files deleted?) fall back to currPath
	browserInited = NO;
	[self setPath:newPath ?: currPath]; // don't actually set currPath here, wait for browserWillSendAction to do it
	[_b sendAction];
}

#pragma mark public
-(void)setShowInvisibles:(BOOL)b {
	showInvisibles = b;
}

// use to convert result from path or pathToColumn
-(NSString*)browserpath2syspath:(NSString *)s {
	//return s;
	if (!rootVolumeName)
		[self loadDir:@"/Volumes" inCol:0]; // init rootVolumeName
	if ([rootVolumeName isEqualToString:s])
		return @"/";
	if ([rootVolumeName isEqualToString:[_b pathToColumn:1]]) {
		return [s substringFromIndex:[rootVolumeName length]];
	}
	return [@"/Volumes" stringByAppendingString:s];
}

-(NSString*)path {
	NSString *s = [_b path];
	//return s;
	if (![_b isLoaded]) return s;
	return [self browserpath2syspath:s];
}

-(BOOL)setPath:(NSString *)aPath {
	NSString *s;
	NSRange r = [aPath rangeOfString:@"/Volumes"];
	if (r.location == 0) {
		s = [aPath substringFromIndex:r.length];
	} else {
		if (!rootVolumeName)
			[self loadDir:@"/Volumes" inCol:0]; // init rootVolumeName
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
	if ([_b setPath:s]) {
		// in 10.6, this will fail unexpectedly with no warning the first time this is run. Hence, the previous line.
		// This will also fail if you try set the path to a non-existent path (e.g. if the directory was just deleted).
		currBrowserPathComponents = nil;
		return YES;
	}
	
	[_b selectRow:0 inColumn:0]; // if it failed, try it again *sigh*
	 // work around stupid bug, doesn't auto-select cell 0
	BOOL result = [_b setPath:s];
	currBrowserPathComponents = nil;
	return result;
}

#pragma mark private
// puts array of directory names located in path
// into our display and internal arrays
- (int)loadDir:(NSString *)path inCol:(int)n {
	NSFileManager *fm = [NSFileManager defaultManager];
	while ([cols count] < n+1) {
		[cols addObject:[NSMutableArray arrayWithCapacity:15]];
		[colsInternal addObject:[NSMutableArray arrayWithCapacity:15]];
	}
	NSMutableArray *a,*a2,*tempArray;
	a = [cols objectAtIndex:n];
	a2 = [colsInternal objectAtIndex:n];
	[a removeAllObjects];
	[a2 removeAllObjects];
	tempArray = [NSMutableArray arrayWithCapacity:15];
	NSString *nextColumn = nil;
	if ([currBrowserPathComponents count] > n+1)
		nextColumn = [currBrowserPathComponents objectAtIndex:n+1];
	
	NSEnumerator *e = [[fm directoryContentsAtPath:path] objectEnumerator];
	BOOL isDir;
	NSString *obj, *fullpath;
	while (obj = [e nextObject]) {
		fullpath = [path stringByAppendingPathComponent:obj];
		if (n==0 && [[fm pathContentOfSymbolicLinkAtPath:fullpath] isEqualToString:@"/"]) {
			// initialize rootVolumeName here
			// executes only on loadColumnZero, saves @"/Macintosh HD" or so
			[rootVolumeName release];
			rootVolumeName = [[@"/" stringByAppendingString:obj] retain];
		}
		if (!showInvisibles) {
			if ([obj characterAtIndex:0] == '.') continue; // dot-files
			if (n==1 && [fullpath isEqualToString:@"/Volumes"])
				continue; // always skip /Volumes
			if (FileIsInvisible(fullpath)) {
				// if trying to browse to a specific directory, show it even if it's invisible
				if (nextColumn && [obj isEqualToString:nextColumn]) {
					[revealedDirectories addObject:fullpath];
				} else if (![revealedDirectories containsObject:fullpath]) {
					continue;
				}
			}
		}
		[fm fileExistsAtPath:fullpath isDirectory:&isDir];
		if (isDir) {
			[tempArray addObject:
			 [NSArray arrayWithObjects:
			  [fm displayNameAtPath:fullpath], obj, nil]];
			//if (n==0) NSLog(@"%@", obj);
			//obj = [fm displayNameAtPath:fullpath];
			//[a addObject:obj];
			//if (n==0) NSLog(@"%@", obj);
		}
	}
	// sort it so it makes sense! the OS doesn't always give directory contents in a convenient order
	[tempArray sortUsingSelector:@selector(embeddedFinderCompare:)];
	e = [tempArray objectEnumerator];
	NSArray *obj2;
	while ((obj2 = [e nextObject])) {
		[a addObject:[obj2 objectAtIndex:0]]; // display names
		[a2 addObject:[obj2 objectAtIndex:1]]; // actual (on disk) names
	}
	return [a count];
}

#pragma mark NSBrowser delegate methods
- (int)browser:(NSBrowser *)b numberOfRowsInColumn:(int)c {
	return [self loadDir:(c == 0
						  ? BROWSER_ROOT
						  : [self browserpath2syspath:[b pathToColumn:c]])
				   inCol:c];
}

- (void)browser:(NSBrowser *)b willDisplayCell:(id)cell atRow:(int)row column:(int)column {
	[cell setStringValue:[[colsInternal objectAtIndex:column] objectAtIndex:row]];
	[cell setTitle:[[cols objectAtIndex:column] objectAtIndex:row]];
}

- (void)browser:(NSBrowser *)b typedString:(NSString *)s inColumn:(int)column {
	NSMutableArray *a = [cols objectAtIndex:column]; // use cols, not colsInternal here, since we sort by display names
	unsigned int i, n = [a count];
	for (i=0; i<n; ++i) {
		if ([[a objectAtIndex:i] caseInsensitiveCompare:s] >= 0)
			break;
	}
	if (i==n) --i;
	[b selectRow:i inColumn:column];
	[b sendAction];
}

- (void)browserWillSendAction:(NSBrowser *)b {
	// we assume that every time the path changes, browser will send action
	// that means if a 3rd party calls setPath, they should call sendAction right away
	NSString *newPath = [self path];
	if ([currPath isEqualToString:newPath]) return;
	
	NSString *s = currPath ? currPath : @"/";
	if (currPath) {
		// read like perl until(...)
		while (!([newPath hasPrefix:s] &&
				 ([s length] == 1 // @"/"
				  || [newPath length] == [s length]
				  || [newPath characterAtIndex:[s length]] == '/'))) {
			if (![s isEqualToString:@"/Volumes"]) {
				[kq removePathFromQueue:s];
				//NSLog(@"ditched %@", s);
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
		[kq addPathToQueue:newPathTmp notifyingAbout:NOTE_RENAME|NOTE_DELETE];
		//NSLog(@"watching %@", newPathTmp);
		if ([newPathTmp isEqualToString:@"/"])
			break;
		newPathTmp = [newPathTmp stringByDeletingLastPathComponent];
	}

	[currPath autorelease];
	currPath = [newPath retain];
	
	FSRef f;
	DisposeHandle((Handle)currAlias);
	currAlias = NULL;
	if (FSPathMakeRef([[self path] fileSystemRepresentation],&f,NULL) == noErr) {
		FSNewAlias(NULL,&f,&currAlias);
	}
}
@end
