//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  DYImageView.h
//  creevey
//
//  Created by d on 2005.04.01.

#import <Cocoa/Cocoa.h>

@interface DYImageViewZoomInfo : NSObject {
	@public
	NSRect sourceRect;
	NSSize destSize;
	float zoomF;
}
@end

typedef NS_ENUM(char, DYImageViewZoomMode) {
	DYImageViewZoomModeZoomOut,
	DYImageViewZoomModeZoomIn,
	DYImageViewZoomModeActualSize,
	DYImageViewZoomModeManual,
};

@interface DYImageView : NSView {
	NSImage *image;
	NSTimer *gifTimer;
	int rotation;
	BOOL scalesUp, showActualSize, isImageFlipped;
	NSRect sourceRect;
	NSSize destSize;
	float zoomF;
}

- (NSImage *)image;
- (void)setImage:(NSImage *)anImage;
- (void)setImage:(NSImage *)anImage zooming:(DYImageViewZoomMode)zoomMode;
- (int)rotation;
- (int)addRotation:(int)r;
- (void)setRotation:(int)n;
- (void)setFlip:(BOOL)b;
- (BOOL)toggleFlip;
- (BOOL)isImageFlipped;

//- (float)zoom;
- (BOOL)scalesUp;
- (void)setScalesUp:(BOOL)b;
- (BOOL)showActualSize;
- (void)setShowActualSize:(BOOL)b;

- (void)zoomOff;
- (void)zoomActualSize;
- (void)zoomIn;
- (void)zoomOut;
- (void)setZoomF:(float)f;
- (void)fakeDragX:(float)x y:(float)y;

- (BOOL)zoomMode;
- (BOOL)zoomInfoNeedsSaving;
- (float)zoomF;

- (BOOL)dragMode;
- (void)setCursor;

- (DYImageViewZoomInfo *)zoomInfo;
- (void)setZoomInfo:(DYImageViewZoomInfo *)i;

@end
