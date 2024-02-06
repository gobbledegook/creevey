//Copyright 2005-2023 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  Created by Dominic Yu 2005 July 12

#import "DYExiftags.h"
#import "DYCarbonGoodies.h"
#import "dcraw.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

//#include "jpeglib.h"
#include "exif.h"
#include "exifint.h"

static uint16_t read2byte(FILE * f, char o);
static BOOL SeekExifInJpeg(FILE * infile);
static int SeekExifInHeif(FILE * f);
static BOOL SeekExifIFD0(FILE * f, char *oo);
unsigned char *exif_jpegthumb(FILE * f, unsigned long *outsize);

struct my_error_mgr {
	struct jpeg_error_mgr pub;	/* "public" fields */
	jmp_buf setjmp_buffer;	/* for return to caller */
};
typedef struct my_error_mgr * my_error_ptr;
static void _my_error_handler(j_common_ptr cinfo)
{
	longjmp(((my_error_ptr)cinfo->err)->setjmp_buffer, 1);
	return;
}

static void appendprops(NSMutableString *result, unsigned char *data, int len, BOOL showMore)
{
	// ED_UNK, ED_CAM, ED_IMG, ED_VRB
	static NSString *headings[4]; // ARC inits these to nil
	if (headings[0] == nil) {
		headings[0] = NSLocalizedString(@"Unsupported Properties:\n", @"");
		headings[1] = NSLocalizedString(@"Camera-Specific Properties:\n", @"");
		headings[2] = NSLocalizedString(@"Image-Specific Properties:\n", @"");
		headings[3] = NSLocalizedString(@"Other Properties:\n", @"");
	}

	NSMutableString *section[4];
	unsigned short i = 0;
	for (; i<4; ++i) section[i] = [NSMutableString string];

	struct exiftags *t = exifparse(data, len);
	if (!t) return;
	struct exifprop *list = t->props;
	while (list) {
		unsigned short lvl = list->lvl;
		if (list->lvl == ED_PAS) lvl = ED_IMG; // point-and-shoot values
		if (list->lvl > ED_VRB) lvl = ED_VRB; // treat overridden & bad values as verbose

		if (showMore || lvl == ED_CAM || lvl == ED_IMG) {
			// fancy localization footwork
			NSString *internalKey = [NSString stringWithCString:list->name encoding:NSISOLatin1StringEncoding];
			NSString *locString = NSLocalizedStringFromTable(internalKey, @"EXIF", @"");
			if (locString == internalKey && list->descr) // fall back to exiftag's English desc, if available
				locString = [NSString stringWithCString:list->descr encoding:NSISOLatin1StringEncoding];
			
			i = __builtin_ctz(lvl); // convert the flag to an index
			[section[i] appendFormat:@"\t%@:\t", locString];
			if (list->str)
				[section[i] appendFormat:@"%s\n", list->str];
			// %s strings seem to get interpreted as MacRoman, which is good enough for now, given that EXIF doesn't have a standard encoding for string values
			else
				[section[i] appendFormat:@"%d\n", list->value];
		}
		list = list->next;
	}
	for (i=1; i<=4; ++i) {
		if (i==4) i=0; // do 0th item (ED_UNK) last
		if (section[i].length) {
			[result appendString:headings[i]];
			[result appendString:section[i]];
			[result appendString:@"\n"];
		}
		if (i==0) i=4;
	}
	exiffree(t);
	if (result.length) [result deleteCharactersInRange:NSMakeRange(result.length-2,2)]; // trailing newlines
}


@implementation DYExiftags

+ (NSString *)tagsForFile:(NSString *)aPath moreTags:(BOOL)showMore {
	NSMutableString *result = [NSMutableString stringWithCapacity:100];
	NSString *extension = aPath.pathExtension.lowercaseString;
	if (IsRaw(extension)) {
		int len;
		unsigned char *data = CopyExifDataFromRawFile(aPath.fileSystemRepresentation, &len);
		if (data) {
			appendprops(result, data, len, showMore);
			free(data);
		}
	} else if (IsHeif(extension)) {
		FILE * f;
		if ((f = fopen(aPath.fileSystemRepresentation, "rb")) == NULL) return nil;
		int len = 0;
		if ((len = SeekExifInHeif(f))) {
			fseek(f, -6, SEEK_CUR); // start at "Exif\0\0"
			len -= 4; // minus app marker + length fields (or whatever filler heif is using)
			unsigned char *data = malloc(len);
			if (data) {
				fread(data, 1, len, f);
				appendprops(result, data, len, showMore);
				free(data);
			}
		}
		fclose(f);
	} else if (FileIsJPEG(aPath)) {
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
				appendprops(result, mptr->data, mptr->data_length, showMore);
			}
			mptr = mptr->next;
		}
		if (jpeg_has_multiple_scans(&srcinfo))
			[result insertString:NSLocalizedString(@"Progressive JPEG file\n", @"") atIndex:0];
		jpeg_destroy_decompress(&srcinfo);
		fclose(input_file);
	}
	[result insertString:@"\n" atIndex:0];
	return result;
}

