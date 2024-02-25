//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "CreeveyController.h"
#import "DYJpegtran.h"
#import "DYCarbonGoodies.h"

#import "DYWrappingMatrix.h"
#import "CreeveyMainWindowController.h"
#import "DYImageCache.h"
#import "SlideshowWindow.h"
#import "DYJpegtranPanel.h"
#import "DYVersChecker.h"
#import "DYExiftags.h"

// The thumbs cache should always store images using the resolved filename as the key.
// This prevents duplication somewhat, but it means when you look things up
// you need to make a call to ResolveAliasToPath.

#define MAX_THUMBS 2000
#define DYVERSCHECKINTERVAL 604800
#define MAX_FILES_TO_CHECK_FOR_JPEG 100

static BOOL FilesContainJPEG(NSArray *paths) {
	// find out if at least one file is a JPEG
	if (paths.count > MAX_FILES_TO_CHECK_FOR_JPEG) return YES; // but give up there's too many to check
	for (NSString *path in paths) {
		if (FileIsJPEG(path))
			return YES;
	}
	return NO;
}

#define TAB(x,y)	[[NSTextTab alloc] initWithType:x location:y]
NSMutableAttributedString* Fileinfo2EXIFString(NSString *origPath, DYImageCache *cache, BOOL moreExif) {
	NSString *path = ResolveAliasToPath(origPath);
	NSMutableString *s = [[NSMutableString alloc] init];
	[s appendString:origPath.lastPathComponent];
	if (path != origPath)
		[s appendFormat:@"\n[%@->%@]", NSLocalizedString(@"Alias", @""), path];
	DYImageInfo *i = [cache infoForKey:path];
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
		fsize = [[NSFileManager.defaultManager attributesOfItemAtPath:path.stringByResolvingSymlinksInPath error:NULL] fileSize];
		// fsize will be 0 on error
		[s appendFormat:@"\n%@ (%qu bytes)",
			FileSize2String(fsize), fsize];
	}
	
	static NSDictionary *atts;
	if (atts == nil) {
		float x = 160;
		NSMutableParagraphStyle *styl = [[NSMutableParagraphStyle alloc] init];
		styl.headIndent = x;
		styl.tabStops = @[TAB(NSRightTabStopType,x-5), TAB(NSLeftTabStopType,x)];
		styl.defaultTabInterval = 5;
		atts = @{
			NSFontAttributeName: [NSFont userFontOfSize:12],
			NSParagraphStyleAttributeName: styl,
		};
	}
	return [[NSMutableAttributedString alloc] initWithString:s attributes:atts];
}

@interface TimeIntervalPlusWeekToStringTransformer : NSValueTransformer
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
@property (nonatomic) BOOL appDidFinishLaunching;
@property (nonatomic) BOOL filesWereOpenedAtLaunch;
@property (nonatomic) BOOL windowsWereRestoredAtLaunch;
@end

@implementation CreeveyController
{
	NSMutableSet *cats[NUM_FNKEY_CATS];
	NSUserDefaults *catDefaults;
	BOOL exifWasVisible;

	NSMutableSet *filetypes;
	NSMutableSet *disabledFiletypes;
	NSMutableSet *fileostypes;
	NSArray *fileextensions;
	NSMutableDictionary *filetypeDescriptions;

	NSMutableArray *creeveyWindows;
	CreeveyMainWindowController * __weak frontWindow;
	NSArray *_prefWinNibItems;
	
	DYImageCache *thumbsCache;
	
	id localeChangeObserver;
	
	NSArray<NSURL*> *_movedUrls;
	NSArray<NSString*> *_originalPaths;

	NSMutableArray *_coalescedFilesToOpen;
}
@synthesize slidesWindow, jpegProgressBar, exifTextView, exifThumbnailDiscloseBtn, prefsWin, slideshowApplyBtn;

+(void)initialize
{
	if (self != [CreeveyController class]) return;

	dcraw_init();

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
	NSString *s = CREEVEY_DEFAULT_PATH;
	[defaults registerDefaults:@{
		@"picturesFolderPath": s,
		@"lastFolderPath": s,
		@"startupOption": @0,
		@"appearance": @0,
		@"thumbCellWidth": @120.0f,
		@"getInfoVisible": @NO,
		@"autoVersCheck": @YES,
		@"jpegPreserveModDate": @NO,
		@"slideshowAutoadvance": @NO,
		@"slideshowAutoadvanceTime": @5.5f,
		@"slideshowLoop": @NO,
		@"slideshowRandom": @NO,
		@"slideshowScaleUp": @NO,
		@"slideshowActualSize": @NO,
		@"slideshowBgColor": [NSKeyedArchiver archivedDataWithRootObject:NSColor.blackColor requiringSecureCoding:YES error:NULL],
		@"exifThumbnailShow": @NO,
		@"showFilenames": @YES,
		@"sortBy": @1, // sort by filename, ascending
		@"Slideshow:RerandomizeOnLoop": @YES,
		@"SlideshowSuppressLoopIndicator": @NO,
		@"maxThumbsToLoad": @100,
		@"autoRotateByOrientationTag": @YES,
		@"openFilesDoSlideshow": @YES,
		@"openFilesIgnoreAutoadvance": @NO,
		@"startupSlideshowFromFolder":@NO,
		@"startupSlideshowSubfolders":@NO,
		@"startupSlideshowSuppressNewWindows":@NO,
	}];

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

	[NSValueTransformer setValueTransformer:[[TimeIntervalPlusWeekToStringTransformer alloc] init]
									forName:@"TimeIntervalPlusWeekToStringTransformer"];
}

