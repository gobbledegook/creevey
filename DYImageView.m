//Copyright 2005-2026 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  Created by d on 2005.04.01.

#import "DYImageView.h"

@interface DYImageViewZoomInfo : NSObject {
	@public
	NSPoint center;
	float zoomF;
}
@end
@implementation DYImageViewZoomInfo
@end


@implementation DYImageView
{
	NSSize _fullSize;
	NSTimer *gifTimer;
	NSArray *_webpFrameInfo; int _webpCurrentFrame; NSUInteger _webpFrameCount;
	NSRect sourceRect, destRect;
	float _zoom; // calculated zoom, relative to image.size
	float zoomF;
	NSPoint imageCenter; // the point in the image we want at the center of the screen
}
@synthesize image, scalesUp, showActualSize, imageFlipped=isImageFlipped, rotation;

- (instancetype)initWithFrame:(NSRect)frameRect {
	if (self = [super initWithFrame:frameRect]) {
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(frameChanged:) name:NSViewFrameDidChangeNotification object:self];
		_imageBackgroundColor = [NSColor clearColor];
	}
	return self;
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)setImageBackgroundColor:(NSColor *)aColor {
	if (_imageBackgroundColor != aColor) {
		_imageBackgroundColor = aColor;
		self.needsDisplay = YES;
	}
}

- (void)frameChanged:(id)obj {
	[self calculateRectsAndSetNeedsDisplay];
}

- (float)currentZoom {
	NSSize imgSize = image.size;
	if (imgSize.width == _fullSize.width)
		return _zoom;
	return _zoom*imgSize.width/_fullSize.width;
}

// calculate sourceRect and destRect (and _zoom)
// if setting zoomF (or showActualSize is YES), make sure imageCenter is also set
// output:
// sourceRect will be "rounded"/aligned to some fraction of a pixel appropriate to the zoom level
// destRect will be aligned to the backing
static NSRect ZoomAlignedRect(NSRect r, float zoom, CGFloat backingScaleFactor) {
	float m = roundf(zoom * backingScaleFactor);
	if (m <= 1.0) return NSIntegralRectWithOptions(r, NSAlignAllEdgesNearest);
	r.origin.x *= m;
	r.origin.y *= m;
	r.size.width *= m;
	r.size.height *= m;
	r = NSIntegralRectWithOptions(r, NSAlignAllEdgesNearest);
	r.origin.x /= m;
	r.origin.y /= m;
	r.size.width /= m;
	r.size.height /= m;
	return r;
}

- (void)calculateRectsAndSetNeedsDisplay {
	if (!image) {
		self.needsDisplay = YES;
		return;
	}
	NSSize bSize = self.bounds.size;
	CGFloat centerX = bSize.width/2, centerY = bSize.height/2;
	if (rotation == 90 || rotation == -90) {
		CGFloat tmp = bSize.height;
		bSize.height = bSize.width;
		bSize.width = tmp;
	}
	NSSize destSize = bSize;
	// if showActualSize and scalesUp are both on, smaller images need to be scaled up (in the else clause), and bigger images should be shown with a default zoom of 1
	if (zoomF || (showActualSize && !(scalesUp && _fullSize.width < bSize.width && _fullSize.height < bSize.height))) {
		// source size (for some subrect of the image)
		NSSize imgSize = image.size;
		float zoom = (zoomF ?: 1) * _fullSize.width / imgSize.width;
		sourceRect.size = NSMakeSize(bSize.width/zoom, bSize.height/zoom);
		if (sourceRect.size.width > imgSize.width) {
			sourceRect.size.width = imgSize.width;
			destSize.width = imgSize.width*zoom;
			sourceRect.origin.x = 0;
		} else {
			sourceRect.origin.x = MAX(imageCenter.x - sourceRect.size.width/2, 0);
			sourceRect.origin.x = MIN(sourceRect.origin.x, imgSize.width - sourceRect.size.width);
		}
		if (sourceRect.size.height > imgSize.height) {
			sourceRect.size.height = imgSize.height;
			destSize.height = imgSize.height*zoom;
			sourceRect.origin.y = 0;
		} else {
			sourceRect.origin.y = MAX(imageCenter.y - sourceRect.size.height/2, 0);
			sourceRect.origin.y = MIN(sourceRect.origin.y, imgSize.height - sourceRect.size.height);
		}
		_zoom = zoom;
	} else {
		sourceRect.origin = NSZeroPoint;
		sourceRect.size = image.size;
		
		if (!scalesUp
			&& sourceRect.size.width <= bSize.width
			&& sourceRect.size.height <= bSize.height)
		{
			destSize = sourceRect.size;
			_zoom = 1;
		} else {
			float w_ratio = bSize.width/sourceRect.size.width;
			float h_ratio = bSize.height/sourceRect.size.height;
			if (w_ratio < h_ratio) { // the side w/ bigger ratio needs to be shrunk
				destSize.height = sourceRect.size.height*w_ratio;
				destSize.width = bSize.width;
				_zoom = w_ratio;
			} else {
				destSize.width = sourceRect.size.width*h_ratio;
				destSize.height = bSize.height;
				_zoom = h_ratio;
			}
		}
	}
	sourceRect = ZoomAlignedRect(sourceRect, _zoom, self.window.backingScaleFactor);
	destRect = [self backingAlignedRect:NSMakeRect(centerX - destSize.width/2, centerY - destSize.height/2, destSize.width, destSize.height) options:NSAlignAllEdgesNearest];
	self.needsDisplay = YES;
}