static unsigned short ExifOrientationForJpegFile(FILE * f) {
	unsigned short z = 0;
	if (SeekExifInJpeg(f)) {
		char o;
		if (SeekExifIFD0(f, &o)) {
			uint16_t n = read2byte(f,o);
			if (n) {
				while (n--) {
					if (read2byte(f,o) == 0x0112) {
						fseek(f, 6, SEEK_CUR);
						z = read2byte(f,o);
						break;
					}
					fseek(f, 10, SEEK_CUR);
				}
			}
		}
	}
	return z;
}

+ (unsigned short)orientationForFile:(NSString *)aPath {
	unsigned short z = 0;
	NSString *ext = aPath.pathExtension.lowercaseString;
	if (IsJPEG(ext)) {
		FILE * f = fopen(aPath.fileSystemRepresentation, "rb");
		if (f == NULL) return 0;
		z = ExifOrientationForJpegFile(f);
		fclose(f);
	} else if (IsRaw(ext)) {
		z = ExifOrientationFromRawFile(aPath.fileSystemRepresentation);
	}
	return z;
}

+ (NSImage *)exifThumbForPath:(NSString *)path {
	FILE * f = fopen(path.fileSystemRepresentation, "rb");
	if (!f) return nil;
	NSImage *image;
	const void *pixels;
	unsigned long outsize;
	if ((pixels = exif_jpegthumb(f, &outsize))) {
		NSData *data = [[NSData alloc] initWithBytesNoCopy:(void *)pixels length:outsize]; //outbuffer will be freed by NSData
		CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceTypeIdentifierHint: @"public.jpeg"});
		if (src) {
			CGImageRef ref = CGImageSourceCreateImageAtIndex(src, 0, NULL);
			if (ref) {
				image = [[NSImage alloc] initWithCGImage:ref size:NSZeroSize];
				CFRelease(ref);
			}
			CFRelease(src);
		}
	}
	fclose(f);
	return image;
}
@end

// let's just assume any values we want are non-zero
static uint16_t read2byte(FILE * f, char o) {
	int b = fgetc(f), c;
	if (b == EOF || (c = fgetc(f)) == EOF) return 0;
	if (o) return (b << 8) | c;
	return (c << 8) | b;
}
static uint16_t read2bytem(FILE * f) {
	int b = fgetc(f), c;
	if (b == EOF || (c = fgetc(f)) == EOF) return 0;
	return (b << 8) | c;
}
static uint32_t read4byte(FILE * f, char o) {
	unsigned char b[4];
	if (4 != fread(b, 1, 4, f)) return 0;
	if (o) return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
	return (b[3] << 24) | (b[2] << 16) | (b[1] << 8) | b[0];
}
static uint32_t read4bytem(FILE * f) {
	unsigned char b[4];
	if (4 != fread(b, 1, 4, f)) return 0;
	return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
}
static uint64_t read8bytem(FILE * f) {
	unsigned char b[8];
	if (8 != fread(b, 1, 8, f)) return 0;
	return ((uint64_t)b[0] << 56) | ((uint64_t)b[1] << 48) | ((uint64_t)b[2] << 40) | ((uint64_t)b[3] << 32) | (b[4] << 24) | (b[5] << 16) | (b[6] << 8) | b[7];
}