- (instancetype)init {
	if (self = [super init]) {
		filetypes = [[NSMutableSet alloc] init];
		fileostypes = [[NSMutableSet alloc] init];
		disabledFiletypes = [[NSMutableSet alloc] init];
		filetypeDescriptions = [[NSMutableDictionary alloc] init];
		for (NSString *identifier in NSImage.imageUnfilteredTypes) {
			// easier to use UTType class from UniformTypeIdentifiers, but that's only available in macOS 11
			CFDictionaryRef t = UTTypeCopyDeclaration((__bridge CFStringRef)identifier);
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
				if (ostypes) for (NSString *s in (__bridge NSArray *)ostypes) {
					// enclose HFS file types in single quotes, e.g. "'PICT'"
					[fileostypes addObject:[NSString stringWithFormat:@"'%@'", s]];
				}
			}
			CFRelease(t);
		}
		_revealedDirectories = [[NSMutableSet alloc] initWithObjects:[NSURL fileURLWithPath:(@"~/Desktop/").stringByResolvingSymlinksInPath isDirectory:YES], nil];
		fileextensions = [filetypes.allObjects sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
		creeveyWindows = [[NSMutableArray alloc] initWithCapacity:5];
		_coalescedFilesToOpen = [[NSMutableArray alloc] init];
		
		thumbsCache = [[DYImageCache alloc] initWithCapacity:MAX_THUMBS];
		thumbsCache.boundingSize = DYWrappingMatrix.maxCellSize;
		thumbsCache.fastThumbnails = YES;
		
		short int i;
		for (i=0; i<NUM_FNKEY_CATS; ++i) {
			cats[i] = [[NSMutableSet alloc] initWithCapacity:0];
		}
		catDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"net.blyt.phoenixslides.categories"];
		
		exifWasVisible = [NSUserDefaults.standardUserDefaults boolForKey:@"getInfoVisible"];
	}
    return self;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
	[(NSPanel *)exifTextView.window setBecomesKeyOnlyIfNeeded:YES];
	//[[exifTextView window] setHidesOnDeactivate:NO];
	// this causes problems b/c the window can be foregrounded without the app
	// coming to the front (oops)
	[slidesWindow setCats:cats];
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	slidesWindow.autoRotate = [u boolForKey:@"autoRotateByOrientationTag"];
	[disabledFiletypes addObjectsFromArray:[u stringArrayForKey:@"ignoredFileTypes"]];
	for (NSString *type in disabledFiletypes) {
		[filetypes removeObject:type];
	}
	[self updateMoveToMenuItem];
	[self updateAppearance];

	NSUserDefaultsController *ud = NSUserDefaultsController.sharedUserDefaultsController;
	[ud addObserver:self forKeyPath:@"values.slideshowBgColor" options:0 context:NULL];
	[ud addObserver:self forKeyPath:@"values.DYWrappingMatrixMaxCellWidth" options:0 context:NULL];
	[ud addObserver:self forKeyPath:@"values.appearance" options:0 context:NULL];
	localeChangeObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSCurrentLocaleDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
		[u setDouble:[u doubleForKey:@"lastVersCheckTime"] forKey:@"lastVersCheckTime"];
	}];
}

- (BOOL)macos1014available { if (@available(macOS 10.14, *)) return YES; return NO; }

- (void)dealloc {
	NSUserDefaultsController *u = NSUserDefaultsController.sharedUserDefaultsController;
	[u removeObserver:self forKeyPath:@"values.slideshowBgColor"];
	[u removeObserver:self forKeyPath:@"values.DYWrappingMatrixMaxCellWidth"];
	[u removeObserver:self forKeyPath:@"values.appearance"];
	[NSNotificationCenter.defaultCenter removeObserver:localeChangeObserver];
	short int i;
	for (i=0; i<NUM_FNKEY_CATS; ++i)
		cats[i] = nil;
}

- (void)slideshowFromAppOpen:(NSArray *)files {
	[self startSlideshowFullscreen:slidesWindow.visible ? slidesWindow.fullscreenMode : YES withFiles:files];
}

- (void)startSlideshowFullscreen:(BOOL)flag {
	[self startSlideshowFullscreen:flag withFiles:nil];
}

- (void)startSlideshowFullscreen:(BOOL)flag withFiles:(nullable NSArray *)files {
	slidesWindow.fullscreenMode = flag;
	BOOL wantsUpdates;
	NSUInteger startIdx = NSNotFound;
	if (files) {
		if ((wantsUpdates = files.count <= 1)) {
			if (files.count == 1) startIdx = [frontWindow indexOfFilename:files[0]];
			files = frontWindow.displayedFilenames;
		}
	} else {
		NSIndexSet *s = frontWindow.selectedIndexes;
		if ((wantsUpdates = s.count <= 1)) {
			files = frontWindow.displayedFilenames;
			if (s.count == 1) startIdx = s.firstIndex;
		} else {
			files = frontWindow.currentSelection;
		}
	}
	if (wantsUpdates) {
		[slidesWindow setFilenames:files basePath:frontWindow.path wantsSubfolders:frontWindow.wantsSubfolders comparator:frontWindow.comparator sortOrder:frontWindow.sortOrder];
	} else {
		[slidesWindow setFilenames:files basePath:frontWindow.path comparator:frontWindow.comparator sortOrder:frontWindow.sortOrder];
	}
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	slidesWindow.autoRotate = frontWindow.imageMatrix.autoRotate;
	// if files != nil these files are being opened from the finder, so check the relevant pref
	float aaInterval;
	if ([u boolForKey:@"slideshowAutoadvance"] && (files == nil || ![u boolForKey:@"openFilesIgnoreAutoadvance"]))
		aaInterval = [u floatForKey:@"slideshowAutoadvanceTime"];
	else
		aaInterval = 0;
	slidesWindow.autoadvanceTime = aaInterval;
	[slidesWindow startSlideshowAtIndex:startIdx];
}

- (IBAction)slideshow:(id)sender
{
	[self startSlideshowFullscreen:YES];
}

- (IBAction)slideshowInWindow:(id)sender {
	[self startSlideshowFullscreen:NO];
}

- (IBAction)openSelectedFiles:(id)sender {
	NSEvent *e = NSApp.currentEvent;
	[self startSlideshowFullscreen:!(e.modifierFlags & NSEventModifierFlagOption)];
}

- (IBAction)revealSelectedFilesInFinder:(id)sender {
	if (slidesWindow.isMainWindow) {
		if (slidesWindow.currentFile) {
			NSString *s = slidesWindow.currentFile;
			[NSWorkspace.sharedWorkspace selectFile:s inFileViewerRootedAtPath:s.stringByDeletingLastPathComponent];
		} else {
			[NSWorkspace.sharedWorkspace openFile:slidesWindow.basePath];
		}
	} else {
		NSArray *a = frontWindow.currentSelection;
		if (a.count) {
			NSMutableArray *b = [NSMutableArray arrayWithCapacity:a.count];
			for (NSString *s in a) {
				[b addObject:[NSURL fileURLWithPath:s isDirectory:NO]];
			}
			[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:b];
		} else {
			[NSWorkspace.sharedWorkspace openFile:frontWindow.path];
		}
	}
}


- (IBAction)setDesktopPicture:(id)sender {
	NSString *s = slidesWindow.isMainWindow
		? slidesWindow.currentFile
		: frontWindow.currentSelection[0];
	NSError * __autoreleasing error = nil;
	[NSWorkspace.sharedWorkspace setDesktopImageURL:[NSURL fileURLWithPath:s isDirectory:NO]
											forScreen:NSScreen.mainScreen
											  options:@{}
												error:&error];
	if (error)  {
		NSAlert *alert = [[NSAlert alloc] init];
		alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"Could not set the desktop because an error occurred. %@", @""), error.localizedDescription];
		[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
		[alert runModal];
	};
}

