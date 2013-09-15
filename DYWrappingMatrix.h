//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

/* DYWrappingMatrix */

#import <Cocoa/Cocoa.h>

// displays thumbnails of image files
// for fastest results, make thumbnails yourself to avoid scaling
// supports selection, drag/drop, keyboard navigation
// assumes it is embedded in a scrollview
@interface DYWrappingMatrix : NSControl
{
	IBOutlet id delegate;

	NSColor *bgColor;
	BOOL autoRotate;
	NSImageCell *myCell;           // one cell, reused for efficiency
	NSCell *myTextCell; // for drawing the file name
	NSMutableArray *images;
	NSMutableArray *filenames;
	float cellWidth;
	unsigned int numCells;
	NSMutableIndexSet *selectedIndexes;
	
	BOOL dragEntered;
	
	// vars used for repeated calculations
	int numCols;
	float cellHeight, columnSpacing, area_w, area_h;
	unsigned int textHeight;
}

+ (NSSize)maxCellSize;

- (void)addImage:(NSImage *)theImage withFilename:(NSString *)s;
- (void)setImage:(NSImage *)theImage forIndex:(unsigned int)i;
- (void)removeAllImages;
//- (void)removeSelectedImages;
- (void)removeImageAtIndex:(unsigned int)i;

// call when no images, preparing to add (for two-pass adding)
//- (void)setFilenames:(NSArray *)a;


- (NSArray *)filenames;
- (NSMutableIndexSet *)selectedIndexes;
- (NSArray *)selectedFilenames;
- (NSString *)firstSelectedFilename;
- (IBAction)selectAll:(id)sender;
- (IBAction)selectNone:(id)sender;
- (void)addSelectedIndex:(unsigned int)i;
- (void)selectIndex:(unsigned int)i;

- (unsigned int)numCells;
- (NSSize)cellSize;
- (float)maxCellWidth;
- (float)minCellWidth;
- (float)cellWidth;
- (void)setCellWidth:(float)w;

- (BOOL)showFilenames;
- (void)setShowFilenames:(BOOL)b;
- (BOOL)autoRotate;
- (void)setAutoRotate:(BOOL)b;

- (void)updateStatusString; // ** rename me
- (void)setDelegate:(id)d;

@end

@interface NSObject(DYWrappingMatrixTarget)
- (IBAction)moveToTrash:(id)sender; // dragging to trashcan will call this
- (IBAction)moveElsewhere:(id)sender; // moving a file to the Finder will call this
- (void)wrappingMatrix:(DYWrappingMatrix *)m selectionDidChange:(NSIndexSet *)s;
@end

