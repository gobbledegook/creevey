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

BOOL FileIsJPEG(NSString *s);
NSMutableAttributedString* Fileinfo2EXIFString(NSString *origPath, DYImageCache *cache,
											   BOOL moreExif, BOOL basicInfo);

#define NUM_FNKEY_CATS 11

@interface CreeveyController : NSObject
{
	NSMutableSet *cats[NUM_FNKEY_CATS];
    IBOutlet SlideshowWindow *slidesWindow;
	IBOutlet NSProgressIndicator *jpegProgressBar;
	IBOutlet NSTextView *exifTextView; BOOL exifWasVisible;
	IBOutlet NSButton *exifThumbnailDiscloseBtn;
	DYJpegtranPanel *jpegController;

	NSSet *filetypes;
	NSMutableArray *creeveyWindows;
	CreeveyMainWindowController *frontWindow;
	
	DYImageCache *thumbsCache;
	
	// prefs stuff
	IBOutlet NSPanel *prefsWin;
	IBOutlet NSTextField *startupDirFld;
	IBOutlet NSMatrix *startupOptionMatrix;
	IBOutlet NSButton *slideshowApplyBtn;
	NSColor *slideshowBgColor;
}
// accessors
- (NSMutableSet **)cats;
- (DYImageCache *)thumbsCache;
- (NSTextView *)exifTextView;
- (NSSet *)filetypes;

- (IBAction)slideshow:(id)sender;
- (IBAction)openSelectedFiles:(id)sender;
- (IBAction)revealSelectedFilesInFinder:(id)sender;
- (IBAction)setDesktopPicture:(id)sender;
- (IBAction)moveToTrash:(id)sender;
- (IBAction)moveElsewhere:(id)sender;
- (IBAction)rotateTest:(id)sender;
- (IBAction)sortThumbnails:(id)sender;
- (IBAction)doShowFilenames:(id)sender;
- (IBAction)doAutoRotateDisplayedImage:(id)sender;

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
- (IBAction)versionCheck:(id)sender;
- (IBAction)sendFeedback:(id)sender;
@end
