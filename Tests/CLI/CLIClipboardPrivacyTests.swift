import Testing

@testable import VitrineCLICore

struct CLIClipboardPrivacyTests {
    @Test(arguments: ["render", "terminal-capture"])
    func confidentialityIsAnExplicitCopyOption(_ command: String) throws {
        let defaults = try CLIArguments.parse([command, "input.txt", "--copy"])
        #expect(defaults.concealClipboard == false)
        let privateCopy = try CLIArguments.parse([
            command, "input.txt", "--copy", "--conceal-clipboard",
        ])
        #expect(privateCopy.copyToClipboard)
        #expect(privateCopy.concealClipboard)
    }

    @Test func confidentialityWithoutCopyIsRejected() {
        #expect(throws: CLIError.incompatibleOptions("--conceal-clipboard requires --copy.")) {
            try CLIArguments.parse([
                "render", "input.swift", "--out", "output.png", "--conceal-clipboard",
            ])
        }
    }
}
