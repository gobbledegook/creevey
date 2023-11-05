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

#import "DYWrappingMatrix.h"
#import "CreeveyMainWindowController.h"
#import "DYImageCache.h"
#import "SlideshowWindow.h"
#import "DYJpegtranPanel.h"
#import "DYVersChecker.h"
#import "DYExiftags.h"

#define MAX_THUMBS 2000
#define DYVERSCHECKINTERVAL 604800
#define MAX_FILES_TO_CHECK_FOR_JPEG 100

BOOL FilesContainJPEG(NSArray *paths) {
	// find out if at least one file is a JPEG
	if ([paths count] > MAX_FILES_TO_CHECK_FOR_JPEG) return YES; // but give up there's too many to check
	for (NSString *path in paths) {
		if (FileIsJPEG(path))
			return YES;
	}
	return NO;
}

#define TAB(x,y)	[[[NSTextTab alloc] initWithType:x location:y] autorelease]
NSMutableAttributedString* Fileinfo2EXIFString(NSString *origPath, DYImageCache *cache, BOOL moreExif) {
	id s, path;
	path = ResolveAliasToPath(origPath);
	s = [[NSMutableString alloc] init];
	[s appendString:[origPath lastPathComponent]];
	if (path != origPath)
		[s appendFormat:@"\n[%@->%@]", NSLocalizedString(@"Alias", @""), path];
	DYImageInfo *i = [cache infoForKey:origPath];
	if (!i) i = [cache infoForKey:path]; // if no info from the given path, try resolving the alias.
	if (i) {
		id exifStr = [DYExiftags tagsForFile:path moreTags:moreExif];
		[s appendFormat:@"\n%@ (%qu bytes)\n%@: %d %@: %d",
			FileSize2String(i->fileSize), i->fileSize,
			NSLocalizedString(@"Width", @""), (int)i->pixelSize.width,
			NSLocalizedString(@"Height", @""), (int)i->pixelSize.height];
		if (exifStr) {
			[s appendString:@"\n"];
			[s appendString:exifStr];
		}
	} else {
		unsigned long long fsize;
		fsize = [[[NSFileManager defaultManager] attributesOfItemAtPath:[path stringByResolvingSymlinksInPath] error:NULL] fileSize];
		// fsize will be 0 on error
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
		[styl setTabStops:@[TAB(NSRightTabStopType,x-5), TAB(NSLeftTabStopType,x)]];
		[styl setDefaultTabInterval:5];
		
		atts[NSParagraphStyleAttributeName] = styl;
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
	return [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:[v floatValue]+DYVERSCHECKINTERVAL]
										  dateStyle:NSDateFormatterLongStyle timeStyle:NSDateFormatterMediumStyle];
}
@end

@interface CreeveyController ()
@property (nonatomic, assign) BOOL appDidFinishLaunching;
@property (nonatomic, assign) BOOL filesWereOpenedAtLaunch;
@property (nonatomic, assign) BOOL windowsWereRestoredAtLaunch;
@end

@implementation CreeveyController

