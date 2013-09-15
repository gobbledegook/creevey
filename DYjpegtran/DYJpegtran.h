//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  DYJpegtran.h
//
//  Created by Dominic Yu 2005 July 11

#import <Foundation/Foundation.h>
#include "jpeglib.h"
#include "transupp.h"

#define DYJPEGTRAN_XFORM_PROGRESSIVE 11
#define DYJPEGTRAN_XFORM_GRAYSCALE   12
#define DYJPEGTRAN_XFORM_AUTOROTATE  13
#define DYJPEGTRAN_XFORM_RESETORIENT 14
#define DYJPEGTRAN_XFORM_REGENTHUMB  15
#define DYJPEGTRAN_XFORM_DELETETHUMB 16

typedef struct {
	jpeg_transform_info tinfo;
	JCOPY_OPTION cp;
	BOOL progressive, optimize, preserveModificationDate,
		thumbOnly, autorotate, resetOrientation,
		replaceThumb, delThumb;
	NSData *newThumb; // must be JPEG!
	NSSize newThumbSize;
} DYJpegtranInfo;

@interface DYJpegtran : NSObject
// returns YES if the file was modified
+ (BOOL)transformImage:(NSString *)thePath transform:(DYJpegtranInfo *)i;
@end
