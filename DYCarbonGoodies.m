//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//
//  DYCarbonGoodies.m
//  creevey
//
//  Created by d on 2005.04.03.

#import "DYCarbonGoodies.h"

NSString *ResolveAliasToPath(NSString *path) {
	NSString *resolvedPath = nil;
	CFURLRef url = CFURLCreateWithFileSystemPath(NULL /*allocator*/, (CFStringRef)path, kCFURLPOSIXPathStyle, NO /*isDirectory*/);
	if (url == NULL) return path;
	// unlike FSResolveAliasFile, CFURLCreateBookMarkDataFromFile and its NSURL counterpart do not check
	// the kIsAlias flag. Apparently not all aliases/bookmarks have this bit set. But for our
	// purposes we can check it and skip the extra steps if the flag is set.
	Boolean isAlias = NO;
	CFBooleanRef b;
	if (CFURLCopyResourcePropertyForKey(url, kCFURLIsAliasFileKey, &b, NULL)) {
		isAlias = CFBooleanGetValue(b);
		CFRelease(b);
	}
	if (isAlias)
		resolvedPath = ResolveAliasURLToPath((NSURL *)url);
	CFRelease(url);
	return resolvedPath ?: path;
}

NSString *ResolveAliasURLToPath(NSURL *url) {
	NSString *path = nil;
	CFDataRef dataRef = CFURLCreateBookmarkDataFromFile(NULL, (CFURLRef)url, NULL);
	if (dataRef) {
		CFURLRef resolvedUrl = CFURLCreateByResolvingBookmarkData(NULL, dataRef, kCFBookmarkResolutionWithoutMountingMask|kCFBookmarkResolutionWithoutUIMask, NULL, NULL, NULL, NULL);
		if (resolvedUrl) {
			path = [(NSString *)CFURLCopyFileSystemPath(resolvedUrl, kCFURLPOSIXPathStyle) autorelease];
			CFRelease(resolvedUrl);
		}
		CFRelease(dataRef);
	}
	return path;
}

BOOL FileIsJPEG(NSString *s) {
	return [[[s pathExtension] lowercaseString] isEqualToString:@"jpg"]
	|| [[[s pathExtension] lowercaseString] isEqualToString:@"jpeg"]
	|| [NSHFSTypeOfFile(s) isEqualToString:@"JPEG"];
}

@implementation NSImage (DYCarbonGoodies)

+ (instancetype)imageByReferencingFileIgnoringJPEGOrientation:(NSString *)fileName
{
	return [[[NSImage alloc] initByReferencingFileIgnoringJPEGOrientation:fileName] autorelease];
}

- (instancetype)initByReferencingFileIgnoringJPEGOrientation:(NSString *)fileName
{
	if (FileIsJPEG(fileName)) return [self initWithDataIgnoringOrientation:[NSData dataWithContentsOfFile:fileName]];
	// initWithDataIgnoringOrientation: doesn't seem to create image representations for some (raw?) files
	return [self initByReferencingFile:fileName];
}

@end
