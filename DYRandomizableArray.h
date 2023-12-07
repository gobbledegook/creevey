// A pseudo-mutableArray class.
// You can randomize it and it will let you pick out indices corresponding to
// the original order when desired.

#import <Foundation/Foundation.h>

@interface DYRandomizableArray<T> : NSObject

// array stuff
@property (readonly) NSUInteger count;
- (T)objectAtIndex:(NSUInteger)index;
- (T)objectAtIndexedSubscript:(NSUInteger)index; // support custom subscript, e.g. array[index]
- (NSUInteger)indexOfObject:(T)anObject;
- (NSUInteger)indexOfObject:(T)anObject usingComparator:(NSComparator)cmp;
- (NSUInteger)indexOfObject:(T)anObject usingComparator:(NSComparator)cmp insertIndex:(NSUInteger *)insertIdx;

// mutable array stuff
- (void)setArray:(NSArray<T> *)otherArray;
- (void)removeAllObjects;
- (void)removeObjectAtIndex:(NSUInteger)index;
- (void)removeObject:(T)anObject;
- (NSUInteger)insertObject:(T)anObject usingComparator:(NSComparator)cmp atIndex:(NSUInteger)index; // index is ignored if not in random mode. Returns the actual insert index
- (NSUInteger)insertObject:(T)anObject usingOrderedIndex:(NSUInteger)insertIdx atIndex:(NSUInteger)index; // this should only ever be called with a valid oIdx!

// randomizable stuff
- (void)randomize;
- (void)randomizeStartingWithObjectAtIndex:(NSUInteger)startIndex;
- (void)derandomize;

- (NSUInteger)orderedIndexOfObjectAtIndex:(NSUInteger)index;

// these return NSNotFound if the index would be out of bounds
- (NSUInteger)orderedIndexOfObjectAfterIndex:(NSUInteger)index;
- (NSUInteger)orderedIndexOfObjectBeforeIndex:(NSUInteger)index;
@end