- (IBAction)transformJpeg:(id)sender {
	DYJpegtranInfo jinfo;
	NSInteger t = [sender tag] - 100;
	if (t == 0) {
		if (!self.jpegController)
			if (![NSBundle.mainBundle loadNibNamed:@"DYJpegtranPanel" owner:self topLevelObjects:NULL]) return;
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
		if (response != NSAlertFirstButtonReturn)
			return; // user cancelled
		jinfo.preserveModificationDate = jinfo.resetOrientation ? [NSUserDefaults.standardUserDefaults boolForKey:@"jpegPreserveModDate"]
																: NO;
										 // make an exception for reset orientation,
										 // since it doesn't _really_ change anything
	} else {
		jinfo.preserveModificationDate = [NSUserDefaults.standardUserDefaults boolForKey:@"jpegPreserveModDate"];
	}
	
	NSArray *a;
	DYImageInfo *imgInfo;
	BOOL slidesWasKey = slidesWindow.isMainWindow; // ** test for main is better than key
	BOOL autoRotate = YES; // set this to yes, if the browser is active and not autorotating we change it below. I.e., autorotate will be true if we're in a slideshow
	if (slidesWasKey) {
		NSString *slidesFile = slidesWindow.currentFile;
		a = @[slidesFile];
		// we need to get the current (viewing) orientation of the slide
		// we *don't* need to save the current cached thumbnail info since it's going to get deleted
		unsigned short orientation = slidesWindow.currentOrientation;
		if (orientation != 0) {
			imgInfo = [thumbsCache infoForKey:ResolveAliasToPath(slidesFile)];
			if (imgInfo)
				imgInfo->exifOrientation = slidesWindow.currentOrientation;
		}
	} else {
		a = frontWindow.currentSelection;
		autoRotate = frontWindow.imageMatrix.autoRotate;
	}
	
	jpegProgressBar.usesThreadedAnimation = YES;
	jpegProgressBar.indeterminate = YES;
	jpegProgressBar.doubleValue = 0;
	jpegProgressBar.maxValue = a.count;
	((NSButton *)[jpegProgressBar.window.contentView viewWithTag:1]).enabled = a.count > 1; // cancel btn
	NSModalSession session = [NSApp beginModalSessionForWindow:jpegProgressBar.window];
	[NSApp runModalSession:session];
	[jpegProgressBar startAnimation:self];

	for (NSString *s in a) {
		NSString *resolvedPath = ResolveAliasToPath(s);
		if (FileIsJPEG(resolvedPath)) {
			if (jinfo.replaceThumb) {
				NSSize tmpSize;
				NSData *i = [DYImageCache createNewThumbFromFile:resolvedPath getSize:&tmpSize];
				if (i) {
					jinfo.newThumb = i;
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
				[slidesWindow uncacheImage:s];
			} else {
				// ** fail silently
				//NSLog(@"rot failed!");
			}
		}
		if (jpegProgressBar.indeterminate) {
			[jpegProgressBar stopAnimation:self];
			jpegProgressBar.indeterminate = NO;
		}
		[jpegProgressBar incrementBy:1];
		if ([NSApp runModalSession:session] != NSModalResponseContinue) break;
	}
	[frontWindow updateExifInfo];

	[NSApp endModalSession:session];
	[jpegProgressBar.window orderOut:self];
}

- (IBAction)stopModal:(id)sender {
	[NSApp stopModal];
}

- (void)updateMoveToMenuItem {
	NSString *path = [NSUserDefaults.standardUserDefaults stringForKey:@"lastUsedMoveToFolder"];
	if (path == nil) return;
	NSMenu *m = [NSApp.mainMenu itemWithTag:FILE_MENU].submenu;
	NSMenuItem *item = [m itemWithTag:MOVE_TO_AGAIN];
	NSString *name = [NSFileManager.defaultManager displayNameAtPath:path];
	item.title = [NSString stringWithFormat:NSLocalizedString(@"Move to “%@” Again", @"File menu"), name];
}

- (void)moveSelectedFilesTo:(NSURL *)dest {
	NSString *curr = slidesWindow.isMainWindow ? slidesWindow.basePath : frontWindow.path;
	if ([dest isEqual:[NSURL fileURLWithPath:curr]]) return;

	NSArray *files = slidesWindow.isMainWindow ? @[slidesWindow.currentFile] : frontWindow.currentSelection;
	NSMutableArray<NSString*> *paths = [NSMutableArray array];
	NSMutableArray<NSURL*> *moved = [NSMutableArray arrayWithCapacity:files.count];
	NSMutableArray<NSString*> *notMoved = [NSMutableArray array];

	NSError * __autoreleasing err;
	for (NSString *f in files) {
		NSURL *destUrl = [dest URLByAppendingPathComponent:f.lastPathComponent];
		if ([NSFileManager.defaultManager moveItemAtPath:f toPath:destUrl.path error:&err]) {
			[paths addObject:f];
			[moved addObject:destUrl];
		} else {
			[notMoved addObject:f];
		}
	}
	if (notMoved.count) {
		NSAlert *alert = [[NSAlert alloc] init];
		if (notMoved.count == 1) {
			alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The file “%@” could not be moved because of an error: %@", @""), notMoved[0].lastPathComponent, err.localizedDescription];
		} else {
			alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"%lu files could not be moved because of an error.",@""), notMoved.count];
		}
		[alert runModal];
	}
	_originalPaths = [paths copy];
	_movedUrls = [moved copy];
	[self removePicsAndTrash:NO];
	[creeveyWindows makeObjectsPerformSelector:@selector(filesWereUndeleted:) withObject:[moved valueForKey:@"path"]];
}

- (IBAction)moveSelectedFiles:(id)sender {
	NSOpenPanel *op = [NSOpenPanel openPanel];
	op.canChooseFiles = NO;
	op.canChooseDirectories = YES;
	if ([op runModal] != NSModalResponseOK) return;
	NSURL *dest = op.URL;
	[self moveSelectedFilesTo:dest];
	[NSUserDefaults.standardUserDefaults setObject:dest.path forKey:@"lastUsedMoveToFolder"];
	[self updateMoveToMenuItem];
}

- (IBAction)moveSelectedFilesAgain:(id)sender {
	NSString *folder = [NSUserDefaults.standardUserDefaults stringForKey:@"lastUsedMoveToFolder"];
	NSURL *dest = [NSURL fileURLWithPath:folder isDirectory:YES];
	[self moveSelectedFilesTo:dest];
}

