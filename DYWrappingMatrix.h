//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

@import Cocoa;

@interface DYMatrixState : NSObject
- (BOOL)imageWithFileInfoNeedsDisplay:(NSArray *)d;
@end

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
@property (weak) IBOutlet id delegate;
@property (weak, nonatomic) NSImage *loadingImage;

@property (class, readonly) NSSize maxCellSize;

- (void)addImage:(NSImage *)theImage withFilename:(NSString *)s;
- (void)addImage:(NSImage *)theImage withFilename:(NSString *)s atIndex:(NSUInteger)i;
- (void)updateImage:(NSImage *)theImage atIndex:(NSUInteger)i;
- (BOOL)setImage:(NSImage *)theImage atIndex:(NSUInteger)i forFilename:(NSString *)s; // to be called on main thread from other thread
@property (nonatomic, readonly) DYMatrixState *currentState;
- (void)removeAllImages;
- (void)removeImageAtIndex:(NSUInteger)i;
- (void)moveImageAtIndex:(NSUInteger)fromIdx toIndex:(NSUInteger)toIdx;
- (void)changeBase:(NSString *)basePath toPath:(NSString *)newBase;

@property (nonatomic, readonly) NSArray *filenames;
@property (nonatomic, readonly) NSMutableIndexSet *selectedIndexes;
@property (nonatomic, readonly, copy) NSArray *selectedFilenames;
@property (nonatomic, readonly) NSString *firstSelectedFilename;
- (IBAction)selectAll:(id)sender;
- (IBAction)selectNone:(id)sender;
- (void)selectFilenames:(NSArray *)arr comparator:(NSComparator)cmp;
- (void)selectIndex:(NSUInteger)i;
- (void)scrollToFirstSelected:(NSIndexSet *)x;

@property (nonatomic, readonly) NSUInteger numCells;

// minCellWidth, cellWidth, and maxCellWidth are bound to the slider via a generic NSObjectController
// minCellWidth is hard-coded
// cellWidth may change dynamically
// maxCellWidth should be bound to the corresponding controller's value, and must also be initialized separately
@property (nonatomic) float maxCellWidth;
@property (nonatomic, readonly) float minCellWidth;
@property (nonatomic) float cellWidth;

@property (nonatomic) BOOL showFilenames;
@property (nonatomic) BOOL autoRotate;

// these return nonmutable copies of arrays and should each be called once when moveElsewhere is called
@property (nonatomic, readonly, copy) NSArray<NSURL *> *movedUrls;
@property (nonatomic, readonly, copy) NSArray<NSString *> *originPaths;
@end

@interface NSObject(DYWrappingMatrixTarget)
- (void)moveToTrash:(id)sender; // dragging to trashcan will call this
- (void)moveElsewhere; // moving a file to the Finder will call this
- (void)wrappingMatrixSelectionDidChange:(NSIndexSet *)s;
- (NSImage *)wrappingMatrixWantsImageForFile:(NSString *)filename atIndex:(NSUInteger)i;
- (unsigned short)exifOrientationForFile:(NSString *)s;
@property (readonly) NSMenu *thumbnailContextMenu;
@end

