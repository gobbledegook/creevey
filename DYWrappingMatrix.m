//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#import "DYWrappingMatrix.h"
#import "NSIndexSetSymDiffExtension.h"
#import "CreeveyMainWindowController.h"
#import "DYCarbonGoodies.h"
#import "NSMutableArray+DYMovable.h"

#define MAX_EXIF_WIDTH  160
#define MIN_CELL_WIDTH  40
#define PADDING 16
#define DEFAULT_TEXTHEIGHT 12

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

@interface DYMatrixState () {
	@public
	NSUInteger numCells;
	int numCols;
	float area_w, area_h;
	NSRect visibleRect;
}
@property (nonatomic, copy) NSArray *filenames;
@end

@implementation DYMatrixState
- (BOOL)imageWithFileInfoNeedsDisplay:(NSArray *)d {
	NSUInteger i = [d[1] unsignedIntegerValue];
	if (i < numCells && [_filenames[i] isEqualToString:d[0]]) {
		NSUInteger row = i/numCols, col = i%numCols;
		NSPoint p = NSMakePoint(area_w*col,area_h*row);
		if (NSPointInRect(p, visibleRect)) return YES;
		// adjust these values by one point to make sure NSPointInRect handles the bottom right corner correctly
		p.x += area_w - 1;
		p.y += area_h - 1;
		return NSPointInRect(p, visibleRect);
	}
	return NO;
}
@end


#pragma mark - DYWrappingMatrix -

@interface DYWrappingMatrix () <NSDraggingSource>
- (void)resize:(id)anObject; // called to recalc, set frame height
@property (nonatomic, strong) NSArray *openWithAppIdentifiers; // saved in mouseDown for subsequent use by the context menu
@end

@implementation DYWrappingMatrix
{
	NSColor *bgColor;
	BOOL autoRotate;
	NSImageCell *myCell;           // one cell, reused for efficiency
	NSCell *myTextCell; // for drawing the file name
	NSMutableArray *images;
	NSMutableArray *filenames;
	NSMutableSet *requestedFilenames; // keep track of which files we've requested images for
	float cellWidth;
	NSUInteger numCells;
	NSMutableIndexSet *selectedIndexes;
	
	BOOL dragEntered;
	
	// vars used for repeated calculations
	int numCols;
	float cellHeight, columnSpacing, area_w, area_h;
	unsigned int textHeight;
	
	float _maxCellWidth;
	float _hPadding, _vPadding;
	NSSize _contentSize;
	BOOL _respondsToLoadImageForFile, _respondsToSelectionDidChange;
	NSMutableArray *_movedUrls, *_originPaths;
	id __weak _appDelegate;
}
@synthesize delegate, loadingImage;

+ (Class)cellClass { return [NSActionCell class]; }
	// NSActionCell or subclass required for target/action

#pragma mark services stuff
+ (void)initialize
{
	if (self != [DYWrappingMatrix class]) return;
	// prefs stuff
	[NSUserDefaults.standardUserDefaults registerDefaults:@{
		@"DYWrappingMatrixBgColor": [NSKeyedArchiver archivedDataWithRootObject:NSColor.controlBackgroundColor requiringSecureCoding:YES error:NULL],
		@"DYWrappingMatrixAllowMove": @NO,
		@"DYWrappingMatrixMaxCellWidth": @"160",
		@"thumbPadding": @(PADDING),
	}];
	
    id sendTypes = @[NSFilenamesPboardType];
    [NSApp registerServicesMenuSendTypes:sendTypes returnTypes:@[]];
}
+ (NSSize)maxCellSize {
	NSInteger w = [NSUserDefaults.standardUserDefaults integerForKey:@"DYWrappingMatrixMaxCellWidth"];
	return NSMakeSize(w, w*3/4);
}

- (id)validRequestorForSendType:(NSString *)sendType
					 returnType:(NSString *)returnType {
    if (!returnType && [sendType isEqual:NSFilenamesPboardType]) {
		if (selectedIndexes.count > 0)
			return self;
	}
    return [super validRequestorForSendType:sendType
								 returnType:returnType];
}
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard
							 types:(NSArray *)types {
    if (![types containsObject:NSFilenamesPboardType])
        return NO;
 	[pboard declareTypes:@[NSFilenamesPboardType]
				   owner:nil];
	return [pboard setPropertyList:[filenames objectsAtIndexes:selectedIndexes]
						   forType:NSFilenamesPboardType];
}

