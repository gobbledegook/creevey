//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

/* DYCreeveyBrowser */

#import <Cocoa/Cocoa.h>
@protocol DYCreeveyBrowserDelegate <NSObject>
- (void)browser:(NSBrowser *)sender typedString:(NSString *)s inColumn:(NSInteger)column;
- (void)browserWillSendAction:(NSBrowser *)sender;
@end

// allows typing to select items (assumes lists are sorted)
// allows drag and drop
// supports separate display/underlying paths
@interface DYCreeveyBrowser : NSBrowser
- (id <NSBrowserDelegate,DYCreeveyBrowserDelegate>)delegate;
@end
