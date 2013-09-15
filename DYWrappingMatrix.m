//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "DYWrappingMatrix.h"
#import "NSArrayIndexSetExtension.h"
#import "NSIndexSetSymDiffExtension.h"
#import "CreeveyMainWindowController.h"


#define MAX_CELL_WIDTH  160
#define MIN_CELL_WIDTH  40
#define DEFAULT_CELL_WIDTH 120
// height is 3/4 * width
#define PADDING 16
#define VERTPADDING 16

/* there are three methods called from a separate thread:
   addSelectedIndex
   removeAllImages
   addImage:withFilename:

   i've tried to make them thread-safe
 */


static NSRect ScaledCenteredRect(NSSize sourceSize, NSRect boundsRect) {
	NSRect destinationRect;
	
	// size
	if (sourceSize.width <= boundsRect.size.width
		&& sourceSize.height <= boundsRect.size.height) {
		destinationRect.size = sourceSize;
	} else {
		float w_ratio, h_ratio;
		w_ratio = boundsRect.size.width/sourceSize.width;
		h_ratio = boundsRect.size.height/sourceSize.height;
		if (w_ratio < h_ratio) { // the side w/ bigger ratio needs to be shrunk
			destinationRect.size.height = sourceSize.height*w_ratio;
			destinationRect.size.width = boundsRect.size.width;
		} else {
			destinationRect.size.width = sourceSize.width*h_ratio;
			destinationRect.size.height = boundsRect.size.height;
		}
	}
	
	// origin
	destinationRect.origin.x = (int)(NSMidX(boundsRect) - destinationRect.size.width/2);
	destinationRect.origin.y = (int)(NSMidY(boundsRect) - destinationRect.size.height/2);
	//return NSIntegralRect(destinationRect);
	return destinationRect;
}

@interface DYWrappingMatrix (Private)
- (void)resize:(id)anObject; // called to recalc, set frame height
@end

@implementation DYWrappingMatrix

+ (Class)cellClass { return [NSActionCell class]; }
	// NSActionCell or subclass required for target/action

#pragma mark services stuff
+ (void)initialize
{
    static BOOL initialized = NO;
    /* Make sure code only gets executed once. */
    if (initialized) return;
    initialized = YES;
    id sendTypes = [NSArray arrayWithObject:NSFilenamesPboardType];
    [NSApp registerServicesMenuSendTypes:sendTypes
							 returnTypes:nil];
    return;
}
+ (NSSize)maxCellSize { return NSMakeSize(MAX_CELL_WIDTH,MAX_CELL_WIDTH*3/4); }

- (id)validRequestorForSendType:(NSString *)sendType
					 returnType:(NSString *)returnType {
    if (!returnType && [sendType isEqual:NSFilenamesPboardType]) {
		if ([[self selectedIndexes] count] > 0)
			return self;
	}
    return [super validRequestorForSendType:sendType
								 returnType:returnType];
}
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard
							 types:(NSArray *)types {
    if (![types containsObject:NSFilenamesPboardType])
        return NO;
 	[pboard declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType]
				   owner:nil];
	return [pboard setPropertyList:[filenames subarrayWithIndexSet:selectedIndexes]
						   forType:NSFilenamesPboardType];
}

#pragma mark init stuff
- (id)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect]) != nil) {
		myCell = [[NSImageCell alloc] initImageCell:nil];
		images = [[NSMutableArray alloc] initWithCapacity:100];
		filenames = [[NSMutableArray alloc] initWithCapacity:100];
		selectedIndexes = [[NSMutableIndexSet alloc] init];
		[self setCellWidth:DEFAULT_CELL_WIDTH];
		
		[self registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
		
		[[[NSThread currentThread] threadDictionary] setObject:@"1" forKey:@"DYWrappingMatrixMainThread"];
	}
	return self;
}

- (void)awakeFromNib {
	[[self enclosingScrollView] setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(resize:)
												 name:NSViewFrameDidChangeNotification
											   object:[self enclosingScrollView]];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[myCell release];
	[images release];
	[filenames release];
	[selectedIndexes release];
	[super dealloc];
}

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView { return YES; }
- (BOOL)isFlipped { return YES; }

