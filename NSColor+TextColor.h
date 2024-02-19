@import Cocoa;
@interface NSColor (DYTextColor)
- (NSColor *)bestTextColor; // don't depend on this working if color has alpha
@end
