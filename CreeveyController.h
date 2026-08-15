//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

@import Cocoa;
#define CREEVEY_DEFAULT_PATH [@"~/Pictures" stringByResolvingSymlinksInPath]

@class DYImageCache, SlideshowWindow, DYJpegtranPanel, KeyBindings, CreeveyMainWindowController;

NSMutableAttributedString* Fileinfo2EXIFString(NSString *origPath, DYImageCache *cache, BOOL moreExif);

// Compact, scrollable alert listing files a Move/Copy operation couldn't process.
void DYReportFileErrors(NSString *messageText, NSArray<NSString *> *files);

// Multiplier for interface text (1.0 / 1.25 / 1.5) from the "interfaceTextSize" preference.
CGFloat DYInterfaceTextScale(void);

#define NUM_FNKEY_CATS 11

@interface CreeveyController : NSObject <NSApplicationDelegate,NSTableViewDataSource,NSWindowRestoration>
@property (strong) IBOutlet DYJpegtranPanel *jpegController;
@property (strong) IBOutlet NSMenu *thumbnailContextMenu;
@property (readonly) NSMutableSet *revealedDirectories; // set of invisible directories that should be shown in the browser

@property (weak) IBOutlet SlideshowWindow *slidesWindow;
@property (weak) IBOutlet NSProgressIndicator *jpegProgressBar;
@property (weak) IBOutlet NSTextView *exifTextView;
@property (weak) IBOutlet NSButton *exifThumbnailDiscloseBtn;

@property (weak) IBOutlet NSPanel *prefsWin;
@property (weak) IBOutlet NSButton *slideshowApplyBtn;

@property (weak) IBOutlet NSButton *slideshowDefaultModeFullscreenBtn;

// accessors
@property (nonatomic, readonly) NSMutableSet * __strong *cats;
- (void)updateCats;
@property (nonatomic, readonly) DYImageCache *thumbsCache;
@property (nonatomic, readonly) KeyBindings *keyBindings;
NSDirectoryEnumerator *CreeveyEnumerator(NSString *path, BOOL recurseSubfolders);
- (BOOL)handledDirectory:(NSURL *)url subfolders:(BOOL)recurse e:(NSDirectoryEnumerator *)e;
- (BOOL)shouldShowFile:(NSURL *)path;
- (void)noteRecentFolderForWindow:(CreeveyMainWindowController *)wc; // Open Recent: record the window's current folder+state
- (BOOL)shouldShowFile:(NSURL *)url includingUnsupported:(BOOL)includeUnsupported;

- (IBAction)slideshow:(id)sender;
- (IBAction)slideshowAlternateMode:(id)sender;
- (IBAction)openSelectedFiles:(id)sender;
- (IBAction)quickLook:(id)sender;
- (IBAction)revealSelectedFilesInFinder:(id)sender;
- (IBAction)copySelectedFilePaths:(id)sender;
- (IBAction)setDesktopPicture:(id)sender;
- (IBAction)moveSelectedFiles:(id)sender;
- (IBAction)copySelectedFiles:(id)sender;
- (IBAction)moveToRecentFolder:(id)sender; // File ▸ Move To Recent ▸ <folder>
- (IBAction)copyToRecentFolder:(id)sender; // File ▸ Copy To Recent ▸ <folder>
- (void)recordRecentMoveDestination:(NSString *)path; // push a Move destination onto the recent list
- (void)recordRecentCopyDestination:(NSString *)path; // push a Copy destination onto the recent list
- (IBAction)moveToTrash:(id)sender;
- (IBAction)deleteSelectedFilesPermanently:(id)sender;
- (IBAction)renameSelectedFile:(id)sender;
- (IBAction)transformJpeg:(id)sender;
- (IBAction)sortThumbnails:(id)sender;
- (IBAction)doShowFilenames:(id)sender;
- (IBAction)togglePathBar:(id)sender;
- (IBAction)toggleDirectoryBrowser:(id)sender;
- (IBAction)toggleUnsupportedFiles:(id)sender;
- (IBAction)doAutoRotateDisplayedImage:(id)sender;

- (void)slideshowFromAppOpen:(NSArray *)files;

// prefs stuff
- (IBAction)openPrefWin:(id)sender;
- (IBAction)goToFolder:(id)sender;
- (IBAction)searchImages:(id)sender;
- (IBAction)toggleSubfolders:(id)sender;
- (IBAction)chooseStartupDir:(id)sender;
- (IBAction)applySlideshowPrefs:(id)sender;
- (IBAction)slideshowDefaultsChanged:(id)sender;
- (IBAction)chooseDefaultSlideshowMode:(id)sender;

// info window
- (IBAction)openGetInfoPanel:(id)sender;
- (IBAction)toggleExifThumbnail:(id)sender;

- (IBAction)reloadConfiguration:(id)sender;
- (IBAction)editConfiguration:(id)sender;
- (IBAction)revealConfiguration:(id)sender;

- (IBAction)openAboutPanel:(id)sender;
- (IBAction)stopModal:(id)sender;
- (IBAction)newWindow:(id)sender;
- (IBAction)newTab:(id)sender;
- (IBAction)versionCheck:(id)sender;
- (IBAction)sendFeedback:(id)sender;
@end