#pragma mark display/drag stuff
- (NSSize)cellSize { return NSMakeSize(cellWidth,cellWidth*3/4); }
- (float)maxCellWidth { return MAX_CELL_WIDTH; }
- (float)minCellWidth { return MIN_CELL_WIDTH; }
- (float)cellWidth { return cellWidth; }
- (void)setCellWidth:(float)w {
	cellWidth = w;
	[self resize:nil];
	[self setNeedsDisplay:YES]; // ** I suppose should call on main thread too
}


- (void)calculateCellSizes {
	// all values dependent on bounds width, cellWidth(, numCells for resize:)
	float self_w = [self bounds].size.width;
	cellHeight = cellWidth*3/4;
	numCols = (int)(self_w)/((int)cellWidth + PADDING/2);
	if (numCols == 0) numCols = 1;
	columnSpacing = (self_w - numCols*cellWidth)/numCols;
	area_w = cellWidth + columnSpacing;
	area_h = cellHeight + VERTPADDING;
}
- (int)point2cellnum:(NSPoint)p {
	int col = MIN(numCols-1, (int)p.x/area_w); if (col < 0) col = 0;
	int row = (int)p.y/area_h;
	int n = col + numCols*row; if (n<0) n=0;
	return n; // n might be > numCells-1
}
- (NSRect)cellnum2rect:(unsigned int)n {
	int row, col;
	row = n/numCols;
	col = n%numCols;
	return NSMakeRect(area_w*col,area_h*row,area_w, area_h);
}
- (NSRect)imageRectForIndex:(unsigned int)n {
	int row, col;
	row = n/numCols;
	col = n%numCols;
	return ScaledCenteredRect([[images objectAtIndex:n] size],
							  NSMakeRect(cellWidth*col + columnSpacing*(col + 0.5),
										 cellHeight*row + VERTPADDING*(row+0.5),
										 cellWidth, cellHeight)); // rect for cell only
}

- (void)selectionNeedsDisplay:(unsigned int)n {
	int row, col;
	row = n/numCols;
	col = n%numCols;
	float x, y, x2, y2;
	NSRect r = [self imageRectForIndex:n]; // use this because it's integral
	// top left of area
	x = area_w*col;                      y = area_h*row;
	// bottom right of cell
	x2 = r.origin.x + r.size.width;     y2 = r.origin.y + r.size.height;
	[self setNeedsDisplayInRect:NSMakeRect(x,y, area_w, r.origin.y-y)]; // top
	[self setNeedsDisplayInRect:NSMakeRect(x,y2, area_w, y+area_h-y2)]; // bottom
	[self setNeedsDisplayInRect:NSMakeRect(x,r.origin.y,
										   r.origin.x-x, r.size.height)]; // left
	[self setNeedsDisplayInRect:NSMakeRect(x2, r.origin.y,
										   x+area_w-x2,r.size.height)]; // right
}

- (unsigned int)draggingSourceOperationMaskForLocal:(BOOL)isLocal {
	return isLocal ? NSDragOperationNone :
	NSDragOperationGeneric | NSDragOperationCopy | NSDragOperationDelete;
	// NSDragOperationLink creates aliases in the finder
}

- (void)draggedImage:(NSImage *)anImage endedAt:(NSPoint)aPoint operation:(NSDragOperation)operation {
	if (operation != NSDragOperationDelete)
		return;
	if ([[self target] respondsToSelector:@selector(moveToTrash:)])
		[[self target] moveToTrash:nil];
}

