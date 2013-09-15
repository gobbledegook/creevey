//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//
//  NSArrayIndexSetExtension.m
//  creevey
//
//  Created by d on 2005.04.08.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import "NSArrayIndexSetExtension.h"


@implementation NSArray (DYIndexSetExtension)

- (NSArray *)subarrayWithIndexSet:(NSIndexSet *)s {
	unsigned int i, *indexes;
//	NSRange r; OBSOLETE CODE**
//	r.location = 0;
//	r.length = [self count];
	unsigned int numIndexes = [s count];
	
	indexes = malloc(sizeof(unsigned int *)*numIndexes);
	NSAssert(indexes, @"subarrayWithIndexSet malloc failed!");
	
	[s getIndexes:indexes maxCount:numIndexes inIndexRange:NULL];
	
	NSMutableArray *a = [[NSMutableArray alloc] initWithCapacity:numIndexes];
	for (i=0; i<numIndexes; ++i)
		[a addObject:[self objectAtIndex:indexes[i]]];
	NSArray *b = [NSArray arrayWithArray:a];
	free(indexes);
	[a release];
	return b;
}

@end


/*
@implementation NSMutableArray (DYIndexSetExtension)

- (void)removeObjectsFromIndices:(NSIndexSet *)s {
	NSRange r = NSMakeRange(0, [self count]);
	unsigned int numSelected, numIndexes = [s count];
	
	unsigned int *indexes = malloc(sizeof(unsigned int *)*numIndexes);
	NSAssert(indexes, @"removeObjectsFromIndices malloc failed!");
	
	numSelected = [s getIndexes:indexes maxCount:numIndexes inIndexRange:&r];
	[self removeObjectsFromIndices:indexes numIndices:numSelected];
	free(indexes);
}

@end
*/