//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "KeyBindings.h"

#pragma mark Action catalog

// Menu commands are identified by their existing NSMenuItem tag (see the anonymous
// enum in CreeveyController.m). We only ever change an item the config file names,
// so these tags are the single coupling point; defaults come from the .xib.
typedef struct { const char *actionId; NSInteger tag; } DYMenuActionDef;

static const DYMenuActionDef kMenuActions[] = {
	{"menu.newWindow",         18},  // tag added in MainMenu.xib
	{"menu.newTab",            10},
	{"menu.goToFolder",        24},  // tag added in MainMenu.xib
	{"menu.quickLook",         20},  // tag added in MainMenu.xib
	{"menu.beginSlideshow",     4},
	{"menu.beginSlideshowInWindow", 11},
	{"menu.getInfo",            6},
	{"menu.setDesktop",         5},
	{"menu.revealInFinder",     1},
	{"menu.moveTo",            12},
	{"menu.moveToAgain",       13},
	{"menu.copyTo",            14},
	{"menu.copyToAgain",       15},
	{"menu.moveToTrash",        2},
	{"menu.rename",            16},
	{"menu.deletePermanently", 17},
	{"menu.selectNone",        19},  // tag added in MainMenu.xib
	{"menu.rotateRightSave",  105},
	{"menu.rotateLeftSave",   107},
	{"menu.sortByName",       201},
	{"menu.sortByModified",   202},
	{"menu.sortByExifDate",   203},
	{"menu.sortByDateAdded",  204},
	{"menu.sortByType",       205},
	{"menu.sortBySize",       206},
	{"menu.sortByFilePath",   207},
	{"menu.showDirectoryBrowser", 25},  // tag added in MainMenu.xib
	{"menu.showPathBar",       26},  // tag added in MainMenu.xib
	{"menu.showUnsupportedFiles", 27},  // tag added in MainMenu.xib
	{"menu.copyAsPathname",    28},  // tag added in MainMenu.xib
	{"menu.search",            29},  // tag added in MainMenu.xib
	{"menu.subfolders",        30},  // tag added in MainMenu.xib
	{"menu.zoomIn",            31},  // tag added in MainMenu.xib
	{"menu.zoomOut",           32},  // tag added in MainMenu.xib
	{"menu.zoomActualSize",    33},  // tag added in MainMenu.xib
	{"menu.zoomFitToWindow",   34},  // tag added in MainMenu.xib
	{"menu.saveRotation",     117},
	{"menu.advancedOptions",  100},
	{"menu.toggleLoop",         3},
	{"menu.toggleRandom",       7},
	{"menu.scaleUp",            8},
	{"menu.actualSize",         9},
	{"menu.endSlideshow",      22},  // tag added in MainMenu.xib
	{"menu.showCheatSheet",    23},  // tag added in MainMenu.xib
	{"menu.preferences",       21},  // tag added in MainMenu.xib
};

// Single-key actions. defaultKeys is a comma-separated list of keystrokes; the
// catalog is the source of truth for the built-in keys (moved out of keyDown:).
typedef struct { const char *actionId; NSInteger code; const char *defaultKeys; } DYKeyActionDef;

static const DYKeyActionDef kSlideshowActions[] = {
	{"slideshow.rotateLeft",         SlideshowActionRotateLeft,         "l"},
	{"slideshow.rotateRight",        SlideshowActionRotateRight,        "r"},
	{"slideshow.flip",               SlideshowActionFlip,               "f"},
	{"slideshow.rename",             SlideshowActionRename,             "e"},
	{"slideshow.moveToTrash",        SlideshowActionMoveToTrash,        "d"},
	{"slideshow.deletePermanently",  SlideshowActionDeletePermanently,  "D"},
	{"slideshow.toggleInfo",         SlideshowActionToggleInfo,         "i"},
	{"slideshow.togglePath",         SlideshowActionTogglePath,         "p"},
	{"slideshow.moreExif",           SlideshowActionMoreExif,           "I"},
	{"slideshow.help",               SlideshowActionHelp,               "h,?,/"},
	{"slideshow.zoomIn",             SlideshowActionZoomIn,             "+"},
	{"slideshow.zoomOut",            SlideshowActionZoomOut,            "-"},
	{"slideshow.actualSize",         SlideshowActionActualSize,         "="},
	{"slideshow.resetView",          SlideshowActionResetView,          "*"},
	{"slideshow.scrollUp",           SlideshowActionScrollUp,           "shift+up"},
	{"slideshow.scrollDown",         SlideshowActionScrollDown,         "shift+down"},
	{"slideshow.scrollLeft",         SlideshowActionScrollLeft,         "shift+left"},
	{"slideshow.scrollRight",        SlideshowActionScrollRight,        "shift+right"},
};