#pragma mark event stuff
- (void)mouseDown:(NSEvent *)theEvent {
	[[self window] makeFirstResponder:self];
	BOOL keepOn = YES;
	char doDrag = 0;
	int cellNum, a, b, i;
	NSRange draggedRange;
	NSMutableIndexSet *oldSelection = [selectedIndexes mutableCopy];
	NSMutableIndexSet *lastIterationSelection = [oldSelection mutableCopy];
	BOOL shiftKeyDown = ([theEvent modifierFlags] & NSShiftKeyMask) != 0;
	BOOL cmdKeyDown = ([theEvent modifierFlags] & NSCommandKeyMask) != 0;

	NSPoint mouseLoc = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	NSPoint mouseDownLoc = mouseLoc;
	int mouseDownCellNum = [self point2cellnum:mouseLoc];
	if (![selectedIndexes containsIndex:mouseDownCellNum] && !shiftKeyDown && !cmdKeyDown) {
		[oldSelection removeAllIndexes];
	}
	if (!cmdKeyDown && mouseDownCellNum < numCells &&
		([selectedIndexes containsIndex:mouseDownCellNum] ||
		 NSPointInRect(mouseLoc, [self imageRectForIndex:mouseDownCellNum]) && !shiftKeyDown)) {
		// we should drag if started in selection
		// or dragging the actual image
		doDrag = 1;
	} else if (shiftKeyDown) {
		// if shift key is down, it's as if we had dragged from the end of the old selection
		mouseDownCellNum = mouseDownCellNum < [selectedIndexes lastIndex]
			? [selectedIndexes firstIndex]
			: [selectedIndexes lastIndex];
	}
	[NSEvent startPeriodicEventsAfterDelay:0 withPeriod:0.3];
    while (1) {
		mouseLoc = [theEvent locationInWindow];
        switch ([theEvent type]) {
			case NSPeriodic: // NOT nsperiodicmask, duh
				mouseLoc = [[self window] mouseLocationOutsideOfEventStream];
			case NSLeftMouseDown: // for the first iteration only
            case NSLeftMouseDragged:
				mouseLoc = [self convertPoint:mouseLoc fromView:nil];
				if (doDrag && [theEvent type] == NSLeftMouseDragged) {
					doDrag = 2;
					keepOn = NO;
					break;
				}
				cellNum = [self point2cellnum:mouseLoc];
				[selectedIndexes removeAllIndexes];
				[selectedIndexes addIndexes:oldSelection];
				// calculate the dragged range
				if (cellNum < mouseDownCellNum) {
					a = cellNum; b = mouseDownCellNum;
				} else {
					a = mouseDownCellNum; b = cellNum;
				}
				if (b >= numCells) b = numCells-1;
				draggedRange.location = a;
				draggedRange.length = b<a ? 0 : b-a+1;
					// if selection outside of cells, skip to next event
				if (shiftKeyDown || !cmdKeyDown) // shift or no modifiers
					[selectedIndexes addIndexesInRange:draggedRange];
				else
					for (i=0; i<draggedRange.length; ++i)
						if ([selectedIndexes containsIndex:draggedRange.location+i])
							[selectedIndexes removeIndex:draggedRange.location+i];
						else
							[selectedIndexes addIndex:draggedRange.location+i];
				if (![self mouse:mouseLoc inRect:[self visibleRect]])
					[self autoscroll:theEvent]; // always check visibleRect for autoscroll
				[lastIterationSelection symmetricDifference:selectedIndexes];
				if ([lastIterationSelection count]) {
					// if selection changed...
					[self updateStatusString];
					for (i=[lastIterationSelection firstIndex]; i != NSNotFound; i = [lastIterationSelection indexGreaterThanIndex:i]) {
						[self selectionNeedsDisplay:i];
					}
				}
				[lastIterationSelection removeAllIndexes];
				[lastIterationSelection addIndexes:selectedIndexes];
				break;
            case NSLeftMouseUp:
				if ([theEvent clickCount] == 2
					&& mouseDownCellNum < numCells
					&& !shiftKeyDown && !cmdKeyDown)
					[self sendAction:[self action] to:[self target]];
				keepOn = NO;
				break;
            default:
				break;
        }
		if (!keepOn) break;
        theEvent = [[self window] nextEventMatchingMask:
			NSLeftMouseUpMask | NSLeftMouseDraggedMask | NSPeriodicMask];
    }
	[NSEvent stopPeriodicEvents];
	if (doDrag == 2) {
		//pboard
		NSPasteboard *pboard = [NSPasteboard pasteboardWithName:NSDragPboard];
		[pboard declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType]
					   owner:nil];
		[pboard setPropertyList:[filenames subarrayWithIndexSet:selectedIndexes]
						forType:NSFilenamesPboardType];
		//loc, img
		NSImage *dragImg, *transparentImg;
		NSPoint imgLoc = mouseDownLoc;
		NSSize imgSize;
		if ([selectedIndexes count] == 1) {
			dragImg = [images objectAtIndex:[selectedIndexes firstIndex]];
			NSRect imgRect = [self imageRectForIndex:mouseDownCellNum];
			imgSize = imgRect.size;
			imgLoc = imgRect.origin;
			imgLoc.y += imgRect.size.height;
		} else {
			dragImg = [NSImage imageNamed:@"multipledocs"];
			imgSize = [dragImg size];
			imgLoc.x -= [dragImg size].width/2;
			imgLoc.y += [dragImg size].height/2; // we're using flipped coords, calc bottom left
		}
		transparentImg = [[[NSImage alloc] initWithSize:imgSize] autorelease];
		[transparentImg lockFocus];
		[dragImg drawInRect:NSMakeRect(0,0,imgSize.width,imgSize.height)
				   fromRect:NSMakeRect(0,0,[dragImg size].width,[dragImg size].height)
				  operation:NSCompositeCopy fraction:0.3];
		[transparentImg unlockFocus];
		[self dragImage:transparentImg
					 at:imgLoc
				 offset:NSMakeSize(mouseLoc.x - mouseDownLoc.x,
								   -(mouseLoc.y - mouseDownLoc.y))
				  event:theEvent
			 pasteboard:pboard source:self slideBack:YES];
	}
	[oldSelection release];
	[lastIterationSelection release];
}

