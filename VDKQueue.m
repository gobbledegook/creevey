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

#pragma mark VDKQueuePathEntry
#pragma mark -

//  This is a simple model class used to hold info about each path we watch.
@interface VDKQueuePathEntry : NSObject

- (instancetype) initWithPath:(NSString*)inPath andSubscriptionFlags:(u_int)flags;

@property (atomic, copy) NSString *path;
@property (atomic, assign) int watchedFD;
@property (atomic, assign) u_int subscriptionFlags;
@property (atomic, assign) uintptr_t uniqueId;

@end

@implementation VDKQueuePathEntry

- (instancetype) initWithPath:(NSString*)inPath andSubscriptionFlags:(u_int)flags;
{
    self = [super init];
	if (self)
	{
		_path = [inPath copy];
		_watchedFD = open([_path fileSystemRepresentation], O_EVTONLY, 0);
		if (_watchedFD < 0)
		{
			[self autorelease];
			return nil;
		}
		_subscriptionFlags = flags;
	}
	return self;
}

-(void)	dealloc
{
	[_path release];
	_path = nil;
    
	if (_watchedFD >= 0) close(_watchedFD);
	_watchedFD = -1;
	
	[super dealloc];
}

@end











#pragma mark -
#pragma mark VDKQueue
#pragma mark -

@implementation VDKQueue
{
@private
	int						_coreQueueFD;                           // The actual kqueue ID (Unix file descriptor).
	NSMutableDictionary    *_watchedPathEntries;                    // List of VDKQueuePathEntries. Keys are NSStrings of the path that each VDKQueuePathEntry is for.
	NSMutableDictionary    *_pathMap;                               // unique id -> path entry (for thread safety)
	BOOL                    _keepWatcherThreadRunning;              // Set to NO to cancel the thread that watches _coreQueueFD for kQueue events
}

#pragma mark -
#pragma mark INIT/DEALLOC

- (instancetype) init
{
	self = [super init];
	if (self)
	{
		_coreQueueFD = kqueue();
		if (_coreQueueFD == -1)
		{
			[self autorelease];
			return nil;
		}
		
		_watchedPathEntries = [[NSMutableDictionary alloc] init];
		_pathMap = [[NSMutableDictionary alloc] init];
	}
	return self;
}


- (void) dealloc
{
	[_pathMap release];
    [_watchedPathEntries release];
    _watchedPathEntries = nil;
    
	if(close(_coreQueueFD) == -1) {
	   NSLog(@"VDKQueue: Couldn't close main kqueue (%d)", errno);
	}

    [super dealloc];
}





#pragma mark -
#pragma mark PRIVATE METHODS

- (VDKQueuePathEntry *)	addPathToQueue:(NSString *)path notifyingAbout:(u_int)flags
{
	static uintptr_t gUniqueID = 0;
	@synchronized(self)
	{
        // Are we already watching this path?
		VDKQueuePathEntry *pathEntry = [_watchedPathEntries objectForKey:path];
		
        if (pathEntry)
		{
            // All flags already set?
			if(([pathEntry subscriptionFlags] | flags) == flags)
            {
				return [[pathEntry retain] autorelease]; 
            }
			
			flags |= [pathEntry subscriptionFlags];
		}
		else
        {
            pathEntry = [[[VDKQueuePathEntry alloc] initWithPath:path andSubscriptionFlags:flags] autorelease];
        }
        
		if (pathEntry)
		{
			struct timespec		nullts = { 0, 0 };
			struct kevent		ev;
			EV_SET(&ev, [pathEntry watchedFD], EVFILT_VNODE, EV_ADD | EV_ENABLE | EV_CLEAR, flags, 0, (void *)gUniqueID);
			
			[pathEntry setSubscriptionFlags:flags];
			[pathEntry setUniqueId:gUniqueID];
			[_pathMap setObject:pathEntry forKey:@(gUniqueID++)];

            [_watchedPathEntries setObject:pathEntry forKey:path];
            kevent(_coreQueueFD, &ev, 1, NULL, 0, &nullts);
            
			// Start the thread that fetches and processes our events if it's not already running.
			if(!_keepWatcherThreadRunning)
			{
				_keepWatcherThreadRunning = YES;
				[NSThread detachNewThreadSelector:@selector(watcherThread:) toTarget:self withObject:nil];
			}
        }
        
        return [[pathEntry retain] autorelease];
    }
}


