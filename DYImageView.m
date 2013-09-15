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

//- (id)initWithFrame:(NSRect)frame {
//    self = [super initWithFrame:frame];
//    if (self) {
//        // Initialization code here.
//    }
//    return self;
//}

- (void)drawRect:(NSRect)rect {
	NSRect sourceRect, destinationRect;
	NSRect boundsRect = [self bounds]; float tmp;
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
	
	if (sourceRect.size.width <= boundsRect.size.width
		&& sourceRect.size.height <= boundsRect.size.height) {
		destinationRect.size.width = (int)(sourceRect.size.width);
		destinationRect.size.height = (int)(sourceRect.size.height);
	} else {
		float w_ratio, h_ratio;
		w_ratio = boundsRect.size.width/sourceRect.size.width;
		h_ratio = boundsRect.size.height/sourceRect.size.height;
		if (w_ratio < h_ratio) { // the side w/ bigger ratio needs to be shrunk
			destinationRect.size.height = (int)(sourceRect.size.height*w_ratio);
			destinationRect.size.width = (int)(boundsRect.size.width);
		} else {
			destinationRect.size.width = (int)(sourceRect.size.width*h_ratio);
			destinationRect.size.height = (int)(boundsRect.size.height);
		}
	}
	
	destinationRect.origin.x = (int)(centerX - destinationRect.size.width/2);
	destinationRect.origin.y = (int)(centerY - destinationRect.size.height/2);
	//destinationRect = NSIntegralRect(destinationRect); // make them integers, dammit
	
	NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:centerX yBy:centerY];
	[transform rotateByDegrees:rotation];
	[transform translateXBy:-centerX yBy:-centerY];
	[transform concat];
	[[NSColor whiteColor] set]; // make a nice background for transparent gifs, etc.
	[NSBezierPath fillRect:destinationRect];
	[image drawInRect:destinationRect fromRect:sourceRect operation:NSCompositeSourceOver fraction:1.0];
	//[transform invert];
	//[transform concat];
}

- (void)setImage:(NSImage *)anImage {
	[image release];
	image = [anImage retain];
	rotation = 0;
	[self setNeedsDisplay:YES];
}

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
@end
