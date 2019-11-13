//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.
//
//  DYImageCache.h
//  creevey
//
//  Created by d on 2005.04.15.
//

#import <Cocoa/Cocoa.h>

NSString *FileSize2String(unsigned long long fileSize);

@interface DYImageInfo : NSObject { // use like a struct
	@public
	NSString *path;
	NSImage /*orig,*/ *image;
	NSDate *modTime;
	unsigned long long fileSize;
	NSSize pixelSize;
	unsigned short exifOrientation;
}
- initWithPath:(NSString *)s;
- (NSString *)pixelSizeAsString;
@end


@interface DYImageCache : NSObject {
	NSLock *cacheLock;
	NSConditionLock *pendingLock;
	
	NSMutableArray *cacheOrder;
	NSMutableDictionary *images;
	NSMutableSet *pending;
	
	NSSize boundingSize;
	NSUInteger maxImages;
	volatile BOOL cachingShouldStop;
	
	NSFileManager *fm;
	NSImageInterpolation interpolationType;
}

- (id)initWithCapacity:(NSUInteger)n;

- (float)boundingWidth;
- (NSSize)boundingSize;
- (void)setBoundingSize:(NSSize)aSize;
- (void)setInterpolationType:(NSImageInterpolation)t;

- (void)cacheFile:(NSString *)s;
- (void)cacheFileInNewThread:(NSString *)s;

// cacheFile consists of the following three steps
// exposed here for doing your own caching (e.g., Epeg)
// you MUST call addImage or dontAdd if attemptLock returns YES
- (BOOL)attemptLockOnFile:(NSString *)s; // will sleep if s is pending, then return NO
- (void)createScaledImage:(DYImageInfo *)imgInfo; // if i->image is nil, you must replace with dummy image
- (void)addImage:(DYImageInfo *)img forFile:(NSString *)s;
- (void)dontAddFile:(NSString *)s; // simply remove from pending

- (NSImage *)imageForKey:(NSString *)s;
- (void)removeImageForKey:(NSString *)s;
- (void)removeAllImages;

- (DYImageInfo *)infoForKey:(NSString *)s;

- (void)abortCaching; // when set, ignore calls to cacheFile; pending files dropped when done
- (void)beginCaching;

@end
