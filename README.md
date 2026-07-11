# GridSelect

GridSelect is a pre-alpha macOS utility for copying rectangular regions from
plain-text, monospace content. It is intended for cases where normal linear text
selection makes it hard to copy columns, aligned fields, or fixed-width slices.

The project is experimental and has a minimal Swift package scaffold, but no
packaged build or supported release yet. Current work is focused on proving the
macOS MVP and the narrow system-integration path needed for the core
interaction.

## MVP Scope

The first MVP is intentionally small:

| Area | MVP direction |
|---|---|
| Platform | macOS first |
| Source content | Plain-text or plain-text-like monospace regions |
| Activation | User-invoked global shortcut |
| Selection | Temporary rectangular overlay across visible text |
| Extraction | Best-effort row and column mapping for the selected rectangle |
| Output | Plain text copied to the system clipboard |

The MVP succeeds when a user can invoke GridSelect, draw a rectangle over visible
monospace text, and copy the corresponding row and column slice without changing
the source application.

## Non-goals

GridSelect is not trying to solve every selection or extraction problem in the
first release. These areas are intentionally outside the MVP:

- OCR or screenshot-based extraction.
- PDF-specific extraction.
- Image handling.
- AI summarization or table inference.
- Replacing normal native text selection.
- App-specific optimizations for Word, Excel, Slack, Notion, or similar apps.
- Windows or Linux support before the macOS MVP is proven.

Requests in these areas should be captured in the
[deferred scope tracker](docs/deferred-scope-tracker.md) instead of becoming MVP
requirements.

## Project Status

| Area | Status |
|---|---|
| Product requirements | Drafted for the macOS-first MVP. |
| Architecture | Proposed native macOS architecture using Swift, SwiftUI, AppKit, and Accessibility APIs. |
| Implementation | Minimal Swift package scaffold exists; core system integrations are not implemented yet. |
| Releases | No supported release or package is available. |
| Contributions | Welcome through focused issues and pull requests that fit the MVP boundary. |

## Documentation

- [Product requirements and MVP boundary](docs/product-requirements.md)
- [ADR 0001: Native macOS architecture for the MVP](docs/adr/0001-macos-native-mvp-architecture.md)
- [Deferred scope tracker](docs/deferred-scope-tracker.md)
- [Issue parallel execution plan](docs/issue-parallel-execution-plan.md)
- [Repository hardening audit](docs/repository-hardening-audit.md)

## Contributing

Before opening a pull request, read [CONTRIBUTING.md](CONTRIBUTING.md) and keep
changes focused on an existing issue or a small proposal. Security reports should
follow [SECURITY.md](SECURITY.md), not public issue details.

All contributors are expected to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## License

GridSelect is licensed under the [MIT License](LICENSE).
