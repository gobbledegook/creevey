//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  DYExiftags.h
//
//  Created by Dominic Yu 2005 July 12

#include "jpeglib.h"
#import <Foundation/Foundation.h>

@interface DYExiftags : NSObject
+ (NSString *)tagsForFile:(NSString *)aPath moreTags:(BOOL)showMore;
+ (unsigned short)orientationForFile:(NSString *)aPath;
@end


// after some false starts, i've decided the following are best here.
// perhaps even better, we could make a pure C file with these instead.

unsigned char *find_exif_thumb(unsigned char *b, unsigned len,
							   unsigned *outLen);

//except for find_exif_thumb, all of these allocate new memory, which
// the caller is responsible for freeing
unsigned char *exifHeaderForFile(NSString *aPath, unsigned *len);
unsigned char *delete_exif_thumb(unsigned char *b, unsigned len,
								 unsigned *outLen);
unsigned char *replace_exif_thumb(unsigned char *newthumb, unsigned long newthumblen,
								  JDIMENSION newWidth, JDIMENSION newHeight,
								  unsigned char *b, unsigned len,
								  unsigned *outLen);
// obviously this doesn't malloc
unsigned short exif_orientation(unsigned char *b, unsigned len, char reset);
