//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "DYCreeveyBrowser.h"
#import "CreeveyMainWindowController.h"

@interface DYBrowserCell : NSBrowserCell {
	NSString *title;
}
// maintains a title for display (sep. from stringValue), and draws it
@end

@implementation DYBrowserCell

- (void)setTitle:(NSString *)s {
	[title release];
	title = [s copy];
}
- (NSString *)title {
	return title;
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
	id myStringValue = [self stringValue];
	[self setStringValue:title];
	[super drawInteriorWithFrame:cellFrame inView:controlView];
	[self setStringValue:myStringValue];
}

@end

@interface DYCreeveyBrowserMatrix : NSMatrix
@end
@implementation DYCreeveyBrowserMatrix
- (BOOL)validateMenuItem:(id <NSMenuItem>)menuItem {
	if ([menuItem action] == @selector(selectAll:)) return YES;
	return [super validateMenuItem:menuItem];
}
- (void)selectAll:(id)sender {
	[[[self window] delegate] selectAll:sender]; // to pass it to image matrix
}
- (void)keyDown:(NSEvent *)e {
	unichar c = [[e characters] characterAtIndex:0];
	if (c == NSPageUpFunctionKey || c == NSPageDownFunctionKey)
		if ([self frame].size.height > [[self superview] frame].size.height)
			[[self superview] keyDown:e]; // scroll ourselves
		else
			[[[self window] delegate] fakeKeyDown:e]; // scroll img matrix
	else
		[super keyDown:e];
}
@end

// for drag-n-drop visual feedback
@interface DYTransparentGreyView : NSView
@end
@implementation DYTransparentGreyView
- (void)drawRect:(NSRect)rect {
	[[[NSColor lightGrayColor] colorWithAlphaComponent:0.5] set];
	[NSBezierPath fillRect:rect];
}
@end

@implementation DYCreeveyBrowser
//why doesn't IB let me set this as a custom class of an NSBrowser???
//it calls a different init method
- (id)initWithFrame:(NSRect)frameRect {
	if (self = [super initWithFrame:frameRect]) {
		[self setMatrixClass:[DYCreeveyBrowserMatrix class]];
		[self setTitled:NO];
		[self setHasHorizontalScroller:YES];
		[self setCellClass:[DYBrowserCell class]];
		[[self cellPrototype] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]-1]];
		[self setAllowsEmptySelection:NO];
		[self setColumnResizingType:NSBrowserUserColumnResizing];
		[self setPrefersAllColumnUserResizing:YES];
		
		typedString = [[NSMutableString alloc] init];
		[self registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
		greyview = [[DYTransparentGreyView alloc] initWithFrame:NSZeroRect];
	}
	return self;
}

- (void)dealloc {
	[typedString release];
	[super dealloc];
}

#define KEYPRESS_INTERVAL 0.5

- (void)keyDown:(NSEvent *)e {
	if (![[self delegate] respondsToSelector:@selector(browser:typedString:inColumn:)]) {
		[super keyDown:e];
		return;
	}
	NSString *s = [e characters];
	if (![s length])
		return; // dead keys return empty
	unichar c = [s characterAtIndex:0];
	if (![[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) {
		[typedString setString:@""];
		[super keyDown:e];
		return;
	}
	
	NSTimeInterval t = [e timestamp];
	if (t - lastKeyTime < KEYPRESS_INTERVAL)
		[typedString appendString:s];
	else
		[typedString setString:s];
	lastKeyTime = t;
	
	[[self delegate] browser:self typedString:typedString inColumn:[self selectedColumn]];
}

- (BOOL)sendAction {
	if ([[self delegate] respondsToSelector:@selector(browserWillSendAction:)])
		[[self delegate] browserWillSendAction:self];
	return [super sendAction];
}

#pragma mark dragging stuff
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    NSPasteboard *pboard;
    NSDragOperation sourceDragMask;
	
    sourceDragMask = [sender draggingSourceOperationMask];
	pboard = [sender draggingPasteboard];
	
    if ( [[pboard types] containsObject:NSFilenamesPboardType] ) {
        if (sourceDragMask & NSDragOperationGeneric) {
			[greyview setFrame:[self bounds]];
			[self addSubview:greyview];
            return NSDragOperationGeneric;
        }
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
    NSPasteboard *pboard;
    NSDragOperation sourceDragMask;
    sourceDragMask = [sender draggingSourceOperationMask];
    pboard = [sender draggingPasteboard];
    if ( [[pboard types] containsObject:NSFilenamesPboardType] ) {
        NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
		
		
        if (sourceDragMask & NSDragOperationGeneric) {
			
            [[[self window] delegate] openFiles:files withSlideshow:NO]; // **
			
        }
		
    }
    return YES;
}

@end
