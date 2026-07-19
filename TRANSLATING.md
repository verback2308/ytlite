# Translating YTLite

YTLite ships classic per-language `Localizable.strings` files — plain text,
editable without Xcode. English (`YTLite/en.lproj/`) is the source of truth;
`ru` is maintained by the author. Adding or updating a language is one file
(plus two one-line registrations, see Workflow).

This document doubles as an **LLM translation prompt**: paste everything from
"Prompt for LLM translation" down, attach `en.lproj/Localizable.strings`, and
state the target language.

## Workflow (adding language `xx`)

1. Copy `YTLite/en.lproj/Localizable.strings` → `YTLite/xx.lproj/Localizable.strings`
   and translate the values (by hand or with the prompt below).
2. Copy `YTLite/en.lproj/Localizable.stringsdict` → `YTLite/xx.lproj/` and fill
   the plural forms your language's CLDR rules require (Russian, for example,
   needs `one`/`few`/`many`; English only `one`/`other`).
3. Register the language (skip if only updating an existing one):
   - `YTLite/Core/Localization/AppLanguage.swift` — add the enum case and its
     native-script `displayName` ("Русский", not "Russian").
   - `YTLite/Info.plist` — add the code to `CFBundleLocalizations`.
4. Validate: `python3 scripts/check_strings.py` (unknown keys and placeholder
   mismatches are errors; missing keys only warn — partial translations ship
   fine and fall back to English).
5. Build. The in-app picker (Settings → Language → App Language) lists the new
   language automatically.

**Content language note**: UI translation is independent of the *content
language* (video titles, feeds — translated server-side by YouTube via `hl`).
If your language's relative-date and view-count words are not yet in
`YTLite/Core/Localization/ContentKeywords.swift`, subscriptions-feed ordering
degrades gracefully but add a keyword table for full support.

**RTL languages (ar, he, fa)**: not accepted yet — the layout has not been
audited for right-to-left. UI-only PRs for RTL will be declined until then.

---

## Prompt for LLM translation

You are translating the UI strings of YTLite, a lightweight third-party
YouTube client for iOS. Input: an English `.strings` file where each line is
`"key" = "value";` with `/* comments */` giving context. Output: the same
file with ONLY the values translated into the target language.

### Hard rules

1. **Never change keys** — the left-hand side of `=` is program API.
2. **Never change placeholders** — `%1$@`, `%1$d`, `%@`, `%d` must appear in
   the translation exactly as many times, with the same numbering. Reorder
   them freely if the target grammar wants a different word order.
3. **Preserve file structure** — keep every line, comment, blank line and
   section header in place; translate comment text only if asked.
4. **Escapes stay escapes** — `\n` stays `\n` (it is a real line break),
   `\"` stays an escaped quote. Every line still ends with `";`.
5. **Missing is better than wrong** — if unsure about a string, leave the
   English value; the app falls back cleanly.

### What must NOT be translated

- Product/project names: YTLite, YouTube, Shorts, SponsorBlock,
  Return YouTube Dislike, Picture-in-Picture stays translated only if your
  language has an established OS term for it (Apple's own glossary).
- Technical debug values mentioned inside footer texts: "Android VR",
  "Mobile Web + pot", "pot", "n-solving", "iOS 12–13" — keep verbatim.
- URLs (returnyoutubedislike.com, sponsor.ajay.app).

### Glossary and tone

- Follow the **official YouTube app** in your language for domain terms:
  Subscribe / Subscriptions / Playlist / Live / Comments / Quality /
  Subtitles / Audio track / "Stats for nerds" — use YouTube's established
  translations, not literal ones (Russian example: "Stats for nerds" →
  "Статистика для сисадминов").
- Follow **Apple's iOS glossary** for system terms: Settings, Cancel, Done,
  Sign In, Dark/Light theme.
- Tone: concise UI language, neutral register, no exclamation marks.
  Address the user politely (formal "you" where the language distinguishes).
- Suffix keys (`player.subtitles.autoSuffix`, `player.audioTrack.aiSuffix`,
  `settings.solver.defaultSuffix`) begin with a space — keep it.
- `(AI)` marks an AI auto-dubbed audio track; use your language's common
  abbreviation for artificial intelligence (Russian: "ИИ").

### Plurals (`Localizable.stringsdict`)

The XML file defines pluralized strings (currently `settings.daysCount`,
"%d day(s)"). Fill every CLDR plural category your language uses
(`zero`/`one`/`two`/`few`/`many`/`other` — subset as required). Do not
change keys, `NSStringFormatValueTypeKey`, or the `%#@days@` wrapper.

### Self-check before returning the file

- [ ] Same number of `"key" = "value";` lines as the input
- [ ] `grep -c '%1$@'` matches the input count; same for `%1$d`
- [ ] No key contains non-ASCII or was renamed
- [ ] Every line ends with `";`
- [ ] Product names untranslated
