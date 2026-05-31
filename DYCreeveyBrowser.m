//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "DYCreeveyBrowser.h"
#import "CreeveyMainWindowController.h"
#import "DYCarbonGoodies.h"

@interface DYCreeveyBrowser ()
@property (nonatomic, strong) NSMenu *contextMenu;
@end

@interface DYBrowserCell : NSBrowserCell {
	NSString *title;
	NSInteger _tag;
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
	if (_tag > 0) {
		NSMutableAttributedString *as = [self.attributedStringValue mutableCopy];
		[as applyFontTraits:NSItalicFontMask range:NSMakeRange(0, as.length)];
		self.attributedStringValue = as;
	}
	[super drawInteriorWithFrame:cellFrame inView:controlView];
	self.stringValue = myStringValue;
}

- (void)setTag:(NSInteger)tag {
	_tag = tag;
}

@end

@interface DYCreeveyBrowserMatrix : NSMatrix <NSMenuItemValidation,NSMenuDelegate> {
	NSCell *_contextMenuCell;
	BOOL _contextMenuCellOldHighlighted;
}
@end
@implementation DYCreeveyBrowserMatrix
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if (menuItem.action == @selector(selectAll:)) return YES;
	if ([menuItem.target isKindOfClass:[DYCreeveyBrowser class]]) return YES;
	return [super validateMenuItem:menuItem];
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

- (DYCreeveyBrowser *)enclosingBrowser {
	NSView *v = self;
	do v = v.superview; while (![v isKindOfClass:[DYCreeveyBrowser class]]);
	return (DYCreeveyBrowser *)v;
}

- (NSMenu *)menuForEvent:(NSEvent *)e {
	NSInteger row, col;
	if (![self getRow:&row column:&col forPoint:[self convertPoint:e.locationInWindow fromView:nil]]) return nil;
	NSMenu *menu = self.enclosingBrowser.contextMenu;
	menu.delegate = self;
	_contextMenuCell = [self cellAtRow:row column:0];
	_contextMenuCellOldHighlighted = _contextMenuCell.highlighted;
	_contextMenuCell.highlighted = YES;
	NSMenuItem *item = [menu itemAtIndex:0];
	item.title = [NSString stringWithFormat:NSLocalizedString(@"Open “%@” in Finder", @"open folder from directory browser context menu"), _contextMenuCell.title];
	item.representedObject = self;
	item.tag = row;
	return menu;
}

- (void)menuDidClose:(NSMenu *)menu {
	_contextMenuCell.highlighted = _contextMenuCellOldHighlighted;
	_contextMenuCell = nil;
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
	DYTransparentGreyView *greyview; // for drag-and-drop
}
@dynamic delegate; // use super.delegate

- (void)openFolderFromContextMenu:(NSMenuItem *)item {
	NSMatrix *m = item.representedObject;
	NSCell *cell = [m cellAtRow:item.tag column:0];
	NSString *filename = cell.stringValue;
// I don't think there's an easy way to catch events/messages to first responder without using a custom matrix class
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
	NSInteger n = [self columnOfMatrix:m];
	[self.delegate browser:self openFolderAtPath:[[self pathToColumn:n] stringByAppendingPathComponent:filename]];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
	if (self = [super initWithFrame:frameRect]) {
		[self setMatrixClass:[DYCreeveyBrowserMatrix class]];
#pragma GCC diagnostic pop
		self.titled = NO;
		self.hasHorizontalScroller = YES;
		[self setCellClass:[DYBrowserCell class]];
		[self.cellPrototype setFont:[NSFont systemFontOfSize:NSFont.smallSystemFontSize]];
		self.allowsEmptySelection = NO;
		self.columnResizingType = NSBrowserUserColumnResizing;
		self.prefersAllColumnUserResizing = NO;
		
		[self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
	}
	return self;
}

- (BOOL)sendAction {
	[self.delegate browserWillSendAction:self];
	return [super sendAction];
}

- (NSMenu *)contextMenu {
	if (!_contextMenu) {
		_contextMenu = [[NSMenu alloc] init];
		NSMenuItem *item = [[NSMenuItem alloc] init];
		item.target = self;
		item.action = @selector(openFolderFromContextMenu:);
		[_contextMenu addItem:item];
	}
	return _contextMenu;
}

#pragma mark dragging stuff
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    if ([sender.draggingPasteboard.types containsObject:NSPasteboardTypeFileURL]) {
        if (sender.draggingSourceOperationMask & NSDragOperationGeneric) {
			if (!greyview) greyview = [[DYTransparentGreyView alloc] initWithFrame:NSZeroRect];
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
