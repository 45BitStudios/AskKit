#import <Foundation/Foundation.h>

// Apple TV has no Contacts framework, so the target builds empty there.
#if __has_include(<Contacts/Contacts.h>)
#import <Contacts/Contacts.h>

NS_ASSUME_NONNULL_BEGIN

/// ObjC entry point for change history. The Contacts enumerator is unavailable in Swift.
@interface AskContactsChangeHistoryFetch : NSObject

+ (nullable CNFetchResult<NSEnumerator<CNChangeHistoryEvent *> *> *)
    resultForStore:(CNContactStore *)store
    request:(CNChangeHistoryFetchRequest *)request
    error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
