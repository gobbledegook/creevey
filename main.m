//
//  main.m
//  creevey
//
//  Created by d on Fri Mar 18 2005.
//  Copyright (c) 2005 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

int main(int argc, const char *argv[])
{
	if (floor(NSAppKitVersionNumber) <= 1187) {
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]; 
		NSApplicationLoad();
		NSRunAlertPanel(@"Incompatible System Version", 
						@"This program requires OS X 10.9 (Mavericks) or later.",
						nil, nil, nil);
		[pool release];
		return 0;
	}
    return NSApplicationMain(argc, argv);
}
