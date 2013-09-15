//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "DYWrappingMatrix.h"
#import "NSArrayIndexSetExtension.h"
#import "NSStringDYBasePathExtension.h"

#define MAX_CELL_WIDTH  180
// max height is 3/4 * max width
#define MIN_CELL_WIDTH  80
#define PADDING 16

@interface NSObject(DYWrappingMatrixTrasher)
- (IBAction)moveToTrash:(id)sender;
@end

static NSRect ScaledCenteredRect(NSSize sourceSize, NSRect boundsRect) {
	NSRect destinationRect;
	// float tmp;
	float centerX, centerY;
	centerX = boundsRect.origin.x + boundsRect.size.width/2;
	centerY = boundsRect.origin.y + boundsRect.size.height/2;
	
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
	destinationRect.origin.x = centerX - destinationRect.size.width/2;
	destinationRect.origin.y = centerY - destinationRect.size.height/2;
	destinationRect = NSIntegralRect(destinationRect); // make them integers, dammit
	return destinationRect;
}

@implementation DYWrappingMatrix

+ (Class)cellClass { return [NSActionCell class]; }
	// NSActionCell or subclass required for target/action

// services stuff
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
	// ** repeated from mouseDown
	NSEnumerator *e = [[cells subarrayWithIndexSet:selectedIndexes] objectEnumerator];
	id obj; NSMutableArray *files = [NSMutableArray array];
	while (obj = [e nextObject]) {
		[files addObject:[obj representedObject]];
	}
	return [pboard setPropertyList:files forType:NSFilenamesPboardType];
}

- (id)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect]) != nil) {
		cells = [[NSMutableArray alloc] initWithCapacity:100];
		selectedIndexes = [[NSMutableIndexSet alloc] init];
		cellWidth = 120;
		
		[self registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
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
	[cells release];
	[selectedIndexes release];
	[super dealloc];
}

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView { return YES; }
- (BOOL)isFlipped { return YES; }


- (NSSize)cellSize { return NSMakeSize(cellWidth,cellWidth*3/4); }

- (void)calculateCellSizes {
	float self_w = [self bounds].size.width;
	cellHeight = cellWidth*3/4;
	numCols = (int)(self_w)/((int)cellWidth + PADDING/2);
	if (numCols == 0) numCols = 1;
	columnSpacing = (self_w - numCols*cellWidth)/numCols;
	area_w = (int)(cellWidth + columnSpacing);
	area_h = (int)(cellHeight + PADDING);
}
- (int)point2cellnum:(NSPoint)p {
	int col = MIN(numCols-1, (int)p.x/area_w); if (col < 0) col = 0;
	int row = (int)p.y/area_h;
	int n = col + numCols*row; if (n<0) n=0;
	return n; // n might be > numCells-1
}
- (NSRect)imageRectForIndex:(unsigned int)n {
	id c = [cells objectAtIndex:n];
	int row, col;
	row = n/numCols;
	col = n%numCols;
	NSRect cellRect = NSMakeRect(cellWidth*col + columnSpacing*(col + 0.5),
								 cellHeight*row + PADDING*(row+0.5),
								 cellWidth, cellHeight);
	return ScaledCenteredRect([[c image] size], cellRect);
}

- (unsigned int)draggingSourceOperationMaskForLocal:(BOOL)isLocal {
	return isLocal ? NSDragOperationNone :
	NSDragOperationGeneric | NSDragOperationCopy | NSDragOperationDelete;
	// NSDragOperationLink creates aliases in the finder
}

- (void)draggedImage:(NSImage *)anImage endedAt:(NSPoint)aPoint operation:(NSDragOperation)operation {
	if (operation != NSDragOperationDelete)
		return;
	[[self target] moveToTrash:nil]; // **
}


- (void)mouseDown:(NSEvent *)theEvent {
	[[self window] makeFirstResponder:self];
	BOOL keepOn = YES;
	char doDrag = 0;
	int cellNum, a, b, i;
	NSRange draggedRange;
	NSMutableIndexSet *oldSelection = [[NSMutableIndexSet alloc] initWithIndexSet:selectedIndexes];
	BOOL shiftKeyDown = ([theEvent modifierFlags] & NSShiftKeyMask) != 0;
	BOOL cmdKeyDown = ([theEvent modifierFlags] & NSCommandKeyMask) != 0;
	[self calculateCellSizes];

	NSPoint mouseLoc = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	NSPoint mouseDownLoc = mouseLoc;
	int mouseDownCellNum = [self point2cellnum:mouseLoc];
	if (![selectedIndexes containsIndex:mouseDownCellNum] && !shiftKeyDown && !cmdKeyDown) {
		[oldSelection removeAllIndexes];
	}
	if (!cmdKeyDown && mouseDownCellNum < numCells &&
		([selectedIndexes containsIndex:mouseDownCellNum] ||
		 NSPointInRect(mouseLoc, [self imageRectForIndex:mouseDownCellNum]))) {
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
				[self setNeedsDisplay:YES];
				break;
            case NSLeftMouseUp:
				if ([theEvent clickCount] == 2)
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
		NSEnumerator *e = [[cells subarrayWithIndexSet:selectedIndexes] objectEnumerator];
		id obj; NSMutableArray *files = [NSMutableArray array];
		while (obj = [e nextObject]) {
			[files addObject:[obj representedObject]];
		}
		//pboard
		NSPasteboard *pboard = [NSPasteboard pasteboardWithName:NSDragPboard];
		[pboard declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType]
					   owner:nil];
		[pboard setPropertyList:files forType:NSFilenamesPboardType];
		//loc, img
		NSImage *dragImg, *transparentImg;
		NSPoint imgLoc = mouseDownLoc;
		if ([selectedIndexes count] == 1) {
			dragImg = [[cells objectAtIndex:[selectedIndexes firstIndex]] image];
			NSRect imgRect = [self imageRectForIndex:mouseDownCellNum];
			imgLoc = imgRect.origin;
			imgLoc.y += imgRect.size.height;
		} else {
			dragImg = [NSImage imageNamed:@"multipledocs"];
			imgLoc.x -= [dragImg size].width/2;
			imgLoc.y += [dragImg size].height/2; // we're using flipped coords, calc bottom left
		}
		transparentImg = [[[NSImage alloc] initWithSize:[dragImg size]] autorelease];
		[transparentImg lockFocus];
		[dragImg compositeToPoint:NSZeroPoint operation:NSCompositeCopy fraction:0.3];
		[transparentImg unlockFocus];
		[self dragImage:transparentImg
					 at:imgLoc
				 offset:NSMakeSize(mouseLoc.x - mouseDownLoc.x,
								   -(mouseLoc.y - mouseDownLoc.y))
				  event:theEvent
			 pasteboard:pboard source:self slideBack:YES];
	}
	[oldSelection release];
}