+(void)initialize
{
	if (self != [CreeveyController class]) return;

    NSMutableDictionary *dict;
    NSUserDefaults *defaults;
	
    defaults=[NSUserDefaults standardUserDefaults];
	
    dict=[NSMutableDictionary dictionary];
	NSString *s = CREEVEY_DEFAULT_PATH;
    dict[@"picturesFolderPath"] = s;
    dict[@"lastFolderPath"] = s;
    dict[@"startupOption"] = @0;
	dict[@"thumbCellWidth"] = @120.0f;
	dict[@"getInfoVisible"] = @NO;
	dict[@"autoVersCheck"] = @YES;
	dict[@"jpegPreserveModDate"] = @NO;
	dict[@"slideshowAutoadvance"] = @NO;
	dict[@"slideshowAutoadvanceTime"] = @5.25f;
	dict[@"slideshowLoop"] = @NO;
	dict[@"slideshowRandom"] = @NO;
	dict[@"slideshowScaleUp"] = @NO;
	dict[@"slideshowActualSize"] = @NO;
	dict[@"slideshowBgColor"] = [NSKeyedArchiver archivedDataWithRootObject:[NSColor blackColor]];
	dict[@"exifThumbnailShow"] = @NO;
	dict[@"showFilenames"] = @YES;
	dict[@"sortBy"] = @1; // sort by filename, ascending
	dict[@"Slideshow:RerandomizeOnLoop"] = @YES;
	dict[@"maxThumbsToLoad"] = @3000;
	dict[@"autoRotateByOrientationTag"] = @YES;
    [defaults registerDefaults:dict];

	// migrate old RBSplitView pref
	if (0.0 == [defaults floatForKey:@"MainWindowSplitViewTopHeight"]) {
		NSString *rbsplitviewvalue = [defaults stringForKey:@"RBSplitView H DividerLoc"];
		if (rbsplitviewvalue) {
			NSScanner *scanner = [NSScanner scannerWithString:rbsplitviewvalue];
			if ([scanner scanInt:NULL]) {
				int rbsplitviewheight;
				if ([scanner scanInt:&rbsplitviewheight])
					[defaults setFloat:(float)rbsplitviewheight forKey:@"MainWindowSplitViewTopHeight"];
			}
		}
		[defaults removeObjectForKey:@"com.ulikusterer.prefspanel.recentpage"];
	}

	id t = [[[TimeIntervalPlusWeekToStringTransformer alloc] init] autorelease];
	[NSValueTransformer setValueTransformer:t
									forName:@"TimeIntervalPlusWeekToStringTransformer"];
}

- (id)init {
	if (self = [super init]) {
		filetypes = [[NSMutableSet alloc] init];
		fileostypes = [[NSMutableSet alloc] init];
		disabledFiletypes = [[NSMutableSet alloc] init];
		filetypeDescriptions = [[NSMutableDictionary alloc] init];
		for (NSString *identifier in NSImage.imageUnfilteredTypes) {
			// easier to use UTType class from UniformTypeIdentifiers, but that's only available in macOS 11
			CFDictionaryRef t = UTTypeCopyDeclaration((CFStringRef)identifier);
			if (t == NULL) continue;
			CFDictionaryRef tags = CFDictionaryGetValue(t, kUTTypeTagSpecificationKey);
			if (tags) {
				NSArray *exts = CFDictionaryGetValue(tags, kUTTagClassFilenameExtension);
				if (exts) {
					[filetypes addObjectsFromArray:exts];
					NSString *description = CFDictionaryGetValue(t, kUTTypeDescriptionKey);
					if (description) for (NSString *ext in exts) {
						NSString *s = filetypeDescriptions[ext];
						filetypeDescriptions[ext] = s ? [s stringByAppendingFormat:@" / %@", description] : description;
					}
				}
				CFArrayRef ostypes = CFDictionaryGetValue(tags, kUTTagClassOSType);
				if (ostypes) for (NSString *s in (NSArray *)ostypes) {
					// enclose HFS file types in single quotes, e.g. "'PICT'"
					[fileostypes addObject:[NSString stringWithFormat:@"'%@'", s]];
				}
			}
			CFRelease(t);
		}
		fileextensions = [[filetypes.allObjects sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)] retain];
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
	[slidesWindow setAutoRotate:[[NSUserDefaults standardUserDefaults] boolForKey:@"autoRotateByOrientationTag"]];
	[disabledFiletypes addObjectsFromArray:[[NSUserDefaults standardUserDefaults] stringArrayForKey:@"ignoredFileTypes"]];
	for (NSString *type in disabledFiletypes) {
		[filetypes removeObject:type];
	}

	[[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
															  forKeyPath:@"values.slideshowAutoadvanceTime"
																 options:NSKeyValueObservingOptionNew
																 context:NULL];
	[[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
															  forKeyPath:@"values.DYWrappingMatrixMaxCellWidth"
																 options:0
																 context:NULL];
	localeChangeObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSCurrentLocaleDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
		NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
		[u setDouble:[u doubleForKey:@"lastVersCheckTime"] forKey:@"lastVersCheckTime"];
	}];
	screenChangeObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidChangeScreenParametersNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
		if ([slidesWindow isVisible]) {
			[slidesWindow resetScreen];
		}
	}];

	[[NSColorPanel sharedColorPanel] setShowsAlpha:YES]; // show color picker w/ opacity/transparency
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:localeChangeObserver];
	[[NSNotificationCenter defaultCenter] removeObserver:screenChangeObserver];
	[thumbsCache release];
	[filetypes release];
	[fileostypes release];
	[disabledFiletypes release];
	[fileextensions release];
	[filetypeDescriptions release];
	[creeveyWindows release];
    [_jpegController release];
    [_thumbnailContextMenu release];
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
		? [[frontWindow displayedFilenames] indexOfObject:files[0]]
			// here's a fun (and SLOW) linear search
		: NSNotFound];
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
	[slidesWindow setAutoRotate:[[frontWindow imageMatrix] autoRotate]];
	[slidesWindow startSlideshowAtIndex: [s count] == 1 ? [s firstIndex] : NSNotFound];
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
		if ([slidesWindow currentFile]) {
			NSString *s = [slidesWindow currentFile];
			[[NSWorkspace sharedWorkspace] selectFile:s inFileViewerRootedAtPath:[s stringByDeletingLastPathComponent]];
		} else {
			[[NSWorkspace sharedWorkspace] openFile:[slidesWindow basePath]];
		}
	} else {
		NSArray *a = [frontWindow currentSelection];
		if ([a count]) {
			NSMutableArray *b = [NSMutableArray arrayWithCapacity:[a count]];
			for (NSString *s in a) {
				[b addObject:[NSURL fileURLWithPath:s]];
			}
			[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:b];
		} else {
			[[NSWorkspace sharedWorkspace] openFile:[frontWindow path]];
		}
	}
}


