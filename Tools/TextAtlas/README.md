# Text Atlas Tooling

This directory contains the reproducible tooling for regenerating ImmersiveMap's
MSDF text atlases:

- `ImmersiveMap/Text/Resources/atlas.json`
- `ImmersiveMap/Text/Resources/atlas.png`
- `ImmersiveMap/Text/Resources/atlas_thin.json`
- `ImmersiveMap/Text/Resources/atlas_thin.png`

The generated files are committed to the package, but the font files are not.
Use locally installed `.ttf` or `.otf` files.

The committed atlas resources are generated from:

- `NotoSans-Bold.ttf` for `atlas.json` and `atlas.png`
- `NotoSans-Regular.ttf` for `atlas_thin.json` and `atlas_thin.png`

Noto Sans is distributed by the Noto Project under the SIL Open Font License
1.1. Download the fonts from `https://github.com/googlefonts/noto-fonts` and
keep the font files outside this repository.

## Install msdf-atlas-gen

Install Viktor Chlumsky's `msdf-atlas-gen` command line tool before running the
script.

Homebrew may provide a package on some systems:

```sh
brew install msdf-atlas-gen
```

If it is not available from your package manager, build the upstream project from
source:

```sh
git clone https://github.com/Chlumsky/msdf-atlas-gen.git
cd msdf-atlas-gen
git submodule update --init --recursive
cmake -S . -B build
cmake --build build --config Release
```

Then pass the built binary with `--msdf-atlas-gen`.

## Font Input

The script requires a primary label font:

```sh
--font /path/to/PrimaryLabelFont.ttf
```

For production atlas regeneration, also pass a thin-weight face:

```sh
--thin-font /path/to/ThinLabelFont.ttf
```

If `--thin-font` is omitted, the script uses `--font` for both outputs. That is
useful for smoke testing the pipeline, but it will not preserve a visually thin
atlas unless the primary font is already the intended thin face.

Do not commit font files into this repository. When changing the atlas font,
document the exact font family, weights, source, and license in this README
before committing regenerated PNG/JSON resources.

## Charset

The default charset is:

```text
Tools/TextAtlas/charsets/labels-basic.txt
```

It covers printable ASCII, the Cyrillic glyphs already used by the current
resources, and Latin Extended characters used by common European map labels.
The charset file may contain comments; the script strips comments before passing
the cleaned charset to `msdf-atlas-gen`.

## Output

By default, generated resources are written to:

```text
ImmersiveMap/Text/Resources
```

The generator settings match the current renderer-compatible atlas metadata:

- atlas type: `msdf`
- image format: `png`
- glyph size: `64`
- distance range: `8`
- dimensions: `2048 x 2048`
- Y origin: `bottom`

If an expanded charset no longer fits in `2048 x 2048`, rerun with larger fixed
dimensions and commit the generated JSON and PNG resources together.

## Example

From any working directory:

```sh
/path/to/ImmersiveMap/Tools/TextAtlas/generate_text_atlas.sh \
  --font "$HOME/Library/Fonts/NotoSans-Bold.ttf" \
  --thin-font "$HOME/Library/Fonts/NotoSans-Regular.ttf"
```

With an upstream build:

```sh
Tools/TextAtlas/generate_text_atlas.sh \
  --msdf-atlas-gen /path/to/msdf-atlas-gen/build/bin/msdf-atlas-gen \
  --font /path/to/PrimaryLabelFont.otf \
  --thin-font /path/to/ThinLabelFont.otf
```
