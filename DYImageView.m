//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//
//  DYImageView.m
//  creevey
//
//  Created by d on 2005.04.01.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import "DYImageView.h"

@implementation DYImageView

- (void)drawRect:(NSRect)rect {
	if (!image) return; //don't draw if nil
	
	NSRect sourceRect, destinationRect;
	NSRect boundsRect = [self bounds]; float tmp, zoom;
	float centerX, centerY;
	centerX = boundsRect.size.width/2;
	centerY = boundsRect.size.height/2;
	if (rotation == 90 || rotation == -90) {
		tmp = boundsRect.size.width;
		boundsRect.size.width = boundsRect.size.height;
		boundsRect.size.height = tmp;
	}
	
	sourceRect.origin = NSZeroPoint;
	sourceRect.size = [image size];
	
	if (!scalesUp
		&& sourceRect.size.width <= boundsRect.size.width
		&& sourceRect.size.height <= boundsRect.size.height)
	{
		destinationRect.size.width = (int)(sourceRect.size.width);
		destinationRect.size.height = (int)(sourceRect.size.height);
		zoom = 1;
	} else {
		float w_ratio, h_ratio;
		w_ratio = boundsRect.size.width/sourceRect.size.width;
		h_ratio = boundsRect.size.height/sourceRect.size.height;
		if (w_ratio < h_ratio) { // the side w/ bigger ratio needs to be shrunk
			destinationRect.size.height = (int)(sourceRect.size.height*w_ratio);
			destinationRect.size.width = (int)(boundsRect.size.width);
			zoom = w_ratio;
		} else {
			destinationRect.size.width = (int)(sourceRect.size.width*h_ratio);
			destinationRect.size.height = (int)(boundsRect.size.height);
			zoom = h_ratio;
		}
	}
	
	destinationRect.origin.x = (int)(centerX - destinationRect.size.width/2);
	destinationRect.origin.y = (int)(centerY - destinationRect.size.height/2);
	//destinationRect = NSIntegralRect(destinationRect); // make them integers, dammit

	//NSCachedImageRep *zzz = [[image representations] objectAtIndex:0];
	NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:centerX yBy:centerY];
	[transform rotateByDegrees:rotation];
	[transform translateXBy:-centerX yBy:-centerY];
	[transform concat];
	
	[[NSColor whiteColor] set]; // make a nice background for transparent gifs, etc.
	[NSBezierPath fillRect:destinationRect];
	
	NSGraphicsContext *cg = [NSGraphicsContext currentContext];
	NSImageInterpolation oldInterp = [cg imageInterpolation];
	[cg setImageInterpolation:zoom > 1 ? NSImageInterpolationNone : NSImageInterpolationLow];
	[image drawInRect:destinationRect fromRect:sourceRect operation:NSCompositeSourceOver fraction:1.0];
	[cg setImageInterpolation:oldInterp];
	
	//[transform invert];
	//[transform concat];
	id rep = [[image representations] objectAtIndex:0];
	if ([rep isKindOfClass:[NSBitmapImageRep class]]
		&& [rep valueForProperty:NSImageFrameCount]) {
		if (!gifTimer || [gifTimer userInfo] != image) gifTimer =
			[NSTimer scheduledTimerWithTimeInterval:[[rep valueForProperty:NSImageCurrentFrameDuration] floatValue]
											 target:self selector:@selector(animateGIF:)
										   userInfo:image repeats:NO];
	}
}

- (void)animateGIF:(NSTimer *)t {
	gifTimer = nil;
	if (image != [t userInfo]) return; // stop if image is changed
	
	NSBitmapImageRep *rep = [[[t userInfo] representations] objectAtIndex:0];
	NSNumber *frameCount = [rep valueForProperty:NSImageFrameCount];
	int n = [[rep valueForProperty:NSImageCurrentFrame] intValue];
	if (++n == [frameCount intValue]) n = 0;
	[rep setProperty:NSImageCurrentFrame
		   withValue:[NSNumber numberWithInt:n]];
	[self setNeedsDisplay:YES];
}

- (void)setImage:(NSImage *)anImage {
	[image release];
	image = [anImage retain];
	rotation = 0;
	[self setNeedsDisplay:YES];

	if (!image) return; //don't draw if nil
}

- (int)rotation { return rotation; }

- (int)addRotation:(int)r {
	rotation += r;
	if (rotation > 180) rotation -=360; else if (rotation < -180) rotation += 360;
	[self setNeedsDisplay:YES];
	return rotation;
}

- (void)setRotation:(int)n {
	rotation = n;
	[self setNeedsDisplay:YES];
}

//- (float)zoom { return zoom; }

- (BOOL)scalesUp { return scalesUp; }
- (void)setScalesUp:(BOOL)b {
	if (scalesUp == b) return;
	scalesUp = b;
	[self setNeedsDisplay:YES];
}

@end