// returns 1 if successful
// unsuccessful: 0 user wants to continue; 2 cancel/abort
- (char)trashFile:(NSString *)fullpath numLeft:(NSUInteger)numFiles resultingURL:(NSURL **)newURL {
	NSURL *url = [NSURL fileURLWithPath:fullpath isDirectory:NO];
	NSError * __autoreleasing error = nil;
	[NSFileManager.defaultManager trashItemAtURL:url resultingItemURL:newURL error:&error];
	if (!error)
		return 1;
	NSAlert *alert = [[NSAlert alloc] init];
	alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The file %@ could not be moved to the trash because an error of %i occurred.", @""), fullpath.lastPathComponent, (int)error.code];
	[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
	if (numFiles > 1)
		[alert addButtonWithTitle:NSLocalizedString(@"Continue", @"")];
	NSModalResponse response = [alert runModal];
	if (response == NSAlertFirstButtonReturn)
		return 2;
	return 0;
}

// pass YES to move to trash; pass NO if this was a drag-to-Finder operation
- (void)removePicsAndTrash:(BOOL)doTrash {
	// *** to be more efficient, we should change the path in the cache instead of deleting it
	if (slidesWindow.isMainWindow) {
		NSString *s = slidesWindow.currentFile;
		NSURL *u;
		if (doTrash ? [self trashFile:s numLeft:1 resultingURL:&u] : (u = _movedUrls[0]) != nil) {
			[creeveyWindows makeObjectsPerformSelector:@selector(fileWasDeleted:) withObject:s];
			[thumbsCache removeImageForKey:s];
			[slidesWindow removeImageForFile:s];
			NSUInteger idx = slidesWindow.currentIndex;
			NSUndoManager *um = slidesWindow.undoManager;
			[um registerUndoWithTarget:self handler:^(id target) {
				NSError * __autoreleasing err;
				if ([NSFileManager.defaultManager moveItemAtPath:u.path toPath:s error:&err]) {
					if (slidesWindow.isMainWindow)
						[slidesWindow insertFile:s atIndex:idx];
					[creeveyWindows makeObjectsPerformSelector:@selector(filesWereUndeleted:) withObject:@[s]];
					if (!doTrash) {
						[creeveyWindows makeObjectsPerformSelector:@selector(fileWasDeleted:) withObject:u.path];
						if (slidesWindow.isMainWindow)
							[slidesWindow removeImageForFile:u.path];
					}
				} else {
					NSAlert *alert = [[NSAlert alloc] init];
					alert.informativeText = [NSString stringWithFormat:doTrash ? NSLocalizedString(@"The file \"%@\" could not be restored from the trash because of an error: %@", @"") : NSLocalizedString(@"The file “%@” could not be moved because of an error: %@", @""), s.lastPathComponent, err.localizedDescription];
					[alert runModal];
				}
			}];
			[um setActionName:[NSString stringWithFormat:doTrash ? NSLocalizedString(@"Move to Trash",@"") : NSLocalizedString(@"Move File",@"for undo")]];
		}
	} else {
		NSUInteger oldIndex = frontWindow.selectedIndexes.firstIndex;
		NSArray *selectedPaths = frontWindow.currentSelection;
		NSUInteger n = selectedPaths.count;
		NSMutableArray<NSArray *> *trashedFiles = [NSMutableArray arrayWithCapacity:n];
		for (NSUInteger i=0; i < n; ++i) {
			NSString *fullpath = selectedPaths[i];
			NSURL * __autoreleasing newURL;
			char result = (doTrash ? [self trashFile:fullpath numLeft:n-i resultingURL:&newURL] : 1);
			if (result == 1) {
				[thumbsCache removeImageForKey:fullpath]; // we don't resolve alias here, but that's OK
				[creeveyWindows makeObjectsPerformSelector:@selector(fileWasDeleted:) withObject:fullpath];
				if (slidesWindow.visible)
					[slidesWindow removeImageForFile:fullpath];
				if (doTrash)
					[trashedFiles addObject:@[fullpath, newURL]]; // this is a pair representing the old and new file locations
			} else if (result == 2)
				break;
		}
		NSUndoManager *um = frontWindow.window.undoManager;
		n = trashedFiles.count;
		if (n) {
			[um registerUndoWithTarget:self handler:^(id target) {
				NSMutableArray *moved = [NSMutableArray arrayWithCapacity:n];
				for (NSArray *a in trashedFiles) {
					if ([NSFileManager.defaultManager moveItemAtPath:[a[1] path] toPath:a[0] error:NULL])
						[moved addObject:a[0]];
				}
				[creeveyWindows makeObjectsPerformSelector:@selector(filesWereUndeleted:) withObject:moved];
				if (slidesWindow.visible)
					[slidesWindow filesWereUndeleted:moved];
				if (moved.count < n) {
					NSAlert *alert = [[NSAlert alloc] init];
					alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"%lu file(s) could not be restored from the trash because of an error. You should probably check your Trash.",@""), n-moved.count];
					[alert runModal];
				}
			}];
			[um setActionName:[NSString stringWithFormat:NSLocalizedString(@"Move to Trash (%lu File(s))",@"for undo"), n]];
		} else if (!doTrash) {
			NSArray<NSURL *> *urls = _movedUrls; // nonmutable copy, suitable to be captured by block below
			// these are file reference URLs so we will be able to resolve the new paths
			n = urls.count;
			if (n) {
				NSArray *paths = _originalPaths;
				[um registerUndoWithTarget:self handler:^(id target) {
					NSMutableArray *moved = [NSMutableArray arrayWithCapacity:n];
					for (NSUInteger i=0; i<n; ++i) {
						NSString *fromPath = urls[i].path;
						if ([NSFileManager.defaultManager moveItemAtPath:fromPath toPath:paths[i] error:NULL]) {
							[moved addObject:paths[i]];
							[creeveyWindows makeObjectsPerformSelector:@selector(fileWasDeleted:) withObject:fromPath];
							if (slidesWindow.visible)
								[slidesWindow removeImageForFile:fromPath];
						}
					}
					[creeveyWindows makeObjectsPerformSelector:@selector(filesWereUndeleted:) withObject:moved];
					if (slidesWindow.visible)
						[slidesWindow filesWereUndeleted:moved];
					if (moved.count < n) {
						NSAlert *alert = [[NSAlert alloc] init];
						alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"%lu file(s) could not be moved back because of an error.",@""), n-moved.count];
						[alert runModal];
					}
				}];
				[um setActionName:[NSString stringWithFormat:NSLocalizedString(@"Move Files (%lu File(s))",@"for undo"), n]];
			}
		}
		[frontWindow updateExifInfo];
		// no selection means all files were successfully deleted; select the next image if possible
		if (frontWindow.selectedIndexes.firstIndex == NSNotFound && oldIndex < frontWindow.displayedFilenames.count) {
			[frontWindow selectIndex:oldIndex];
		}
	}
}

