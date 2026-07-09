# Security Policy

GridSelect is pre-alpha software. It has no supported release yet, but security
reports are still welcome and should be handled privately.

## Supported Versions

| Version | Support status |
|---|---|
| `main` pre-alpha work | Best-effort maintainer review |
| Packaged releases | Not available |

## Reporting a Vulnerability

Do not publish vulnerability details in a public issue, pull request, or
discussion.

Preferred reporting path:

1. Use GitHub's private vulnerability reporting for this repository when it is
   available from the repository Security tab.
2. If private vulnerability reporting is not available, ask `@Saber5656` for a
   private reporting channel without including technical exploit details.
3. Include affected commit or version information, impact, reproduction steps,
   and any suggested mitigation in the private report.

## What to Expect

- The maintainer will triage reports on a best-effort basis during pre-alpha.
- Public disclosure should wait until the maintainer has had a reasonable
  opportunity to assess and mitigate the issue.
- Reports about OCR, screenshot capture, PDF parsing, image processing, or AI
  features are out of scope unless those features are later added.

## Security-Relevant Project Boundaries

The MVP is designed to use macOS Accessibility APIs for text inspection and to
copy user-selected plain text to the system clipboard after an explicit user
action. It should not request Screen Recording or broad input monitoring unless
a later reviewed decision changes that scope.