static const DYKeyActionDef kBrowserActions[] = {
	{"browser.moveToTrash",       BrowserActionMoveToTrash,       "d"},
	{"browser.deletePermanently", BrowserActionDeletePermanently, "D"},
	{"browser.rename",            BrowserActionRename,            "e"},
};

// Characters that drive core navigation and can't be reassigned to an action.
static NSCharacterSet *ReservedViewerChars(void) {
	static NSCharacterSet *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableCharacterSet *m = [NSMutableCharacterSet characterSetWithCharactersInString:@" q0123456789!@"];
		unichar reserved[] = {
			0x1b, // esc
			NSLeftArrowFunctionKey, NSRightArrowFunctionKey, NSUpArrowFunctionKey, NSDownArrowFunctionKey,
			NSHomeFunctionKey, NSEndFunctionKey, NSPageUpFunctionKey, NSPageDownFunctionKey, NSHelpFunctionKey,
			NSF1FunctionKey, NSF2FunctionKey, NSF3FunctionKey, NSF4FunctionKey, NSF5FunctionKey, NSF6FunctionKey,
			NSF7FunctionKey, NSF8FunctionKey, NSF9FunctionKey, NSF10FunctionKey, NSF11FunctionKey, NSF12FunctionKey,
		};
		for (size_t i = 0; i < sizeof(reserved)/sizeof(reserved[0]); ++i)
			[m addCharactersInRange:NSMakeRange(reserved[i], 1)];
		s = [m copy];
	});
	return s;
}

#pragma mark Keystroke parsing

// Maps a special-key name to its keyEquivalent unichar. Returns 0 if unknown.
static unichar SpecialKeyChar(NSString *name) {
	static NSDictionary<NSString*,NSNumber*> *map;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		map = @{
			@"delete": @0x08, @"backspace": @0x08, @"forwarddelete": @0x7f,
			@"space": @0x20, @"return": @0x0d, @"enter": @0x0d, @"tab": @0x09,
			@"esc": @0x1b, @"escape": @0x1b,
			@"left": @(NSLeftArrowFunctionKey), @"right": @(NSRightArrowFunctionKey),
			@"up": @(NSUpArrowFunctionKey), @"down": @(NSDownArrowFunctionKey),
			@"home": @(NSHomeFunctionKey), @"end": @(NSEndFunctionKey),
			@"pageup": @(NSPageUpFunctionKey), @"pagedown": @(NSPageDownFunctionKey),
			@"f1": @(NSF1FunctionKey), @"f2": @(NSF2FunctionKey), @"f3": @(NSF3FunctionKey),
			@"f4": @(NSF4FunctionKey), @"f5": @(NSF5FunctionKey), @"f6": @(NSF6FunctionKey),
			@"f7": @(NSF7FunctionKey), @"f8": @(NSF8FunctionKey), @"f9": @(NSF9FunctionKey),
			@"f10": @(NSF10FunctionKey), @"f11": @(NSF11FunctionKey), @"f12": @(NSF12FunctionKey),
		};
	});
	NSNumber *n = map[name.lowercaseString];
	return n ? (unichar)n.unsignedShortValue : 0;
}