- (IBAction)moveToTrash:(id)sender {
	[self removePicsAndTrash:YES];
}

#pragma mark matrix view methods

- (void)moveElsewhere {
	_movedUrls = frontWindow.imageMatrix.movedUrls;
	_originalPaths = frontWindow.imageMatrix.originPaths;
	[self removePicsAndTrash:NO];
}

- (unsigned short)exifOrientationForFile:(NSString *)s {
	NSString *path = ResolveAliasToPath(s);
	DYImageInfo *i = [thumbsCache infoForKey:path];
	return i ? i->exifOrientation : [DYExiftags orientationForFile:path];
}

#pragma mark app delegate methods

- (BOOL)slideshowFromStartupPreference {
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	NSString *path = [u integerForKey:@"startupOption"] == 0 ? [u stringForKey:@"lastFolderPath"] : [u stringForKey:@"picturesFolderPath"];
	BOOL isDir;
	if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir] && isDir) {
		BOOL fullScreen = ![u boolForKey:@"startupSlideshowInWindow"];
		short int sortOrder = [u integerForKey:@"sortBy"];
		[slidesWindow loadFilenamesFromPath:path fullScreen:fullScreen wantsSubfolders:[u boolForKey:@"startupSlideshowSubfolders"] comparator:ComparatorForSortOrder(sortOrder) sortOrder:sortOrder];
		return YES;
	}
	return NO;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	[self showExifThumbnail:[u boolForKey:@"exifThumbnailShow"]
			   shrinkWindow:NO];
	
	_appDidFinishLaunching = YES;
	if (_windowsWereRestoredAtLaunch && _filesWereOpenedAtLaunch) {
		// ugly hack to force the slideshow window to be on top of the restored windows
		BOOL wasVisible = slidesWindow.isVisible;
		[slidesWindow orderFront:nil];
		if (!wasVisible) [slidesWindow orderOut:nil];
	}

	[self applySlideshowPrefs:nil];
	[self updateSlideshowBgColor];
	BOOL doSlideshow = [u boolForKey:@"startupSlideshowFromFolder"];
	BOOL suppressNewWindow = doSlideshow && [u boolForKey:@"startupSlideshowSuppressNewWindows"];
	if (doSlideshow) {
		if (![self slideshowFromStartupPreference]) {
			// fail silently and open a new window if necessary
			suppressNewWindow = NO;
		}
	}

	// open a new window if there isn't one (either from dropping icons onto app at launch, or from restoring saved state)
	if (!frontWindow && !_windowsWereRestoredAtLaunch && !suppressNewWindow)
		[self newWindow:self];

	NSTimeInterval t = NSDate.timeIntervalSinceReferenceDate;
	if ([u boolForKey:@"autoVersCheck"]
		&& (t - [u doubleForKey:@"lastVersCheckTime"] > DYVERSCHECKINTERVAL)) // one week
		DYVersCheckForUpdateAndNotify(NO);

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
		// because screw thread safety
		@autoreleasepool {
			NSArray<NSArray *> *savedCats = [catDefaults arrayForKey:@"cats"];
			short i = 0;
			for (NSArray *a in savedCats) {
				NSMutableArray *readable = [NSMutableArray arrayWithCapacity:a.count];
				for (NSString *path in a) {
					if (0 == access(path.fileSystemRepresentation, R_OK))
						[readable addObject:path];
				}
				[cats[i++] addObjectsFromArray:readable];
			}
			[self updateCats];
		}
	});
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	if (creeveyWindows.count)
		[frontWindow updateDefaults];
	[u setBool:(slidesWindow.isMainWindow || creeveyWindows.count == 0) ? exifWasVisible : exifTextView.window.visible
		forKey:@"getInfoVisible"];
	[u synchronize];
}

- (void)openFilesCoalesced {
	BOOL doSlideshow = [NSUserDefaults.standardUserDefaults boolForKey:@"openFilesDoSlideshow"];
	[frontWindow openFiles:_coalescedFilesToOpen withSlideshow:doSlideshow];
	[_coalescedFilesToOpen removeAllObjects];
}

- (void)openFiles:(NSArray *)files {
	if (!creeveyWindows.count) [self newWindow:nil];
	[frontWindow.window makeKeyAndOrderFront:nil];
	if (!_appDidFinishLaunching)
		_filesWereOpenedAtLaunch = YES;
	[_coalescedFilesToOpen addObjectsFromArray:files];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[self performSelector:@selector(openFilesCoalesced) withObject:nil afterDelay:0.5];
}

- (BOOL)application:(NSApplication *)sender
		   openFile:(NSString *)filename {
	[self openFiles:@[filename]];
	return YES;
}

