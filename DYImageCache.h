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

typedef NS_ENUM(char, DYImageQuality) {
	DYImageQualityLow,  // faster "thumbnail"
	DYImageQualityHigh, // scaled with high quality interpolation
	DYImageQualityFull, // the full size image
};

@interface DYImageInfo : NSObject {
	@public // access these instance variables like a struct
	time_t modTime;
	off_t fileSize;
	NSSize pixelSize;
	unsigned short exifOrientation;
	DYImageQuality quality;
}
@property (strong, nonatomic) NSImage *image;
@property (readonly, nonatomic) NSString *path;
- (instancetype)initWithPath:(NSString *)s NS_DESIGNATED_INITIALIZER;
@property (nonatomic, readonly) BOOL hasFullSizeImage;
@property (nonatomic, readonly, copy) NSString *pixelSizeAsString;
@end


@interface DYImageCache : NSObject
@property (nonatomic) BOOL fastThumbnails; // faster but lower quality rendering. default is NO
@property (strong, nonatomic) NSImage *fallbackImage; // if set, store this image in the cache if a file does not load
- (instancetype)initWithCapacity:(NSUInteger)n NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) float boundingWidth;
@property (nonatomic) NSSize boundingSize;

+ (NSData *)createNewThumbFromFile:(NSString *)path getSize:(NSSize *)outSize;

- (BOOL)cacheFile:(NSString *)s fullSize:(DYImageQuality)q; // returns YES if an image info object was added to the cache (and caller should eventually call endAccess:)
- (BOOL)loadFullSizeImageForCached:(DYImageInfo *)info;
- (BOOL)loadHighInterpolationImageForCached:(DYImageInfo *)info;

- (NSImage *)imageForKey:(NSString *)s;
- (NSImage *)imageForKeyInvalidatingCacheIfNecessary:(NSString *)s;
- (void)removeImageForKey:(NSString *)s;
- (void)removeAllImages;

- (DYImageInfo *)infoForKey:(NSString *)s;

// NSDiscardableContent accessors
- (void)beginAccess:(NSString *)key; // you should call beginAcess if you retain the image (e.g., after calling imageForKey:)
- (void)endAccess:(NSString *)key; // you should eventually call endAccess if cacheFile: returns YES or you call beginAcess:

- (void)abortCaching; // when set, ignore calls to cacheFile; pending files dropped when done
- (void)beginCaching;

@end