- (NSAffineTransform *)drawingTransform {
	NSSize b = self.bounds.size;
	CGFloat centerX = b.width/2, centerY = b.height/2; // center of bounds rect
	NSAffineTransform *transform = [NSAffineTransform transform];
	[transform translateXBy:centerX yBy:centerY];
	if (rotation != 0) [transform rotateByDegrees:rotation];
	if (isImageFlipped) [transform scaleXBy:-1 yBy:1];
	[transform translateXBy:-centerX yBy:-centerY];
	return transform;
}

- (void)drawRect:(NSRect)rect {
	if (!image) {
		[_imageBackgroundColor set];
		NSRectFill(NSIntersectionRect(rect, self.bounds));
		return;
	}
	NSAffineTransform *transform = [self drawingTransform];
	[transform concat];
	
	[_imageBackgroundColor set]; // background for transparent gifs
	[NSBezierPath fillRect:destRect];

	NSGraphicsContext *cg = NSGraphicsContext.currentContext;
	NSImageInterpolation oldInterp = cg.imageInterpolation;
	cg.imageInterpolation = zoomF >= 6.0 ? NSImageInterpolationNone : NSImageInterpolationHigh;
	NSImage *toDraw = image;
	if (_webpImageSource) {
		CGImageRef webpFrame = CGImageSourceCreateImageAtIndex((CGImageSourceRef)_webpImageSource, _webpCurrentFrame, NULL);
		if (webpFrame) {
			toDraw = [[NSImage alloc] initWithCGImage:webpFrame size:NSZeroSize];
			if (!gifTimer || gifTimer.userInfo != _webpImageSource) {
				float frameDuration = [_webpFrameInfo[_webpCurrentFrame][@"DelayTime"] floatValue];
				if (frameDuration < .01) frameDuration = .01; // minimum of 10ms is apparently standard
				gifTimer = [NSTimer scheduledTimerWithTimeInterval:frameDuration target:self selector:@selector(animateWebp:) userInfo:_webpImageSource repeats:NO];
				gifTimer.tolerance = frameDuration*0.1;
			}
			CFRelease(webpFrame);
		}
	}
	[toDraw drawInRect:destRect fromRect:sourceRect operation:NSCompositingOperationSourceOver fraction:1.0];
	cg.imageInterpolation = oldInterp;
	
	[transform invert];
	[transform concat];

	if (image != toDraw) return; // animating webp, so no need to check if animating gif
	id rep = image.representations[0];
	if ([rep isKindOfClass:[NSBitmapImageRep class]]
		&& [rep valueForProperty:NSImageFrameCount]) {
		if (!gifTimer || gifTimer.userInfo != image) {
			float frameDuration = [[rep valueForProperty:NSImageCurrentFrameDuration] floatValue];
			gifTimer = [NSTimer scheduledTimerWithTimeInterval:frameDuration
														target:self selector:@selector(animateGIF:)
													  userInfo:image repeats:NO];
			gifTimer.tolerance = frameDuration*0.15;
		}
	}
}

- (void)animateGIF:(NSTimer *)t {
	gifTimer = nil;
	if (image != t.userInfo) return; // stop if image is changed
	
	NSBitmapImageRep *rep = (NSBitmapImageRep *)[t.userInfo representations][0];
	NSNumber *frameCount = [rep valueForProperty:NSImageFrameCount];
	int n = [[rep valueForProperty:NSImageCurrentFrame] intValue];
	if (++n == frameCount.intValue) n = 0;
	[rep setProperty:NSImageCurrentFrame withValue:@(n)];
	[self setNeedsDisplay:YES];
}

- (void)setWebpImageSource:(id)src {
	_webpImageSource = nil;
	CFDictionaryRef props = CGImageSourceCopyProperties((CGImageSourceRef)src, NULL);
	if (props) {
		NSArray *frameInfo = ((__bridge NSDictionary *)props)[@"{WebP}"][@"FrameInfo"];
		if (frameInfo && (_webpFrameCount = frameInfo.count) > 1) {
			_webpImageSource = src;
			_webpFrameInfo = frameInfo;
		}
		CFRelease(props);
	}
}

