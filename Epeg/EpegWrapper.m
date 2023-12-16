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

static NSImage *ImageFromEpegStruct(Epeg_Image *im, NSSize boundingBox, NSSize *pixSize, BOOL wantExifThumb, unsigned short *orientation);

+ (NSImage *)imageWithPath:(NSString *)path
			   boundingBox:(NSSize)boundingBox
				   getSize:(NSSize *)pixSize
				 exifThumb:(BOOL)wantExifThumb
			getOrientation:(unsigned short *)orientationOut {
	Epeg_Image *im = epeg_file_open(path.fileSystemRepresentation);
	if (!im) return nil;
	return ImageFromEpegStruct(im, boundingBox, pixSize, wantExifThumb, orientationOut);
}

+ (NSImage *)imageWithData:(char *)data
					   len:(int)len
			   boundingBox:(NSSize)boundingBox
				 exifThumb:(BOOL)wantExifThumb
			getOrientation:(unsigned short *)orientationOut {
	Epeg_Image *im = epeg_memory_open((unsigned char *)data, len);
	if (!im) return nil;
	return ImageFromEpegStruct(im, boundingBox, NULL, wantExifThumb, orientationOut);
}

static NSImage *ImageFromEpegStruct(Epeg_Image *im, NSSize boundingBox, NSSize *pixSize, BOOL wantExifThumb, unsigned short *orientationOut) {
	NSImage *image;
	int width_in, height_in;
	epeg_size_get(im, &width_in, &height_in);
	if (width_in < boundingBox.width || height_in < boundingBox.height) {
		// fail if either dimension is too small
		// works around black areas outside small images
		epeg_close(im);
		return nil;
	}
	if (pixSize) {
		pixSize->width = width_in;
		pixSize->height = height_in;
	}
	FILE * f = epeg_fp(im); // borrow the open file pointer for our own purposes
	long pos = ftell(f);
	rewind(f);
	unsigned short orientation = ExifOrientationForFile(f);
	fseek(f, pos, SEEK_SET);
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
		//NSLog(@"exif thumb for %@", path);
		NSSize tSize = imageRep.size;
		if (((int)tSize.width)*height_in != ((int)(tSize.height))*width_in) {
			// dimensions don't match
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

		if (epeg_scale_only(im) != 0) {
			epeg_close(im);
			return nil;
		}
		pixels = epeg_pixels_get(im, 0, 0, width_out, height_out);
		if (!pixels) {
			epeg_close(im);
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
	epeg_close(im);
	
	image = [[NSImage alloc] initWithSize:NSZeroSize];
	[image addRepresentation:imageRep];
	//NSLog(@"%@", NSStringFromSize([image size]));
	
	return image;
}

+ (NSImage *)exifThumbForPath:(NSString *)path {
	Epeg_Image *im = NULL;
	NSImage *image;
	
	im = epeg_file_open(path.fileSystemRepresentation);
	if (!im)
		return nil;
	
	const void *pixels;
	unsigned long outsize;
	NSBitmapImageRep *imageRep = nil;
	if ((pixels = epeg_exif_thumb(im, &outsize))) {
		NSData *data = [[NSData alloc] initWithBytesNoCopy:(void *)pixels length:outsize]; //outbuffer will be freed by NSData
		imageRep = [[NSBitmapImageRep alloc] initWithData:data];
	}
	epeg_close(im);
	if (!imageRep)
		return nil;
	
	image = [[NSImage alloc] initWithSize:NSZeroSize];
	[image addRepresentation:imageRep];
	
	return image;
}


@end
