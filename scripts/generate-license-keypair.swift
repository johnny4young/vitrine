#!/usr/bin/env swift
import CryptoKit
import Foundation

// Generates the Ed25519 keypair for the direct-download PRO license signing (CS-090,
// Architecture B). Run once, then follow docs/ACTIVATION.md:
//
//   swift scripts/generate-license-keypair.swift
//
//   • PUBLIC  → paste into LicenseVerifier.embedded (Vitrine/Pro/LicenseKey.swift). Not secret.
//   • PRIVATE → keep secret (your Keychain / a password manager). Export it as
//     VITRINE_LICENSE_SIGNING_KEY only on the release machine, at build time. NEVER commit it.
//
// The two halves are a pair: a token the app signs with PRIVATE verifies only against PUBLIC.

let privateKey = Curve25519.Signing.PrivateKey()
let privateB64 = privateKey.rawRepresentation.base64EncodedString()
let publicB64 = privateKey.publicKey.rawRepresentation.base64EncodedString()

print(
    """

      Vitrine PRO license signing keypair (Ed25519)
      =============================================

      PUBLIC  (commit into source — LicenseVerifier.embedded):
      \(publicB64)

      PRIVATE (KEEP SECRET — export as VITRINE_LICENSE_SIGNING_KEY at build time):
      \(privateB64)

      Next steps: docs/ACTIVATION.md  ·  never commit the PRIVATE value.

    """)
