//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "DYJpegtran.h"
#import "DYExiftags.h"

#import "SlideshowWindow.h"
#import "DYCarbonGoodies.h"
#import "CreeveyController.h"
#import "DYRandomizableArray.h"
#import "DYFileWatcher.h"
#import "NSMutableArray+DYMovable.h"

static BOOL UsingMagicMouse(NSEvent *e) {
	return e.phase != NSEventPhaseNone || e.momentumPhase != NSEventPhaseNone;
}

@interface SlideshowWindow () <DYFileWatcherDelegate>
@property (nonatomic, copy) NSComparator comparator;

- (void)jump:(NSInteger)n;
- (void)jumpTo:(NSUInteger)n;
- (void)setTimer:(NSTimeInterval)s;
- (void)runTimer;
- (void)killTimer;
- (void)updateInfoFld;
- (void)updateExifFld;

- (void)saveZoomInfo;

// cat methods
- (void)displayCats;
- (void)assignCat:(short int)n toggle:(BOOL)toggle;

// cache methods
- (NSImage *)loadFromCache:(NSString *)s;
- (void)cacheAndDisplay:(NSString *)s;
@end

@implementation SlideshowWindow
{
	NSMutableSet * __strong *cats;
	DYImageView *imgView;
	NSTextField *infoFld, *catsFld; BOOL hideInfoFld, moreExif;
	NSTextView *exifFld;
	
	DYImageCache *imgCache;
	
	BOOL timerPaused;
	NSTimer *autoTimer;
	
	NSMutableDictionary *rotations, *zooms, *flips;
	
	NSString *basePath;
	NSScreen *oldScreen;
	NSUInteger currentIndex;
	NSUInteger lastIndex; // for outside access to last slide shown
	
	NSTextView *helpFld;
	NSImageView *loopImageView;
	
	BOOL loopMode, randomMode;
	unsigned char keyIsRepeating;
	
	BOOL mouseDragged;

	DYRandomizableArray<NSString *> *filenames;
	NSOperationQueue *_upcomingQueue;
	DYFileWatcher *_fileWatcher;

	_Atomic BOOL _stopLoading;
}
@synthesize rerandomizeOnLoop, autoRotate, autoadvanceTime = timerIntvl;

+ (void)initialize {
	if (self != [SlideshowWindow class]) return;
	[NSUserDefaults.standardUserDefaults registerDefaults:@{@"DYSlideshowWindowVisibleFields": @0}];
}

#define MAX_CACHED 15
// MAX_CACHED must be bigger than the number of items you plan to have cached!
#define MAX_REPEATING_CACHED 6
// when key is held down, max to cache before skipping over

- (instancetype)initWithContentRect:(NSRect)r styleMask:(NSWindowStyleMask)m backing:(NSBackingStoreType)b defer:(BOOL)d {
	// full screen window, force it to be NSBorderlessWindowMask
	if (self = [super initWithContentRect:r styleMask:NSWindowStyleMaskBorderless backing:b defer:d]) {
		filenames = [[DYRandomizableArray alloc] init];
		rotations = [[NSMutableDictionary alloc] init];
		flips = [[NSMutableDictionary alloc] init];
		zooms = [[NSMutableDictionary alloc] init];
		imgCache = [[DYImageCache alloc] initWithCapacity:MAX_CACHED];
		imgCache.rotatable = YES;
		_upcomingQueue = [[NSOperationQueue alloc] init];
		_fileWatcher = [[DYFileWatcher alloc] initWithDelegate:self];
		
 		self.backgroundColor = NSColor.blackColor;
		self.opaque = NO;
		_fullscreenMode = YES; // set this to prevent autosaving the frame from the nib
		self.collectionBehavior = NSWindowCollectionBehaviorParticipatesInCycle|NSWindowCollectionBehaviorFullScreenNone;
		// *** Unfortunately the menubar doesn't seem to show up on the second screen... Eventually we'll want to switch to use NSView's enterFullScreenMode:withOptions:
		currentIndex = NSNotFound;
   }
    return self;
}

- (void)awakeFromNib {
	imgView = [[DYImageView alloc] initWithFrame:NSZeroRect];
	[self.contentView addSubview:imgView];
	imgView.frame = self.contentView.frame;
	imgView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	
	infoFld = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,360,20)];
	[imgView addSubview:infoFld];
	infoFld.autoresizingMask = NSViewMaxXMargin|NSViewMaxYMargin;
	infoFld.backgroundColor = NSColor.grayColor;
	infoFld.bezeled = NO;
	infoFld.editable = NO;
	
	catsFld = [[NSTextField alloc] initWithFrame:NSMakeRect(0,imgView.bounds.size.height-20,300,20)];
	[imgView addSubview:catsFld];
	catsFld.autoresizingMask = NSViewMaxXMargin|NSViewMinYMargin;
	catsFld.backgroundColor = NSColor.grayColor;
	catsFld.bezeled = NO;
	catsFld.editable = NO; // **
	catsFld.hidden = YES;
	
	NSSize s = imgView.bounds.size;
	NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(s.width-360,0,360,s.height-20)];
	[imgView addSubview:sv];
	sv.autoresizingMask = NSViewHeightSizable | NSViewMinXMargin;
	
	exifFld = [[NSTextView alloc] initWithFrame:NSMakeRect(0,0,sv.contentSize.width,20)];
	sv.documentView = exifFld;
	exifFld.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable | NSViewMinXMargin;

	sv.drawsBackground = NO;
	sv.hasVerticalScroller = YES;
	sv.verticalScroller = [[NSScroller alloc] init];
	sv.verticalScroller.controlSize = NSControlSizeSmall;
	sv.autohidesScrollers = YES;
	//[exifFld setEditable:NO];
	exifFld.drawsBackground = NO;
	exifFld.selectable = NO;
	//[exifFld setVerticallyResizable:NO];
	sv.hidden = YES;
	
	switch ([NSUserDefaults.standardUserDefaults integerForKey:@"DYSlideshowWindowVisibleFields"]) {
		case 0:
			hideInfoFld = YES;
			break;
		case 2:
			sv.hidden = NO;
			break;
		default:
			break;
	}
}

- (void)setFullscreenMode:(BOOL)b {
	_fullscreenMode = b;
	if (b) {
		self.styleMask = NSWindowStyleMaskBorderless;
		self.collectionBehavior = NSWindowCollectionBehaviorParticipatesInCycle|NSWindowCollectionBehaviorFullScreenNone;
	} else {
		self.styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable;
		self.collectionBehavior = NSWindowCollectionBehaviorParticipatesInCycle|NSWindowCollectionBehaviorFullScreenNone;
	}
	if (self.visible)
		[self configureScreen];
}

