//Copyright 2005-2026 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  Created by d on 2005.04.01.

@import Cocoa;
@class DYImageView;
@class DYImageViewZoomInfo;

@protocol DYImageViewDelegate <NSObject>
- (void)imageViewDragged:(DYImageView *)theImageView;
@end

@interface DYImageView : NSView
// image properties/methods
@property (nonatomic) NSImage *image;
- (void)setImage:(NSImage *)anImage withSize:(NSSize)aSize rotated:(int)degrees flipped:(BOOL)flipped zoomInfo:(DYImageViewZoomInfo *)zInfo;
@property (nonatomic) id webpImageSource; // CGImageSourceRef
@property (nonatomic, readonly) int rotation;
@property (nonatomic, readonly) BOOL imageFlipped;
@property (nonatomic, readonly) DYImageViewZoomInfo *zoomInfo;
- (int)addRotation:(int)r;
- (BOOL)toggleFlip;

// zoom
@property (nonatomic, readonly) float currentZoom;
- (void)zoomActualSize;
- (void)zoomIn;
- (void)zoomOut;
- (void)zoomBy:(float)magnification atPoint:(NSPoint)locationInWindow;
- (void)fakeDragX:(float)x y:(float)y;
@property (nonatomic, readonly) BOOL zoomMode;
@property (nonatomic, readonly) BOOL dragMode;

// general view properties
@property (nonatomic) BOOL scalesUp;
@property (nonatomic) BOOL showActualSize;
@property (nonatomic) NSColor *imageBackgroundColor;
@property (nonatomic, weak) id<DYImageViewDelegate> delegate;

- (void)setCursor;
@end