// Parse "cmd+shift+i" style into a menu key equivalent + modifier mask.
// Returns NO on any malformed component.
static BOOL ParseKeystroke(NSString *s, NSString **outKey, NSEventModifierFlags *outMask) {
	if (s.length == 0) return NO;
	NSString *token;
	NSEventModifierFlags mask = 0;
	if (s.length == 1) {
		token = s; // a lone character, including "+"
	} else {
		NSArray<NSString *> *parts = [s componentsSeparatedByString:@"+"];
		// last non-empty part is the key; the rest are modifiers
		token = parts.lastObject;
		for (NSUInteger i = 0; i + 1 < parts.count; ++i) {
			NSString *m = parts[i].lowercaseString;
			if (m.length == 0) continue; // e.g. trailing "+"
			if ([m isEqualToString:@"cmd"] || [m isEqualToString:@"command"]) mask |= NSEventModifierFlagCommand;
			else if ([m isEqualToString:@"ctrl"] || [m isEqualToString:@"control"]) mask |= NSEventModifierFlagControl;
			else if ([m isEqualToString:@"opt"] || [m isEqualToString:@"option"] || [m isEqualToString:@"alt"]) mask |= NSEventModifierFlagOption;
			else if ([m isEqualToString:@"shift"]) mask |= NSEventModifierFlagShift;
			else return NO; // unknown modifier
		}
		if (token.length == 0) token = @"+"; // the key itself was "+"
	}

	NSString *keyEquiv;
	if (token.length == 1) {
		unichar c = [token characterAtIndex:0];
		if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) {
			BOOL shifted = (c >= 'A' && c <= 'Z') || (mask & NSEventModifierFlagShift) != 0;
			keyEquiv = shifted ? token.uppercaseString : token.lowercaseString;
			mask &= ~NSEventModifierFlagShift; // an uppercase letter already implies shift
		} else {
			keyEquiv = token; // punctuation / digit
		}
	} else {
		unichar c = SpecialKeyChar(token);
		if (c == 0) return NO; // unknown special key
		keyEquiv = [NSString stringWithCharacters:&c length:1];
	}
	if (outKey) *outKey = keyEquiv;
	if (outMask) *outMask = mask;
	return YES;
}

// Viewer bindings are matched by a normalized "modifier-mask|key" token, so a keystroke
// like ⇧← is distinct from ← (which stays reserved for navigation).
static const NSEventModifierFlags kViewerMask =
	NSEventModifierFlagCommand|NSEventModifierFlagControl|NSEventModifierFlagOption|NSEventModifierFlagShift;

static NSString *EncodeViewerKey(NSString *keyEquiv, NSEventModifierFlags mask) {
	return [NSString stringWithFormat:@"%lu|%@", (unsigned long)(mask & kViewerMask), keyEquiv];
}

// Token for a key event. For printable keys shift is already folded into the character
// (charactersIgnoringModifiers keeps shift, so "+" and "D" arrive as-is) and dropped from the
// mask; for function keys (arrows, etc.) shift is kept, so ⇧← ≠ ←.
static NSString *EncodeViewerEvent(NSEvent *e) {
	NSString *chars = e.charactersIgnoringModifiers.length ? e.charactersIgnoringModifiers : e.characters;
	if (chars.length == 0) return nil;
	NSEventModifierFlags mask = e.modifierFlags & kViewerMask;
	unichar c = [chars characterAtIndex:0];
	BOOL functionKey = (c >= 0xF700 && c <= 0xF8FF); // NSUpArrowFunctionKey … et al.
	if (!functionKey) mask &= ~NSEventModifierFlagShift; // shift is folded into the printable char
	return EncodeViewerKey(chars, mask);
}

#pragma mark -

@implementation KeyBindings {
	// actionId -> @[keyEquiv, @(mask)] or NSNull (explicit unbind). Only keys the file names.
	NSMutableDictionary<NSString*, id> *_menuOverrides;
	// actionId -> @[keyEquiv, @(mask)] captured from the .xib once, to revert to.
	NSMutableDictionary<NSString*, NSArray*> *_menuDefaults;
	NSMutableDictionary<NSString*, NSNumber*> *_slideshowDispatch; // char -> SlideshowAction
	NSMutableDictionary<NSString*, NSNumber*> *_browserDispatch;   // char -> BrowserAction
	NSMutableArray<NSString*> *_errors;
}

- (instancetype)init {
	if (!(self = [super init])) return nil;
	_menuOverrides = [NSMutableDictionary dictionary];
	_slideshowDispatch = [NSMutableDictionary dictionary];
	_browserDispatch = [NSMutableDictionary dictionary];
	_errors = [NSMutableArray array];
	return self;
}

