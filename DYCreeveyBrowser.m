//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "DYCreeveyBrowser.h"
#import "CreeveyMainWindowController.h"
#import "DYCarbonGoodies.h"
#import "CreeveyController.h"
#import "DirBrowserDelegate.h"
#import <objc/message.h>

@interface DYBrowserCell : NSBrowserCell {
	NSString *title;
}
// maintains a title for display (sep. from stringValue), and draws it
@end

@implementation DYBrowserCell

- (void)setTitle:(NSString *)s {
	if (s == title) return;
	title = [s copy];
}
- (NSString *)title {
	return title;
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
	NSString *myStringValue = self.stringValue;
	self.stringValue = title ?: @"";
	[super drawInteriorWithFrame:cellFrame inView:controlView];
	self.stringValue = myStringValue;
}

@end

@interface DYCreeveyBrowserMatrix : NSMatrix <NSMenuItemValidation>
@end
@implementation DYCreeveyBrowserMatrix
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if (menuItem.action == @selector(selectAll:)) return YES;
	return [super validateMenuItem:menuItem];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
	CreeveyMainWindowController *wc = (CreeveyMainWindowController *)self.window.delegate;
	if (wc == nil) return nil;

	NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
	NSInteger row = -1;
	NSInteger col = -1;
	[self getRow:&row column:&col forPoint:p];
	if (row < 0) return nil;

	DYCreeveyBrowser *browser = (DYCreeveyBrowser *)wc.dirBrowser;
	if (browser == nil) return nil;

	NSInteger browserColumn = -1;
	SEL columnOfMatrixSel = @selector(columnOfMatrix:);
	if ([browser respondsToSelector:columnOfMatrixSel]) {
		browserColumn = ((NSInteger (*)(id, SEL, id))objc_msgSend)(browser, columnOfMatrixSel, self);
	}
	if (browserColumn < 0) browserColumn = browser.selectedColumn;
	if (browserColumn < 0) browserColumn = 0;

	NSCell *cell = [self cellAtRow:row column:0];
	if (cell == nil) return nil;
	NSString *component = cell.stringValue;
	if (component.length == 0) return nil;

	NSString *prefix = (browserColumn > 0) ? [browser pathToColumn:browserColumn] : @"";
	NSString *browserPath;
	if (browserColumn == 0 && ![component hasPrefix:@"/"])
		browserPath = [@"/" stringByAppendingString:component];
	else
		browserPath = [component hasPrefix:@"/"] ? component : [prefix stringByAppendingPathComponent:component];
	DirBrowserDelegate *dirDelegate = (DirBrowserDelegate *)browser.delegate;
	if (dirDelegate == nil) return nil;
	NSString *sysPath = [dirDelegate browserpath2syspath:browserPath];
	if (sysPath.length == 0) return nil;

	CreeveyController *appDelegate = (CreeveyController *)NSApp.delegate;
	if (appDelegate == nil) return nil;
	if (appDelegate.dirBrowserContextMenu == nil) {
		if (![NSBundle.mainBundle loadNibNamed:@"DirBrowserContextMenu" owner:appDelegate topLevelObjects:NULL]) return nil;
	}

	// Ensure the context path doesn't go stale if the user dismisses the menu.
	// The app delegate will clear dirBrowserContextPath in -menuDidClose:.
	if (appDelegate.dirBrowserContextMenu.delegate != appDelegate)
		appDelegate.dirBrowserContextMenu.delegate = (id<NSMenuDelegate>)appDelegate;

	appDelegate.dirBrowserContextPath = sysPath;
	return appDelegate.dirBrowserContextMenu;
}

- (void)selectAll:(id)sender {
	[(CreeveyMainWindowController *)self.window.delegate selectAll:sender]; // to pass it to image matrix
}
- (void)keyDown:(NSEvent *)e {
	unichar c = 0;
	if (e.characters.length == 1)
		c = [e.characters characterAtIndex:0];
	if (c == NSPageUpFunctionKey || c == NSPageDownFunctionKey)
		if (self.frame.size.height > self.superview.frame.size.height)
			[self.superview keyDown:e]; // scroll ourselves
		else
			[(CreeveyMainWindowController *)self.window.delegate fakeKeyDown:e]; // scroll img matrix
	else
		[super keyDown:e];
}
@end

