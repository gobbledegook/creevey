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
	NSTextField *infoFld, *catsFld; BOOL hideInfoFld, moreExif;
	NSTextView *exifFld;
//	int blurr;
	
	DYImageCache *imgCache;
	
	NSTimeInterval timerIntvl; BOOL timerPaused;
	NSTimer *autoTimer;
	
	NSMutableDictionary *rotations, *zooms, *flips;
	
	NSString *basePath;
	NSScreen *oldScreen;
	volatile NSUInteger currentIndex;
	NSUInteger lastIndex; // for outside access to last slide shown
	
	NSTextView *helpFld;
	NSImageView *loopImageView;
	
	BOOL loopMode, randomMode, rerandomizeOnLoop, autoRotate;
	unsigned char keyIsRepeating;
	
	BOOL mouseDragged;
}
@property (nonatomic) BOOL fullscreenMode;

- (void)setCats:(NSMutableSet **)newCats;

- (void)setFilenames:(NSArray *)files basePath:(NSString *)s comparator:(NSComparator)block; // call this before starting the slideshow
- (void)setFilenames:(NSArray *)files basePath:(NSString *)s wantsSubfolders:(BOOL)b comparator:(NSComparator)block; // or this version to watch the directory and update with directory changes during slideshow
- (void)startSlideshow;
- (void)startSlideshowAtIndex:(NSUInteger)n;
- (void)endSlideshow;
- (void)resetScreen;

- (void)setAutoadvanceTime:(NSTimeInterval)s; // 0 to turn off

- (NSUInteger)currentIndex;
- (NSString *)currentFile;
- (NSString *)basePath;
- (unsigned short)currentOrientation; // returns an EXIF orientation
- (unsigned short)currentFileExifOrientation;
- (void)displayImage; // to reload current file, assuming the mod date is different (oops - don't use this anymore)
- (void)redisplayImage; // to force reload of current file, regardless of mod date
- (BOOL)currentImageLoaded;
- (void)removeImageForFile:(NSString *)s; // use this if something's been deleted
- (void)insertFile:(NSString *)s atIndex:(NSUInteger)idx; // use this to undo a deletion
- (void)filesWereUndeleted:(NSArray *)a;
- (void)uncacheImage:(NSString *)s; // when an image is modified, remove it from cache

- (void)setRerandomizeOnLoop:(BOOL)b;
- (void)setAutoRotate:(BOOL)b;
- (BOOL)autoRotate;

// menu methods
- (IBAction)endSlideshow:(id)sender;
- (IBAction)toggleLoopMode:(id)sender;
- (IBAction)toggleCheatSheet:(id)sender;
- (IBAction)toggleScalesUp:(id)sender;
- (IBAction)toggleShowActualSize:(id)sender;
- (IBAction)toggleRandom:(id)sender;

@end
