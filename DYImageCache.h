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
//  Copyright 2005 __MyCompanyName__. All rights reserved.
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
	unsigned int maxImages;
	BOOL cachingShouldStop;
	
	NSFileManager *fm;
	NSImageInterpolation interpolationType;
}

- (id)initWithCapacity:(unsigned int)n;

- (void)setBoundingSize:(NSSize)aSize;
- (void)setInterpolationType:(NSImageInterpolation)t;

- (void)cacheFile:(NSString *)s;
- (void)cacheFileInNewThread:(NSString *)s;

// for doing your own caching (e.g., Epeg)
- (void)addImage:(NSImage *)img forFile:(NSString *)s size:(NSSize)aSize;
- (NSImage *)imageForKey:(NSString *)s;
- (void)removeImageForKey:(NSString *)s;

- (DYImageInfo *)infoForKey:(NSString *)s;

- (void)abortCaching;
- (void)beginCaching;

@end