- (NSURL *)fileURL {
	NSURL *appSupport = [NSFileManager.defaultManager URLForDirectory:NSApplicationSupportDirectory
															inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:NULL];
	// .jsonc so editors allow the // comments (JSON-with-comments) without lint errors
	return [[appSupport URLByAppendingPathComponent:@"Phoenix Slides" isDirectory:YES]
			URLByAppendingPathComponent:@"keybindings.jsonc" isDirectory:NO];
}

// the pre-.jsonc filename, migrated forward if present so edits aren't lost
- (NSURL *)legacyFileURL {
	return [self.fileURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"keybindings.json" isDirectory:NO];
}

#pragma mark Loading

- (void)load {
	[_errors removeAllObjects];
	[_menuOverrides removeAllObjects];
	[_slideshowDispatch removeAllObjects];
	[_browserDispatch removeAllObjects];

	// seed viewer dispatch with the built-in defaults; overrides replace per-action below
	NSMutableDictionary<NSString*, NSNumber*> *slideshowById = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString*, NSNumber*> *browserById = [NSMutableDictionary dictionary];
	NSDictionary *keybindings = [self readKeybindings]; // nil if file missing/unreadable/malformed

	// resolve effective keystrokes for each viewer action (override or default)
	[self buildViewerDispatch:_slideshowDispatch table:kSlideshowActions count:sizeof(kSlideshowActions)/sizeof(kSlideshowActions[0]) overrides:keybindings idToCode:slideshowById];
	[self buildViewerDispatch:_browserDispatch table:kBrowserActions count:sizeof(kBrowserActions)/sizeof(kBrowserActions[0]) overrides:keybindings idToCode:browserById];

	// menu overrides (only entries the file names)
	if (keybindings) {
		for (size_t i = 0; i < sizeof(kMenuActions)/sizeof(kMenuActions[0]); ++i) {
			NSString *actionId = @(kMenuActions[i].actionId);
			id val = keybindings[actionId];
			if (!val) continue; // not named -> keep the .xib default
			if (val == NSNull.null) { _menuOverrides[actionId] = NSNull.null; continue; }
			NSString *ks = [val isKindOfClass:NSString.class] ? val : ([val isKindOfClass:NSArray.class] ? [val firstObject] : nil);
			NSString *key; NSEventModifierFlags mask;
			if (ks && ParseKeystroke(ks, &key, &mask))
				_menuOverrides[actionId] = @[key, @(mask)];
			else
				[_errors addObject:[NSString stringWithFormat:@"Could not understand the shortcut for \"%@\".", actionId]];
		}
		// flag any keys in the file that don't match a known action
		[self flagUnknownActionIds:keybindings];
	}
}

// Read + comment-strip + JSON-parse the file; returns the "keybindings" object or nil.
- (NSDictionary *)readKeybindings {
	NSURL *url = self.fileURL;
	if (![url checkResourceIsReachableAndReturnError:NULL]) return nil; // missing == all defaults
	NSError *err = nil;
	NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&err];
	if (!text) {
		[_errors addObject:[NSString stringWithFormat:@"Could not read the configuration file: %@", err.localizedDescription]];
		return nil;
	}
	NSData *json = [[self stripJSONComments:text] dataUsingEncoding:NSUTF8StringEncoding];
	id root = [NSJSONSerialization JSONObjectWithData:json options:0 error:&err];
	if (![root isKindOfClass:NSDictionary.class]) {
		[_errors addObject:[NSString stringWithFormat:@"The configuration file is not valid JSON: %@", err.localizedDescription]];
		return nil;
	}
	id kb = root[@"keybindings"];
	if (kb && ![kb isKindOfClass:NSDictionary.class]) {
		[_errors addObject:@"\"keybindings\" must be an object."];
		return nil;
	}
	return kb ?: @{};
}

