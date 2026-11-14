# Export compliance (encryption)

**Proposal: `ITSAppUsesNonExemptEncryption` = `false`.** Not added to
`ios/Runner/Info.plist` yet: it needs the owner's OK.

## Reasoning

What the app uses encryption for:

| Use | Where | Exempt? |
|---|---|---|
| HTTPS to the Supabase Edge Functions (`https://fwikodmrfoorbstmkedx.supabase.co/functions/v1`) | `package:http` → iOS URLSession / Android TLS | Yes: standard encryption provided by the OS |
| Google AdMob, Google Sign-In, Sign in with Apple network calls | Their SDKs, over HTTPS | Yes: same |
| Session tokens in the Keychain / Android Keystore | `flutter_secure_storage` (OS APIs) | Yes: OS-provided data-at-rest protection for the app's own data |
| SHA-256 of a random nonce for Sign in with Apple | `package:crypto` | Yes: hashing for authentication, not confidentiality |

The app has **no proprietary or non-standard cryptography**, no own
implementation of encryption algorithms, no VPN/end-to-end messaging, and
doesn't encrypt user content for confidentiality beyond the OS's TLS and
Keychain. Under the US EAR (category 5 part 2, note 4 / the mass-market and
"authentication only / OS-provided encryption" exemptions), Apple's guidance is
that apps that only use encryption built into the OS (HTTPS via URLSession,
Keychain) qualify for the exemption, so the answer to "Does your app use
encryption?" → **Yes**, and "Does it qualify for any of the exemptions…?" →
**Yes** (only standard encryption within Apple's OS), which is what
`ITSAppUsesNonExemptEncryption = false` declares. No export compliance
documentation (CCATS) and no annual self-classification report should be
needed for this case.

(This is engineering reasoning, not legal advice. The developer is
responsible for the answer.)

## Options

1. **Add it to Info.plist** (recommended once approved). Every TestFlight
   build is then ready for testers without a manual question:

   ```xml
   <key>ITSAppUsesNonExemptEncryption</key>
   <false/>
   ```

   The widget extension doesn't need it (the key is read from the main app).

2. **Answer per build** in App Store Connect → TestFlight → the build →
   *Manage* (missing compliance). Works, but every CI build waits for a click.

## Google Play

Play has no per-build encryption question. The app is distributed worldwide
by default; there is no extra declaration for standard HTTPS.
