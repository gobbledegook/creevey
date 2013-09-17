//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#include "stdlib.h"

#import "CreeveyController.h"
#import "EpegWrapper.h"
#import "DYJpegtran.h"
#import "DYCarbonGoodies.h"
#import "NSArrayIndexSetExtension.h"

#import "DYWrappingMatrix.h"
#import "CreeveyMainWindowController.h"
#import "DYImageCache.h"
#import "SlideshowWindow.h"
#import "DYJpegtranPanel.h"
#import "DYVersChecker.h"
#import "DYExiftags.h"

#define MAX_THUMBS 2000
#define DYVERSCHECKINTERVAL 604800

BOOL FileIsJPEG(NSString *s) {
	return [[[s pathExtension] lowercaseString] isEqualToString:@"jpg"]
	|| [NSHFSTypeOfFile(s) isEqualToString:@"JPEG"];
}

#define TAB(x,y)	[[[NSTextTab alloc] initWithType:x location:y] autorelease]
NSMutableAttributedString* Fileinfo2EXIFString(NSString *origPath, DYImageCache *cache,
											   BOOL moreExif, BOOL basicInfo) {
	// basicInfo was added for the slideshow view
	// it's defunct now that i've decided to stick the filename in
	id s, path;
	path = ResolveAliasToPath(origPath);
	s = [[NSMutableString alloc] init];
	if (basicInfo) [s appendString:[origPath lastPathComponent]];
	if (path != origPath)
		[s appendFormat:@"\n[%@->%@]", NSLocalizedString(@"Alias", @""), path];
	DYImageInfo *i = [cache infoForKey:origPath];
	if (!i) i = [cache infoForKey:path]; // if no info from the given path, try resolving the alias.
	if (i) {
		id exifStr = [DYExiftags tagsForFile:path moreTags:moreExif];
		if (basicInfo)
			[s appendFormat:@"\n%@ (%qu bytes)\n%@: %d %@: %d",
				FileSize2String(i->fileSize), i->fileSize,
				NSLocalizedString(@"Width", @""), (int)i->pixelSize.width,
				NSLocalizedString(@"Height", @""), (int)i->pixelSize.height];
		if (exifStr) {
			if (basicInfo) [s appendString:@"\n"];
			[s appendString:exifStr];
		}
	} else if (basicInfo) {
		unsigned long long fsize;
		fsize = [[[NSFileManager defaultManager] fileAttributesAtPath:path traverseLink:YES] fileSize];
		[s appendFormat:@"\n%@ (%qu bytes)\n%@",
			FileSize2String(fsize), fsize,
			NSLocalizedString(@"Unable to read file", @"")];
	}
	
	NSMutableDictionary *atts = [NSMutableDictionary dictionaryWithObject:
										[NSFont userFontOfSize:12] forKey:NSFontAttributeName];
	NSMutableAttributedString *attStr =
		[[NSMutableAttributedString alloc] initWithString:s
											   attributes:atts];
	NSRange r = [s rangeOfString:NSLocalizedString(@"Camera-Specific Properties:\n", @"")];
	// ** this may not be optimal
	if (r.location != NSNotFound) {
		float x = 160;
		NSMutableParagraphStyle *styl = [[[NSMutableParagraphStyle alloc] init] autorelease];
		[styl setHeadIndent:x];
		[styl setTabStops:[NSArray arrayWithObjects:TAB(NSRightTabStopType,x-5),
			TAB(NSLeftTabStopType,x), nil]];
		[styl setDefaultTabInterval:5];
		
		[atts setObject:styl forKey:NSParagraphStyleAttributeName];
		[attStr setAttributes:atts range:NSMakeRange(r.location,[s length]-r.location)];
	}
	[s release];
	return [attStr autorelease];
}

@interface TimeIntervalPlusWeekToStringTransformer : NSObject
// using a val xformer means the field gets updated automatically
@end
@implementation TimeIntervalPlusWeekToStringTransformer
+ (Class)transformedValueClass { return [NSString class]; }
- (id)transformedValue:(id)v {
	return [[NSDate dateWithTimeIntervalSinceReferenceDate:
		[v floatValue]+DYVERSCHECKINTERVAL] description];
}
@end

@implementation CreeveyController

