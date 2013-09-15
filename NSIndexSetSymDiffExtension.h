//
//  NSIndexSetSymDiffExtension.h
//  creevey
//
//  Created by d on 2005.06.13.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface NSMutableIndexSet (SymDiffExtension)

- (void)symmetricDifference:(NSIndexSet *)setB;
@end
