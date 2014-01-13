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

// Originally the design of this class was as follows: for each image,
// you create a little thumbnail to display and add it to the matrix
// one by one. Unfortunately this means you can only load the matrix
// as fast as you can generate images, which can be slow.
// I am going to try a new method where if no image is set, the matrix
// will ask its delegate for one. The delegate will either come back
// with one right away, or promise to supply it, in which case it is
// expected to come back with the filename and the previous index.
// Since the index might have changed, if the filename and index don't match,
// the matrix will have to do a search (probably outwards from the index)
// to find the correct index and update, then draw it if it's visible
// in the scroll view.
@interface DYWrappingMatrix : NSControl
{
	IBOutlet id delegate;

	NSColor *bgColor;
	BOOL autoRotate;
	NSImageCell *myCell;           // one cell, reused for efficiency
	NSCell *myTextCell; // for drawing the file name
	NSImage *loadingImage; // loads up "loading.png" on init
	NSMutableArray *images;
	NSMutableArray *filenames;
	NSMutableSet *requestedFilenames; // keep track of which files we've requested images for
	volatile NSUInteger numThumbsLoaded;
	float cellWidth;
	NSUInteger numCells;
	NSMutableIndexSet *selectedIndexes;
	
	BOOL dragEntered;
	
	// vars used for repeated calculations
	int numCols;
	float cellHeight, columnSpacing, area_w, area_h;
	unsigned int textHeight;
}

+ (NSSize)maxCellSize;

- (void)addImage:(NSImage *)theImage withFilename:(NSString *)s;
- (void)setImage:(NSImage *)theImage forIndex:(NSUInteger)i;
- (void)setImageWithFileInfo:(NSDictionary *)d; // to be called on main thread from other thread
- (BOOL)imageWithFileInfoNeedsDisplay:(NSDictionary *)d;
- (void)removeAllImages;
//- (void)removeSelectedImages;
- (void)removeImageAtIndex:(NSUInteger)i;

// call when no images, preparing to add (for two-pass adding)
//- (void)setFilenames:(NSArray *)a;


- (NSArray *)filenames;
- (NSMutableIndexSet *)selectedIndexes;
- (NSArray *)selectedFilenames;
- (NSString *)firstSelectedFilename;
- (IBAction)selectAll:(id)sender;
- (IBAction)selectNone:(id)sender;
- (void)addSelectedIndex:(NSUInteger)i;
- (void)selectIndex:(NSUInteger)i;

- (NSUInteger)numCells;
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
- (NSUInteger)numThumbsLoaded;
- (void)setDelegate:(id)d;

@end

@interface NSObject(DYWrappingMatrixTarget)
- (IBAction)moveToTrash:(id)sender; // dragging to trashcan will call this
- (IBAction)moveElsewhere:(id)sender; // moving a file to the Finder will call this
- (void)wrappingMatrix:(DYWrappingMatrix *)m selectionDidChange:(NSIndexSet *)s;
- (NSImage *)wrappingMatrix:(DYWrappingMatrix *)m loadImageForFile:(NSString *)filename atIndex:(NSUInteger)i;
@end