+(void)initialize
{
    NSMutableDictionary *dict;
    NSUserDefaults *defaults;
	
    defaults=[NSUserDefaults standardUserDefaults];
	
    dict=[NSMutableDictionary dictionary];
	NSString *s = CREEVEY_DEFAULT_PATH;
    [dict setObject:s forKey:@"picturesFolderPath"];
    [dict setObject:s forKey:@"lastFolderPath"];
    [dict setObject:[NSNumber numberWithShort:0] forKey:@"startupOption"];
	[dict setObject:[NSNumber numberWithFloat:120] forKey:@"thumbCellWidth"];
	[dict setObject:[NSNumber numberWithBool:YES] forKey:@"getInfoVisible"];
	[dict setObject:[NSNumber numberWithBool:YES] forKey:@"autoVersCheck"];
	[dict setObject:[NSNumber numberWithBool:NO] forKey:@"jpegPreserveModDate"];
	[dict setObject:[NSNumber numberWithBool:NO] forKey:@"slideshowAutoadvance"];
	[dict setObject:[NSNumber numberWithFloat:5.25] forKey:@"slideshowAutoadvanceTime"];
	[dict setObject:[NSNumber numberWithBool:NO] forKey:@"slideshowLoop"];
	[dict setObject:[NSNumber numberWithBool:NO] forKey:@"slideshowRandom"];
	[dict setObject:[NSNumber numberWithBool:NO] forKey:@"slideshowScaleUp"];
	[dict setObject:[NSNumber numberWithBool:NO] forKey:@"slideshowActualSize"];
	[dict setObject:[NSKeyedArchiver archivedDataWithRootObject:[NSColor blackColor]] forKey:@"slideshowBgColor"];
	[dict setObject:[NSNumber numberWithBool:NO] forKey:@"exifThumbnailShow"];
	[dict setObject:[NSNumber numberWithBool:YES] forKey:@"showFilenames"];
	[dict setObject:[NSNumber numberWithBool:YES] forKey:@"Slideshow:RerandomizeOnLoop"];
    [defaults registerDefaults:dict];

	id t = [[[TimeIntervalPlusWeekToStringTransformer alloc] init] autorelease];
	[NSValueTransformer setValueTransformer:t
									forName:@"TimeIntervalPlusWeekToStringTransformer"];
}

- (id)init {
	if (self = [super init]) {
		filetypes = [[NSSet alloc] initWithArray:[NSImage imageUnfilteredFileTypes]];
			//@"jpg", @"jpeg," @"gif",
			//@"tif", @"tiff", @"pict", @"pdf", @"icns", nil];
		//hfstypes = [[NSSet alloc] initWithObjects:@"'PICT'", @"'JPEG'", @"'GIFf'",
		//	@"'TIFF'", @"'PDF '", nil]; // need those single quotes
		//NSLog(@"%@", [NSImage imageFileTypes]);
		creeveyWindows = [[NSMutableArray alloc] initWithCapacity:5];
		
		thumbsCache = [[DYImageCache alloc] initWithCapacity:MAX_THUMBS];
		[thumbsCache setBoundingSize:[DYWrappingMatrix maxCellSize]];
		[thumbsCache setInterpolationType:NSImageInterpolationNone];
		
		short int i;
		for (i=0; i<NUM_FNKEY_CATS; ++i) {
			cats[i] = [[NSMutableSet alloc] initWithCapacity:0];
		}
		
		exifWasVisible = [[NSUserDefaults standardUserDefaults] boolForKey:@"getInfoVisible"];
	}
    return self;
}


