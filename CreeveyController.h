//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

/* CreeveyController */

#import <Cocoa/Cocoa.h>
#import "DYImageCache.h"
#import "SlideshowWindow.h"
#import "DYWrappingMatrix.h"
#import "RBSplitView.h"

@interface CreeveyController : NSObject
{
    IBOutlet NSBrowser *dirBrowser;
    IBOutlet SlideshowWindow *slidesWindow;
	IBOutlet NSButton *slidesBtn;
	IBOutlet DYWrappingMatrix *imgMatrix;
	IBOutlet NSTextField *statusFld, *bottomStatusFld;
	
	NSSet *filetypes;
	
	NSMutableArray *filenames;
	DYImageCache *thumbsCache;
	NSLock *thumbsCacheLock; BOOL stopCaching; NSTimeInterval lastThreadTime;
	
	BOOL currentFilesDeletable;
	BOOL filenamesDone;
	NSMutableSet *filesBeingOpened;
	BOOL recurseSubfolders;
	BOOL showInvisibles;
	
	// prefs stuff
	IBOutlet NSPanel *prefsWin;
	IBOutlet NSTextField *startupDirFld;
	IBOutlet NSMatrix *startupOptionMatrix;
}
- (IBAction)slideshow:(id)sender;
- (IBAction)displayDir:(id)sender;
- (IBAction)openSelectedFiles:(id)sender;
- (IBAction)revealSelectedFilesInFinder:(id)sender;
- (IBAction)setRecurseSubfolders:(id)sender;
- (IBAction)setDesktopPicture:(id)sender;
// prefs stuff
- (IBAction)openPrefWin:(id)sender;
- (IBAction)chooseStartupDir:(id)sender;
- (IBAction)changeStartupOption:(id)sender;

- (IBAction)openAboutPanel:(id)sender;
@end