static int SeekExifInHeif(FILE * f) {
	// heif files are composed of "atoms" aka "boxes"
	BOOL inited = NO;
	for (;;) {
		off_t boxStart = ftello(f);
		uint64_t boxLen = read4bytem(f); // each atom starts with a 4-byte length
		if (boxLen < 8 && boxLen != 1)   // length==1 means an 8-byte length follows the type
			return NO;
		unsigned char type[4];
		if (4 != fread(type, 1, 4, f)) return 0;
		if (!inited) {
			// as a sanity check, make sure the first atom is 'ftyp'
			inited = YES;
			if (memcmp(type, "ftyp", 4)) return 0;
		}
		if (boxLen == 1) {
			boxLen = read8bytem(f);
		}
		if (memcmp(type, "meta", 4)) {
			if (fseeko(f, boxStart+boxLen, SEEK_SET)) // skip to next atom
				return 0;
			continue;
		}
		// found "meta" atom
		off_t metaEnd = boxStart + boxLen;
		fseek(f, 4, SEEK_CUR); // skip vers/flag
		uint32_t exifID = UINT32_MAX;
		while ((boxStart = ftello(f)) < metaEnd) {
			boxLen = read4bytem(f);
			if (boxLen < 8) return 0;
			if (4 != fread(type, 1, 4, f)) return 0;
			int version;
			if (!memcmp(type, "iinf", 4)) {
				version = fgetc(f);
				fseek(f, 3, SEEK_CUR); // skip flag
				uint32_t n = version ? read4bytem(f) : read2bytem(f);
				for (uint32_t i = 0; i < n; ++i) {
					off_t eStart = ftello(f);
					uint32_t eLen = read4bytem(f);
					if (eLen < 16) return 0; // must have at least size, type "infe", flag, and data
					fseek(f, 4, SEEK_CUR); // assume "infe"
					version = fgetc(f);
					fseek(f, 3, SEEK_CUR);
					uint32_t itemID;
					itemID = version <= 2 ? read2bytem(f) : read4bytem(f);
					fseek(f, 2, SEEK_CUR); // skip protection_index
					fread(type, 1, 4, f);
					if (!memcmp(type, "Exif", 4))
						exifID = itemID;
					fseeko(f, eStart+eLen, SEEK_SET);
				}
			} else if (!memcmp(type, "iloc", 4)) {
				version = fgetc(f);
				fseek(f, 3, SEEK_CUR);
				uint16_t config = read2bytem(f);
				uint16_t offset_size = (config >> 12) & 0xF;
				uint16_t length_size = (config >> 8) & 0xF;
				uint16_t base_offset_size = (config >> 4) & 0xF;
				uint16_t index_size = version >= 1 ? config & 0xF : 0;
				uint32_t n = version < 2 ? read2bytem(f) : read4bytem(f);
				if (n > 20000) return 0; // this value copied from libheif
				for (uint32_t i = 0; i < n; ++i) {
					uint32_t myId = version < 2 ? read2bytem(f) : read4bytem(f);
					if (version >= 1) fseek(f, 2, SEEK_CUR); // skip construction_method
					fseek(f, 2, SEEK_CUR); // skip data_reference_index
					uint64_t base_offset = 0;
					if (base_offset_size == 4) base_offset = read4bytem(f);
					else if (base_offset_size == 8) base_offset = read8bytem(f);
					uint16_t numExtents = read2bytem(f);
					if (numExtents > 32) return 0;
					if (myId != exifID) {
						fseek(f, numExtents*(index_size+offset_size+length_size), SEEK_CUR);
						continue;
					}
					// found Exif offset! Assume there's one and only one extent
					if (index_size) fseek(f, index_size, SEEK_CUR);
					off_t exifOffset = offset_size == 8 ? read8bytem(f) : read4bytem(f);
					uint64_t exifLength = length_size == 8 ? read8bytem(f) : read4bytem(f);
					exifOffset += base_offset;
					fseeko(f, exifOffset+4, SEEK_SET);
					unsigned char buf[6];
					if (6 != fread(buf, 1, 6, f)) return 0;
					if (memcmp(buf, "Exif\0\0", 6)) return 0;
					return (int)exifLength;
				}
			}
			fseeko(f, boxStart + boxLen, SEEK_SET);
		}
	}
	return 0;
}

static BOOL SeekExifInJpeg(FILE * infile)
{
	int a = fgetc(infile);
	if (a != 0xff || fgetc(infile) != 0xD8) return 0; // file starts with FFD8
	for(;;){
		int itemlen;
		int prev = 0;
		int marker = 0;
		for (a=0;;a++){
			marker = fgetc(infile);
			if (marker == EOF) return 0; // Unexpected end of file
			if (marker != 0xff && prev == 0xff) break; // each marker is FFxx, where xx is the marker number
			prev = marker;
		}
		if (a > 10)
			return 0; // Extraneous {a-1} padding bytes before section {marker}

		// Read the length of the section (in big endian order)
		itemlen = read2bytem(infile);
		if (itemlen < 2) return 0; // invalid marker

		unsigned char buf[6];
		switch(marker){
			case 0xDA: // stop before hitting compressed data
			case 0xD9: // End Of Image
				return 0;

			case 0xE1: // Exif (or possibly XMP)
				if (6 != fread(buf, 1, 6, infile)) return 0; // hit EOF
				if (memcmp(buf, "Exif\0\0", 6)) return 0; // not Exif
				return 1; // found it!
				break;

			default: // Skip any other sections.
				break;
		}
		fseek(infile, itemlen-2, SEEK_CUR);
	}
	return 0;
}