- (void)setAutoRotate:(BOOL)b {
	autoRotate = b;
	[rotations removeAllObjects];
	[flips removeAllObjects];
	if (currentIndex != NSNotFound) {
		[self displayImage];
	}
}

- (void)setCats:(NSMutableSet * __strong *)newCats {
    cats = newCats;
}

// must override this for borderless windows
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }

#pragma mark start/end stuff
- (void)setFilenames:(NSArray *)files basePath:(NSString *)s wantsSubfolders:(BOOL)b comparator:(NSComparator)block {
	[self setFilenames:files basePath:s comparator:block];
	_fileWatcher.wantsSubfolders = b;
	[_fileWatcher watchDirectory:s];
}

- (void)setFilenames:(NSArray *)files basePath:(NSString *)s comparator:(NSComparator)block {
	if (currentIndex != NSNotFound)
		[self cleanUp];
	
	if (s != basePath) {
		if ([s characterAtIndex:s.length-1] != '/')
			basePath = [s stringByAppendingString:@"/"];
		else
			basePath = [s copy];
	}
	[filenames setArray:files];
	self.comparator = block;
}

- (void)loadFilenamesFromPath:(NSString *)s fullScreen:(BOOL)fullScreen wantsSubfolders:(BOOL)b comparator:(NSComparator)block {
	static dispatch_queue_t _loadQueue;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		_loadQueue = dispatch_queue_create("phoenixslides.slideshow.load", NULL);
	});
	self.fullscreenMode = fullScreen;
	[self configureScreen];
	currentIndex = NSNotFound;
	imgView.image = nil;
	infoFld.hidden = NO;
	dispatch_async(dispatch_get_main_queue(), ^{
		[self makeKeyAndOrderFront:nil];
	});
	self.comparator = block;
	_stopLoading = YES;
	static _Atomic uint64_t blockTime;
	uint64_t timeStamp = blockTime = mach_absolute_time();
	dispatch_async(_loadQueue, ^{
		if (timeStamp == blockTime)
			[self loadImages:s subfolders:b];
	});
}

- (NSString *)currentShortFilename {
	NSString *s = filenames[currentIndex];
	return s.length <= basePath.length ? s : [s substringFromIndex:basePath.length];
}

- (void)configureScreen
{
	NSScreen *myScreen = self.visible ? self.screen : NSScreen.mainScreen;
	NSRect screenRect = myScreen.frame;
	NSRect boundingRect = screenRect;
	if (@available(macOS 12.0, *)) {
		CGFloat inset = myScreen.safeAreaInsets.top;
		if (inset) {
			boundingRect.size.height -= inset;
		}
	}
	oldScreen = myScreen;
	NSSize oldSize = imgCache.boundingSize;
	if (oldSize.width < boundingRect.size.width
		|| oldSize.height < boundingRect.size.height) {
		[imgCache removeAllImages];
	}
	imgCache.boundingSize = boundingRect.size;
	if (_fullscreenMode) {
		[self setFrame:screenRect display:NO];
		boundingRect.origin = imgView.frame.origin;
		imgView.frame = boundingRect;
	} else {
		NSString *v = [NSUserDefaults.standardUserDefaults objectForKey:@"DYSlideshowWindowFrame"];
		NSRect r;
		if (v) {
			r = NSRectFromString(v);
		} else {
			r = screenRect;
			r.size.width = r.size.width/2;
			r.size.height = r.size.height/2;
			r.origin.y = screenRect.size.height;
		}
		[self setFrame:r display:NO];
		imgView.frame = self.contentLayoutRect;
	}
}

- (void)resetScreen
{
	if ([oldScreen.deviceDescription[@"NSScreenNumber"] isNotEqualTo:self.screen.deviceDescription[@"NSScreenNumber"]]) {
		[self configureScreen];
		[self displayImage];
	}
}

- (void)cleanUp {
	[_fileWatcher stop];
	lastIndex = currentIndex;
	if (currentIndex != NSNotFound) {
		[self saveZoomInfo];
		currentIndex = NSNotFound;
	}
	_stopLoading = YES;
	[self killTimer];
	[imgCache abortCaching];
	[self.undoManager removeAllActions];

	// this is a half-hearted attempt to clean up. Really we just rely on the countLimit on the cache
	NSUInteger n = MIN(filenames.count, MAX_CACHED);
	for (NSUInteger i=0; i<n; ++i) {
		[imgCache endAccess:filenames[i]];
	}
}

- (void)endSlideshow {
	[self orderOut:nil];
}

- (void)orderOut:(id)sender {
	[self cleanUp];
	if (!_fullscreenMode)
		[NSUserDefaults.standardUserDefaults setObject:NSStringFromRect(self.frame) forKey:@"DYSlideshowWindowFrame"];
	[super orderOut:sender];
}

- (void)startSlideshow {
	[self startSlideshowAtIndex:NSNotFound]; // to distinguish from 0, for random mode
}
- (void)startSlideshowAtIndex:(NSUInteger)startIndex {
	if (filenames.count == 0) {
		NSBeep();
		return;
	}
	
	if (!self.visible) {
		[self configureScreen];
	}
	
	if (randomMode) {
		[filenames randomizeStartingWithObjectAtIndex:startIndex];
		startIndex = 0;
	} else {
		if (startIndex == NSNotFound) startIndex = 0;
	}
	currentIndex = startIndex;
	[self setTimer:timerIntvl]; // reset the timer, in case running
	if (helpFld) helpFld.hidden = YES;
	exifFld.string = @"";
	[imgCache beginCaching];
	imgView.image = nil;
	[self displayImage];
	[self makeKeyAndOrderFront:nil];

	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	BOOL seenIntro = [u boolForKey:@"seenSlideshowIntro"];
	if (!seenIntro) {
		NSAlert *alert = [[NSAlert alloc] init];
		alert.messageText = NSLocalizedString(@"Welcome to Phoenix Slides!",@"");
		alert.informativeText = NSLocalizedString(@"Hit the 'h' key to see a list of keyboard shortcuts you can use during the slideshow.",@"");
		[alert addButtonWithTitle:NSLocalizedString(@"Got It!", @"welcome alert button 1")];
		[alert addButtonWithTitle:NSLocalizedString(@"Show Me", @"welcome alert button 2")];
		if ([alert runModal] == NSAlertSecondButtonReturn)
			[self toggleHelp];
		[u setBool:YES forKey:@"seenSlideshowIntro"];
	}

	// ordering front seems to reset the cursor, so force it again
	[imgView setCursor];
}

