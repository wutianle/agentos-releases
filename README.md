# AgentOS Releases

This repository distributes approved AgentOS installation packages. The product
source repository remains private.

## Install AgentOS 2.0.0

```sh
curl -fsSL https://github.com/wutianle/agentos-releases/releases/download/v2.0.0/install.sh | sh
```

The installer checks archive size, SHA-256, platform, architecture, and package
identity. Signed update manifests are available through the stable and beta
channels; both channels point to the approved 2.0.0 release at its launch.

Target-specific offline bundles are available in the same release. Existing
configuration, conversations, attachments, and Skills remain outside the
versioned program directory during an upgrade.

## Published versions

Only explicitly approved beta versions and formal releases are published here.
Internal build candidates stay in private staging. Historical beta releases are
not installation entry points after the formal release migration is completed.

Core 2.0.0 also hosts its verified Runtime dependencies. Their immutable component
identifiers remain local Runtime `1.0.0-beta.35` and Cube Runtime
`1.0.0-beta.34`; the archives are unchanged and are downloaded from the formal
`v2.0.0` release. This relocation does not rebuild existing sandbox templates or
change their identities.

Release maintainers may use the existing manual import workflow to transfer
already accepted binary assets with an exact SHA-256 check. Candidate validation
must finish before any asset is uploaded to this public repository.
