# Contributing

## Development

```bash
mix deps.get
mix test
```

## Releasing

Run the release script with a bump type:

```bash
bin/release minor  # 0.3.0 -> 0.4.0
bin/release patch  # 0.3.0 -> 0.3.1
bin/release major  # 0.3.0 -> 1.0.0
```

This handles everything automatically:
- Bumps `@version` in `mix.exs`
- Updates version references across all docs
- Runs the test suite (aborts on failure)
- Commits, tags, and pushes to `main`
- Creates a GitHub release with auto-generated notes

After the script completes, publish to Hex:

```bash
mix hex.publish
```
