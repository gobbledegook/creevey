//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#include "stdlib.h"

#import "SlideshowWindow.h"
#import <Carbon/Carbon.h>
#import "DYCarbonGoodies.h"
#import "NSStringDYBasePathExtension.h"
#import "CreeveyController.h"

@interface SlideshowWindow (Private)

//- (void)displayImage;
- (void)jump:(int)n;
- (void)jumpTo:(int)n;
- (void)setTimer:(NSTimeInterval)s;
- (void)runTimer;
- (void)killTimer;
- (void)updateInfoFld;

// cat methods
- (void)displayCats;
- (void)assignCat:(short int)n toggle:(BOOL)toggle;

// cache methods
- (NSImage *)loadFromCache:(NSString *)s;
- (void)cacheAndDisplay:(NSString *)s;


@end

@implementation SlideshowWindow

+ (void)initialize {
	srandom((unsigned long)time(NULL));
}

#define MAX_CACHED 15
// MAX_CACHED must be bigger than the number of items you plan to have cached!
#define MAX_REPEATING_CACHED 6
// when key is held down, max to cache before skipping over

// this is the designated initializer
- (id)initWithContentRect:(NSRect)r styleMask:(unsigned int)m backing:(NSBackingStoreType)b defer:(BOOL)d {
	// full screen window, force it to be NSBorderlessWindowMask
	if (self = [super initWithContentRect:r styleMask:NSBorderlessWindowMask backing:b defer:d]) {
		filenames = [[NSMutableArray alloc] init];
		rotations = [[NSMutableDictionary alloc] init];
		imgCache = [[DYImageCache alloc] initWithCapacity:MAX_CACHED];
		
 		[self setBackgroundColor:[NSColor blackColor]];
		currentIndex = -1;
   }
    return self;
}

- (void)awakeFromNib {
	imgView = [[DYImageView alloc] initWithFrame:NSZeroRect];
	[self setContentView:imgView]; // image now fills entire window
	[imgView release]; // the prev line retained it
	
	infoFld = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,300,20)];
	[imgView addSubview:infoFld]; [infoFld release];
	[infoFld setBackgroundColor:[NSColor grayColor]];
	[infoFld setBezeled:NO];
	[infoFld setEditable:NO];
	
	catsFld = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[imgView addSubview:catsFld]; [catsFld release];
	[catsFld setBackgroundColor:[NSColor grayColor]];
	[catsFld setBezeled:NO];
	[catsFld setEditable:NO]; // **
	[catsFld setHidden:YES];
}

- (void)dealloc {
	[filenames release];
	[rotations release];
	[imgCache release];
	[helpFld release];
	[super dealloc];
}

- (void)setCats:(NSMutableSet **)newCats {
    cats = newCats;
}

// must override this for borderless windows
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }

// start/end stuff
- (void)setFilenames:(NSArray *)files {
	[filenames removeAllObjects];
	[filenames addObjectsFromArray:files];
}

- (void)setBasePath:(NSString *)s {
	[basePath release];
	if ([s characterAtIndex:[s length]-1] != '/')
		basePath = [[s stringByAppendingString:@"/"] retain];
	else
		basePath = [s copy];
}

- (NSString *)currentShortFilename {
	NSString *s = [filenames objectAtIndex:currentIndex];
	return [s stringByDeletingBasePath:basePath];
}

- (void)endSlideshow {
	currentIndex = -1;
	[self killTimer];
	[self orderOut:nil];
	
	[imgCache abortCaching];
}

