//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "DYJpegtranPanel.h"

@implementation DYJpegtranPanel
- (IBAction)transformChanged:(id)sender
{
	[self.trimBtn setEnabled:[[sender selectedItem] tag]==JXFORM_NONE || [[sender selectedItem] tag]==JXFORM_TRANSPOSE
		? NSOffState : NSOnState];
}

- (IBAction)convert:(id)sender
{
	[NSApp stopModalWithCode:100];
}

- (IBAction)stopModal:(id)sender
{
	[NSApp stopModal];
}

- (BOOL)runOptionsPanel:(DYJpegtranInfo *)i {
	// set defaults
	[self.transformMenu selectItemAtIndex:0];
	[self.trimBtn setEnabled:NO]; [self.trimBtn setState:NSOffState];
	[self.grayscaleBtn setState:NSOffState];
	[self.markersMenu selectItemAtIndex:0];
	[self.progressiveBtn setState:NSOffState];
	[self.optimizeBtn setState:NSOffState];
	
	// run dialog
	int n = [NSApp runModalForWindow:[self.transformMenu window]];
	[[self.transformMenu window] orderOut:nil];
	if (n != 100) return NO;
	
	// fill in the blanks
	i->tinfo.transform = [[self.transformMenu selectedItem] tag];
	i->tinfo.trim = [self.trimBtn isEnabled] && [self.trimBtn state];
	i->tinfo.force_grayscale = [self.grayscaleBtn state];
	i->cp = [[self.markersMenu selectedItem] tag];
	i->progressive = [self.progressiveBtn state];
	i->optimize = [self.optimizeBtn state];
	i->thumbOnly = 0;
	i->autorotate = 0;
	i->resetOrientation = 0;
	i->replaceThumb = 0;
	i->delThumb = 0;
	return YES;
}

@end
