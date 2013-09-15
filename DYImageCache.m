//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//
//  DYImageCache.m
//  creevey
//
//  Created by d on 2005.04.15.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import "DYImageCache.h"
#import "DYCarbonGoodies.h"
@implementation DYImageInfo
- (void)dealloc {
	//[orig release];
	[image release];
	[modTime release];
	[super dealloc];
}
@end


/* cache of NSImage objects in a hash where the filename is the key.
* we also use an array to know which indexes were cached in which order
* so we know when to get rid of them.
*/


@implementation DYImageCache
// this is the designated initializer
- (id)initWithCapacity:(unsigned int)n {
	if (self = [super init]) {
		cacheOrder = [[NSMutableArray alloc] init];
		images = [[NSMutableDictionary alloc] init];
		pending = [[NSMutableSet alloc] init];
		
		cacheLock = [[NSLock alloc] init];
		pendingLock = [[NSConditionLock alloc] initWithCondition:0];
		
		maxImages = n;
		
		fm = [NSFileManager defaultManager];
	}
    return self;
}

- (void)setBoundingSize:(NSSize)aSize {
	boundingSize = aSize;
}

- (void)dealloc {
	[images release];
	[cacheOrder release];
	[pending release];
	[cacheLock release];
	[pendingLock release];
	[super dealloc];
}

- (DYImageInfo *)createScaledImage:(NSString *)s {
	s = ResolveAliasToPath(s);
	NSDictionary *fattrs = [fm fileAttributesAtPath:s traverseLink:NO];
	DYImageInfo *imgInfo = [[[DYImageInfo alloc] init] autorelease];
	imgInfo->modTime = [[fattrs fileModificationDate] retain];
	if ([fattrs fileSize] == 0)
		return imgInfo;  // nsimage crashes on zero-length files
	
	NSSize maxSize = boundingSize;
	NSImage *orig, *result = nil;
	orig = [[NSImage alloc] initByReferencingFile:s];
	//NSLog(@"%@", orig);
	/* You MUST either setDataRetained:YES OR setCacheMode:NSImageCacheNever.
		* Once the image is composited, NSImage will throw away the original
		* data and save only a cached (read: reduced) version. It seems that
		* if [orig size] is smaller than the raw pixel size, NSImage immediately
		* throws away the original data and caches a smaller scaled-down
		* raw size == stated size version. If the data is not retained, when we
		* try to draw a larger image which requires the missing data, the NSImage
		* simply blows up the cached image into a larger pixely image.
		* We can fix this by telling it not to cache at all, or by retaining the
		* original data.
		*/
	//[orig setDataRetained:YES];
	[orig setCacheMode:NSImageCacheNever];
	// now scale the img
	if (orig && [[orig representations] count]) { //** why doesn't it return nil for corrupt jpegs?
		NSSize oldSize, newSize;
		NSImageRep *oldRep = [[orig representations] objectAtIndex:0];
		oldSize = NSMakeSize([oldRep pixelsWide],[oldRep pixelsHigh]); // need pixels here, [orig size] might be wrong!
		
		if (oldSize.width == 0 || oldSize.height == 0)
			oldSize = [orig size];
		if (oldSize.width != 0 && oldSize.height != 0) { // if it's still 0, skip it, BAD IMAGE

			if ((maxSize.height > maxSize.width) != (oldSize.height > oldSize.width)) {
				// ** do this only for the slideshow
				maxSize.height = boundingSize.width;
				maxSize.width = boundingSize.height;
			}
			
			if (oldSize.width <= maxSize.width && oldSize.height <= maxSize.height) {
				newSize = oldSize;
				// we still cache anyway in case there's a pixel vs reported size diff
				// ** we might be able to optimize away by checking for equality
				// in which case, don't set nevercache for returned images
			} else {
				float w_ratio, h_ratio;
				w_ratio = maxSize.width/oldSize.width;
				h_ratio = maxSize.height/oldSize.height;
				if (w_ratio < h_ratio) { // the side w/ bigger ratio needs to be shrunk
					newSize.height = oldSize.height*w_ratio;
					newSize.width = maxSize.width;
				} else {
					newSize.width = oldSize.width*h_ratio;
					newSize.height = maxSize.height;
				}
			}
			result = [[NSImage alloc] initWithSize:newSize];// autorelease];
			// right now we copy the old image into a new, smaller image
			// is there a better way? just add cached rep to the orig image?
			oldSize = [oldRep size];
			[result lockFocus];
			//NSGraphicsContext *cg = [NSGraphicsContext currentContext];
			//NSImageInterpolation oldInterp = [cg imageInterpolation];
			//[cg setImageInterpolation:NSImageInterpolationLow];
			[orig drawInRect:NSMakeRect(0,0,newSize.width,newSize.height)
					fromRect:NSMakeRect(0,0,oldSize.width,oldSize.height)
				   operation:NSCompositeSourceOver fraction:1.0];
			//[cg setImageInterpolation:oldInterp];
			[result unlockFocus];
			[orig release];
		}
	}
	imgInfo->image = result;
	return imgInfo;
}

