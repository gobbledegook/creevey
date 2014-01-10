// A pseudo-mutableArray class.
// You can randomize it and it will let you pick out indices corresponding to
// the original order when desired.

#import <Foundation/Foundation.h>

@interface DYRandomizableArray : NSObject {
	NSMutableArray *array, // working array
		*orderedArray,     // saved copy, only populated when array is randomized
		*randomToOrdered,  // parallel array to the working array
		*orderedToRandom;  // inversion of randomToOrdered
}

// array stuff
- (unsigned)count;
- (id)objectAtIndex:(unsigned)index;
- (unsigned)indexOfObject:(id)anObject;

// mutable array stuff
- (void)setArray:(NSArray *)otherArray;
- (void)removeAllObjects;
- (void)removeObjectAtIndex:(unsigned)index;
- (void)removeObject:(id)anObject;

// randomizable stuff
- (void)randomize;
- (void)randomizeStartingWithObjectAtIndex:(unsigned)startIndex;
- (void)derandomize;

- (unsigned)orderedIndexOfObjectAtIndex:(unsigned)index;

// these return NSNotFound if the index would be out of bounds
- (unsigned)orderedIndexOfObjectAfterIndex:(unsigned)index;
- (unsigned)orderedIndexOfObjectBeforeIndex:(unsigned)index;
@end
