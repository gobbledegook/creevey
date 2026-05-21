/* =============================================================================
	FILE:		UKPrefsPanel.m
	
	AUTHORS:	M. Uli Kusterer (UK), (c) Copyright 2003, all rights reserved.
                modified by Dominic Yu (DY), 2006
	
	DIRECTIONS:
		UKPrefsPanel is ridiculously easy to use: Create a tabless NSTabView,
		where the name of each tab is the name for the toolbar item, and the
		identifier of each tab is the identifier to be used for the toolbar
		item to represent it. Then create image files with the identifier as
		their names to be used as icons in the toolbar.
	
		Finally, drag UKPrefsPanel.h into the NIB with the NSTabView,
		instantiate a UKPrefsPanel and connect its tabView outlet to your
		NSTabView. When you open the window, the UKPrefsPanel will
		automatically add a toolbar to the window with all tabs represented by
		a toolbar item, and clicking an item will switch between the tab view's
		items.

	
	REVISIONS:
		2003-08-13	UK	Added auto-save, fixed bug with empty window titles.
		2003-07-22  UK  Added Panther stuff, documented.
		2003-06-30  UK  Created.
   ========================================================================== */

#import "UKPrefsPanel.h"
#import "CreeveyController.h"

@interface UKPrefsPanel ()
@property (nonatomic) NSString *autosaveName;	///< Identifier used for saving toolbar state and current selected page of prefs window.
-(IBAction)	changePanes:(id)sender;
@end

@implementation UKPrefsPanel
{
	NSMutableDictionary*	itemsList;			///< Auto-generated from tab view's items.
	NSString*				baseWindowName;		///< Auto-fetched at awakeFromNib time. We append a colon and the name of the current page to the actual window title.
}
@synthesize tabView, autosaveName;

-(instancetype) init
{
	if( self = [super init] )
	{
		itemsList = [[NSMutableDictionary alloc] init];
		baseWindowName = @"";
		autosaveName = @"com.ulikusterer";
	}
	return self;
}

// stuff to resize intelligently -DY
- (void)doResize {
	// find optimal dimensions
	float maxX=0, maxY=0;
	NSRect r;
	for (NSView *aView in tabView.selectedTabViewItem.view.subviews) {
		r = aView.frame;
		if (NSMaxX(r) > maxX)
			maxX = NSMaxX(r);
		if (NSMaxY(r) > maxY)
			maxY = NSMaxY(r);
	}
	NSWindow *w = tabView.window;
	r = w.frame;
	// Ensure minimum width of 550 to accommodate all toolbar icons
	float desiredWidth = maxX + 20;
	if (desiredWidth < 550) desiredWidth = 550;
	r.size.width = desiredWidth;
	maxY += 16 + (NSHeight(r) - NSHeight(w.contentView.frame));
	r.origin.y -= (maxY - r.size.height);
	r.size.height = maxY;
	[w setFrame:r display:YES animate:YES];
}


/* -----------------------------------------------------------------------------
	awakeFromNib:
		This object and all others in the NIB have been created and hooked up.
		Fetch the window name so we can modify it to indicate the current
		page, and add our toolbar to the window.
		
		This method is the great obstacle to making UKPrefsPanel an NSTabView
		subclass. When the tab view's awakeFromNib method is called, the
		individual tabs aren't set up yet, meaning mapTabsToToolbar gives us an
		empty toolbar. ... bummer.
		
		If anybody knows how to fix this, you're welcome to tell me.
   -------------------------------------------------------------------------- */

-(void)	awakeFromNib
{
	// Add Fonts tab before creating toolbar
	[self addFontsTab];

	// Generate a string containing the window's title so we can display the original window title plus the selected pane:
	NSString *wndTitle = tabView.window.title;
	if( wndTitle.length > 0 )
	{
		baseWindowName = [NSString stringWithFormat:@"%@ : ", wndTitle];
	}

	// Make sure our autosave-name is based on the one of our prefs window:
	self.autosaveName = tabView.window.frameAutosaveName; // defined below -DY

	// Select the preferences page the user last had selected when this window was opened:
	NSString *key = [NSString stringWithFormat:@"%@.prefspanel.recenttab", autosaveName];
	NSInteger index = [NSUserDefaults.standardUserDefaults integerForKey:key];
	if (index >= tabView.numberOfTabViewItems) index = 0; // prevent crash if number of items has changed
	[tabView selectTabViewItemAtIndex:index];

	// Actually hook up our toolbar and the tabs:
	[self mapTabsToToolbar];
	
	// remove the toolbar button! -DY 2006.08.06
	[tabView.window setShowsToolbarButton:NO];
	// and make sure it's tabless -DY
	tabView.tabViewType = NSNoTabsBezelBorder;
	//[tabView setDrawsBackground:NO];
	// and resize
	[self doResize];
}


