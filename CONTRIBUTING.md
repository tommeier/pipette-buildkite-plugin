# Contributing

## Development

```bash
mix deps.get
mix test
```

## Releasing

1. Bump `@version` in `mix.exs`
2. Update version references in documentation:
   - `README.md` (hex version `"~> X.Y"` and plugin tag `#vX.Y.Z`)
   - `guides/getting-started.md`
   - `guides/production-example.md`
   - `guides/dynamic-groups.md`
3. Commit and push to `main`
4. Tag and create a GitHub release:

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   gh release create vX.Y.Z --generate-notes
   ```

5. Publish to Hex:

   ```bash
   mix hex.publish
   ```
