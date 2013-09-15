//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  DYJpegtran.m
//
//  Created by Dominic Yu 2005 July 11

#import "DYJpegtran.h"

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


@implementation DYJpegtran

+ (BOOL)transformImage:(NSString *)thePath transform:(DYJpegtranInfo *)i {
	struct jpeg_decompress_struct srcinfo;
	struct jpeg_compress_struct dstinfo;
	struct my_error_mgr jsrcerr, jdsterr;
	jvirt_barray_ptr * src_coef_arrays;
	jvirt_barray_ptr * dst_coef_arrays;
	FILE * input_file;
	FILE * output_file;
	JCOPY_OPTION copyoption = i->cp;
	
	/* Open files first, so setjmp can assume they're open. */
	if ((input_file = fopen([thePath fileSystemRepresentation], "rb")) == NULL) {
		NSLog(@"DYJpegtran can't open %s\n", [thePath fileSystemRepresentation]);
		return NO;
	}
	if ((output_file = tmpfile()) == NULL) {
		NSLog(@"DYJpegtran can't open temp file\n");
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
	
	// skip file if nothing is changing
	if (!i->tinfo.transform
		&& !i->tinfo.force_grayscale
		&& i->cp == JCOPYOPT_ALL
		&& !i->optimize
		&& (i->progressive == jpeg_has_multiple_scans(&srcinfo)))
		return YES;
	
	/* Any space needed by a transform option must be requested before
		* jpeg_read_coefficients so that memory allocation will be done right.
		*/
#if TRANSFORMS_SUPPORTED
	jtransform_request_workspace(&srcinfo, &i->tinfo);
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
												   &i->tinfo);
#else
	dst_coef_arrays = src_coef_arrays;
#endif
	
	//cinfo->optimize_coding = TRUE;
	if (i->progressive)
		jpeg_simple_progression(&dstinfo);
	if (i->optimize)
		dstinfo.optimize_coding = TRUE;
	
	/* Specify data destination for compression */
	jpeg_stdio_dest(&dstinfo, output_file);
	
	/* Start compressor (note no image data is actually written here) */
	jpeg_write_coefficients(&dstinfo, dst_coef_arrays);
	
	/* Copy to the output file any extra markers that we want to preserve */
	jcopy_markers_execute(&srcinfo, &dstinfo, copyoption);
	
	/* Execute image transformation, if any */
#if TRANSFORMS_SUPPORTED
	jtransform_execute_transformation(&srcinfo, &dstinfo,
									  src_coef_arrays,
									  &i->tinfo);
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
	
	NSArray *fkeys = [NSArray arrayWithObjects:NSFileCreationDate, NSFileHFSCreatorCode, NSFileHFSTypeCode, nil];
	NSArray *fatts = [[[NSFileManager defaultManager] fileAttributesAtPath:thePath traverseLink:YES]
		objectsForKeys:fkeys notFoundMarker:[NSNull null]];
	//NSLog(@"%@", [fatts objectAtIndex:0]);
	NSData *theData = [[NSData alloc] initWithBytesNoCopy:thebytes length:numbytes freeWhenDone:YES];
	[theData writeToFile:thePath atomically:YES];
	[theData release];
	
	//restore date created, hfs codes
	[[NSFileManager defaultManager] changeFileAttributes:[NSDictionary dictionaryWithObjects:fatts forKeys:fkeys]
												  atPath:thePath];
	
	/* All done. */
	return YES;//exit(jsrcerr.num_warnings + jdsterr.num_warnings ?EXIT_WARNING:EXIT_SUCCESS);
}

@end
