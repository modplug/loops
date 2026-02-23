#import "ObjCHelpers.h"

BOOL ObjCTryCatch(NS_NOESCAPE void (^block)(void),
                   NSError * _Nullable __autoreleasing * _Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"%@: %@",
                              exception.name, exception.reason ?: @"(no reason)"];
            *error = [NSError errorWithDomain:@"ObjCException"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: desc}];
        }
        return NO;
    }
}
