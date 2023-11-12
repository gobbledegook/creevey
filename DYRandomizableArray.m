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
- (NSUInteger)count {
	return [array count];
}

- (id)objectAtIndex:(NSUInteger)index {
	return array[index];
}

- (NSUInteger)indexOfObject:(id)anObject {
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

- (void)removeObjectAtIndex:(NSUInteger)index {
	if ([orderedArray count]) {
		// remove the item from orderedArray
		NSUInteger orderedIndex = [self orderedIndexOfObjectAtIndex:index];
		[orderedArray removeObjectAtIndex:orderedIndex];

		// adjust r2o
		NSUInteger i, count = [array count];
		for (i=0; i<count; ++i) {
			NSUInteger n = [randomToOrdered[i] unsignedIntegerValue];
			if (n > orderedIndex)
				randomToOrdered[i] = @(n-1);
		}
		[randomToOrdered removeObjectAtIndex:index];

		// adjust o2r
		for (i=0; i<count; ++i) {
			NSUInteger n = [orderedToRandom[i] unsignedIntegerValue];
			if (n > index)
				orderedToRandom[i] = @(n-1);
		}
		[orderedToRandom removeObjectAtIndex:orderedIndex];
	}
	[array removeObjectAtIndex:index];
}

- (void)removeObject:(id)anObject {
	NSUInteger i = [array indexOfObject:anObject];
	if (i == NSNotFound) return;
	[self removeObjectAtIndex:i];
}

- (void)insertObject:(id)anObject withOrderedIndex:(NSUInteger)oIdx atIndex:(NSUInteger)index {
	NSUInteger count = array.count;
	if (index > count) index = count;
	if (oIdx > count) oIdx = count;
	if ([orderedArray count]) {
		[orderedArray insertObject:anObject atIndex:oIdx];
		NSUInteger i;
		for (i=0; i<count; ++i) {
			NSUInteger n = [randomToOrdered[i] unsignedIntegerValue];
			if (n > oIdx)
				randomToOrdered[i] = @(n+1);
		}
		[randomToOrdered insertObject:@(oIdx) atIndex:index];
		for (i=0; i<count; ++i) {
			NSUInteger n = [orderedToRandom[i] unsignedIntegerValue];
			if (n > index)
				orderedToRandom[i] = @(n+1);
		}
		[orderedToRandom insertObject:@(index) atIndex:oIdx];
	} else {
		index = oIdx;
	}
	[array insertObject:anObject atIndex:index];
}

// randomizable stuff
- (void)derandomize {
	[array setArray:orderedArray];
	[orderedArray removeAllObjects];
	[randomToOrdered removeAllObjects];
	[orderedToRandom removeAllObjects];
}

- (void)randomize {
	[self randomizeStartingWithObjectAtIndex:NSNotFound];
}

- (void)randomizeStartingWithObjectAtIndex:(NSUInteger)startIndex {
	NSUInteger i, count = [array count];

	// save a copy and initialize the other arrays if it's the first time randomizing
	if (![orderedArray count]) {
		[orderedArray setArray:array];

		// initialize r2o array
		[randomToOrdered removeAllObjects];
		for (i=0; i<count; ++i) {
			[randomToOrdered addObject:@(i)];
		}

		// and the o2r array
		[orderedToRandom setArray:randomToOrdered]; // copy r2o just to make sure it has the right number of objects
	}

	// randomize
	i = count;
	if (startIndex != NSNotFound) {
		// save selected object at the end
		[array exchangeObjectAtIndex:startIndex withObjectAtIndex:--i];
		[randomToOrdered exchangeObjectAtIndex:startIndex withObjectAtIndex:i];
	}
	while (--i) {
		NSUInteger randomIndex = arc4random_uniform(i+1);
		[array exchangeObjectAtIndex:i withObjectAtIndex:randomIndex];
		[randomToOrdered exchangeObjectAtIndex:i withObjectAtIndex:randomIndex]; // simultaneously save r2o array (it's parallel)
		orderedToRandom[[randomToOrdered[i] unsignedIntegerValue]] = @(i); // and save the inverse values to o2r array
	}
	if (startIndex != NSNotFound) {
		// put selected object at the start
		[array exchangeObjectAtIndex:0 withObjectAtIndex:count-1];
		[randomToOrdered exchangeObjectAtIndex:0 withObjectAtIndex:count-1];
		orderedToRandom[[randomToOrdered[count-1] unsignedIntegerValue]] = @(count-1);
	}
	// don't forget the item at index 0!
	orderedToRandom[[randomToOrdered[0] unsignedIntegerValue]] = @0U;
}

- (NSUInteger)orderedIndexOfObjectAtIndex:(NSUInteger)index {
	return [randomToOrdered[index] unsignedIntegerValue];

}

- (NSUInteger)orderedIndexOfObjectAfterIndex:(NSUInteger)index {
	NSUInteger i = [randomToOrdered[index] unsignedIntegerValue] + 1;
	if (i == [array count]) return NSNotFound;
	return [orderedToRandom[i] unsignedIntegerValue];
}

- (NSUInteger)orderedIndexOfObjectBeforeIndex:(NSUInteger)index {
	NSUInteger i = [randomToOrdered[index] unsignedIntegerValue];
	if (i == 0) return NSNotFound;
	return [orderedToRandom[i-1] unsignedIntegerValue];
}
@end