#pragma mark init stuff
- (instancetype)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect]) != nil) {
		myCell = [[NSImageCell alloc] initImageCell:nil];
		myTextCell = [[NSCell alloc] init];
		myTextCell.alignment = NSTextAlignmentCenter;
		images = [[NSMutableArray alloc] initWithCapacity:100];
		filenames = [[NSMutableArray alloc] initWithCapacity:100];
		selectedIndexes = [[NSMutableIndexSet alloc] init];
		requestedFilenames = [[NSMutableSet alloc] init];
		_movedUrls = [[NSMutableArray alloc] init];
		_originPaths = [[NSMutableArray alloc] init];
		// cellWidth should be initialized by an external controller during awakeFromNib
		_maxCellWidth = FLT_MAX;
		textHeight = DEFAULT_TEXTHEIGHT;
		autoRotate = YES;
		
		[self registerForDraggedTypes:@[NSFilenamesPboardType]];
	}
	return self;
}

- (void)awakeFromNib {
	[self.enclosingScrollView setPostsFrameChangedNotifications:YES];
	[NSNotificationCenter.defaultCenter addObserver:self
											 selector:@selector(resize:)
												 name:NSViewFrameDidChangeNotification
											   object:self.enclosingScrollView];
	[self.enclosingScrollView.contentView setPostsBoundsChangedNotifications:YES];
	NSUserDefaults *udf = NSUserDefaults.standardUserDefaults;
	float padding = [udf floatForKey:@"thumbPadding"];
	_vPadding = _hPadding = padding < 0 ? 0 : padding > PADDING ? PADDING : padding;
	NSData *colorData = [udf dataForKey:@"DYWrappingMatrixBgColor"];
	NSColor *aColor = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSColor class] fromData:colorData error:NULL];
	if (aColor == nil) {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
		aColor = [NSUnarchiver unarchiveObjectWithData:colorData];
#pragma GCC diagnostic pop
		NSData *migratedData = [NSKeyedArchiver archivedDataWithRootObject:aColor requiringSecureCoding:YES error:NULL];
		[udf setObject:migratedData forKey:@"DYWrappingMatrixBgColor"];
	}
	bgColor = aColor;
	[NSUserDefaultsController.sharedUserDefaultsController addObserver:self
															  forKeyPath:@"values.DYWrappingMatrixMaxCellWidth"
																 options:NSKeyValueObservingOptionNew
																 context:NULL];
	[NSUserDefaultsController.sharedUserDefaultsController addObserver:self
															  forKeyPath:@"values.DYWrappingMatrixBgColor"
																 options:NSKeyValueObservingOptionNew
																 context:NULL];
	_respondsToLoadImageForFile = [delegate respondsToSelector:@selector(wrappingMatrixWantsImageForFile:atIndex:)];
	_respondsToSelectionDidChange = [delegate respondsToSelector:@selector(wrappingMatrixSelectionDidChange:)];
	_appDelegate = NSApp.delegate;
}

- (void)setMaxCellWidth:(float)w {
	if (w < _maxCellWidth) {
		_maxCellWidth = w; // this has to be set before we do the resizing
		self.cellWidth = cellWidth < w ? cellWidth : w;
	} else {
		_maxCellWidth = w;
		// tell delegate to reload anything we've loaded already
		// the delay is to wait for all the other windows to have emptied the thumbs cache before we start repopulating it
		NSUInteger n = filenames.count;
		if (n && _respondsToLoadImageForFile) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			for (NSUInteger i = 0; i < n; ++i) {
				if (images[i] != loadingImage)
					[delegate wrappingMatrixWantsImageForFile:filenames[i] atIndex:i];
			}
		});
	}
}
- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:(id)object 
                        change:(NSDictionary *)c
                       context:(void *)context
{
    if ([keyPath isEqual:@"values.DYWrappingMatrixMaxCellWidth"]) {
		self.maxCellWidth = [NSUserDefaults.standardUserDefaults integerForKey:@"DYWrappingMatrixMaxCellWidth"];
	} else if ([keyPath isEqualToString:@"values.DYWrappingMatrixBgColor"]) {
		bgColor = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSColor class] fromData:[NSUserDefaults.standardUserDefaults dataForKey:@"DYWrappingMatrixBgColor"] error:NULL];
		[self setNeedsDisplay];
	}
}

