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

// mutable array stuff
- (void)setArray:(NSArray<T> *)otherArray;
- (void)removeAllObjects;
- (void)removeObjectAtIndex:(NSUInteger)index;
- (void)removeObject:(T)anObject;
- (void)insertObject:(T)anObject withOrderedIndex:(NSUInteger)oIdx atIndex:(NSUInteger)index;

// randomizable stuff
- (void)randomize;
- (void)randomizeStartingWithObjectAtIndex:(NSUInteger)startIndex;
- (void)derandomize;

- (NSUInteger)orderedIndexOfObjectAtIndex:(NSUInteger)index;

// these return NSNotFound if the index would be out of bounds
- (NSUInteger)orderedIndexOfObjectAfterIndex:(NSUInteger)index;
- (NSUInteger)orderedIndexOfObjectBeforeIndex:(NSUInteger)index;
@end
