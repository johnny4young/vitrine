import SwiftUI

extension View {
    /// Assigns an identifier to a container without letting SwiftUI propagate that
    /// identifier down to the nearest descendant accessibility elements.
    ///
    /// On a plain non-element container, `.accessibilityIdentifier(_:)` can override
    /// child identifiers such as button or picker ids. Make the view an accessibility
    /// container first whenever the parent and its children both need stable ids.
    func accessibilityContainerIdentifier(_ identifier: String) -> some View {
        accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
    }
}
