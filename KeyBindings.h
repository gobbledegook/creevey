//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

// KeyBindings reads a user-editable JSON file (~/Library/Application Support/
// Phoenix Slides/config.json) that reassigns keyboard shortcuts. It is loaded at
// launch and can be reloaded live. Scope is keybindings only; it does not touch
// NSUserDefaults settings.

@import Cocoa;

// Rebindable single-key actions handled in SlideshowWindow keyDown:.
// Navigation keys (arrows, space, digits, esc, F-keys, …) are NOT rebindable and
// are intentionally absent here.
typedef NS_ENUM(NSInteger, SlideshowAction) {
	SlideshowActionNone = 0,
	SlideshowActionRotateLeft,
	SlideshowActionRotateRight,
	SlideshowActionFlip,
	SlideshowActionRename,
	SlideshowActionMoveToTrash,
	SlideshowActionDeletePermanently,
	SlideshowActionToggleInfo,
	SlideshowActionTogglePath,
	SlideshowActionMoreExif,
	SlideshowActionHelp,
	SlideshowActionZoomIn,
	SlideshowActionZoomOut,
	SlideshowActionActualSize,
	SlideshowActionResetView,
	SlideshowActionScrollUp,
	SlideshowActionScrollDown,
	SlideshowActionScrollLeft,
	SlideshowActionScrollRight,
};

// Rebindable single-key actions handled in the browser (CreeveyMainWindowController).
typedef NS_ENUM(NSInteger, BrowserAction) {
	BrowserActionNone = 0,
	BrowserActionMoveToTrash,
	BrowserActionDeletePermanently,
	BrowserActionRename,
};

@interface KeyBindings : NSObject

// ~/Library/Application Support/Phoenix Slides/config.json
@property (nonatomic, readonly) NSURL *fileURL;

// Read the file (validating against the action catalog) and build the binding
// maps. Missing file / bad entries fall back to built-in defaults. Safe to call
// repeatedly (this is what "Reload Configuration" does).
- (void)load;

// Apply the current menu-shortcut bindings to the app's main menu.
- (void)applyToMainMenu;

// Dispatch lookups for the refactored keyDown: handlers.
- (SlideshowAction)slideshowActionForEvent:(NSEvent *)e;
- (BrowserAction)browserActionForEvent:(NSEvent *)e;

// Show a single summarizing alert if the last load produced validation errors.
- (void)reportErrorsIfAny;

// Write the commented default template if the file doesn't exist yet.
- (void)writeTemplateIfMissing;

// Menu command helpers.
- (void)openInEditor;    // writes the template if missing, then opens the file
- (void)revealInFinder;  // selects the file in the Finder

@end