// Remove // comments (line and trailing), ignoring // inside JSON strings.
- (NSString *)stripJSONComments:(NSString *)text {
	NSMutableString *out = [NSMutableString stringWithCapacity:text.length];
	BOOL inString = NO, escaped = NO, inComment = NO;
	NSUInteger n = text.length;
	for (NSUInteger i = 0; i < n; ++i) {
		unichar c = [text characterAtIndex:i];
		if (inComment) {
			if (c == '\n') { inComment = NO; [out appendFormat:@"%C", c]; }
			continue;
		}
		if (inString) {
			[out appendFormat:@"%C", c];
			if (escaped) escaped = NO;
			else if (c == '\\') escaped = YES;
			else if (c == '"') inString = NO;
			continue;
		}
		if (c == '"') { inString = YES; [out appendFormat:@"%C", c]; continue; }
		if (c == '/' && i + 1 < n && [text characterAtIndex:i+1] == '/') { inComment = YES; ++i; continue; }
		[out appendFormat:@"%C", c];
	}
	return out;
}

- (void)buildViewerDispatch:(NSMutableDictionary<NSString*,NSNumber*> *)dispatch
					  table:(const DYKeyActionDef *)table count:(size_t)count
				  overrides:(NSDictionary *)keybindings
				   idToCode:(NSMutableDictionary<NSString*,NSNumber*> *)idToCode {
	for (size_t i = 0; i < count; ++i) {
		NSString *actionId = @(table[i].actionId);
		NSNumber *code = @(table[i].code);
		id override = keybindings[actionId];
		NSArray<NSString *> *keystrokes;
		if (override == nil) {
			keystrokes = [@(table[i].defaultKeys) componentsSeparatedByString:@","]; // built-in default
		} else if (override == NSNull.null) {
			keystrokes = @[]; // explicit unbind
		} else if ([override isKindOfClass:NSString.class]) {
			keystrokes = @[override];
		} else if ([override isKindOfClass:NSArray.class]) {
			keystrokes = override;
		} else {
			[_errors addObject:[NSString stringWithFormat:@"The value for \"%@\" must be a string, a list, or null.", actionId]];
			keystrokes = @[];
		}
		for (NSString *ks in keystrokes) {
			NSString *key; NSEventModifierFlags mask;
			if (!ParseKeystroke(ks, &key, &mask) || key.length != 1) {
				[_errors addObject:[NSString stringWithFormat:@"\"%@\" is not a valid single-key shortcut for \"%@\".", ks, actionId]];
				continue;
			}
			// plain (unmodified) navigation keys stay reserved; the same key with a modifier
			// (e.g. ⇧←) is fair game
			if (mask == 0 && [ReservedViewerChars() characterIsMember:[key characterAtIndex:0]]) {
				[_errors addObject:[NSString stringWithFormat:@"\"%@\" is reserved for navigation and can't be reassigned (\"%@\").", ks, actionId]];
				continue;
			}
			NSString *tok = EncodeViewerKey(key, mask);
			if (dispatch[tok]) {
				[_errors addObject:[NSString stringWithFormat:@"The key \"%@\" is bound to more than one action; keeping the first.", ks]];
				continue; // first occurrence wins
			}
			dispatch[tok] = code;
		}
	}
}

- (void)flagUnknownActionIds:(NSDictionary *)keybindings {
	NSMutableSet<NSString *> *known = [NSMutableSet set];
	for (size_t i = 0; i < sizeof(kMenuActions)/sizeof(kMenuActions[0]); ++i) [known addObject:@(kMenuActions[i].actionId)];
	for (size_t i = 0; i < sizeof(kSlideshowActions)/sizeof(kSlideshowActions[0]); ++i) [known addObject:@(kSlideshowActions[i].actionId)];
	for (size_t i = 0; i < sizeof(kBrowserActions)/sizeof(kBrowserActions[0]); ++i) [known addObject:@(kBrowserActions[i].actionId)];
	for (NSString *key in keybindings) {
		if (![known containsObject:key])
			[_errors addObject:[NSString stringWithFormat:@"Unknown action \"%@\" (ignored).", key]];
	}
}

#pragma mark Applying

static NSMenuItem *MenuItemWithTag(NSMenu *menu, NSInteger tag) {
	for (NSMenuItem *item in menu.itemArray) {
		if (item.tag == tag) return item;
		if (item.submenu) {
			NSMenuItem *found = MenuItemWithTag(item.submenu, tag);
			if (found) return found;
		}
	}
	return nil;
}

