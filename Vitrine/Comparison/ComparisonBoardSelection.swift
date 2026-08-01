import Foundation

/// Ordered, session-only selection state shared by the Recents workflow and its tests.
struct ComparisonBoardSelection: Equatable {
    private(set) var ids: [Capture.ID] = []

    var count: Int { ids.count }

    var canCreateBoard: Bool {
        ComparisonBoard.itemCountRange.contains(count)
    }

    func index(of id: Capture.ID) -> Int? {
        ids.firstIndex(of: id)
    }

    mutating func toggle(_ id: Capture.ID) {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else if ids.count < ComparisonBoard.itemCountRange.upperBound {
            ids.append(id)
        }
    }

    mutating func reset() {
        ids.removeAll(keepingCapacity: false)
    }

    func resolved(in captures: [Capture]) -> [Capture] {
        ids.compactMap { id in captures.first(where: { $0.id == id }) }
    }
}