- (void)resize:(id)anObject { // called by notification center
	[self calculateCellSizes];
	NSSize mySize = [self frame].size;
	int numRows = numCells == 0 ? 0 : (numCells-1)/numCols + 1;
	float h = MAX(numRows*area_h, [[self superview] frame].size.height);
	if (mySize.height != h) {
		mySize.height = h;
		[self setFrameSize:mySize];
	}
}

// always call this if called from another thread
// calling from main seems to make drawing weird
- (void)setNeedsDisplayInRect2:(NSRect)invalidRect {
//	if ([[[NSThread currentThread] threadDictionary] objectForKey:@"DYWrappingMatrixMainThread"])
//		[super setNeedsDisplayInRect:(NSRect)invalidRect];
//	else
		[self performSelectorOnMainThread:@selector(setNeedsDisplayInRectThreaded:)
							   withObject:[NSValue valueWithRect:invalidRect]
							waitUntilDone:NO];
}

- (void)setNeedsDisplayInRectThreaded:(NSValue *)v {
	[self setNeedsDisplayInRect:[v rectValue]];
}
- (void)setNeedsDisplayThreaded {
	[self setNeedsDisplay:YES];
}

// needsToDrawRect: is broken in Panther (10.3)
// see TN2107
// purportedly fixed in 10.4
- (BOOL)needsToDrawRect:(NSRect)rect rectListBounds:(NSRect)rectListBounds
{
    const NSRect *rectList;
    int count;
    int i;
    
    if (!NSIntersectsRect(rect, rectListBounds)) {
        return NO;
    }
    [self getRectsBeingDrawn:&rectList count:&count];
    if (count == 1) {
        return YES;
    } else {
        for (i = 0; i < count; i++) {
            if (NSIntersectsRect(rect, rectList[i])) {
                return YES;
            }
        }
        return NO;
    }
}

