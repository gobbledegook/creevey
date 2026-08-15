//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

@import Cocoa;

@class DYWrappingMatrix, DYCreeveyBrowser;

@interface CreeveyMainWindowController : NSWindowController <NSWindowDelegate,NSSplitViewDelegate>
@property (weak) IBOutlet DYCreeveyBrowser *dirBrowser;
@property (weak) IBOutlet NSButton *slidesBtn;
@property (weak) IBOutlet DYWrappingMatrix *imgMatrix;
@property (weak) IBOutlet NSTextField *statusFld;
@property (weak) IBOutlet NSTextField *bottomStatusFld;
@property (weak) IBOutlet NSButton *subfoldersButton;
@property (weak) IBOutlet NSButton *unsupportedButton;

- (IBAction)setRecurseSubfolders:(id)sender;

// accessors
@property (nonatomic, readonly) NSString *path;
- (BOOL)setPath:(NSString *)s; // navigate the directory browser to a folder; NO if invalid
@property (nonatomic) BOOL pathBarVisible;
@property (nonatomic) BOOL directoryBrowserVisible;
@property (nonatomic) BOOL showUnsupportedFiles;
@property (nonatomic, readonly) NSURL *URL;
@property (nonatomic, readonly) NSArray *currentSelection;
@property (nonatomic, readonly) NSIndexSet *selectedIndexes;
- (void)selectIndex:(NSUInteger)i;
- (IBAction)copy:(id)sender; // forwards Cmd-C to the thumbnail grid (also called from the dir browser)
@property (nonatomic, readonly) NSArray *displayedFilenames;
- (NSUInteger)indexOfFilename:(NSString *)s;
@property (nonatomic, readonly) BOOL currentFilesDeletable;
@property (nonatomic, readonly) BOOL filenamesDone;
@property (nonatomic) short sortOrder;
- (void)changeSortOrder:(short int)n;
@property (nonatomic, readonly) NSComparator comparator;
@property (readonly) BOOL wantsSubfolders;
@property (nonatomic, readonly) DYWrappingMatrix *imageMatrix;

// Open Recent: capture the window's full navigable state, and restore it (navigate +
// apply sort/toggles + select the remembered file once the async load finishes)
- (NSDictionary *)currentStateDictionary;
- (void)restoreState:(NSDictionary *)state;

//other
- (void)setDefaultPath;
- (void)updateDefaults;
- (void)openFiles:(NSArray *)a withSlideshow:(BOOL)b;
- (void)fakeKeyDown:(NSEvent *)e;
- (void)reloadInterfaceTextSize;
- (void)focusSearchField; // File > Search: focus the filter field and select its text
- (BOOL)isArchivePath:(NSString *)path; // YES for .zip/.cbz
- (void)openArchive:(NSString *)zipPath; // extract a .zip to a temp folder and browse it
+ (void)sweepLeftoverArchiveTemps; // delete stale extracted-archive temp dirs (launch/quit only)

// notifiers
- (void)fileWasChanged:(NSString *)s;
- (void)fileWasDeleted:(NSString *)s;
- (void)filesWereUndeleted:(NSArray *)a;
- (void)updateExifInfo;

@end

NSComparator ComparatorForSortOrder(short sortOrder);
