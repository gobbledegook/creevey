//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  Created by d on 2005.04.15.

#import "DYImageCache.h"
#import "DYCarbonGoodies.h"
#import "DYExiftags.h"
#import <sys/stat.h>

#define N_StringFromFileSize_UNITS 3
NSString *FileSize2String(unsigned long long fileSize) {
	char * const units[N_StringFromFileSize_UNITS] = {"KB", "MB", "GB"};
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
- (instancetype)init NS_UNAVAILABLE;
@property NSUInteger counter;
@end
@implementation DYImageInfo
@synthesize image, path;

- (instancetype)initWithPath:(NSString *)s {
	if (self = [super init]) {
		path = [s copy];
		_counter = 1; // NSCache may try to evict us immediately!
		
		struct stat buf;
		if (!stat(ResolveAliasToPath(s).fileSystemRepresentation, &buf)) {
			modTime = buf.st_mtimespec.tv_sec;
			fileSize = buf.st_size;
		}
	}
	return self;
}
- (NSString *)pixelSizeAsString {
	return [NSString stringWithFormat:@"%dx%d", (int)pixelSize.width, (int)pixelSize.height];
}

- (NSImage *)loadFullSizeImage {
	NSString *myPath = ResolveAliasToPath(path);
	CGImageSourceRef src = CGImageSourceCreateFromPath(myPath);
	if (src) {
		size_t idx;
		if (@available(macOS 10.14, *))
			idx = CGImageSourceGetPrimaryImageIndex(src);
		else idx = 0;
		NSString *type = (__bridge NSString *)CGImageSourceGetType(src);
		if (([type isEqualToString:@"com.compuserve.gif"]) && CGImageSourceGetCount(src) > 1) {
			// special case for animated gifs
			image = [[NSImage alloc] initWithContentsOfFile:myPath];
		} else {
			CGImageRef ref = CGImageSourceCreateImageAtIndex(src, idx, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCacheImmediately:@YES});
			if (ref) {
				image = [[NSImage alloc] initWithCGImage:ref size:NSZeroSize];
				CFRelease(ref);
			}
		}
		CFRelease(src);
	}
	return image;
}

