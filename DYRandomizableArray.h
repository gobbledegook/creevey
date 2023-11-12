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
- (NSUInteger)count;
- (id)objectAtIndex:(NSUInteger)index;
- (NSUInteger)indexOfObject:(id)anObject;

// mutable array stuff
- (void)setArray:(NSArray *)otherArray;
- (void)removeAllObjects;
- (void)removeObjectAtIndex:(NSUInteger)index;
- (void)removeObject:(id)anObject;
- (void)insertObject:(id)anObject withOrderedIndex:(NSUInteger)oIdx atIndex:(NSUInteger)index;

// randomizable stuff
- (void)randomize;
- (void)randomizeStartingWithObjectAtIndex:(NSUInteger)startIndex;
- (void)derandomize;

- (NSUInteger)orderedIndexOfObjectAtIndex:(NSUInteger)index;

// these return NSNotFound if the index would be out of bounds
- (NSUInteger)orderedIndexOfObjectAfterIndex:(NSUInteger)index;
- (NSUInteger)orderedIndexOfObjectBeforeIndex:(NSUInteger)index;
@end