- (void)becomeMainWindow { // need this when switching apps
	if (_fullscreenMode)
		NSApp.presentationOptions = NSApplicationPresentationHideDock|NSApplicationPresentationAutoHideMenuBar;
	[super becomeMainWindow];
}

- (void)resignMainWindow {
	if (_fullscreenMode)
		NSApp.presentationOptions = NSApplicationPresentationDefault;
	[super resignMainWindow];
}

- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen
{
	// As of 10.15.1(?) when the menubar hides, the window will get moved up by the height of the menubar.
	// This should be the correct fix for that.
	if (_fullscreenMode)
		return [super constrainFrameRect:self.screen.frame toScreen:screen];
	return [super constrainFrameRect:frameRect toScreen:screen];
}

- (void)watcherFiles:(NSArray *)files {
	if (currentIndex == NSNotFound) return;
	NSFileManager *fm = NSFileManager.defaultManager;
	BOOL needUpdate = NO;
	for (NSString *s in files) {
		BOOL fileExists = [fm fileExistsAtPath:s];
		if (currentIndex < filenames.count && [filenames[currentIndex] isEqualToString:s]) {
			if (fileExists)
				[self redisplayImage];
			else
				[self removeImageForFile:s atIndex:currentIndex];
			continue;
		}
		NSUInteger insertIdx;
		NSUInteger idx = [filenames indexOfObject:s usingComparator:self.comparator insertIndex:&insertIdx];
		if (idx == NSNotFound) {
			if (fileExists) {
				[filenames insertObject:s usingOrderedIndex:insertIdx atIndex:filenames.count]; // appends to end if in random mode
				if (!randomMode && insertIdx <= currentIndex) {
					currentIndex++;
				}
				needUpdate = YES;
			}
		} else {
			if (!fileExists)
				[self removeImageForFile:s atIndex:idx];
		}
	}
	if (needUpdate)
		[self updateForAddedFiles];
}

- (void)watcherRootChanged:(NSURL *)fileRef {
	NSString *s = _fileWatcher.path, *newPath = fileRef.path;
	if (newPath == nil) {
		// directory no longer exists!
		dispatch_async(dispatch_get_main_queue(), ^{
			[self endSlideshow];
		});
		return;
	}
	basePath = newPath.length == 1 ? newPath : [newPath stringByAppendingString:@"/"];
	[filenames changeBase:s toPath:newPath];
}

#pragma mark timer stuff
// setTimer
// sets the interval between slide show advancing.
// set to 0 to stop.
- (void)setTimer:(NSTimeInterval)s {
	timerIntvl = s;
	[self updateTimer];
}

- (void)updateTimer {
	if (timerIntvl > 0.0)
		[self runTimer];
	else
		[self killTimer];
}

- (void)runTimer {
	[self killTimer]; // always remove the old timer
	if (loopMode || currentIndex+1 < filenames.count) {
		//NSLog(@"scheduling timer from %d", currentIndex);
		autoTimer = [NSTimer
scheduledTimerWithTimeInterval:timerIntvl
						target:self
					  selector:@selector(nextTimer:)
					  userInfo:nil repeats:NO];
		autoTimer.tolerance = 0.2;
	}
}

- (void)killTimer {
	[autoTimer invalidate]; autoTimer = nil;
}

- (void)pauseTimer {
	[self killTimer];
	timerPaused = YES;
	if (hideInfoFld) infoFld.hidden = NO;
	[self updateInfoFld];
}

- (void)nextTimer:(NSTimer *)t {
	//NSLog(@"timer fired!");
	autoTimer = nil; // so another thread won't send a message to a stale timer obj
	[self jump:1]; // works with loop mode
}

#pragma mark display stuff
- (float)calcZoom:(NSSize)sourceSize {
	// calc here b/c larger images have already been cached & shrunk!
	NSRect boundsRect = [imgView convertRect:imgView.bounds toView:nil]; // get pixels, not points
	int rotation = imgView.rotation;
	float tmp;
	if (rotation == 90 || rotation == -90) {
		tmp = boundsRect.size.width;
		boundsRect.size.width = boundsRect.size.height;
		boundsRect.size.height = tmp;
	}
	
	if (!imgView.scalesUp
		&& sourceSize.width <= boundsRect.size.width
		&& sourceSize.height <= boundsRect.size.height)
	{
		return 1;
	} else {
		float w_ratio, h_ratio;
		w_ratio = boundsRect.size.width/sourceSize.width;
		h_ratio = boundsRect.size.height/sourceSize.height;
		return w_ratio < h_ratio ? w_ratio : h_ratio;
	}
}

- (void)updateExifFld {
	if (currentIndex >= filenames.count) return;
	NSMutableAttributedString *attStr;
	attStr = Fileinfo2EXIFString(filenames[currentIndex],
								 imgCache,moreExif);
	NSRange r = NSMakeRange(0,attStr.length);
	NSShadow *shdw = [[NSShadow alloc] init];
	shdw.shadowColor = NSColor.blackColor;
	shdw.shadowBlurRadius = 7; // 7 or 8 is good
	[attStr addAttribute:NSShadowAttributeName
				   value:shdw
				   range:r];
	[exifFld replaceCharactersInRange:NSMakeRange(0,exifFld.string.length)
							  withRTF:[attStr RTFFromRange:NSMakeRange(0,attStr.length)
										documentAttributes:@{}]];
	exifFld.textColor = NSColor.whiteColor;
}


