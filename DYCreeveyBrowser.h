//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

/* DYCreeveyBrowser */

#import <Cocoa/Cocoa.h>
@class DYTransparentGreyView;

@interface DYCreeveyBrowser : NSBrowser
{
	NSMutableString *typedString;
	NSTimeInterval lastKeyTime;
	DYTransparentGreyView *greyview;
}
@end