- (void) watcherThread:(id)sender
{
    int					n;
    struct kevent		ev;
    struct timespec     timeout = { 1, 0 };     // 1 second timeout. Should be longer, but we need this thread to exit when a kqueue is dealloced, so 1 second timeout is quite a while to wait.
	int					theFD = _coreQueueFD;	// So we don't have to risk accessing iVars when the thread is terminated.
	NSThread.currentThread.name = @"VDKQueue";
#if DEBUG_LOG_THREAD_LIFETIME
	NSLog(@"watcherThread started.");
#endif
	
    while(_keepWatcherThreadRunning)
    {
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        @try 
        {
            n = kevent(theFD, NULL, 0, &ev, 1, &timeout);
            if (n > 0)
            {
                //NSLog( @"KEVENT returned %d", n );
                if (ev.filter == EVFILT_VNODE)
                {
                    //NSLog( @"KEVENT filter is EVFILT_VNODE" );
                    if (ev.fflags)
                    {
                        //NSLog( @"KEVENT flags are set" );
                        
						uintptr_t uid = (uintptr_t)ev.udata;
						VDKQueuePathEntry *pe;
						@synchronized(self)
						{
							pe = [_pathMap objectForKey:@(uid)];
						}
                        if (pe)
                        {
                            NSString *fpath = [pe.path retain];         // Need to retain so it does not disappear while the block at the bottom is waiting to run on the main thread. Released in that block.
                            if (!fpath) continue;
                            
                            // call the delegate method on the main thread.
							u_int flags = ev.fflags;
                            dispatch_async(dispatch_get_main_queue(), ^{
								[_delegate VDKQueue:self receivedNotification:flags forPath:fpath];
								[fpath release];
							});
                        }
                    }
                }
            }
        }
        
        @catch (NSException *localException) 
        {
            NSLog(@"Error in VDKQueue watcherThread: %@", localException);
        }
		[pool release];
    }
    
#if DEBUG_LOG_THREAD_LIFETIME
	NSLog(@"watcherThread finished.");
#endif

}






#pragma mark -
#pragma mark PUBLIC METHODS


- (void) addPath:(NSString *)aPath
{
    if (!aPath) return;
    [aPath retain];
    
    @synchronized(self)
    {
        VDKQueuePathEntry *entry = [_watchedPathEntries objectForKey:aPath];
        
        // Only add this path if we don't already have it.
        if (!entry)
        {
            [self addPathToQueue:aPath notifyingAbout:VDKQueueNotifyDefault];
        }
    }
    
    [aPath release];
}


- (void) addPath:(NSString *)aPath notifyingAbout:(u_int)flags
{
    if (!aPath) return;
    [aPath retain];
    
    @synchronized(self)
    {
        VDKQueuePathEntry *entry = [_watchedPathEntries objectForKey:aPath];
        
        // Only add this path if we don't already have it.
        if (!entry)
        {
            [self addPathToQueue:aPath notifyingAbout:flags];
        }
    }
    
    [aPath release];
}


- (void) removePath:(NSString *)aPath
{
    if (!aPath) return;
    [aPath retain];
    
    @synchronized(self)
	{
		VDKQueuePathEntry *entry = [_watchedPathEntries objectForKey:aPath];
        
        // Remove it only if we're watching it.
        if (entry) {
			[_pathMap removeObjectForKey:@(entry.uniqueId)];
            [_watchedPathEntries removeObjectForKey:aPath];
        }
	}
    
    [aPath release];
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
		_keepWatcherThreadRunning = NO;

		// Do this to close all the open file descriptors for files we're watching
		[_pathMap removeAllObjects];
		[_watchedPathEntries removeAllObjects];
	}
}


- (NSUInteger) numberOfWatchedPaths
{
    NSUInteger count;
    
    @synchronized(self)
    {
        count = [_watchedPathEntries count];
    }
    
    return count;
}




@end

