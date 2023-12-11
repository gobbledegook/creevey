//Copyright 2005-2012 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  Created by Dominic Yu 2005 July 12

#import "DYExiftags.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

//#include "jpeglib.h"
#include "exif.h"
#include "exifint.h"

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
			id internalKey = [NSString stringWithCString:list->name encoding:NSISOLatin1StringEncoding];
			id locString = NSLocalizedStringFromTable(internalKey,
													  @"EXIF", @"");
			if (locString == internalKey && list->descr)
				// failed, use exiftag's English desc
				// but check if it's NULL
				locString = [NSString stringWithCString:list->descr encoding:NSISOLatin1StringEncoding];
			if (list->str)
				[result appendFormat:@"\t%@:\t%s\n", locString, list->str]; // %s strings seem to get interpreted as MacRoman, which is good enough for now, given that EXIF doesn't have a standard encoding for string values
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
	if ((input_file = fopen(aPath.fileSystemRepresentation, "rb")) == NULL) {
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
			[result insertString:[[NSString alloc] initWithBytes:mptr->data length:mptr->data_length
														encoding:NSMacOSRomanStringEncoding]
						 atIndex:0];
			[result insertString:NSLocalizedString(@"JPEG Comment:\n", @"") atIndex:0];
		} else if (mptr->marker == JPEG_APP0+1) {
			t = exifparse(mptr->data, mptr->data_length);
			// may return NULL if it's not a proper EXIF marker
			
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
			if (result.length) // in case APP1 header is not EXIF!
				[result deleteCharactersInRange:NSMakeRange(result.length-2,2)];
			    // delete two trailing newlines (see printprops)
			    // this is not run for jpeg comments (duh)
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

+ (unsigned short)orientationForFile:(NSString *)aPath {
	unsigned len;
	unsigned char *app1 = exifHeaderForFile(aPath,&len);
	if (!app1)
		return 0;
	unsigned short z = exif_orientation(app1,len,0);
	free(app1);
	return z;
}

@end


unsigned char *exifHeaderForFile(NSString *aPath, unsigned *len) {
	struct jpeg_decompress_struct srcinfo;
	struct my_error_mgr jsrcerr;
	FILE * input_file;
	
	/* Open files first, so setjmp can assume they're open. */
	if ((input_file = fopen(aPath.fileSystemRepresentation, "rb")) == NULL)
		return NULL;
	srcinfo.err = jpeg_std_error(&jsrcerr.pub);
	jsrcerr.pub.error_exit = _my_error_handler;
	
	if (setjmp(jsrcerr.setjmp_buffer)) {
		jpeg_destroy_decompress(&srcinfo);
		fclose(input_file);
		return NULL;
	}
	jpeg_create_decompress(&srcinfo);
	jpeg_stdio_src(&srcinfo, input_file);
	jpeg_save_markers(&srcinfo,JPEG_APP0+1,0xFFFF);
	jpeg_read_header(&srcinfo, TRUE);
	
	jpeg_saved_marker_ptr mptr = srcinfo.marker_list;
	unsigned char *newapp1 = NULL;
	if (mptr && (mptr->marker == JPEG_APP0+1)) {
		newapp1 = malloc(mptr->data_length);
		if (newapp1) {
			memcpy(newapp1,mptr->data,mptr->data_length);
			*len = mptr->data_length;
		}
	}
	jpeg_destroy_decompress(&srcinfo);
	fclose(input_file);
	return newapp1;
}


static unsigned largestExifOffset(unsigned oldLargest,
								  unsigned char *b0, unsigned len,
								  unsigned char *b, enum byteorder o) {
	while (1) {
		unsigned n;
		n = exif2byte(b,o); // number of entries in this IFD
		b += 2;
		u_int32_t tmp;
		unsigned short num_bytes;
		while (n--) {
			tmp = exif4byte(b+8,o);
			switch (exif2byte(b+2,o)) {
				case 1:
				case 2:
				case 6:
				case 7:
					num_bytes = 1;
					break;
				case 3:
				case 8:
					num_bytes = 2;
					break;
				case 4:
				case 9:
				case 11:
					num_bytes = 4;
					break;
				case 5:
				case 10:
				case 12:
				default:
					num_bytes = 8;
					break;
			}
			if (num_bytes * exif4byte(b+4,o) > 4) {
				if (tmp > oldLargest)
					oldLargest = tmp;
			}
			if (exif2byte(b,o) == 0x8769 || exif2byte(b,o) == 0xA005) {
				// subIFD
				if (tmp < len) {
					if (tmp > oldLargest) oldLargest = tmp;
					oldLargest = largestExifOffset(oldLargest,b0,len,b0+tmp,o);
				}
			}
			b += 12;
		}
		tmp = exif4byte(b,o);
		if (!tmp)
			break;
		if (tmp >= len)  // not really necessary, if well-formed exif
			break;
		b = b0 + tmp;
	}
	return oldLargest;
}


/*
 * Write an unsigned 2-byte int to a buffer.
 */
static void
byte2exif(u_int16_t n, unsigned char *b, enum byteorder o)
{
	int i;
	
	if (o == BIG)
		for (i = 0; i < 2; i++)
			b[1 - i] = (unsigned char)((n >> (i * 8)) & 0xff);
	else
		for (i = 0; i < 2; i++)
			b[i] = (unsigned char)((n >> (i * 8)) & 0xff);
}

/* send app1 marker to a function
find length thumb,total
make sure new size < 65533

realloc, replace
update IFD1 with thumbnail length
also width, height; maybe look for hints in adjust_exif_parameters (in transupp.c)?
finally adjust app1 length
*/

unsigned char *find_exif_thumb(unsigned char *b, unsigned len,
							   unsigned *outLen)
{
	return replace_exif_thumb(NULL,1,0,0,b,len,outLen);
}
unsigned char *delete_exif_thumb(unsigned char *b, unsigned len,
								 unsigned *outLen)
{
	return replace_exif_thumb(NULL,0,0,0,b,len,outLen);
// the following code strips out the entire IFD1 EXIF block
// this may be undesirable if we wish to regenerate a thumb at some future point
//	if (memcmp(b, "Exif\0\0", 6)) {
//		return NULL;
//	}
//	b += 6;
//	len -= 6;
//	unsigned char *b0 = b; // save beginning for offsets, later
//	enum byteorder o;
//	/* Determine endianness of the TIFF data. */
//	if (!memcmp(b, "MM", 2))
//		o = BIG;
//	else if (!memcmp(b, "II", 2))
//		o = LITTLE;
//	else {
//		return NULL;
//	}
//	b += 2;
//	
//	/* Verify the TIFF header. */
//	if (exif2byte(b, o) != 42) {
//		return NULL;
//	}
//	b += 2;
//	
//	/* Get the 0th IFD, where all of the good stuff should start. */
//	b = b0 + exif4byte(b, o);
//	/* skip the 0th IFD */
//	b += 12*exif2byte(b,o);
//	b += 2; // don't forget the two bytes you read in the last line!
//	unsigned n = exif4byte(b,o); // offset of next IFD
//	unsigned offset_of_link_to_ifd1offset = b - b0 + 6;
//	if (n == 0)
//		return NULL;
//	b = b0 + n;
//	
//	unsigned ifd1offset = n + 6; // save IFD1 offset
//	
//	/* make sure this is the last IFD */
//	b += 12*exif2byte(b,o);
//	b += 2;
//	if (exif4byte(b,o))
//		return NULL;
//	
//	unsigned char *newapp1;
//	newapp1 = malloc(ifd1offset);
//	if (!newapp1)
//		return NULL;
//	memcpy(newapp1, b0-6, ifd1offset);
//	byte4exif(0,newapp1 + offset_of_link_to_ifd1offset,o);
//	*outLen = ifd1offset;
//	return newapp1;
}

// n.b. code sort of duplicated in (actually copied from) my modified copy of epeg.c
// pass NULL,1 to just fetch jpeg data
// pass NULL,0 to delete thumb
// pass new jpeg data + len to replace it
// there's no error checking for type of data, but it MUST be JPEG, and you must
// calculate its width and height beforehand
// caller is responsible for freeing the new app1 data
unsigned char *replace_exif_thumb(unsigned char *newthumb, unsigned long newthumblen,
								  JDIMENSION newWidth, JDIMENSION newHeight,
								  unsigned char *b, unsigned len,
								  unsigned *outLen)
{
	if (memcmp(b, "Exif\0\0", 6)) {
		return NULL;
	}
	b += 6;
	len -= 6;
	unsigned char *b0 = b; // save beginning for offsets, later
	enum byteorder o;
	
	/* Determine endianness of the TIFF data. */
	
	if (!memcmp(b, "MM", 2))
		o = BIG;
	else if (!memcmp(b, "II", 2))
		o = LITTLE;
	else {
		return NULL;
	}
	
	b += 2;
	
	/* Verify the TIFF header. */
	
	if (exif2byte(b, o) != 42) {
		return NULL;
	}
	b += 2;
	
	/* Get the 0th IFD, where all of the good stuff should start. */
	b = b0 + exif4byte(b, o);
	/* skip the 0th IFD */
	b += 12*exif2byte(b,o);
	b += 2; // don't forget the two bytes you read in the last line!
	unsigned n = exif4byte(b,o); // offset of next IFD
	if (n == 0)
		return NULL;
	// check for non-standard EXIF - will not have offset to next IFD!
	if (n > len-6)
		return NULL;
	b = b0 + n;

	unsigned ifd1offset = n + 6; // save IFD1 offset

	n = exif2byte(b,o); // number of tags in IFD1
	b += 2;
	unsigned long thumbStart = 0;
	unsigned long thumbLength = 0;
	
	u_int32_t tmp;
	while (n--) {
		tmp = exif4byte(b+8,o);
		//printf("#%u in IFD1 is tag %x, value %u\n", n,exif2byte(b,o),tmp);
		switch (exif2byte(b,o)) {
			case 0x0103:
				if (tmp != 6)
					return NULL; // not a JPEG thumb, we're done.
				break;
			case 0x0201:
				thumbStart = tmp;
				break;
			case 0x0202:
				thumbLength = tmp;
				break;
			default:
				break;
		}
		b += 12;
	}
	if (thumbStart == 0 /*|| thumbLength == 0*/) return NULL; // if uninitialized
	//printf("found an EXIF thumb! len: %lu, lim: %u\n", thumbStart + thumbLength, len);
	if (thumbStart + thumbLength > len) return NULL; // make sure it's contained in our APP1 marker
	if (newthumblen != 1) {
		// Hopefully no one ever accidentally passes in a 1-byte data block to this function,
		// cuz we use '1' as a sentinel value meaning don't replace, just return a pointer
		if (thumbStart + newthumblen > 0xFFF5) // too much data too fit
			return NULL;
		unsigned tmpLargestOffset = largestExifOffset(0,b0,len-6,b0 + exif4byte(b0+4, o),o);
		if (thumbStart < tmpLargestOffset) // thumb not at end of APP1, so fail
			return NULL;
		unsigned char *newapp1;
		newapp1 = malloc(thumbStart + newthumblen + 6);
		if (!newapp1)
			return NULL;
		memcpy(newapp1, b0-6, thumbStart+6);
		if (newthumb)
			memcpy(newapp1+thumbStart+6, newthumb, newthumblen);
		*outLen = thumbStart + newthumblen + 6;
		
		// now, replace relevant tags in the new IFD1
		b = newapp1 + ifd1offset;
		n = exif2byte(b,o); // number of tags in IFD1
		b += 2;
		while (n--) {
			// width x100, length x10x, bytecount x202
			switch (exif2byte(b,o)) {
				case 0x0100: // width
				case 0x0101: // height
					tmp =  exif2byte(b,o) == 0x0100 ? newWidth : newHeight;
					if (exif2byte(b+2,o) == 3) {
						// short
						byte2exif(tmp,b+8,o);
						byte2exif(0,b+10,o);
						//NSLog(@"just wrote a short!");
					} else {
						// long
						byte4exif(tmp,b+8,o);
					}
					break;
				case 0x0202:
					byte4exif(newthumblen,b+8,o);
					break;
				default:
					break;
			}
			b += 12;
		}
		
		return newapp1;
	}
	*outLen = thumbLength;
	return b0 + thumbStart;
}

// ** lots of repeated code here; factor out stuff to verify tiff header?
// also, make sure our pointer doesn't go past len.
unsigned short exif_orientation(unsigned char *b, unsigned len, char reset) {
	if (memcmp(b, "Exif\0\0", 6)) {
		return 0;
	}
	b += 6;
	len -= 6;
	unsigned char *b0 = b; // save beginning for offsets, later
	enum byteorder o;
	/* Determine endianness of the TIFF data. */
	if (!memcmp(b, "MM", 2))
		o = BIG;
	else if (!memcmp(b, "II", 2))
		o = LITTLE;
	else {
		return 0;
	}
	b += 2;
	
	/* Verify the TIFF header. */
	if (exif2byte(b, o) != 42) {
		return 0;
	}
	b += 2;
	
	/* Get the 0th IFD, where all of the good stuff should start. */
	b = b0 + exif4byte(b, o);
	unsigned n;
	n = exif2byte(b,o); // number of entries in this IFD
	b += 2;
	while (n--) {
		if (exif2byte(b,o) == 0x0112) // orientation
		{
			unsigned short z = exif2byte(b+8,o);
			if (reset && (b - b0 + 4 <= len))
				byte2exif(1,b+8,o);
			if (z > 0 && z <= 8)
				return z;
			else
				return 0;
		}
		b += 12;
	}
	return 0;
}

void exiforientation_to_components(unsigned short n, int *getDegrees, BOOL *getFlipped) {
	switch (n) {
		case 1: *getDegrees = 0; *getFlipped = NO; break;
		case 8: *getDegrees = 90; *getFlipped = NO; break;
		case 6: *getDegrees = -90; *getFlipped = NO; break;
		case 3: *getDegrees = 180; *getFlipped = NO; break;
		case 2: *getDegrees = 0; *getFlipped = YES; break;
		case 5: *getDegrees = 90; *getFlipped = YES; break;
		case 7: *getDegrees = -90; *getFlipped = YES; break;
		case 4: *getDegrees = 180; *getFlipped = YES; break;
		default: *getDegrees = 0; *getFlipped = NO; break;
	}
}

unsigned short components_to_exiforientation(int deg, BOOL flipped) {
	if (deg == 0) {
		return flipped ? 2 : 1;
	} else if (deg == 90) {
		return flipped ? 5 : 8;
	} else if (deg == -90) {
		return flipped ? 7 : 6;
	} else { // deg == 180
		return flipped ? 4 : 3;
	}
}
