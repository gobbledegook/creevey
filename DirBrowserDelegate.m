//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "DirBrowserDelegate.h"
#import "DYCarbonGoodies.h"

@implementation DirBrowserDelegate
- (id)init {
    if (self = [super init]) {
		fm = [NSFileManager defaultManager];
		cols = [[NSMutableArray alloc] init];
		hidden = [[NSString stringWithContentsOfFile:@"/.hidden"] componentsSeparatedByString:@"\n"];
    }
    return self;
}

-(void)setShowInvisibles:(BOOL)b {
	showInvisibles = b;
}

- (int)loadDir:(NSString *)path inCol:(int)n {
	while ([cols count] < n+1) {
		[cols addObject:[NSMutableArray arrayWithCapacity:15]];
	}
	NSMutableArray *a = [cols objectAtIndex:n];
	[a removeAllObjects];
	NSEnumerator *e = [[fm directoryContentsAtPath:path] objectEnumerator];
	id obj;
	BOOL isDir;
	NSString *fullpath;
	while (obj = [e nextObject]) {
		fullpath = [path stringByAppendingPathComponent:obj];
		if (!showInvisibles) {
			if ([obj characterAtIndex:0] == '.') continue; // dot-files
			if (n==0 && [obj isEqualToString:@"Volumes"]) {
				[a addObject:obj]; // exception for /Volumes
				continue;
			}
			if (n==0 && [hidden containsObject:obj])
				continue;
			if (FileIsInvisible(fullpath)) continue;
		}
		[fm fileExistsAtPath:fullpath isDirectory:&isDir];
		if (isDir) {
			[a addObject:obj];
		}
	}
	return [a count];
}

// delegate methods
- (int)browser:(NSBrowser *)b numberOfRowsInColumn:(int)c {
	return [self loadDir:(c == 0 ? @"/" : [b pathToColumn:c]) inCol:c];
}

- (void)browser:(NSBrowser *)b willDisplayCell:(id)cell atRow:(int)row column:(int)column {
	[cell setStringValue:[[cols objectAtIndex:column] objectAtIndex:row]];
}

- (void)browser:(NSBrowser *)b typedString:(NSString *)s inColumn:(int)column {
	NSMutableArray *a = [cols objectAtIndex:column];
	unsigned int i, n = [a count];
	for (i=0; i<n; ++i) {
		if ([[a objectAtIndex:i] caseInsensitiveCompare:s] >= 0)
			break;
	}
	if (i==n) --i;
	[b selectRow:i inColumn:column];
	[b sendAction];
}

@end
