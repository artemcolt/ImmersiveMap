# Generated

`Generated` contains source files produced by external generators and checked
into the package when they are required by the Swift target.

Generated output is not a place for hand-written engine behavior. Change the
source schema or generator configuration, then regenerate.

## Responsibilities

- Store generated Swift sources required by the package build.
- Keep generated code isolated from hand-written engine logic.
- Make generator ownership obvious to future maintainers.

## May Contain

- Generated Swift files derived from schemas in `Proto`.
- Minimal documentation explaining generation boundaries.
- Generator outputs that are deterministic and public-safe.

## Must Not Contain

- Hand-written models, parsers, renderer code, or business logic.
- Manual edits to generated files that should be made in the source schema.
- Local generated artifacts, temporary files, build products, or DerivedData.
- Secrets, auth tokens, private URLs, or machine-specific paths.
- Source files that require the standard repository copyright header but were
  not actually hand-written.

## Intended Flow

```text
Proto schema
  -> generator
  -> Generated source
  -> package build
```
