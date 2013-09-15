//
//  EpegWrapper.m
//  Epeg
//
//  Created by Marc Liyanage on Fri Jan 16 2004.
//  Modified by Dominic Yu 2005 April 27
//

#import "EpegWrapper.h"

/*@interface EpegBitmapImageRep : NSBitmapImageRep
@end
@implementation EpegBitmapImageRep
- (void)dealloc {
	free([self bitmapData]);
	[super dealloc];
}
@end
// */


@implementation EpegWrapper

//+ (NSString *)jpegErrorMessage {
//	return [NSString stringWithCString:epeg_error_msg()];
//}

+ (NSImage *)imageWithPath:(NSString *)path
			   boundingBox:(NSSize)boundingBox
				   getSize:(NSSize *)pixSize {

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

	float bbox_ratio = (float)(boundingBox.width / boundingBox.height);
	float orig_ratio = ((float)width_in / (float)height_in);
	//	NSLog(@"bbox ratio: %f, orig_ratio: %f", bbox_ratio, orig_ratio);

	float scalefactor;
	scalefactor =
		(orig_ratio > bbox_ratio)
		? (float)(boundingBox.width / width_in)
		: (float)(boundingBox.height / height_in);
	//	NSLog(@"scale %f", scalefactor);

	int width_out = (int)((float)width_in * scalefactor);
	int height_out = (int)((float)height_in * scalefactor);
	//	NSLog(@"x in %d, y in %d / x out %d, y out %d", width_in, height_in, width_out, height_out);

	epeg_decode_size_set(im, width_out, height_out);
	epeg_decode_colorspace_set(im, EPEG_RGB8);

/*	//option1
	unsigned char *outbuffer;
	int outsize;
	epeg_memory_output_set(im, &outbuffer, &outsize);
	//epeg_quality_set(im, 75);
	if (epeg_encode(im) != 0) {
		// ALWAYS check the return code!
		NSLog(@"unable to encode epeg thumbnail for path '%@'", path);
		epeg_close(im);
		return nil;
	}
	//NSLog(@"%d compressed, from %d", outsize, (width_out * height_out * 3));
	epeg_close(im);
	NSData *data = [[NSData alloc] initWithBytesNoCopy:outbuffer length:outsize]; //outbuffer will be freed by NSData
	NSBitmapImageRep *imageRep = [[NSBitmapImageRep alloc] initWithData:data];
	[data release]; // */
	
	//option2
	//possibly faster since we skip compression
	//but it seems about the same (b/c of memcpying more memory?)
	const void *pixels;
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
	NSBitmapImageRep *imageRep =
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
	epeg_close(im);// */
	
	image = [[NSImage alloc] initWithSize:NSZeroSize];
	[image addRepresentation:imageRep];
	[imageRep release];
	
	//NSLog(@"%@", NSStringFromSize([image size]));
	
	return image; // N.B.: retained, NOT autoreleased!!!
}

@end
