/* =============================================================================
	FILE:		UKPrefsPanel.h
	
	AUTHORS:	M. Uli Kusterer (UK), (c) Copyright 2003, all rights reserved.
                modified by Dominic Yu (DY), 2006

	REVISIONS:
		2003-08-13	UK	Added auto-save, fixed bug with empty window titles.
		2003-07-22  UK  Added Panther stuff, documented.
		2003-06-30  UK  Created.
   ========================================================================== */
	
/**		A class that creates a simple Safari-like Preferences window with a
		toolbar at the top.
		
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

        DY: IMPORTANT! If you have more than one prefs window,
        make sure your prefs windows have an auto-save name defined.
        This code uses it as the toolbar's identifier.
        I've fixed a bug where the default autosave name is clobbered
        if the window's is not defined (nil). 2006.08.06

*/

	

/* -----------------------------------------------------------------------------
	Headers:
   -------------------------------------------------------------------------- */

#import <Foundation/Foundation.h>


/* -----------------------------------------------------------------------------
	Classes:
   -------------------------------------------------------------------------- */

@interface UKPrefsPanel : NSObject <NSToolbarDelegate>
@property (nonatomic, weak) NSTabView *tabView; ///< The tabless tab-view containing the different pref panes. (you should just hook this up in IB)

// Action for hooking up this object and the menu item:
-(IBAction)		orderFrontPrefsPanel: (id)sender;

// You don't have to care about these:
-(IBAction)	changePanes: (id)sender;

@end
