import Foundation

/// Best-effort content/language detection from clipboard text (CS-004).
///
/// `detect(_:)` uses additive weighted keyword scoring and returns the highest
/// scoring language (or `.plaintext` when there is no signal), which is more
/// robust than ordered `if/else` for overlapping tokens (e.g. Swift vs Go `func`).
enum LanguageDetector {
    /// Returns `true` when the text looks like a single http(s) URL.
    static func isURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isNewline),
            let url = URL(string: trimmed),
            let scheme = url.scheme
        else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    /// Detects the most likely language via weighted keyword scoring.
    static func detect(_ raw: String) -> Language {
        let code = raw.lowercased()
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .plaintext
        }

        var scores: [Language: Int] = [:]
        func add(_ language: Language, _ signals: [(needle: String, weight: Int)]) {
            for signal in signals where code.contains(signal.needle) {
                scores[language, default: 0] += signal.weight
            }
        }

        add(
            .swift,
            [
                ("import swiftui", 3), ("import foundation", 3), ("@state", 3),
                ("guard let", 2), ("-> some view", 3), ("func ", 2), ("let ", 1), ("var ", 1),
            ])
        add(.go, [("package main", 3), ("func main(", 3), ("fmt.", 2), (":=", 2), ("import (", 2)])
        add(
            .python,
            [
                ("def ", 3), ("elif ", 2), ("import numpy", 2), ("__init__", 3),
                ("print(", 1), ("self.", 1),
            ])
        add(
            .javascript,
            [
                ("function ", 2), ("const ", 1), ("=>", 1), ("console.log", 2),
                ("require(", 2), ("document.", 2),
            ])
        add(
            .typescript,
            [
                ("interface ", 3), (": string", 2), (": number", 2),
                (": boolean", 2), ("export type", 3), ("implements ", 2),
            ])
        add(
            .sql,
            [
                ("select ", 2), ("insert into", 3), ("update ", 2), ("delete from", 3),
                (" where ", 2), (" join ", 2),
            ])
        add(.html, [("<!doctype", 3), ("<html", 3), ("</div>", 2), ("<body", 2), ("<span", 1)])
        add(
            .bash,
            [
                ("#!/bin/bash", 3), ("#!/bin/sh", 3), ("#!/usr/bin/env", 2), ("echo ", 1),
                ("fi\n", 1),
            ])

        // TypeScript subsumes the generic JavaScript signals.
        if let typescript = scores[.typescript], typescript > 0 {
            scores[.javascript] = (scores[.javascript] ?? 0) - 1
        }

        // Deterministic argmax: highest score wins, ties broken by raw value.
        let ranked = scores.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue
        }
        guard let best = ranked.first, best.value > 0 else { return .plaintext }
        return best.key
    }
}
