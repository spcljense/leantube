# LeanTube fonts

Roboto 3.015 Regular is used for menus, search, playback controls, and
metadata. Noto Sans 2.015 Bold is used for video titles and screen headings.
Roboto and Noto Sans are also fallbacks for missing glyphs in the other face.

Roboto: [Google Fonts Roboto](https://github.com/google/fonts/tree/main/ofl/roboto),
`Roboto[wdth,wght].ttf`, SHA-256
`d7598e12c5dbef095ff8272cfc55da0250bd07fbdecbac8a530b9b277872a134`.
See `Roboto-OFL.txt`.

Noto Sans, the script-specific Noto Sans faces, and Noto Sans Symbols are
unmodified files from Arch Linux `noto-fonts` 1:2026.11.01-1.
The Noto Sans CJK KR regular face and the Noto Emoji outline subset come
from the local Stremio Native package assets `pkg/appfont-cjk.ttf` and
`pkg/appfont-emoji.ttf`. The emoji subset covers individual pictographs.
See `Noto-OFL.txt` and `NotoSansMath.md`.

Fallback selection keeps grapheme clusters together. SDL_ttf and HarfBuzz
shape the selected script-specific faces. The app can also use installed
webOS fonts for characters outside the bundled coverage.