- (void)awakeFromNib { // ** warning: this gets called when loading nibs too!
	[(NSPanel *)[exifTextView window] setBecomesKeyOnlyIfNeeded:YES];
	//[[exifTextView window] setHidesOnDeactivate:NO];
	// this causes problems b/c the window can be foregrounded without the app
	// coming to the front (oops)
	[slidesWindow setCats:cats];
	[slidesWindow setRerandomizeOnLoop:[[NSUserDefaults standardUserDefaults] boolForKey:@"Slideshow:RerandomizeOnLoop"]];
	
	[[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
															  forKeyPath:@"values.slideshowAutoadvanceTime"
																 options:NSKeyValueObservingOptionNew
																 context:NULL];
	[[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
															  forKeyPath:@"values.DYWrappingMatrixMaxCellWidth"
																 options:0
																 context:NULL];
	[[NSColorPanel sharedColorPanel] setShowsAlpha:YES]; // show color picker w/ opacity/transparency
}

- (void)dealloc {
	[thumbsCache release];
	[filetypes release];
	[creeveyWindows release];
	short int i;
	for (i=0; i<NUM_FNKEY_CATS; ++i)
		[cats[i] release];
	[super dealloc];
}

- (void)slideshowFromAppOpen:(NSArray *)files {
	[slidesWindow setBasePath:[frontWindow path]];
	[slidesWindow setFilenames:[files count] > 1
		? [files sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]
			// ** use smarter sorting here?
		: [frontWindow displayedFilenames]];
	[slidesWindow startSlideshowAtIndex: [files count] == 1
		? [[frontWindow displayedFilenames] indexOfObject:[files objectAtIndex:0]]
			// here's a fun (and SLOW) linear search
		: -1];
}

- (void)startSlideshow {
	// check for nil?
	// clever disabling of items should be ok
	[slidesWindow setBasePath:[frontWindow path]];
	NSIndexSet *s = [frontWindow selectedIndexes];
	[slidesWindow setFilenames:[s count] > 1
		? [frontWindow currentSelection]
		: [frontWindow displayedFilenames]];
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	[slidesWindow setAutoadvanceTime:[u boolForKey:@"slideshowAutoadvance"]
		? [u floatForKey:@"slideshowAutoadvanceTime"]
		: 0]; // see prefs section for more notes
	[slidesWindow setRerandomizeOnLoop:[u boolForKey:@"Slideshow:RerandomizeOnLoop"]];
	[slidesWindow startSlideshowAtIndex: [s count] == 1 ? [s firstIndex] : -1];
}

- (IBAction)slideshow:(id)sender
{
	[self startSlideshow];
}

- (IBAction)openSelectedFiles:(id)sender {
	[self startSlideshow];
}

- (IBAction)revealSelectedFilesInFinder:(id)sender {
	if ([slidesWindow isMainWindow]) {
		RevealItemsInFinder([NSArray arrayWithObject:[slidesWindow currentFile]]);
	} else {
		NSArray *a = [frontWindow currentSelection];
		if ([a count])
			RevealItemsInFinder(a);
		else
			[[NSWorkspace sharedWorkspace] openFile:[frontWindow path]];
	}
}


- (IBAction)setDesktopPicture:(id)sender {
	NSString *s = [slidesWindow isMainWindow]
		? [slidesWindow currentFile]
		: [[frontWindow currentSelection] objectAtIndex:0];
	OSErr err = SetDesktopPicture(ResolveAliasToPath(s),0);
	if (err != noErr) {
		NSRunAlertPanel(nil, //title
						NSLocalizedString(@"Could not set the desktop because an error of type %i occurred.", @""),
						@"Cancel", nil, nil,
						err);
	}
}

// this is called "test" even though it works now.
// moral: name your functions correctly from the start.
- (IBAction)rotateTest:(id)sender {
	DYJpegtranInfo jinfo;
	int t = [sender tag] - 100;
	if (t == 0) {
		if (!jpegController)
			if (![NSBundle loadNibNamed:@"DYJpegtranPanel" owner:self]) return;
		if (![jpegController runOptionsPanel:&jinfo]) return;
	} else {
		jinfo.thumbOnly = t > 30;
		if (jinfo.thumbOnly) t -= 30;
		jinfo.tinfo.transform = t < DYJPEGTRAN_XFORM_PROGRESSIVE ? t : JXFORM_NONE;
		jinfo.tinfo.trim = FALSE;
		jinfo.tinfo.force_grayscale = t == DYJPEGTRAN_XFORM_GRAYSCALE;
		jinfo.cp = JCOPYOPT_ALL;
		jinfo.progressive = t == DYJPEGTRAN_XFORM_PROGRESSIVE;
		jinfo.optimize = 0;
		jinfo.autorotate = t == DYJPEGTRAN_XFORM_AUTOROTATE;
		jinfo.resetOrientation = t == DYJPEGTRAN_XFORM_RESETORIENT;
		jinfo.replaceThumb = t == DYJPEGTRAN_XFORM_REGENTHUMB;
		jinfo.delThumb = t == DYJPEGTRAN_XFORM_DELETETHUMB;
	}
	// throw up warning if necessary
	if (jinfo.tinfo.force_grayscale || jinfo.cp != JCOPYOPT_ALL || jinfo.tinfo.trim
		|| jinfo.resetOrientation || jinfo.replaceThumb || jinfo.delThumb) {
		if (NSRunCriticalAlertPanel(NSLocalizedString(@"Warning", @""),
								NSLocalizedString(@"This operation cannot be undone! Are you sure you want to continue?", @""),
								NSLocalizedString(@"Continue", @""), NSLocalizedString(@"Cancel", @""), nil)
			!= NSAlertDefaultReturn)
			return; // user cancelled
		jinfo.preserveModificationDate = jinfo.resetOrientation ? [[NSUserDefaults standardUserDefaults] boolForKey:@"jpegPreserveModDate"]
																: NO;
										 // make an exception for reset orientation,
										 // since it doesn't _really_ change anything
	} else {
		jinfo.preserveModificationDate = [[NSUserDefaults standardUserDefaults] boolForKey:@"jpegPreserveModDate"];
	}
	
	NSArray *a;
	DYImageInfo *imgInfo;
	BOOL slidesWasKey = [slidesWindow isMainWindow]; // ** test for main is better than key
	BOOL autoRotate = YES; // set this to yes, if the browser is active and not autorotating we change it below. I.e., autorotate will be true if we're in a slideshow
	if (slidesWasKey) {
		NSString *slidesFile = [slidesWindow currentFile];
		a = [NSArray arrayWithObject:slidesFile];
		// we need to get the current (viewing) orientation of the slide
		// we *don't* need to save the current cached thumbnail info since it's going to get deleted
		unsigned short orientation = [slidesWindow currentOrientation];
		if (orientation != 0) {
			imgInfo = [thumbsCache infoForKey:ResolveAliasToPath(slidesFile)];
			if (imgInfo)
				imgInfo->exifOrientation = [slidesWindow currentOrientation];
		}
	} else {
		a = [frontWindow currentSelection];
		autoRotate = [[frontWindow imageMatrix] autoRotate];
	}
	
	[jpegProgressBar setUsesThreadedAnimation:YES];
	[jpegProgressBar setIndeterminate:YES];
	[jpegProgressBar setDoubleValue:0];
	[jpegProgressBar setMaxValue:[a count]];
	[[[[jpegProgressBar window] contentView] viewWithTag:1] setEnabled:[a count] > 1]; // cancel btn
	NSModalSession session = [NSApp beginModalSessionForWindow:[jpegProgressBar window]];
	[NSApp runModalSession:session];
	[jpegProgressBar startAnimation:self];

	unsigned int n;
	NSString *s, *resolvedPath;
	NSSize maxThumbSize = NSMakeSize(160,160);
	for (n = 0; n < [a count]; ++n) {
		s = [a objectAtIndex:n];
		resolvedPath = ResolveAliasToPath(s);
		if (jinfo.replaceThumb) {
			NSSize tmpSize;
			NSImage *i = [EpegWrapper imageWithPath:resolvedPath
										boundingBox:maxThumbSize
											getSize:&tmpSize
										  exifThumb:NO
									 getOrientation:NULL];
			if (i) {
				// assuming EpegWrapper always gives us a bitmap imagerep
				jinfo.newThumb = [(NSBitmapImageRep *)[[i representations] objectAtIndex:0]
					representationUsingType:NSJPEGFileType
								 properties:[NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:0.0]
																		forKey:NSImageCompressionFactor]
					];
				jinfo.newThumbSize = tmpSize;
			} else {
				jinfo.newThumb = NULL;
			}
		}
		imgInfo = [thumbsCache infoForKey:resolvedPath];
		jinfo.starting_exif_orientation = autoRotate
			? (imgInfo ? imgInfo->exifOrientation : 0) // thumbsCache should always have the info we want, but just in case it doesn't don't crash!
			: 0;
		if ([DYJpegtran transformImage:resolvedPath transform:jinfo]) {
			[thumbsCache removeImageForKey:resolvedPath];
			[creeveyWindows makeObjectsPerformSelector:@selector(fileWasChanged:) withObject:s];
			// slower, but easier code
			if (slidesWasKey) // remember, progress window is now key
				[slidesWindow redisplayImage];
			else
				[slidesWindow uncacheImage:s]; // when we have multiple slideshows, we can just use this method
		} else {
			// ** fail silently
			//NSLog(@"rot failed!");
		}
		if ([jpegProgressBar isIndeterminate]) {
			[jpegProgressBar stopAnimation:self];
			[jpegProgressBar setIndeterminate:NO];
		}
		[jpegProgressBar incrementBy:1];
		if ([NSApp runModalSession:session] != NSRunContinuesResponse) break;
	}
	[frontWindow updateExifInfo];

	[NSApp endModalSession:session];
	[[jpegProgressBar window] orderOut:self];
}

- (IBAction)stopModal:(id)sender {
	[NSApp stopModal];
}


// returns 1 if successful
// unsuccessful: 0 user wants to continue; 2 cancel/abort
- (char)trashFile:(NSString *)fullpath numLeft:(unsigned int)numFiles {
	int tag;
	if ([[NSWorkspace sharedWorkspace]
performFileOperation:NSWorkspaceRecycleOperation
			  source:[fullpath stringByDeletingLastPathComponent]
		 destination:@""
			   files:[NSArray arrayWithObject:[fullpath lastPathComponent]]
				 tag:&tag]) {
		return 1;
	}
	if (NSRunAlertPanel(nil, //title
						NSLocalizedString(@"The file %@ could not be moved to the trash because an error of %i occurred.", @""),
						NSLocalizedString(@"Cancel", @""),
						(numFiles > 1 ? NSLocalizedString(@"Continue", @"") : nil),
						nil,
						[fullpath lastPathComponent], tag) == NSAlertDefaultReturn)
		return 2;
	return 0;
}

- (void)removePicsAndTrash:(BOOL)b {
	// *** to be more efficient, we should change the path in the cache instead of deleting it
	if ([slidesWindow isMainWindow]) {
		NSString *s = [slidesWindow currentFile];
		if (!b || [self trashFile:s numLeft:1]) {
			[creeveyWindows makeObjectsPerformSelector:@selector(fileWasDeleted:) withObject:s];
			[thumbsCache removeImageForKey:s];
			[slidesWindow removeImageForFile:s];
		}
	} else {
		NSArray *a = [frontWindow currentSelection];
		unsigned int i, n = [a count];
		// we have to go backwards b/c we're deleting from the imgMatrix
		// wait... we don't, because we're not using indexes anymore
		for (i=0; i < n; ++i) {
			NSString *fullpath = [a objectAtIndex:i];
			char result = (b ? [self trashFile:fullpath numLeft:n-i] : 1);
			if (result == 1) {
				[thumbsCache removeImageForKey:fullpath]; // we don't resolve alias here, but that's OK
				[creeveyWindows makeObjectsPerformSelector:@selector(fileWasDeleted:) withObject:fullpath];
				if ([slidesWindow isVisible])
					[slidesWindow unsetFilename:fullpath];
			} else if (result == 2)
				break;
		}
		[frontWindow updateExifInfo];
	}
}

- (IBAction)moveToTrash:(id)sender {
	[self removePicsAndTrash:YES];
}

- (IBAction)moveElsewhere:(id)sender {
	[self removePicsAndTrash:NO];
}

#pragma mark app delegate methods
//int col = [dirBrowser selectedColumn];
// it's "selected" but not actually first responder
// hence the following convolutions
//	//NSLog(@"setting firstresponder");
//	NSWindow *w = [dirBrowser window];
//	id r = [w firstResponder];
//	do {
//		if (r == dirBrowser) {
//			[w makeFirstResponder:dirBrowser];
//			break;
//		}
//	} while ((r = [r nextResponder]) != w);
//	// i hate NSBrowser
//	//NSLog(@"DONE setting firstresponder");

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	[self showExifThumbnail:[u boolForKey:@"exifThumbnailShow"]
			   shrinkWindow:NO];
	
	//NSLog(@"appdidfinlaunch called");
	if (!frontWindow) // user didn't drop icons onto app when opening
		[self newWindow:self];

	[self applySlideshowPrefs:nil];
	
	NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate];
	if ([u boolForKey:@"autoVersCheck"]
		&& (t - [u floatForKey:@"lastVersCheckTime"] > DYVERSCHECKINTERVAL)) // one week
		if ([[DYVersChecker alloc] initWithNotify:NO])
			[u setFloat:t forKey:@"lastVersCheckTime"];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	if ([creeveyWindows count])
		[frontWindow updateDefaults];
	[u setBool:([slidesWindow isMainWindow] || [creeveyWindows count] == 0) ? exifWasVisible : [[exifTextView window] isVisible]
		forKey:@"getInfoVisible"];
	[u synchronize];
}