- (void)updateInfoFldWithRotation:(int)r {
	DYImageInfo *info = [imgCache infoForKey:filenames[currentIndex]];
	if (info == nil) {
		// avoid crash if user tries to rotate before the image has loaded
		return;
	}
	id dir;
	switch (r) {
		case 90: dir = NSLocalizedString(@" left", @""); break;
		case -90: dir = NSLocalizedString(@" right", @""); break;
		default: dir = @"";
	}
	if (r < 0) r = -r;
	float zoom = imgView.zoomMode ? imgView.zoomF : [self calcZoom:info->pixelSize];
	infoFld.stringValue = [NSString stringWithFormat:@"[%lu/%lu] %@ - %@ - %@%@%@%@ %@",
		currentIndex+1, (unsigned long)filenames.count,
		[self currentShortFilename],
		FileSize2String(info->fileSize),
		info.pixelSizeAsString,
		(zoom != 1.0 || imgView.zoomMode) ? [NSString stringWithFormat:
			@" @ %.0f%%", zoom*100] : @"",
						   imgView.imageFlipped ? NSLocalizedString(@" flipped", @"") : @"",
		r ? [NSString stringWithFormat:
			NSLocalizedString(@" rotated%@ %i%C", @""), dir, r, 0xb0] : @"", //degrees
		timerIntvl && timerPaused ? [NSString stringWithFormat:@" %@(%.1f%@) %@",
			NSLocalizedString(@"Auto-advance", @""),
			timerIntvl,
			NSLocalizedString(@"seconds", @""),
			NSLocalizedString(@"PAUSED", @"")]
								  : @""];
	[infoFld sizeToFit];
}

- (void)updateInfoFld {
	[self updateInfoFldWithRotation:imgView.rotation];
}

- (void)redisplayImage {
	if (currentIndex == NSNotFound) return;
	NSString *theFile = filenames[currentIndex];
	[zooms removeObjectForKey:theFile]; // don't forget to reset the zoom/rotation!
	[rotations removeObjectForKey:theFile];
	[flips removeObjectForKey:theFile];
	[self displayImage];
}

- (void)uncacheImage:(NSString *)s {
	[imgCache removeImageForKey:s];
	[zooms removeObjectForKey:s];
	[rotations removeObjectForKey:s];
	[flips removeObjectForKey:s];
	if ((currentIndex != NSNotFound && currentIndex != filenames.count) && [s isEqualToString:filenames[currentIndex]])
		[self displayImage];
}

- (void)displayImage {
	if (currentIndex == NSNotFound) return; // in case called after slideshow ended
									// not necessary if s/isActive/isKeyWindow/
	if (currentIndex == filenames.count) { // if the last image was deleted, show a blank screen
		catsFld.hidden = YES;
		infoFld.hidden = NO;
		infoFld.stringValue = NSLocalizedString(@"End of slideshow (last file was deleted)", @"");
		[infoFld sizeToFit];
		exifFld.string = @"";
		imgView.image = nil;
		return;
	}
	NSString *theFile = filenames[currentIndex];
	NSImage *img = [self loadFromCache:theFile];
	[self displayCats];
	if (img) {
		NSNumber *rot = rotations[theFile];
		DYImageViewZoomInfo *zoomInfo = zooms[theFile];
		int r = rot ? rot.intValue : 0;
		BOOL imgFlipped = [flips[theFile] boolValue];
		
		if (hideInfoFld) infoFld.hidden = YES; // this must happen before setImage, for redraw purposes
		imgView.image = img;
		if (r) imgView.rotation = r;
		if (imgFlipped) imgView.imageFlipped = YES;
		// ** see keyDown for specifics
		// if zoomed in, we need to set a different image
		// here, copy-pasted from keyDown
		DYImageInfo *info = [imgCache infoForKey:filenames[currentIndex]];
		if (autoRotate && !rot && !imgFlipped && info->exifOrientation) {
			// auto-rotate by exif orientation
			exiforientation_to_components(info->exifOrientation, &r, &imgFlipped);
			rotations[theFile] = @(r);
			flips[theFile] = @(imgFlipped);
			imgView.rotation = r;
			imgView.imageFlipped = imgFlipped;
		}
		if ((zoomInfo || imgView.showActualSize) && !NSEqualSizes(info->pixelSize, info.image.size)) {
			[imgView setImage:[info loadFullSizeImage]
					  zooming:zoomInfo ? DYImageViewZoomModeManual : DYImageViewZoomModeActualSize];
			if (zoomInfo) imgView.zoomInfo = zoomInfo;
		} else if (zoomInfo) {
			imgView.zoomInfo = zoomInfo;
		}
		[self updateInfoFldWithRotation:r];
		if (!exifFld.enclosingScrollView.hidden) [self updateExifFld];
		if (timerIntvl) [self runTimer];
	} else {
		if (hideInfoFld) infoFld.hidden = NO;
		infoFld.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Loading [%i/%i] %@...", @""),
			(unsigned int)currentIndex+1, (unsigned int)filenames.count, [self currentShortFilename]];
		[infoFld sizeToFit];
		return;
	}
	if (keyIsRepeating) return; // don't bother precaching if we're fast-forwarding anyway

	if (self.isMainWindow && !imgView.dragMode)
		[NSCursor setHiddenUntilMouseMoves:YES];

	if (imgView.showActualSize) return; // don't bother caching scaled down images if user wants full size images
	short int i;
	for (i=1; i<=2; i++) {
		if (currentIndex+i >= filenames.count)
			break;
		[_upcomingQueue addOperationWithBlock:^{
			[imgCache cacheFile:filenames[currentIndex+i]];
		}];
	}
}

- (void)showLoopAnimation {
	if (!loopImageView) {
		NSImage *loopImage = [NSImage imageNamed:@"loop_forward.tiff"];
		NSSize s = loopImage.size;
		NSRect r;
		r.size = s;
		s = self.contentView.frame.size;
		r.origin.x = (s.width - r.size.width)/2;
		r.origin.y = (s.height - r.size.height)/2;

		loopImageView = [[NSImageView alloc] initWithFrame:NSIntegralRect(r)];
		[self.contentView addSubview:loopImageView];
		loopImageView.image = loopImage;
	}
	loopImageView.hidden = NO;

	NSDictionary *viewDict = @{ NSViewAnimationTargetKey: loopImageView, NSViewAnimationEffectKey: NSViewAnimationFadeOutEffect };
    NSViewAnimation *theAnim = [[NSViewAnimation alloc] initWithViewAnimations:@[viewDict]];
	theAnim.duration = 0.9;
    theAnim.animationCurve = NSAnimationEaseIn;

    [theAnim startAnimation];
}