- (void)animateWebp:(NSTimer *)t {
	gifTimer = nil;
	if (_webpImageSource != t.userInfo) return;
	if (++_webpCurrentFrame == _webpFrameCount) _webpCurrentFrame = 0;
	[self setNeedsDisplay:YES];
}

- (void)setImage:(NSImage *)anImage {
	if (anImage != image) {
		image = anImage;
		_fullSize = image.size;
		_webpImageSource = nil;
		_webpCurrentFrame = 0;
	}
	zoomF = 0;
	NSSize imgSize = image.size;
	imageCenter = NSMakePoint(imgSize.width/2, imgSize.height/2);
	rotation = 0;
	isImageFlipped = NO;

	[NSCursor.arrowCursor set];
	[self calculateRectsAndSetNeedsDisplay];
}

- (void)setImage:(NSImage *)anImage withSize:(NSSize)aSize rotated:(int)degrees flipped:(BOOL)flipped zoomInfo:(DYImageViewZoomInfo *)zInfo {
	image = anImage;
	_fullSize = aSize;
	_webpImageSource = nil;
	_webpCurrentFrame = 0;
	if (zInfo) {
		zoomF = zInfo->zoomF;
		imageCenter = zInfo->center;
		float f = image.size.width/_fullSize.width;
		imageCenter.x *= f;
		imageCenter.y *= f;
	} else {
		zoomF = 0;
		NSSize s = image.size;
		imageCenter = NSMakePoint(s.width/2, s.height/2);
	}
	rotation = degrees;
	isImageFlipped = flipped;
	[self setCursor];
	[self calculateRectsAndSetNeedsDisplay];
}

#define MakeCenterPoint(R) NSMakePoint((R).origin.x + (R).size.width/2, (R).origin.y + (R).size.height/2)

- (int)addRotation:(int)r {
	rotation += r;
	if (rotation > 180) rotation -=360; else if (rotation < -90) rotation += 360;
	if (zoomF || showActualSize)
		imageCenter = MakeCenterPoint(sourceRect);
	[self calculateRectsAndSetNeedsDisplay];
	return rotation;
}

- (BOOL)toggleFlip {
	isImageFlipped = !isImageFlipped;
	if (rotation == 90 || rotation == -90) {
		rotation = -rotation;
	}
	[self calculateRectsAndSetNeedsDisplay];
	return isImageFlipped;
}

- (void)setScalesUp:(BOOL)b {
	if (scalesUp == b) return;
	scalesUp = b;
	[self calculateRectsAndSetNeedsDisplay];
}

- (void)setShowActualSize:(BOOL)b {
	if (showActualSize == b) return;
	showActualSize = b;
	[self calculateRectsAndSetNeedsDisplay];
}

- (void)calculateImageCenterAndSetNeedsDisplay {
	if (!image) return;
	imageCenter = MakeCenterPoint(sourceRect);
	[self setCursor];
	[self calculateRectsAndSetNeedsDisplay];
}

- (void)zoomActualSize {
	if (zoomF != 1) {
		zoomF = 1;
		[self calculateImageCenterAndSetNeedsDisplay];
	}
}

- (void)zoomIn {
	if (zoomF >= 512) {
		NSBeep();
		return;
	}
	float oldF = self.currentZoom;
	float p = 2*log2f(oldF); // find closest half-power of 2
	int n = (int)floorf(p);
	float f;
	do {
		n++;
		f = n%2 ? ldexpf(1.5,(n-1)/2) : ldexpf(1,n/2);
	} while (f <= oldF);
	
	if (!image) return;
	zoomF = f;
	NSSize imgSize = image.size;
	// if already zoomed in at the edge/corner, keep that edge/corner there
	if (sourceRect.size.width < imgSize.width) {
		if (sourceRect.origin.x == 0)
			imageCenter.x = 0;
		else if (sourceRect.origin.x == imgSize.width - sourceRect.size.width)
			imageCenter.x = imgSize.width;
		else
			imageCenter.x = NSMidX(sourceRect);
	} else {
		imageCenter.x = imgSize.width/2;
	}
	if (sourceRect.size.height < imgSize.height) {
		if (sourceRect.origin.y == 0)
			imageCenter.y = 0;
		else if (sourceRect.origin.y == imgSize.height - sourceRect.size.height)
			imageCenter.y = imgSize.height;
		else
			imageCenter.y = NSMidY(sourceRect);
	} else {
		imageCenter.y = imgSize.height/2;
	}
	[self setCursor];
	[self calculateRectsAndSetNeedsDisplay];
}

