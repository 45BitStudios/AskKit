#import "AskContactsChangeHistory.h"

#if __has_include(<Contacts/Contacts.h>)

@implementation AskContactsChangeHistoryFetch

+ (CNFetchResult<NSEnumerator<CNChangeHistoryEvent *> *> *)
    resultForStore:(CNContactStore *)store
    request:(CNChangeHistoryFetchRequest *)request
    error:(NSError *__autoreleasing  _Nullable *)error
{
    return [store enumeratorForChangeHistoryFetchRequest:request error:error];
}

@end

#endif
