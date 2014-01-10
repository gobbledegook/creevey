#import "DYRandomizableArray.h"

@implementation DYRandomizableArray

- (id)init
{
    self = [super init];
    if (self) {
		array = [[NSMutableArray alloc] init];
		orderedArray = [[NSMutableArray alloc] init];
		randomToOrdered = [[NSMutableArray alloc] init];
		orderedToRandom = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [array release];
	[orderedArray release];
	[randomToOrdered release];
	[orderedToRandom release];
	[super dealloc];
}

// array stuff
- (unsigned)count {
	return [array count];
}

- (id)objectAtIndex:(unsigned)index {
	return [array objectAtIndex:index];
}

- (unsigned)indexOfObject:(id)anObject {
	return [array indexOfObject:anObject];
}

// mutable array stuff
- (void)setArray:(NSArray *)otherArray {
	[array setArray:otherArray];
	[orderedArray removeAllObjects];
	[randomToOrdered removeAllObjects];
	[orderedToRandom removeAllObjects];
}

- (void)removeAllObjects {
	[array removeAllObjects];
	[orderedArray removeAllObjects];
	[randomToOrdered removeAllObjects];
	[orderedToRandom removeAllObjects];
}

- (void)removeObjectAtIndex:(unsigned)index {
	if ([orderedArray count]) {
		// remove the item from orderedArray
		unsigned orderedIndex = [self orderedIndexOfObjectAtIndex:index];
		[orderedArray removeObjectAtIndex:orderedIndex];

		// adjust r2o
		unsigned i, count = [array count];
		for (i=0; i<count; ++i) {
			unsigned n = [[randomToOrdered objectAtIndex:i] unsignedIntegerValue];
			if (n > orderedIndex)
				[randomToOrdered replaceObjectAtIndex:i withObject:[NSNumber numberWithUnsignedInteger:n-1]];
		}
		[randomToOrdered removeObjectAtIndex:index];

		// adjust o2r
		for (i=0; i<count; ++i) {
			unsigned n = [[orderedToRandom objectAtIndex:i] unsignedIntegerValue];
			if (n > index)
				[orderedToRandom replaceObjectAtIndex:i withObject:[NSNumber numberWithUnsignedInteger:n-1]];
		}
		[orderedToRandom removeObjectAtIndex:orderedIndex];
	}
	[array removeObjectAtIndex:index];
}

- (void)removeObject:(id)anObject {
	unsigned i = [array indexOfObject:anObject];
	if (i == NSNotFound) return;
	[self removeObjectAtIndex:i];
}

// randomizable stuff
- (void)derandomize {
	[array setArray:orderedArray];
	[orderedArray removeAllObjects];
	[randomToOrdered removeAllObjects];
	[orderedToRandom removeAllObjects];
}

- (void)randomize {
	[self randomizeStartingWithObjectAtIndex:-1];
}

- (void)randomizeStartingWithObjectAtIndex:(unsigned)startIndex {
	unsigned i, count = [array count];

	// save a copy and initialize the other arrays if it's the first time randomizing
	if (![orderedArray count]) {
		[orderedArray setArray:array];

		// initialize r2o array
		[randomToOrdered removeAllObjects];
		for (i=0; i<count; ++i) {
			[randomToOrdered addObject:[NSNumber numberWithUnsignedInteger:i]];
		}

		// and the o2r array
		[orderedToRandom setArray:randomToOrdered]; // copy r2o just to make sure it has the right number of objects
	}

	// randomize
	i = count;
	if (startIndex != -1) {
		// save selected object at the end
		[array exchangeObjectAtIndex:startIndex withObjectAtIndex:--i];
		[randomToOrdered exchangeObjectAtIndex:startIndex withObjectAtIndex:i];
	}
	while (--i) {
		unsigned randomIndex = random()%(i+1);
		[array exchangeObjectAtIndex:i withObjectAtIndex:randomIndex];
		[randomToOrdered exchangeObjectAtIndex:i withObjectAtIndex:randomIndex]; // simultaneously save r2o array (it's parallel)
		[orderedToRandom replaceObjectAtIndex:[[randomToOrdered objectAtIndex:i] unsignedIntegerValue]
								   withObject:[NSNumber numberWithUnsignedInteger:i]]; // and save the inverse values to o2r array
	}
	if (startIndex != -1) {
		// put selected object at the start
		[array exchangeObjectAtIndex:0 withObjectAtIndex:count-1];
		[randomToOrdered exchangeObjectAtIndex:0 withObjectAtIndex:count-1];
		[orderedToRandom replaceObjectAtIndex:[[randomToOrdered objectAtIndex:count-1] unsignedIntegerValue]
								   withObject:[NSNumber numberWithUnsignedInteger:count-1]];
	}
	// don't forget the item at index 0!
	[orderedToRandom replaceObjectAtIndex:[[randomToOrdered objectAtIndex:0] unsignedIntegerValue]
							   withObject:[NSNumber numberWithUnsignedInteger:0]];

	// generate o2r array
//	for (randomIndex=0; randomIndex<count; ++randomIndex) {
//		i = [[randomToOrdered objectAtIndex:randomIndex] unsignedIntegerValue];
//		[orderedToRandom replaceObjectAtIndex:i withObject:[NSNumber numberWithInt:randomIndex]];
//	}
}

- (unsigned)orderedIndexOfObjectAtIndex:(unsigned)index {
	return [[randomToOrdered objectAtIndex:index] unsignedIntegerValue];

}

- (unsigned)orderedIndexOfObjectAfterIndex:(unsigned)index {
	unsigned i = [[randomToOrdered objectAtIndex:index] unsignedIntegerValue] + 1;
	if (i == [array count]) return NSNotFound;
	return [[orderedToRandom objectAtIndex:i] unsignedIntegerValue];
}

- (unsigned)orderedIndexOfObjectBeforeIndex:(unsigned)index {
	unsigned i = [[randomToOrdered objectAtIndex:index] unsignedIntegerValue];
	if (i == 0) return NSNotFound;
	return [[orderedToRandom objectAtIndex:i-1] unsignedIntegerValue];
}
@end
