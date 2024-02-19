#import "NSColor+TextColor.h"
@implementation NSColor (DYTextColor)
#define PVAL(x) (x <= 0.03982 ? x/12.92 : pow((x+0.055)/1.055,2.4))
- (NSColor *)bestTextColor {
	NSColor *rgb = [self colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
	if (rgb) {
		CGFloat r,g,b;
		[rgb getRed:&r green:&g blue:&b alpha:NULL];
		CGFloat luminance = PVAL(r)*0.2126 + PVAL(g)*0.7152+ PVAL(b)*0.0722;
		return luminance > 0.5 ? NSColor.blackColor : NSColor.whiteColor;
	}
	return NSColor.controlTextColor;
}
@end