#pragma mark NSDiscardableContent
- (BOOL)beginContentAccess {
	self.counter = self.counter + 1;
	return YES;
}
- (void)endContentAccess {
	if (self.counter)
		self.counter = self.counter - 1;
}
- (void)discardContentIfPossible {
	if (self.counter == 0) {
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
	
	_Atomic BOOL cachingShouldStop;

	NSUInteger _maxCount;
	NSMutableOrderedSet<NSString *> *stupidKeys;
	NSMutableDictionary<NSString *, DYImageInfo *> *stupidCacheWorkaround;
}
- (instancetype)init NS_UNAVAILABLE;
@end

@implementation DYImageCache
@synthesize boundingSize;
- (instancetype)initWithCapacity:(NSUInteger)n {
	if (self = [super init]) {
		images = [[NSCache alloc] init];
		images.countLimit = n;
		images.evictsObjectsWithDiscardedContent = YES;
		pending = [[NSMutableSet alloc] init];
		_maxCount = n;
		if (_maxCount < 20) {
			stupidKeys = [NSMutableOrderedSet orderedSetWithCapacity:n];
			stupidCacheWorkaround = [NSMutableDictionary dictionaryWithCapacity:n];
		}
		
		cacheLock = [[NSLock alloc] init];
		pendingLock = [[NSConditionLock alloc] initWithCondition:0];
	}
    return self;
}

- (void)beginAccess:(NSString *)key {
	[[images objectForKey:key] beginContentAccess];
}
- (void)endAccess:(NSString *)key {
	[[images objectForKey:key] endContentAccess];
}

- (float)boundingWidth { return boundingSize.width; }

// Image I/O does not support PDF or SVG, so use NSImage for these
static void ScaleImage(NSImage *orig, NSSize boundingSize, BOOL _rotatable, DYImageInfo *imgInfo) {
	NSImage *result;
	NSSize maxSize = boundingSize;
	if (orig && orig.representations.count) {
		NSImageRep *oldRep = orig.representations[0];
		NSSize oldSize = NSMakeSize(oldRep.pixelsWide, oldRep.pixelsHigh);
		if (oldSize.width == 0 || oldSize.height == 0) // PDF's don't have pixels
			oldSize = orig.size;
		
		if (oldSize.width != 0 && oldSize.height != 0) { // but if it's still 0, skip it, BAD IMAGE
			imgInfo->pixelSize = oldSize;
			if (_rotatable && (maxSize.height > maxSize.width) != (oldSize.height > oldSize.width)) {
				maxSize.height = boundingSize.width;
				maxSize.width = boundingSize.height;
			}
			
			if (oldSize.width <= maxSize.width && oldSize.height <= maxSize.height) {
				result = orig;
				if (!NSEqualSizes(oldSize,orig.size))
					orig.size = oldSize;
			} else {
				NSSize newSize;
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
				orig.size = newSize;
				result = [[NSImage alloc] initWithSize:newSize];
				[result lockFocus];
				[orig drawAtPoint:NSZeroPoint fromRect:NSMakeRect(0, 0, newSize.width, newSize.height) operation:NSCompositingOperationCopy fraction:1.0];
				[result unlockFocus];
			}
		}
	}
	imgInfo.image = result;
}

+ (NSData *)createNewThumbFromFile:(NSString *)path getSize:(NSSize *)outSize {
	NSData *result;
	CGImageSourceRef orig = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
	if (orig) {
		CGImageRef thumb = CGImageSourceCreateThumbnailAtIndex(orig, 0, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@(160), (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES});
		if (thumb) {
			NSMutableData *data = [[NSMutableData alloc] init];
			CGImageDestinationRef ref = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, (__bridge CFStringRef)@"public.jpeg", 1, NULL);
			if (ref) {
				CGImageDestinationAddImage(ref, thumb, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality:@0.0});
				if (CGImageDestinationFinalize(ref)) {
					result = data;
					outSize->width = CGImageGetWidth(thumb);
					outSize->height = CGImageGetHeight(thumb);
				}
				CFRelease(ref);
			}
			CFRelease(thumb);
		}
		CFRelease(orig);
	}
	return result;
}