- (void)jump:(NSInteger)n { // go forward n pics (negative numbers go backwards)
	if (n < 0)
		[self setTimer:0]; // going backwards stops auto-advance
	else // could get rid of 'else' b/c going backwards makes timerPaused irrelevant
		timerPaused = NO; // going forward unpauses auto-advance
	if ((n > 0 && currentIndex+1 >= filenames.count) || (n < 0 && currentIndex == 0)){
		if (loopMode) {
			if (randomMode && n > 0 && rerandomizeOnLoop) {
				// reshuffle whenever you loop through to the beginning
				[filenames randomize];
			}
			[self jumpTo:n<0 ? filenames.count-1 : 0];
			[self showLoopAnimation];
		} else {
			NSBeep();
		}
	} else {
		if (n < 0 && labs(n) > currentIndex) {
			n = -currentIndex;
		} else if (n > 0 && n >= filenames.count - currentIndex) {
			n = filenames.count - 1 - currentIndex;
		}
		[self jumpTo:currentIndex+n];
	}
}

- (void)jump:(int)n ordered:(BOOL)ordered { // if ordered is YES, jump to the next/previous slide in the ordered sequence
	if (ordered && randomMode) {
		[self setTimer:0]; // always stop auto-advance here
		if (currentIndex >= filenames.count) {
			// stop if we just deleted the last file
			NSBeep();
			return;
		}
		NSUInteger newIndex = n < 0 ? [filenames orderedIndexOfObjectBeforeIndex:currentIndex] : [filenames orderedIndexOfObjectAfterIndex:currentIndex];
		if (newIndex == NSNotFound) {
			NSBeep();
			return;
		}
		[self jumpTo:newIndex];
	} else {
		[self jump:n];
	}
}

- (void)jumpTo:(NSUInteger)n {
	//NSLog(@"jumping to %d", n);
	[self killTimer];
	// we rely on this only being called when changing pics, not at startup
	[self saveZoomInfo];
	// above code is repeated in endSlideshow, setBasePath
	
	currentIndex = n >= filenames.count ? filenames.count - 1 : n;
	[self displayImage];
}

- (void)saveZoomInfo {
	if (currentIndex >= filenames.count) return;
	if (imgView.zoomInfoNeedsSaving)
		zooms[filenames[currentIndex]] = imgView.zoomInfo;
}

- (void)setRotation:(int)n {
	n = [imgView addRotation:n];
	rotations[filenames[currentIndex]] = @(n);
	[self updateInfoFldWithRotation:n];
}

- (void)toggleFlip {
	BOOL b = [imgView toggleFlip];
	NSString *s = filenames[currentIndex];
	flips[s] = @(b);

	// also update the rotation to match, since flipping will reverse it
	int r = [rotations[s] intValue];
	if (r == 90 || r == -90)
		rotations[s] = @(-r);
	
	[self updateInfoFld];
}

- (void)toggleExif {
	exifFld.enclosingScrollView.hidden = !exifFld.enclosingScrollView.hidden;
	if (!exifFld.enclosingScrollView.hidden)
		[self updateExifFld];
}

- (void)toggleHelp {
	if (!helpFld) {
		helpFld = [[NSTextView alloc] initWithFrame:NSZeroRect];
		[self.contentView addSubview:helpFld];
		if (![helpFld readRTFDFromFile:
			[NSBundle.mainBundle pathForResource:@"creeveyhelp" ofType:@"rtf"]])
			NSLog(@"couldn't load cheat sheet!");
		helpFld.backgroundColor = NSColor.lightGrayColor;
		helpFld.selectable = NO;
//		NSLayoutManager *lm = [helpFld layoutManager];
//		NSRange rnge = [lm glyphRangeForCharacterRange:NSMakeRange(0,[[helpFld textStorage] length])
//								  actualCharacterRange:NULL];
//		NSSize s = [lm boundingRectForGlyphRange:rnge
//								 inTextContainer:[lm textContainerForGlyphAtIndex:0
//																   effectiveRange:NULL]].size;
//			//[[helpFld textStorage] size];
//		NSLog(NSStringFromRange(rnge));
		NSSize s = [helpFld.textStorage size];
		NSRect r = NSMakeRect(0,0,s.width+10,s.height);
		// width must be bigger than text, or wrappage will occur
		s = self.contentView.frame.size;
		r.origin.x = s.width - r.size.width - 50;
		r.origin.y = s.height - r.size.height - 55;
		helpFld.frame = NSIntegralRect(r);
		helpFld.autoresizingMask = NSViewMinXMargin|NSViewMinYMargin;
		return;
	}
	helpFld.hidden = !helpFld.hidden;
}

