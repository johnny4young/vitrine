import WebKit

extension WebContentRuleListStoreSource {
    func makeStore() -> WKContentRuleListStore? {
        makeStore(
            applicationDefault: { WKContentRuleListStore.default() },
            directory: { WKContentRuleListStore(url: $0) })
    }
}
