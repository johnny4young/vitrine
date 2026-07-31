/// Removes Swift line-comment text so source-boundary tests inspect executable
/// references rather than documentation.
func sourceCodeWithoutLineComments(_ source: String) -> String {
    source.split(separator: "\n", omittingEmptySubsequences: false)
        .map { line in
            guard let commentStart = line.range(of: "//") else {
                return String(line)
            }
            return String(line[..<commentStart.lowerBound])
        }
        .joined(separator: "\n")
}
