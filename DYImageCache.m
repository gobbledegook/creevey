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

#define N_StringFromFileSize_UNITS 3
NSString *FileSize2String(unsigned long long fileSize) {
	char *units[N_StringFromFileSize_UNITS] = {"KB", "MB", "GB"};
	short i;
	if (fileSize < 1024)
		return [NSString stringWithFormat:@"%qu bytes", fileSize];
	
	double n = fileSize;
	for (i=0; i<N_StringFromFileSize_UNITS; ++i) {
		n /= 1024.0;
		if (n < 1024) break;
	}
	return [NSString stringWithFormat:@"%.1f %s", n, units[i]];
}

@implementation DYImageInfo
- (void)dealloc {
	//[orig release];
	[image release];
	[modTime release];
	[super dealloc];
}

// designated initializer
- initWithPath:(NSString *)s {
	if (self = [super init]) {
		path = [s copy];
		
		// get modTime
		NSDictionary *fattrs = [[NSFileManager
			defaultManager] fileAttributesAtPath:ResolveAliasToPath(s)
									traverseLink:NO];
		modTime = [[fattrs fileModificationDate] retain];
		
		// get fileSize
		fileSize = [fattrs fileSize];
	}
	return self;
}
- (NSString *)pixelSizeAsString {
	return [NSString stringWithFormat:@"%dx%d", (int)pixelSize.width, (int)pixelSize.height];
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

- (void)setInterpolationType:(NSImageInterpolation)t {
	interpolationType = t;
}

- (void)dealloc {
	[images release];
	[cacheOrder release];
	[pending release];
	[cacheLock release];
	[pendingLock release];
	[super dealloc];
}

- (void)createScaledImage:(DYImageInfo *)imgInfo {
	if (imgInfo->fileSize == 0)
		return;  // nsimage crashes on zero-length files
	
	NSSize maxSize = boundingSize;
	NSImage *orig, *result = nil;
	// calc pixelSize
	orig = [[NSImage alloc] initByReferencingFile:ResolveAliasToPath(imgInfo->path)];
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
		* A better way: setScalesWhenResized
		*/
	[orig setScalesWhenResized:YES];
	// now scale the img
	if (orig && [[orig representations] count]) { // why doesn't it return nil for corrupt jpegs?
		NSImageRep *oldRep = [[orig representations] objectAtIndex:0];
		NSSize oldSize, newSize;
		oldSize = NSMakeSize([oldRep pixelsWide], [oldRep pixelsHigh]);
		
		if (oldSize.width == 0 || oldSize.height == 0) // PDF's don't have pixels
			oldSize = [orig size];
		
		if (oldSize.width != 0 && oldSize.height != 0) { // but if it's still 0, skip it, BAD IMAGE
			imgInfo->pixelSize = oldSize;
			if ((maxSize.height > maxSize.width) != (oldSize.height > oldSize.width)) {
				// ** do this only for the slideshow
				maxSize.height = boundingSize.width;
				maxSize.width = boundingSize.height;
			}
			
			if ((oldSize.width <= maxSize.width && oldSize.height <= maxSize.height)
				|| ([oldRep isKindOfClass:[NSBitmapImageRep class]]
					&& [((NSBitmapImageRep*)oldRep) valueForProperty:NSImageFrameCount])) {
				// special case for animated gifs
				result = [orig retain];
				if (!NSEqualSizes(oldSize,[orig size]))
					[orig setSize:oldSize];
				// in which case, don't set nevercache for returned images?
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
				[orig setSize:newSize];			  
				result = [[NSImage alloc] initWithSize:newSize];
				[result lockFocus];
				[orig compositeToPoint:NSZeroPoint operation:NSCompositeSourceOver];
				[result unlockFocus];
			}
			//oldSize = [oldRep size];
//			oldSize =  newSize;
//			[result lockFocus];
//			NSGraphicsContext *cg;
//			NSImageInterpolation oldInterp;
//			if (interpolationType) { // NSImageInterpolationDefault is 0
//				cg = [NSGraphicsContext currentContext];
//				oldInterp = [cg imageInterpolation];
//				[cg setImageInterpolation:interpolationType];
//			}
//			[orig drawInRect:NSMakeRect(0,0,newSize.width,newSize.height)
//					fromRect:NSMakeRect(0,0,oldSize.width,oldSize.height)
//				   operation:NSCompositeSourceOver fraction:1.0];
//			if (interpolationType)
//				[cg setImageInterpolation:oldInterp];
//			[result unlockFocus];
		}
	}
	[orig release];
	imgInfo->image = result;
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
	if (![self attemptLockOnFile:s]) return;
	
	// make image objects
	//NSLog(@"caching %@", idx);
	DYImageInfo *result = [[DYImageInfo alloc] initWithPath:s];
	[self createScaledImage:result];
	if (result->image == nil)
		result->image = [[NSImage imageNamed:@"brokendoc"] retain]; // ** don't hardcode!
	
	// now add it to cache
	[self addImage:result forFile:s];
	[result release];
	//NSLog(@"caching %@ done!", idx);
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

- (BOOL)attemptLockOnFile:(NSString *)s {
	[cacheLock lock];
	if (CacheContains(s) || cachingShouldStop) {
		// abort if already cached OR slideshow ended
		[cacheLock unlock];
		return NO;
	}
	if (PendingContains(s)) {
		[cacheLock unlock];
		//NSLog(@"waiting for pending %@", idx);
		[pendingLock lockWhenCondition:[s hash]];
		// this lock doesn't do anything, but is useful for communication purposes
		//NSLog(@"%@ not pending.", idx);
		[pendingLock unlockWithCondition:[s hash]];
		return NO;
	}
	[pending addObject:s]; // so no one else caches it simultaneously
	[cacheLock unlock];
	return YES;
}

- (void)addImage:(DYImageInfo *)imgInfo forFile:(NSString *)s {
	[cacheLock lock];
	[pending removeObject:s];
	if (!cachingShouldStop) {
		[cacheOrder addObject:s];
		[images setObject:imgInfo forKey:s];
		
		// remove stale images, if any
		if ([cacheOrder count] > maxImages) {
			[images removeObjectForKey:[cacheOrder objectAtIndex:0]];
			[cacheOrder removeObjectAtIndex:0];
		}
	}
	[cacheLock unlock];
	[pendingLock unlockWithCondition:[s hash]]; // unlocking w/o locking, i guess it's OK
}

- (void)dontAddFile:(NSString *)s {
	[cacheLock lock];
	[pending removeObject:s];
	[cacheLock unlock];
	[pendingLock unlockWithCondition:[s hash]];
}

- (DYImageInfo *)infoForKey:(NSString *)s {
	// ** unlike imageforkey, this is nonmagical
	return [images objectForKey:s];
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