static void ScaleCGImage(CGImageSourceRef orig, CGSize boundingSize, DYImageInfo *imgInfo, BOOL fastThumbnails) {
	size_t idx;
	if (@available(macOS 10.14, *))
		idx = CGImageSourceGetPrimaryImageIndex(orig);
	else idx = 0;
	NSString *type = (__bridge NSString *)CGImageSourceGetType(orig);
	CGImageRef full = CGImageSourceCreateImageAtIndex(orig, idx, fastThumbnails ? (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache:@NO} : NULL);
	if (full) {
		CGSize fullSize = {CGImageGetWidth(full),CGImageGetHeight(full)};
		imgInfo->pixelSize = fullSize;

		if (([type isEqualToString:@"com.compuserve.gif"]) && CGImageSourceGetCount(orig) > 1) {
			// special case for animated gifs
			imgInfo.image = [[NSImage alloc] initWithContentsOfFile:ResolveAliasToPath(imgInfo.path)];
		} else if (!fastThumbnails) {
			CGFloat maxLen = 1.5*boundingSize.width;
			if (imgInfo->pixelSize.width < maxLen && imgInfo->pixelSize.height < maxLen) {
				imgInfo.image = [[NSImage alloc] initWithCGImage:full size:NSZeroSize];
			} else {
				// if the image is significantly bigger than the bounding size, we should scale it down for speed/memory
				CGColorSpaceRef colorSpace = CGImageGetColorSpace(full);
				if (colorSpace) {
					CGSize newSize = boundingSize;
					if ((newSize.height > newSize.width) != (imgInfo->pixelSize.height > imgInfo->pixelSize.width)) {
						newSize.width = boundingSize.height;
						newSize.height = boundingSize.width;
					}
					CGFloat w_ratio = newSize.width/fullSize.width, h_ratio = newSize.height/fullSize.height;
					if (w_ratio < h_ratio) {
						newSize.height = (int)(fullSize.height*w_ratio);
					} else {
						newSize.width = (int)(fullSize.width*h_ratio);
					}
					CGContextRef ctx = CGBitmapContextCreate(NULL, newSize.width, newSize.height, CGImageGetBitsPerComponent(full), 0, colorSpace, CGImageGetBitmapInfo(full));
					if (ctx) {
						CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
						CGContextDrawImage(ctx, (CGRect){CGPointZero,newSize}, full);
						CGImageRef ref = CGBitmapContextCreateImage(ctx);
						if (ref) {
							imgInfo.image = [[NSImage alloc] initWithCGImage:ref size:NSZeroSize];
							CFRelease(ref);
						}
						CFRelease(ctx);
					}
				}
			}
		}
		CFRelease(full);
		if ([type isEqualToString:@"public.tiff"]) {
			NSImage *img = [[NSImage alloc] initByReferencingFile:imgInfo.path];
			NSSize expectedSize = img.size;
			// CGImageSourceCreateImageAtIndex returns tiny images for certain raw files (.NEF), so we work around it
			if (abs((int)(expectedSize.width - fullSize.width)) > 1000)
				imgInfo.image = nil;
		}
		if (imgInfo.image != nil) return;
	}
	if (!fastThumbnails) {
		// certain raw images don't seem to play well with CGImageSourceCreateImageAtIndex
		// so we fall back to NSImage
		imgInfo->exifOrientation = 0; // except now we let NSImage auto-rotate. Curiously enough, trying NSImage's -initWithDataIgnoringOrientation: runs into the same problem as using CGImage (tiny images)
		ScaleImage([[NSImage alloc] initByReferencingFile:imgInfo.path], boundingSize, YES, imgInfo);
		return;
	}
	BOOL isJpeg = [type isEqualToString:@"public.jpeg"];
	BOOL isHeic = [type isEqualToString:@"public.heic"];
	NSMutableDictionary *options = [NSMutableDictionary dictionary];
	options[(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize] = @(boundingSize.width);
	if (imgInfo->exifOrientation == 0) {
		options[(__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform] = @YES;
	}
	int embeddedThumbSize = isJpeg ? 160 : isHeic ? 320 : 0;
	CFStringRef key = boundingSize.width > embeddedThumbSize ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent;
	options[(__bridge NSString *)key] = @YES;
	CGImageRef thumb = CGImageSourceCreateThumbnailAtIndex(orig, idx, (__bridge CFDictionaryRef)options);
	if (thumb) {
		if (isJpeg) {
			size_t thumbW = CGImageGetWidth(thumb), thumbH = CGImageGetHeight(thumb);
			BOOL isPortrait = NO;
			if (thumbH > thumbW) {
				// check and swap dimensions in case the thumb is nonstandard
				size_t tmp = thumbW;
				thumbW = thumbH;
				thumbH = tmp;
				isPortrait = YES;
			}
			if (isPortrait != (imgInfo->pixelSize.width < imgInfo->pixelSize.height)
				|| (thumbW < 160 && 160 < (int)imgInfo->pixelSize.width)) {
				// If for some bizarre reason the image and its thumb are different orientations, just make a new thumb from scratch.
				[options removeObjectForKey:(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageIfAbsent];
				options[(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways] = @YES;
				CGImageRef newThumb = CGImageSourceCreateThumbnailAtIndex(orig, idx, (__bridge CFDictionaryRef)options);
				if (newThumb) {
					CFRelease(thumb);
					thumb = newThumb;
				}
			} else if (thumbW == 160 && thumbH == 120) {
				// EXIF thumb is normally 160x120 (4:3 ratio)
				// If the image is not the same proportion, we need to crop out the black areas in the thumbnail
				int w, h;
				if (isPortrait) {
					w = imgInfo->pixelSize.height;
					h = imgInfo->pixelSize.width;
				} else {
					w = imgInfo->pixelSize.width;
					h = imgInfo->pixelSize.height;
				}
				int w3 = w*3, h4 = h*4;
				if (w3 != h4) {
					CGRect thumbRect;
					if (h4 < w3) {
						thumbRect.size.width = 160;
						thumbRect.size.height = 160*h/w;
						thumbRect.origin.x = 0;
						thumbRect.origin.y = (120-thumbRect.size.height)/2;
					} else {
						thumbRect.size.width = 120*w/h;
						thumbRect.size.height = 120;
						thumbRect.origin.x = (160-thumbRect.size.width)/2;
						thumbRect.origin.y = 0;
					}
					if (isPortrait) {
						CGFloat tmp = thumbRect.size.width;
						thumbRect.size.width = thumbRect.size.height;
						thumbRect.size.height = tmp;
						tmp = thumbRect.origin.x;
						thumbRect.origin.x = thumbRect.origin.y;
						thumbRect.origin.y = tmp;
					}
					CGImageRef cropped = CGImageCreateWithImageInRect(thumb, thumbRect);
					if (cropped) {
						CFRelease(thumb); // cropped retains thumb, so it's safe to release here
						thumb = cropped;
					}
				}
			}
		}
		imgInfo.image = [[NSImage alloc] initWithCGImage:thumb size:NSZeroSize];
		CFRelease(thumb);
	}
}

- (void)createScaledImage:(DYImageInfo *)imgInfo {
	if (imgInfo->fileSize == 0)
		return;  // nsimage crashes on zero-length files
	NSString *path = ResolveAliasToPath(imgInfo.path);
	NSString *ext = path.pathExtension.lowercaseString;
	if (IsNotCGImage(ext)) {
		NSImage *img = [[NSImage alloc] initWithContentsOfFile:path];
		if (_fastThumbnails) {
			ScaleImage(img, boundingSize, _rotatable, imgInfo);
		} else {
			// return vector graphics in their non-pixelated glory
			imgInfo.image = img;
			imgInfo->pixelSize = img.size;
		}
	} else {
		CGImageSourceRef orig = CGImageSourceCreateFromPath(path);
		if (orig) {
			// get the orientation first; it will determine if ScaleCGImage needs to auto-rotate
			imgInfo->exifOrientation = [DYExiftags orientationForFile:path];
			ScaleCGImage(orig, boundingSize, imgInfo, _fastThumbnails);
			CFRelease(orig);
		}
	}
}

- (void)createScaledImage:(DYImageInfo *)imgInfo fromData:(NSData *)data ofType:(enum dcraw_type)dataType {
	NSString *hint;
	switch (dataType) {
		case dc_jpeg:
			hint = @"public.jpeg"; break;
		case dc_tiff:
			hint = @"public.tiff"; break;
		default:
			hint = @"public.pbm"; break;
	}
	NSDictionary *opts = @{(__bridge NSString *)kCGImageSourceTypeIdentifierHint: hint};
	CGImageSourceRef orig = CGImageSourceCreateWithData((__bridge CFDataRef)data, (__bridge CFDictionaryRef)opts);
	if (orig) {
		ScaleCGImage(orig, boundingSize, imgInfo, YES);
		CFRelease(orig);
	}
}

- (void)createFullsizeImage:(DYImageInfo *)imgInfo {
	if (imgInfo->fileSize == 0) return;
	NSString *path = ResolveAliasToPath(imgInfo.path);
	if (IsNotCGImage(path.pathExtension.lowercaseString)) {
		NSImage *img = [[NSImage alloc] initWithContentsOfFile:path];
		imgInfo.image = img;
		imgInfo->pixelSize = img.size;
	} else {
		imgInfo->exifOrientation = [DYExiftags orientationForFile:path];
		[imgInfo loadFullSizeImage];
		imgInfo->pixelSize = imgInfo.image.size;
	}
}


// see usage note in the .h file.
#define CacheContains(x)	([images objectForKey:x] != nil)
#define PendingContains(x)  ([pending containsObject:x])
//#define LOGCACHING 1
- (void)cacheFile:(NSString *)s {
	[self cacheFile:s fullSize:NO];
}
- (void)cacheFile:(NSString *)s fullSize:(BOOL)fullSize {
	if (![self attemptLockOnFile:s]) return;
	
	DYImageInfo *result = [[DYImageInfo alloc] initWithPath:s];
	if (fullSize)
		[self createFullsizeImage:result];
	else
		[self createScaledImage:result];
	if (result.image == nil)
		result.image = [NSImage imageNamed:@"brokendoc.tif"];

	[self addImage:result forFile:s];
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
#if LOGCACHING
		NSLog(@"waiting for pending %@", s.lastPathComponent);
#endif
		for (;;) {
			[pendingLock lockWhenCondition:s.hash];
			[pendingLock unlock];
			// in case of hash collisions, make sure the file has actually been removed from the pending set
			[cacheLock lock];
			if (!PendingContains(s)) {
				[cacheLock unlock];
#if LOGCACHING
				NSLog(@"done waiting for %@", s.lastPathComponent);
#endif
				[pendingLock lock];
				[pendingLock unlockWithCondition:s.hash];
				return NO;
			}
			[cacheLock unlock];
#if LOGCACHING
			NSLog(@"hash collision for %@, waiting again...", s.lastPathComponent);
#endif
		}
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
		if (stupidKeys && [images objectForKey:s] == nil) {
			// for some reason, very occasionally you can add an object to the cache but it doesn't stick. This results in sort of infinite looping in the slideshow as it creates a cached image which gets immediately discarded, over and over. The slideshow just shows a blank screen with the message "loading...". This should work around that.
			if (stupidKeys.count == _maxCount) {
				[stupidCacheWorkaround removeObjectForKey:stupidKeys[0]];
				[stupidKeys removeObjectAtIndex:0];
			}
			[stupidKeys addObject:s];
			stupidCacheWorkaround[s] = imgInfo;
		}
	}
	[cacheLock unlock];
	[pendingLock lock];
	[pendingLock unlockWithCondition:s.hash]; // signal to any waiting threads
}

- (void)dontAddFile:(NSString *)s {
	[cacheLock lock];
	[pending removeObject:s];
	[cacheLock unlock];
	[pendingLock lock];
	[pendingLock unlockWithCondition:s.hash];
}

- (DYImageInfo *)infoForKey:(NSString *)s {
	if (stupidKeys) return stupidCacheWorkaround[s] ?: [images objectForKey:s];
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
		struct stat buf;
		time_t modTime = stat(ResolveAliasToPath(s).fileSystemRepresentation, &buf) ? 0 : buf.st_mtimespec.tv_sec;

		// == nil if file doesn't exist
		if (modTime == imgInfo->modTime)
			return imgInfo.image;
		[self removeImageForKey:s];
	} else if (stupidKeys && stupidCacheWorkaround[s]) {
		return stupidCacheWorkaround[s].image;
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
			[pendingLock lockWhenCondition:s.hash];
			[pendingLock unlockWithCondition:s.hash];
			[cacheLock lock];
		}
		[images removeObjectForKey:s];
		if (stupidKeys) {
			[stupidKeys removeObject:s];
			[stupidCacheWorkaround removeObjectForKey:s];
		}
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
