//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  Created by d on 2005.04.26.

#import <Cocoa/Cocoa.h>

@interface NSString (NSStringDYBasePathExtension)
// assume basePath has trailing '/'
// returns self if basePath not found
- (NSString *)stringByDeletingBasePath:(NSString *)basePath;
@end
