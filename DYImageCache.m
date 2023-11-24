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
#import "DYExiftags.h"

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

@interface DYImageInfo () <NSDiscardableContent>
@property NSUInteger counter;
@end
@implementation DYImageInfo
@synthesize image, path, modTime;

- (void)dealloc {
	[image release];
	[modTime release];
	[super dealloc];
}

// designated initializer
- initWithPath:(NSString *)s {
	if (self = [super init]) {
		path = [s copy];
		_counter = 1; // NSCache may try to evict us immediately!
		
		// get modTime
		NSDictionary *fattrs = [[NSFileManager defaultManager] attributesOfItemAtPath:ResolveAliasToPath(s) error:NULL];
		modTime = [[fattrs fileModificationDate] retain];
		
		// get fileSize
		fileSize = [fattrs fileSize];
	}
	return self;
}
- (NSString *)pixelSizeAsString {
	return [NSString stringWithFormat:@"%dx%d", (int)pixelSize.width, (int)pixelSize.height];
}

#pragma mark NSDiscardableContent
- (BOOL)beginContentAccess {
	self.counter = self.counter + 1;
	return YES;
}
- (void)endContentAccess {
	self.counter = self.counter - 1;
}
- (void)discardContentIfPossible {
	if (self.counter == 0) {
		[image release];
		image = nil;
		// we expect to be immediately evicted
	}
}
- (BOOL)isContentDiscarded {
	return image == nil;
}
@end


@interface DYImageCache ()
{
	NSLock *cacheLock;
	NSConditionLock *pendingLock;
	
	NSCache<NSString *, DYImageInfo *> *images;
	NSMutableSet<NSString *> *pending;
	
	NSSize boundingSize;
	NSUInteger maxImages;
	volatile BOOL cachingShouldStop;
	
	NSFileManager *fm;
	NSImageInterpolation interpolationType;
}
@end

@implementation DYImageCache
// this is the designated initializer
- (id)initWithCapacity:(NSUInteger)n {
	if (self = [super init]) {
		images = [[NSCache alloc] init];
		images.countLimit = n;
		images.evictsObjectsWithDiscardedContent = YES;
		pending = [[NSMutableSet alloc] init];
		
		cacheLock = [[NSLock alloc] init];
		pendingLock = [[NSConditionLock alloc] initWithCondition:0];
		
		fm = [NSFileManager defaultManager];
	}
    return self;
}

- (void)beginAccess:(NSString *)key {
	[[images objectForKey:key] beginContentAccess];
}
- (void)endAccess:(NSString *)key {
	[[images objectForKey:key] endContentAccess];
}

- (void)setBoundingSize:(NSSize)aSize {
	boundingSize = aSize;
}
- (float)boundingWidth {	return boundingSize.width; }
- (NSSize)boundingSize { return boundingSize; }

- (void)setInterpolationType:(NSImageInterpolation)t {
	interpolationType = t;
}

- (void)dealloc {
	[images release];
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

	orig = [[NSImage alloc] initByReferencingFileIgnoringJPEGOrientation:ResolveAliasToPath(imgInfo.path)];

	// now scale the img
	if (orig && [[orig representations] count]) { // why doesn't it return nil for corrupt jpegs?
		NSImageRep *oldRep = [orig representations][0];
		NSSize oldSize, newSize;
		oldSize = NSMakeSize([oldRep pixelsWide], [oldRep pixelsHigh]);
		
		if (oldSize.width == 0 || oldSize.height == 0) // PDF's don't have pixels
			oldSize = [orig size];
		
		if (oldSize.width != 0 && oldSize.height != 0) { // but if it's still 0, skip it, BAD IMAGE
			imgInfo->pixelSize = oldSize;
			if (_rotatable && (maxSize.height > maxSize.width) != (oldSize.height > oldSize.width)) {
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
					newSize.height = (int)(oldSize.height*w_ratio);
					newSize.width = (int)(maxSize.width);
				} else {
					newSize.width = (int)(oldSize.width*h_ratio);
					newSize.height = (int)(maxSize.height);
				}
				if (newSize.width == 0) newSize.width = 1; // super-skinny images will make this crash unless you specify a minimum dimension of 1
				if (newSize.height == 0) newSize.height = 1;
				[orig setSize:newSize];
				result = [[NSImage alloc] initWithSize:newSize];
				[result lockFocus];
				[orig drawAtPoint:NSZeroPoint fromRect:NSMakeRect(0, 0, newSize.width, newSize.height) operation:NSCompositingOperationSourceOver fraction:1.0];
				[result unlockFocus];
			}
		}
	}
	[orig release];
	imgInfo.image = result;
	[result release];
}

// see usage note in the .h file.
#define CacheContains(x)	([images objectForKey:x] != nil)
#define PendingContains(x)  ([pending containsObject:x])
- (void)cacheFile:(NSString *)s {
	if (![self attemptLockOnFile:s]) return;
	
	// make image objects
	//NSLog(@"caching %@", idx);
	DYImageInfo *result = [[DYImageInfo alloc] initWithPath:s];
	[self createScaledImage:result];
	if (result.image == nil)
		result.image = [NSImage imageNamed:@"brokendoc.tif"];
	else
		result->exifOrientation = [DYExiftags orientationForFile:ResolveAliasToPath(s)];

	// now add it to cache
	[self addImage:result forFile:s];
	[result release];
	//NSLog(@"caching %@ done!", idx);
}

- (BOOL)attemptLockOnFile:(NSString *)s { // add s to the "pending" array
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
		[images setObject:imgInfo forKey:s];
	}
	[cacheLock unlock];
	[pendingLock lock];
	[pendingLock unlockWithCondition:[s hash]]; // unlocking w/o locking, i guess it's OK
}

- (void)dontAddFile:(NSString *)s {
	[cacheLock lock];
	[pending removeObject:s];
	[cacheLock unlock];
	[pendingLock lock];
	[pendingLock unlockWithCondition:[s hash]];
}

- (DYImageInfo *)infoForKey:(NSString *)s {
	// ** unlike imageforkey, this is nonmagical
	return [images objectForKey:s];
}

- (NSImage *)imageForKey:(NSString *)s {
	return [images objectForKey:s].image;
}

- (NSImage *)imageForKeyInvalidatingCacheIfNecessary:(NSString *)s {
	DYImageInfo *imgInfo = [images objectForKey:s];
	if (imgInfo) {
		// must resolve alias before getting mod time
		// b/c that's what we do in scaleImage
		NSDate *modTime = [[fm attributesOfItemAtPath:ResolveAliasToPath(s) error:NULL] fileModificationDate];

		// == nil if file doesn't exist
		if ((modTime == nil && imgInfo.modTime == nil)
			|| (modTime && imgInfo.modTime && [modTime isEqualToDate:imgInfo.modTime]))
			return imgInfo.image;
		[self removeImageForKey:s];
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
		[images removeObjectForKey:s];
	}
	[cacheLock unlock];
}

- (void)removeAllImages {
	[cacheLock lock];
	[images removeAllObjects];
	[pending removeAllObjects];
	[cacheLock unlock];
}

- (void)abortCaching {
	cachingShouldStop = YES;
}
- (void)beginCaching {
	cachingShouldStop = NO;
}
@end
