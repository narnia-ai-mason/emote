# Changelog

Each version has a `v` tag. Builds 1.4.4 through 1.4.10 were test builds and were never tagged or released.

## 1.4.11 — 2026-10-06

### Added

- Neovim in a terminal. Emote reads the buffer, cursor, mode, and Visual selection over Neovim's RPC socket and inserts the emoji straight into the buffer, so line numbers, wrapped lines, and completion plugins don't get in the way. Tried in Otty and Terminal; iTerm2, kitty, and Ghostty are untested.
- A local history of recommendations and their outcomes in `~/Library/Application Support/Emote/recommendation-history.jsonl`, with caret diagnostics for the latest one in `caret-debug.txt`.

### Changed

- Markup headings count wherever the caret sits on the line: Markdown `#`, setext underlines, AsciiDoc `=`, and HTML `<h1>`–`<h6>`. The marker is left out of the request.
- A heading's next sentence skips blank lines and stops at another heading. In Notion, it comes from the next block.
- An emoji or closing quote after a period stays with its sentence. A caret touching a period means that sentence, not the next one.

### Fixed

- Chrome and Slack: the caret landed several characters off, and paragraphs ran together, so headings were read as sentences.
- Cursor and other VS Code forks: suggestions went wrong past roughly line 120, where the editor stops sharing text. Emote now reads around the caret, or says the app hides text that far down.
- Obsidian and Notion: hidden placeholder characters broke headings and words.
- The HUD no longer jumps to the middle of the screen when an app reports an empty or far-off caret rectangle.

## 1.4.3 — 2026-10-04

### Fixed

- Gemma 4 sometimes returned nothing for a heading with no following sentence. Replies are now constrained to a JSON emoji list.

### Removed

- The leftover Apple Intelligence and OpenRouter code. Only Gemma 4 and the API engine remain.

## 1.4.2 — 2026-10-04

### Changed

- The fourth tone is named playful. A saved joyful setting becomes playful.

## 1.4.1 — 2026-10-04

### Fixed

- Settings shows Ready once Gemma 4 has downloaded.

## 1.4.0 — 2026-10-04

### Added

- Gemma 4 E4B as the default engine. It downloads once and runs on the Mac.
- An API engine for any OpenAI-compatible chat API, with a base URL, key, and model name.
- Heading, sentence, and word modes, chosen by where the caret sits.

### Changed

- Tone is a choice of four instead of free text.

### Removed

- The Apple Intelligence and OpenRouter-only engines.

## 1.3.0 — 2026-09-13

### Fixed

- Japanese and Chinese focus on the word by the cursor instead of the whole sentence. Fullwidth `！` and `？` end sentences.

## 1.2.1 — 2026-09-13

### Changed

- The on-device engine is grayed out until Apple Intelligence is ready.

## 1.2.0 — 2026-09-13

### Added

- Apple Intelligence on-device suggestions, with OpenRouter as a fallback.

## 1.1.0 — 2026-09-13

### Added

- A temperature slider for how consistent suggestions are.

## 1.0.1 — 2026-09-13

- First release: a menu-bar app that suggests emojis for the sentence by the caret.