- (void)application:(NSApplication *)sender
		  openFiles:(NSArray *)files {
	[self openFiles:files];
	[sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag {
	if (!creeveyWindows.count) {
		NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
		if ([u boolForKey:@"startupSlideshowFromFolder"]) {
			if ([self slideshowFromStartupPreference])
				if ([u boolForKey:@"startupSlideshowSuppressNewWindows"])
					return NO;
		}
		[self newWindow:self];
		return NO;
	}
	return YES;
}

-(void)applicationDidChangeScreenParameters:(NSNotification *)notification {
	if (slidesWindow.visible)
		[slidesWindow resetScreen];
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
	NEW_TAB,
	BEGIN_SLIDESHOW_IN_WINDOW,
	MOVE_TO,
	MOVE_TO_AGAIN,
	JPEG_OP = 100,
	ROTATE_L = 107,
	ROTATE_R = 105,
	EXIF_ORIENT_ROTATE = 113,
	EXIF_ORIENT_RESET = 114,
	EXIF_THUMB_DELETE = 116,
	ROTATE_SAVE = 117,
	SORT_NAME = 201,
	SORT_DATE_MODIFIED = 202,
	SORT_EXIF_DATE = 203,
	SHOW_FILE_NAMES = 251,
	AUTO_ROTATE = 261,
	SLIDESHOW_MENU = 1001,
	VIEW_MENU = 200,
	FILE_MENU = 300,
};


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	NSInteger t = menuItem.tag;
	NSInteger test_t = t;
	if (!NSApp.mainWindow) {
		// menu items with tags only enabled if there's a window
		return !t;
	}
	if (t>JPEG_OP && t < SORT_NAME) {
		if ((t > JPEG_OP + 30 || t == EXIF_THUMB_DELETE) &&
			!menuItem.menu.supermenu && // only for contextual menu
			![[exifThumbnailDiscloseBtn.window.contentView viewWithTag:2] image]) {
			return NO;
		}
		test_t = JPEG_OP;
	}
	if (!creeveyWindows.count) frontWindow = nil;
	NSUInteger numSelected = frontWindow ? frontWindow.selectedIndexes.count : 0;
	BOOL writable, isjpeg;
	NSString *moveTo;
	
	switch (test_t) {
		case NEW_TAB:
			return frontWindow.window.isMainWindow;
		case MOVE_TO_AGAIN:
			moveTo = [NSUserDefaults.standardUserDefaults stringForKey:@"lastUsedMoveToFolder"];
			// fall through
		case MOVE_TO:
		case MOVE_TO_TRASH:
		case JPEG_OP:
			// only when slides isn't loading cache!
			// only if writeable (we just test the first file in the list)
			writable = slidesWindow.isMainWindow
				? slidesWindow.currentFile &&
					slidesWindow.currentImageLoaded &&
					[NSFileManager.defaultManager isDeletableFileAtPath:
					 slidesWindow.currentFile]
				: numSelected > 0 && frontWindow && frontWindow.currentFilesDeletable;
			if (t != JPEG_OP) return writable && (t == MOVE_TO_AGAIN ? moveTo != nil : YES);
			
			isjpeg = slidesWindow.isMainWindow
				? slidesWindow.currentFile && FileIsJPEG(slidesWindow.currentFile)
				: numSelected > 0 && frontWindow && FilesContainJPEG(frontWindow.currentSelection);
			
			if (t == ROTATE_SAVE) { // only allow saving rotations during the slideshow
				return writable && isjpeg && slidesWindow.isMainWindow
				&& slidesWindow.currentOrientation > 1;
			}
			if ((t == EXIF_ORIENT_ROTATE || t == EXIF_ORIENT_RESET) && slidesWindow.isMainWindow) {
				return writable && isjpeg && slidesWindow.currentFileExifOrientation > 1;
			}
			return writable && isjpeg;
		case REVEAL_IN_FINDER:
			return YES;
		case BEGIN_SLIDESHOW:
		case BEGIN_SLIDESHOW_IN_WINDOW:
			if (slidesWindow.isMainWindow ) return NO;
			return frontWindow && frontWindow.filenamesDone && frontWindow.displayedFilenames.count;
		case SET_DESKTOP:
			return slidesWindow.isMainWindow
				? (slidesWindow.currentFile != nil)
				: numSelected == 1;
		case AUTO_ROTATE:
			return YES;
		case GET_INFO:
		case SORT_NAME:
		case SORT_DATE_MODIFIED:
		case SORT_EXIF_DATE:
		case SHOW_FILE_NAMES:
			return !slidesWindow.isMainWindow;
		default:
			return YES;
	}
}

- (void)updateMenuItemsForSorting:(short int)sortNum {
	short int sortType = abs(sortNum);
	NSInteger tag = 200 + sortType;
	NSMenu *m = [NSApp.mainMenu itemWithTag:VIEW_MENU].submenu;
	for (NSInteger i = 201; i <= SORT_EXIF_DATE; ++i) {
		NSMenuItem *item = [m itemWithTag:i];
		if (i == tag) {
			item.state = sortNum > 0 ? NSOnState : NSMixedState;
		} else {
			item.state = NSOffState;
		}
	}
}

- (IBAction)sortThumbnails:(id)sender {
	short int newSort, oldSort;
	oldSort = frontWindow.sortOrder;
	newSort = [sender tag] - 200;
	
	if (newSort == abs(oldSort)) {
		newSort = -oldSort; // reverse the sort if user selects it again
	} else {
		if (newSort == 2) newSort = -2; // default to reverse sort if sorting by date
	}
	[self updateMenuItemsForSorting:newSort];
	[frontWindow changeSortOrder:newSort];
	if (creeveyWindows.count == 1) // save as default if this is the only window
		[NSUserDefaults.standardUserDefaults setInteger:newSort forKey:@"sortBy"];
}

- (IBAction)doShowFilenames:(id)sender {
	BOOL b = !frontWindow.imageMatrix.showFilenames;
	NSMenuItem *item = sender;
	item.state = b;
	frontWindow.imageMatrix.showFilenames = b;
	if (creeveyWindows.count == 1) // save as default if this is the only window
		[NSUserDefaults.standardUserDefaults setBool:b forKey:@"showFilenames"];
}

- (IBAction)doAutoRotateDisplayedImage:(id)sender {
	BOOL b = slidesWindow.isMainWindow ? !slidesWindow.autoRotate : !frontWindow.imageMatrix.autoRotate;
	NSMenuItem *item = sender;
	item.state = b;
	frontWindow.imageMatrix.autoRotate = b;
	slidesWindow.autoRotate = b;
	if (creeveyWindows.count == 1 || slidesWindow.isMainWindow)
		[NSUserDefaults.standardUserDefaults setBool:b forKey:@"autoRotateByOrientationTag"];
}

#pragma mark prefs stuff
- (IBAction)openPrefWin:(id)sender; {
	if (!prefsWin) {
		NSArray * __autoreleasing arr;
		if (![NSBundle.mainBundle loadNibNamed:@"PrefsWin" owner:self topLevelObjects:&arr]) return;
		_prefWinNibItems = arr;
	}
    [prefsWin makeKeyAndOrderFront:nil];
}
- (IBAction)chooseStartupDir:(id)sender; {
    NSOpenPanel *op=[NSOpenPanel openPanel];
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	
    op.canChooseDirectories = YES;
    op.canChooseFiles = NO;
	op.directoryURL = [NSURL fileURLWithPath:[u stringForKey:@"picturesFolderPath"] isDirectory:YES];
	[op beginSheetModalForWindow:prefsWin completionHandler:^(NSInteger result) {
		if (result == NSModalResponseOK) {
			[u setObject:(op.URLs[0]).path forKey:@"picturesFolderPath"];
			[u setInteger:1 forKey:@"startupOption"];
		}
	}];
}

- (IBAction)openAboutPanel:(id)sender {
	[NSApp orderFrontStandardAboutPanelWithOptions:@{@"ApplicationIcon": [NSImage imageNamed:@"logo"]}];
}

// avoid warning "PerformSelector may cause a leak because its selector is unknown"
// ARC can't handle performSelector: with an unknown selector, so we explicitly convert the selector to a C function
static void SendAction(NSMenuItem *sender) {
	id target = sender.target;
	if (target) {
		SEL action = sender.action;
		void (*func)(id, SEL, id) = (void *)[target methodForSelector:action];
		func(target, action, sender);
	}
}

// This gets called in three circumstances: (1) at startup, to set up our menu/slideshow window,
// (2) always, when the slideshow window is closed and a setting is changed, and
// (3) when the "Apply" button is clicked (only enabled when the slideshow window is visible)
- (IBAction)applySlideshowPrefs:(id)sender {
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	NSMenu *m = [NSApp.mainMenu itemWithTag:SLIDESHOW_MENU].submenu;
	NSMenuItem *i;
	i = [m itemWithTag:LOOP];
	i.state = ![u boolForKey:@"slideshowLoop"];
	SendAction(i);
	
	i = [m itemWithTag:RANDOM_MODE];
	i.state = ![u boolForKey:@"slideshowRandom"];
	SendAction(i);

	i = [m itemWithTag:SLIDESHOW_SCALE_UP];
	i.state = ![u boolForKey:@"slideshowScaleUp"];
	SendAction(i);

	i = [m itemWithTag:SLIDESHOW_ACTUAL_SIZE];
	i.state = ![u boolForKey:@"slideshowActualSize"];
	SendAction(i);

	if (slidesWindow.visible) {
		slidesWindow.autoadvanceTime = [u boolForKey:@"slideshowAutoadvance"] ? [u floatForKey:@"slideshowAutoadvanceTime"] : 0;
		[slidesWindow updateTimer];
	}
	
	slideshowApplyBtn.enabled = NO;
}

- (void)updateSlideshowBgColor {
	slidesWindow.backgroundColor = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSColor class] fromData:[NSUserDefaults.standardUserDefaults dataForKey:@"slideshowBgColor"] error:NULL];
}

