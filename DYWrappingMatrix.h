//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

/* DYWrappingMatrix */

#import <Cocoa/Cocoa.h>

@interface DYWrappingMatrix : NSControl
{
	NSMutableArray *cells;
	NSArray *filenames;
	float cellWidth;
	unsigned int numCells;
	NSMutableIndexSet *selectedIndexes;
	
	BOOL dragEntered;
	
	// vars used for repeated calculations
	int numCols, area_w, area_h;
	float cellHeight, columnSpacing;
}

- (void)addImage:(NSImage *)theImage withFilename:(NSString *)s;
//- (void)setImage:(NSImage *)theImage forIndex:(unsigned int)i;
- (void)removeAllImages;
//- (void)removeSelectedImages;
- (void)removeImageAtIndex:(unsigned int)i;

- (NSMutableIndexSet *)selectedIndexes;
- (IBAction)selectAll:(id)sender;
- (IBAction)selectNone:(id)sender;
- (void)addSelectedIndex:(unsigned int)i;

- (unsigned int)numCells;
- (NSSize)cellSize;
@end
