# i18n/README_i18n.md

This branch adds initial tooling and a Simplified Chinese Localizable.strings file to start full i18n work.

What I added:
- YTLite/zh-Hans.lproj/Localizable.strings
  - Initial common translations (OK, Cancel, Retry, Sign In, etc.).
- scripts/extract_strings.py
  - A heuristic script to find likely user-facing string literals in .swift and .storyboard files.

Next recommended steps (I can do these for you):
1) Run the extractor and review results:
   python3 scripts/extract_strings.py > strings_to_localize.json
   Review strings_to_localize.json and remove false positives.

2) For each user-facing string, replace the literal in code with NSLocalizedString("<key>", comment: "")
   - Choose stable keys (e.g., "home.title", "auth.sign_in.button").
   - Example: titleLabel.text = NSLocalizedString("home.title", comment: "Title on the home screen")

3) Add translations to YTLite/zh-Hans.lproj/Localizable.strings using those keys.

4) Repeat in small batches and test the app with the device language set to Chinese.

If you want, I can proceed to:
- Automatically propose replacements for a batch of files (e.g., Core UI components), create PRs, and populate zh-Hans translations.
- Or perform a full- repo automated replacement in multiple commits.

Which do you want me to do next? (I can start running the extractor and prepare the first batch of replacements.)
