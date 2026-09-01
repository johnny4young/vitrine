import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("CLI argument schema")
struct CLIArgumentSchemaTests {
    @Test func everyOptionIdentityHasOneDefinitionAndEveryTokenIsUnique() {
        #expect(CLIArgumentSchema.options.count == CLIOptionID.allCases.count)
        #expect(Set(CLIArgumentSchema.options.map(\.id)) == Set(CLIOptionID.allCases))

        let names = CLIArgumentSchema.options.flatMap(\.names)
        #expect(names.count == 114)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { $0.hasPrefix("-") })
        #expect(
            CLIArgumentSchema.options.allSatisfy {
                $0.canonicalFlag.hasPrefix("--") && !$0.synopsis.isEmpty
                    && !$0.description.isEmpty
            })
    }

    @Test func commandSchemaCoversEveryParserOwnedCommand() {
        #expect(CLIArgumentSchema.commands.map(\.command) == CLIOptions.Command.allCases)
        for command in CLIOptions.Command.allCases {
            #expect(CLIArgumentSchema.command(named: command.rawValue) == command)
        }
        #expect(CLIArgumentSchema.command(named: "unknown") == nil)
    }

    @Test func legacyAliasesRemainMappedToTheirStableOptions() {
        let expected: [String: CLIOptionID] = [
            "-o": .out,
            "-q": .quiet,
            "-e": .edit,
            "-h": .help,
            "--lang": .language,
            "--wrap": .wrapColumns,
            "--tidy": .formatCode,
            "--no-clobber": .noOverwrite,
            "--stdin-filename": .stdinName,
            "--show-language-badge": .languageBadge,
        ]
        for (alias, id) in expected {
            #expect(CLIArgumentSchema.option(named: alias)?.id == id)
        }
    }

    @Test func helpPlaceholderAndParserArityCannotDrift() {
        for definition in CLIArgumentSchema.options {
            switch definition.arity {
            case .flag:
                #expect(!definition.synopsis.contains("<"))
            case .value:
                #expect(definition.synopsis.contains("<"))
            }
        }
    }

    @Test func everyValueAliasUsesTheSchemaMissingValueContract() {
        for definition in CLIArgumentSchema.options {
            guard case .value = definition.arity else { continue }
            for name in definition.names {
                #expect(throws: CLIError.missingValue(flag: name)) {
                    try CLIArguments.parse([
                        "render", "input.swift", "--out", "output.png", name,
                    ])
                }
            }
        }
    }

    @Test func terminalCaptureAllowlistComesOnlyFromTheSchema() {
        let allowed = Set(
            CLIArgumentSchema.options
                .filter(\.terminalCaptureAllowed)
                .flatMap(\.names))
        #expect(
            allowed
                == [
                    "--help", "-h", "--copy", "--edit", "-e", "--terminal-width",
                    "--filename", "--title",
                ])
    }

    @Test func generatedHelpCoversEveryCanonicalOptionAndStaysBounded() {
        let help = CLIUsage.text
        let normalizedHelp = Self.normalizedWhitespace(help)
        for definition in CLIArgumentSchema.options {
            #expect(help.contains(definition.synopsis))
            #expect(normalizedHelp.contains(Self.normalizedWhitespace(definition.description)))
        }
        let optionLines = CLIArgumentSchema.helpText.split(
            separator: "\n", omittingEmptySubsequences: false)
        #expect(optionLines.allSatisfy { $0.count <= 80 })
    }

    @Test func aliasesResolveToOneStableIdentity() throws {
        for definition in CLIArgumentSchema.options {
            for name in definition.names {
                #expect(CLIArgumentSchema.option(named: name)?.id == definition.id)
            }
        }
        #expect(CLIArgumentSchema.option(named: "--not-real") == nil)
    }
    private static func normalizedWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

}