/* -----------------------------------------------------------------------------
	mapTabsToToolbar:
		Create a toolbar based on our tab control.
		
		Tab title		-   Name for toolbar item.
		Tab identifier  -	Image file name and toolbar item identifier.
   -------------------------------------------------------------------------- */

-(void) mapTabsToToolbar
{
    // Create a new toolbar instance, and attach it to our document window 
    NSToolbar		*toolbar =tabView.window.toolbar;
	if( toolbar == nil )   // No toolbar yet? Create one!
		toolbar = [[NSToolbar alloc] initWithIdentifier:[NSString stringWithFormat:@"%@.prefspanel.toolbar", autosaveName]];
	
    // Set up toolbar properties: Allow customization, give a default display mode, and remember state in user defaults 
	toolbar.allowsUserCustomization = NO;
	toolbar.autosavesConfiguration = NO; // DY: avoid auto-saving list of identifiers, which might change/increase across versions
    toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
	
	// Set up item list based on Tab View:
	NSInteger itemCount = tabView.numberOfTabViewItems;
	
	[itemsList removeAllObjects];	// In case we already had a toolbar.
	
	for( NSInteger x = 0; x < itemCount; x++ )
	{
		NSTabViewItem *theItem = [tabView tabViewItemAtIndex:x];
		itemsList[theItem.identifier] = theItem.label;
	}
    
    // We are the delegate
    toolbar.delegate = self;
    
    // Attach the toolbar to the document window 
    tabView.window.toolbar = toolbar;
	
	// Set up window title:
	NSTabViewItem *currPage = tabView.selectedTabViewItem;
	if( currPage == nil )
		currPage = [tabView tabViewItemAtIndex:0];
	tabView.window.title = [baseWindowName stringByAppendingString:currPage.label];
	
	toolbar.selectedItemIdentifier = currPage.identifier;
}


/* -----------------------------------------------------------------------------
	orderFrontPrefsPanel:
		IBAction to assign to "Preferences..." menu item.
   -------------------------------------------------------------------------- */

-(IBAction) orderFrontPrefsPanel:(id)sender
{
	[tabView.window makeKeyAndOrderFront:sender];
}


/* -----------------------------------------------------------------------------
	toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:
		Create an item with the proper image and name based on our list
		of tabs for the specified identifier.
   -------------------------------------------------------------------------- */

-(NSToolbarItem *) toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdent willBeInsertedIntoToolbar:(BOOL)willBeInserted
{
    // Required delegate method:  Given an item identifier, this method returns an item 
    // The toolbar will use this method to obtain toolbar items that can be displayed in the customization sheet, or in the toolbar itself 
    NSToolbarItem   *toolbarItem = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdent];
    NSString*		itemLabel;
	
    if( (itemLabel = itemsList[itemIdent]) != nil )
	{
		// Set the text label to be displayed in the toolbar and customization palette 
		toolbarItem.label = itemLabel;
		toolbarItem.paletteLabel = itemLabel;
		toolbarItem.tag = [tabView indexOfTabViewItemWithIdentifier:itemIdent];
		
		// Set up a reasonable tooltip, and image   Note, these aren't localized, but you will likely want to localize many of the item's properties 
		toolbarItem.toolTip = itemLabel;
		toolbarItem.image = [NSImage imageNamed:itemIdent];
		
		// Tell the item what message to send when it is clicked 
		toolbarItem.target = self;
		toolbarItem.action = @selector(changePanes:);
    }
	else
	{
		// itemIdent refered to a toolbar item that is not provided or supported by us or cocoa
		// Returning nil will inform the toolbar this kind of item is not supported
		toolbarItem = nil;
    }
	
    return toolbarItem;
}