- (void)zoomOut {
	if (zoomF != 0 && zoomF < 0.002) {
		NSBeep();
		return;
	}
	float oldF = self.currentZoom;
	float p = 2*log2f(oldF);
	int n = (int)ceilf(p);
	do {
		n--;
		zoomF = n%2 ? ldexpf(1.5,(n-1)/2) : ldexpf(1,n/2);
	} while (zoomF >= oldF);
	[self calculateImageCenterAndSetNeedsDisplay];
}

- (void)zoomBy:(float)magnification atPoint:(NSPoint)locationInWindow {
	float currentZoom = self.currentZoom;
	if ((magnification < 0 && currentZoom < 0.002) || (magnification > 0 && currentZoom >= 512)) return;
	NSPoint p = [self convertPointToImage:locationInWindow], center = MakeCenterPoint(sourceRect);
	CGFloat dx = (p.x - center.x)*_zoom, dy = (p.y - center.y)*_zoom;
	float f = _zoom * (1.0 + magnification);
	imageCenter.x = p.x - dx/f;
	imageCenter.y = p.y - dy/f;
	zoomF = currentZoom * (1.0 + magnification);
	[self calculateRectsAndSetNeedsDisplay];
}

- (NSPoint)convertPointToImage:(NSPoint)p {
	p = [self convertPoint:p fromView:nil]; // convert from window coordinates
	NSAffineTransform *t = [self drawingTransform];
	[t invert];
	p = [t transformPoint:p];
	p.x -= destRect.origin.x;
	p.y -= destRect.origin.y;
	// p is now the offset from the image's sourceRect.origin
	NSPoint q = sourceRect.origin;
	q.x += p.x/_zoom;
	q.y += p.y/_zoom;
	return q;
}

- (void)fakeDragX:(float)x y:(float)y {
	float xmax,ymax;
	xmax = image.size.width - sourceRect.size.width;
	ymax = image.size.height - sourceRect.size.height;
	float zoom = zoomF ?: 1;
	if (xmax > 0 || ymax > 0) {
		x /= zoom;
		y /= zoom;
		float tmpX = x;
		switch (rotation) {
			case -90:
				x = -y;
				y = tmpX;
				break;
			case 90:
				x = y;
				y = -tmpX;
				break;
			case 180:
				x = -x;
				y = -y;
				break;
		}
		if (isImageFlipped) x = -x;
		imageCenter = NSMakePoint(NSMidX(sourceRect) - x, NSMidY(sourceRect) - y);
		[self calculateRectsAndSetNeedsDisplay];
	}
	if ([_delegate respondsToSelector:@selector(imageViewDragged:)])
		[_delegate imageViewDragged:self];
}

- (void)scrollWheel:(NSEvent *)e {
	if (self.dragMode)
		[self fakeDragX:e.deltaX*128 y:-e.deltaY*128];
	else
		[super scrollWheel:e];
}
- (void)mouseDown:(NSEvent *)e {
	if (self.dragMode) {
		[NSCursor.closedHandCursor push];
	}
	[super mouseDown:e];
}
- (void)mouseDragged:(NSEvent *)e {
	if (!image) return;
	NSSize imgSize = image.size;
	if (sourceRect.size.width < imgSize.width || sourceRect.size.height < imgSize.height) {
		[self fakeDragX:e.deltaX y:-e.deltaY]; // y is flipped?
		[NSCursor.closedHandCursor set];
	}
}
- (void)mouseUp:(NSEvent *)e {
	if (self.dragMode) {
		[NSCursor pop];
		[self setCursor];
	}
	[super mouseUp:e];
}

- (DYImageViewZoomInfo *)zoomInfo {
	if (!image) return nil;
	if (!showActualSize && zoomF == 0) return nil;
	NSPoint c = MakeCenterPoint(sourceRect);
	NSSize imgSize = image.size;
	if (showActualSize && zoomF == 0) {
		NSPoint p = NSMakePoint(imgSize.width/2, imgSize.height/2);
		if (fabs(c.x-p.x) < 1.1 && fabs(c.y-p.y) < 1.1)
			return nil;
	}
	DYImageViewZoomInfo *i = [[DYImageViewZoomInfo alloc] init];
	i->zoomF = zoomF;
	i->center = c;
	float f = image.size.width/_fullSize.width;
	i->center.x /= f;
	i->center.y /= f;
	return i;
}

- (BOOL)zoomMode { return zoomF != 0; }

- (BOOL)dragMode {
	if (!image) return NO;
	if (zoomF == 0 && !showActualSize) return NO;
	NSSize imgSize = image.size;
	return sourceRect.size.width < imgSize.width || sourceRect.size.height < imgSize.height;
}
- (void)setCursor {
	// sets hand or arrow, depending
	if (self.dragMode) {
		[NSCursor.openHandCursor set];
		[NSCursor setHiddenUntilMouseMoves:NO]; // NOT unhide
	} else {
		[NSCursor.arrowCursor set];
	}
}

@end
