//
//  EpegWrapper.m
//  Epeg
//
//  Created by Marc Liyanage on Fri Jan 16 2004.
//  Modified by Dominic Yu 2005 April 27 - 2006.08.07
//

#import "EpegWrapper.h"
#import "DYExiftags.h"

@implementation EpegWrapper

//+ (NSString *)jpegErrorMessage {
//	return [NSString stringWithCString:epeg_error_msg()];
//}

+ (NSImage *)imageWithPath:(NSString *)path
			   boundingBox:(NSSize)boundingBox
				   getSize:(NSSize *)pixSize
				 exifThumb:(BOOL)wantExifThumb
			getOrientation:(unsigned short *)orientationOut {

	Epeg_Image *im = NULL;
	NSImage *image;
	int width_in, height_in;
	
	im = epeg_file_open([path fileSystemRepresentation]);
	if (!im)
		return nil;
	
	epeg_size_get(im, &width_in, &height_in);
	if (width_in < boundingBox.width || height_in < boundingBox.height) {
		// fail if either dimension is too small
		// works around black areas outside small images
		epeg_close(im);
		return nil;
	}
	pixSize->width = width_in;
	pixSize->height = height_in;
	
	unsigned short orientation = [DYExiftags orientationForFile:path];
	if (orientationOut) *orientationOut = orientation;
	if (/* autorotate && */ orientation >= 5
		&& boundingBox.width < boundingBox.height != width_in < height_in) {
		// swap the width/height for the largest thumbnail, in case we need to rotate
		float tmp;
		tmp = boundingBox.width;
		boundingBox.width = boundingBox.height;
		boundingBox.height = tmp;
	}
	
	// insert clever EXIF thumbnail routine here
	const void *pixels;
	unsigned long outsize;
	NSBitmapImageRep *imageRep = nil;
	if (wantExifThumb && (pixels = epeg_exif_thumb(im, &outsize))) {
		NSData *data = [[NSData alloc] initWithBytesNoCopy:(void *)pixels length:outsize]; //outbuffer will be freed by NSData
		imageRep = [[NSBitmapImageRep alloc] initWithData:data];
		[data release];
		//NSLog(@"exif thumb for %@", path);
		NSSize tSize = [imageRep size];
		if (((int)tSize.width)*height_in != ((int)(tSize.height))*width_in) {
			// dimensions don't match
			[imageRep release];
			imageRep = nil;
		}
	}
	int width_out, height_out;
	if (!imageRep) {
		
		float bbox_ratio = (float)(boundingBox.width / boundingBox.height);
		float orig_ratio = ((float)width_in / (float)height_in);
		//	NSLog(@"bbox ratio: %f, orig_ratio: %f", bbox_ratio, orig_ratio);

		float scalefactor;
		scalefactor =
			(orig_ratio > bbox_ratio)
			? (float)(boundingBox.width / width_in)
			: (float)(boundingBox.height / height_in);
		//	NSLog(@"scale %f", scalefactor);

		width_out = (int)((float)width_in * scalefactor);
		height_out = (int)((float)height_in * scalefactor);
		//	NSLog(@"x in %d, y in %d / x out %d, y out %d", width_in, height_in, width_out, height_out);

		epeg_decode_size_set(im, width_out, height_out);
		epeg_decode_colorspace_set(im, EPEG_RGB8);

		if (epeg_scale_only(im) != 0)
			return nil;
		// sep call to epeg_scale_only, if error, the epeg handle will _probably_
		// be closed (but not necessarily, it seems--see the epeg source)
		pixels = epeg_pixels_get(im, 0, 0, width_out, height_out);
		if (!pixels) {
			NSLog(@"epeg unable to get pixels for path '%@'", path);
			epeg_close(im); // ... we _should_ need to close here, though
			return nil;
		}
		imageRep =
			[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
													pixelsWide:width_out
													pixelsHigh:height_out
												 bitsPerSample:8
											   samplesPerPixel:3
													  hasAlpha:NO
													  isPlanar:NO
												colorSpaceName:NSDeviceRGBColorSpace
												   bytesPerRow:width_out*3
												  bitsPerPixel:0];
		memcpy([imageRep bitmapData], pixels, (width_out * height_out * 3));
		epeg_pixels_free(im, pixels);
	}
	epeg_close(im);// */
	
	image = [[NSImage alloc] initWithSize:NSZeroSize];
	[image addRepresentation:imageRep];
	[imageRep release];
	//NSLog(@"%@", NSStringFromSize([image size]));
	
	return [image autorelease];
}

+ (NSImage *)exifThumbForPath:(NSString *)path {
	Epeg_Image *im = NULL;
	NSImage *image;
	
	im = epeg_file_open([path fileSystemRepresentation]);
	if (!im)
		return nil;
	
	const void *pixels;
	unsigned long outsize;
	NSBitmapImageRep *imageRep = nil;
	if ((pixels = epeg_exif_thumb(im, &outsize))) {
		NSData *data = [[NSData alloc] initWithBytesNoCopy:(void *)pixels length:outsize]; //outbuffer will be freed by NSData
		imageRep = [[NSBitmapImageRep alloc] initWithData:data];
		[data release];
	}
	epeg_close(im);
	if (!imageRep)
		return nil;
	
	image = [[NSImage alloc] initWithSize:NSZeroSize];
	[image addRepresentation:imageRep];
	[imageRep release];
	
	return [image autorelease];
}


@end
