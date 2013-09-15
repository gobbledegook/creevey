//
//  FinderCompare.m
//  Created by Pablo Gomez Basanta on 23/7/05.
//
//  Based on:
//  http://developer.apple.com/qa/qa2004/qa1159.html
//

#import <Foundation/NSString.h>

@interface NSString (FinderCompare)

- (NSComparisonResult)finderCompare:(NSString *)aString;

@end