- (void)dealloc {
	NSUserDefaultsController *u = NSUserDefaultsController.sharedUserDefaultsController;
	[u removeObserver:self forKeyPath:@"values.DYWrappingMatrixMaxCellWidth"];
	[u removeObserver:self forKeyPath:@"values.DYWrappingMatrixBgColor"];
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView { return YES; }
- (BOOL)isFlipped { return YES; }

#pragma mark display/drag stuff
- (float)maxCellWidth {
	return _maxCellWidth;
}
- (float)minCellWidth { return MIN_CELL_WIDTH; }
- (float)cellWidth { return cellWidth; }
- (void)setCellWidth:(float)w {
	if (w < MIN_CELL_WIDTH) w = MIN_CELL_WIDTH;
	else if (w > _maxCellWidth) w = _maxCellWidth;
	if (cellWidth == w) return;
	cellWidth = w;
	[self resize:nil];
	[self setNeedsDisplay:YES];
}


- (void)calculateCellSizes {
	// all values dependent on bounds width, cellWidth(, numCells for resize:)
	float self_w = self.bounds.size.width;
	cellHeight = cellWidth*3/4;
	numCols = (int)(self_w)/((int)cellWidth + _hPadding/2);
	if (numCols == 0) numCols = 1;
	columnSpacing = (self_w - numCols*cellWidth)/numCols;
	area_w = cellWidth + columnSpacing;
	area_h = cellHeight + _vPadding + textHeight;
}
- (NSInteger)point2cellnum:(NSPoint)p {
	NSInteger col = MIN(numCols-1, (NSInteger)p.x/area_w); if (col < 0) col = 0;
	NSInteger row = (NSInteger)p.y/area_h;
	NSInteger n = col + numCols*row; if (n<0) n=0;
	return n; // n might be > numCells-1
}
- (NSRect)cellnum2rect:(NSUInteger)n {
	NSUInteger row, col;
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
										 (cellHeight+textHeight)*row + _vPadding*(row+0.5),
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

#pragma mark NSDraggingSource stuff
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
	if (context == NSDraggingContextWithinApplication) return NSDragOperationNone;
	unsigned int o = NSDragOperationGeneric | NSDragOperationDelete | NSDragOperationCopy;
	if ([NSUserDefaults.standardUserDefaults boolForKey:@"DYWrappingMatrixAllowMove"])
		o |= NSDragOperationLink | NSDragOperationMove;
	// NSDragOperationLink creates aliases in the finder
	return o;
}

- (void)draggingSession:(NSDraggingSession *)session movedToPoint:(NSPoint)screenPoint {
	session.draggingFormation = NSDraggingFormationPile;
}

- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)aPoint operation:(NSDragOperation)operation {
	if (operation == NSDragOperationDelete) {
		if ([_appDelegate respondsToSelector:@selector(moveToTrash:)])
			[_appDelegate moveToTrash:nil];
	} else if (operation == NSDragOperationMove) {
		if ([_appDelegate respondsToSelector:@selector(moveElsewhere)])
			[_appDelegate moveElsewhere];
	}
	// moveElsewhere should have retained copies of these, so OK to reset them now
	[_movedUrls removeAllObjects];
	[_originPaths removeAllObjects];
}

- (NSArray<NSURL *> *)movedUrls {
	return [_movedUrls copy];
}

- (NSArray<NSString *> *)originPaths {
	return [_originPaths copy];
}

#pragma mark filename stuff

- (BOOL)showFilenames {
	return textHeight > 0;
}
- (void)setShowFilenames:(BOOL)b {
	// preserve the scrollpoint relative to the top left visible thumbnail
	NSPoint mouseLoc = [self convertPoint:NSMakePoint(1, 1) fromView:self.enclosingScrollView]; // for some reason NSZeroPoint isn't quite right...
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

#pragma mark menu stuff

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if (menuItem.action == @selector(copy:)) return selectedIndexes.count > 0;
	// selectAll:/selectNone:
	return filenames.count > 0;
}

- (IBAction)copy:(id)sender {
	NSMutableArray *items = [NSMutableArray arrayWithCapacity:selectedIndexes.count];
	[selectedIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
		NSString *path = filenames[idx];
		NSPasteboardItem *pbi = [[NSPasteboardItem alloc] init];
		[pbi setString:path forType:NSPasteboardTypeString];
		[pbi setString:[NSURL fileURLWithPath:path isDirectory:NO].absoluteString  forType:NSPasteboardTypeFileURL];
		[items addObject:pbi];
	}];
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	[pb clearContents];
	[pb writeObjects:items];
}