#pragma mark event stuff
// Here's the bulk of our user interface, all keypresses
- (void)keyUp:(NSEvent *)e {
	if (keyIsRepeating) {
		keyIsRepeating = 0;
		switch ([e.characters characterAtIndex:0]) {
			case ' ':
			case NSRightArrowFunctionKey:
			case NSDownArrowFunctionKey:
			case NSLeftArrowFunctionKey:
			case NSUpArrowFunctionKey:
			case NSPageUpFunctionKey:
			case NSPageDownFunctionKey:
				[self displayImage];
				break;
			default:
				break;
		}
	}
}
- (void)keyDown:(NSEvent *)e {
	if (e.characters.length == 0) return; // avoid exception on deadkeys
	unichar c = [e.characters characterAtIndex:0];
	if (currentIndex == NSNotFound) {
		// loading filenames
		switch(c) {
			case 'q':
			case '\x1b':
				[self endSlideshow];
				return;
			default:
				NSBeep();
				return;
		}
	}
	if (currentIndex == filenames.count) {
		switch(c) {
			case ' ': // only allow shift-space to go back
				if ((e.modifierFlags & NSEventModifierFlagShift) == 0) return;
				// fallthrough
			case NSLeftArrowFunctionKey:
			case NSUpArrowFunctionKey:
			case NSHomeFunctionKey:
			case NSEndFunctionKey:
			case NSPageUpFunctionKey:
			case 'q':
			case '\x1b': // escape
			case 'h':
			case '?':
			case '/':
				break;
			default:
				NSBeep();
				return;
		}
	}
	if (c >= '1' && c <= '9') {
		if ((e.modifierFlags & NSEventModifierFlagNumericPad) != 0 && imgView.zoomMode) {
			if (c == '5') {
				NSBeep();
			} else {
				char x,y;
				c -= '0';
				if (c<=3) y = 1; else if (c>=7) y = -1; else y = 0;
				if (c%3 == 0) x = -1; else if (c%3 == 1) x = 1; else x=0;
				[imgView fakeDragX:(imgView.bounds.size.width/2)*x
								 y:(imgView.bounds.size.height/2)*y];
			}
		} else {
			if (timerIntvl == 0 || timerPaused) [self jump:1];
			[self setTimer:c - '0'];
		}
		return;
	}
	if (c == '0') {
		[self setTimer:0];
		[self updateInfoFld];
		return;
	}
	if (c >= NSF1FunctionKey && c <= NSF12FunctionKey) {
		[self assignCat:c - NSF1FunctionKey + 1
				 toggle:(e.modifierFlags & NSEventModifierFlagCommand) != 0];
		//NSLog(@"got cat %i", c - NSF1FunctionKey + 1);
		return;
	}
	if (e.ARepeat && keyIsRepeating < MAX_REPEATING_CACHED) {
		keyIsRepeating++;
	}
	if (c == ' ' && ((e.modifierFlags & NSEventModifierFlagShift) != 0)) {
		c = NSLeftArrowFunctionKey;
	}
	DYImageInfo *obj;
	switch (c) {
		case '!':
			[self setTimer:0.5];
			break;
		case '@':
			[self setTimer:1.5];
			break;
		case ' ':
			if (timerIntvl && autoTimer) {
				//[self setTimer:0];
				[self pauseTimer];
				break; // pause slideshow only
			}
			// otherwise advance
		case NSRightArrowFunctionKey:
		case NSDownArrowFunctionKey:
			// hold down option to go to the next non-randomized slide
			[self jump:1 ordered:(e.modifierFlags & NSEventModifierFlagOption) != 0];
			break;
		case NSLeftArrowFunctionKey:
		case NSUpArrowFunctionKey:
			[self jump:-1 ordered:(e.modifierFlags & NSEventModifierFlagOption) != 0];
			break;
		case NSHomeFunctionKey:
			[self jump:-currentIndex]; // <0 stops auto-advance
			break;
		case NSEndFunctionKey:
			[self jumpTo:filenames.count-1];
			break;
		case NSPageUpFunctionKey:
			[self jump:-10];
			break;
		case NSPageDownFunctionKey:
			[self jump:10];
			break;
		case 'q':
		case '\x1b': // escape
			[self endSlideshow];
			break;
		case 'i':
			// cycles three ways: info, info + exif, none
			hideInfoFld = !infoFld.hidden && !exifFld.enclosingScrollView.hidden;
			if (!infoFld.hidden)
				[self toggleExif];
			infoFld.hidden = hideInfoFld; // 10.3 or later!
			{
				unsigned short infoFldVisible = 0;
				if (!exifFld.enclosingScrollView.hidden) {
					infoFldVisible = 2;
				} else if (!hideInfoFld) {
					infoFldVisible = 1;
				}
				[NSUserDefaults.standardUserDefaults setInteger:infoFldVisible forKey:@"DYSlideshowWindowVisibleFields"];
			}
			break;
		case 'h':
		case '?':
		case '/':
		case NSHelpFunctionKey: // doesn't work, trapped at a higher level?
			[self toggleHelp];
			break;
		case 'I':
			if (exifFld.enclosingScrollView.hidden) {
				moreExif = YES;
				hideInfoFld = NO;
				[self toggleExif];
				infoFld.hidden = NO;
			} else {
				moreExif = !moreExif;
				[self updateExifFld];
			}
			[NSUserDefaults.standardUserDefaults setInteger:2 forKey:@"DYSlideshowWindowVisibleFields"];
			break;
		case 'l':
			[self setRotation:90];
			break;
		case 'r':
			[self setRotation:-90];
			break;
		case 'f':
			[self toggleFlip];
			break;
		case '=':
			//if ([imgView showActualSize])
			//	[zooms removeObjectForKey:[filenames objectAtIndex:currentIndex]];
			// actually, '=' doesn't center the pic, so this is wrong
			// if you zoom or move a pic while in actualsize mode, you're basically stuck with a non-default zoom
			// intentional fall-through to next cases
		case '+':
		case '-':
			if ((obj = [imgCache infoForKey:filenames[currentIndex]])) {
				if (obj.image == imgView.image
					&& !NSEqualSizes(obj->pixelSize, obj.image.size)) { // cached image smaller than orig
					[imgView setImage:[obj loadFullSizeImage]
							  zooming:c == '=' ? DYImageViewZoomModeActualSize : c == '+' ? DYImageViewZoomModeZoomIn : DYImageViewZoomModeZoomOut];
				} else {
					if (c == '+') [imgView zoomIn];
					else if (c == '-') [imgView zoomOut];
					else [imgView zoomActualSize];
				}
				[self updateInfoFld];
			}
			// can't save zooms here, save when leaving the pict; see jumpTo
			// for important comments
			break;
		case '*':
			//[imgView zoomOff];
			//if (![imgView showActualSize])
			//	[zooms removeObjectForKey:[filenames objectAtIndex:currentIndex]];
			//[self updateInfoFld];
			[self redisplayImage]; // this resets zoom, rotate, and flip
			break;
		default:
			//NSLog(@"%x",c);
			[super keyDown:e];
	}
}

- (BOOL)performKeyEquivalent:(NSEvent *)e {
	unichar c = [e.characters characterAtIndex:0];
	//NSLog([e charactersIgnoringModifiers]);
	//NSLog([e characters]);
	// charactersIgnoringModifiers is 10.4 or later, and doesn't play well with Dvorak Qwerty-cmd
	DYImageInfo *obj;
	switch (c) {
		case '=':
			if (!(e.modifierFlags & NSEventModifierFlagNumericPad))
				c = '+';
			// intentional fall-through
		case '+':
		case '-':
			if (currentIndex >= filenames.count) { NSBeep(); return YES; }
			// ** code copied from keyDown
			if ((obj = [imgCache infoForKey:filenames[currentIndex]])) {
				if (obj.image == imgView.image
					&& !NSEqualSizes(obj->pixelSize, obj.image.size)) {  // cached image smaller than orig
					[imgView setImage:[obj loadFullSizeImage]
							  zooming:c == '=' ? DYImageViewZoomModeActualSize : c == '+' ? DYImageViewZoomModeZoomIn : DYImageViewZoomModeZoomOut];
				} else {
					if (c == '+') [imgView zoomIn];
					else if (c == '-') [imgView zoomOut];
					else [imgView zoomActualSize];
				}
				[self updateInfoFld];
			}
			return YES;
		default:
			return [super performKeyEquivalent:e];
	}
}


// mouse control added for 1.2.2 (2006 Aug)

- (void)mouseDown:(NSEvent *)e {
	if (imgView.dragMode)
		return;
	if (!NSPointInRect(e.locationInWindow, self.contentView.frame))
		return;
	
	mouseDragged = YES; // prevent the following mouseUp from advancing twice
	    // this would happen if it was zoomed in
	if (e.clickCount == 1)
		[self jump:1];
	else if (e.clickCount == 2)
		[self endSlideshow];
}

