# Omashelf

Your recent clipboard items as cards on the edge of the screen. Drag a card
into any app and its contents land where you drop it, the way you would drag a
file out of a file manager.

- **Text** goes into the text field you drop it on: a browser, a chat box, an
  editor.
- **Images** arrive as a file, so they work anywhere that takes a dropped
  image, such as a chat app or an upload box.
- **Copied files** (from Files or another file manager) arrive as those files.

Omashelf shows the history Omarchy's clipboard manager already keeps
(`~/.local/state/omarchy/clipboard-history.json`). It only reads that file and
never changes it, so the shelf and Super+Ctrl+V always show the same items.

## Install

```bash
omarchy plugin add https://github.com/iluxav/omashelf.git --enable
```

Then give it a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + V", "Shelf", "omarchy-shell shell toggle iluxav.omashelf '{}'")
```

Super+Shift+V sits next to Omarchy's own clipboard keys: Super+V pastes and
Super+Ctrl+V opens the clipboard manager.

## Use

| Action | Result |
|---|---|
| Drag a card | Drop its text, image or files into another window |
| Click a card | Copy it back onto the clipboard |
| Esc, or the close button | Close the shelf |

The shelf takes keyboard focus only when you click it, so the window you are
dropping into keeps its focus.

## Limits

- Terminals differ in what they accept. Some insert dropped text, some only
  accept dropped files, and some accept neither.
- The shelf shows the 40 most recent items.

## Requirements

Omarchy with its built-in clipboard manager (`omarchy.clipboard`) enabled, which
is the default.

## License

MIT
