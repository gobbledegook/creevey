//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  Created by d on 2005.04.01.

@import Cocoa;

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

@interface DYImageView : NSView
@property (nonatomic) NSImage *image;
@property (nonatomic) int rotation;
@property (nonatomic) BOOL scalesUp;
@property (nonatomic) BOOL showActualSize;
@property (nonatomic, getter=isImageFlipped) BOOL imageFlipped;
@property (nonatomic, readonly) float zoomF;

- (void)setImage:(NSImage *)anImage zooming:(DYImageViewZoomMode)zoomMode;
- (int)addRotation:(int)r;
- (BOOL)toggleFlip;
- (void)zoomOff;
- (void)zoomActualSize;
- (void)zoomIn;
- (void)zoomOut;
- (void)setZoomF:(float)f;
- (void)fakeDragX:(float)x y:(float)y;

@property (nonatomic, readonly) BOOL zoomMode;
@property (nonatomic, readonly) BOOL zoomInfoNeedsSaving;

@property (nonatomic, readonly) BOOL dragMode;
- (void)setCursor;

@property (nonatomic) DYImageViewZoomInfo *zoomInfo;

@end
