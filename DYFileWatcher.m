//
//  DYFileWatcher.m
//  Phoenix Slides
//
//  Created by 祥 on 12/6/23.
//

#import "DYFileWatcher.h"
#import "DYCarbonGoodies.h"
#import "CreeveyController.h"

@interface DYFileWatcher ()
@property (nonatomic, copy) NSString *path;
- (instancetype)init NS_UNAVAILABLE;
- (void)gotEventPaths:(NSArray *)eventPaths flags:(const FSEventStreamEventFlags *)eventFlags count:(size_t)n;
@end

static void fseventCallback(ConstFSEventStreamRef streamRef, void *info, size_t n, void *p, const FSEventStreamEventFlags flags[], const FSEventStreamEventId eventIds[])
{
	[(__bridge DYFileWatcher *)info gotEventPaths:(__bridge NSArray *)(p) flags:flags count:n];
	// NB: the CFArrayRef of event paths gets released after this returns
}

@implementation DYFileWatcher
{
	FSEventStreamRef stream;
	id <DYFileWatcherDelegate> __weak _delegate;
	CreeveyController * __weak appDelegate;
}

- (instancetype)initWithDelegate:(id <DYFileWatcherDelegate>)d {
	if (self = [super init]) {
		_delegate = d;
	}
	return self;
}

- (void)dealloc {
	[self stop];
}

- (void)watchDirectory:(NSString *)s {
	if (stream)
		[self stop];
	if ([s.stringByDeletingLastPathComponent isEqualToString:@"/"])
		return; // just refuse to watch top level directories for now
	stream = FSEventStreamCreate(NULL, &fseventCallback, &(FSEventStreamContext){0,(__bridge void *)self,NULL,NULL,NULL}, (__bridge CFArrayRef)@[s], kFSEventStreamEventIdSinceNow, 2.0, kFSEventStreamCreateFlagFileEvents|kFSEventStreamCreateFlagUseCFTypes|kFSEventStreamCreateFlagIgnoreSelf|kFSEventStreamCreateFlagMarkSelf);
	FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	if (!FSEventStreamStart(stream)) {
		FSEventStreamInvalidate(stream);
		stream = NULL;
	}
	self.path = s;
	appDelegate = (CreeveyController *)NSApp.delegate;
}

- (void)gotEventPaths:(NSArray *)eventPaths flags:(const FSEventStreamEventFlags *)eventFlags count:(size_t)n	 {
	NSMutableSet *files = [[NSMutableSet alloc] init];
	for (size_t i=0; i<n; ++i) {
		NSString *s = eventPaths[i];
		FSEventStreamEventFlags f = eventFlags[i];
		if (f & (kFSEventStreamEventFlagItemCreated|kFSEventStreamEventFlagItemModified|kFSEventStreamEventFlagItemRemoved|kFSEventStreamEventFlagItemRenamed)) {
			if (f & kFSEventStreamEventFlagItemIsDir) continue;
			if (_wantsSubfolders ? [s hasPrefix:_path] : [s.stringByDeletingLastPathComponent isEqualToString:_path]) {
				NSString *theFile = ResolveAliasToPath(s);
				NSURL *url = [NSURL fileURLWithPath:theFile isDirectory:NO];
				NSNumber *val;
				if ([url getResourceValue:&val forKey:NSURLIsHiddenKey error:NULL] && val.boolValue) continue;
				if (![appDelegate shouldShowFile:theFile]) continue;
				[files addObject:s];
			}
		}
	}
	if (files.count)
		[_delegate watcherFiles:files.allObjects];
}

- (void)stop {
	if (stream) {
		FSEventStreamStop(stream);
		FSEventStreamInvalidate(stream);
		FSEventStreamRelease(stream);
		stream = NULL;
	}
}


@end