- (void)startSlideshow {
	[self startSlideshowAtIndex:-1]; // to distinguish from 0, for random mode
}
- (void)startSlideshowAtIndex:(int)startIndex {
	if ([filenames count] == 0) {
		NSBeep();
		return;
	}
	
	screenRect = [[NSScreen mainScreen] frame];
	[imgCache setBoundingSize:screenRect.size];
	// this may need to change as screen res changes
	// we assume user won't change screen resolution during a show
	
	[self setContentSize:screenRect.size];
	[self setFrameOrigin:NSZeroPoint];
	[catsFld setFrame:NSMakeRect(0,[imgView bounds].size.height-20,300,20)];
	// ** OR set springiness on awake
	
	
	if (randomMode) {
		unsigned i = [filenames count];
		if (startIndex != -1)
			// save selected image at the end
			[filenames exchangeObjectAtIndex:startIndex withObjectAtIndex:--i];
		while (--i)
			[filenames exchangeObjectAtIndex:i withObjectAtIndex:random()%(i+1)];
		if (startIndex != -1) {
			// now put it at the beginning
			[filenames exchangeObjectAtIndex:0 withObjectAtIndex:[filenames count]-1];
			startIndex = 0;
		}
	}
	if (startIndex == -1) startIndex = 0;
	currentIndex = startIndex;
	[self setTimer:0]; // reset the timer, in case running
	if (helpFld) [helpFld setHidden:YES];
	[imgCache beginCaching];
	[imgView setImage:nil];
	[self displayImage];
	[self makeKeyAndOrderFront:nil];
}

- (void)becomeKeyWindow { // need this when switching apps
	[self bringToForeground];
	//HideMenuBar(); // in Carbon
	//OSStatus Error = 
	SetSystemUIMode(kUIModeAllHidden, kUIOptionAutoShowMenuBar);
    //if (Error != noErr) NSLog(@"Error couldn't set SystemUIMode: %ld", (long)Error);
	[super becomeKeyWindow];
}

- (void)resignKeyWindow {
	SetSystemUIMode(kUIModeNormal, 0);	
	[super resignKeyWindow];
}

- (void)sendToBackground {
	[self setLevel:NSNormalWindowLevel-1];
}

- (void)bringToForeground {
	[self setLevel:NSNormalWindowLevel]; //**debugging
//	[self setLevel:NSFloatingWindowLevel];//CGShieldingWindowLevel()];//NSMainMenuWindowLevel+1
}

#pragma mark timer stuff
// setTimer
// sets the interval between slide show advancing.
// set to 0 to stop.
- (void)setTimer:(NSTimeInterval)s {
	timerIntvl = s;
	if (s)
		[self runTimer];
	else
		[self killTimer];
}

- (void)runTimer {
	[self killTimer]; // always remove the old timer
	if (loopMode || currentIndex+1 < [filenames count]) {
		//NSLog(@"scheduling timer from %d", currentIndex);
		autoTimer = [NSTimer
scheduledTimerWithTimeInterval:timerIntvl
						target:self
					  selector:@selector(nextTimer:)
					  userInfo:nil repeats:NO];
	}
}

- (void)killTimer {
	[autoTimer invalidate]; autoTimer = nil;
}

