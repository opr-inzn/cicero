# Contributing to Cicero

Thank you for helping. Bug reports, sample fonts, sample texts and ideas are all welcome, and so are pull requests.

## Before you start

Please [open an issue](https://github.com/opr-inzn/cicero/issues/new) before you work on a larger change, so we can agree on the approach first. Right now I am working on performance and reliability, so I may hold back new features until that work is finished. Small fixes don’t need an issue.

## Branches

- **`main`** holds the latest stable release.
- **`beta`** holds the next version and the beta releases. **Open pull requests against `beta`.**

When a beta is ready, `beta` is merged into `main` and released as the stable version.

## Versions

- A stable release is `<major>.<minor>.<patch>`, for example `0.12.0`.
- A beta release is that version followed by `b` and the beta build: `0.12.0b1`, `0.12.0b2`, and so on, up to the stable `0.12.0`.
- The build number (`CFBundleVersion`) goes up with every release, beta or stable, because updates go by the build number.

## Building

You need macOS 15 or later on Apple silicon, and Swift 6.2 (Xcode or the Command Line Tools).

```sh
swift build                    # build
./scripts/build-app.sh         # build build/Cicero.app
./scripts/build-app.sh --install   # and copy it to /Applications
```

## Testing

The test suite isn’t in the public repository, so you can’t run it from a clone. In your pull request, describe what you tried and how: which fonts, which steps, what you expected and what happened. I run the full suite before I merge.

## AI assistance

Using AI tools such as Claude Code or Codex is completely fine, and you don’t need to disclose it. What matters is that you understand the code you send and that you tested it.

## Release notes

Describe the change for users in the pull request. I write the entry in [CHANGELOG.md](CHANGELOG.md) when I release.

## License

By contributing, you agree that your contribution is released under the [MIT License](LICENSE), like the rest of Cicero.
