<p align="center">
  <img src="Resources/Emote.png" width="128" alt="Emote">
</p>

<h1 align="center">Emote</h1>

Emoji suggestions that appear next to your cursor.

Emote lives in the Mac menu bar. While you’re writing, press a hotkey and five emojis show up beside the caret — like the suggestions macOS already gives you for words, but for the feeling of the sentence.

Pick one with the keyboard. It drops into whatever you were already typing.

https://github.com/user-attachments/assets/3d642a04-41bc-404b-9cdb-40dd79dc96c6

## Install

1. Download the latest `Emote-*.dmg` from [Releases](https://github.com/narnia-ai-mason/emote/releases).
2. Open the disk image and drag **Emote** into Applications.
3. Open Emote from Applications. It appears in the menu bar.

macOS 14 or later. If Gatekeeper blocks the app, open it once from Finder with **Open**.

## Try it

1. Open **Settings** from the menu bar icon.
2. Paste an [OpenRouter](https://openrouter.ai) API key.
3. Allow **Accessibility** so Emote can read and type into other apps.

Then go to any text field and press **⌃⌘E**. You can change that shortcut in Settings.

Tab or the arrow keys move. Enter inserts. Esc dismisses.

If the caret is in a word, Emote suggests for that word. At the start of a sentence, it suggests for the whole line. Select a word to replace it.

Set a tone if you want the suggestions warmer, drier, or a little extra.

## Models

Emote talks to [OpenRouter](https://openrouter.ai). **Auto routing** (`openrouter/free`) may pick a different free model each time. Pin **Nex N2.5 Mini** — or paste any other model id — if you want the same model on every press.

These are LLM suggestions, so the five emojis can change even when the sentence, model, and temperature stay the same. That is normal. Press the hotkey again if you want another set.

Temperature in Settings asks for more consistent or more varied picks. Lower is meant to be more consistent. Higher is meant to be more varied. The model may ignore that, especially on free endpoints. Even at 0, results can still change.

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
swift run EmoteCLI "hello"
```
