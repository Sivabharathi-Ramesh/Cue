# Cue icon

The mark pairs a white speech-bubble **C** with three mint audio bars. The
bold silhouette and high contrast help users pick out Cue on a busy home screen.

## Palette

| Use        | Colour                                  |
|------------|-----------------------------------------|
| Background | `#3D46CF` → `#2729A4` → `#151454`         |
| Letter     | `#FFFFFF` → `#EEF0FF`                     |
| Audio bars | `#72FCB0`                               |

## Files

| File | What it is |
|------|------------|
| `cue_icon.svg` | Master artwork, 1024 × 1024, full bleed |
| `cue_icon_foreground.svg` | Android adaptive foreground, 108 × 108, transparent, safe-zone sized |
| `cue_icon_mono.svg` | Single-colour mark for Android 13+ themed icons |
| `cue_icon_512.png` | Store listing / press use |
| `cue_icon_preview.png` | Size and mask preview sheet |

## Where it is wired in

- Android launcher: `android/app/src/main/res/mipmap-*/ic_launcher.png` (legacy,
  API < 26) plus `mipmap-anydpi-v26` and `mipmap-anydpi-v33` adaptive icons
  (`drawable/ic_launcher_background.xml`, `ic_launcher_foreground.xml`,
  `ic_launcher_monochrome.xml`).
- iOS: all slots in `ios/Runner/Assets.xcassets/AppIcon.appiconset`.

## Regenerating

```sh
inkscape --export-type=png --export-filename=out.png --export-width=192 cue_icon.svg
```

Export directly from the SVG at each target size. Use the full-bleed artwork
for the store icon and opaque RGB PNGs for the iOS catalog. For legacy Android
PNGs, set the background rectangle's `rx` to `60` in a copy of the SVG to render
rounded corners.
