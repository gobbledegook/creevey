//
//  EpegWrapper.h
//  Epeg
//
//  Created by Marc Liyanage on Fri Jan 16 2004.
//  Modified by Dominic Yu 2005 April 27
//

#import <Foundation/Foundation.h>
#include "Epeg.h"

@interface EpegWrapper : NSObject 

+ (NSImage *)imageWithPath:(NSString *)path
			   boundingBox:(NSSize)boundingBox 
				   getSize:(NSSize *)pixSize
				 exifThumb:(BOOL)wantExifThumb
			getOrientation:(unsigned short *)orientationOut; // pass NULL if you don't need it

+ (NSImage *)imageWithData:(char *)data
					   len:(int)len
			   boundingBox:(NSSize)boundingBox
				 exifThumb:(BOOL)wantExifThumb
			getOrientation:(unsigned short *)orientationOut;

//+ (NSString *)jpegErrorMessage;

+ (NSImage *)exifThumbForPath:(NSString *)path;

@end