- (void)applyToMainMenu {
	NSMenu *mainMenu = NSApp.mainMenu;
	if (!mainMenu) return;
	// capture the built-in (.xib) shortcuts once, before we ever change them, so an
	// action the file omits reverts to its default instead of sticking on reload
	if (!_menuDefaults) {
		_menuDefaults = [NSMutableDictionary dictionary];
		for (size_t i = 0; i < sizeof(kMenuActions)/sizeof(kMenuActions[0]); ++i) {
			NSMenuItem *item = MenuItemWithTag(mainMenu, kMenuActions[i].tag);
			if (item)
				_menuDefaults[@(kMenuActions[i].actionId)] = @[item.keyEquivalent ?: @"", @(item.keyEquivalentModifierMask)];
		}
	}
	for (size_t i = 0; i < sizeof(kMenuActions)/sizeof(kMenuActions[0]); ++i) {
		NSString *actionId = @(kMenuActions[i].actionId);
		NSMenuItem *item = MenuItemWithTag(mainMenu, kMenuActions[i].tag);
		if (!item) continue;
		id override = _menuOverrides[actionId];
		NSString *key; NSEventModifierFlags mask;
		if (override == NSNull.null) {
			key = @""; mask = 0;                          // explicit unbind
		} else if (override) {
			key = override[0]; mask = (NSEventModifierFlags)[override[1] unsignedIntegerValue];
		} else {
			NSArray *def = _menuDefaults[actionId];       // not in the file -> revert to built-in
			key = def ? def[0] : @"";
			mask = def ? (NSEventModifierFlags)[def[1] unsignedIntegerValue] : 0;
		}
		item.keyEquivalent = key;
		item.keyEquivalentModifierMask = mask;
	}
}

#pragma mark Dispatch

- (SlideshowAction)slideshowActionForEvent:(NSEvent *)e {
	NSString *tok = EncodeViewerEvent(e);
	if (!tok) return SlideshowActionNone;
	NSNumber *code = _slideshowDispatch[tok];
	return code ? (SlideshowAction)code.integerValue : SlideshowActionNone;
}

- (BrowserAction)browserActionForEvent:(NSEvent *)e {
	NSString *tok = EncodeViewerEvent(e);
	if (!tok) return BrowserActionNone;
	NSNumber *code = _browserDispatch[tok];
	return code ? (BrowserAction)code.integerValue : BrowserActionNone;
}

#pragma mark Errors & file access

- (void)reportErrorsIfAny {
	if (_errors.count == 0) return;
	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = NSLocalizedString(@"There were problems in the configuration file.", @"");
	alert.informativeText = [_errors componentsJoinedByString:@"\n"];
	[alert addButtonWithTitle:NSLocalizedString(@"OK", @"")];
	[alert runModal];
}

- (void)openInEditor {
	[self writeTemplateIfMissing];
	[NSWorkspace.sharedWorkspace openURL:self.fileURL];
}

- (void)revealInFinder {
	[self writeTemplateIfMissing];
	[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[self.fileURL]];
}

