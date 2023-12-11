//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import <Cocoa/Cocoa.h>

@class DYWrappingMatrix, DYCreeveyBrowser;

@interface CreeveyMainWindowController : NSWindowController <NSWindowDelegate,NSSplitViewDelegate>
@property (weak) IBOutlet DYCreeveyBrowser *dirBrowser;
@property (weak) IBOutlet NSButton *slidesBtn;
@property (weak) IBOutlet DYWrappingMatrix *imgMatrix;
@property (weak) IBOutlet NSTextField *statusFld;
@property (weak) IBOutlet NSTextField *bottomStatusFld;
@property (weak) IBOutlet NSButton *subfoldersButton;

- (IBAction)setRecurseSubfolders:(id)sender;

// accessors
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly, copy) NSArray *currentSelection;
@property (nonatomic, readonly) NSIndexSet *selectedIndexes;
- (void)selectIndex:(NSUInteger)i;
@property (nonatomic, readonly) NSArray *displayedFilenames;
- (NSUInteger)indexOfFilename:(NSString *)s;
@property (nonatomic, readonly) BOOL currentFilesDeletable;
@property (nonatomic, readonly) BOOL filenamesDone;
@property (nonatomic) short sortOrder;
- (void)changeSortOrder:(short int)n;
@property (nonatomic, readonly) NSComparator comparator;
@property (readonly) BOOL wantsSubfolders;
@property (nonatomic, readonly) DYWrappingMatrix *imageMatrix;

//other
- (void)setDefaultPath;
- (void)updateDefaults;
- (void)openFiles:(NSArray *)a withSlideshow:(BOOL)b;
- (void)fakeKeyDown:(NSEvent *)e;

// notifiers
- (void)fileWasChanged:(NSString *)s;
- (void)fileWasDeleted:(NSString *)s;
- (void)filesWereUndeleted:(NSArray *)a;
- (void)updateExifInfo;

@end
