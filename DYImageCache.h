//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  Created by d on 2005.04.15.

@import Cocoa;
#include "dcraw.h"

NSString *FileSize2String(unsigned long long fileSize);

@interface DYImageInfo : NSObject {
	@public // access these instance variables like a struct
	time_t modTime;
	off_t fileSize;
	NSSize pixelSize;
	unsigned short exifOrientation;
}
@property (strong, nonatomic) NSImage *image;
@property (readonly, nonatomic) NSString *path;
- (instancetype)initWithPath:(NSString *)s NS_DESIGNATED_INITIALIZER;
- (NSImage *)loadFullSizeImage;
@property (nonatomic, readonly, copy) NSString *pixelSizeAsString;
@end


@interface DYImageCache : NSObject
@property (nonatomic) BOOL rotatable; // default is NO
@property (nonatomic) BOOL fastThumbnails; // faster but lower quality rendering. default is NO
- (instancetype)initWithCapacity:(NSUInteger)n NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) float boundingWidth;
@property (nonatomic) NSSize boundingSize;

+ (NSData *)createNewThumbFromFile:(NSString *)path getSize:(NSSize *)outSize;

- (void)cacheFile:(NSString *)s;
- (void)cacheFile:(NSString *)s fullSize:(BOOL)fullSize;

// cacheFile consists of the following three steps
// exposed here for doing your own caching (e.g., Epeg)
// you MUST call addImage or dontAdd if attemptLock returns YES
- (BOOL)attemptLockOnFile:(NSString *)s; // will sleep if s is pending, then return NO
- (void)createScaledImage:(DYImageInfo *)imgInfo; // if i->image is nil, you must replace with dummy image
- (void)createScaledImage:(DYImageInfo *)imgInfo fromData:(NSData *)data ofType:(enum dcraw_type)dataType;
- (void)addImage:(DYImageInfo *)img forFile:(NSString *)s;
- (void)dontAddFile:(NSString *)s; // simply remove from pending

- (NSImage *)imageForKey:(NSString *)s;
- (NSImage *)imageForKeyInvalidatingCacheIfNecessary:(NSString *)s;
- (void)removeImageForKey:(NSString *)s;
- (void)removeAllImages;

- (DYImageInfo *)infoForKey:(NSString *)s;

// NSDiscardableContent accessors
- (void)beginAccess:(NSString *)key; // you should call beginAcess if you retain the image (e.g., after calling imageForKey:)
- (void)endAccess:(NSString *)key; // you should eventually call endAccess if you call (1) cacheFile: (2) addImage:forFile: or (3) beginAcess:

- (void)abortCaching; // when set, ignore calls to cacheFile; pending files dropped when done
- (void)beginCaching;

@end