// while zoomed, wait until mouseUp to advance/end
- (void)mouseUp:(NSEvent *)e {
	if (!imgView.dragMode)
		return;
	if (mouseDragged)
		return;
	
	if (e.clickCount == 1)
		[self jump:1];
	else if (e.clickCount == 2)
		[self endSlideshow];
}

- (void)rightMouseDown:(NSEvent *)e {
	[self jump:-1];
}

- (void)sendEvent:(NSEvent *)e {
	NSEventType t = e.type;

	// override to send right clicks to self
	if (t == NSEventTypeRightMouseDown)	{
		[self rightMouseDown:e];
		return;
	}
	// but trapping help key here doesn't work

	if (t == NSEventTypeLeftMouseDragged) {
		mouseDragged = YES;
	} else if (t == NSEventTypeLeftMouseDown) {
		mouseDragged = NO; // reset this on mouseDown, not mouseUp (too early)
		// or wait til after call to super
	}
	[super sendEvent:e];
}

- (void)scrollWheel:(NSEvent *)e {
	if (UsingMagicMouse(e)) return;
	float y = e.deltaY;
	int sign = y < 0 ? 1 : -1;
	[self jump:sign*(floor(fabs(y)/7.0)+1)];
}

- (void)magnifyWithEvent:(NSEvent *)event
{
	if (currentIndex >= filenames.count) return;
	NSString *filename = filenames[currentIndex];
	DYImageInfo *info = [imgCache infoForKey:filename];
	if (info) {
		float zoom = imgView.zoomMode ? imgView.zoomF : [self calcZoom:info->pixelSize];
		if (info.image == imgView.image
			&& !NSEqualSizes(info->pixelSize, info.image.size)) { // cached image smaller than orig
			[imgView setImage:[info loadFullSizeImage]
					  zooming:DYImageViewZoomModeManual];
		}
		[imgView setZoomF:zoom * (1.0 + event.magnification)];
		[self updateInfoFld];
	}
}


#pragma mark cache stuff

- (NSImage *)loadFromCache:(NSString *)s {
	NSImage *img = [imgCache imageForKeyInvalidatingCacheIfNecessary:s];
	if (img)
		return img;
	//NSLog(@"%d not cached yet, now loading", n);
	if (keyIsRepeating < MAX_REPEATING_CACHED || currentIndex == 0 || currentIndex == filenames.count-1)
		[NSThread detachNewThreadSelector:@selector(cacheAndDisplay:)
								 toTarget:self withObject:s];
	return nil;
}

- (void)cacheAndDisplay:(NSString *)s {
	if (currentIndex == NSNotFound) return; // in case slideshow ended before thread started (i.e., don't bother caching if the slideshow is over already)
	@autoreleasepool {
		[imgCache cacheFile:s]; // this operation takes time...
		if (currentIndex != NSNotFound && [filenames[currentIndex] isEqualToString:s]) {
			//NSLog(@"cacheAndDisplay now displaying %@", idx);
			[self performSelectorOnMainThread:@selector(displayImage) withObject:nil waitUntilDone:NO];
		} /*else {
		NSLog(@"cacheAndDisplay aborted %@", idx);
		// the user hit next or something, we don't need this anymore
		} */
	}
}

#pragma mark accessors

- (BOOL)isActive {
	return currentIndex != NSNotFound;
}
- (NSUInteger)currentIndex {
	return self.visible ? currentIndex : lastIndex;
}
- (NSString *)currentFile {
	NSUInteger idx = self.currentIndex;
	if (idx >= filenames.count) { // if showing "last file was deleted" screen
		return nil;
	}
	return filenames[idx];
}
- (NSString *)basePath {
	return basePath;
}
- (unsigned short)currentOrientation {
	NSString *theFile = filenames[self.currentIndex];
	NSNumber *rot = rotations[theFile];
	return components_to_exiforientation(rot ? rot.intValue : 0, [flips[theFile] boolValue]);
}
- (unsigned short)currentFileExifOrientation {
	return [imgCache infoForKey:filenames[self.currentIndex]]->exifOrientation;
}

- (BOOL)currentImageLoaded {
	NSString *s = self.currentFile;
	if (s == nil) return NO;
	return [imgCache infoForKey:s] != nil;
}

- (void)removeImageForFile:(NSString *)s {
	[self removeImageForFile:s atIndex:NSNotFound];
}
- (void)removeImageForFile:(NSString *)s atIndex:(NSUInteger)n {
	BOOL trashMode = (n == NSNotFound);
	if (trashMode) {
		n = [filenames indexOfObject:s usingComparator:_comparator];
		if (n == NSNotFound) return;
	}
	BOOL current = (currentIndex == n);
	[filenames removeObjectAtIndex:n];
	[imgCache removeImageForKey:s];
	// if file before current file was deleted, shift index back one
	if (n < currentIndex)
		currentIndex--;
	// in trashMode, if currentIndex == [filenames count], that means the last file in the list
	// was deleted, and displayImage will show a blank screen.
	else if (!trashMode && currentIndex == filenames.count)
		currentIndex--;

	if (filenames.count == 0) {
		// no more images to display!
		[self endSlideshow];
		return;
	}
	if (current)
		[self displayImage]; // reload at the current index
	else
		[self updateInfoFld];
}

- (void)insertFile:(NSString *)s atIndex:(NSUInteger)idx {
	idx = [filenames insertObject:s usingComparator:_comparator atIndex:idx];
	[self jumpTo:idx];
}

- (void)filesWereUndeleted:(NSArray *)a {
	NSString *path = basePath;
	if (path.length > 1 && [path characterAtIndex:path.length-1] == '/')
		path = [basePath substringToIndex:path.length-1];
	BOOL subFolders = _fileWatcher.wantsSubfolders;
	BOOL needUpdate = NO;
	for (NSString *s in a) {
		if (subFolders ? [s hasPrefix:basePath] : [s.stringByDeletingLastPathComponent isEqualToString:path]) {
			NSUInteger idx = [filenames insertObject:s usingComparator:_comparator atIndex:filenames.count];
			if (!randomMode && idx <= currentIndex) {
				currentIndex++;
			}
			needUpdate = YES;
		}
	}
	if (needUpdate)
		[self updateForAddedFiles];
}

