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

@interface DirBrowserDelegate (Private)
- (int)loadDir:(NSString *)path inCol:(int)n;
@end

@implementation DirBrowserDelegate
- (id)init {
    if (self = [super init]) {
		cols = [[NSMutableArray alloc] init];
		colsInternal = [[NSMutableArray alloc] init];
		hidden = floor(NSAppKitVersionNumber) <= 743
			? [[[NSString stringWithContentsOfFile:@"/.hidden"] componentsSeparatedByString:@"\n"] retain]
			: [[NSArray alloc] init]; // no .hidden in 10.4
		
		kq = [[UKKQueue alloc] init];
		[kq addPathToQueue:BROWSER_ROOT notifyingAbout:NOTE_WRITE];
		[kq setDelegate:self];
    }
    return self;
}

- (void)dealloc {
	[kq release];
	[cols release];
	[colsInternal release];
	[hidden release];
	[super dealloc];
}

-(void) kqueue: (UKKQueue*)q receivedNotification: (NSString*)nm forFile: (NSString*)fpath
{
	NSLog(@"got %@ for %@", nm, fpath);
	if ([nm isEqualToString:UKKQueueFileRenamedNotification]) {
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
	[self setPath:newPath ? newPath : currPath]; // don't actually set currPath here
												 // wait for browserWillSendAction to do it
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
	//return [_b setPath:aPath];
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
	if ([_b setPath:s]) return YES;
	[_b selectRow:0 inColumn:0]; // if it failed, try it again *sigh*
	return [_b setPath:s];
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
	NSMutableArray *a,*a2;
	a = [cols objectAtIndex:n];
	a2 = [colsInternal objectAtIndex:n];
	[a removeAllObjects];
	[a2 removeAllObjects];
	
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
			if (n==1 && [hidden containsObject:obj])
				continue;
			if (FileIsInvisible(fullpath))
				continue;
		}
		[fm fileExistsAtPath:fullpath isDirectory:&isDir];
		if (isDir) {
			[a2 addObject:obj];
			//if (n==0) NSLog(@"%@", obj);
			//obj = [fm displayNameAtPath:fullpath];
			[a addObject:[fm displayNameAtPath:fullpath]];
			//[a addObject:obj];
			//if (n==0) NSLog(@"%@", obj);
		}
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
	NSMutableArray *a = [colsInternal objectAtIndex:column];
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

	[currPath release];
	currPath = [newPath retain];
	
	FSRef f;
	DisposeHandle((Handle)currAlias);
	currAlias = NULL;
	if (FSPathMakeRef([[self path] fileSystemRepresentation],&f,NULL) == noErr) {
		FSNewAlias(NULL,&f,&currAlias);
	}
}
@end
