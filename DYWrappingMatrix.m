//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "DYWrappingMatrix.h"
#import "NSIndexSetSymDiffExtension.h"
#import "CreeveyMainWindowController.h"
#import "DYCarbonGoodies.h"

#import "DYImageCache.h" // kludge to access the thumbsCache
#import "CreeveyController.h"


#define MAX_EXIF_WIDTH  160
#define MIN_CELL_WIDTH  40
#define DEFAULT_CELL_WIDTH 120
// height is 3/4 * width
#define PADDING 16
#define VERTPADDING 16
#define DEFAULT_TEXTHEIGHT 12

/* there are some methods called in a separate thread:
   addSelectedIndex
   removeAllImages
   addImage:withFilename:
   imageWithFileInfoNeedsDisplay:

   i've tried to make them thread-safe
 */

@interface NSImage (ImageRotationAddition)
// helper method to generate a new NSImage and make it draw that instead.
- (NSImage *)rotateByExifOrientation:(unsigned short)n;
@end

@implementation NSImage (ImageRotationAddition)
- (NSImage *)rotateByExifOrientation:(unsigned short)n; {
	NSSize newSize = [self size];
	if (n >= 5) {
		// if rotating, swap the width/height
		float tmp;
		tmp = newSize.width;
		newSize.width = newSize.height;
		newSize.height = tmp;
	}
	NSImage *rotImg = [[[NSImage alloc] initWithSize:newSize] autorelease];
	[rotImg lockFocus];
	int r = 0, x0 = 0, y0 = 0; BOOL imgFlipped = NO;
	switch (n) {
		case 4: r = 180; case 2: imgFlipped = YES; break;
		case 5: imgFlipped = YES; case 8: r = 90; break;
		case 7: imgFlipped = YES; case 6: r = -90; break;
		case 3: r = 180; break;
	}
	switch (n) {
		case 2: x0 = -newSize.width; break;
		case 3: x0 = -newSize.width; y0 = -newSize.height; break;
		case 4: y0 = -newSize.height; break;
		case 5: x0 = -newSize.height; y0 = -newSize.width; break;
		case 6: x0 = -newSize.height; break;
		case 8: y0 = -newSize.width; break;
	}
	NSAffineTransform *transform = [NSAffineTransform transform];
	[transform rotateByDegrees:r];
	if (imgFlipped)
		[transform scaleXBy:-1 yBy:1];
	[transform concat];
	
	[self drawAtPoint:NSMakePoint(x0, y0)
			 fromRect:NSZeroRect
			operation:NSCompositeSourceOver  
			 fraction:1.0];
	[rotImg unlockFocus];
	return rotImg;
}
@end




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
- (NSImage *)imageForIndex:(NSUInteger)n;
- (NSSize)imageSizeForIndex:(NSUInteger)n;
- (unsigned short)exifOrientationForIndex:(NSUInteger)n;
@end

@implementation DYWrappingMatrix

+ (Class)cellClass { return [NSActionCell class]; }
	// NSActionCell or subclass required for target/action

#pragma mark services stuff
+ (void)initialize
{
	// prefs stuff
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[dict setObject:[NSArchiver archivedDataWithRootObject:[NSColor whiteColor]] forKey:@"DYWrappingMatrixBgColor"];
	[dict setObject:[NSNumber numberWithBool:NO] forKey:@"DYWrappingMatrixAllowMove"];
	[dict setObject:@"160" forKey:@"DYWrappingMatrixMaxCellWidth"];
	[defaults registerDefaults:dict];
	
    static BOOL initialized = NO;
    /* Make sure code only gets executed once. */
    if (initialized) return;
    initialized = YES;
    id sendTypes = [NSArray arrayWithObject:NSFilenamesPboardType];
    [NSApp registerServicesMenuSendTypes:sendTypes
							 returnTypes:nil];
    return;
}
+ (NSSize)maxCellSize {
	int w = [[NSUserDefaults standardUserDefaults] integerForKey:@"DYWrappingMatrixMaxCellWidth"];
	return NSMakeSize(w, w*3/4);
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
	return [pboard setPropertyList:[filenames objectsAtIndexes:selectedIndexes]
						   forType:NSFilenamesPboardType];
}