- (void)updateAppearance {
	if (@available(macOS 10.14, *)) {
		switch ([NSUserDefaults.standardUserDefaults integerForKey:@"appearance"]) {
			case 1: NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua]; break;
			case 2: NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]; break;
			default: NSApp.appearance = nil; break;
		}
	}
}

- (IBAction)slideshowDefaultsChanged:(id)sender; {
	if (slidesWindow.visible)
		slideshowApplyBtn.enabled = YES;
	else
		[self applySlideshowPrefs:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:(id)object 
                        change:(NSDictionary *)c
                       context:(void *)context
{
    if ([keyPath isEqual:@"values.DYWrappingMatrixMaxCellWidth"]) {
		if (thumbsCache.boundingWidth
			< [NSUserDefaults.standardUserDefaults integerForKey:@"DYWrappingMatrixMaxCellWidth"]) {
			[thumbsCache removeAllImages];
			thumbsCache.boundingSize = [DYWrappingMatrix maxCellSize];
		}
	} else if ([keyPath isEqualToString:@"values.slideshowBgColor"]) {
		[self updateSlideshowBgColor];
		[slidesWindow.contentView setNeedsDisplay:YES];
	} else if ([keyPath isEqualToString:@"values.appearance"]) {
		[self updateAppearance];
	}
}


#pragma mark exif thumb
- (IBAction)toggleExifThumbnail:(id)sender {
	NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
	BOOL b = ![u boolForKey:@"exifThumbnailShow"];
	[self showExifThumbnail:b shrinkWindow:YES];
	[u setBool:b forKey:@"exifThumbnailShow"];
}

- (void)showExifThumbnail:(BOOL)b shrinkWindow:(BOOL)shrink {
	NSWindow *w = exifThumbnailDiscloseBtn.window;
	NSView *v = w.contentView;
	NSImageView *imageView = [v viewWithTag:2];
	NSTextView *placeholderTextView = [v viewWithTag:3];
	NSPopUpButton *popdownMenu = [v viewWithTag:6];
	exifThumbnailDiscloseBtn.state = b;
	b = !b;
	if (imageView.hidden != b) {
		NSRect r = w.frame;
		NSRect q;
		if (!shrink)
			q = exifTextView.enclosingScrollView.frame; // get the scrollview, not the textview
		if (b) { // hiding
			if (shrink) {
				r.size.height -= 160;
				r.origin.y += 160;
			} else
				q.size.height += 160;
			placeholderTextView.hidden = b;
			imageView.hidden = b;
			for (NSLayoutConstraint *constraint in imageView.constraints) {
				if (constraint.firstAttribute == NSLayoutAttributeHeight)
					constraint.constant = 0;
			}
			popdownMenu.hidden = b;
		} else { // showing
			if (shrink) {
				r.size.height += 160;
				r.origin.y -= 160;
			} else
				q.size.height -= 160;
		}
		NSView *v2 = exifTextView.enclosingScrollView;
		if (!shrink)
			v2.frame = q;
		else {
			NSUInteger oldMask = v2.autoresizingMask;
			v2.autoresizingMask = NSViewMaxXMargin;
			[w setFrame:r display:YES animate:YES];
			v2.autoresizingMask = oldMask;
		}
		if (!b) {
			placeholderTextView.hidden = b;
			imageView.hidden = b;
			for (NSLayoutConstraint *constraint in imageView.constraints) {
				if (constraint.firstAttribute == NSLayoutAttributeHeight)
					constraint.constant = 160;
			}
			popdownMenu.hidden = b;
		}
	}
}


#pragma mark new window stuff
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
	// opt in to secure behavior in macOS 12 and later. See the AppKit release notes for macOS 14.
	return YES;
}
+ (void)restoreWindowWithIdentifier:(NSString *)identifier
							  state:(NSCoder *)state
				  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler
{
	CreeveyController *appDelegate = (CreeveyController *)NSApp.delegate;
	[appDelegate newWindow:nil];
	CreeveyMainWindowController *wc = [appDelegate windowControllers].lastObject;
	completionHandler(wc.window, nil);
	appDelegate.windowsWereRestoredAtLaunch = YES;
}
- (NSArray *)windowControllers { return creeveyWindows; }

- (IBAction)openGetInfoPanel:(id)sender {
	NSWindow *w = exifTextView.window;
	if (w.visible)
		[w orderOut:self];
	else {
		[w orderFront:self];
		if (creeveyWindows.count) [frontWindow updateExifInfo];
	}
}

- (void)newWindow:(BOOL)asTab init:(BOOL)needsPath {
	if (!creeveyWindows.count) {
		if (exifWasVisible)
			[exifTextView.window orderFront:self]; // only check for first window
	}
	CreeveyMainWindowController *wc = [[CreeveyMainWindowController alloc] initWithWindowNibName:@"CreeveyWindow"];
	[creeveyWindows addObject:wc];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowClosed:) name:NSWindowWillCloseNotification object:wc.window];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowChanged:) name:NSWindowDidBecomeMainNotification object:wc.window];
	if (asTab)
		[frontWindow.window addTabbedWindow:wc.window ordered:NSWindowAbove];
	[wc showWindow:nil]; // or override wdidload
	short int sortOrder = [NSUserDefaults.standardUserDefaults integerForKey:@"sortBy"];
	wc.sortOrder = sortOrder;
	wc.imageMatrix.showFilenames = [NSUserDefaults.standardUserDefaults boolForKey:@"showFilenames"];
	wc.imageMatrix.autoRotate = [NSUserDefaults.standardUserDefaults boolForKey:@"autoRotateByOrientationTag"];
	if (needsPath)
		[wc setDefaultPath];

	// make sure menu items are checked properly (code copied from windowChanged:)
	NSMenu *m = [NSApp.mainMenu itemWithTag:VIEW_MENU].submenu;
	[self updateMenuItemsForSorting:sortOrder];
	[m itemWithTag:SHOW_FILE_NAMES].state = wc.imageMatrix.showFilenames ? NSOnState : NSOffState;
	[m itemWithTag:AUTO_ROTATE].state = wc.imageMatrix.autoRotate ? NSOnState : NSOffState;
}