- (void)applicationDidResignActive:(NSNotification *)aNotification {
	[slidesWindow sendToBackground];
}

- (BOOL)application:(NSApplication *)sender
		   openFile:(NSString *)filename {
	if (![creeveyWindows count]) [self newWindow:nil];
	[frontWindow openFiles:[NSArray arrayWithObject:filename] withSlideshow:YES];
	if (sender) {
		[[frontWindow window] makeKeyAndOrderFront:nil];
		//[sender activateIgnoringOtherApps:YES]; // for expose'
	}
	return YES;
}

- (void)application:(NSApplication *)sender
		  openFiles:(NSArray *)files {
	if (![creeveyWindows count]) [self newWindow:nil];
	[frontWindow openFiles:files withSlideshow:YES];
	if (sender) {
		[sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
		[[frontWindow window] makeKeyAndOrderFront:nil];
	}
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag {
	if (![creeveyWindows count]) {
		[self newWindow:self];
		return NO;
	}
	return YES;
}
#pragma mark menu methods
enum {
	REVEAL_IN_FINDER = 1,
	MOVE_TO_TRASH,
	LOOP, // Embiggen is also 3
	BEGIN_SLIDESHOW,
	SET_DESKTOP,
	GET_INFO,
	RANDOM_MODE,
	SLIDESHOW_SCALE_UP,
	SLIDESHOW_ACTUAL_SIZE,
	JPEG_OP = 100,
	ROTATE_L = 107,
	ROTATE_R = 105,
	EXIF_ORIENT_ROTATE = 113,
	EXIF_ORIENT_RESET = 114,
	EXIF_THUMB_DELETE = 116,
	ROTATE_SAVE = 117,
	SORT_NAME = 201,
	SORT_DATE_MODIFIED = 202,
	SHOW_FILE_NAMES = 251,
	AUTO_ROTATE = 261,
	SLIDESHOW_MENU = 1001,
	VIEW_MENU = 200
};


- (BOOL)validateMenuItem:(id <NSMenuItem>)menuItem {
	int t = [menuItem tag];
	int test_t = t;
	if (![NSApp mainWindow]) {
		// menu items with tags only enabled if there's a window
		return !t;
	}
	if (t>JPEG_OP && t < SORT_NAME) {
		if ((t > JPEG_OP + 30 || t == EXIF_THUMB_DELETE) &&
			![[menuItem menu] supermenu] && // only for contextual menu
			![[[[exifThumbnailDiscloseBtn window] contentView] viewWithTag:2] image]) {
			return NO;
		}
		test_t = JPEG_OP;
	}
	if (![creeveyWindows count]) frontWindow = nil;
	unsigned int numSelected = frontWindow ? [[frontWindow selectedIndexes] count] : 0;
	BOOL writable, isjpeg;
	
	switch (test_t) {
		case MOVE_TO_TRASH:
		case JPEG_OP:
			// only when slides isn't loading cache!
			// only if writeable (we just test the first file in the list)
			writable = [slidesWindow isMainWindow]
				? [slidesWindow currentImageLoaded] &&
					[[NSFileManager defaultManager] isDeletableFileAtPath:
						[slidesWindow currentFile]]
				: numSelected > 0 && frontWindow && [frontWindow currentFilesDeletable];
			if (t == MOVE_TO_TRASH) return writable;
			
			isjpeg = [slidesWindow isMainWindow]
				? FileIsJPEG([slidesWindow currentFile])
				: numSelected > 0 && frontWindow && FileIsJPEG([frontWindow firstSelectedFilename]);
			
			//if (t == JPEG_OP) return writable && isjpeg;
			if (t == ROTATE_SAVE) { // only allow saving rotations during the slideshow
				return writable && isjpeg && [slidesWindow isMainWindow]
				&& [slidesWindow currentOrientation] > 1;
			}
			if ((t == EXIF_ORIENT_ROTATE || t == EXIF_ORIENT_RESET) && [slidesWindow isMainWindow]) {
				return writable && isjpeg && [slidesWindow currentFileExifOrientation] > 1;
			}
			return writable && isjpeg;
			// I don't like the idea of accessing the disk every time the menu
			// is accessed
		case REVEAL_IN_FINDER:
			return YES;
		case BEGIN_SLIDESHOW:
			if ([slidesWindow isMainWindow] ) return NO;
			return frontWindow && [frontWindow filenamesDone] && [[frontWindow displayedFilenames] count];
		case SET_DESKTOP:
			return [slidesWindow isMainWindow] || numSelected == 1;
		case GET_INFO:
		case SORT_NAME:
		case SORT_DATE_MODIFIED:
		case SHOW_FILE_NAMES:
		case AUTO_ROTATE:
			return ![slidesWindow isMainWindow];
		default:
			return YES;
	}
}

- (IBAction)sortThumbnails:(id)sender {
	short int newSort, oldSort;
	oldSort = [frontWindow sortOrder];
	newSort = [sender tag] - 200;
	
	if (newSort == abs(oldSort)) {
		newSort = -oldSort; // reverse the sort if user selects it again
		[sender setState:newSort < 0 ? NSMixedState : NSOnState];
	} else {
		[sender setState:NSOnState];

		NSMenu *m = [[[NSApp mainMenu] itemWithTag:VIEW_MENU] submenu];
		[[m itemWithTag:newSort == 2 ? SORT_NAME : SORT_DATE_MODIFIED] setState:NSOffState];
	}
	[frontWindow setSortOrder:newSort];
}

- (IBAction)doShowFilenames:(id)sender {
	BOOL b = ![[frontWindow imageMatrix] showFilenames];
	[sender setState:b ? NSOnState : NSOffState];
	[[frontWindow imageMatrix] setShowFilenames:b];
	if ([creeveyWindows count] == 1) // save as default if this is the only window
		[[NSUserDefaults standardUserDefaults] setBool:b forKey:@"showFilenames"];
}

- (IBAction)doAutoRotateDisplayedImage:(id)sender {
	BOOL b = ![[frontWindow imageMatrix] autoRotate];
	[sender setState:b ? NSOnState : NSOffState];
	[[frontWindow imageMatrix] setAutoRotate:b];
}

#pragma mark prefs stuff
- (IBAction)openPrefWin:(id)sender; {
//	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
//	[startupDirFld setStringValue:[u stringForKey:@"picturesFolderPath"]];
//	int i, n = [u integerForKey:@"startupOption"];
//	for (i=0; i<2; ++i) {
//		[[startupOptionMatrix cellWithTag:i] setState:i==n];
//	}
    [prefsWin makeKeyAndOrderFront:nil];
}
- (IBAction)chooseStartupDir:(id)sender; {
    NSOpenPanel *op=[NSOpenPanel openPanel];
	
    [op setCanChooseDirectories:YES];
    [op setCanChooseFiles:NO];
    [op beginSheetForDirectory:[[NSUserDefaults standardUserDefaults] stringForKey:@"picturesFolderPath"]
						  file:NULL types:NULL
				modalForWindow:prefsWin modalDelegate:self
				didEndSelector:@selector(openPanelDidEnd:returnCode:contextInfo:)
				   contextInfo:NULL];
}
- (void)openPanelDidEnd:(NSOpenPanel *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo
{
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	if (returnCode == NSOKButton) {
		NSString *s = [[sheet filenames] objectAtIndex:0];
		//[startupDirFld setStringValue:s];
		[u setObject:s forKey:@"picturesFolderPath"];
		[u setInteger:1 forKey:@"startupOption"];
		//[[startupOptionMatrix cellWithTag:0] setState:0];
		//[[startupOptionMatrix cellWithTag:1] setState:1];
	}
	[sheet orderOut:self];
	[prefsWin makeKeyAndOrderFront:nil]; // otherwise unkeys
}

- (IBAction)changeStartupOption:(id)sender; {
//	[[NSUserDefaults standardUserDefaults] setInteger:[[sender selectedCell] tag]
//											   forKey:@"startupOption"];
}


- (IBAction)openAboutPanel:(id)sender {
	[NSApp orderFrontStandardAboutPanelWithOptions:
		[NSDictionary dictionaryWithObject:[NSImage imageNamed:@"logo"]
									forKey:@"ApplicationIcon"]];
}

- (IBAction)applySlideshowPrefs:(id)sender {
	// ** this code is inelegant, but whatever
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	NSMenu *m = [[[NSApp mainMenu] itemWithTag:SLIDESHOW_MENU] submenu];
	NSMenuItem *i;
	i = [m itemWithTag:LOOP];
	[i setState:![u boolForKey:@"slideshowLoop"]];
	[[i target] performSelector:[i action] withObject:i];
	
	i = [m itemWithTag:RANDOM_MODE];
	[i setState:![u boolForKey:@"slideshowRandom"]];
	[[i target] performSelector:[i action] withObject:i];

	i = [m itemWithTag:SLIDESHOW_SCALE_UP];
	[i setState:![u boolForKey:@"slideshowScaleUp"]];
	[[i target] performSelector:[i action] withObject:i];

	i = [m itemWithTag:SLIDESHOW_ACTUAL_SIZE];
	[i setState:![u boolForKey:@"slideshowActualSize"]];
	[[i target] performSelector:[i action] withObject:i];

	// auto-advance, since it can only be set during slideshow (and not in menu)
	// is automagically applied when slideshow starts
	[slidesWindow setAutoadvanceTime:[u boolForKey:@"slideshowAutoadvance"]
		? [u floatForKey:@"slideshowAutoadvanceTime"]
		: 0];
	
	// bg color is continuously set. it's cooler that way.
	// but we still need this for inital setup
	[slidesWindow setBackgroundColor:
		[NSKeyedUnarchiver unarchiveObjectWithData:[u dataForKey:@"slideshowBgColor"]]];


	[slideshowApplyBtn setEnabled:NO];
}

- (IBAction)slideshowDefaultsChanged:(id)sender; {
	[slideshowApplyBtn setEnabled:YES];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:(id)object 
                        change:(NSDictionary *)c
                       context:(void *)context
{
    if ([keyPath isEqual:@"values.slideshowAutoadvanceTime"]) {
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"slideshowAutoadvance"];
		[slideshowApplyBtn setEnabled:YES];
    } else if ([keyPath isEqual:@"values.DYWrappingMatrixMaxCellWidth"]) {
		if ([thumbsCache boundingWidth]
			< [[NSUserDefaults standardUserDefaults] integerForKey:@"DYWrappingMatrixMaxCellWidth"]) {
			[thumbsCache removeAllImages];
			[thumbsCache setBoundingSize:[DYWrappingMatrix maxCellSize]];
		}
    }
}

- (NSColor *)slideshowBgColor { // not actually used, i don't think, we always grab from user defaults
    return [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] dataForKey:@"slideshowBgColor"]];
}

- (void)setSlideshowBgColor:(NSColor *)value {
	[slidesWindow setBackgroundColor:value];
	[[slidesWindow contentView] setNeedsDisplay:YES];
	[[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:value]
											  forKey:@"slideshowBgColor"];
}


#pragma mark exif thumb
- (IBAction)toggleExifThumbnail:(id)sender {
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	int b =	![u boolForKey:@"exifThumbnailShow"];
	[self showExifThumbnail:b shrinkWindow:YES];
	[u setBool:b forKey:@"exifThumbnailShow"];
}

- (void)showExifThumbnail:(BOOL)b shrinkWindow:(BOOL)shrink {
	NSWindow *w = [exifThumbnailDiscloseBtn window];
	NSView *v = [w contentView];
	[exifThumbnailDiscloseBtn setState:b];
	b = !b;
	if ([[v viewWithTag:2] isHidden] != b) {
		NSRect r = [w frame];
		NSRect q;
		if (!shrink)
			q = [[exifTextView enclosingScrollView] frame]; // get the scrollview, not the textview
		if (b) { // hiding
			if (shrink) {
				r.size.height -= 160;
				r.origin.y += 160;
			} else
				q.size.height += 160;
			[[v viewWithTag:3] setHidden:b]; // text
			[[v viewWithTag:2] setHidden:b]; // imgview
			[[v viewWithTag:6] setHidden:b]; // popdown menu
		} else { // showing
			if (shrink) {
				r.size.height += 160;
				r.origin.y -= 160;
			} else
				q.size.height -= 160;
		}
		NSView *v2 = [exifTextView enclosingScrollView];
		if (!shrink)
			[v2 setFrame:q];
		else {
			unsigned int oldMask = [v2 autoresizingMask];
			[v2 setAutoresizingMask:NSViewMaxXMargin];
			[w setFrame:r display:YES animate:YES];
			[v2 setAutoresizingMask:oldMask];
		}
		if (!b) {
			[[v viewWithTag:3] setHidden:b]; // text
			[[v viewWithTag:2] setHidden:b]; // imgview
			[[v viewWithTag:6] setHidden:b]; // popdown menu
		}
	}
}


#pragma mark new window stuff
- (IBAction)openGetInfoPanel:(id)sender {
	NSWindow *w = [exifTextView window];
	if ([w isVisible])
		[w orderOut:self];
	else {
		[w orderFront:self];
		if ([creeveyWindows count]) [frontWindow updateExifInfo];
	}
}

- (IBAction)newWindow:(id)sender {
	if (![creeveyWindows count]) {
		if (exifWasVisible)
			[[exifTextView window] orderFront:self]; // only check for first window
	}
	id wc = [[CreeveyMainWindowController alloc] initWithWindowNibName:@"CreeveyWindow"];
	[creeveyWindows addObject:wc];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowClosed:) name:NSWindowWillCloseNotification object:[wc window]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowChanged:) name:NSWindowDidBecomeMainNotification object:[wc window]];
	[wc showWindow:nil]; // or override wdidload
	[[wc imageMatrix] setShowFilenames:[[NSUserDefaults standardUserDefaults] boolForKey:@"showFilenames"]];
	if (sender)
		[wc setDefaultPath];
}