- (void)pauseTimer {
	[self killTimer];
	timerPaused = YES;
	if (hideInfoFld) [infoFld setHidden:NO];
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
	NSRect boundsRect = [imgView bounds];
	int rotation = [imgView rotation];
	float tmp;
	if (rotation == 90 || rotation == -90) {
		tmp = boundsRect.size.width;
		boundsRect.size.width = boundsRect.size.height;
		boundsRect.size.height = tmp;
	}
	
	if (![imgView scalesUp]
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

// display image number "currentIndex"
// if it's not cached, say "Loading" and spin off a thread to cache it
- (void)updateInfoFldWithRotation:(int)r {
	DYImageInfo *info = [imgCache infoForKey:[filenames objectAtIndex:currentIndex]];
	id dir;
	switch (r) {
		case 90: dir = NSLocalizedString(@" left", @""); break;
		case -90: dir = NSLocalizedString(@" right", @""); break;
		default: dir = @"";
	}
	if (r < 0) r = -r;
	float zoom = [imgView zoomMode] ? [imgView zoomF] : [self calcZoom:info->pixelSize];
	[infoFld setStringValue:[NSString stringWithFormat:@"[%i/%i%@] %@ - %@%@ - %@%@",
		currentIndex+1, [filenames count],
		r ? [NSString stringWithFormat:
			NSLocalizedString(@" rotated%@ %i%C", @""), dir, r, 0xb0] : @"", //degrees
		[self currentShortFilename],
		[info pixelSizeAsString],
		(zoom != 1.0 || [imgView zoomMode]) ? [NSString stringWithFormat:
			@" @ %.0f%%", zoom*100] : @"",
		FileSize2String(info->fileSize),
		timerIntvl && timerPaused ? [NSString stringWithFormat:@" %@(%.1g%@) %@",
			NSLocalizedString(@"Auto-advance", @""),
			timerIntvl,
			NSLocalizedString(@"seconds", @""),
			NSLocalizedString(@"PAUSED", @"")]
								  : @""]];
//	[infoFld setNeedsDisplay:YES];
	[infoFld sizeToFit];
//	[infoFld setNeedsDisplay:YES];
	[imgView setNeedsDisplay:YES]; // **
}

- (void)updateInfoFld {
	[self updateInfoFldWithRotation:[imgView rotation]];
}

- (void)displayImage {
	if (currentIndex == -1) return; // in case called after slideshow ended
									// not necessary if s/isActive/isKeyWindow/
	NSString *theFile = [filenames objectAtIndex:currentIndex];
	NSImage *img = [self loadFromCache:theFile];
	if ([self isKeyWindow])
		[NSCursor setHiddenUntilMouseMoves:YES];
	[self displayCats];
	if (img) {
		//NSLog(@"displaying %d", currentIndex);
		NSNumber *rot = [rotations objectForKey:theFile];
		int r = rot ? [rot intValue] : 0;
		if (hideInfoFld) [infoFld setHidden:YES]; // this must happen before setImage, for redraw purposes
		[imgView setImage:img];
		if (r) [imgView setRotation:r];
		[self updateInfoFldWithRotation:r];
		if (timerIntvl) [self runTimer];
	} else {
		if (hideInfoFld) [infoFld setHidden:NO];
		[infoFld setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Loading [%i/%i] %@...", @""),
			currentIndex+1, [filenames count], [self currentShortFilename]]];
		[infoFld sizeToFit];
		return;
	}
	if (keyIsRepeating) return; // don't bother precaching if we're fast-forwarding anyway
	int i;
	for (i=1; i<=2; i++) {
		if (currentIndex+i >= [filenames count])
			break;
		[imgCache cacheFileInNewThread:[filenames objectAtIndex:currentIndex+i]];
	}
}

- (void)jump:(int)n { // go forward n pics (negative numbers go backwards)
	if (n < 0)
		[self setTimer:0]; // going backwards stops auto-advance
	else // could get rid of 'else' b/c going backwards makes timerPaused irrelevant
		timerPaused = NO; // going forward unpauses auto-advance
	if ((n > 0 && currentIndex+1 == [filenames count]) || (n < 0 && currentIndex == 0)){
		if (loopMode)
			[self jumpTo:n<0 ? [filenames count]-1 : 0];
		else
			NSBeep();
		return;
	}
	[self jumpTo:currentIndex+n];
}

- (void)jumpTo:(int)n {
	//NSLog(@"jumping to %d", n);
	[self killTimer];
	currentIndex = n < 0 ? 0 : n >= [filenames count] ? [filenames count] - 1 : n;
	[self displayImage];
}

- (void)setRotation:(int)n {
	n = [imgView addRotation:n];
	[rotations setObject:[NSNumber numberWithInt:n]
				  forKey:[filenames objectAtIndex:currentIndex]];
	[self updateInfoFldWithRotation:n];
}


- (void)toggleHelp {
	if (!helpFld) {
		helpFld = [[NSTextView alloc] initWithFrame:NSZeroRect]; //NSMakeRect(0,0,310,265)
		[[self contentView] addSubview:helpFld]; [helpFld release];
		[helpFld setHorizontallyResizable:YES]; // NO by default
//		[helpFld setVerticallyResizable:NO]; // YES by default
//		[helpFld sizeToFit]; //doesn't do anything?
		if (![helpFld readRTFDFromFile:
			[[NSBundle mainBundle] pathForResource:@"creeveyhelp" ofType:@"rtf"]])
			NSLog(@"couldn't load cheat sheet!");
		[helpFld setBackgroundColor:[NSColor lightGrayColor]];
		[helpFld setSelectable:NO];
		NSSize s = [[helpFld textStorage] size];
		NSRect r = NSMakeRect(0,0,s.width+12,s.height);
		// width must be bigger than text, or wrappage will occur
		s = [[self contentView] frame].size;
		r.origin.x = s.width - r.size.width - 50;
		r.origin.y = s.height - r.size.height - 55;
		[helpFld setFrame:r];
		return;
	}
	[helpFld setHidden:![helpFld isHidden]];
}

// Here's the bulk of our user interface, all keypresses
- (void)keyUp:(NSEvent *)e {
	if (keyIsRepeating) {
		keyIsRepeating = 0;
		switch ([[e characters] characterAtIndex:0]) {
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
	unichar c = [[e characters] characterAtIndex:0];
	if (c >= '1' && c <= '9') {
		if (([e modifierFlags] & NSNumericPadKeyMask) != 0 && [imgView zoomMode]) {
			if (c == '5') {
				NSBeep();
			} else {
				char x,y;
				c -= '0';
				if (c<=3) y = 1; else if (c>=7) y = -1;
				if (c%3 == 0) x = -1; else if (c%3 == 1) x = 1;
				[imgView fakeDragX:([imgView bounds].size.width/2)*x
								 y:([imgView bounds].size.height/2)*y];
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
				 toggle:([e modifierFlags] & NSCommandKeyMask) != 0];
		//NSLog(@"got cat %i", c - NSF1FunctionKey + 1);
		return;
	}
	if ([e isARepeat] && keyIsRepeating < MAX_REPEATING_CACHED) {
		keyIsRepeating++;
	}
	DYImageInfo *obj;
	switch (c) {
		case '!':
			[self setTimer:0.5];
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
			[self jump:1];
			break;
		case NSLeftArrowFunctionKey:
		case NSUpArrowFunctionKey:
			[self jump:-1];
			break;
		case NSHomeFunctionKey:
			[self jump:-currentIndex]; // <0 stops auto-advance
			break;
		case NSEndFunctionKey:
			[self jumpTo:[filenames count]-1];
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
			hideInfoFld = ![infoFld isHidden];
			[infoFld setHidden:hideInfoFld]; // 10.3 or later!
			break;
		case 'h':
		case '?':
		case '/':
		case NSHelpFunctionKey: // doesn't work, trapped at a higher level?
			[self toggleHelp];
			break;
		case 'l':
			[self setRotation:90];
			break;
		case 'r':
			[self setRotation:-90];
			break;
		case '+':
		case '-':
		case '=':
			if (obj = [imgCache infoForKey:[filenames objectAtIndex:currentIndex]]) {
				if (obj->image == [imgView image]
					&& !NSEqualSizes(obj->pixelSize,[obj->image size])) {
					[imgView setImage:[[[NSImage alloc] initByReferencingFile:
						ResolveAliasToPath([filenames objectAtIndex:currentIndex])] autorelease]
							   zoomIn:c == '=' ? 2 : c == '+'];
				} else {
					if (c == '+') [imgView zoomIn];
					else if (c == '-') [imgView zoomOut];
					else [imgView zoomActualSize];
				}
				[self updateInfoFld];
			}
			break;
		case '*':
			[imgView zoomOff];
			[self updateInfoFld];
			break;
		default:
			//NSLog(@"%x",c);
			[super keyDown:e];
	}
}

// cache stuff

- (NSImage *)loadFromCache:(NSString *)s {
	NSImage *img = [imgCache imageForKey:s];
	if (img)
		return img;
	//NSLog(@"%d not cached yet, now loading", n);
	if (keyIsRepeating < MAX_REPEATING_CACHED || currentIndex == 0 || currentIndex == [filenames count]-1)
		[NSThread detachNewThreadSelector:@selector(cacheAndDisplay:)
								 toTarget:self withObject:s];
	return nil;
}

- (void)cacheAndDisplay:(NSString *)s { // ** roll this into imagecache?
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[imgCache cacheFile:s];
	if ([[filenames objectAtIndex:currentIndex] isEqualToString:s]) {
		//NSLog(@"cacheAndDisplay now displaying %@", idx);
		[self performSelectorOnMainThread:@selector(displayImage) // requires 10.2
							   withObject:nil waitUntilDone:NO];
		//[self displayImage];
		//if (autoTimer) [[NSRunLoop currentRunLoop] run];
		// we must run the runLoop for the timer b/c we're in a separate thread
	} /*else {
		NSLog(@"cacheAndDisplay aborted %@", idx);
		// the user hit next or something, we don't need this anymore		
	} */
	[pool release];
}

// giving access to outsiders
- (BOOL)isActive {
	return currentIndex != -1;
}
- (NSString *)currentFile {
	if (currentIndex == -1) return nil;
	return [filenames objectAtIndex:currentIndex];
}

- (BOOL)currentImageLoaded {
	NSString *s = [self currentFile];
	return [imgCache infoForKey:s] != nil;
}

- (void)removeImageForFile:(NSString *)s {
	[imgCache removeImageForKey:s];
	[filenames removeObject:s];
	if (currentIndex == [filenames count]) currentIndex--;
	if (currentIndex == -1) {
		// no more images to display!
		[self endSlideshow];
		return;
	}
	[self displayImage]; // reload at the current index
}

#pragma mark cat methods
- (void)displayCats {
	NSMutableArray *labels = [NSMutableArray arrayWithCapacity:1];
	NSString *s = [filenames objectAtIndex:currentIndex];
	short int i;
	for (i=0; i<NUM_FNKEY_CATS; ++i) {
		if ([cats[i] containsObject:s])
			[labels addObject:[NSString stringWithFormat:NSLocalizedString(@"Group %i", @""), i+2]];
	}
	if ([labels count]) {
		[catsFld setStringValue:[labels componentsJoinedByString:@", "]];
		[catsFld sizeToFit];
		[catsFld setHidden:NO];
	} else {
		[catsFld setHidden:YES];
	}
}

- (void)assignCat:(short int)n toggle:(BOOL)toggle{
	if (n==1) {
		short int i;
		for (i=0; i<NUM_FNKEY_CATS; ++i)
			[cats[i] removeObject:[filenames objectAtIndex:currentIndex]];
	} else {
		id s = [filenames objectAtIndex:currentIndex];
		if (toggle && [cats[n-2] containsObject:s])
			[cats[n-2] removeObject:s];
		else
			[cats[n-2] addObject:s];
		if (toggle)
			[imgView setNeedsDisplayInRect:[catsFld frame]]; // in case the field shrinks
	}
	[self displayCats];
}


#pragma mark menu methods
- (BOOL)validateMenuItem:(id <NSMenuItem>)menuItem {
	if ([menuItem tag] == 3) // Loop
		return YES;
	if ([menuItem tag] == 7) // random
		return ![self isActive];
	return [self isActive];
}

- (IBAction)endSlideshow:(id)sender {
	[self endSlideshow];
}

- (IBAction)toggleLoopMode:(id)sender {
	loopMode = !loopMode;
	[sender setState:loopMode]; // ** what about startup?
}
- (IBAction)toggleCheatSheet:(id)sender {
	[self toggleHelp];
	[sender setState:![helpFld isHidden]];
}
- (IBAction)toggleScalesUp:(id)sender {
	BOOL b = ![sender state];
	[sender setState:b];
	[imgView setScalesUp:b];
	if (currentIndex != -1)
		[self updateInfoFld];
}
- (IBAction)toggleRandom:(id)sender {
	randomMode = !randomMode;
	[sender setState:randomMode];
}

@end
