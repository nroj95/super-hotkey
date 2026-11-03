# Translations

Super Hotkey shows its text in the Windows display language when a file for it is here, and in English otherwise. **Language...** in the tray can pick another language; Super Hotkey restarts in it.

## Add a language

1. Copy `template.lang` to `<code>.lang`, named after the language's code: `de.lang` for German, `pt-BR.lang` for Brazilian Portuguese. Windows looks for the full code first, then the part before the dash.
2. Write the language's own name after `; language:` on the first line, such as `; language: Deutsch`.
3. Write each translation after its `=`. A line left empty shows in English, so you can stop at any point.
4. Run `python tools/lang.py de` to see how much is left.

## Rules

- Keep `{1}`, `{2}` and so on: they stand for text the suite fills in, such as a key name.
- Keep key names such as `CapsLock`, `Pause`, `Win` and `Ctrl`, and the module names, such as `Secret Layers`, as they are.
- Lines in capitals are guide headings. Write their translation in capitals too.
- Each guide sentence is one entry; the guide joins them into paragraphs.
- Buttons and checkboxes have a fixed width, so look at the pages to check that nothing is cut off.
- Save the file as UTF-8.

## When the code changes

`python tools/lang.py --update` brings the template and every language up to date: new text gets an empty `=`, and a translation whose English changed or disappeared moves below `; stale` at the end, so you can reuse its wording. Delete a stale entry once you no longer need it. `python tests/check.py` fails until the files are up to date.
