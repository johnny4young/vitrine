struct ReleaseNote {
    let title = "A clear first image"
    let checks = ["render", "review", "share"]

    var summary: String {
        "\(title): \(checks.count) checks"
    }
}