#pragma mark event stuff
- (void)mouseDown:(NSEvent *)theEvent {
	[self.window makeFirstResponder:self];
	if (numCells == 0) return;
	BOOL keepOn = YES;
	char doDrag = 0;
	NSUInteger cellNum, a, b;
	NSRange draggedRange;
	NSMutableIndexSet *oldSelection = [selectedIndexes mutableCopy];
	NSMutableIndexSet *lastIterationSelection = [oldSelection mutableCopy];
	BOOL shiftKeyDown = (theEvent.modifierFlags & NSEventModifierFlagShift) != 0;
	BOOL cmdKeyDown = (theEvent.modifierFlags & NSEventModifierFlagCommand) != 0;

	NSPoint mouseLoc = [self convertPoint:theEvent.locationInWindow fromView:nil];
	NSUInteger mouseDownCellNum = [self point2cellnum:mouseLoc];
	if (![selectedIndexes containsIndex:mouseDownCellNum] && !shiftKeyDown && !cmdKeyDown) {
		[oldSelection removeAllIndexes];
	}
	if (!cmdKeyDown && mouseDownCellNum < numCells &&
		([selectedIndexes containsIndex:mouseDownCellNum] ||
		 (NSPointInRect(mouseLoc, [self imageRectForIndex:mouseDownCellNum]) && !shiftKeyDown))) {
		// we should drag if started in selection
		// or dragging the actual image
		doDrag = 1;
	} else if (shiftKeyDown) {
		// if shift key is down, it's as if we had dragged from the end of the old selection
		mouseDownCellNum = mouseDownCellNum < selectedIndexes.lastIndex
			? selectedIndexes.firstIndex
			: selectedIndexes.lastIndex;
	}
	[NSEvent startPeriodicEventsAfterDelay:0 withPeriod:0.3];
    while (1) {
		mouseLoc = theEvent.locationInWindow;
        switch (theEvent.type) {
			case NSEventTypePeriodic:
				mouseLoc = self.window.mouseLocationOutsideOfEventStream;
			case NSEventTypeLeftMouseDown: // for the first iteration only
			case NSEventTypeLeftMouseDragged:
				mouseLoc = [self convertPoint:mouseLoc fromView:nil];
				if (doDrag && theEvent.type == NSEventTypeLeftMouseDragged) {
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
					for (NSUInteger i=0; i<draggedRange.length; ++i)
						if ([selectedIndexes containsIndex:draggedRange.location+i])
							[selectedIndexes removeIndex:draggedRange.location+i];
						else
							[selectedIndexes addIndex:draggedRange.location+i];
				if (![self mouse:mouseLoc inRect:self.visibleRect])
					[self autoscroll:theEvent]; // always check visibleRect for autoscroll
				[lastIterationSelection symmetricDifference:selectedIndexes];
				if (lastIterationSelection.count) {
					[self notifySelectionDidChange];
					for (NSUInteger i=lastIterationSelection.firstIndex; i != NSNotFound; i = [lastIterationSelection indexGreaterThanIndex:i]) {
						[self selectionNeedsDisplay:i];
					}
				}
				[lastIterationSelection removeAllIndexes];
				[lastIterationSelection addIndexes:selectedIndexes];
				break;
			case NSEventTypeLeftMouseUp:
				if (theEvent.clickCount == 2
					&& mouseDownCellNum < numCells
					&& !shiftKeyDown && !cmdKeyDown)
					[self sendAction:self.action to:self.target];
				keepOn = NO;
				break;
            default:
				break;
        }
		if (!keepOn) break;
        theEvent = [self.window nextEventMatchingMask:
					NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged | NSEventMaskPeriodic];
    }
	[NSEvent stopPeriodicEvents];
	if (doDrag == 2) {
		NSMutableArray *draggingItems = [NSMutableArray arrayWithCapacity:selectedIndexes.count];
		[selectedIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
			NSString *path = filenames[idx];
			NSURL *url = [NSURL fileURLWithPath:path isDirectory:NO];
			[_originPaths addObject:path];
			[_movedUrls addObject:url.fileReferenceURL];
			NSPasteboardItem *pbi = [[NSPasteboardItem alloc] init];
			[pbi setString:url.absoluteString forType:NSPasteboardTypeFileURL];
			NSDraggingItem *item = [[NSDraggingItem alloc] initWithPasteboardWriter:pbi];
			// set an image to be dragged
			// for performance reasons we use a block as an imagecomponentprovider rather than actual nsimages
			// contrary to the documentation, the imageComponentsProvider is a block that returns an array, not an array of blocks
			NSRect imageRect = [self imageRectForIndex:idx];
			NSImage *image = images[idx]; // the block should capture a ref to the image, not to our images array
			item.draggingFrame = imageRect;
			imageRect.origin = NSZeroPoint; // origin must be zero for the block to work correctly
			item.imageComponentsProvider = ^NSArray<NSDraggingImageComponent *> * _Nonnull {
				NSDraggingImageComponent *c = [NSDraggingImageComponent draggingImageComponentWithKey:NSDraggingImageComponentIconKey];
				c.frame = imageRect;
				c.contents = image;
				return @[c];
			};
			[draggingItems addObject:item];
		}];
		[self beginDraggingSessionWithItems:draggingItems event:theEvent source:self];
	}
}