#pragma mark init stuff
- (id)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect]) != nil) {
		myCell = [[NSImageCell alloc] initImageCell:nil];
		myTextCell = [[NSCell alloc] init];
		[myTextCell setAlignment:NSCenterTextAlignment];
		images = [[NSMutableArray alloc] initWithCapacity:100];
		filenames = [[NSMutableArray alloc] initWithCapacity:100];
		selectedIndexes = [[NSMutableIndexSet alloc] init];
		requestedFilenames = [[NSMutableSet alloc] init];
		[self setCellWidth:DEFAULT_CELL_WIDTH];
		textHeight = DEFAULT_TEXTHEIGHT;
		autoRotate = YES;
		loadingImage = [NSImage imageNamed:@"loading.png"];
		
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
	bgColor = [[NSUnarchiver unarchiveObjectWithData:
		[[NSUserDefaults standardUserDefaults] dataForKey:@"DYWrappingMatrixBgColor"]]
		retain];
	[[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
															  forKeyPath:@"values.DYWrappingMatrixMaxCellWidth"
																 options:NSKeyValueObservingOptionNew
																 context:NULL];
}

- (void)setMaxCellWidth:(float)w {
	//do nothing
}
- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:(id)object 
                        change:(NSDictionary *)c
                       context:(void *)context
{
    if ([keyPath isEqual:@"values.DYWrappingMatrixMaxCellWidth"]) {
		[self setMaxCellWidth:[[NSUserDefaults standardUserDefaults] integerForKey:@"DYWrappingMatrixMaxCellWidth"]];
    }
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[myCell release];
	[myTextCell release];
	[images release];
	[filenames release];
	[selectedIndexes release];
	[requestedFilenames release];
	[bgColor release];
	[super dealloc];
}

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView { return YES; }
- (BOOL)isFlipped { return YES; }

#pragma mark display/drag stuff
- (NSSize)cellSize { return NSMakeSize(cellWidth,cellWidth*3/4); }
- (float)maxCellWidth {
	return [[NSUserDefaults standardUserDefaults] integerForKey:@"DYWrappingMatrixMaxCellWidth"];
}
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
	area_h = cellHeight + VERTPADDING + textHeight;
}
- (NSInteger)point2cellnum:(NSPoint)p {
	NSInteger col = MIN(numCols-1, (NSInteger)p.x/area_w); if (col < 0) col = 0;
	NSInteger row = (NSInteger)p.y/area_h;
	NSInteger n = col + numCols*row; if (n<0) n=0;
	return n; // n might be > numCells-1
}
- (NSRect)cellnum2rect:(NSUInteger)n {
	int row, col;
	row = n/numCols;
	col = n%numCols;
	return NSMakeRect(area_w*col,area_h*row,area_w, area_h);
}
- (NSRect)imageRectForIndex:(NSUInteger)n {
	NSUInteger row, col;
	row = n/numCols;
	col = n%numCols;
	return ScaledCenteredRect([self imageSizeForIndex:n],
							  NSMakeRect(cellWidth*col + columnSpacing*(col + 0.5),
										 (cellHeight+textHeight)*row + VERTPADDING*(row+0.5),
										 cellWidth, cellHeight)); // rect for cell only
}

