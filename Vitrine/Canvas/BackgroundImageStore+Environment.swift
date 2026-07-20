import SwiftUI

/// SwiftUI environment injection for the image stores, kept in the UI layer so
/// `BackgroundImageStore` itself stays free of the SwiftUI view layer (VitrineCore
/// prerequisite). The store is a plain value type over the app container; these entries
/// let the render path resolve it from `@Environment` and let tests/previews inject an
/// isolated store.
extension EnvironmentValues {
    /// The store used to resolve image backgrounds.
    ///
    /// Defaults to the real app-container store; injected with an isolated store in tests
    /// and previews so the render path can resolve fixture images without touching the
    /// user's container.
    @Entry var backgroundImageStore: BackgroundImageStore = .container

    /// The store used to resolve the beautified **foreground** image. Same default-real,
    /// inject-in-tests contract as `backgroundImageStore`, rooted at a separate directory.
    @Entry var foregroundImageStore: BackgroundImageStore = .foregroundContainer
}