static BOOL SeekExifIFD0(FILE * f, char *oo) {
	long b0 = ftell(f);

	// get endian-ness
	enum byteorder o;
	unsigned char buf[2] = "\0\0";
	fread(buf, 1, 2, f);
	if (!memcmp(buf, "MM", 2)) o = 1;
	else if (!memcmp(buf, "II", 2)) o = 0;
	else return 0;

	// verify TIFF header
	if (read2byte(f,o) != 42) return 0;
	u_int32_t offset = read4byte(f, o);
	if (!offset) return 0;

	fseek(f, b0+offset, SEEK_SET);
	*oo = o;
	return YES;
}

static BOOL SeekExifSubIFD(FILE * f, char *oo) {
	long b0 = ftell(f);
	if (!SeekExifIFD0(f, oo)) return 0;
	enum byteorder o = *oo;
	uint16_t n;
	n = read2byte(f,o); // number of entries in this IFD
	if (!n) return 0;
	uint32_t exifOffset = 0;
	while (n--) {
		if (read2byte(f,o) == 0x8769) // offset to Exif SubIFD
		{
			fseek(f, 6, SEEK_CUR); // 2 + 6 = 8
			exifOffset = read4byte(f,o); // + 4 = 12
			break;
		}
		fseek(f, 10, SEEK_CUR); // 2 + 10 = 12 (each entry is 12 bytes)
	}
	if (!exifOffset) return 0;

	fseek(f, b0+exifOffset, SEEK_SET);
	return YES;
}

unsigned char *exif_jpegthumb(FILE * f, unsigned long *outsize) {
	if (SeekExifInJpeg(f)) {
		long b0 = ftell(f);
		char o;
		if (SeekExifIFD0(f, &o)) {
			fseek(f, 12*read2byte(f,o), SEEK_CUR); // skip the 0th IFD
			uint32_t n = read4byte(f,o); // offset of next IFD
			if (n == 0) return NULL; // non-standard EXIF will not have offset to next IFD!
			fseek(f, b0+n, SEEK_SET);
			n = read2byte(f,o); // num tags
			unsigned long thumbStart = 0, thumbLength = 0;
			while (n--) {
				uint16_t tag = read2byte(f,o);
				fseek(f, 6, SEEK_CUR);
				uint16_t val;
				switch (tag) {
					case 0x0103:
						val = read2byte(f,o);
						fseek(f, 2, SEEK_CUR);
						if (val != 6)
							return NULL; // not a JPEG thumb, we're done.
						break;
					case 0x0201:
						thumbStart = read4byte(f,o);
						break;
					case 0x0202:
						thumbLength = read4byte(f,o);
						break;
					case 0:
						return NULL; // EOF or tag 0x0000
						break;
					default:
						fseek(f, 4, SEEK_CUR);
						break;
				}
			}
			// sanity check on thumbLength, a 160x120 jpeg should take no more than 8.25 bits/pixel
			if (thumbStart == 0 || thumbLength == 0 || thumbLength > 32000) return NULL;
			unsigned char *buf = malloc(thumbLength);
			if (!buf) return NULL;
			*outsize = thumbLength;
			fseek(f, b0+thumbStart, SEEK_SET);
			if (fread(buf, thumbLength, 1, f))
				return buf;
		}
	}
	return NULL;
}

static BOOL exif_datetimeoriginal(FILE * f, unsigned char *outBuf) {
	long b0 = ftell(f);
	char o;
	if (!SeekExifSubIFD(f, &o)) return NO;

	uint16_t n = read2byte(f,o);
	if (!n) return NO;
	uint32_t stringOffset = 0;
	while (n--) {
		if (read2byte(f,o) == 0x9003) // DateTimeOriginal
		{
			fseek(f, 6, SEEK_CUR);
			stringOffset = read4byte(f,o);
			break;
		}
		fseek(f, 10, SEEK_CUR);
	}
	return stringOffset && !fseek(f, b0+stringOffset, SEEK_SET) && 20 == fread(outBuf, 1, 20, f);
}

