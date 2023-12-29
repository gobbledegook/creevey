//	VDKQueue.m
//	Created by Bryan D K Jones on 28 March 2012
//	Copyright 2013 Bryan D K Jones
//  Modified 2023 Dominic Yu
//
//  Based heavily on UKKQueue, which was created and copyrighted by Uli Kusterer on 21 Dec 2003.
//
//	This software is provided 'as-is', without any express or implied
//	warranty. In no event will the authors be held liable for any damages
//	arising from the use of this software.
//	Permission is granted to anyone to use this software for any purpose,
//	including commercial applications, and to alter it and redistribute it
//	freely, subject to the following restrictions:
//	   1. The origin of this software must not be misrepresented; you must not
//	   claim that you wrote the original software. If you use this software
//	   in a product, an acknowledgment in the product documentation would be
//	   appreciated but is not required.
//	   2. Altered source versions must be plainly marked as such, and must not be
//	   misrepresented as being the original software.
//	   3. This notice may not be removed or altered from any source
//	   distribution.

#import "VDKQueue.h"
#import <unistd.h>
#import <fcntl.h>
#include <sys/stat.h>

#pragma mark VDKQueuePathEntry -

//  This is a simple model class used to hold info about each path we watch.
@interface VDKQueuePathEntry : NSObject
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPath:(NSString*)inPath andSubscriptionFlags:(u_int)flags NS_DESIGNATED_INITIALIZER;
@property (readonly) NSString *path;
@property (readonly) int watchedFD;
@property u_int subscriptionFlags;
@property (readonly) uintptr_t uniqueId;
@end

@implementation VDKQueuePathEntry
- (instancetype)initWithPath:(NSString*)inPath andSubscriptionFlags:(u_int)flags {
	static uintptr_t gUniqueID = 0;
	if (self = [super init]) {
		_path = [inPath copy];
		_watchedFD = open(_path.fileSystemRepresentation, O_EVTONLY, 0);
		if (_watchedFD < 0) {
			self = nil;
			return nil;
		}
		_subscriptionFlags = flags;
		_uniqueId = gUniqueID++;
	}
	return self;
}
- (void)dealloc {
	close(_watchedFD);
}
@end


#pragma mark - VDKQueue -

@implementation VDKQueue {
@private
	int						_coreQueueFD;                           // The actual kqueue ID (Unix file descriptor).
	NSMutableDictionary<NSString *, VDKQueuePathEntry *> *_watchedPathEntries; // path -> path entry
	NSMutableDictionary<NSNumber *, VDKQueuePathEntry *> *_pathMap; // unique id -> path entry (for thread safety)
	BOOL                    _isWatcherThreadRunning;
}

#pragma mark - INIT/DEALLOC

- (instancetype) init
{
	if (self = [super init])
	{
		_coreQueueFD = kqueue();
		if (_coreQueueFD == -1)
		{
			self = nil;
			return nil;
		}
		
		_watchedPathEntries = [[NSMutableDictionary alloc] init];
		_pathMap = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void) dealloc
{
	if(close(_coreQueueFD) == -1) {
	   NSLog(@"VDKQueue: Couldn't close main kqueue (%d)", errno);
	}
}


- (void) addPath:(NSString *)path notifyingAbout:(u_int)flags
{
	if (!path) return;
	@synchronized(self)
	{
        // Are we already watching this path?
		VDKQueuePathEntry *pathEntry = _watchedPathEntries[path];
        if (pathEntry) {
            // All flags already set?
			if ((pathEntry.subscriptionFlags | flags) == flags) return;
			flags |= pathEntry.subscriptionFlags;
			pathEntry.subscriptionFlags = flags;
		} else {
            pathEntry = [[VDKQueuePathEntry alloc] initWithPath:path andSubscriptionFlags:flags];
			_watchedPathEntries[path] = pathEntry;
			_pathMap[@(pathEntry.uniqueId)] = pathEntry;
        }

		struct kevent ev;
		EV_SET(&ev, pathEntry.watchedFD, EVFILT_VNODE, EV_ADD|EV_CLEAR, flags, 0, (void *)pathEntry.uniqueId);
		kevent(_coreQueueFD, &ev, 1, NULL, 0, &(struct timespec){0,0});

		// Start the thread that fetches and processes our events if it's not already running.
		if (!_isWatcherThreadRunning) {
			_isWatcherThreadRunning = YES;
			[NSThread detachNewThreadSelector:@selector(watcherThread:) toTarget:self withObject:nil];
		}
    }
}


- (void) watcherThread:(id)sender
{
    int					n;
    struct kevent		ev;
	const int			theFD = _coreQueueFD;	// So we don't have to risk accessing iVars when the thread is terminated.
	NSThread.currentThread.name = @"VDKQueue";
#if DEBUG_LOG_THREAD_LIFETIME
	NSLog(@"watcherThread started.");
#endif
	
	for (;;) {
		@autoreleasepool {
			n = kevent(theFD, NULL, 0, &ev, 1, NULL);
			if (n > 0 && ev.filter == EVFILT_VNODE && ev.fflags) {
				uintptr_t uid = (uintptr_t)ev.udata;
				VDKQueuePathEntry *pe;
				@synchronized(self) {
					pe = _pathMap[@(uid)];
				}
				if (pe) {
					// call the delegate method on the main thread.
					dispatch_async(dispatch_get_main_queue(), ^{
						[_delegate VDKQueue:self receivedNotification:ev.fflags forPath:pe.path];
					});
				}
			} else if (ev.filter == EVFILT_USER) {
				@synchronized (self) {
					_isWatcherThreadRunning = NO;
				}
				break;
			}
		}
	}
    
#if DEBUG_LOG_THREAD_LIFETIME
	NSLog(@"watcherThread finished.");
#endif

}


#pragma mark - PUBLIC METHODS

- (void) removePath:(NSString *)aPath
{
    if (!aPath) return;
    @synchronized(self)
	{
		VDKQueuePathEntry *entry = _watchedPathEntries[aPath];
        
        // Remove it only if we're watching it.
        if (entry) {
			[_pathMap removeObjectForKey:@(entry.uniqueId)];
            [_watchedPathEntries removeObjectForKey:aPath];
        }
	}
}


- (void) removeAllPaths
{
    @synchronized(self)
    {
		[_pathMap removeAllObjects];
        [_watchedPathEntries removeAllObjects];
    }
}


- (void) stopWatching
{
	// This method must be called if we want this object to ever be dealloc'd. This is because detachNewThreadSelector:toTarget:withObject:
	// retains the target (in this case, self), setting the retainCount to 2. Aside from the memory leak issue, if the thread is never terminated,
	// the watcher thread might still try to send messages to a nonexistent delegate, causing your app to crash.
	@synchronized(self)
	{
		// Shut down the thread that's scanning for kQueue events
		kevent(_coreQueueFD, &(struct kevent){0, EVFILT_USER, EV_ADD|EV_ONESHOT, NOTE_TRIGGER, 0, NULL}, 1, NULL, 0, &(struct timespec){0,0});

		// Do this to close all the open file descriptors for files we're watching
		[_pathMap removeAllObjects];
		[_watchedPathEntries removeAllObjects];
	}
}

@end
