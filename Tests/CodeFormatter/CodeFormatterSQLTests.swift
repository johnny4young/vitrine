import Testing

@testable import Vitrine

@Suite("Code formatter — SQL")
struct CodeFormatterSQLTests {
    // MARK: - formatSQL

    /// A compact query gets a vertical select list and clause hierarchy while preserving
    /// the user's keyword casing and quoted value bytes.
    @Test func formatSQLExpandsSelectListsJoinsAndPredicates() {
        let input =
            "SELECT u.id,u.email,COUNT(o.id) AS order_count FROM users u LEFT JOIN orders o ON o.user_id=u.id WHERE u.active=TRUE AND u.email<>'from@example.com' GROUP BY u.id,u.email ORDER BY order_count DESC;"
        let expected = """
            SELECT
              u.id,
              u.email,
              COUNT(o.id) AS order_count
            FROM users u
            LEFT JOIN orders o
              ON o.user_id = u.id
            WHERE u.active = TRUE
              AND u.email <> 'from@example.com'
            GROUP BY u.id, u.email
            ORDER BY order_count DESC;
            """
        #expect(CodeFormatter.formatSQL(input) == expected)
    }

    /// Vendor quoting and parameter syntaxes are opaque lexer tokens: formatting can
    /// add layout around them but never split or normalize their contents.
    @Test func formatSQLPreservesQuotedValuesIdentifiersCommentsAndParameters() {
        let input =
            "UPDATE [accounts] SET display_name='O''Reilly',note=$tag$from,where$tag$ /* keep */ WHERE id=:id AND tenant_id=$1;"
        let expected = """
            UPDATE [accounts]
            SET
              display_name = 'O''Reilly',
              note = $tag$from,where$tag$ /* keep */
            WHERE id = :id
              AND tenant_id = $1;
            """
        #expect(CodeFormatter.formatSQL(input) == expected)
    }

    /// Numeric exponents, prefixed strings, vendor operators, system variables, casts,
    /// and positional/named parameters stay atomic instead of being split by spacing.
    @Test func formatSQLKeepsDialectTokensAtomic() {
        let input =
            #"SELECT 1e-3,N'O''Reilly',data@>'{"a":1}',payload??'key',@@ROWCOUNT FROM metrics WHERE id=@id AND version::int>=?;"#
        let expected = """
            SELECT
              1e-3,
              N'O''Reilly',
              data @> '{"a":1}',
              payload ?? 'key',
              @@ROWCOUNT
            FROM metrics
            WHERE id = @id
              AND version :: int >= ?;
            """
        #expect(CodeFormatter.formatSQL(input) == expected)
    }

    /// Formatting output is stable across repeated Format Code commands.
    @Test func formatSQLIsIdempotent() throws {
        let formatted = try #require(CodeFormatter.formatSQL("SELECT id,name FROM users;"))
        #expect(CodeFormatter.formatSQL(formatted) == formatted)
    }

    /// Uncertain input is rejected rather than partially reshaped.
    @Test func formatSQLRejectsNonStatementsAndUnbalancedSyntax() {
        #expect(CodeFormatter.formatSQL("plain prose") == nil)
        #expect(CodeFormatter.formatSQL("SELECT 'unterminated") == nil)
        #expect(CodeFormatter.formatSQL("SELECT (id FROM users") == nil)
        #expect(CodeFormatter.formatSQL("SELECT id FROM users /* open") == nil)
    }
}