time_t ExifDatetimeForFile(const char *path, DYExiftagsFileType type) {
	FILE * input_file;
	if ((input_file = fopen(path, "rb")) == NULL)
		return -1;
	BOOL ok = NO;
	switch (type) {
		case JPEG:
			ok = SeekExifInJpeg(input_file);
			break;
		case HEIF:
			ok = SeekExifInHeif(input_file) != 0;
			break;
	}
	if (!ok) {
		fclose(input_file);
		return -1;
	}
	time_t result = -1;
	unsigned char s[20];
	if (exif_datetimeoriginal(input_file, s)) {
		s[19] = 0; // make sure string is null-terminated before passing to sscanf
		struct tm t;
		if (sscanf((char *)s, "%d:%d:%d %d:%d:%d", &t.tm_year, &t.tm_mon,
				   &t.tm_mday, &t.tm_hour, &t.tm_min, &t.tm_sec) == 6) {
			t.tm_year -= 1900;
			t.tm_mon -= 1;
			t.tm_isdst = -1;
			result = mktime(&t);
		}
	}
	fclose(input_file);
	return result;
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
}

u_int32_t bytesTo0thIFD(unsigned char *b, unsigned len, enum byteorder *o) {
	if (len < 16) return 0; // 14 bytes read in this function, plus two for length of IFD
	if (memcmp(b, "Exif\0\0", 6)) return 0;
	b += 6;

	/* Determine endianness of the TIFF data. */
	if (!memcmp(b, "MM", 2)) *o = BIG;
	else if (!memcmp(b, "II", 2)) *o = LITTLE;
	else return 0;
	b += 2;

	/* Verify the TIFF header. */
	if (exif2byte(b, *o) != 42) return 0;
	b += 2;

	/* Get the 0th IFD, where all of the good stuff should start. */
	return exif4byte(b, *o);
}

// pass NULL,1 to just fetch jpeg data
// pass NULL,0 to delete thumb
// pass new jpeg data + len to replace it
// there's no error checking for type of data, but it MUST be JPEG, and you must
// calculate its width and height beforehand
// caller is responsible for freeing the new app1 data
unsigned char *replace_exif_thumb(unsigned char *newthumb, unsigned newthumblen,
								  JDIMENSION newWidth, JDIMENSION newHeight,
								  unsigned char *b, unsigned len,
								  unsigned *outLen)
{
	enum byteorder o;
	u_int32_t offset = bytesTo0thIFD(b, len, &o);
	if (!offset) return NULL;
	unsigned char *b0 = b + 6; // save beginning for offsets, later
	len -= 6;
	b = b0 + offset;
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
	unsigned thumbStart = 0;
	unsigned thumbLength = 0;
	
	while (n--) {
		switch (exif2byte(b,o)) {
			case 0x0103:
				if (exif2byte(b+8,o) != 6)
					return NULL; // not a JPEG thumb, we're done.
				break;
			case 0x0201:
				thumbStart = exif4byte(b+8,o);
				break;
			case 0x0202:
				thumbLength = exif4byte(b+8,o);
				break;
			default:
				break;
		}
		b += 12;
	}
	if (thumbStart == 0 /*|| thumbLength == 0*/) return NULL; // if uninitialized
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
		JDIMENSION tmp;
		while (n--) {
			// width x100, length x10x, bytecount x202
			uint16_t tag = exif2byte(b,o);
			switch (tag) {
				case 0x0100: // width
				case 0x0101: // height
					tmp = tag == 0x0100 ? newWidth : newHeight;
					if (exif2byte(b+2,o) == 3) {
						// short
						byte2exif(tmp,b+8,o);
						byte2exif(0,b+10,o);
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

unsigned short exif_orientation(unsigned char *b, unsigned len, char reset) {
	enum byteorder o;
	u_int32_t offset = bytesTo0thIFD(b, len, &o);
	if (!offset) return 0;
	unsigned char *b0 = b + 6; // save beginning for offsets, later
	len -= 6;
	b = b0 + offset;
	unsigned n;
	n = exif2byte(b,o); // number of entries in this IFD
	b += 2;
	if (len < offset + 2 + n*12) return 0;
	while (n--) {
		if (exif2byte(b,o) == 0x0112) // orientation
		{
			unsigned short z = exif2byte(b+8,o);
			if (reset)
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
