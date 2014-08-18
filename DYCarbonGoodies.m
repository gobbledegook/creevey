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

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
NSString *ResolveAliasToPath(NSString *path) {
	NSString *resolvedPath = nil;
	CFURLRef url = CFURLCreateWithFileSystemPath(NULL /*allocator*/, (CFStringRef)path, kCFURLPOSIXPathStyle, NO /*isDirectory*/);
	if (url == NULL) return path;
	FSRef fsRef;
	if (CFURLGetFSRef(url, &fsRef)) {
		Boolean targetIsFolder, wasAliased;
		if (FSResolveAliasFileWithMountFlags(&fsRef, true /*resolveAliasChains*/, &targetIsFolder, &wasAliased, kResolveAliasFileNoUI) == noErr
			&& wasAliased) {
			CFURLRef resolvedUrl = CFURLCreateFromFSRef(NULL, &fsRef);
			if (resolvedUrl != NULL) {
				CFStringRef thePath = CFURLCopyFileSystemPath(resolvedUrl, kCFURLPOSIXPathStyle);
				resolvedPath = [(NSString*)thePath copy];
				CFRelease(thePath);
				CFRelease(resolvedUrl);
			}
		}
	}
	CFRelease(url);
	return resolvedPath ?: path;
}
#pragma GCC diagnostic pop

BOOL FileIsInvisible(NSString *path) {
	CFURLRef url = CFURLCreateWithFileSystemPath(NULL /*allocator*/, (CFStringRef)path,
												 kCFURLPOSIXPathStyle, NO /*isDirectory*/);
	if (url == NULL) return NO;
	LSItemInfoRecord info;
	OSStatus err = LSCopyItemInfoForURL (url, kLSRequestBasicFlagsOnly, &info);
	CFRelease(url);
	if (err) return NO;
	
	return (info.flags & kLSItemInfoIsInvisible) != 0;
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