/*//a failed experiment
if (oldSize.width > screenRect.size.width || oldSize.height > screenRect.size.height) {
	NSCachedImageRep *scaledRep =
	[[NSCachedImageRep alloc] initWithSize:screenRect.size depth:[self depthLimit]
								  separate:NO alpha:NO];
	[orig addRepresentation:scaledRep]; [scaledRep release];
	NSSize newSize; NSPoint newOrigin = NSZeroPoint;
	
	float w_ratio, h_ratio;
	w_ratio = screenRect.size.width/oldSize.width;
	h_ratio = screenRect.size.height/oldSize.height;
	if (w_ratio < h_ratio) { // the side w/ bigger ratio needs to be shrunk
		newSize.height = oldSize.height*w_ratio;
		newSize.width = screenRect.size.width;
		newOrigin.y = (screenRect.size.height - newSize.height)/2;
	} else {
		newSize.width = oldSize.width*h_ratio;
		newSize.height = screenRect.size.height;
		newOrigin.x = (screenRect.size.width - newSize.width)/2;
	}
	[orig lockFocusOnRepresentation:scaledRep];
	[oldRep drawInRect:NSMakeRect(newOrigin.x,newOrigin.y,newSize.width,newSize.height)];
	[orig unlockFocus];
	[orig removeRepresentation:oldRep];
}
*/

#define CacheContains(x)	([images objectForKey:x] != nil)
#define PendingContains(x)  ([pending containsObject:x])
- (void)cacheFile:(NSString *)s {
	DYImageInfo *result;
	[cacheLock lock];
	if (CacheContains(s) || cachingShouldStop) {
		// abort if already cached OR slideshow ended
		[cacheLock unlock];
		return;
	}
	if (PendingContains(s)) {
		[cacheLock unlock];
		//NSLog(@"waiting for pending %@", idx);
		[pendingLock lockWhenCondition:[s hash]];
		// this lock doesn't do anything, but is useful for communication purposes
		//NSLog(@"%@ not pending.", idx);
		[pendingLock unlockWithCondition:[s hash]];
		return;
	}
	[pending addObject:s]; // so no one else caches it simultaneously
	[cacheLock unlock];
	
	// make image objects
	//NSLog(@"caching %@", idx);
	result = [self createScaledImage:s];
	if (result->image == nil) result->image = [[NSImage imageNamed:@"brokendoc"] retain]; // ** don't hardcode!
	
	// now add it to cache
	[cacheLock lock];
	if (!cachingShouldStop) { // skip if show ended
		[pending removeObject:s];		[cacheOrder addObject:s];
		[images setObject:result forKey:s];
		
		// remove stale images, if any
		if ([cacheOrder count] > maxImages) {
			[images removeObjectForKey:[cacheOrder objectAtIndex:0]];
			[cacheOrder removeObjectAtIndex:0];
		}
		//NSLog(@"caching %@ done!", idx);
	}
	// clean up
	[cacheLock unlock];
	//[pendingLock lock];
	[pendingLock unlockWithCondition:[s hash]]; // unlocking w/o locking, i guess it's OK
}

- (void)cacheFileThreaded:(NSString *)s {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[self cacheFile:s];
	[pool release];
}

- (void)cacheFileInNewThread:(NSString *)s {
	[NSThread detachNewThreadSelector:@selector(cacheFileThreaded:) toTarget:self
						   withObject:s];
}

- (void)addImage:(NSImage *)img forFile:(NSString *)s {
	// repeated code from cacheFile?
	[cacheLock lock];
	[cacheOrder addObject:s];
	DYImageInfo *imgInfo = [[[DYImageInfo alloc] init] autorelease];
	imgInfo->modTime = [[[fm fileAttributesAtPath:s traverseLink:NO] fileModificationDate] retain];
	imgInfo->image = [img retain];
	[images setObject:imgInfo forKey:s];
	
	// remove stale images, if any
	if ([cacheOrder count] > maxImages) {
		[images removeObjectForKey:[cacheOrder objectAtIndex:0]];
		[cacheOrder removeObjectAtIndex:0];
	}
	[cacheLock unlock];
}

- (NSImage *)imageForKey:(NSString *)s {
	DYImageInfo *imgInfo = [images objectForKey:s];
	if (imgInfo) {
		// must resolve alias before getting mod time
		// b/c that's what we do in scaleImage
		NSDate *modTime = [[fm fileAttributesAtPath:ResolveAliasToPath(s)
									   traverseLink:NO] fileModificationDate];
		// == nil if file doesn't exist
		if ((modTime == nil && imgInfo->modTime == nil)
			|| (modTime && imgInfo->modTime && [modTime isEqualToDate:imgInfo->modTime]))
			return imgInfo->image;
		[self removeImageForKey:s];
		return nil;
	}
	return nil;
}

- (void)removeImageForKey:(NSString *)s {
	[cacheLock lock];
	// be thread safe
	if (CacheContains(s)) {
		if (PendingContains(s)) {
			// wait until pending is done
			[cacheLock unlock];
			[pendingLock lockWhenCondition:[s hash]];
			[pendingLock unlockWithCondition:[s hash]];
			[cacheLock lock];
		}
		[cacheOrder removeObject:s];
		[images removeObjectForKey:s];
	}
	[cacheLock unlock];
}


- (void)abortCaching {
	cachingShouldStop = YES;
//	[cacheLock lock];
//	currentIndex = -1; // in case any threads (cacheAndDisplay) still running, they'll know to stop
//	
//	[images removeAllObjects];
//	[cachedIndexes removeAllObjects];
//	[pending removeAllObjects];
//	[cacheLock unlock];
}
- (void)beginCaching {
	cachingShouldStop = NO;
}
@end
