//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  Created by d on 2005.04.03.

#import <Cocoa/Cocoa.h>

// returns path if it's not an alias, or if not resolvable
NSString *ResolveAliasToPath(NSString *path);
NSString *ResolveAliasURLToPath(NSURL *url);

// for extensions
BOOL IsJPEG(NSString *x);
BOOL IsRaw(NSString *x);
BOOL IsHeif(NSString *x);

// for paths
BOOL FileIsJPEG(NSString *s);

@interface NSImage (DYCarbonGoodies)
+ (instancetype)imageByReferencingFileIgnoringJPEGOrientation:(NSString *)fileName;
- (instancetype)initByReferencingFileIgnoringJPEGOrientation:(NSString *)fileName;
@end
