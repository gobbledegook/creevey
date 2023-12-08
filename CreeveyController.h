//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

/* CreeveyController */

#import <Cocoa/Cocoa.h>
#define CREEVEY_DEFAULT_PATH [@"~/Pictures" stringByResolvingSymlinksInPath]

@class CreeveyMainWindowController, DYImageCache, SlideshowWindow, DYJpegtranPanel;

NSMutableAttributedString* Fileinfo2EXIFString(NSString *origPath, DYImageCache *cache, BOOL moreExif);

#define NUM_FNKEY_CATS 11

@interface CreeveyController : NSObject <NSApplicationDelegate,NSTableViewDataSource,NSWindowRestoration>
{
	NSMutableSet *cats[NUM_FNKEY_CATS];
    BOOL exifWasVisible;

	NSMutableSet *filetypes;
	NSMutableSet *disabledFiletypes;
	NSMutableSet *fileostypes;
	NSArray *fileextensions;
	NSMutableDictionary *filetypeDescriptions;
	NSMutableArray *creeveyWindows;
	CreeveyMainWindowController * __weak frontWindow;
	
	DYImageCache *thumbsCache;
	
	// prefs stuff
	NSColor *slideshowBgColor;
	id localeChangeObserver;
	id screenChangeObserver;
}

@property (strong) IBOutlet DYJpegtranPanel *jpegController;
@property (strong) IBOutlet NSMenu *thumbnailContextMenu;
@property (readonly) NSMutableSet *revealedDirectories; // set of invisible directories that should be shown in the browser

@property (weak) IBOutlet SlideshowWindow *slidesWindow;
@property (weak) IBOutlet NSProgressIndicator *jpegProgressBar;
@property (weak) IBOutlet NSTextView *exifTextView;
@property (weak) IBOutlet NSButton *exifThumbnailDiscloseBtn;

// prefs stuff
@property (weak) IBOutlet NSPanel *prefsWin;
@property (weak) IBOutlet NSTextField *startupDirFld;
@property (weak) IBOutlet NSMatrix *startupOptionMatrix;
@property (weak) IBOutlet NSButton *slideshowApplyBtn;

// accessors
- (NSMutableSet * __strong *)cats;
- (DYImageCache *)thumbsCache;
- (BOOL)shouldShowFile:(NSString *)path;

- (IBAction)slideshow:(id)sender;
- (IBAction)slideshowInWindow:(id)sender;
- (IBAction)openSelectedFiles:(id)sender;
- (IBAction)revealSelectedFilesInFinder:(id)sender;
- (IBAction)setDesktopPicture:(id)sender;
- (IBAction)moveToTrash:(id)sender;
- (IBAction)rotateTest:(id)sender;
- (IBAction)sortThumbnails:(id)sender;
- (IBAction)doShowFilenames:(id)sender;
- (IBAction)doAutoRotateDisplayedImage:(id)sender;

- (void)slideshowFromAppOpen:(NSArray *)files;

// prefs stuff
- (IBAction)openPrefWin:(id)sender;
- (IBAction)chooseStartupDir:(id)sender;
- (IBAction)changeStartupOption:(id)sender;
- (IBAction)applySlideshowPrefs:(id)sender;
- (IBAction)slideshowDefaultsChanged:(id)sender;
- (NSColor *)slideshowBgColor;
- (void)setSlideshowBgColor:(NSColor *)value;
// info window thumbnail
- (IBAction)toggleExifThumbnail:(id)sender;
- (void)showExifThumbnail:(BOOL)b shrinkWindow:(BOOL)shrink;

- (IBAction)openAboutPanel:(id)sender;
- (IBAction)stopModal:(id)sender;
- (IBAction)openGetInfoPanel:(id)sender;
- (IBAction)newWindow:(id)sender;
- (IBAction)newTab:(id)sender;
- (IBAction)versionCheck:(id)sender;
- (IBAction)sendFeedback:(id)sender;
@end
