
<p align="center">
  <img src="Resources/Emote.png" width="128" alt="Emote">
</p>

<h1 align="center">Emote</h1>

Emoji suggestions that appear next to your cursor.

Most emoji pickers ask you to remember a name — `:tada:`, “party popper”, or a search box. Emote does not. It reads the sentence and suggests for the feeling.

Emote lives in the Mac menu bar. While you’re writing, press a hotkey and a few emojis show up beside the caret — like the suggestions macOS already gives you for words, but for the feeling of the sentence.

Pick one with the keyboard. It drops into whatever you were already typing.

https://github.com/user-attachments/assets/6baae39e-ed64-4fb0-a38f-562e422bffac

<details>
<summary>한국어 · 日本語 · 中文</summary>

**한국어**


https://github.com/user-attachments/assets/b341b74e-6c21-4d17-a37c-f4b3bb7cae46


**日本語**


https://github.com/user-attachments/assets/d4ba211a-fddc-4761-b8e9-52ca73a2f7df


**中文**


https://github.com/user-attachments/assets/ba6b1b45-8cd2-482b-b67e-b21733af134c


</details>

## Install

1. Download the latest `Emote-*.dmg` from [Releases](https://github.com/narnia-ai-mason/emote/releases).
2. Open the disk image and drag **Emote** into Applications.
3. Open Emote from Applications. It appears in the menu bar.

macOS 14 or later. If Gatekeeper blocks the app, open it once from Finder with **Open**.

## Try it

1. Open **Settings** from the menu bar icon.
2. Leave the engine on **Gemma 4**, or switch to **API**.
3. Allow **Accessibility** so Emote can read and type into other apps.

Then go to any text field and press **⌃⌘E**. You can change that shortcut in Settings.

Tab or the arrow keys move. Enter inserts. Esc dismisses.

Where the caret is changes the request. At the start of a sentence with no ending punctuation, Emote treats that line as a heading and also reads the first sentence on the next line, if there is one. A markup heading is a heading wherever the caret sits on that line: Markdown `#` through `######`, a title on an `=` or `-` underline, AsciiDoc `=`, and HTML `<h1>` through `<h6>`. The marker is left out of the request. After a finished sentence, or inside one, it suggests for that sentence. In a short word, it suggests for that word. A longer selection is treated as a sentence. Word boundaries follow macOS, so Japanese, Chinese, and other languages without spaces still focus on the word by the cursor.

Settings has four tones: neutral, dry, warm, and playful. Tone changes the mood of the list. It does not change what the sentence is about.

Fewer than five suggestions is fine. Press the hotkey again if you want another set.

## Engines

**Gemma 4** is the default. It runs Gemma 4 E4B on this Mac. The first time, Settings asks you to download it (about 5.2 GB). After that, Settings shows Ready. The first suggestion after you open the app can take a few seconds while the model loads. The HUD says **Loading the model…** for that press, then **Finding…** after that. The sentence stays on this Mac. This does not need Apple Intelligence, so it runs on macOS 14 as well as later versions.

**API** sends the sentence to an OpenAI-compatible chat API. Settings takes a base URL, an API key, and a model name. The base URL is the provider's `/v1` root. OpenAI, OpenRouter, Groq, and Together all use that shape. The default is OpenAI's `https://api.openai.com/v1` with `gpt-4o-mini`.

Gemma 4 stays on this Mac. API is a third-party service. Emote does not run it and is not responsible for how that service stores or uses the text. See **About Emote** in the menu bar.

These are model suggestions, so the emojis can change even when the sentence stays the same.

## Build from source

```sh
./scripts/run-app.sh
```

```sh
swift test
```

The same recommender is available from the terminal:

```sh
swift run EmoteCLI --engine gemma4 "hello"
swift run EmoteCLI --engine api --tone warm "I just shipped"
```

For API, set `EMOTE_API_KEY` (or `OPENAI_API_KEY`), and optionally `EMOTE_API_BASE_URL` and `EMOTE_API_MODEL`. `--model` overrides the model name.