- (void)selectionNeedsDisplay:(NSUInteger)n {
	NSUInteger row, col;
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

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal {
	if (isLocal) return NSDragOperationNone;
	unsigned int o = NSDragOperationGeneric | NSDragOperationDelete | NSDragOperationCopy;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYWrappingMatrixAllowMove"])
		o |= NSDragOperationLink | NSDragOperationMove;
	// NSDragOperationLink creates aliases in the finder
	return o;
	
	// Note: You CANNOT check the currentEvent for modifier flags here to
	// change the kind of dragging operation to the Finder. This is because
	// the Finder seems to only remember the first return value from this
	// function, even though it happens to get called over and over again.
	// i.e., later invocations of this function return the value that you tell
	// it to, but the Finder just ignores it. This means you only get the
	// desired behavior when the user holds down the option key _before_
	// the dragging starts, which is not good user interface.
}

- (void)draggedImage:(NSImage *)anImage endedAt:(NSPoint)aPoint operation:(NSDragOperation)operation {
	// ** hm, how to best talk to the right object?
	if (operation == NSDragOperationDelete) {
		if ([[NSApp delegate] respondsToSelector:@selector(moveToTrash:)])
			[[NSApp delegate] moveToTrash:nil];		
	} else if (operation == NSDragOperationMove) {
		if ([[NSApp delegate] respondsToSelector:@selector(moveElsewhere:)])
			[[NSApp delegate] moveElsewhere:nil];		
	}
}

#pragma mark filename stuff

- (BOOL)showFilenames {
	return textHeight > 0;
}
- (void)setShowFilenames:(BOOL)b {
	// preserve the scrollpoint relative to the top left visible thumbnail
	NSPoint mouseLoc = [self convertPoint:NSMakePoint(1, 1) fromView:[self enclosingScrollView]]; // for some reason NSZeroPoint isn't quite right...
	NSInteger row = (NSInteger)mouseLoc.y/area_h;
	float dy = mouseLoc.y - area_h*row;

	// show/hide filenames
	if (b) {
		textHeight = DEFAULT_TEXTHEIGHT;
	} else {
		textHeight = 0;
	}
	[self resize:nil];
	[self setNeedsDisplay]; // you need this because it doesn't redraw if there's not enough items in the window to make it look like the scrollview changed
	
	// restore scrollpoint
	[self scrollPoint:NSMakePoint(0, row*area_h + dy)];
}

#pragma mark event stuff
- (void)mouseDown:(NSEvent *)theEvent {
	[[self window] makeFirstResponder:self];
	BOOL keepOn = YES;
	char doDrag = 0;
	NSUInteger cellNum, a, b, i;
	NSRange draggedRange;
	NSMutableIndexSet *oldSelection = [selectedIndexes mutableCopy];
	NSMutableIndexSet *lastIterationSelection = [oldSelection mutableCopy];
	BOOL shiftKeyDown = ([theEvent modifierFlags] & NSShiftKeyMask) != 0;
	BOOL cmdKeyDown = ([theEvent modifierFlags] & NSCommandKeyMask) != 0;

	NSPoint mouseLoc = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	NSPoint mouseDownLoc = mouseLoc;
	NSUInteger mouseDownCellNum = [self point2cellnum:mouseLoc];
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
		[pboard setPropertyList:[filenames objectsAtIndexes:selectedIndexes]
						forType:NSFilenamesPboardType];
		//loc, img
		NSImage *dragImg, *transparentImg;
		NSPoint imgLoc = mouseDownLoc;
		NSSize imgSize;
		if ([selectedIndexes count] == 1) {
			dragImg = [self imageForIndex:[selectedIndexes firstIndex]];
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
	NSUInteger numRows = numCells == 0 ? 0 : (numCells-1)/numCols + 1;
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

- (void)drawRect:(NSRect)rect {
	NSGraphicsContext *cg = [NSGraphicsContext currentContext];
	NSImageInterpolation oldInterp = [cg imageInterpolation];
	[cg setImageInterpolation:NSImageInterpolationNone];
	
	[bgColor set];
	[NSBezierPath fillRect:rect];
	//NSLog(@"---------------------------");
	NSUInteger i, row, col;
	NSRect areaRect = NSMakeRect(0, 0, area_w, area_h);
	NSRect textCellRect = NSMakeRect(0, 0, area_w, textHeight + VERTPADDING/2);
	NSRect cellRect;
	NSWindow *myWindow = [self window];
	[myTextCell setFont:[NSFont systemFontOfSize:cellWidth >= 160 ? 12 : 4+cellWidth/20]]; // ranges from 6 to 12: 6 + 6*(cellWidth-40)/(160-40)
	for (i=0; i<numCells; ++i) {
		row = i/numCols;
		col = i%numCols;
		areaRect.origin = NSMakePoint(area_w*col, area_h*row);
		if (![self needsToDrawRect:areaRect]) continue;
		// color the selection
		if ([selectedIndexes containsIndex:i]) {
			[([myWindow firstResponder] == self && [myWindow isKeyWindow]
			  ? [NSColor selectedTextBackgroundColor]
			  : [NSColor lightGrayColor]) set];
			[NSBezierPath fillRect:areaRect];
		}
		// retrieve the image, or ask the delegate to load it and send it back if it hasn't been set yet
		NSImage *img = [images objectAtIndex:i];
		NSString *filename = [filenames objectAtIndex:i];
		if (img == loadingImage) {
			if ([delegate respondsToSelector:@selector(wrappingMatrix:loadImageForFile:atIndex:)]
				&& ![requestedFilenames containsObject:filename]) {
				NSImage *newImage = [delegate wrappingMatrix:self loadImageForFile:filename atIndex:i];
				if (newImage) {
					[images replaceObjectAtIndex:i withObject:newImage];
					img = newImage;
					++numThumbsLoaded;
				} else {
					[requestedFilenames addObject:filename];
				}
			}
		}
		[myCell setImage:img];//[self imageForIndex:i]];//
		// calculate drawing area for thumb and filename area
		if (textHeight) {
			textCellRect.origin.x = areaRect.origin.x;
			textCellRect.origin.y = areaRect.origin.y + area_h - textHeight - VERTPADDING/2;
		}
		cellRect = [self imageRectForIndex:i];
		if (![self needsToDrawRect:cellRect] &&
			(textHeight == 0
			 || ![self needsToDrawRect:textCellRect])) {
			//NSLog(@"skipped cell %i", i);
			continue;
		}
		[[NSColor whiteColor] set]; // white bg for transparent imgs
		NSRectFill(cellRect);
		if (autoRotate) {
			// this code is awfully similar to the NSImage category above,
			// but I figure it's more time and memory efficient to draw directly to the view
			// rather than generating a new NSImage every time you want to draw
			unsigned short orientation = [self exifOrientationForIndex:i];
			int r = 0; BOOL imgFlipped = NO;
			switch (orientation) {
				case 4: r = 180; case 2: imgFlipped = YES; break;
				case 5: imgFlipped = YES; case 8: r = -90; break;
				case 7: imgFlipped = YES; case 6: r = 90; break;
				case 3: r = 180; break;
			}
			NSAffineTransform *transform = [NSAffineTransform transform];
			[transform translateXBy:cellRect.origin.x+cellRect.size.width/2
								yBy:cellRect.origin.y+cellRect.size.height/2];
			[transform rotateByDegrees:r];
			if (imgFlipped) [transform scaleXBy:-1 yBy:1];
			[transform translateXBy:-cellRect.origin.x-cellRect.size.width/2
								yBy:-cellRect.origin.y-cellRect.size.height/2];
			[transform concat];
			NSRect cellRect2 = cellRect;
			if (orientation >= 5) {
				// swap
				cellRect2.size.width = cellRect.size.height;
				cellRect2.size.height = cellRect.size.width;
				
				// adjust for rotation offset
				float offset = (cellRect.size.width - cellRect.size.height)/2;
				cellRect2.origin.x += offset;
				cellRect2.origin.y -= offset;
			}
			[myCell drawWithFrame:cellRect2 inView:self];
			[transform invert];
			[transform concat];
		} else {
			[myCell drawWithFrame:cellRect inView:self];
		}
		
		if (textHeight) {
			[myTextCell setStringValue:[[filenames objectAtIndex:i] lastPathComponent]];
			[myTextCell drawWithFrame:textCellRect inView:self];
		}
	}
	if (dragEntered) {
		[[[NSColor lightGrayColor] colorWithAlphaComponent:0.5] set];
		[NSBezierPath fillRect:rect];
	}
	[cg setImageInterpolation:oldInterp];
}
- (void)scrollSelectionToVisible:(NSUInteger)n {
	[self updateStatusString];
	NSRect r = [self cellnum2rect:n];
	[self selectionNeedsDisplay:n];
	// round down for better auto-scrolling
	r.size.height = (int)r.size.height;
	if (![self mouse:r.origin inRect:[self visibleRect]])
		[self scrollRectToVisible:r];
}
- (void)keyDown:(NSEvent *)e {
	if ([[e characters] length] == 0) return;
	unichar c = [[e characters] characterAtIndex:0];
	NSRect r;
	switch (c) {
		case NSHomeFunctionKey:
			r = [self cellnum2rect:0];
			r.size.height = (int)r.size.height;
			[self scrollRectToVisible:r];
			return;
		case NSEndFunctionKey:
			r = [self cellnum2rect:[filenames count]-1];
			r.size.height = (int)r.size.height;
			[self scrollRectToVisible:r];
			return;
		case NSRightArrowFunctionKey:
		case NSLeftArrowFunctionKey:
		case NSDownArrowFunctionKey:
		case NSUpArrowFunctionKey:
			break;
		default:
			[super keyDown:e];
			return;
	}
	NSUInteger n;
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

- (void)selectIndex:(NSUInteger)i {
	// redraw the old selection (assume this only gets called if single selection)
	if ([selectedIndexes count])
		[self selectionNeedsDisplay:[selectedIndexes firstIndex]];
	
	[selectedIndexes removeAllIndexes];
	[selectedIndexes addIndex:i];
	[self scrollSelectionToVisible:i];
}

#pragma mark auto-rotate stuff
- (BOOL)autoRotate {
	return autoRotate;
}
- (void)setAutoRotate:(BOOL)b {
	NSUInteger i;
	// once for the old areas
	for (i=0; i<numCells; ++i) {
		if ([self exifOrientationForIndex:i] <= 1) continue;
		[self setNeedsDisplayInRect:[self imageRectForIndex:i]];
	}
	autoRotate = b;
	// once for the new
	for (i=0; i<numCells; ++i) {
		if ([self exifOrientationForIndex:i] <= 1) continue;
		[self setNeedsDisplayInRect:[self imageRectForIndex:i]];
	}
}
- (NSImage *)imageForIndex:(NSUInteger)n {
	if (autoRotate) {
		return [[images objectAtIndex:n] rotateByExifOrientation:
				[self exifOrientationForIndex:n]];
	} else {
		return [images objectAtIndex:n];
	}
}
- (NSSize)imageSizeForIndex:(NSUInteger)n {
	NSSize s = [[images objectAtIndex:n] size];
	if (autoRotate && [self exifOrientationForIndex:n] >= 5) {
		float tmp;
		tmp = s.width;
		s.width = s.height;
		s.height = tmp;
	}
	return s;
}
- (unsigned short)exifOrientationForIndex:(NSUInteger)n {
	DYImageInfo *i = [[(CreeveyController *)[NSApp delegate] thumbsCache]
					  infoForKey:ResolveAliasToPath([filenames objectAtIndex:n])];
	return i ? i->exifOrientation : 0;
}



#pragma mark selection stuff
- (NSMutableIndexSet *)selectedIndexes {
	return selectedIndexes;
}

- (NSArray *)filenames {
	return filenames;
}

- (NSArray *)selectedFilenames {
	return [filenames objectsAtIndexes:selectedIndexes];
}

- (NSString *)firstSelectedFilename {
	return [filenames objectAtIndex:[selectedIndexes firstIndex]];
}

- (IBAction)selectAll:(id)sender {
	[selectedIndexes addIndexesInRange:NSMakeRange(0,numCells)];
	NSUInteger i;
	for (i=0; i<numCells; ++i) {
		[self selectionNeedsDisplay:i];
	}
	[self updateStatusString];
}

- (IBAction)selectNone:(id)sender {
	[selectedIndexes removeAllIndexes];
	NSUInteger i;
	for (i=0; i<numCells; ++i) {
		[self selectionNeedsDisplay:i];
	}
	[self updateStatusString];
}

- (NSUInteger)numCells {
	return numCells;
}

- (void)addSelectedIndex:(NSUInteger)i {
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
- (void)setImage:(NSImage *)theImage forIndex:(NSUInteger)i {
	if (i >= numCells) return;
	[images replaceObjectAtIndex:i withObject:theImage];
	[self setNeedsDisplayInRect2:[self cellnum2rect:i]];
}

#pragma mark lazy loading stuff
- (void)setImageWithFileInfo:(NSDictionary *)d {
	NSString *s = [d objectForKey:@"filename"];
	[requestedFilenames removeObject:s];
	NSUInteger i = [[d objectForKey:@"index"] unsignedIntegerValue];
	NSImage *theImage = [d objectForKey:@"image"];
	if (i >= numCells) return;
	if (![[filenames objectAtIndex:i] isEqualToString:s]) {
		i = [filenames indexOfObject:s];
		if (i == NSNotFound) return;
	}
	if ([images objectAtIndex:i] != theImage) {
		[images replaceObjectAtIndex:i withObject:theImage];
		++numThumbsLoaded;
		[self setNeedsDisplayInRect2:[self cellnum2rect:i]];
	}
}

- (BOOL)imageWithFileInfoNeedsDisplay:(NSDictionary *)d {
	NSString *s = [d objectForKey:@"filename"];
	if (![requestedFilenames containsObject:s]) return NO;
	NSUInteger i = [[d objectForKey:@"index"] unsignedIntegerValue];
	if (i >= numCells) return NO;
	// simple check to see if nothing's changed and the rect is visible
	if ([[filenames objectAtIndex:i] isEqualToString:s]) {
		NSRect visibleRect = [self visibleRect];
		NSRect cellRect = [self cellnum2rect:i];
		NSPoint p = cellRect.origin;
		if (NSPointInRect(p, visibleRect)) return YES;
		p.x += cellRect.size.width - 1; // adjust these values by one point to make sure NSPointInRect handles the bottom right corner correctly
		p.y += cellRect.size.height - 1;
		return NSPointInRect(p, visibleRect);
	}
	return NO;
}

- (void)updateStatusString {
	if ([delegate respondsToSelector:@selector(wrappingMatrix:selectionDidChange:)]) {
		[delegate wrappingMatrix:self selectionDidChange:selectedIndexes];
	}
}

- (NSUInteger)numThumbsLoaded {
	return numThumbsLoaded;
}

#pragma mark add/delete images stuff
- (void)addImage:(NSImage *)theImage withFilename:(NSString *)s{
	if (!theImage)
		theImage = loadingImage;
	else
		++numThumbsLoaded;
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
	[requestedFilenames removeAllObjects];
	numThumbsLoaded = 0;
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
- (void)removeImageAtIndex:(NSUInteger)i {
	// check if i is in range
	if (i >= [images count]) return;
	// adjust numLoaded if necessary
	if ([images objectAtIndex:i] != loadingImage) {
		--numThumbsLoaded;
	}
	numCells--;
	[images removeObjectAtIndex:i];
	[requestedFilenames removeObject:[filenames objectAtIndex:i]];
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