- (void)windowClosed:(NSNotification *)n {
	id wc = [[n object] windowController];
	if ([creeveyWindows indexOfObjectIdenticalTo:wc] != NSNotFound) {
		frontWindow = nil; // ** in case something funny happens between her and wChanged?
		if ([creeveyWindows count] == 1) {
			[[creeveyWindows objectAtIndex:0] updateDefaults];
			if (exifWasVisible = [[exifTextView window] isVisible]) {
				[[exifTextView window] orderOut:nil];
			}
		}
		[[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:[wc window]];
		[creeveyWindows removeObject:wc];
		[wc autorelease]; // retained from newWindow:
	}
}

- (void)windowChanged:(NSNotification *)n {
	frontWindow = [[n object] windowController];
	
	short int sortOrder = [frontWindow sortOrder];
	NSMenu *m = [[[NSApp mainMenu] itemWithTag:VIEW_MENU] submenu];
	[[m itemWithTag:200+abs(sortOrder)] setState:sortOrder > 0 ? NSOnState : NSMixedState];
	[[m itemWithTag:abs(sortOrder) == 2 ? SORT_NAME : SORT_DATE_MODIFIED] setState:NSOffState];
	[[m itemWithTag:SHOW_FILE_NAMES] setState:[[frontWindow imageMatrix] showFilenames] ? NSOnState : NSOffState];
	[[m itemWithTag:AUTO_ROTATE] setState:[[frontWindow imageMatrix] autoRotate] ? NSOnState : NSOffState];
}

- (IBAction)versionCheck:(id)sender {
	if ([[DYVersChecker alloc] initWithNotify:YES])
		[[NSUserDefaults standardUserDefaults] setFloat:[NSDate timeIntervalSinceReferenceDate]
												 forKey:@"lastVersCheckTime"];
}
- (IBAction)sendFeedback:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://blyt.net/phxslides/feedback.html"]];
}

#pragma mark slideshow window delegate method
- (void)windowDidBecomeMain:(NSNotification *)aNotification {
	if ([creeveyWindows count] && (exifWasVisible = [[exifTextView window] isVisible]))
		[[exifTextView window] orderOut:nil];
	// only needed in case user cycles through windows; see startSlideshow above
}
- (void)windowDidResignMain:(NSNotification *)aNotification {
	// do this here, not in windowChanged, to avoid app switch problems
	if ([creeveyWindows count] && exifWasVisible)
		[[exifTextView window] orderFront:nil];
	if ([creeveyWindows count] && [[frontWindow currentSelection] count] <= 1) {
		NSArray *a = [frontWindow displayedFilenames];
		int i = [slidesWindow currentIndex];
		if (i < [a count]
			&& [[a objectAtIndex:i] isEqualToString:[slidesWindow currentFile]])
			[frontWindow selectIndex:i];
	}
}


- (DYImageCache *)thumbsCache { return thumbsCache; }
- (NSTextView *)exifTextView { return exifTextView; }
- (NSSet *)filetypes { return filetypes; }
- (NSMutableSet **)cats { return cats; }

@end
