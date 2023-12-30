#import "DYRandomizableArray.h"
#import "NSMutableArray+DYMovable.h"

@implementation DYRandomizableArray
{
	NSMutableArray *array, // working array
			*orderedArray; // saved copy, only populated when array is randomized
	NSMutableArray<NSNumber *> *randomToOrdered,  // parallel array to the working array
							   *orderedToRandom;  // inversion of randomToOrdered
}

- (instancetype)init
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

// array stuff
- (NSUInteger)count {
	return array.count;
}

- (id)objectAtIndex:(NSUInteger)index {
	return array[index];
}

- (id)objectAtIndexedSubscript:(NSUInteger)index {
	return array[index];
}

- (NSUInteger)indexOfObject:(id)anObject {
	return [array indexOfObject:anObject];
}

- (NSUInteger)indexOfObject:(id)anObject usingComparator:(NSComparator)cmp {
	NSArray *a = orderedArray.count ? orderedArray : array;
	NSUInteger idx = [a indexOfObject:anObject inSortedRange:NSMakeRange(0, array.count) options:0 usingComparator:cmp];
	return orderedArray.count ? orderedToRandom[idx].unsignedIntegerValue : idx;
}

- (NSUInteger)indexOfObject:(id)anObject usingComparator:(NSComparator)cmp insertIndex:(NSUInteger *)insertIdx {
	NSUInteger count = array.count;
	NSArray *a = orderedArray.count ? orderedArray : array;
	NSUInteger idx = [a indexOfObject:anObject inSortedRange:NSMakeRange(0, count) options:NSBinarySearchingInsertionIndex usingComparator:cmp];
	if (idx < count && [a[idx] isEqual:anObject])
		return orderedArray.count ? orderedToRandom[idx].unsignedIntegerValue : idx;
	*insertIdx = idx;
	return NSNotFound;
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
	if (orderedArray.count) {
		// remove the item from orderedArray
		NSUInteger orderedIndex = randomToOrdered[index].unsignedIntegerValue;
		[orderedArray removeObjectAtIndex:orderedIndex];

		// adjust r2o
		NSUInteger i, count = array.count;
		for (i=0; i<count; ++i) {
			NSUInteger n = (randomToOrdered[i]).unsignedIntegerValue;
			if (n > orderedIndex)
				randomToOrdered[i] = @(n-1);
		}
		[randomToOrdered removeObjectAtIndex:index];

		// adjust o2r
		for (i=0; i<count; ++i) {
			NSUInteger n = (orderedToRandom[i]).unsignedIntegerValue;
			if (n > index)
				orderedToRandom[i] = @(n-1);
		}
		[orderedToRandom removeObjectAtIndex:orderedIndex];
	}
	[array removeObjectAtIndex:index];
}

- (NSUInteger)insertObject:(id)anObject usingComparator:(NSComparator)cmp atIndex:(NSUInteger)index {
	NSUInteger count = array.count;
	if (index > count) index = count;
	NSMutableArray *a = orderedArray.count ? orderedArray : array;
	NSUInteger oIdx = [a indexOfObject:anObject inSortedRange:NSMakeRange(0, count) options:NSBinarySearchingInsertionIndex usingComparator:cmp];
	if (oIdx < count && [a[oIdx] isEqual:anObject])
		return orderedArray.count ? orderedToRandom[oIdx].unsignedIntegerValue : oIdx;
	return [self insertObject:anObject usingOrderedIndex:oIdx atIndex:index];
}

- (NSUInteger)insertObject:(id)anObject usingOrderedIndex:(NSUInteger)oIdx atIndex:(NSUInteger)index {
	NSUInteger count = array.count;
	if (orderedArray.count) {
		[orderedArray insertObject:anObject atIndex:oIdx];
		NSUInteger i;
		for (i=0; i<count; ++i) {
			NSUInteger n = (randomToOrdered[i]).unsignedIntegerValue;
			if (n >= oIdx)
				randomToOrdered[i] = @(n+1);
		}
		[randomToOrdered insertObject:@(oIdx) atIndex:index];
		for (i=0; i<count; ++i) {
			NSUInteger n = (orderedToRandom[i]).unsignedIntegerValue;
			if (n >= index)
				orderedToRandom[i] = @(n+1);
		}
		[orderedToRandom insertObject:@(index) atIndex:oIdx];
	} else {
		index = oIdx;
	}
	[array insertObject:anObject atIndex:index];
	return index;
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
	NSUInteger i, count = array.count;

	// save a copy and initialize the other arrays if it's the first time randomizing
	if (!orderedArray.count) {
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
		NSUInteger randomIndex = arc4random_uniform((uint32_t)i+1);
		[array exchangeObjectAtIndex:i withObjectAtIndex:randomIndex];
		[randomToOrdered exchangeObjectAtIndex:i withObjectAtIndex:randomIndex]; // simultaneously save r2o array (it's parallel)
		orderedToRandom[(randomToOrdered[i]).unsignedIntegerValue] = @(i); // and save the inverse values to o2r array
	}
	if (startIndex != NSNotFound) {
		// put selected object at the start
		[array exchangeObjectAtIndex:0 withObjectAtIndex:count-1];
		[randomToOrdered exchangeObjectAtIndex:0 withObjectAtIndex:count-1];
		orderedToRandom[(randomToOrdered[count-1]).unsignedIntegerValue] = @(count-1);
	}
	// don't forget the item at index 0!
	orderedToRandom[(randomToOrdered[0]).unsignedIntegerValue] = @0U;
}

- (NSUInteger)orderedIndexFromIndex:(NSUInteger)index {
	return randomToOrdered[index].unsignedIntegerValue;
}

- (NSUInteger)orderedIndexOfObjectAfterIndex:(NSUInteger)index {
	NSUInteger i = randomToOrdered[index].unsignedIntegerValue + 1;
	if (i == array.count) return NSNotFound;
	return (orderedToRandom[i]).unsignedIntegerValue;
}

- (NSUInteger)orderedIndexOfObjectBeforeIndex:(NSUInteger)index {
	NSUInteger i = randomToOrdered[index].unsignedIntegerValue;
	if (i == 0) return NSNotFound;
	return (orderedToRandom[i-1]).unsignedIntegerValue;
}

- (void)changeBase:(NSString *)basePath toPath:(NSString *)newBase {
	if (orderedArray.count)
		[orderedArray changeBase:basePath toPath:newBase];
	[array changeBase:basePath toPath:newBase];
}
@end
