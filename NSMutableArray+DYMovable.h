@import Foundation;
@interface NSMutableArray (DYMovable)
- (void)moveObjectAtIndex:(NSUInteger)fromIdx toIndex:(NSUInteger)toIdx;
- (NSUInteger)updateIndexOfObject:(id)obj usingComparator:(NSComparator)cmp oldIndex:(NSUInteger *)outIdx;
@end
