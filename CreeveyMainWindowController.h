//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

/* CreeveyMainWindowController */

#import <Cocoa/Cocoa.h>

@class DYWrappingMatrix;

@interface CreeveyMainWindowController : NSWindowController <NSWindowDelegate>
{
    IBOutlet NSBrowser *dirBrowser;
	IBOutlet NSButton *slidesBtn;
	IBOutlet DYWrappingMatrix *imgMatrix;
	IBOutlet NSTextField *statusFld, *bottomStatusFld;

	NSMutableArray *filenames, *displayedFilenames;
	NSLock *loadImageLock; NSTimeInterval lastThreadTime;
	volatile char stopCaching;
	
	NSConditionLock *imageCacheQueueLock;
	NSMutableArray *imageCacheQueue, *secondaryImageCacheQueue;
	volatile BOOL imageCacheQueueRunning;

	BOOL currentFilesDeletable;
	volatile BOOL filenamesDone, loadingDone, // loadingDone only meaningful if filenamesDone is true, always check both!
		startSlideshowWhenReady;
	NSMutableSet *filesBeingOpened; // to be selected
	BOOL recurseSubfolders;
	BOOL showInvisibles;
	short int sortOrder;
	
	short int currCat;
}
//actions
- (IBAction)setRecurseSubfolders:(id)sender;

// accessors
- (NSString *)path;
- (BOOL)setPath:(NSString *)s;
- (NSArray *)currentSelection;
- (NSIndexSet *)selectedIndexes;
- (void)selectIndex:(NSUInteger)i;
- (NSString *)firstSelectedFilename;
- (NSArray *)displayedFilenames;
- (BOOL)currentFilesDeletable;
- (BOOL)filenamesDone;
- (short int)sortOrder;
- (void)setSortOrder:(short int)n;
- (void)changeSortOrder:(short int)n;
- (DYWrappingMatrix *)imageMatrix;

//other
- (void)setDefaultPath;
- (void)updateDefaults;
- (void)openFiles:(NSArray *)a withSlideshow:(BOOL)b;

// notifiers
- (void)fileWasChanged:(NSString *)s;
- (void)fileWasDeleted:(NSString *)s;
- (void)updateExifInfo;


@end
