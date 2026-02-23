#import <Foundation/Foundation.h>

/// Executes a block and catches any ObjC exception.
/// Returns YES on success, NO if an exception was thrown.
/// If an exception occurs and `error` is non-NULL, it receives an NSError
/// wrapping the exception description.
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL ObjCTryCatch(NS_NOESCAPE void (^block)(void),
                                     NSError * _Nullable __autoreleasing * _Nullable error);
NS_ASSUME_NONNULL_END
