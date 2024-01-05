//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

@import Cocoa;
#import "DYImageView.h"
#import "DYImageCache.h"

@interface SlideshowWindow : NSWindow
@property (nonatomic) BOOL fullscreenMode;

- (void)setCats:(NSMutableSet * __strong *)newCats;

- (void)setFilenames:(NSArray *)files basePath:(NSString *)s comparator:(NSComparator)block; // call this before starting the slideshow
- (void)setFilenames:(NSArray *)files basePath:(NSString *)s wantsSubfolders:(BOOL)b comparator:(NSComparator)block; // or this version to watch the directory and update with directory changes during slideshow
- (void)loadFilenamesFromPath:(NSString *)s wantsSubfolders:(BOOL)b comparator:(NSComparator)block;
- (void)startSlideshow;
- (void)startSlideshowAtIndex:(NSUInteger)n;
- (void)endSlideshow;
- (void)resetScreen;

@property (nonatomic, readonly) NSUInteger currentIndex;
@property (nonatomic, readonly) NSString *currentFile;
@property (nonatomic, readonly) NSString *basePath;
@property (nonatomic, readonly) unsigned short currentOrientation; // returns an EXIF orientation
@property (nonatomic, readonly) unsigned short currentFileExifOrientation;
- (void)displayImage; // to reload current file, assuming the mod date is different (oops - don't use this anymore)
- (void)redisplayImage; // to force reload of current file, regardless of mod date
@property (nonatomic, readonly) BOOL currentImageLoaded;
- (void)removeImageForFile:(NSString *)s; // use this if something's been deleted
- (void)insertFile:(NSString *)s atIndex:(NSUInteger)idx; // use this to undo a deletion
- (void)filesWereUndeleted:(NSArray *)a;
- (void)uncacheImage:(NSString *)s; // when an image is modified, remove it from cache

@property (nonatomic) BOOL rerandomizeOnLoop;
@property (nonatomic) BOOL autoRotate;
@property (nonatomic) NSTimeInterval autoadvanceTime;
- (void)updateTimer;

// menu methods
- (IBAction)endSlideshow:(id)sender;
- (IBAction)toggleLoopMode:(id)sender;
- (IBAction)toggleCheatSheet:(id)sender;
- (IBAction)toggleScalesUp:(id)sender;
- (IBAction)toggleShowActualSize:(id)sender;
- (IBAction)toggleRandom:(id)sender;

@end
