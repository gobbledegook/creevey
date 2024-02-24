//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  Created by d on 2005.04.03.

#import "DYCarbonGoodies.h"

NSString *ResolveAliasToPath(NSString *path) {
	NSURL *resolved;
	CFURLRef url = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)path, kCFURLPOSIXPathStyle, NO /*isDirectory*/);
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
		resolved = ResolveAliasURL((__bridge NSURL *)url);
	CFRelease(url);
	return resolved ? resolved.path : path;
}

NSURL * _Nullable ResolveAliasURL(NSURL *url) {
	NSURL *result;
	CFDataRef dataRef = CFURLCreateBookmarkDataFromFile(NULL, (__bridge CFURLRef)url, NULL);
	if (dataRef) {
		CFURLRef resolvedUrl = CFURLCreateByResolvingBookmarkData(NULL, dataRef, kCFBookmarkResolutionWithoutMountingMask|kCFBookmarkResolutionWithoutUIMask, NULL, NULL, NULL, NULL);
		if (resolvedUrl) {
			result = (NSURL *)CFBridgingRelease(resolvedUrl);
		}
		CFRelease(dataRef);
	}
	return result;
}

BOOL IsJPEG(NSString *x) {
	return [x isEqualToString:@"jpg"] || [x isEqualToString:@"jpeg"];
}

BOOL IsRaw(NSString *x) {
	static NSSet *exts;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		exts = [NSSet setWithArray:@[@"3fr", @"arw", @"cr2", @"cr3", @"crw", @"dcr", @"dng", @"dxo", @"erf", @"exr", @"fff", @"iiq", @"mos", @"mrw", @"nef", @"nrw", @"orf", @"pef", @"raf", @"raw", @"rw2", @"rwl", @"srf", @"srw", @"tif"]];
	});
	return [exts containsObject:x];
}

BOOL IsHeif(NSString *x) {
	static NSSet *exts;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		exts = [NSSet setWithArray:@[@"heic", @"heics", @"heif", @"hif", @"avci"]];
	});
	return [exts containsObject:x];
}

BOOL IsNotCGImage(NSString *x) {
	return [x isEqualToString:@"pdf"] || [x hasPrefix:@"svg"];
}

BOOL FileIsJPEG(NSString *s) {
	NSString *x = s.pathExtension.lowercaseString;
	return [x isEqualToString:@"jpg"] || [x isEqualToString:@"jpeg"]
	|| [NSHFSTypeOfFile(s) isEqualToString:@"JPEG"];
}

CGImageSourceRef _Nullable CGImageSourceCreateFromPath(NSString *path) {
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (data) return CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
	return NULL;
}
