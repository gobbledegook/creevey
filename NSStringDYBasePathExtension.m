//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//
//  NSStringDYBasePathExtension.m
//  creevey
//
//  Created by d on 2005.04.26.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import "NSStringDYBasePathExtension.h"


@implementation NSString (NSStringDYBasePathExtension)
// assume basePath has trailing '/'
- (NSString *)stringByDeletingBasePath:(NSString *)basePath {
	NSRange r = [self rangeOfString:basePath];
	if (r.location == 0 && r.length < [self length]) {
		return [self substringFromIndex:r.length];
	}
	return self;
}
@end
