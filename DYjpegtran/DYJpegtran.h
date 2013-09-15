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

typedef struct {
	jpeg_transform_info tinfo;
	JCOPY_OPTION cp;
	BOOL progressive, optimize, preserveModificationDate;
} DYJpegtranInfo;

@interface DYJpegtran : NSObject
+ (BOOL)transformImage:(NSString *)thePath transform:(DYJpegtranInfo *)i;
@end
