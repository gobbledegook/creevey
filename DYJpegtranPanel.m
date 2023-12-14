//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "DYJpegtranPanel.h"

@implementation DYJpegtranPanel
- (IBAction)transformChanged:(id)sender
{
	NSInteger tag = _transformMenu.selectedItem.tag;
	_trimBtn.enabled = tag != JXFORM_NONE && tag != JXFORM_TRANSPOSE;
	_convertButton.enabled =
		_transformMenu.selectedItem.tag ||
		(_trimBtn.enabled && _trimBtn.state) ||
		_progressiveBtn.state ||
		_optimizeBtn.state ||
		_grayscaleBtn.state ||
		_markersMenu.selectedItem.tag != JCOPYOPT_ALL;
}

- (IBAction)convert:(id)sender
{
	[NSApp stopModalWithCode:NSModalResponseOK];
}

- (IBAction)stopModal:(id)sender
{
	[NSApp stopModalWithCode:NSModalResponseCancel];
}

- (BOOL)runOptionsPanel:(DYJpegtranInfo *)i {
	// set defaults
	[self.transformMenu selectItemAtIndex:0];
	self.trimBtn.enabled = NO;
	self.trimBtn.state = NSOffState;
	self.grayscaleBtn.state = NSOffState;
	[self.markersMenu selectItemAtIndex:0];
	self.progressiveBtn.state = NSOffState;
	self.optimizeBtn.state = NSOffState;
	
	// run dialog
	NSModalResponse n = [NSApp runModalForWindow:self.transformMenu.window];
	[self.transformMenu.window orderOut:nil];
	if (n != NSModalResponseOK) return NO;
	
	// fill in the blanks
	i->tinfo.transform = (JXFORM_CODE)self.transformMenu.selectedItem.tag;
	i->tinfo.trim = self.trimBtn.enabled && self.trimBtn.state;
	i->tinfo.force_grayscale = (boolean)self.grayscaleBtn.state;
	i->cp = (JCOPY_OPTION)self.markersMenu.selectedItem.tag;
	i->progressive = self.progressiveBtn.state;
	i->optimize = self.optimizeBtn.state;
	i->thumbOnly = 0;
	i->autorotate = 0;
	i->resetOrientation = 0;
	i->replaceThumb = 0;
	i->delThumb = 0;
	return YES;
}

@end
