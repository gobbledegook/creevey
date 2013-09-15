//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

//  DYCarbonGoodies.h
//  creevey
//
//  Created by d on 2005.04.03.

#import <Cocoa/Cocoa.h>

// returns path if it's not an alias, or if not resolvable
NSString *ResolveAliasToPath(NSString *path);

// returns nil on error
NSString *AliasToPath(AliasHandle aHndl);

// can reveal multiple items, unlike NSWorkspace
void RevealItemsInFinder(NSArray *a);

// check if a files invisible flag is set
BOOL FileIsInvisible(NSString *path);

// use AppleEvent to set desktop pic
OSErr SetDesktopPicture(NSString *picturePath,SInt32 pIndex);
