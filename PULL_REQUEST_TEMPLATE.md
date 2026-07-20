# i18n(auth) PR description

This PR introduces Simplified Chinese localization for the Auth module and replaces hard-coded UI strings with NSLocalizedString(). It is the first step toward full i18n support.

Changes:
- Replaced user-facing hardcoded strings in YTLite/Core/Auth/AuthViewController.swift with NSLocalizedString() keys (auth.*).
- Added translations for these keys to YTLite/zh-Hans.lproj/Localizable.strings.
- Added an extractor script in previous commits to help find other strings across the repo.

Files changed:
- YTLite/Core/Auth/AuthViewController.swift
- YTLite/zh-Hans.lproj/Localizable.strings

Testing steps:
1. Checkout branch i18n/auth-localization
2. Run the app in Simulator/Device with system language set to Simplified Chinese
3. Start the Auth flow and verify button titles, instructions, and status/error messages appear in Chinese.

Notes:
- This change only affects UI strings and should not alter app behavior.
- Later PRs will cover additional modules and storyboard/localizable strings.