- (IBAction)setDesktopPicture:(id)sender {
	NSString *s = [slidesWindow isMainWindow]
		? [slidesWindow currentFile]
		: [frontWindow currentSelection][0];
	NSError *error = nil;
	[[NSWorkspace sharedWorkspace] setDesktopImageURL:[NSURL fileURLWithPath:s]
											forScreen:[NSScreen mainScreen]
											  options:@{}
												error:&error];
	if (error)  {
		NSAlert *alert = [[NSAlert alloc] init];
		alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"Could not set the desktop because an error occurred. %@", @""), error.localizedDescription];
		[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
		[alert runModal];
		[alert release];
	};
}

// this is called "test" even though it works now.
// moral: name your functions correctly from the start.
- (IBAction)rotateTest:(id)sender {
	DYJpegtranInfo jinfo;
	NSInteger t = [sender tag] - 100;
	if (t == 0) {
		if (!self.jpegController)
			if (![[NSBundle mainBundle] loadNibNamed:@"DYJpegtranPanel" owner:self topLevelObjects:NULL]) return;
		if (![self.jpegController runOptionsPanel:&jinfo]) return;
	} else {
		jinfo.thumbOnly = t > 30;
		if (jinfo.thumbOnly) t -= 30;
		jinfo.tinfo.transform = t < DYJPEGTRAN_XFORM_PROGRESSIVE ? (JXFORM_CODE)t : JXFORM_NONE;
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
		NSAlert *alert = [[NSAlert alloc] init];
		alert.messageText = NSLocalizedString(@"Warning", @"");
		alert.informativeText = NSLocalizedString(@"This operation cannot be undone! Are you sure you want to continue?", @"");
		[alert addButtonWithTitle:NSLocalizedString(@"Continue", @"")];
		[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
		NSModalResponse response = [alert runModal];
		[alert release];
		if (response != NSAlertFirstButtonReturn)
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
		a = @[slidesFile];
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

	NSSize maxThumbSize = NSMakeSize(160,160);
	for (NSString *s in a) {
		NSString *resolvedPath = ResolveAliasToPath(s);
		if (FileIsJPEG(resolvedPath)) {
			if (jinfo.replaceThumb) {
				NSSize tmpSize;
				NSImage *i = [EpegWrapper imageWithPath:resolvedPath
											boundingBox:maxThumbSize
												getSize:&tmpSize
											  exifThumb:NO
										 getOrientation:NULL];
				if (i) {
					// assuming EpegWrapper always gives us a bitmap imagerep
					jinfo.newThumb = [(NSBitmapImageRep *)[i representations][0]
						representationUsingType:NSJPEGFileType
									 properties:@{NSImageCompressionFactor: @0.0f}
						];
					jinfo.newThumbSize = tmpSize;
					[i release];
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
		}
		if ([jpegProgressBar isIndeterminate]) {
			[jpegProgressBar stopAnimation:self];
			[jpegProgressBar setIndeterminate:NO];
		}
		[jpegProgressBar incrementBy:1];
		if ([NSApp runModalSession:session] != NSModalResponseContinue) break;
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
- (char)trashFile:(NSString *)fullpath numLeft:(NSUInteger)numFiles {
	NSURL *url = [NSURL fileURLWithPath:fullpath];
	NSError * _Nullable error = nil;
	[[NSFileManager defaultManager] trashItemAtURL:url resultingItemURL:nil error:&error];
	if (!error)
		return 1;
	NSAlert *alert = [[NSAlert alloc] init];
	alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The file %@ could not be moved to the trash because an error of %i occurred.", @""), fullpath.lastPathComponent, (int)error.code];
	[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
	if (numFiles > 1)
		[alert addButtonWithTitle:NSLocalizedString(@"Continue", @"")];
	NSModalResponse response = [alert runModal];
	[alert release];
	if (response == NSAlertFirstButtonReturn)
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
		NSUInteger oldIndex = [[frontWindow selectedIndexes] firstIndex];
		NSArray *a = [frontWindow currentSelection];
		NSUInteger i, n = [a count];
		// we have to go backwards b/c we're deleting from the imgMatrix
		// wait... we don't, because we're not using indexes anymore
		for (i=0; i < n; ++i) {
			NSString *fullpath = a[i];
			char result = (b ? [self trashFile:fullpath numLeft:n-i] : 1);
			if (result == 1) {
				[thumbsCache removeImageForKey:fullpath]; // we don't resolve alias here, but that's OK
				[creeveyWindows makeObjectsPerformSelector:@selector(fileWasDeleted:) withObject:fullpath];
				if ([slidesWindow isVisible])
					[slidesWindow removeImageForFile:fullpath];
			} else if (result == 2)
				break;
		}
		[frontWindow updateExifInfo];
		// no selection means all files were successfully deleted; select the next image if possible
		if ([[frontWindow selectedIndexes] firstIndex] == NSNotFound && oldIndex < [frontWindow displayedFilenames].count) {
			[frontWindow selectIndex:oldIndex];
		}
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
	_appDidFinishLaunching = YES;
	if (_windowsWereRestoredAtLaunch && _filesWereOpenedAtLaunch) {
		// ugly hack to force the slideshow window to be on top of the restored windows
		BOOL wasVisible = slidesWindow.isVisible;
		[slidesWindow orderFront:nil];
		if (!wasVisible) [slidesWindow orderOut:nil];
	}
	// open a new window if there isn't one (either from dropping icons onto app at launch, or from restoring saved state)
	if (!frontWindow && !_windowsWereRestoredAtLaunch)
		[self newWindow:self];

	[self applySlideshowPrefs:nil];
	
	NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate];
	if ([u boolForKey:@"autoVersCheck"]
		&& (t - [u doubleForKey:@"lastVersCheckTime"] > DYVERSCHECKINTERVAL)) // one week
		DYVersCheckForUpdateAndNotify(NO);
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


- (BOOL)application:(NSApplication *)sender
		   openFile:(NSString *)filename {
	if (![creeveyWindows count]) [self newWindow:nil];
	[frontWindow openFiles:@[filename] withSlideshow:YES];
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
	if (!_appDidFinishLaunching) {
		_filesWereOpenedAtLaunch = YES;
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


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	NSInteger t = [menuItem tag];
	NSInteger test_t = t;
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
	NSUInteger numSelected = frontWindow ? [[frontWindow selectedIndexes] count] : 0;
	BOOL writable, isjpeg;
	
	switch (test_t) {
		case MOVE_TO_TRASH:
		case JPEG_OP:
			// only when slides isn't loading cache!
			// only if writeable (we just test the first file in the list)
			writable = [slidesWindow isMainWindow]
				? [slidesWindow currentFile] &&
					[slidesWindow currentImageLoaded] &&
					[[NSFileManager defaultManager] isDeletableFileAtPath:
						[slidesWindow currentFile]]
				: numSelected > 0 && frontWindow && [frontWindow currentFilesDeletable];
			if (t == MOVE_TO_TRASH) return writable;
			
			isjpeg = [slidesWindow isMainWindow]
				? [slidesWindow currentFile] && FileIsJPEG([slidesWindow currentFile])
				: numSelected > 0 && frontWindow && FilesContainJPEG([frontWindow currentSelection]);
			
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
			return [slidesWindow isMainWindow]
				? ([slidesWindow currentFile] != nil)
				: numSelected == 1;
		case AUTO_ROTATE:
			return YES;
		case GET_INFO:
		case SORT_NAME:
		case SORT_DATE_MODIFIED:
		case SHOW_FILE_NAMES:
			return ![slidesWindow isMainWindow];
		default:
			return YES;
	}
}

- (void)updateMenuItemsForSorting:(short int)sortNum {
	short int sortType = abs(sortNum);
	BOOL sortAscending = sortNum > 0;
	NSMenu *m = [[[NSApp mainMenu] itemWithTag:VIEW_MENU] submenu];
	[[m itemWithTag:sortType == 2 ? SORT_NAME : SORT_DATE_MODIFIED] setState:NSOffState];
	[[m itemWithTag:200+sortType] setState:sortAscending ? NSOnState : NSMixedState];
}

- (IBAction)sortThumbnails:(id)sender {
	short int newSort, oldSort;
	oldSort = [frontWindow sortOrder];
	newSort = [sender tag] - 200;
	
	if (newSort == abs(oldSort)) {
		newSort = -oldSort; // reverse the sort if user selects it again
	} else {
		if (newSort == 2) newSort = -2; // default to reverse sort if sorting by date
	}
	[self updateMenuItemsForSorting:newSort];
	[frontWindow changeSortOrder:newSort];
	if ([creeveyWindows count] == 1) // save as default if this is the only window
		[[NSUserDefaults standardUserDefaults] setInteger:newSort forKey:@"sortBy"];
}

- (IBAction)doShowFilenames:(id)sender {
	BOOL b = ![[frontWindow imageMatrix] showFilenames];
	[sender setState:b ? NSOnState : NSOffState];
	[[frontWindow imageMatrix] setShowFilenames:b];
	if ([creeveyWindows count] == 1) // save as default if this is the only window
		[[NSUserDefaults standardUserDefaults] setBool:b forKey:@"showFilenames"];
}

- (IBAction)doAutoRotateDisplayedImage:(id)sender {
	BOOL b = [slidesWindow isMainWindow] ? ![slidesWindow autoRotate] : ![[frontWindow imageMatrix] autoRotate];
	[sender setState:b ? NSOnState : NSOffState];
	[[frontWindow imageMatrix] setAutoRotate:b];
	[slidesWindow setAutoRotate:b];
	if ([creeveyWindows count] == 1 || [slidesWindow isMainWindow])
		[[NSUserDefaults standardUserDefaults] setBool:b forKey:@"autoRotateByOrientationTag"];
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
	NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
	
    [op setCanChooseDirectories:YES];
    [op setCanChooseFiles:NO];
	[op setDirectoryURL:[NSURL fileURLWithPath:[u stringForKey:@"picturesFolderPath"] isDirectory:YES]];
	[op beginSheetModalForWindow:prefsWin completionHandler:^(NSInteger result) {
		if (result == NSModalResponseOK) {
			[u setObject:[[op URLs][0] path] forKey:@"picturesFolderPath"];
			[u setInteger:1 forKey:@"startupOption"];
		}
	}];
}

- (IBAction)changeStartupOption:(id)sender; {
//	[[NSUserDefaults standardUserDefaults] setInteger:[[sender selectedCell] tag]
//											   forKey:@"startupOption"];
}


- (IBAction)openAboutPanel:(id)sender {
	[NSApp orderFrontStandardAboutPanelWithOptions:@{@"ApplicationIcon": [NSImage imageNamed:@"logo"]}];
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
		dispatch_async(dispatch_get_main_queue(), ^{
			[slideshowApplyBtn setEnabled:YES];
		});
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
	BOOL b = ![u boolForKey:@"exifThumbnailShow"];
	[self showExifThumbnail:b shrinkWindow:YES];
	[u setBool:b forKey:@"exifThumbnailShow"];
}

- (void)showExifThumbnail:(BOOL)b shrinkWindow:(BOOL)shrink {
	NSWindow *w = [exifThumbnailDiscloseBtn window];
	NSView *v = [w contentView];
	NSImageView *imageView = [v viewWithTag:2];
	NSTextView *placeholderTextView = [v viewWithTag:3];
	NSPopUpButton *popdownMenu = [v viewWithTag:6];
	[exifThumbnailDiscloseBtn setState:b];
	b = !b;
	if ([imageView isHidden] != b) {
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
			[placeholderTextView setHidden:b];
			[imageView setHidden:b];
			for (NSLayoutConstraint *constraint in imageView.constraints) {
				if (constraint.firstAttribute == NSLayoutAttributeHeight)
					constraint.constant = 0;
			}
			[popdownMenu setHidden:b];
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
			NSUInteger oldMask = [v2 autoresizingMask];
			[v2 setAutoresizingMask:NSViewMaxXMargin];
			[w setFrame:r display:YES animate:YES];
			[v2 setAutoresizingMask:oldMask];
		}
		if (!b) {
			[placeholderTextView setHidden:b];
			[imageView setHidden:b];
			for (NSLayoutConstraint *constraint in imageView.constraints) {
				if (constraint.firstAttribute == NSLayoutAttributeHeight)
					constraint.constant = 160;
			}
			[popdownMenu setHidden:b];
		}
	}
}


#pragma mark new window stuff
+ (void)restoreWindowWithIdentifier:(NSString *)identifier
							  state:(NSCoder *)state
				  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler
{
	CreeveyController *appDelegate = (CreeveyController *)[NSApp delegate];
	[appDelegate newWindow:nil];
	CreeveyMainWindowController *wc = [appDelegate windowControllers].lastObject;
	completionHandler([wc window], nil);
	appDelegate.windowsWereRestoredAtLaunch = YES;
}
- (NSArray *)windowControllers { return creeveyWindows; }

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
	[wc release];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowClosed:) name:NSWindowWillCloseNotification object:[wc window]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowChanged:) name:NSWindowDidBecomeMainNotification object:[wc window]];
	[wc showWindow:nil]; // or override wdidload
	short int sortOrder = [[NSUserDefaults standardUserDefaults] integerForKey:@"sortBy"];
	[wc setSortOrder:sortOrder];
	[[wc imageMatrix] setShowFilenames:[[NSUserDefaults standardUserDefaults] boolForKey:@"showFilenames"]];
	[[wc imageMatrix] setAutoRotate:[[NSUserDefaults standardUserDefaults] boolForKey:@"autoRotateByOrientationTag"]];
	if (sender)
		[wc setDefaultPath];

	// make sure menu items are checked properly (code copied from windowChanged:)
	NSMenu *m = [[[NSApp mainMenu] itemWithTag:VIEW_MENU] submenu];
	[self updateMenuItemsForSorting:sortOrder];
	[[m itemWithTag:SHOW_FILE_NAMES] setState:[[wc imageMatrix] showFilenames] ? NSOnState : NSOffState];
	[[m itemWithTag:AUTO_ROTATE] setState:[[wc imageMatrix] autoRotate] ? NSOnState : NSOffState];
}

- (void)windowClosed:(NSNotification *)n {
	id wc = [[n object] windowController];
	if ([creeveyWindows indexOfObjectIdenticalTo:wc] != NSNotFound) {
		frontWindow = nil; // ** in case something funny happens between her and wChanged?
		if ([creeveyWindows count] == 1) {
			[creeveyWindows[0] updateDefaults];
			if ((exifWasVisible = [[exifTextView window] isVisible])) {
				[[exifTextView window] orderOut:nil];
			}
		}
		[[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:[wc window]];
		[creeveyWindows removeObject:wc];
	}
}

- (void)windowChanged:(NSNotification *)n {
	frontWindow = [[n object] windowController];
	
	short int sortOrder = [frontWindow sortOrder];
	NSMenu *m = [[[NSApp mainMenu] itemWithTag:VIEW_MENU] submenu];
	[self updateMenuItemsForSorting:sortOrder];
	[[m itemWithTag:SHOW_FILE_NAMES] setState:[[frontWindow imageMatrix] showFilenames] ? NSOnState : NSOffState];
	[[m itemWithTag:AUTO_ROTATE] setState:[[frontWindow imageMatrix] autoRotate] ? NSOnState : NSOffState];
}

- (IBAction)versionCheck:(id)sender {
	DYVersCheckForUpdateAndNotify(YES);
}
- (IBAction)sendFeedback:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://blyt.net/phxslides/feedback.html"]];
}

#pragma mark slideshow window delegate method
- (void)windowDidBecomeMain:(NSNotification *)aNotification {
	if ([creeveyWindows count] && (exifWasVisible = [[exifTextView window] isVisible]))
		[[exifTextView window] orderOut:nil];
	[[[[[NSApp mainMenu] itemWithTag:VIEW_MENU] submenu] itemWithTag:AUTO_ROTATE] setState:[slidesWindow autoRotate]];
	// only needed in case user cycles through windows; see startSlideshow above
}
- (void)windowDidResignMain:(NSNotification *)aNotification {
	// do this here, not in windowChanged, to avoid app switch problems
	if ([creeveyWindows count] && exifWasVisible)
		[[exifTextView window] orderFront:nil];
	if ([creeveyWindows count] && [[frontWindow currentSelection] count] <= 1) {
		NSArray *a = [frontWindow displayedFilenames];
		NSUInteger i = [slidesWindow currentIndex];
		if (i < [a count]
			&& [a[i] isEqualToString:[slidesWindow currentFile]])
			[frontWindow selectIndex:i];
	}
}


- (DYImageCache *)thumbsCache { return thumbsCache; }
- (NSTextView *)exifTextView { return exifTextView; }
- (NSMutableSet **)cats { return cats; }

- (BOOL)shouldShowFile:(NSString *)path {
	NSString *pathExtension = [path pathExtension];
	if (pathExtension.length == 0) return [fileostypes containsObject:NSHFSTypeOfFile(path)];
	return [filetypes containsObject:pathExtension] || [filetypes containsObject:[pathExtension lowercaseString]] || ([fileostypes containsObject:NSHFSTypeOfFile(path)] && ![disabledFiletypes containsObject:pathExtension]);
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return [fileextensions count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	if ([[tableColumn identifier] isEqualToString:@"enabled"]) return @([filetypes containsObject:fileextensions[row]]);
	if ([[tableColumn identifier] isEqualToString:@"description"]) return filetypeDescriptions[fileextensions[row]];
	return fileextensions[row];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	NSString *type = fileextensions[row];
	if ([object boolValue]) {
		[filetypes addObject:type];
		[disabledFiletypes removeObject:type];
	} else {
		[filetypes removeObject:type];
		[disabledFiletypes addObject:type];
	}
	[[NSUserDefaults standardUserDefaults] setObject:[disabledFiletypes allObjects] forKey:@"ignoredFileTypes"];
}

@end
