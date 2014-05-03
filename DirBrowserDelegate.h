//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

/* DirBrowserDelegate */

#import <Cocoa/Cocoa.h>
#import "DYCreeveyBrowser.h"
@class UKKQueue;

@interface DirBrowserDelegate : NSObject <DYCreeveyBrowserDelegate>
{
	NSMutableArray *cols, *colsInternal;
	NSString *rootVolumeName;
	BOOL showInvisibles;
	BOOL browserInited; // work around NSBrowser bug
	
	NSString *currPath;
	NSArray *currBrowserPathComponents;
	NSMutableSet *revealedDirectories;
	AliasHandle currAlias;
	
	UKKQueue *kq;
	IBOutlet NSBrowser *_b;
}
@end
