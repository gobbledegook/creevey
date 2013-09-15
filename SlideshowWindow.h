//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

/* SlideshowWindow
 * give it a list of images
 * a full screen window pops up
 * remember to hide it when the app becomes inactive!
 */

#import <Cocoa/Cocoa.h>
#import "DYImageView.h"
#import "DYImageCache.h"

@interface SlideshowWindow : NSWindow
{
	NSMutableSet **cats;
    DYImageView *imgView;
	NSTextField *infoFld, *catsFld; BOOL hideInfoFld;
	
	DYImageCache *imgCache;
	
	NSTimeInterval timerIntvl; BOOL timerPaused;
	NSTimer *autoTimer;
	
	NSMutableArray *filenames;
	NSMutableDictionary *rotations;
	
	NSString *basePath;
	NSRect screenRect;
	int currentIndex;
	
	NSTextView *helpFld;
	
	BOOL loopMode, randomMode;
	unsigned char keyIsRepeating;
}

- (void)setCats:(NSMutableSet **)newCats;

- (void)setFilenames:(NSArray *)files; // call this before starting the slideshow
- (void)setBasePath:(NSString *)s;
- (void)startSlideshow;
- (void)startSlideshowAtIndex:(int)n;
- (void)endSlideshow;
- (void)sendToBackground;
- (void)bringToForeground;

- (NSString *)currentFile;
- (void)displayImage; // to reload current file, assuming the mod date is different
- (BOOL)currentImageLoaded;
- (void)removeImageForFile:(NSString *)s;

// menu methods
- (IBAction)endSlideshow:(id)sender;
- (IBAction)toggleLoopMode:(id)sender;
- (IBAction)toggleCheatSheet:(id)sender;
- (IBAction)toggleScalesUp:(id)sender;
- (IBAction)toggleRandom:(id)sender;

@end
