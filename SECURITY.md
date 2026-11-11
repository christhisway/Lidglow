# Security policy

Lidglow controls the lid logo through a private macOS framework (CoreBrightness) and can capture system audio and, if you choose it, the microphone. Please report anything that could let another app or person misuse those, or anything else that affects your Mac's security or privacy.

## Reporting a problem

**Please report it privately.** Don't open a public issue.

1. Go to the repository's **Security** tab and click **Report a vulnerability**. This opens a private advisory that only the maintainer can see.
2. Describe the problem, how to reproduce it, and the Lidglow version (**Settings → About**) and macOS version.

You'll get a reply as soon as the maintainer can manage. Lidglow is a free personal project, so there's no guaranteed response time. Once a fix is released, the advisory can be published with credit to you if you'd like.

## Supported versions

Only the latest release on [GitHub Releases](https://github.com/christhisway/Lidglow/releases) gets security fixes.

## Out of scope

- Lidglow has no network code, so it can't be attacked over the network, and it never sends anything anywhere. A report showing otherwise is very much in scope.
- A macOS update that stops logo control working is a compatibility bug, not a security problem. Please [open a normal issue](https://github.com/christhisway/Lidglow/issues/new/choose) for it.
