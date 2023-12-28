//
//  DYFileWatcher.h
//  Phoenix Slides
//
//  Created by 祥 on 12/6/23.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@protocol DYFileWatcherDelegate <NSObject>
- (void)watcherFiles:(NSArray *)files;
@end

@interface DYFileWatcher : NSObject
@property (nonatomic) BOOL wantsSubfolders;
- (instancetype)initWithDelegate:(id <DYFileWatcherDelegate>)delegate NS_DESIGNATED_INITIALIZER;
- (void)watchDirectory:(NSString *)thePath;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
