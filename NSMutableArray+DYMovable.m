#import "NSMutableArray+DYMovable.h"

@implementation NSMutableArray (DYMovable)
- (void)moveObjectAtIndex:(NSUInteger)fromIdx toIndex:(NSUInteger)toIdx {
	id obj = [self objectAtIndex:fromIdx];
	[self removeObjectAtIndex:fromIdx];
	[self insertObject:obj atIndex:toIdx];
}
- (NSUInteger)updateIndexOfObject:(id)obj usingComparator:(NSComparator)cmp oldIndex:(NSUInteger *)outIdx {
	NSUInteger idx = [self indexOfObject:obj]; // linear search to find object with outdated index
	if (idx == NSNotFound) return NSNotFound;
	if (outIdx) *outIdx = idx;
	[self removeObjectAtIndex:idx];
	idx = [self indexOfObject:obj inSortedRange:(NSRange){0,self.count} options:NSBinarySearchingInsertionIndex usingComparator:cmp];
	[self insertObject:obj atIndex:idx];
	return idx;
}

- (void)changeBase:(NSString *)basePath toPath:(NSString *)newBase {
	NSUInteger i, n = self.count;
	NSRange r = {0, basePath.length};
	for (i=0; i<n; ++i) {
		NSString *s = self[i];
		self[i] = [s stringByReplacingCharactersInRange:r withString:newBase];
	}
}
@end
