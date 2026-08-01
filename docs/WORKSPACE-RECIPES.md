# Workspace recipes

A workspace recipe is one portable JSON document that keeps a code-capture style,
optional header context, and output defaults together. It is useful when the same
folder or repository repeatedly needs the same presentation in documentation,
reviews, or release notes.

Recipes are explicit by design. Vitrine does not search parent folders, inspect Git
configuration, or read Application Support when the CLI starts. Pass the file you
want for each invocation:

```bash
vitrine recipe validate docs/examples/documentation.vitrine-recipe.json
vitrine recipe show docs/examples/documentation.vitrine-recipe.json --json
vitrine render README.md --out /tmp/readme.png \
  --recipe docs/examples/documentation.vitrine-recipe.json
```

`recipe validate` and `recipe show` do not render and do not require PRO activation.
Rendering through `--recipe` follows the normal CLI entitlement boundary.

## What a recipe contains

The versioned `vitrine.workspace-recipe` envelope contains exactly one recipe:

- a display name;
- a portable `StyleSnapshot`;
- an optional embedded custom-theme palette;
- optional window-title and header metadata;
- optional destination preset, canvas size, scale, format, and color profile.

The complete example at
[`docs/examples/documentation.vitrine-recipe.json`](examples/documentation.vitrine-recipe.json)
is validated by the test suite.

The document contains no workspace path, source text, output path, capture history,
or credentials. Filename metadata is reduced to its final path component during
encoding and decoding. Image backgrounds are not portable and continue to fall back
to Vitrine's signature gradient when a style is captured.

## Precedence

Settings are applied from lowest to highest precedence:

1. Vitrine defaults;
2. the recipe's destination preset;
3. the recipe's style and output defaults;
4. an explicit `--style-preset`;
5. explicit CLI flags such as `--theme`, `--padding`, `--format`, or
   `--no-language-badge`.

A recognized extension in `--out` is also explicit. For example, `--out card.pdf`
produces PDF even when the recipe defaults to PNG. Passing both `--format` and a
recognized extension still requires them to agree.

## Validation and compatibility

- The current schema version is `1`.
- Unknown document formats and schema versions fail before rendering.
- Destination presets, themes, scale, and canvas bounds are validated.
- A custom theme must embed its palette and its id must exactly match the style's
  theme reference.
- Recipe files are limited to 1 MB.
- `multi-size` rejects recipe-level destination, canvas, or scale defaults because
  each selected destination owns those dimensions.
- Recipes currently configure code and terminal captures, not `--image` input.

The CLI intentionally has no `recipe import` command. A portable file should remain
the source of truth instead of being copied into hidden CLI state. Machine-local
folder associations belong to the macOS app and remain separate from the exported
document.
