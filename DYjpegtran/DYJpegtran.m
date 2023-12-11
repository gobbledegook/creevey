//Copyright 2005-2014 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  Created by Dominic Yu 2005 July 11

#import "DYJpegtran.h"
#import "DYExiftags.h"

static const unsigned short OrientTab[9] = {
	JXFORM_NONE,
	JXFORM_NONE,
	JXFORM_FLIP_H,
	JXFORM_ROT_180,
	JXFORM_FLIP_V,
	JXFORM_TRANSPOSE,
	JXFORM_ROT_90,
	JXFORM_TRANSVERSE,
	JXFORM_ROT_270
};

struct my_error_mgr {
	struct jpeg_error_mgr pub;	/* "public" fields */
	
	jmp_buf setjmp_buffer;	/* for return to caller */
};
typedef struct my_error_mgr * my_error_ptr;

static void 
_my_error_handler(j_common_ptr cinfo)
{
	my_error_ptr errmgr;
	
	errmgr = (my_error_ptr)cinfo->err;
	//(*cinfo->err->format_message)(cinfo, _jpegliberror);
	longjmp(errmgr->setjmp_buffer, 1);
	return;
}

static unsigned char *transformThumbnail(unsigned char *b, unsigned len,
								  jpeg_transform_info *info_copy,
								  unsigned *outLen,
								  JDIMENSION *newWidth, JDIMENSION *newHeight) {
	struct jpeg_decompress_struct srcinfo;
	struct jpeg_compress_struct dstinfo;
	struct my_error_mgr jsrcerr, jdsterr;
	jvirt_barray_ptr * src_coef_arrays;
	jvirt_barray_ptr * dst_coef_arrays;
	FILE * input_file;
	FILE * output_file;
	
	//	if ((output_file = fopen("/tmp/blah.jpg","w+b")) == NULL) {
	if ((output_file = tmpfile()) == NULL) {
		return NULL;
	}
	//	if ((input_file = fopen("/tmp/blahin.jpg","w+b")) == NULL) {
	if ((input_file = tmpfile()) == NULL) {
		fclose(output_file);
		return NULL;
	} else {
		fwrite(b,len,1,input_file);
		rewind(input_file);
	}
	srcinfo.err = jpeg_std_error(&jsrcerr.pub);
	jsrcerr.pub.error_exit = _my_error_handler;
	dstinfo.err = jpeg_std_error(&jdsterr.pub);
	jdsterr.pub.error_exit = _my_error_handler;
	
	if (setjmp(jsrcerr.setjmp_buffer) || setjmp(jdsterr.setjmp_buffer)) {
		jpeg_destroy_compress(&dstinfo);
		jpeg_destroy_decompress(&srcinfo);
		fclose(input_file);
		fclose(output_file);
		return NULL;
	}
	jpeg_create_decompress(&srcinfo);
	jpeg_create_compress(&dstinfo);
	
	jpeg_stdio_src(&srcinfo, input_file);
	(void) jpeg_read_header(&srcinfo, TRUE);
#if TRANSFORMS_SUPPORTED
	jtransform_request_workspace(&srcinfo, info_copy);
#endif
	src_coef_arrays = jpeg_read_coefficients(&srcinfo);
	jpeg_copy_critical_parameters(&srcinfo, &dstinfo);
#if TRANSFORMS_SUPPORTED
	dst_coef_arrays = jtransform_adjust_parameters(&srcinfo, &dstinfo,
												   src_coef_arrays,
												   info_copy);
#else
	dst_coef_arrays = src_coef_arrays;
#endif
	jpeg_stdio_dest(&dstinfo, output_file);
	jpeg_write_coefficients(&dstinfo, dst_coef_arrays);
#if TRANSFORMS_SUPPORTED
	jtransform_execute_transformation(&srcinfo, &dstinfo,
									  src_coef_arrays,
									  info_copy);
#endif
	*newWidth = srcinfo.image_width;
	*newHeight = srcinfo.image_height;
	
	jpeg_finish_compress(&dstinfo);
	jpeg_destroy_compress(&dstinfo);
	(void)jpeg_finish_decompress(&srcinfo);
	jpeg_destroy_decompress(&srcinfo);
	
	/* Close files, if we opened them */
	//_epeg_memfile_read_close(input_file);
	fclose(input_file);
	long numbytes = ftell(output_file);
	void *thebytes = malloc(numbytes);
	fseek(output_file,0,SEEK_SET);
	if (!thebytes ||
		numbytes != fread(thebytes,sizeof(char),numbytes,output_file)) {
		fclose(output_file);
		return NULL;
	}
	fclose(output_file);
	*outLen = numbytes;
	return thebytes;
	}



