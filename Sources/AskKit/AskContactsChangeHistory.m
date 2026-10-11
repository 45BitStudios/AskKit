#import "AskContactsChangeHistory.h"

@implementation AskContactsChangeHistoryFetch

+ (CNFetchResult<NSEnumerator<CNChangeHistoryEvent *> *> *)
    resultForStore:(CNContactStore *)store
    request:(CNChangeHistoryFetchRequest *)request
    error:(NSError *__autoreleasing  _Nullable *)error
{
    return [store enumeratorForChangeHistoryFetchRequest:request error:error];
}

@end
