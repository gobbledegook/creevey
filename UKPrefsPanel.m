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

/* -----------------------------------------------------------------------------
	Headers:
   -------------------------------------------------------------------------- */

#import "UKPrefsPanel.h"


@implementation UKPrefsPanel

/* -----------------------------------------------------------------------------
	Constructor:
   -------------------------------------------------------------------------- */

-(id) init
{
	if( self = [super init] )
	{
		tabView = nil;
		itemsList = [[NSMutableDictionary alloc] init];
		baseWindowName = [@"" retain];
		autosaveName = [@"com.ulikusterer" retain];
	}
	
	return self;
}


/* -----------------------------------------------------------------------------
	Destructor:
   -------------------------------------------------------------------------- */

-(void)	dealloc
{
	[itemsList release];
	[baseWindowName release];
	[autosaveName release];
	[super dealloc]; // ** DY
}

// stuff to resize intelligently -DY
- (void)doResize {
	NSWindow *w = [tabView window];
	NSView *v = [[tabView selectedTabViewItem] view];
	// find optimal dimensions
	float maxX, maxY;
	maxX = maxY = 0;
	NSEnumerator *e = [[v subviews] objectEnumerator];
	NSView *aView;
	NSRect r;
	while (aView = [e nextObject]) {
		r = [aView frame];
		if (NSMaxX(r) > maxX)
			maxX = NSMaxX(r);
		if (NSMaxY(r) > maxY)
			maxY = NSMaxY(r);
	}
	r = [w frame];
	r.size.width = maxX + 20;
	maxY += 16 + (NSHeight(r) - NSHeight([[w contentView] frame]));
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
	NSString*		key;
	int				index = 0;
	NSString*		wndTitle = nil;
	
	// Generate a string containing the window's title so we can display the original window title plus the selected pane:
	wndTitle = [[tabView window] title];
	if( [wndTitle length] > 0 )
	{
		[baseWindowName release];
		baseWindowName = [[NSString stringWithFormat: @"%@ : ", wndTitle] retain];
	}
	
	// Make sure our autosave-name is based on the one of our prefs window:
	[self setAutosaveName: [[tabView window] frameAutosaveName]]; // defined below -DY
	
	// Select the preferences page the user last had selected when this window was opened:
	key = [NSString stringWithFormat: @"%@.prefspanel.recentpage", autosaveName];
	index = [[NSUserDefaults standardUserDefaults] integerForKey: key];
	[tabView selectTabViewItemAtIndex: index];
	
	// Actually hook up our toolbar and the tabs:
	[self mapTabsToToolbar];
	
	// remove the toolbar button! -DY 2006.08.06
	[[tabView window] setShowsToolbarButton:NO];
	// and make sure it's tabless -DY
	[tabView setTabViewType:NSNoTabsBezelBorder];
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
    NSToolbar		*toolbar =[[tabView window] toolbar];
	int				itemCount = 0,
					x = 0;
	NSTabViewItem	*currPage = nil;
	
	if( toolbar == nil )   // No toolbar yet? Create one!
		toolbar = [[[NSToolbar alloc] initWithIdentifier: [NSString stringWithFormat: @"%@.prefspanel.toolbar", autosaveName]] autorelease];
	
    // Set up toolbar properties: Allow customization, give a default display mode, and remember state in user defaults 
    [toolbar setAllowsUserCustomization: NO];
    [toolbar setAutosavesConfiguration: NO]; // DY: avoid auto-saving list of identifiers, which might change/increase across versions
    [toolbar setDisplayMode: NSToolbarDisplayModeIconAndLabel];
	
	// Set up item list based on Tab View:
	itemCount = [tabView numberOfTabViewItems];
	
	[itemsList removeAllObjects];	// In case we already had a toolbar.
	
	for( x = 0; x < itemCount; x++ )
	{
		NSTabViewItem*		theItem = [tabView tabViewItemAtIndex:x];
		NSString*			theIdentifier = [theItem identifier];
		NSString*			theLabel = [theItem label];
		
		[itemsList setObject:theLabel forKey:theIdentifier];
	}
    
    // We are the delegate
    [toolbar setDelegate: self];
    
    // Attach the toolbar to the document window 
    [[tabView window] setToolbar: toolbar];
	
	// Set up window title:
	currPage = [tabView selectedTabViewItem];
	if( currPage == nil )
		currPage = [tabView tabViewItemAtIndex:0];
	[[tabView window] setTitle: [baseWindowName stringByAppendingString: [currPage label]]];
	
	#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_3
	if( [toolbar respondsToSelector: @selector(setSelectedItemIdentifier:)] )
		[toolbar setSelectedItemIdentifier: [currPage identifier]];
	#endif
}


/* -----------------------------------------------------------------------------
	orderFrontPrefsPanel:
		IBAction to assign to "Preferences..." menu item.
   -------------------------------------------------------------------------- */

