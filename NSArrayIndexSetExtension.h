//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  NSArrayIndexSetExtension.h
//  creevey
//
//  Created by d on 2005.04.08.

#import <Cocoa/Cocoa.h>


@interface NSArray (DYIndexSetExtension)

- (NSArray *)subarrayWithIndexSet:(NSIndexSet *)s;

@end
/*
@interface NSMutableArray (DYIndexSetExtension)

- (void)removeObjectsFromIndices:(NSIndexSet *)s;

@end
*/