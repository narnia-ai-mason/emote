<p align="center">
  <img src="Resources/Emote.png" width="128" alt="Emote">
</p>

<h1 align="center">Emote</h1>

Emoji suggestions that appear next to your cursor.

Most emoji pickers ask you to remember a name — `:tada:`, “party popper”, or a search box. Emote does not. It reads the sentence and suggests for the feeling.

Emote lives in the Mac menu bar. While you’re writing, press a hotkey and a few emojis show up beside the caret — like the suggestions macOS already gives you for words, but for the feeling of the sentence.

Pick one with the keyboard. It drops into whatever you were already typing.

https://github.com/user-attachments/assets/3d642a04-41bc-404b-9cdb-40dd79dc96c6

## Install

1. Download the latest `Emote-*.dmg` from [Releases](https://github.com/narnia-ai-mason/emote/releases).
2. Open the disk image and drag **Emote** into Applications.
3. Open Emote from Applications. It appears in the menu bar.

macOS 14 or later. If Gatekeeper blocks the app, open it once from Finder with **Open**.

## Try it

1. Open **Settings** from the menu bar icon.
2. Choose an **Engine**.
3. Allow **Accessibility** so Emote can read and type into other apps.

Then go to any text field and press **⌃⌘E**. You can change that shortcut in Settings.

Tab or the arrow keys move. Enter inserts. Esc dismisses.

If the caret is in a word, Emote suggests for that word. At the start of a sentence, it suggests for the whole line. Select a word to replace it.

Set a tone if you want the suggestions warmer, drier, or a little extra.

Fewer than five suggestions is fine. Press the hotkey again if you want another set.

## Engines

**Auto** uses Apple Intelligence on this Mac when it’s ready and fast enough. If it isn’t, Auto uses OpenRouter. You need one or the other: Apple Intelligence turned on, or an OpenRouter API key.

**On-device** uses only the Apple Intelligence model on this Mac. No API key. That needs macOS 26 or later, Apple silicon, and Apple Intelligence enabled in System Settings. Settings can open that pane for you.

**OpenRouter** sends the text around the cursor to [OpenRouter](https://openrouter.ai) and the model you chose. Apple Intelligence can stay off. You need an API key.

On-device stays on this Mac. OpenRouter is a third-party service. Emote does not run it and is not responsible for how it stores or uses that text. See **About Emote** in the menu bar, and OpenRouter’s [terms](https://openrouter.ai/terms) and [privacy](https://openrouter.ai/privacy).

## OpenRouter models

When the engine is Auto or OpenRouter, **Auto routing** (`openrouter/free`) may pick a different free model each time. Pin **Nex N2.5 Mini** — or paste any other model id — if you want the same model on every press.

These are LLM suggestions, so the emojis can change even when the sentence, model, and temperature stay the same. That is normal.

Temperature in Settings applies to OpenRouter. Lower is meant to be more consistent. Higher is meant to be more varied. The model may ignore that, especially on free endpoints. Even at 0, results can still change. On-device uses a fixed 0.7 so the list does not collapse to one or two emojis.

Some free models stay blocked unless you allow free-model training in [OpenRouter privacy settings](https://openrouter.ai/settings/privacy). That setting is on your account, not per API key.

## Build from source

```sh
./scripts/run-app.sh
```

```sh
swift test
```

The same recommender is available from the terminal:

```sh
swift run EmoteCLI --engine auto "hello"
swift run EmoteCLI --engine on-device --prewarm --tone "warm and light" "I just shipped"
```