-(IBAction)		orderFrontPrefsPanel: (id)sender
{
	[[tabView window] makeKeyAndOrderFront:sender];
}


/* -----------------------------------------------------------------------------
	setTabView:
		Accessor for specifying the tab view to query.
   -------------------------------------------------------------------------- */

-(void)			setTabView: (NSTabView*)tv
{
	tabView = tv;
}


-(NSTabView*)   tabView
{
	return tabView;
}


/* -----------------------------------------------------------------------------
	setAutosaveName:
		Name used for saving state of prefs window.
   -------------------------------------------------------------------------- */

-(void)			setAutosaveName: (NSString*)name
{
	if (name) {
		// ignore if nil
		[name retain];
		[autosaveName release];
		autosaveName = name;
	}
}


-(NSString*)	autosaveName
{
	return autosaveName;
}


/* -----------------------------------------------------------------------------
	toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:
		Create an item with the proper image and name based on our list
		of tabs for the specified identifier.
   -------------------------------------------------------------------------- */

-(NSToolbarItem *) toolbar: (NSToolbar *)toolbar itemForItemIdentifier: (NSString *) itemIdent willBeInsertedIntoToolbar:(BOOL) willBeInserted
{
    // Required delegate method:  Given an item identifier, this method returns an item 
    // The toolbar will use this method to obtain toolbar items that can be displayed in the customization sheet, or in the toolbar itself 
    NSToolbarItem   *toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier: itemIdent] autorelease];
    NSString*		itemLabel;
	
    if( (itemLabel = [itemsList objectForKey:itemIdent]) != nil )
	{
		// Set the text label to be displayed in the toolbar and customization palette 
		[toolbarItem setLabel: itemLabel];
		[toolbarItem setPaletteLabel: itemLabel];
		[toolbarItem setTag:[tabView indexOfTabViewItemWithIdentifier:itemIdent]];
		
		// Set up a reasonable tooltip, and image   Note, these aren't localized, but you will likely want to localize many of the item's properties 
		[toolbarItem setToolTip: itemLabel];
		[toolbarItem setImage: [NSImage imageNamed:itemIdent]];
		
		// Tell the item what message to send when it is clicked 
		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(changePanes:)];
    }
	else
	{
		// itemIdent refered to a toolbar item that is not provide or supported by us or cocoa 
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

#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_3
-(NSArray*) toolbarSelectableItemIdentifiers: (NSToolbar*)toolbar
{
	return [itemsList allKeys];
}
#endif


/* -----------------------------------------------------------------------------
	changePanes:
		Action for our custom toolbar items that causes the window title to
		reflect the current pane and the proper pane to be shown in response to
		a click.
   -------------------------------------------------------------------------- */

-(IBAction)	changePanes: (id)sender
{
	NSString*		key;
	
	[tabView selectTabViewItemAtIndex: [sender tag]];
	[[tabView window] setTitle: [baseWindowName stringByAppendingString: [sender label]]];
	
	key = [NSString stringWithFormat: @"%@.prefspanel.recentpage", autosaveName];
	[[NSUserDefaults standardUserDefaults] setInteger:[sender tag] forKey:key];
}


/* -----------------------------------------------------------------------------
	toolbarDefaultItemIdentifiers:
		Return the identifiers for all toolbar items that will be shown by
		default.
		This is simply a list of all tab view items in order.
   -------------------------------------------------------------------------- */

-(NSArray*) toolbarDefaultItemIdentifiers: (NSToolbar *) toolbar
{
	int					itemCount = [tabView numberOfTabViewItems],
						x;
	NSTabViewItem*		theItem = [tabView tabViewItemAtIndex:0];
	//NSMutableArray*	defaultItems = [NSMutableArray arrayWithObjects: [theItem identifier], NSToolbarSeparatorItemIdentifier, nil];
	NSMutableArray*	defaultItems = [NSMutableArray array];
	
	for( x = 0; x < itemCount; x++ )
	{
		theItem = [tabView tabViewItemAtIndex:x];
		
		[defaultItems addObject: [theItem identifier]];
	}
	
	return defaultItems;
}


/* -----------------------------------------------------------------------------
	toolbarAllowedItemIdentifiers:
		Return the identifiers for all toolbar items that *can* be put in this
		toolbar. We allow a couple more items (flexible space, separator lines
		etc.) in addition to our custom items.
   -------------------------------------------------------------------------- */

-(NSArray*) toolbarAllowedItemIdentifiers: (NSToolbar *) toolbar
{
    NSMutableArray*		allowedItems = [[[itemsList allKeys] mutableCopy] autorelease];
	
	[allowedItems addObjectsFromArray: [NSArray arrayWithObjects: NSToolbarSeparatorItemIdentifier,
				NSToolbarSpaceItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier,
				NSToolbarCustomizeToolbarItemIdentifier, nil] ];
	
	return allowedItems;
}


@end
