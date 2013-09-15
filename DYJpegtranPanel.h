//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

/* DYJpegtranPanel */

#import <Cocoa/Cocoa.h>
#import "DYJpegtran.h"

@interface DYJpegtranPanel : NSObject
{
    IBOutlet NSPopUpButton *copyMarkersMenu;
    IBOutlet NSButton *grayscaleBtn;
    IBOutlet NSButton *optimizeBtn;
    IBOutlet NSButton *progressiveBtn;
    IBOutlet NSPopUpButton *transformMenu;
    IBOutlet NSButton *trimBtn;
}
- (IBAction)convert:(id)sender;
- (IBAction)stopModal:(id)sender;
- (IBAction)transformChanged:(id)sender;

- (BOOL)runOptionsPanel:(DYJpegtranInfo *)i;
@end