- (void)drawRect:(NSRect)rect {
	NSGraphicsContext *cg = [NSGraphicsContext currentContext];
	NSImageInterpolation oldInterp = [cg imageInterpolation];
	[cg setImageInterpolation:NSImageInterpolationNone];
	
	[[NSColor whiteColor] set];
	[NSBezierPath fillRect:rect];
	//NSLog(@"---------------------------");
	int i, row, col;
	NSRect areaRect = NSMakeRect(0, 0, area_w, area_h);
	NSRect cellRect;
	NSWindow *myWindow = [self window];
	for (i=0; i<numCells; ++i) {
		row = i/numCols;
		col = i%numCols;
		areaRect.origin = NSMakePoint(area_w*col, area_h*row);
		if (![self needsToDrawRect:areaRect rectListBounds:rect]) continue; // 10.3
		// color the selection
		if ([selectedIndexes containsIndex:i]) {
			[([myWindow firstResponder] == self && [myWindow isKeyWindow]
			  ? [NSColor selectedTextBackgroundColor]
			  : [NSColor lightGrayColor]) set];
			[NSBezierPath fillRect:areaRect];
		}
		// calculate drawing area for thumb
		cellRect = [self imageRectForIndex:i];
		if (![self needsToDrawRect:cellRect	rectListBounds:rect]) {
			//NSLog(@"skipped cell %i", i);
			continue;	
		}
		[myCell setImage:[images objectAtIndex:i]];
		[[NSColor whiteColor] set]; // white bg for transparent imgs
		NSRectFill(cellRect);
		[myCell drawWithFrame:cellRect inView:self];
	}
	if (dragEntered) {
		[[[NSColor lightGrayColor] colorWithAlphaComponent:0.5] set];
		[NSBezierPath fillRect:rect];
	}
	[cg setImageInterpolation:oldInterp];
}
- (void)scrollSelectionToVisible:(unsigned int)n {
	[self updateStatusString];
	NSRect r = [self cellnum2rect:n];
	[self selectionNeedsDisplay:n];
	// round down for better auto-scrolling
	r.size.height = (int)r.size.height;
	if (![self mouse:r.origin inRect:[self visibleRect]])
		[self scrollRectToVisible:r];
}
- (void)keyDown:(NSEvent *)e {
	unichar c = [[e characters] characterAtIndex:0];
	switch (c) {
		case NSRightArrowFunctionKey:
		case NSLeftArrowFunctionKey:
		case NSDownArrowFunctionKey:
		case NSUpArrowFunctionKey:
			break;
		default:
			[super keyDown:e];
			return;
	}
	unsigned int n;
	if ([selectedIndexes count] == 1) {
		n = [selectedIndexes firstIndex];
		[self selectionNeedsDisplay:n];
		switch (c) {
			case NSRightArrowFunctionKey: if (n<numCells-1) n++; break;
			case NSLeftArrowFunctionKey:  if (n>0) n--; break;
			case NSDownArrowFunctionKey:
				if ((numCells - 1 - n) < numCols) n = numCells-1;
				else n += numCols;
				break;
			case NSUpArrowFunctionKey:
				if (numCols > n) n = 0;
				else n -= numCols;
				break;
			default: break;
		}
		[selectedIndexes removeAllIndexes];
	} else if ([selectedIndexes count] == 0) {
		switch (c) {
			case NSRightArrowFunctionKey:
			case NSDownArrowFunctionKey:
				n = 0;
				break;
			case NSLeftArrowFunctionKey:
			case NSUpArrowFunctionKey:
			default: // keep the compiler happy about n
				n = numCells-1;
				break;
		}
	} else
		return;
	[selectedIndexes addIndex:n];
	[self scrollSelectionToVisible:n];
}

- (void)selectIndex:(unsigned int)i {
	// redraw the old selection (assume this only gets called if single selection)
	if ([selectedIndexes count])
		[self selectionNeedsDisplay:[selectedIndexes firstIndex]];
	
	[selectedIndexes removeAllIndexes];
	[selectedIndexes addIndex:i];
	[self scrollSelectionToVisible:i];
}

#pragma mark selection stuff
- (NSMutableIndexSet *)selectedIndexes {
	return selectedIndexes;
}

- (NSArray *)filenames {
	return filenames;
}

- (NSArray *)selectedFilenames {
	return [filenames subarrayWithIndexSet:selectedIndexes];
}

- (NSString *)firstSelectedFilename {
	return [filenames objectAtIndex:[selectedIndexes firstIndex]];
}