/* -----------------------------------------------------------------------------
	toolbarSelectableItemIdentifiers:
		Make sure all our custom items can be selected. NSToolbar will
		automagically select the appropriate item when it is clicked.
   -------------------------------------------------------------------------- */

-(NSArray*) toolbarSelectableItemIdentifiers:(NSToolbar*)toolbar
{
	return itemsList.allKeys;
}


/* -----------------------------------------------------------------------------
	changePanes:
		Action for our custom toolbar items that causes the window title to
		reflect the current pane and the proper pane to be shown in response to
		a click.
   -------------------------------------------------------------------------- */

-(IBAction)	changePanes:(id)sender
{
	[tabView selectTabViewItemAtIndex:[sender tag]];
	tabView.window.title = [baseWindowName stringByAppendingString:[sender label]];
	
	NSString *key = [NSString stringWithFormat:@"%@.prefspanel.recenttab", autosaveName];
	[NSUserDefaults.standardUserDefaults setInteger:[sender tag] forKey:key];
}


/* -----------------------------------------------------------------------------
	toolbarDefaultItemIdentifiers:
		Return the identifiers for all toolbar items that will be shown by
		default.
		This is simply a list of all tab view items in order.
   -------------------------------------------------------------------------- */

-(NSArray*) toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	NSInteger itemCount = tabView.numberOfTabViewItems;
	NSMutableArray *defaultItems = [NSMutableArray array];

	for( NSInteger x = 0; x < itemCount; x++ )
	{
		[defaultItems addObject:[tabView tabViewItemAtIndex:x].identifier];
	}
	
	return defaultItems;
}


/* -----------------------------------------------------------------------------
	toolbarAllowedItemIdentifiers:
		Return the identifiers for all toolbar items that *can* be put in this
		toolbar. We allow a couple more items (flexible space, separator lines
		etc.) in addition to our custom items.
   -------------------------------------------------------------------------- */

-(NSArray*) toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	return [itemsList.allKeys arrayByAddingObjectsFromArray:@[NSToolbarSpaceItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier] ];
}