- (void)writeTemplateIfMissing {
	NSURL *url = self.fileURL;
	if ([url checkResourceIsReachableAndReturnError:NULL]) return;
	// migrate a pre-existing keybindings.json to the new .jsonc name, preserving edits
	NSURL *legacy = self.legacyFileURL;
	if ([legacy checkResourceIsReachableAndReturnError:NULL] &&
		[NSFileManager.defaultManager moveItemAtURL:legacy toURL:url error:NULL])
		return;
	[NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent
						   withIntermediateDirectories:YES attributes:nil error:NULL];
	[[self templateText] writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

// A self-documenting snapshot of the current shortcuts. Every action is written as
// a real (active) entry so the file reflects the current keybindings; deleting a
// line reverts that action to its built-in default.
- (NSString *)templateText {
	NSMutableArray<NSArray *> *entries = [NSMutableArray array]; // @[section, "\"key\": value"]
	for (size_t i = 0; i < sizeof(kMenuActions)/sizeof(kMenuActions[0]); ++i) {
		NSString *cur = [self currentMenuKeystrokeForTag:kMenuActions[i].tag];
		NSString *val = cur ? [NSString stringWithFormat:@"\"%@\"", cur] : @"null";
		[entries addObject:@[@"Menu shortcuts", [NSString stringWithFormat:@"\"%@\": %@", @(kMenuActions[i].actionId), val]]];
	}
	[self appendViewerEntries:entries table:kSlideshowActions count:sizeof(kSlideshowActions)/sizeof(kSlideshowActions[0]) section:@"Slideshow keys"];
	[self appendViewerEntries:entries table:kBrowserActions count:sizeof(kBrowserActions)/sizeof(kBrowserActions[0]) section:@"Browser (thumbnail window) keys"];

	NSMutableString *s = [NSMutableString stringWithString:
		@"{\n"
		"  // Phoenix Slides keyboard shortcuts. This file was created from your current\n"
		"  // shortcuts. Edit a value and use Phoenix Slides > Reload Configuration to\n"
		"  // apply it (no restart needed).\n"
		"  //\n"
		"  // Value: a keystroke string, a list of strings, or null for no shortcut.\n"
		"  // Modifiers: cmd, ctrl, opt, shift. Examples: \"cmd+shift+i\", \"n\", \"D\".\n"
		"  // Slideshow/browser keys may use modifiers too, e.g. \"shift+left\" to pan;\n"
		"  // vim users can set slideshow.scrollLeft/Right/Up/Down to \"h\"/\"l\"/\"k\"/\"j\".\n"
		"  // Delete a line to fall back to the built-in default.\n"
		"  \"keybindings\": {\n"];
	NSString *lastSection = nil;
	for (NSUInteger i = 0; i < entries.count; ++i) {
		NSString *section = entries[i][0], *line = entries[i][1];
		if (![section isEqualToString:lastSection]) {
			[s appendFormat:@"\n    // --- %@ ---\n", section];
			lastSection = section;
		}
		[s appendFormat:@"    %@%@\n", line, (i + 1 < entries.count) ? @"," : @""];
	}
	[s appendString:@"  }\n}\n"];
	return s;
}

- (void)appendViewerEntries:(NSMutableArray<NSArray *> *)entries table:(const DYKeyActionDef *)table count:(size_t)count section:(NSString *)section {
	for (size_t i = 0; i < count; ++i) {
		NSArray<NSString *> *keys = [@(table[i].defaultKeys) componentsSeparatedByString:@","];
		NSString *value;
		if (keys.count == 1) {
			value = [NSString stringWithFormat:@"\"%@\"", keys[0]];
		} else {
			NSMutableArray *quoted = [NSMutableArray array];
			for (NSString *k in keys) [quoted addObject:[NSString stringWithFormat:@"\"%@\"", k]];
			value = [NSString stringWithFormat:@"[%@]", [quoted componentsJoinedByString:@", "]];
		}
		[entries addObject:@[section, [NSString stringWithFormat:@"\"%@\": %@", @(table[i].actionId), value]]];
	}
}

// Format a menu item's current key equivalent back into keystroke syntax (best effort).
- (NSString *)currentMenuKeystrokeForTag:(NSInteger)tag {
	NSMenuItem *item = MenuItemWithTag(NSApp.mainMenu, tag);
	if (!item || item.keyEquivalent.length == 0) return nil;
	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	NSEventModifierFlags m = item.keyEquivalentModifierMask;
	if (m & NSEventModifierFlagControl) [parts addObject:@"ctrl"];
	if (m & NSEventModifierFlagOption)  [parts addObject:@"opt"];
	if (m & NSEventModifierFlagShift)   [parts addObject:@"shift"];
	if (m & NSEventModifierFlagCommand) [parts addObject:@"cmd"];
	unichar c = [item.keyEquivalent characterAtIndex:0];
	NSString *keyName;
	switch (c) {
		case 0x08: keyName = @"delete"; break;
		case 0x7f: keyName = @"forwarddelete"; break;
		case 0x0d: keyName = @"return"; break;
		case 0x1b: keyName = @"esc"; break;
		case 0x20: keyName = @"space"; break;
		default:
			if (c >= NSF1FunctionKey && c <= NSF12FunctionKey)
				keyName = [NSString stringWithFormat:@"f%d", (int)(c - NSF1FunctionKey + 1)];
			else
				keyName = item.keyEquivalent; // ordinary character (uppercase already implies shift)
	}
	[parts addObject:keyName];
	return [parts componentsJoinedByString:@"+"];
}

@end
