//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import <Cocoa/Cocoa.h>
#import "DYCreeveyBrowser.h"

@interface DirBrowserDelegate : NSObject <DYCreeveyBrowserDelegate>
- (NSString*)path;
- (void)setPath:(NSString *)s;
@property (weak) IBOutlet NSBrowser *b;
@property (weak) NSMutableSet *revealedDirectories;
@property (readonly) NSString *currPath;
@end