@implementation DYJpegtran

+ (BOOL)transformImage:(NSString *)thePath transform:(DYJpegtranInfo)i {
	// you need to pass-by-value the entire struct, since we modify it
	// (see "if (i.starting_exif_orientation > 1 ... )")
	struct jpeg_decompress_struct srcinfo;
	struct jpeg_compress_struct dstinfo;
	struct my_error_mgr jsrcerr, jdsterr;
	jvirt_barray_ptr * src_coef_arrays;
	jvirt_barray_ptr * dst_coef_arrays;
	FILE * input_file;
	FILE * output_file;
	JCOPY_OPTION copyoption = i.cp;
	jpeg_transform_info info_copy;
	
	// take into account current orientation and adjust accordingly
	if (i.starting_exif_orientation > 1
		&& !i.autorotate
		&& !i.resetOrientation) {
		int deg; BOOL flipped;
		exiforientation_to_components(i.starting_exif_orientation, &deg, &flipped);
		// note: jpegtran talks about rotation clockwise
		// but Cocoa does rotation counter-clockwise on an x-y plane.
		// so the following looks like it's backwards, but it's actually correct.
		switch (i.tinfo.transform) {
			case JXFORM_ROT_90:
				deg -= 90;
				break;
			case JXFORM_ROT_180:
				deg += 180;
				break;
			case JXFORM_ROT_270:
				deg += 90;
				break;
			case JXFORM_FLIP_H:
				flipped = !flipped;
				if (i.starting_exif_orientation > 4) deg += 180;
				// because flipping is order-dependent for 90-degree turns,
				// for the EXIF orientations involving 90-degree turns,
				// we have to add another 180 turn.
				// This applies to these four flip-toggle cases.
				break;
			case JXFORM_FLIP_V:
				flipped = !flipped;
				if (i.starting_exif_orientation <= 4) deg += 180;
				break;
			case JXFORM_TRANSPOSE:
				if (i.starting_exif_orientation <= 4) deg += 90; else deg -= 90;
				flipped = !flipped;
				break;
			case JXFORM_TRANSVERSE:
				if (i.starting_exif_orientation <= 4) deg -= 90; else deg += 90;
				flipped = !flipped;
				break;
			default:
				break;
		}
		if (deg > 180) deg -= 360; else if (deg == -180) deg = 180;
		if (deg == 0) {
			i.tinfo.transform = flipped ? JXFORM_FLIP_H : JXFORM_NONE;
		} else if (deg == 90) {
			i.tinfo.transform = flipped ? JXFORM_TRANSPOSE : JXFORM_ROT_270;
		} else if (deg == -90) {
			i.tinfo.transform = flipped ? JXFORM_TRANSVERSE : JXFORM_ROT_90;
		} else { // deg == 180
			i.tinfo.transform = flipped ? JXFORM_FLIP_V : JXFORM_ROT_180;
		}
		// after doing this, always reset the orientation!
		// but only if the transform is JXFORM_NONE,
		// otherwise the method might think it's a non-op (if the file's orientation tag is 1)
		// and stop executing later on.
		if (i.tinfo.transform == JXFORM_NONE)
			i.resetOrientation = YES;
	}
	
	/* Open files first, so setjmp can assume they're open. */
	if ((input_file = fopen(thePath.fileSystemRepresentation, "rb")) == NULL) {
		NSLog(@"DYJpegtran can't open %s\n", thePath.fileSystemRepresentation);
		return NO;
	}
	if ((output_file = tmpfile()) == NULL) {
		NSLog(@"DYJpegtran can't open temp file\n");
		fclose(input_file);
		return NO;
	}
	
	srcinfo.err = jpeg_std_error(&jsrcerr.pub);
	jsrcerr.pub.error_exit = _my_error_handler;
	dstinfo.err = jpeg_std_error(&jdsterr.pub);
	jdsterr.pub.error_exit = _my_error_handler;
	
	if (setjmp(jsrcerr.setjmp_buffer) || setjmp(jdsterr.setjmp_buffer)) {
		jpeg_destroy_compress(&dstinfo);
		jpeg_destroy_decompress(&srcinfo);
		fclose(input_file);
		fclose(output_file);
		NSLog(@"fatal error for %@", thePath);
		return NO;
	}
	jpeg_create_decompress(&srcinfo);
	jpeg_create_compress(&dstinfo);
	
	/* Note: we assume only the decompression object will have virtual arrays.
		*/
	
	//cinfo->err->trace_level = 0; // ** ??
	
	/* Specify data source for decompression */
	jpeg_stdio_src(&srcinfo, input_file);
	
	/* Enable saving of extra markers that we want to copy */
	jcopy_markers_setup(&srcinfo, copyoption);
	
	/* Read file header */
	(void) jpeg_read_header(&srcinfo, TRUE);
	
	// for EXIF, first marker should be guaranteed to be APP1, but just in case
	// a file has been manipulated by a non exifpatch'd jpegtran...
	jpeg_saved_marker_ptr app1markerptr;
	app1markerptr = srcinfo.marker_list;
	while (app1markerptr) {
		if (app1markerptr->marker == JPEG_APP0 + 1) break;
		app1markerptr = app1markerptr->next;
	}
	unsigned short currentOrientation;
	currentOrientation = app1markerptr ? exif_orientation(app1markerptr->data,app1markerptr->data_length,0) : 0;
	if (i.autorotate) {
		// this must be done before request_workspace for mem alloc reasons
		i.tinfo.transform = OrientTab[currentOrientation];
		// if it's 0, the next "if" will exit this function
	}
	
	// skip file if nothing is changing
	unsigned outSize;
	if ((i.replaceThumb && (!i.newThumb
							 || !app1markerptr
							 || !find_exif_thumb(app1markerptr->data,
												 app1markerptr->data_length,
												 &outSize)))
		|| (i.autorotate && currentOrientation <= 1) // !app1markerptr
		|| (i.resetOrientation && currentOrientation <= 1) // !app1markerptr
		|| (i.delThumb && (!app1markerptr
							|| !find_exif_thumb(app1markerptr->data,
												app1markerptr->data_length,
												&outSize)
							|| outSize == 0))
		|| (!i.tinfo.transform
			&& !i.tinfo.force_grayscale
			&& i.cp == JCOPYOPT_ALL
			&& !i.optimize
			&& (i.progressive == jpeg_has_multiple_scans(&srcinfo))
			&& !i.replaceThumb
			&& !i.resetOrientation
			&& !i.delThumb)
		)
	{
		jpeg_destroy_compress(&dstinfo);
		jpeg_destroy_decompress(&srcinfo);
		fclose(input_file);
		fclose(output_file);
		//NSLog(@"No change! exiting transformImage");
		return NO;
	}
	
	// 
	info_copy = i.tinfo;  // you MUST make a new copy, since
						   // execute_transform mucks with this! Many hours were wasted because of this error...
	if (i.thumbOnly) {
		i.tinfo.transform = JXFORM_NONE;
		i.tinfo.force_grayscale = 0;
		i.tinfo.trim = 0;
	}
	
	
	/* Any space needed by a transform option must be requested before
		* jpeg_read_coefficients so that memory allocation will be done right.
		*/
#if TRANSFORMS_SUPPORTED
	jtransform_request_workspace(&srcinfo, &i.tinfo);
#endif
	
	/* Read source file as DCT coefficients */
	src_coef_arrays = jpeg_read_coefficients(&srcinfo);
	
	/* Initialize destination compression parameters from source values */
	jpeg_copy_critical_parameters(&srcinfo, &dstinfo);
	
	/* Adjust destination parameters if required by transform options;
	* also find out which set of coefficient arrays will hold the output.
		*/
#if TRANSFORMS_SUPPORTED
	dst_coef_arrays = jtransform_adjust_parameters(&srcinfo, &dstinfo,
												   src_coef_arrays,
												   &i.tinfo);
#else
	dst_coef_arrays = src_coef_arrays;
#endif
	
	//cinfo->optimize_coding = TRUE;
	if (i.progressive)
		jpeg_simple_progression(&dstinfo);
	if (i.optimize)
		dstinfo.optimize_coding = TRUE;
	
	/* Specify data destination for compression */
	jpeg_stdio_dest(&dstinfo, output_file);
	
	/* Start compressor (note no image data is actually written here) */
	jpeg_write_coefficients(&dstinfo, dst_coef_arrays);
	
	// DY - this is where we'd want to fiddle with the APP1 marker
	/* consider applying exif orientation patch
		http://sylvana.net/jpegcrop/exif_orientation.html
	 */
	unsigned oldApp1Size;
	unsigned char *oldthumb, *newthumb, *oldapp1, *newapp1;
	JDIMENSION newWidth, newHeight;
	// skip this thumb rotating step if no rotation
	// ** maybe we should also do grayscale on the thumb? too much work...
	newapp1 = NULL;
	if (app1markerptr) {
		if (info_copy.transform) {
			oldthumb = find_exif_thumb(app1markerptr->data,
									   app1markerptr->data_length,
									   &outSize);
			if (oldthumb) {
				newthumb = transformThumbnail(oldthumb,outSize,&info_copy,&outSize,
											  &newWidth,&newHeight);
				if (newthumb) {
					newapp1 = replace_exif_thumb(newthumb,outSize,newWidth,newHeight,
												 app1markerptr->data,
												 app1markerptr->data_length,
												 &outSize);
					free(newthumb); // old wasn't malloc'd, doesn't need freeing
				}
			}
		} else if (i.delThumb) {
			newapp1 = delete_exif_thumb(app1markerptr->data,app1markerptr->data_length,&outSize);
		} else if (i.replaceThumb) {
			newapp1 = replace_exif_thumb((unsigned char *)i.newThumb.bytes,i.newThumb.length,
										 i.newThumbSize.width,i.newThumbSize.height,
										 app1markerptr->data,
										 app1markerptr->data_length,
										 &outSize);
		}
		if (newapp1) {
			oldapp1 = app1markerptr->data;
			oldApp1Size = app1markerptr->data_length;
			app1markerptr->data = newapp1;
			app1markerptr->data_length = outSize;
		}
	}
	// reset the orientation tag
	// ** note: we modify in-place, which i think is OK...
	if (app1markerptr && (info_copy.transform || i.resetOrientation)) {
		exif_orientation(app1markerptr->data,app1markerptr->data_length,1); // reset it
	}
	
	/* Copy to the output file any extra markers that we want to preserve */
	jcopy_markers_execute(&srcinfo, &dstinfo, copyoption);
	
	if (app1markerptr && newapp1) {
		app1markerptr->data = oldapp1;
		app1markerptr->data_length = oldApp1Size;
		free(newapp1);
	}
	/* Execute image transformation, if any */
#if TRANSFORMS_SUPPORTED
	jtransform_execute_transformation(&srcinfo, &dstinfo,
									  src_coef_arrays,
									  &i.tinfo);
#endif
	
	
	/* Finish compression and release memory */
	jpeg_finish_compress(&dstinfo);
	jpeg_destroy_compress(&dstinfo);
	(void)jpeg_finish_decompress(&srcinfo);
	jpeg_destroy_decompress(&srcinfo);
	
	/* Close files, if we opened them */
	fclose(input_file);
	// save over orig file first
	long numbytes = ftell(output_file);
	//NSLog(@"%ld", numbytes);
	void *thebytes = malloc(numbytes);
	fseek(output_file,0,SEEK_SET);
	if (!thebytes ||
		numbytes != fread(thebytes,sizeof(char),numbytes,output_file)) {
		fclose(output_file);
		NSLog(@"couldn't copy the bytes!");
		return NO;
	}
	fclose(output_file);
	
	NSMutableArray *fkeys = [NSMutableArray arrayWithObjects:NSFileCreationDate, NSFileHFSCreatorCode, NSFileHFSTypeCode, nil];
	if (i.preserveModificationDate)
		[fkeys addObject:NSFileModificationDate];
	NSArray *fatts = [[NSFileManager.defaultManager attributesOfItemAtPath:thePath.stringByResolvingSymlinksInPath error:NULL] objectsForKeys:fkeys notFoundMarker:[NSNull null]];
	//NSLog(@"%@", [fatts objectAtIndex:0]);
	NSData *theData = [[NSData alloc] initWithBytesNoCopy:thebytes length:numbytes freeWhenDone:YES];
	[theData writeToFile:thePath atomically:YES];
	
	//restore date created, hfs codes
	[NSFileManager.defaultManager setAttributes:[NSDictionary dictionaryWithObjects:fatts forKeys:fkeys]
									 ofItemAtPath:thePath error:NULL];
	
	/* All done. */
	return YES;//exit(jsrcerr.num_warnings + jdsterr.num_warnings ?EXIT_WARNING:EXIT_SUCCESS);
}

@end
