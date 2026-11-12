# AgentOS Releases

This repository distributes approved AgentOS installation packages. The product
source repository remains private.

## Install AgentOS 2.0.10

```sh
curl -fsSL https://github.com/wutianle/agentos-releases/releases/download/v2.0.10/install.sh | sh
```

The installer checks archive size, SHA-256, platform, architecture, and package
identity. Signed update manifests are available through the stable and beta
channels. The stable channel points to the approved 2.0.10 release.

Target-specific offline bundles are available in the same release. Existing
configuration, conversations, attachments, and Skills remain outside the
versioned program directory during an upgrade.

## Published versions

Only explicitly approved beta versions and formal releases are published here.
Internal build candidates stay in private staging. Historical beta releases are
not installation entry points after the formal release migration is completed.

Core `2.0.10` is verified with AgentOS Runtime `1.0.1`, published separately
in [`runtime-v1.0.1`](https://github.com/wutianle/agentos-releases/releases/tag/runtime-v1.0.1).
The Runtime contains the Gateway and Codex/OpenCode bridges used by this release.
AgentOS prepares compatible local and Cube templates during the upgrade. Core and Runtime archives are not duplicated
between their release tags.

Release maintainers may use the existing manual import workflow to transfer
already accepted binary assets with an exact SHA-256 check. Candidate validation
must finish before any asset is uploaded to this public repository.
