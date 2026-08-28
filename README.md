# AgentOS Releases

This repository is the public distribution endpoint for AgentOS installation
assets. The AgentOS source repository remains private and no product source code
is published here.

Published assets are organized into two immutable release streams:

- `v<version>` contains the AgentOS Core archive, artifact metadata, release
  notes, and `install.sh`
- `runtime-v<version>` contains the platform-specific local sandbox and Cube
  Runtime archives plus their artifact metadata

Install a published Core version with HTTPS only:

```sh
curl -fsSL https://github.com/wutianle/agentos-releases/releases/download/v<version>/install.sh | sh
```

The installer does not require GitHub CLI or a GitHub account. Every archive is
validated against its published size and SHA-256 metadata before installation.
