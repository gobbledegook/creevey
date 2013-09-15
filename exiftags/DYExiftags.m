//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  DYExiftags.m
//
//  Created by Dominic Yu 2005 July 12

#import "DYExiftags.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>


//#include "jpeg.h"
#include "jpeglib.h"
#include "exif.h"

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
	longjmp(errmgr->setjmp_buffer, 1);
	return;
}

static NSString *
printprops(struct exifprop *list, unsigned short lvl, int pas)
{
	//const char *n;
	NSMutableString *result = [NSMutableString stringWithCapacity:100];
	
	switch (lvl) {
		case ED_UNK:
			[result appendString:NSLocalizedString(@"Unsupported Properties:\n", @"")];
			break;
		case ED_CAM:
			[result appendString:NSLocalizedString(@"Camera-Specific Properties:\n", @"")];
			break;
		case ED_IMG:
			[result appendString:NSLocalizedString(@"Image-Specific Properties:\n", @"")];
			break;
		case ED_VRB:
			[result appendString:NSLocalizedString(@"Other Properties:\n", @"")];
			break;
	}
	
	while (list) {
		
		/* Take care of point-and-shoot values. */
		
		if (list->lvl == ED_PAS)
			list->lvl = pas ? ED_CAM : ED_IMG;
		
		/* For now, just treat overridden & bad values as verbose. */
		
		if (list->lvl == ED_OVR || list->lvl == ED_BAD)
			list->lvl = ED_VRB;
		if (list->lvl == lvl) {
			// fancy localization footwork
			//n = list->descr ? list->descr : list->name;
			id internalKey = [NSString stringWithCString:list->name];
			id locString = NSLocalizedStringFromTable(internalKey,
													  @"EXIF", @"");
			if (locString == internalKey && list->descr)
				// failed, use exiftag's English desc
				// but check if it's NULL
				locString = [NSString stringWithCString:list->descr];
			if (list->str)
				[result appendFormat:@"\t%@:\t%s\n", locString, list->str];
			else
				[result appendFormat:@"\t%@:\t%d\n", locString, list->value];
		}
		
		list = list->next;
	}
	[result appendString:@"\n"];
	return result;
}


@implementation DYExiftags

+ (NSString *)tagsForFile:(NSString *)aPath moreTags:(BOOL)showMore {
	NSMutableString *result = [NSMutableString stringWithCapacity:100];
	struct exiftags *t;
	int pas = 0;
/*	unsigned char *exifbuf;
	int mark, gotexif, first;
	unsigned int len, rlen;
	FILE *fp;

	gotexif = FALSE;
	first = 0;
	exifbuf = NULL;
	
	if ((fp = fopen([aPath fileSystemRepresentation],"r")) == NULL) {
		return nil;
	}
	
	while (jpegscan(fp, &mark, &len, !(first++))) {
		
		if (mark != JPEG_M_APP1) {
			if (fseek(fp, len, SEEK_CUR)) {
				fclose(fp);
				return nil;
			} //exifdie((const char *)strerror(errno));
			continue;
		}
		
		exifbuf = (unsigned char *)malloc(len);
		if (!exifbuf) {
			fclose(fp);
			return nil;
		}	//exifdie((const char *)strerror(errno));
		
		rlen = fread(exifbuf, 1, len, fp);
		if (rlen != len) {
			//exifwarn("error reading JPEG (length mismatch)");
			free(exifbuf);
			fclose(fp);
			return nil;
		}
		
		t = exifparse(exifbuf, len);
		
		if (t && t->props) {
			gotexif = TRUE;
			
			//if (dumplvl & ED_CAM)
			[result appendString:printprops(t->props, ED_CAM, pas)];
			//if (dumplvl & ED_IMG)
			[result appendString:printprops(t->props, ED_IMG, pas)];
			//if (dumplvl & ED_VRB)
			//[result appendString:printprops(t->props, ED_VRB, pas)];
			//if (dumplvl & ED_UNK)
			//[result appendString:printprops(t->props, ED_UNK, pas)];
		}
		exiffree(t);
		free(exifbuf);
	}
	fclose(fp);
	
	if (!gotexif) {
		//exifwarn("couldn't find Exif data");
		return nil;
	}
	
	return [result copy];*/
	struct jpeg_decompress_struct srcinfo;
	struct my_error_mgr jsrcerr;
	FILE * input_file;
	
	/* Open files first, so setjmp can assume they're open. */
	if ((input_file = fopen([aPath fileSystemRepresentation], "rb")) == NULL) {
		return nil;
	}
	srcinfo.err = jpeg_std_error(&jsrcerr.pub);
	jsrcerr.pub.error_exit = _my_error_handler;
	
	if (setjmp(jsrcerr.setjmp_buffer)) {
		jpeg_destroy_decompress(&srcinfo);
		fclose(input_file);
		return nil;
	}
	jpeg_create_decompress(&srcinfo);
	jpeg_stdio_src(&srcinfo, input_file);
	jpeg_save_markers(&srcinfo,JPEG_COM,0xFFFF);
	jpeg_save_markers(&srcinfo,JPEG_APP0+1,0xFFFF);
	jpeg_read_header(&srcinfo, TRUE);
	
	jpeg_saved_marker_ptr mptr = srcinfo.marker_list;
	while (mptr) {
		if (mptr->marker == JPEG_COM) {
			// go backwards, comments at the beginning
			[result insertString:@"\n" atIndex:0];
			[result insertString:[NSString stringWithCString:mptr->data length:mptr->data_length]
						 atIndex:0];
			[result insertString:NSLocalizedString(@"JPEG Comment:\n", @"") atIndex:0];
		} else if (mptr->marker == JPEG_APP0+1) {
			t = exifparse(mptr->data, mptr->data_length);
			
			if (t && t->props) {
				//if (dumplvl & ED_CAM)
				[result appendString:printprops(t->props, ED_CAM, pas)];
				//if (dumplvl & ED_IMG)
				[result appendString:printprops(t->props, ED_IMG, pas)];
				if (showMore) {
					//if (dumplvl & ED_VRB)
					[result appendString:printprops(t->props, ED_VRB, pas)];
					//if (dumplvl & ED_UNK)
					[result appendString:printprops(t->props, ED_UNK, pas)];
				}
			}
			exiffree(t);
			[result deleteCharactersInRange:NSMakeRange([result length]-2,2)];
		}
		mptr = mptr->next;
	}
	[result insertString:@"\n" atIndex:0];
	if (jpeg_has_multiple_scans(&srcinfo))
		[result insertString:NSLocalizedString(@"Progressive JPEG file\n", @"") atIndex:0];
	jpeg_destroy_decompress(&srcinfo);
	fclose(input_file);
	return result;
}

@end