- (void)updateForAddedFiles {
	// check if we're in trashMode
	if (imgView.image == nil)
		[self redisplayImage];
	else
		[self updateInfoFld];
}

#pragma mark cat methods
- (void)displayCats {
	NSMutableArray *labels = [NSMutableArray arrayWithCapacity:1];
	NSString *s = filenames[currentIndex];
	short int i;
	for (i=0; i<NUM_FNKEY_CATS; ++i) {
		if ([cats[i] containsObject:s])
			[labels addObject:[NSString stringWithFormat:NSLocalizedString(@"Group %i", @""), i+2]];
	}
	if (labels.count) {
		catsFld.stringValue = [labels componentsJoinedByString:@", "];
		[catsFld sizeToFit];
		catsFld.hidden = NO;
	} else {
		catsFld.hidden = YES;
	}
}

- (void)assignCat:(short int)n toggle:(BOOL)toggle{
	if (n==1) {
		short int i;
		for (i=0; i<NUM_FNKEY_CATS; ++i)
			[cats[i] removeObject:filenames[currentIndex]];
	} else {
		id s = filenames[currentIndex];
		if (toggle && [cats[n-2] containsObject:s])
			[cats[n-2] removeObject:s];
		else
			[cats[n-2] addObject:s];
		if (toggle)
			[imgView setNeedsDisplayInRect:catsFld.frame]; // in case the field shrinks
	}
	[self displayCats];
	[(CreeveyController *)NSApp.delegate updateCats];
}


#pragma mark menu methods
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if (menuItem.tag == 3) // Loop
		return YES;
	if (menuItem.tag == 8) // Scale Up
		return YES;
	if (menuItem.tag == 9) // Actual Size
		return YES;
	if (menuItem.tag == 7) // random
		return YES;
	// check if the item's menu is the slideshow menu
	return [menuItem.menu itemWithTag:3] ? [self isActive]
										   : [super validateMenuItem:menuItem];
}

- (IBAction)endSlideshow:(id)sender {
	[self endSlideshow];
}

- (IBAction)toggleLoopMode:(id)sender {
	NSMenuItem *item = sender;
	item.state = loopMode = !item.state;
}
- (IBAction)toggleCheatSheet:(id)sender {
	[self toggleHelp];
}
- (IBAction)toggleScalesUp:(id)sender {
	NSMenuItem *item = sender;
	BOOL b = !item.state;
	item.state = b;
	imgView.scalesUp = b;
	if (currentIndex >= filenames.count) return;
	if (currentIndex != NSNotFound)
		[self updateInfoFld];
}
- (IBAction)toggleRandom:(id)sender {
	NSMenuItem *item = sender;
	BOOL b = !item.state;
	item.state = b;
	BOOL oldRandomMode = randomMode;
	randomMode = b;
	if (currentIndex == NSNotFound)
		return;
	// slideshow is running, so we need to do some cleanup
	if (randomMode == oldRandomMode)
		return; // but if this is a "forced" toggle from hitting "Apply Settings", no action is required
	if (randomMode) {
		if (currentIndex == filenames.count) currentIndex = NSNotFound;
		[filenames randomizeStartingWithObjectAtIndex:currentIndex];
		currentIndex = 0;
	} else {
		if (currentIndex == filenames.count)
			currentIndex = 0;
		else
			currentIndex = [filenames orderedIndexFromIndex:currentIndex];
		[filenames derandomize];
	}
	[self displayImage];
}
- (IBAction)toggleShowActualSize:(id)sender {
	NSMenuItem *item = sender;
	BOOL b = !item.state;
	// save zoomInfo, if any, BEFORE changing the vars
	if (currentIndex != NSNotFound) {
		[self killTimer]; // ** why?
		[self saveZoomInfo];
	}
	// then change vars and re-display
	item.state = b;
	imgView.showActualSize = b;
	if (currentIndex == filenames.count) return;
	if (currentIndex != NSNotFound) [self displayImage];
}

- (void)updateStatusOnMainThread:(NSString * (^)(void))f {
	static _Atomic uint64_t statusTime;
	uint64_t timeStamp = statusTime = mach_absolute_time();
	dispatch_async(dispatch_get_main_queue(), ^{
		if (statusTime == timeStamp) {
			infoFld.stringValue = f() ?: @"";
			[infoFld sizeToFit];
		}
	});
}

- (void)loadImages:(NSString *)path subfolders:(BOOL)recurseSubfolders {
	_stopLoading = NO;
	@autoreleasepool {
		CreeveyController *appDelegate = (CreeveyController *)NSApp.delegate;
		NSUInteger i = 0;
		NSString *loadingMsg = NSLocalizedString(@"Getting filenames...", @"");
		[self updateStatusOnMainThread:^NSString *{ return loadingMsg; }];
		NSMutableArray *files = [NSMutableArray array];
		NSDirectoryEnumerator *e = CreeveyEnumerator(path, recurseSubfolders);
		for (NSURL *url in e) {
			@autoreleasepool {
				if ([appDelegate handledDirectory:url subfolders:recurseSubfolders e:e])
					continue;
				if ([appDelegate shouldShowFile:url]) {
					[files addObject:url.path];
					if (++i % 100 == 0) [self updateStatusOnMainThread:^NSString *{ return [NSString stringWithFormat:@"%@ (%lu)", loadingMsg, i]; }];
				}
				if (_stopLoading)
					return;
			}
		}
		if (files.count) {
			[self updateStatusOnMainThread:^NSString *{
				return [NSString stringWithFormat:NSLocalizedString(@"Sorting %lu filenames…", @""), files.count];
			}];
			[files sortUsingComparator:self.comparator];
			if (_stopLoading) return;
			dispatch_async(dispatch_get_main_queue(), ^{
				NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
				[self setFilenames:files basePath:path wantsSubfolders:recurseSubfolders comparator:_comparator];
				self.rerandomizeOnLoop = [u boolForKey:@"Slideshow:RerandomizeOnLoop"];
				self.autoRotate = [u boolForKey:@"autoRotateByOrientationTag"];
				self.autoadvanceTime = [u boolForKey:@"slideshowAutoadvance"] ? [u floatForKey:@"slideshowAutoadvanceTime"] : 0;
				[self startSlideshowAtIndex:NSNotFound];
			});
		} else {
			[self updateStatusOnMainThread:^NSString *{
				return [NSLocalizedString(@"No image files found: ", @"long filepath appended here") stringByAppendingString:path];
			}];
		}
	}
}

@end
