#!/usr/bin/env python3
"""Create a branch + commit for each new localization language."""

import subprocess
import sys
import os

os.chdir(os.path.join(os.path.dirname(__file__), ".."))

LANGUAGES = [
    ("af", "afrikaans", "Afrikaans"),
    ("am", "amharic", "አማርኛ"),
    ("az", "azerbaijani", "Azərbaycanca"),
    ("be", "belarusian", "Беларуская"),
    ("bg", "bulgarian", "Български"),
    ("bn", "bengali", "বাংলা"),
    ("bs", "bosnian", "Bosanski"),
    ("ca", "catalan", "Català"),
    ("cs", "czech", "Čeština"),
    ("da", "danish", "Dansk"),
    ("de", "german", "Deutsch"),
    ("el", "greek", "Ελληνικά"),
    ("es", "spanish", "Español"),
    ("et", "estonian", "Eesti"),
    ("eu", "basque", "Euskara"),
    ("fi", "finnish", "Suomi"),
    ("fr", "french", "Français"),
    ("ga", "irish", "Gaeilge"),
    ("gl", "galician", "Galego"),
    ("gu", "gujarati", "ગુજરાતી"),
    ("hi", "hindi", "हिन्दी"),
    ("hr", "croatian", "Hrvatski"),
    ("hu", "hungarian", "Magyar"),
    ("hy", "armenian", "Հայերեն"),
    ("id", "indonesian", "Bahasa Indonesia"),
    ("is", "icelandic", "Íslenska"),
    ("it", "italian", "Italiano"),
    ("ja", "japanese", "日本語"),
    ("kk", "kazakh", "Қазақша"),
    ("km", "khmer", "ភាសាខ្មែរ"),
    ("ko", "korean", "한국어"),
    ("ky", "kyrgyz", "Кыргызча"),
    ("lo", "lao", "ລາວ"),
    ("lt", "lithuanian", "Lietuvių"),
    ("lv", "latvian", "Latviešu"),
    ("mk", "macedonian", "Македонски"),
    ("ml", "malayalam", "മലയാളം"),
    ("mn", "mongolian", "Монгол"),
    ("mr", "marathi", "मराठी"),
    ("ms", "malay", "Bahasa Melayu"),
    ("my", "burmese", "မြန်မာ"),
    ("ne", "nepali", "नेपाली"),
    ("nl", "dutch", "Nederlands"),
    ("no", "norwegian", "Norsk"),
    ("pa", "punjabi", "ਪੰਜਾਬੀ"),
    ("pl", "polish", "Polski"),
    ("pt", "portuguese", "Português"),
    ("ro", "romanian", "Română"),
    ("si", "sinhala", "සිංහල"),
    ("sk", "slovak", "Slovenčina"),
    ("sl", "slovenian", "Slovenščina"),
    ("sq", "albanian", "Shqip"),
    ("sr", "serbian", "Српски"),
    ("sv", "swedish", "Svenska"),
    ("sw", "swahili", "Kiswahili"),
    ("ta", "tamil", "தமிழ்"),
    ("te", "telugu", "తెలుగు"),
    ("th", "thai", "ไทย"),
    ("tl", "filipino", "Filipino"),
    ("tr", "turkish", "Türkçe"),
    ("uk", "ukrainian", "Українська"),
    ("uz", "uzbek", "Oʻzbekcha"),
    ("vi", "vietnamese", "Tiếng Việt"),
    ("zh-Hans", "chineseSimplified", "简体中文"),
    ("zh-Hant", "chineseTraditional", "繁體中文"),
    ("zu", "zulu", "isiZulu"),
]

SWIFT_PATH = "YTLite/Core/Localization/AppLanguage.swift"
PLIST_PATH = "YTLite/Info.plist"
PBXPROJ_PATH = "YTLite.xcodeproj/project.pbxproj"


def run(cmd):
    subprocess.run(cmd, check=True)


BASE_BRANCH = "feature/localization"


def make_branch(code):
    run(["git", "checkout", "-b", f"lang/{code}", BASE_BRANCH])


def checkout_base():
    run(["git", "checkout", BASE_BRANCH])


def add_swift_case(code, case_name, display_name):
    with open(SWIFT_PATH, "r") as f:
        content = f.read()

    # Add enum case after the last existing case
    enum_marker = '    case russian = "ru"'
    new_enum = f'{enum_marker}\n    case {case_name} = "{code}"'
    content = content.replace(enum_marker, new_enum)

    # Add displayName case before the closing }
    display_marker = '        case .russian:\n            "Русский"'
    new_display = f'{display_marker}\n        case .{case_name}:\n            "{display_name}"'
    content = content.replace(display_marker, new_display)

    with open(SWIFT_PATH, "w") as f:
        f.write(content)


def add_info_plist(code):
    with open(PLIST_PATH, "r") as f:
        content = f.read()

    marker = "		<string>ru</string>"
    new_line = f'{marker}\n		<string>{code}</string>'
    content = content.replace(marker, new_line)

    with open(PLIST_PATH, "w") as f:
        f.write(content)


def add_known_region(code):
    with open(PBXPROJ_PATH, "r") as f:
        content = f.read()

    marker = "				ru,"
    new_line = f"{marker}\n				{code},"
    content = content.replace(marker, new_line, 1)

    with open(PBXPROJ_PATH, "w") as f:
        f.write(content)


def commit(code, display_name):
    run(["git", "add", SWIFT_PATH, PLIST_PATH, PBXPROJ_PATH])
    run(["git", "add", f"YTLite/{code}.lproj/"])
    run(["git", "commit", "-m", f"Add {display_name} ({code}) localization"])


def main():
    # Determine which languages to process
    start_from = sys.argv[1] if len(sys.argv) > 1 else None
    started = start_from is None

    for code, case_name, display_name in LANGUAGES:
        if not started:
            if code == start_from:
                started = True
            else:
                continue

        print(f"\n=== {code} ({display_name}) ===")
        try:
            make_branch(code)
            add_swift_case(code, case_name, display_name)
            add_info_plist(code)
            add_known_region(code)
            commit(code, display_name)
            checkout_base()
            print(f"  ✓ branch lang/{code} created and committed")
        except Exception as e:
            print(f"  ✗ FAILED: {e}")
            # Try to get back to base branch
            try:
                subprocess.run(
                    ["git", "checkout", "--", SWIFT_PATH, PLIST_PATH, PBXPROJ_PATH],
                    capture_output=True,
                )
                checkout_base()
            except Exception:
                pass


if __name__ == "__main__":
    main()
