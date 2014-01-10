//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  DYVersChecker.h
//  creevey
//  Created by d on 2005.07.29.

#import <Cocoa/Cocoa.h>

// this class releases itself when done

@interface DYVersChecker : NSObject {
	BOOL notify;
	int responseCode;
	NSMutableData *receivedData;
}
- initWithNotify:(BOOL)newNotify; // returns nil if can't open connection

@end
