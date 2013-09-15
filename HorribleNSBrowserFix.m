//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//
//  HorribleNSBrowserFix.m
//  creevey
//
//  Created by d on 2005.04.16.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

// suppress animation which seems to crash AppKit
// this appears to be unnecessary in 10.4
// easier?: try setting the NSBrowserSupportsContinuousScrolling default to NO

struct __BrcshFlags {
    unsigned int done:1;
    unsigned int animate:1;
    unsigned int shouldPostScrollNotifications:1;
    unsigned int needsEndColumnAnimationOptimization:1;
    unsigned int reserved:28;
};

@interface _NSBrowserColumnScrollHelper : NSObject
{
    id _scrollView;
    id _optimizableColumn;
    struct _NSPoint _initialOrigin;
    struct _NSRect _destinationRect;
    float _totalDistance;
    float _totalDuration;
    struct __BrcshFlags _brcshFlags;
    double _startTime;
    struct __CFRunLoopTimer *_timer;
    struct __CFRunLoop *_runLoop;
    struct __CFRunLoopObserver *_displayWindowForBrowserObserver;
}
- (void)scrollRectToVisible:(struct _NSRect)fp8 inScrollView:(id)fp24 animate:(BOOL)fp28;
@end

@interface _NSBrowserColumnScrollHelper2 : _NSBrowserColumnScrollHelper
@end
@implementation _NSBrowserColumnScrollHelper2
+ (void)load {
	// only load for 10.3
	// i've only tested for 10.3.8, though
	if (floor(NSAppKitVersionNumber) == 743)
		[_NSBrowserColumnScrollHelper2 poseAsClass:[_NSBrowserColumnScrollHelper class]];
	// 10.3.2 is 743.14
	// 10.3.3 is 743.2
	// 10.3.5 is 743.24
	// 10.3.8 is 743.33
}
- (void)scrollRectToVisible:(NSRect)r inScrollView:(id)sv animate:(BOOL)b {
	[super scrollRectToVisible:r inScrollView:(id)sv animate:NO];
}
@end