- (void)resize:(id)anObject { // called by notification center
	[self calculateCellSizes];
	NSSize mySize = self.frame.size;
	NSUInteger numRows = numCells == 0 ? 0 : (numCells-1)/numCols + 1;
	float h = MAX(floorf(numRows*area_h), [[self superview] frame].size.height);
	if (mySize.height != h) {
		mySize.height = h;
		_contentSize = mySize;
		[self invalidateIntrinsicContentSize];
	}
}

- (NSSize)intrinsicContentSize
{
	return _contentSize;
}

- (void)drawRect:(NSRect)rect {
	NSGraphicsContext *cg = NSGraphicsContext.currentContext;
	NSImageInterpolation oldInterp = cg.imageInterpolation;
	cg.imageInterpolation = NSImageInterpolationNone;
	
	[bgColor set];
	[NSBezierPath fillRect:rect];
	//NSLog(@"---------------------------");
	NSUInteger i, row, col;
	NSRect areaRect = NSMakeRect(0, 0, area_w, area_h);
	NSRect textCellRect = NSMakeRect(0, 0, area_w, textHeight + _vPadding/2);
	NSRect cellRect;
	NSWindow *myWindow = self.window;
	myTextCell.font = [NSFont systemFontOfSize:cellWidth >= 160 ? 12 : 4+cellWidth/20]; // ranges from 6 to 12: 6 + 6*(cellWidth-40)/(160-40)
	for (i=0; i<numCells; ++i) {
		row = i/numCols;
		col = i%numCols;
		areaRect.origin = NSMakePoint(area_w*col, area_h*row);
		if (![self needsToDrawRect:areaRect]) continue;
		// color the selection
		if ([selectedIndexes containsIndex:i]) {
			[(myWindow.firstResponder == self && myWindow.keyWindow
			  ? NSColor.selectedTextBackgroundColor
			  : NSColor.lightGrayColor) set];
			[NSBezierPath fillRect:areaRect];
		}
		// retrieve the image, or ask the delegate to load it and send it back if it hasn't been set yet
		NSImage *img = images[i];
		NSString *filename = filenames[i];
		if (img == loadingImage) {
			if (_respondsToLoadImageForFile && ![requestedFilenames containsObject:filename]) {
				NSImage *newImage = [delegate wrappingMatrixWantsImageForFile:filename atIndex:i];
				if (newImage) {
					images[i] = newImage;
					img = newImage;
				} else {
					[requestedFilenames addObject:filename];
				}
			}
		}
		myCell.image = img;
		// calculate drawing area for thumb and filename area
		if (textHeight) {
			textCellRect.origin.x = areaRect.origin.x;
			textCellRect.origin.y = areaRect.origin.y + area_h - textHeight - _vPadding/2;
		}
		cellRect = [self imageRectForIndex:i];
		if (![self needsToDrawRect:cellRect] &&
			(textHeight == 0
			 || ![self needsToDrawRect:textCellRect])) {
			//NSLog(@"skipped cell %i", i);
			continue;
		}
		[NSColor.whiteColor set]; // white bg for transparent imgs
		NSRectFill(cellRect);
		if (autoRotate) {
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
			[myCell drawInteriorWithFrame:cellRect2 inView:self];
			[transform invert];
			[transform concat];
		} else {
			[myCell drawInteriorWithFrame:cellRect inView:self];
		}
		
		if (textHeight) {
			myTextCell.stringValue = filename.lastPathComponent;
			[myTextCell drawInteriorWithFrame:textCellRect inView:self];
		}
	}
	if (dragEntered) {
		[[NSColor.lightGrayColor colorWithAlphaComponent:0.5] set];
		[NSBezierPath fillRect:rect];
	}
	cg.imageInterpolation = oldInterp;
}
- (void)scrollSelectionToVisible:(NSUInteger)n {
	[self notifySelectionDidChange];
	NSRect r = [self cellnum2rect:n];
	[self selectionNeedsDisplay:n];
	// round down for better auto-scrolling
	r.size.height = (int)r.size.height;
	if (![self mouse:r.origin inRect:self.visibleRect])
		[self scrollRectToVisible:r];
}
- (void)scrollToFirstSelected:(NSIndexSet *)x {
	[selectedIndexes addIndexes:x];
	[selectedIndexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL * _Nonnull stop) {
		[self selectionNeedsDisplay:i];
	}];
	NSRect r = [self cellnum2rect:x.firstIndex];
	if (selectedIndexes.count > 1) {
		// scroll such that the first selected thumb is a little bit below the top of the view
		CGFloat scrollHeight = self.visibleRect.size.height - 30;
		r.size.height = r.size.height > scrollHeight ? r.size.height : scrollHeight;
	}
	r.size.height = (int)r.size.height;
	[self scrollRectToVisible:r];
	[self notifySelectionDidChange];
}

