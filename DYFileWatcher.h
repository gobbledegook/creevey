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
- (void)watcherRootChanged:(NSURL *)fileRef;
@end

@interface DYFileWatcher : NSObject
@property (nonatomic) BOOL wantsSubfolders;
@property (nonatomic, readonly) NSString *path;
- (instancetype)initWithDelegate:(id <DYFileWatcherDelegate>)delegate NS_DESIGNATED_INITIALIZER;
- (void)watchDirectory:(NSString *)thePath;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