- (IBAction)selectAll:(id)sender {
	[selectedIndexes addIndexesInRange:NSMakeRange(0,numCells)];
	unsigned int i;
	for (i=0; i<numCells; ++i) {
		[self selectionNeedsDisplay:i];
	}
	[self updateStatusString];
}

- (IBAction)selectNone:(id)sender {
	[selectedIndexes removeAllIndexes];
	unsigned int i;
	for (i=0; i<numCells; ++i) {
		[self selectionNeedsDisplay:i];
	}
	[self updateStatusString];
}

- (unsigned int)numCells {
	return numCells;
}

- (void)addSelectedIndex:(unsigned int)i {
	[selectedIndexes addIndex:i];
	[self setNeedsDisplayInRect2:[self cellnum2rect:i]];
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(updateStatusString)
											   object:nil];
	[self performSelectorOnMainThread:@selector(updateStatusString)
						   withObject:nil waitUntilDone:NO];
	//[self updateStatusString];
}

// call this when an image changes (filename is already set)
- (void)setImage:(NSImage *)theImage forIndex:(unsigned int)i {
	if (i >= numCells) return;
	[images replaceObjectAtIndex:i withObject:theImage];
	[self setNeedsDisplayInRect2:[self cellnum2rect:i]];
}

- (void)updateStatusString {
	if ([delegate respondsToSelector:@selector(wrappingMatrix:selectionDidChange:)]) {
		[delegate wrappingMatrix:self selectionDidChange:selectedIndexes];
	}
}

#pragma mark add/delete images stuff
- (void)addImage:(NSImage *)theImage withFilename:(NSString *)s{
	[images addObject:theImage];
	[filenames addObject:s];
	numCells++;
	//[self resize:nil];
	[self performSelectorOnMainThread:@selector(resize:)
						   withObject:nil waitUntilDone:NO];
	[self setNeedsDisplayInRect2:[self cellnum2rect:numCells-1]];
}

- (void)removeAllImages {
	numCells = 0;
	[images removeAllObjects];
	[filenames removeAllObjects];
	// ** [self resize:nil];
	//[self setNeedsDisplay:YES]; // ** I suppose should call on main thread too
	[self performSelectorOnMainThread:@selector(resize:)
						   withObject:nil waitUntilDone:NO];
	[self performSelectorOnMainThread:@selector(setNeedsDisplayThreaded)
						   withObject:nil waitUntilDone:NO];
	[self selectNone:nil]; // **
}
/*
- (void)removeSelectedImages {
	numCells -= [selectedIndexes count];
	[images removeObjectsFromIndices:selectedIndexes];
	[selectedIndexes removeAllIndexes];
	[self setNeedsDisplay:YES];
}
*/
- (void)removeImageAtIndex:(unsigned int)i {
	//** check if i is in range?
	numCells--;
	[images removeObjectAtIndex:i];
	[filenames removeObjectAtIndex:i];
	[selectedIndexes shiftIndexesStartingAtIndex:i+1 by:-1];
	[self resize:nil];
	do {
		[self setNeedsDisplayInRect:[self cellnum2rect:i]];
	} while (++i<=numCells);
	// use <=, not <, because we need to redraw the last cell, which has shifted
	[self updateStatusString];
}


#pragma mark more dragging stuff
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    NSPasteboard *pboard;
    NSDragOperation sourceDragMask;
	
    sourceDragMask = [sender draggingSourceOperationMask];
	pboard = [sender draggingPasteboard];
	
    if ( [[pboard types] containsObject:NSFilenamesPboardType] ) {
        if (sourceDragMask & NSDragOperationGeneric) {
			dragEntered = YES;
			[self setNeedsDisplay:YES];
            return NSDragOperationGeneric;
        }
    }
    return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender {
	dragEntered = NO;
	[self setNeedsDisplay:YES];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender {
	dragEntered = NO;
	[self setNeedsDisplay:YES];
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

- (void)setDelegate:(id)d {
	delegate = d; // NOT retained
}


@end