- (void)addFontsTab {
	// Check if Font Settings tab already exists
	for (NSTabViewItem *item in tabView.tabViewItems) {
		if ([item.identifier isEqualToString:@"fonts"]) {
			return; // Already exists
		}
	}

	// Create Font Settings tab
	NSTabViewItem *fontTab = [[NSTabViewItem alloc] initWithIdentifier:@"fonts"];
	fontTab.label = NSLocalizedString(@"Fonts", @"Font settings tab");

	// Create the content view for the tab
	NSView *fontView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 487, 448)];

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	// Folder Browser Font Size
	NSTextField *folderLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 380, 200, 20)];
	folderLabel.stringValue = NSLocalizedString(@"Folder Browser Font Size:", @"");
	folderLabel.bezeled = NO;
	folderLabel.drawsBackground = NO;
	folderLabel.editable = NO;
	folderLabel.selectable = NO;
	[fontView addSubview:folderLabel];

	NSSlider *folderSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(20, 350, 300, 20)];
	folderSlider.minValue = 10.0;
	folderSlider.maxValue = 24.0;
	CGFloat folderFontSize = [defaults floatForKey:@"folderBrowserFontSize"];
	if (folderFontSize <= 0) folderFontSize = NSFont.systemFontSize;
	folderSlider.floatValue = folderFontSize;
	folderSlider.target = [NSApp delegate];
	folderSlider.action = @selector(folderBrowserFontSizeChanged:);
	folderSlider.continuous = YES;
	[fontView addSubview:folderSlider];

	NSTextField *folderSizeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(330, 350, 50, 20)];
	folderSizeLabel.stringValue = [NSString stringWithFormat:@"%.0f pt", folderFontSize];
	folderSizeLabel.bezeled = NO;
	folderSizeLabel.drawsBackground = NO;
	folderSizeLabel.editable = NO;
	folderSizeLabel.selectable = NO;
	folderSizeLabel.tag = 1001; // Tag for updating
	[fontView addSubview:folderSizeLabel];

	NSButton *folderResetBtn = [[NSButton alloc] initWithFrame:NSMakeRect(390, 345, 80, 30)];
	folderResetBtn.title = NSLocalizedString(@"Reset", @"");
	folderResetBtn.bezelStyle = NSBezelStyleRounded;
	folderResetBtn.target = [NSApp delegate];
	folderResetBtn.action = @selector(resetFolderBrowserFontSize:);
	[fontView addSubview:folderResetBtn];

	// Thumbnail Label Font Size
	NSTextField *thumbLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 280, 200, 20)];
	thumbLabel.stringValue = NSLocalizedString(@"Thumbnail Label Font Size:", @"");
	thumbLabel.bezeled = NO;
	thumbLabel.drawsBackground = NO;
	thumbLabel.editable = NO;
	thumbLabel.selectable = NO;
	[fontView addSubview:thumbLabel];

	NSSlider *thumbSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(20, 250, 300, 20)];
	thumbSlider.minValue = 0.0; // 0 means automatic
	thumbSlider.maxValue = 18.0;
	CGFloat thumbFontSize = [defaults floatForKey:@"thumbnailLabelFontSize"];
	thumbSlider.floatValue = thumbFontSize;
	thumbSlider.target = [NSApp delegate];
	thumbSlider.action = @selector(thumbnailLabelFontSizeChanged:);
	thumbSlider.continuous = YES;
	[fontView addSubview:thumbSlider];

	NSTextField *thumbSizeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(330, 250, 50, 20)];
	if (thumbFontSize <= 0) {
		thumbSizeLabel.stringValue = NSLocalizedString(@"Auto", @"");
	} else {
		thumbSizeLabel.stringValue = [NSString stringWithFormat:@"%.0f pt", thumbFontSize];
	}
	thumbSizeLabel.bezeled = NO;
	thumbSizeLabel.drawsBackground = NO;
	thumbSizeLabel.editable = NO;
	thumbSizeLabel.selectable = NO;
	thumbSizeLabel.tag = 1002; // Tag for updating
	[fontView addSubview:thumbSizeLabel];

	NSButton *thumbResetBtn = [[NSButton alloc] initWithFrame:NSMakeRect(390, 245, 80, 30)];
	thumbResetBtn.title = NSLocalizedString(@"Reset", @"");
	thumbResetBtn.bezelStyle = NSBezelStyleRounded;
	thumbResetBtn.target = [NSApp delegate];
	thumbResetBtn.action = @selector(resetThumbnailLabelFontSize:);
	[fontView addSubview:thumbResetBtn];

	// Info text
	NSTextField *infoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 180, 450, 40)];
	infoLabel.stringValue = NSLocalizedString(@"Note: Changes apply immediately to all windows. Thumbnail label size of 'Auto' adjusts based on thumbnail width.", @"");
	infoLabel.bezeled = NO;
	infoLabel.drawsBackground = NO;
	infoLabel.editable = NO;
	infoLabel.selectable = NO;
	infoLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	infoLabel.textColor = [NSColor secondaryLabelColor];
	[fontView addSubview:infoLabel];

	fontTab.view = fontView;
	[tabView addTabViewItem:fontTab];

	// Create a fonts icon if it doesn't exist
	if (![NSImage imageNamed:@"fonts"]) {
		NSImage *fontsIcon = nil;
		if (@available(macOS 11.0, *)) {
			// Use SF Symbol on macOS 11+
			fontsIcon = [NSImage imageWithSystemSymbolName:@"textformat.size" accessibilityDescription:@"Fonts"];
		}
		if (!fontsIcon) {
			// Fallback: create a simple text-based icon
			fontsIcon = [[NSImage alloc] initWithSize:NSMakeSize(32, 32)];
			[fontsIcon lockFocus];
			NSFont *font = [NSFont boldSystemFontOfSize:20];
			NSDictionary *attributes = @{NSFontAttributeName: font,
										NSForegroundColorAttributeName: [NSColor labelColor]};
			[@"Aa" drawAtPoint:NSMakePoint(3, 5) withAttributes:attributes];
			[fontsIcon unlockFocus];
		}
		[fontsIcon setName:@"fonts"];
	}
}

@end