- (void)resize:(id)anObject { // called by notification center
	[self calculateCellSizes];
	NSSize mySize = [self frame].size;
	int numRows = numCells == 0 ? 1 : (numCells-1)/numCols + 1;
	float h = MAX(numRows*area_h, [[self superview] frame].size.height);
	if (mySize.height != h) {
		mySize.height = h;
		[self setFrameSize:mySize];
	}
}


- (void)drawRect:(NSRect)rect {
	[[NSColor whiteColor] set];
	[NSBezierPath fillRect:rect];
	[self calculateCellSizes];
	
	int i, row, col;
	NSRect areaRect = NSMakeRect(0, 0, area_w, area_h);
	NSRect cellRect = NSMakeRect(0, 0, cellWidth, cellHeight);
	NSWindow *myWindow = [self window];
	for (i=0; i<numCells; ++i) {
		row = i/numCols;
		col = i%numCols;
		areaRect.origin = NSMakePoint(area_w*col, area_h*row);
		if (![self needsToDrawRect:areaRect]) continue; // 10.3
		if ([selectedIndexes containsIndex:i]) {
			[([myWindow firstResponder] == self && [myWindow isKeyWindow]
			  ? [NSColor selectedTextBackgroundColor]
			  : [NSColor lightGrayColor]) set];
			[NSBezierPath fillRect:areaRect];
		}
		cellRect.origin = NSMakePoint(cellWidth*col + columnSpacing*(col + 0.5),
									  cellHeight*row + PADDING*(row+0.5));
		if (![self needsToDrawRect:cellRect]) continue;
		[[cells objectAtIndex:i] drawWithFrame:cellRect inView:self];
	}
	if (dragEntered) {
		[[[NSColor lightGrayColor] colorWithAlphaComponent:0.5] set];
		[NSBezierPath fillRect:rect];
	}
}

- (NSMutableIndexSet *)selectedIndexes {
	return selectedIndexes;
}

- (IBAction)selectAll:(id)sender {
	[selectedIndexes addIndexesInRange:NSMakeRange(0,numCells)];
	[self setNeedsDisplay:YES];
}

- (IBAction)selectNone:(id)sender {
	[selectedIndexes removeAllIndexes];
	[self setNeedsDisplay:YES];
}

- (unsigned int)numCells {
	return numCells;
}

- (void)addSelectedIndex:(unsigned int)i {
	[selectedIndexes addIndex:i];
}

//- (void)setImage:(NSImage *)theImage forIndex:(unsigned int)i {
//	if (i >= numCells) return;
//	NSImageCell *c = [cells objectAtIndex:i];
//	[c setImage:theImage];
//	[self setNeedsDisplay:YES];
//}

- (void)addImage:(NSImage *)theImage withFilename:(NSString *)s{
	// once we create a cell, we never dealloc it
	// keep track using numCells
	unsigned int i = numCells;
	NSImageCell *c;
	if ([cells count] < ++numCells) {
		c = [[NSImageCell alloc] initImageCell:theImage];
		[cells addObject:c]; [c release];
	} else {
		c = [cells objectAtIndex:i];
		[c setImage:theImage];
	}
	[c setRepresentedObject:s];
	[self resize:nil];
	[self setNeedsDisplay:YES];
	//[self calculateCellSizes];
	//[self setNeedsDisplayInRect:NSMakeRect(area_w*(i%numCols), area_h*(i/numCols),
	//									   area_w, area_h)];
}

- (void)removeAllImages {
	numCells = 0;
	[selectedIndexes removeAllIndexes];
	[self resize:nil];
	[self setNeedsDisplay:YES];
}
/*
- (void)removeSelectedImages {
	numCells -= [selectedIndexes count];
	[cells removeObjectsFromIndices:selectedIndexes];
	[selectedIndexes removeAllIndexes];
	[self setNeedsDisplay:YES];
}
*/
- (void)removeImageAtIndex:(unsigned int)i {
	//** check if i is in range?
	numCells--;
	[cells removeObjectAtIndex:i];
	[selectedIndexes shiftIndexesStartingAtIndex:i+1 by:-1];
	[self resize:nil];
	[self setNeedsDisplay:YES];
}


// dragging stuff
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
			
            [[NSApp delegate] application:nil
								openFiles:files]; // **
			
        }
		
    }
    return YES;
}

@end