// for drag-n-drop visual feedback
@interface DYTransparentGreyView : NSView
@end
@implementation DYTransparentGreyView
- (void)drawRect:(NSRect)rect {
	[[NSColor.lightGrayColor colorWithAlphaComponent:0.5] set];
	[NSBezierPath fillRect:rect];
}
@end

@implementation DYCreeveyBrowser
{
	NSMutableString *typedString;
	NSTimeInterval lastKeyTime;
	DYTransparentGreyView *greyview; // for drag-and-drop
}
@dynamic delegate; // use super.delegate

- (instancetype)initWithFrame:(NSRect)frameRect {
	if (self = [super initWithFrame:frameRect]) {
// I don't think there's an easy way to catch events/messages to first responder without using a custom matrix class
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
		[self setMatrixClass:[DYCreeveyBrowserMatrix class]];
#pragma GCC diagnostic pop
		self.titled = NO;
		self.hasHorizontalScroller = YES;
		[self setCellClass:[DYBrowserCell class]];
		[self.cellPrototype setFont:[NSFont systemFontOfSize:NSFont.smallSystemFontSize]];
		self.allowsEmptySelection = NO;
		self.columnResizingType = NSBrowserUserColumnResizing;
		self.prefersAllColumnUserResizing = NO;
		
		typedString = [[NSMutableString alloc] init];
		[self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
		greyview = [[DYTransparentGreyView alloc] initWithFrame:NSZeroRect];
	}
	return self;
}

#define KEYPRESS_INTERVAL 0.5

- (void)keyDown:(NSEvent *)e {
	unichar c = 0;
	if (e.characters.length == 1)
		c = [e.characters characterAtIndex:0];
	if ((c >= 0xF700 && c <= 0xF8FF) || [[NSCharacterSet controlCharacterSet] characterIsMember:c] || [[NSCharacterSet newlineCharacterSet] characterIsMember:c]) {
		// NSPageUpFunctionKey, NSPageDownFunctionKey, arrow keys, etc.
		[typedString setString:@""];
		[super keyDown:e];
		return;
	}
	[self interpretKeyEvents:@[e]];
	return;
}

- (void)insertText:(id)insertString {
	NSString *s = insertString;
	NSTimeInterval t = NSDate.timeIntervalSinceReferenceDate;
	if (t - lastKeyTime < KEYPRESS_INTERVAL)
		[typedString appendString:s];
	else
		[typedString setString:s];
	lastKeyTime = t;
	
	[self.delegate browser:self typedString:typedString inColumn:self.selectedColumn];
}

- (BOOL)sendAction {
	[self.delegate browserWillSendAction:self];
	return [super sendAction];
}

#pragma mark dragging stuff
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    if ([sender.draggingPasteboard.types containsObject:NSPasteboardTypeFileURL]) {
        if (sender.draggingSourceOperationMask & NSDragOperationGeneric) {
			greyview.frame = self.bounds;
			[self addSubview:greyview];
            return NSDragOperationGeneric;
        }
    }
    return NSDragOperationNone;
}

- (BOOL)wantsPeriodicDraggingUpdates {
	return NO;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender
{
	if (sender.draggingSourceOperationMask & NSDragOperationGeneric) {
		return NSDragOperationGeneric;
	}
	return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender {
	[greyview removeFromSuperview];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender {
	[greyview removeFromSuperview];
	return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
	NSPasteboard *pboard = sender.draggingPasteboard;
	NSArray *urlc = @[[NSURL class]];
	if ((sender.draggingSourceOperationMask & NSDragOperationGeneric)
		&& [pboard canReadObjectForClasses:urlc options:NULL]) {
		NSArray *files = [pboard readObjectsForClasses:urlc options:NULL].asFilePaths;
        [(CreeveyMainWindowController *)self.window.delegate openFiles:files withSlideshow:NO];
    }
    return YES;
}

@end
