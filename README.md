<p align="center">
  <img src="Resources/Emote.png" width="128" alt="Emote">
</p>

<h1 align="center">Emote</h1>

Emoji suggestions that appear next to your cursor.

Emote lives in the Mac menu bar. While you’re writing, press a hotkey and five emojis show up beside the caret — like the suggestions macOS already gives you for words, but for the feeling of the sentence.

Pick one with the keyboard. It drops into whatever you were already typing.

## Try it

1. Open **Settings** from the menu bar icon.
2. Paste an [OpenRouter](https://openrouter.ai) API key.
3. Allow **Accessibility** so Emote can read and type into other apps.

Then go to any text field and press **⌃⌘E**. You can change that shortcut in Settings.

Tab or the arrow keys move. Enter inserts. Esc dismisses.

If the caret is in a word, Emote suggests for that word. At the start of a sentence, it suggests for the whole line. Select a word to replace it.

Set a tone if you want the suggestions warmer, drier, or a little extra.

## Models

Emote talks to [OpenRouter](https://openrouter.ai). **Auto routing** (`openrouter/free`) may pick a different free model each time. Pin **Nex N2.5 Mini** — or paste any other model id — for more consistent suggestions.

Temperature in Settings also changes how varied the picks are. Lower is more consistent. Higher is more varied. Even at 0, results can still change.

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