- (IBAction)newWindow:(id)sender {
	[self newWindow:NO init:(sender != nil)];
}

- (IBAction)newTab:(id)sender {
	[self newWindow:YES init:YES];
}

- (void)windowClosed:(NSNotification *)n {
	NSWindowController *wc = [n.object windowController];
	if ([creeveyWindows indexOfObjectIdenticalTo:wc] != NSNotFound) {
		if (wc.window == frontWindow.window) {
			// for some reason closing a tab will call windowChanged: (with the new window) before windowClosed: (with the old window)
			frontWindow = nil;
		}
		if (creeveyWindows.count == 1) {
			[creeveyWindows[0] updateDefaults];
			if ((exifWasVisible = exifTextView.window.visible)) {
				[exifTextView.window orderOut:nil];
			}
		}
		[NSNotificationCenter.defaultCenter removeObserver:self name:nil object:wc.window];
		[creeveyWindows removeObject:wc];
	}
}

- (void)windowChanged:(NSNotification *)n {
	frontWindow = [n.object windowController];
	
	short int sortOrder = frontWindow.sortOrder;
	NSMenu *m = [NSApp.mainMenu itemWithTag:VIEW_MENU].submenu;
	[self updateMenuItemsForSorting:sortOrder];
	[m itemWithTag:SHOW_FILE_NAMES].state = frontWindow.imageMatrix.showFilenames ? NSOnState : NSOffState;
	[m itemWithTag:AUTO_ROTATE].state = frontWindow.imageMatrix.autoRotate ? NSOnState : NSOffState;
}

- (IBAction)versionCheck:(id)sender {
	DYVersCheckForUpdateAndNotify(YES);
}
- (IBAction)sendFeedback:(id)sender {
	[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"http://blyt.net/phxslides/feedback.html"]];
}

#pragma mark slideshow window delegate method
- (void)windowDidBecomeMain:(NSNotification *)aNotification {
	if (creeveyWindows.count && (exifWasVisible = exifTextView.window.visible))
		[exifTextView.window orderOut:nil];
	[[NSApp.mainMenu itemWithTag:VIEW_MENU].submenu itemWithTag:AUTO_ROTATE].state = slidesWindow.autoRotate;
	// only needed in case user cycles through windows; see startSlideshow above
}
- (void)windowDidResignMain:(NSNotification *)aNotification {
	// do this here, not in windowChanged, to avoid app switch problems
	if (creeveyWindows.count && exifWasVisible)
		[exifTextView.window orderFront:nil];
	if (creeveyWindows.count && frontWindow.currentSelection.count <= 1) {
		NSArray *a = frontWindow.displayedFilenames;
		NSUInteger i = slidesWindow.currentIndex;
		if (i < a.count
			&& [a[i] isEqualToString:slidesWindow.currentFile])
			[frontWindow selectIndex:i];
	}
}
- (void)windowDidChangeBackingProperties:(NSNotification *)notification {
	if (slidesWindow.visible)
		[slidesWindow configureBacking];
}


- (DYImageCache *)thumbsCache { return thumbsCache; }
- (NSMutableSet * __strong *)cats { return cats; }
- (void)updateCats {
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:NUM_FNKEY_CATS];
	for (short i=0; i<NUM_FNKEY_CATS; ++i)
		[result addObject:cats[i].allObjects];
	[catDefaults setObject:result forKey:@"cats"];
}

NSDirectoryEnumerator *CreeveyEnumerator(NSString *path, BOOL recurseSubfolders) {
	return [NSFileManager.defaultManager
			enumeratorAtURL:[NSURL fileURLWithPath:path isDirectory:YES]
			includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsAliasFileKey,NSURLIsHiddenKey]
			options:recurseSubfolders ? 0 : NSDirectoryEnumerationSkipsSubdirectoryDescendants
			errorHandler:nil];
}

#define IS_URL_DIRECTORY ([url getResourceValue:&val forKey:NSURLIsDirectoryKey error:NULL] && val.boolValue)
#define IS_URL_HIDDEN    ([url getResourceValue:&val forKey:NSURLIsHiddenKey error:NULL] && val.boolValue)
#define IS_URL_ALIAS     ([url getResourceValue:&val forKey:NSURLIsAliasFileKey error:NULL] && val.boolValue)

- (BOOL)handledDirectory:(NSURL *)url subfolders:(BOOL)recurse e:(NSDirectoryEnumerator *)e {
	NSNumber * __autoreleasing val;
	if (IS_URL_DIRECTORY) {
		if (recurse && ((IS_URL_HIDDEN && ![_revealedDirectories containsObject:url]) || [url.lastPathComponent isEqualToString:@"Thumbs"]))
			[e skipDescendents]; // special addition for mbatch
		return YES;
	}
	return NO;
}

- (BOOL)shouldShowFile:(NSURL *)url {
	NSNumber * __autoreleasing val;
	if (IS_URL_HIDDEN) return NO;
	if (IS_URL_ALIAS) {
		NSURL *resolved = ResolveAliasURL(url);
		if (resolved) url = resolved;
	}
	NSString *path = url.path;
	NSString *pathExtension = url.pathExtension.lowercaseString;
	if (pathExtension.length == 0) return [fileostypes containsObject:NSHFSTypeOfFile(path)];
	return [filetypes containsObject:pathExtension] || ([fileostypes containsObject:NSHFSTypeOfFile(path)] && ![disabledFiletypes containsObject:pathExtension]);
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return fileextensions.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	if ([tableColumn.identifier isEqualToString:@"enabled"]) return @([filetypes containsObject:fileextensions[row]]);
	if ([tableColumn.identifier isEqualToString:@"description"]) return filetypeDescriptions[fileextensions[row]];
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
	[NSUserDefaults.standardUserDefaults setObject:disabledFiletypes.allObjects forKey:@"ignoredFileTypes"];
}

@end
