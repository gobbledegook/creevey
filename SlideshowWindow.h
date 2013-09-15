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


// returns path if it's not an alias, or if not resolvable
NSString *ResolveAliasToPath(NSString *path);

@interface SlideshowWindow : NSWindow
{
    DYImageView *imgView;
	NSTextField *infoFld; BOOL hideInfoFld;
	
	DYImageCache *imgCache;
	
	NSTimeInterval timerIntvl;
	NSTimer *autoTimer;
	
	NSMutableArray *filenames;
	NSMutableDictionary *rotations;
	
	NSString *basePath;
	NSRect screenRect;
	int currentIndex;
	
	NSTextView *helpFld;
	
	BOOL loopMode;
	unsigned char keyIsRepeating;
}

- (void)setFilenames:(NSArray *)files; // call this before starting the slideshow
- (void)setBasePath:(NSString *)s;
- (void)startSlideshow;
- (void)startSlideshowAtIndex:(int)n;
- (void)endSlideshow;
- (void)sendToBackground;
- (void)bringToForeground;

- (BOOL)isActive; // ** why doesn't isKeyWindow work?
- (NSString *)currentFile;
- (BOOL)currentImageLoaded;
- (void)removeImageForFile:(NSString *)s;

// cache methods
- (NSImage *)loadFromCache:(NSString *)s;
- (void)cacheAndDisplay:(NSString *)s;

// menu methods
- (IBAction)endSlideshow:(id)sender;
- (IBAction)toggleLoopMode:(id)sender;
- (IBAction)toggleCheatSheet:(id)sender;

// private methods
- (void)displayImage;
- (void)jump:(int)n;
- (void)jumpTo:(int)n;
- (void)setTimer:(NSTimeInterval)s;
- (void)runTimer;
- (void)killTimer;

@end