- (void)keyDown:(NSEvent *)e {
	if (e.characters.length == 0) return;
	unichar c = [e.characters characterAtIndex:0];
	NSRect r;
	switch (c) {
		case NSHomeFunctionKey:
			r = [self cellnum2rect:0];
			r.size.height = (int)r.size.height;
			[self scrollRectToVisible:r];
			return;
		case NSEndFunctionKey:
			r = [self cellnum2rect:filenames.count-1];
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
	if (selectedIndexes.count == 1) {
		n = selectedIndexes.firstIndex;
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
	} else if (selectedIndexes.count == 0 && numCells > 0) {
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
	if (selectedIndexes.count)
		[self selectionNeedsDisplay:selectedIndexes.firstIndex];
	
	[selectedIndexes removeAllIndexes];
	[selectedIndexes addIndex:i];
	[self scrollSelectionToVisible:i];
}

- (void)magnifyWithEvent:(NSEvent *)event
{
	self.cellWidth = cellWidth * (1.0 + event.magnification);
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
- (NSSize)imageSizeForIndex:(NSUInteger)n {
	NSSize s = [images[n] size];
	if (autoRotate && [self exifOrientationForIndex:n] >= 5) {
		float tmp;
		tmp = s.width;
		s.width = s.height;
		s.height = tmp;
	}
	return s;
}
- (unsigned short)exifOrientationForIndex:(NSUInteger)n {
	return [_appDelegate exifOrientationForFile:filenames[n]];
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
	return filenames[selectedIndexes.firstIndex];
}

- (IBAction)selectAll:(id)sender {
	[selectedIndexes addIndexesInRange:NSMakeRange(0,numCells)];
	NSUInteger i;
	for (i=0; i<numCells; ++i) {
		[self selectionNeedsDisplay:i];
	}
	[self notifySelectionDidChange];
}

- (IBAction)selectNone:(id)sender {
	[selectedIndexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
		[self selectionNeedsDisplay:i];
	}];
	[selectedIndexes removeAllIndexes];
	[self notifySelectionDidChange];
}

- (void)selectFilenames:(NSArray *)arr comparator:(NSComparator)cmp {
	NSMutableIndexSet *newIdxs = [[NSMutableIndexSet alloc] init];
	NSRange r = {0,filenames.count};
	for (NSString *s in arr) {
		NSUInteger idx = [filenames indexOfObject:s inSortedRange:r options:0 usingComparator:cmp];
		if (idx != NSNotFound)
			[newIdxs addIndex:idx];
	}
	if (newIdxs.count) {
		[selectedIndexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
			[self selectionNeedsDisplay:i];
		}];
		[selectedIndexes removeAllIndexes];
		[self scrollToFirstSelected:newIdxs];
	}
}

- (NSUInteger)numCells {
	return numCells;
}

// call this when an image changes (filename is already set)
- (void)updateImage:(NSImage *)theImage atIndex:(NSUInteger)i {
	if (i >= numCells) return;
	images[i] = theImage;
	[self setNeedsDisplayInRect:[self cellnum2rect:i]];
}

#pragma mark lazy loading stuff
// called in main thread. returns YES if theImage has been retained
- (BOOL)setImage:(NSImage *)theImage atIndex:(NSUInteger)i forFilename:(NSString *)s {
	[requestedFilenames removeObject:s];
	if (i >= numCells) return NO;
	if (![filenames[i] isEqualToString:s]) {
		i = [filenames indexOfObject:s];
		if (i == NSNotFound) return NO;
	}
	if (images[i] != theImage) {
		images[i] = theImage;
		[self setNeedsDisplayInRect:[self cellnum2rect:i]];
		return YES;
	}
	return NO;
}

- (DYMatrixState *)currentState {
	DYMatrixState *o = [[DYMatrixState alloc] init];
	o->numCells = numCells;
	o->numCols = numCols;
	o->area_w = area_w;
	o->area_h = area_h;
	o->visibleRect = self.visibleRect;
	o.filenames = filenames;
	return o;
}

- (void)notifySelectionDidChange {
	if (_respondsToSelectionDidChange)
		[delegate wrappingMatrixSelectionDidChange:selectedIndexes];
}

#pragma mark add/delete images stuff
- (void)addImage:(NSImage *)theImage withFilename:(NSString *)s{
	[self addImage:theImage withFilename:s atIndex:filenames.count];
}

- (void)addImage:(NSImage *)theImage withFilename:(NSString *)s atIndex:(NSUInteger)i {
	if (!theImage)
		theImage = loadingImage;
	[images insertObject:theImage atIndex:i];
	[filenames insertObject:s atIndex:i];
	numCells++;
	[self resize:nil];
	[self setNeedsDisplayInRect:[self cellnum2rect:numCells-1]];
}

- (void)removeAllImages {
	numCells = 0;
	[images removeAllObjects];
	[filenames removeAllObjects];
	[requestedFilenames removeAllObjects];
	[selectedIndexes removeAllIndexes];
	[self resize:nil];
	[self setNeedsDisplay:YES];
	// manually set to 0 to avoid animation (which you get if you call [self scrollPoint:]
	[self.enclosingScrollView.contentView scrollToPoint:NSZeroPoint];
	self.enclosingScrollView.verticalScroller.doubleValue = 0;
}
- (void)removeImageAtIndex:(NSUInteger)i {
	// check if i is in range
	if (i >= images.count) return;
	numCells--;
	[images removeObjectAtIndex:i];
	[requestedFilenames removeObject:filenames[i]];
	[filenames removeObjectAtIndex:i];
	[selectedIndexes shiftIndexesStartingAtIndex:i+1 by:-1];
	[self resize:nil];
	do {
		[self setNeedsDisplayInRect:[self cellnum2rect:i]];
	} while (++i<=numCells);
	// use <=, not <, because we need to redraw the last cell, which has shifted
	[self notifySelectionDidChange];
}
- (void)moveImageAtIndex:(NSUInteger)fromIdx toIndex:(NSUInteger)toIdx {
	if (fromIdx == toIdx) return;
	[images moveObjectAtIndex:fromIdx toIndex:toIdx];
	[filenames moveObjectAtIndex:fromIdx toIndex:toIdx];
	BOOL selected = [selectedIndexes containsIndex:fromIdx];
	[selectedIndexes shiftIndexesStartingAtIndex:fromIdx+1 by:-1];
	[selectedIndexes shiftIndexesStartingAtIndex:toIdx by:1];
	if (selected) [selectedIndexes addIndex:toIdx];
	if (fromIdx > toIdx) {
		NSUInteger tmp = fromIdx;
		fromIdx = toIdx;
		toIdx = tmp;
	}
	do {
		[self setNeedsDisplayInRect:[self cellnum2rect:fromIdx]];
	} while (++fromIdx <= toIdx);
}
- (void)changeBase:(NSString *)basePath toPath:(NSString *)newBase {
	[filenames changeBase:basePath toPath:newBase];
}


#pragma mark more dragging stuff
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    NSPasteboard *pboard;
    NSDragOperation sourceDragMask;
	
    sourceDragMask = sender.draggingSourceOperationMask;
	pboard = sender.draggingPasteboard;
	
    if ( [pboard.types containsObject:NSFilenamesPboardType] ) {
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
    sourceDragMask = sender.draggingSourceOperationMask;
    pboard = sender.draggingPasteboard;
    if ( [pboard.types containsObject:NSFilenamesPboardType] ) {
        NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
		

        if (sourceDragMask & NSDragOperationGeneric) {
			
            [(CreeveyMainWindowController *)self.window.delegate openFiles:files withSlideshow:NO]; // **
			
        }
		
    }
    return YES;
}

#pragma mark contextual menu stuff

- (void)openWith:(NSMenuItem *)sender
{
	NSInteger index = [sender.menu indexOfItem:sender];
	if (index < 0 || index >= self.openWithAppIdentifiers.count) return;
	NSString *appIdentifier = self.openWithAppIdentifiers[index];
	NSArray *paths = self.selectedFilenames;
	NSMutableArray *urls = [NSMutableArray arrayWithCapacity:paths.count];
	for (NSString *path in paths) {
		[urls addObject:[NSURL fileURLWithPath:path isDirectory:NO]];
	}
	[NSWorkspace.sharedWorkspace openURLs:urls withAppBundleIdentifier:appIdentifier options:NSWorkspaceLaunchDefault additionalEventParamDescriptor:nil launchIdentifiers:NULL];
	self.openWithAppIdentifiers = nil;
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    id appDelegate = NSApp.delegate;
    if (![appDelegate respondsToSelector:@selector(thumbnailContextMenu)]) return nil;
    if ([appDelegate thumbnailContextMenu] == nil) {
        if (![NSBundle.mainBundle loadNibNamed:@"ThumbnailContextMenu" owner:appDelegate topLevelObjects:NULL]) return nil;
    }
	NSPoint mouseLoc = [self convertPoint:event.locationInWindow fromView:nil];
	NSUInteger cellNum = [self point2cellnum:mouseLoc];
	BOOL hasSelection = selectedIndexes.count != 0;
	if (cellNum < numCells) {
		if (![selectedIndexes containsIndex:cellNum]) {
			// if user clicked on a non-selected item, select that item
			if (hasSelection)
				[self selectNone:nil];
			[self selectIndex:cellNum];
		}
	} else {
		// do nothing if there is no selection and user clicked outside of the thumbs
		if (!hasSelection)
			return nil;
	}

	NSURL *firstFile = [NSURL fileURLWithPath:filenames[selectedIndexes.firstIndex] isDirectory:NO];
	NSArray *allApplications = (NSArray *)CFBridgingRelease(LSCopyApplicationURLsForURL((__bridge CFURLRef)firstFile, kLSRolesViewer|kLSRolesEditor));
	NSMutableArray *filteredApplications = [NSMutableArray array];
	NSString *selfIdentifier = NSBundle.mainBundle.bundleIdentifier;
	NSWorkspace *ws = NSWorkspace.sharedWorkspace;
	NSURL *defaultAppURL = [ws URLForApplicationToOpenURL:firstFile];
	if (allApplications == nil || defaultAppURL == nil) {
		// fail gracefully if the file is not openable
		NSMenu *menu = [appDelegate thumbnailContextMenu];
		NSMenu *openWithMenu = [[NSMenu alloc] init];
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"None Available", @"") action:NULL keyEquivalent:@""];
		[openWithMenu addItem:item];
		[menu itemAtIndex:0].submenu = openWithMenu;
		return menu;
	}
	NSString *defaultIdentifier = [NSBundle bundleWithURL:defaultAppURL].bundleIdentifier;
	NSMutableSet *appIdentifiers = [NSMutableSet setWithCapacity:allApplications.count]; // don't duplicate app identifiers
	NSCountedSet *displayNames = [NSCountedSet setWithCapacity:allApplications.count]; // disambiguate identical display names if necessary
	NSFileManager *fm = NSFileManager.defaultManager;
	for (NSURL *app in allApplications) {
		NSString *appIdentifier = [NSBundle bundleWithURL:app].bundleIdentifier;
		if (appIdentifier.length == 0 || [appIdentifier isEqualToString:selfIdentifier] || [appIdentifier isEqualToString:defaultIdentifier])
			continue;
		if (![appIdentifiers containsObject:appIdentifier]) {
			[appIdentifiers addObject:appIdentifier];
			[displayNames addObject:[fm displayNameAtPath:app.path]];
			[filteredApplications addObject:app];
		}
	}
	// In macOS 10.15 and later, the returned array is sorted with the first element containing the best available apps for opening the specified URL.
	// So we should be able to get rid of the above loop when we drop support for <10.15
	NSArray *sortedApplications = [filteredApplications sortedArrayUsingComparator:^NSComparisonResult(NSURL *obj1, NSURL *obj2) {
		NSString *path1 = obj1.path;
		NSString *path2 = obj2.path;
		NSString *a = [fm displayNameAtPath:path1];
		NSString *b = [fm displayNameAtPath:path2];
		NSComparisonResult result = [a localizedStandardCompare:b];
		if (result == NSOrderedSame) {
			// if display names are the same, fall back to path, which should sort things in order of /Applications, /Users, /Volumes
			result = [path1 compare:path2];
		}
		return result;
	}];
	NSMutableArray *sortedAppIdentifiers = [NSMutableArray arrayWithCapacity:appIdentifiers.count];
	NSMenu *openWithMenu = [[NSMenu alloc] init];
	if (![selfIdentifier isEqualToString:defaultIdentifier]) {
		[sortedAppIdentifiers addObject:defaultIdentifier];
		NSString *path = defaultAppURL.path;
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[fm displayNameAtPath:path] action:@selector(openWith:) keyEquivalent:@""];
		item.image = [ws iconForFile:path];
		item.image.size = NSMakeSize(16, 16);
		[openWithMenu addItem:item];
		[sortedAppIdentifiers addObject:@""];
		[openWithMenu addItem:[NSMenuItem separatorItem]];
	}
	for (NSURL *app in sortedApplications) {
		NSString *path = app.path;
		NSString *displayName = [fm displayNameAtPath:path];
		NSString *appIdentifier = [NSBundle bundleWithURL:app].bundleIdentifier;
		[sortedAppIdentifiers addObject:appIdentifier];
		if ([displayNames countForObject:displayName] > 1) {
			displayName = [displayName stringByAppendingString:[NSString stringWithFormat:@" (%@)", appIdentifier]];
		}
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:displayName action:@selector(openWith:) keyEquivalent:@""];
		item.image = [ws iconForFile:path];
		item.image.size = NSMakeSize(16, 16);
		[openWithMenu addItem:item];
	}
	self.openWithAppIdentifiers = [sortedAppIdentifiers copy];
    NSMenu *menu = [appDelegate thumbnailContextMenu];
	[menu itemAtIndex:0].submenu = openWithMenu;
	return menu;
}

@end
