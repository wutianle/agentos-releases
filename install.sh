#!/bin/sh

set -eu

DEFAULT_VERSION="2.0.10"
DEFAULT_SANDBOX_RUNTIME_VERSION="1.0.1"
DEFAULT_SANDBOX_RUNTIME_TAG="runtime-v1.0.1"
DEFAULT_SANDBOX_RUNTIME_DIGEST_AMD64="8ffdc4de664e995983cf58b83908d0e5c28f7fbfd8aea92694400470ea777f1e"
DEFAULT_SANDBOX_RUNTIME_DIGEST_ARM64="55b8281068f86da1148df131cf613cd117e5424a027c440e99e15831276662ee"
MINIMUM_LINUX_GLIBC_VERSION="2.28"
AGENTOS_REPOSITORY="${AGENTOS_REPOSITORY:-wutianle/agentos-releases}"
AGENTOS_VERSION="${AGENTOS_VERSION:-$DEFAULT_VERSION}"
AGENTOS_SANDBOX_RUNTIME_VERSION="${AGENTOS_SANDBOX_RUNTIME_VERSION:-$DEFAULT_SANDBOX_RUNTIME_VERSION}"
AGENTOS_SANDBOX_RUNTIME_TAG="${AGENTOS_SANDBOX_RUNTIME_TAG:-}"
AGENTOS_SANDBOX_RUNTIME_DIGEST="${AGENTOS_SANDBOX_RUNTIME_DIGEST:-}"
AGENTOS_PREFIX="${AGENTOS_PREFIX:-}"
ENVIRONMENT_FILE="${AGENTOS_ENV_FILE:-}"
NO_LINK="${AGENTOS_NO_LINK:-0}"
SKIP_DOCTOR="${AGENTOS_SKIP_DOCTOR:-0}"
NO_START="${AGENTOS_NO_START:-0}"
SKIP_SANDBOX_RUNTIME="${AGENTOS_SKIP_SANDBOX_RUNTIME:-0}"
DRY_RUN="${AGENTOS_DRY_RUN:-0}"
VERBOSE="${AGENTOS_VERBOSE:-0}"
LOCAL_CORE_ARCHIVE="${AGENTOS_CORE_ARCHIVE:-}"
LOCAL_RUNTIME_ARCHIVE="${AGENTOS_RUNTIME_ARCHIVE:-}"
OFFLINE_BUNDLE="${AGENTOS_OFFLINE_BUNDLE:-}"
HEALTH_URL="${AGENTOS_HEALTH_URL:-}"
SANDBOX_HEALTH_URL="${AGENTOS_SANDBOX_HEALTH_URL:-http://127.0.0.1:4380/v1/health}"

usage() {
  cat <<'EOF'
AgentOS installer

Usage:
  install.sh [options]

Options:
  --version <version>  Install a specific Core release version
  --prefix <path>      Use a custom installation root
  --env-file <path>    Persist and reuse one AgentOS environment file
  --no-link            Do not create ~/.local/bin/agentos
  --no-doctor          Skip the post-install diagnostic
  --no-start           Install without starting the AgentOS user service
  --core-only          Install AgentOS without the local AgentOS Runtime
  --core <path>        Install Core from a local release archive
  --runtime <path>     Install AgentOS Runtime from a local release archive
  --offline <path>     Install Core and Runtime from one offline bundle
  --dry-run            Show the resolved installation without changing anything
  --verbose            Print shell commands while the installer runs
  -h, --help           Show this help

Examples:
  curl -fsSL https://example.com/install.sh | sh
  curl -fsSL https://example.com/install.sh | sh -s -- --version 2.0.0
  curl -fsSL https://example.com/install.sh | sh -s -- --prefix /opt/agentos
  ./install.sh --prefix /app/agentos/core \
    --env-file /app/agentos/config/agentos.env --core-only
  curl -fsSL https://example.com/install.sh | sh -s -- --core-only
  ./install.sh --core /path/agentos-2.0.0-darwin-arm64.tar.gz \
    --runtime /path/agentos-sandbox-runtime-1.0.1-darwin-arm64.tar.gz
  ./install.sh --offline /path/agentos-offline-bundle.tar.gz
EOF
}

fail() {
  printf 'AgentOS installation failed: %s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      [ "$#" -ge 2 ] || fail "--version requires a value."
      AGENTOS_VERSION="$2"
      shift 2
      ;;
    --prefix)
      [ "$#" -ge 2 ] || fail "--prefix requires a path."
      AGENTOS_PREFIX="$2"
      shift 2
      ;;
    --env-file)
      [ "$#" -ge 2 ] || fail "--env-file requires a path."
      ENVIRONMENT_FILE="$2"
      shift 2
      ;;
    --no-link)
      NO_LINK=1
      shift
      ;;
    --no-doctor)
      SKIP_DOCTOR=1
      shift
      ;;
    --no-start)
      NO_START=1
      shift
      ;;
    --core-only)
      SKIP_SANDBOX_RUNTIME=1
      shift
      ;;
    --core)
      [ "$#" -ge 2 ] || fail "--core requires a path."
      LOCAL_CORE_ARCHIVE="$2"
      shift 2
      ;;
    --runtime)
      [ "$#" -ge 2 ] || fail "--runtime requires a path."
      LOCAL_RUNTIME_ARCHIVE="$2"
      shift 2
      ;;
    --offline)
      [ "$#" -ge 2 ] || fail "--offline requires a path."
      OFFLINE_BUNDLE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1. Run with --help for supported options."
      ;;
  esac
done

if [ -n "$OFFLINE_BUNDLE" ] && { [ -n "$LOCAL_CORE_ARCHIVE" ] || [ -n "$LOCAL_RUNTIME_ARCHIVE" ]; }; then
  fail "--offline cannot be combined with --core or --runtime."
fi
if [ -n "$LOCAL_RUNTIME_ARCHIVE" ] && [ "$SKIP_SANDBOX_RUNTIME" = "1" ]; then
  fail "--runtime cannot be combined with --core-only."
fi

AGENTOS_VERSION="${AGENTOS_VERSION#v}"
[ -n "$AGENTOS_VERSION" ] || fail "The release version must not be empty."
AGENTOS_TAG="${AGENTOS_TAG:-v${AGENTOS_VERSION}}"
AGENTOS_SANDBOX_RUNTIME_VERSION="${AGENTOS_SANDBOX_RUNTIME_VERSION#v}"
[ -n "$AGENTOS_SANDBOX_RUNTIME_VERSION" ] || fail "The AgentOS Runtime version must not be empty."
if [ -z "$AGENTOS_SANDBOX_RUNTIME_TAG" ]; then
  if [ "$AGENTOS_REPOSITORY" = "wutianle/agentos-releases" ] && \
    [ "$AGENTOS_SANDBOX_RUNTIME_VERSION" = "$DEFAULT_SANDBOX_RUNTIME_VERSION" ]; then
    AGENTOS_SANDBOX_RUNTIME_TAG="$DEFAULT_SANDBOX_RUNTIME_TAG"
  else
    AGENTOS_SANDBOX_RUNTIME_TAG="runtime-v${AGENTOS_SANDBOX_RUNTIME_VERSION}"
  fi
fi

if [ "$VERBOSE" = "1" ]; then
  set -x
fi

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  bold="$(printf '\033[1m')"
  muted="$(printf '\033[2m')"
  reset="$(printf '\033[0m')"
else
  bold=""
  muted=""
  reset=""
fi

step() {
  printf '\n%s==>%s %s\n' "$bold" "$reset" "$*"
}

detail() {
  printf '    %s%s%s\n' "$muted" "$*" "$reset"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

resolve_local_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$(pwd)" "$1" ;;
  esac
}

validate_tar_archive_paths() {
  archive_to_validate="$1"
  tar -tzf "$archive_to_validate" | awk '
    BEGIN { valid = 1; count = 0 }
    {
      count += 1
      if ($0 ~ /^\// || $0 ~ /(^|\/)\.\.($|\/)/) valid = 0
    }
    END { exit (valid && count > 0) ? 0 : 1 }
  ' || fail "The offline archive contains an unsafe or empty file layout."
}

detect_platform() {
  case "$(uname -s)" in
    Darwin) printf 'darwin\n' ;;
    Linux) printf 'linux\n' ;;
    *) fail "Unsupported operating system: $(uname -s)" ;;
  esac
}

detect_core_architecture() {
  case "$(uname -m)" in
    arm64|aarch64) printf 'arm64\n' ;;
    x86_64|amd64) printf 'x64\n' ;;
    *) fail "Unsupported CPU architecture: $(uname -m)" ;;
  esac
}

detect_runtime_architecture() {
  case "$(uname -m)" in
    arm64|aarch64) printf 'arm64\n' ;;
    x86_64|amd64) printf 'amd64\n' ;;
    *) fail "Unsupported CPU architecture: $(uname -m)" ;;
  esac
}

detect_glibc_version() {
  if command -v getconf >/dev/null 2>&1; then
    detected_glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null || true)"
    case "$detected_glibc" in
      "glibc "*) printf '%s\n' "${detected_glibc#glibc }"; return ;;
    esac
  fi
  if command -v ldd >/dev/null 2>&1; then
    detected_glibc="$(ldd --version 2>&1 | awk 'NR == 1 {
      for (field = 1; field <= NF; field += 1) {
        if ($field ~ /^[0-9]+\.[0-9]+([.][0-9]+)?$/) {
          print $field
          exit
        }
      }
    }')"
    [ -n "$detected_glibc" ] && printf '%s\n' "$detected_glibc"
  fi
}

require_linux_glibc_baseline() {
  [ "$platform" = "linux" ] || return 0
  detected_glibc="$(detect_glibc_version)"
  [ -n "$detected_glibc" ] || fail "AgentOS Linux packages require glibc ${MINIMUM_LINUX_GLIBC_VERSION} or newer; this system does not report a supported glibc runtime."
  awk -v detected="$detected_glibc" -v minimum="$MINIMUM_LINUX_GLIBC_VERSION" 'BEGIN {
    detected_count = split(detected, detected_parts, ".")
    minimum_count = split(minimum, minimum_parts, ".")
    count = detected_count > minimum_count ? detected_count : minimum_count
    for (position = 1; position <= count; position += 1) {
      detected_part = detected_parts[position] == "" ? 0 : detected_parts[position] + 0
      minimum_part = minimum_parts[position] == "" ? 0 : minimum_parts[position] + 0
      if (detected_part > minimum_part) exit 0
      if (detected_part < minimum_part) exit 1
    }
    exit 0
  }' || fail "AgentOS Linux packages require glibc ${MINIMUM_LINUX_GLIBC_VERSION} or newer; detected ${detected_glibc}."
}

resolve_installation_root() {
  if [ -n "$AGENTOS_PREFIX" ]; then
    case "$AGENTOS_PREFIX" in
      /*) printf '%s\n' "$AGENTOS_PREFIX" ;;
      *) printf '%s/%s\n' "$(pwd)" "$AGENTOS_PREFIX" ;;
    esac
    return
  fi
  printf '%s/.local/share/agentos\n' "$HOME"
}

resolve_environment_file() {
  [ -n "$ENVIRONMENT_FILE" ] || return 0
  resolve_local_path "$ENVIRONMENT_FILE"
}

print_download_progress() {
  current_bytes="$1"
  total_bytes="$2"
  awk -v current="$current_bytes" -v total="$total_bytes" 'BEGIN {
    width = 28
    percent = total > 0 ? int(current * 100 / total) : 0
    if (percent > 100) percent = 100
    filled = int(percent * width / 100)
    printf "\r    ["
    for (position = 0; position < width; position++) {
      printf "%s", (position < filled ? "=" : " ")
    }
    printf "] %3d%%  %.1f / %.1f MiB", percent, current / 1048576, total / 1048576
  }'
}

monitor_download() {
  monitored_pid="$1"
  monitored_path="$2"
  monitored_size="$3"
  while kill -0 "$monitored_pid" 2>/dev/null; do
    if [ -f "$monitored_path" ]; then
      monitored_bytes="$(wc -c < "$monitored_path" | tr -d '[:space:]')"
    else
      monitored_bytes=0
    fi
    print_download_progress "$monitored_bytes" "$monitored_size"
    sleep 1
  done
}

run_asset_download() {
  curl_asset_url="$1"
  curl_destination="$2"
  curl_expected_size="$3"
  curl_resume="$4"
  curl_log="${curl_destination}.download.log"
  set -- \
    --fail --location --silent --show-error \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --retry 0 --connect-timeout 15 --speed-limit 1 --speed-time 60 \
    --output "$curl_destination"
  case "$curl_asset_url" in
    https://api.github.com/*) set -- "$@" --header 'Accept: application/octet-stream' ;;
  esac
  if [ "$curl_resume" = "1" ] && [ -s "$curl_destination" ]; then
    set -- "$@" --continue-at -
  fi
  curl_status=0
  if [ -n "$curl_expected_size" ] && [ -t 1 ]; then
    curl "$@" "$curl_asset_url" >"$curl_log" 2>&1 &
    download_pid=$!
    monitor_download "$download_pid" "$curl_destination" "$curl_expected_size"
    if wait "$download_pid"; then
      print_download_progress "$curl_expected_size" "$curl_expected_size"
    else
      curl_status=$?
    fi
    download_pid=""
    printf '\n'
  elif curl "$@" "$curl_asset_url" >"$curl_log" 2>&1; then
    return 0
  else
    curl_status=$?
  fi
  return "$curl_status"
}

resolve_github_api_asset() {
  api_download_node="${installation_root}/current/node/bin/node"
  if [ ! -x "$api_download_node" ]; then
    api_download_node="$(command -v node 2>/dev/null || true)"
  fi
  if [ -z "$api_download_node" ]; then
    printf '%s\n' 'GitHub API fallback needs an installed AgentOS or Node.js for safe JSON parsing. Use an offline package on a new machine without Node.js.' >&2
    return 1
  fi
  api_metadata_url="$("$api_download_node" --input-type=module - "$AGENTOS_REPOSITORY" "$1" <<'EOF'
const [repository, tag] = process.argv.slice(2);
if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository)) throw new Error("Invalid GitHub repository");
console.log(`https://api.github.com/repos/${repository}/releases/tags/${encodeURIComponent(tag)}`);
EOF
  )" || return 1
  api_metadata_path="${3}.github-release.json"
  # Public release fallback is anonymous; no credential can follow a redirect.
  if ! curl --fail --location --silent --show-error \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 15 --max-time 30 \
    --header 'Accept: application/vnd.github+json' \
    --output "$api_metadata_path" "$api_metadata_url"; then
    rm -f "$api_metadata_path"
    return 1
  fi
  api_resolve_status=0
  "$api_download_node" --input-type=module - \
    "$api_metadata_path" "$2" "${4:-}" "${5:-}" "$AGENTOS_REPOSITORY" <<'EOF' || api_resolve_status=$?
import { readFileSync } from "node:fs";
const [file, name, expectedSize, expectedSha256, repository] = process.argv.slice(2);
const release = JSON.parse(readFileSync(file, "utf8"));
const matches = Array.isArray(release.assets) ? release.assets.filter((entry) => entry?.name === name) : [];
if (matches.length !== 1) throw new Error("GitHub release asset is missing or ambiguous");
const asset = matches[0];
if (!Number.isSafeInteger(asset.id) || asset.id <= 0) throw new Error("Invalid GitHub asset ID");
if (expectedSize && asset.size !== Number(expectedSize)) throw new Error("GitHub asset size differs from release metadata");
if (expectedSha256 && asset.digest != null && asset.digest !== `sha256:${expectedSha256}`) throw new Error("GitHub asset digest differs from release metadata");
console.log(`https://api.github.com/repos/${repository}/releases/assets/${asset.id}`);
EOF
  rm -f "$api_metadata_path"
  return "$api_resolve_status"
}

download_asset() {
  download_release_tag="$1"
  download_asset_name="$2"
  download_destination="$3"
  expected_download_size="${4:-}"
  resumable_download="${5:-0}"
  expected_download_sha256="${6:-}"
  download_log="${download_destination}.download.log"
  download_source="${download_destination}.source"
  require_command curl
  download_routes="direct api"
  saved_download_source="$(cat "$download_source" 2>/dev/null || true)"
  case "$saved_download_source" in
    "https://api.github.com/repos/${AGENTOS_REPOSITORY}/releases/assets/"*) download_routes="api direct" ;;
  esac
  for download_route in $download_routes; do
    if [ "$download_route" = "api" ]; then
      detail "Trying the official GitHub release asset API"
      if ! asset_url="$(resolve_github_api_asset \
        "$download_release_tag" "$download_asset_name" "$download_destination" \
        "$expected_download_size" "$expected_download_sha256")"; then
        continue
      fi
    else
      asset_url="https://github.com/${AGENTOS_REPOSITORY}/releases/download/${download_release_tag}/${download_asset_name}"
    fi
    source_identity="${asset_url}|${expected_download_sha256}"
    resumed_existing_download=0
    if [ "$resumable_download" = "1" ]; then
      if [ -s "$download_destination" ] && [ "$saved_download_source" = "$source_identity" ]; then
        resumed_existing_download=1
      else
        rm -f "$download_destination"
      fi
      printf '%s\n' "$source_identity" > "$download_source"
      saved_download_source="$source_identity"
    fi
    download_status=0
    if run_asset_download "$asset_url" "$download_destination" "$expected_download_size" "$resumed_existing_download"; then
      rm -f "$download_log" "$download_source"
      return
    else
      download_status=$?
    fi
    if [ "$resumed_existing_download" = "1" ] && \
      { [ "$download_status" = "33" ] || [ "$download_status" = "36" ]; }; then
      detail "The server rejected the saved byte range; restarting this asset once"
      rm -f "$download_destination"
      if run_asset_download "$asset_url" "$download_destination" "$expected_download_size" 0; then
        rm -f "$download_log" "$download_source"
        return
      fi
    fi
    cat "$download_log" >&2
  done
  rm -f "$download_log"
  if [ "$resumable_download" = "1" ] && [ -s "$download_destination" ]; then
    saved_download_bytes="$(wc -c < "$download_destination" | tr -d '[:space:]')"
    fail "Could not download ${download_asset_name}. Partial download saved at ${download_destination} (${saved_download_bytes}/${expected_download_size} bytes). Run the same install command again to continue."
  fi
  fail "Could not download ${download_asset_name} over HTTPS. Confirm that the release asset is accessible."
}

acquire_download_cache_lock() {
  requested_download_lock="$1"
  if ! mkdir "$requested_download_lock" 2>/dev/null; then
    existing_download_pid="$(cat "${requested_download_lock}/pid" 2>/dev/null || true)"
    if printf '%s\n' "$existing_download_pid" | grep -Eq '^[0-9]+$' && \
      kill -0 "$existing_download_pid" 2>/dev/null; then
      fail "Another AgentOS installer is downloading this release asset."
    fi
    rm -rf "$requested_download_lock"
    mkdir "$requested_download_lock" || fail "Could not acquire the release download cache lock."
  fi
  printf '%s\n' "$$" >"${requested_download_lock}/pid"
  download_lock_dir="$requested_download_lock"
}

release_download_cache_lock() {
  [ -n "${download_lock_dir:-}" ] || return 0
  rm -rf "$download_lock_dir"
  download_lock_dir=""
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
    return
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | sed 's/^.*= //'
    return
  fi
  fail "sha256sum, shasum, or openssl is required to verify the download."
}

verify_checksum_manifest() {
  checksum_root="$1"
  checksum_manifest="$2"
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$checksum_root" && sha256sum --status -c "$checksum_manifest")
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    (cd "$checksum_root" && shasum -a 256 --status -c "$checksum_manifest")
    return
  fi
  fail "sha256sum or shasum is required to verify the installed release."
}

read_artifact_metadata() {
  metadata_file="$1"
  expected_file_name="$2"
  expected_kind="$3"
  expected_platform="$4"
  expected_architecture="$5"
  artifact_sha256="$(awk -F'"' '/"sha256"[[:space:]]*:/ { print $4; exit }' "$metadata_file")"
  artifact_size="$(sed -n 's/.*"sizeBytes"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$metadata_file" | head -n 1)"
  artifact_file_name="$(awk -F'"' '/"fileName"[[:space:]]*:/ { print $4; exit }' "$metadata_file")"
  artifact_kind="$(awk -F'"' '/"kind"[[:space:]]*:/ { print $4; exit }' "$metadata_file")"
  artifact_platform="$(awk -F'"' '/"platform"[[:space:]]*:/ { print $4; exit }' "$metadata_file")"
  artifact_architecture="$(awk -F'"' '/"architecture"[[:space:]]*:/ { print $4; exit }' "$metadata_file")"
  printf '%s\n' "$artifact_sha256" | grep -Eq '^[0-9a-f]{64}$' || fail "Release metadata contains an invalid SHA-256."
  printf '%s\n' "$artifact_size" | grep -Eq '^[0-9]+$' || fail "Release metadata contains an invalid file size."
  [ "$artifact_file_name" = "$expected_file_name" ] || fail "Release metadata does not match ${expected_file_name}."
  [ "$artifact_kind" = "$expected_kind" ] || fail "Release metadata has unexpected artifact kind: ${artifact_kind:-missing}."
  [ "$artifact_platform" = "$expected_platform" ] || fail "Release metadata has unexpected platform: ${artifact_platform:-missing}."
  [ "$artifact_architecture" = "$expected_architecture" ] || fail "Release metadata has unexpected architecture: ${artifact_architecture:-missing}."
}

download_verified_release_asset() {
  verified_release_tag="$1"
  verified_asset_name="$2"
  verified_metadata_name="$3"
  verified_asset_path="$4"
  verified_metadata_path="$5"
  verified_artifact_label="$6"
  verified_expected_kind="$7"
  verified_expected_platform="$8"
  verified_expected_architecture="$9"

  step "Resolving ${verified_artifact_label}"
  download_asset "$verified_release_tag" "$verified_metadata_name" "$verified_metadata_path"
  read_artifact_metadata \
    "$verified_metadata_path" "$verified_asset_name" "$verified_expected_kind" \
    "$verified_expected_platform" "$verified_expected_architecture"
  artifact_size_mib="$(awk -v bytes="$artifact_size" 'BEGIN { printf "%.1f", bytes / 1048576 }')"
  mkdir -p "$download_cache_root"
  verified_cache_path="${download_cache_root}/${artifact_sha256}-${verified_asset_name}"
  verified_partial_path="${verified_cache_path}.partial"
  acquire_download_cache_lock "${verified_cache_path}.lock"

  verified_cache_ready=0
  if [ -f "$verified_cache_path" ]; then
    cached_size="$(wc -c < "$verified_cache_path" | tr -d '[:space:]')"
    cached_sha256="$(sha256_file "$verified_cache_path")"
    if [ "$cached_size" = "$artifact_size" ] && [ "$cached_sha256" = "$artifact_sha256" ]; then
      verified_cache_ready=1
      step "Using cached ${verified_asset_name}"
    else
      detail "Discarding an invalid completed download cache entry"
      rm -f "$verified_cache_path"
    fi
  fi

  if [ "$verified_cache_ready" = "0" ] && [ -f "$verified_partial_path" ]; then
    partial_size="$(wc -c < "$verified_partial_path" | tr -d '[:space:]')"
    if [ "$partial_size" -gt "$artifact_size" ]; then
      detail "Discarding an oversized partial download"
      rm -f "$verified_partial_path"
    elif [ "$partial_size" = "$artifact_size" ]; then
      partial_sha256="$(sha256_file "$verified_partial_path")"
      if [ "$partial_sha256" = "$artifact_sha256" ]; then
        mv "$verified_partial_path" "$verified_cache_path"
        verified_cache_ready=1
        step "Using completed cached ${verified_asset_name}"
      else
        detail "Discarding a completed partial download with an invalid SHA-256"
        rm -f "$verified_partial_path"
      fi
    elif [ "$partial_size" -gt 0 ]; then
      partial_size_mib="$(awk -v bytes="$partial_size" 'BEGIN { printf "%.1f", bytes / 1048576 }')"
      detail "Resuming the saved download at ${partial_size_mib} / ${artifact_size_mib} MiB"
    fi
  fi

  if [ "$verified_cache_ready" = "0" ]; then
    step "Downloading ${verified_asset_name} (${artifact_size_mib} MiB)"
    detail "The download may take a few minutes"
    download_asset \
      "$verified_release_tag" "$verified_asset_name" "$verified_partial_path" \
      "$artifact_size" 1 "$artifact_sha256"
    downloaded_sha256="$(sha256_file "$verified_partial_path")"
    downloaded_size="$(wc -c < "$verified_partial_path" | tr -d '[:space:]')"
    if [ "$downloaded_sha256" != "$artifact_sha256" ] || [ "$downloaded_size" != "$artifact_size" ]; then
      rm -f "$verified_partial_path"
      release_download_cache_lock
      fail "${verified_artifact_label} download cache verification failed; the invalid partial file was removed."
    fi
    mv "$verified_partial_path" "$verified_cache_path"
  fi

  cp "$verified_cache_path" "$verified_asset_path"
  release_download_cache_lock

  step "Verifying ${verified_artifact_label}"
  actual_sha256="$(sha256_file "$verified_asset_path")"
  actual_size="$(wc -c < "$verified_asset_path" | tr -d '[:space:]')"
  [ "$actual_sha256" = "$artifact_sha256" ] || fail "${verified_artifact_label} SHA-256 verification failed."
  [ "$actual_size" = "$artifact_size" ] || fail "${verified_artifact_label} size verification failed."
  detail "SHA-256: ${actual_sha256}"
}

sandbox_runtime_installed_version() {
  runtime_manifest="$(sandbox_runtime_release_manifest_path)"
  [ -f "$runtime_manifest" ] || return 1
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$runtime_manifest" | head -n 1
}

sandbox_runtime_installed_digest() {
  runtime_manifest="$(sandbox_runtime_release_manifest_path)"
  [ -f "$runtime_manifest" ] || return 1
  sed -n 's/.*"runtimeDigest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$runtime_manifest" | head -n 1
}

sandbox_runtime_release_manifest_path() {
  case "${platform:-}" in
    darwin) printf '%s/.agentos/sandbox-vmm/release-manifest.json\n' "$HOME" ;;
    linux) printf '/usr/lib/agentos/sandbox-vmm/release-manifest.json\n' ;;
    *) return 1 ;;
  esac
}

sandbox_runtime_is_current() {
  [ "$(sandbox_runtime_installed_version 2>/dev/null || true)" = "$AGENTOS_SANDBOX_RUNTIME_VERSION" ] || return 1
  if [ -n "$AGENTOS_SANDBOX_RUNTIME_DIGEST" ]; then
    [ "$(sandbox_runtime_installed_digest 2>/dev/null || true)" = "$AGENTOS_SANDBOX_RUNTIME_DIGEST" ] || return 1
  fi
  case "$platform" in
    darwin)
      sandbox_executable="${HOME}/.agentos/sandbox-vmm/bin/agentos-sandbox-vmm"
      sandbox_image_root="${HOME}/.agentos/sandbox-vmm/images"
      ;;
    linux)
      sandbox_executable="/usr/lib/agentos/sandbox-vmm/agentos-sandbox-vmm"
      ;;
    *) return 1 ;;
  esac
  [ -x "$sandbox_executable" ] || return 1
  if [ "$platform" = "linux" ]; then
    return 0
  fi
  [ -f "${sandbox_image_root}/official-local-runtime-source.json" ] || return 1
  [ -f "${sandbox_image_root}/agentos-harness-runtime.ext4" ] || return 1
  [ -f "${sandbox_image_root}/vmlinux" ] || return 1
  [ -f "${sandbox_image_root}/initramfs.img" ] || return 1
}

verify_core_release_archive() {
  core_archive_to_verify="$1"
  core_verification_root="${temporary_root}/verify-core"
  rm -rf "$core_verification_root"
  mkdir -p "$core_verification_root"
  validate_tar_archive_paths "$core_archive_to_verify"
  tar -xzf "$core_archive_to_verify" -C "$core_verification_root"
  core_package_root="${core_verification_root}/${package_name}"
  core_manifest="${core_package_root}/release-package.json"
  [ -f "$core_manifest" ] || fail "The Core archive does not contain release-package.json."
  core_manifest_version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$core_manifest" | head -n 1)"
  core_manifest_platform="$(sed -n 's/.*"platform"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$core_manifest" | head -n 1)"
  core_manifest_architecture="$(sed -n 's/.*"architecture"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$core_manifest" | head -n 1)"
  [ "$core_manifest_version" = "$AGENTOS_VERSION" ] || fail "Core archive version ${core_manifest_version:-missing} does not match ${AGENTOS_VERSION}."
  [ "$core_manifest_platform" = "$platform" ] || fail "Core archive platform ${core_manifest_platform:-missing} does not match ${platform}."
  [ "$core_manifest_architecture" = "$architecture" ] || fail "Core archive architecture ${core_manifest_architecture:-missing} does not match ${architecture}."
  [ -x "${core_package_root}/node/bin/node" ] || fail "The Core archive does not contain its bundled Node.js runtime."
  [ -f "${core_package_root}/install/install.mjs" ] || fail "The Core archive does not contain the AgentOS installer."
  rm -rf "$core_verification_root"
}

verify_sandbox_runtime_archive() {
  runtime_archive_to_verify="$1"
  runtime_verification_root="${temporary_root}/verify-runtime"
  rm -rf "$runtime_verification_root"
  mkdir -p "$runtime_verification_root"
  validate_tar_archive_paths "$runtime_archive_to_verify"
  tar -xzf "$runtime_archive_to_verify" -C "$runtime_verification_root"
  runtime_package_root="${runtime_verification_root}/${sandbox_runtime_package_name}"
  runtime_manifest="${runtime_package_root}/release-manifest.json"
  [ -f "$runtime_manifest" ] || fail "The AgentOS Runtime archive does not contain release-manifest.json."
  runtime_manifest_version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$runtime_manifest" | head -n 1)"
  runtime_manifest_platform="$(sed -n 's/.*"platform"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$runtime_manifest" | head -n 1)"
  runtime_manifest_architecture="$(sed -n 's/.*"architecture"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$runtime_manifest" | head -n 1)"
  [ "$runtime_manifest_version" = "$AGENTOS_SANDBOX_RUNTIME_VERSION" ] || fail "AgentOS Runtime version ${runtime_manifest_version:-missing} does not match ${AGENTOS_SANDBOX_RUNTIME_VERSION}."
  [ "$runtime_manifest_platform" = "$platform" ] || fail "AgentOS Runtime platform ${runtime_manifest_platform:-missing} does not match ${platform}."
  [ "$runtime_manifest_architecture" = "$runtime_architecture" ] || fail "AgentOS Runtime architecture ${runtime_manifest_architecture:-missing} does not match ${runtime_architecture}."
  case "$platform" in
    darwin)
      [ -x "${runtime_package_root}/deploy/macos/install.sh" ] || fail "The AgentOS Runtime archive does not contain its macOS installer."
      ;;
  esac
  rm -rf "$runtime_verification_root"
}

find_offline_bundle_asset() {
  offline_root="$1"
  offline_name="$2"
  offline_matches="$(find "$offline_root" -type f -name "$offline_name" -print)"
  offline_match_count="$(printf '%s\n' "$offline_matches" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  [ "$offline_match_count" = "1" ] || fail "The offline bundle must contain exactly one ${offline_name}."
  printf '%s\n' "$offline_matches"
}

xml_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&apos;/g"
}

install_macos_user_service() {
  require_command id
  require_command launchctl
  require_command plutil
  service_label="com.agentos.server"
  service_domain="gui/$(id -u)"
  service_root="${HOME}/Library/LaunchAgents"
  service_path="${service_root}/${service_label}.plist"
  legacy_sandbox_service_path="${service_root}/com.agentos.sandbox-vmm.plist"
  service_log_root="${installation_root}/logs"
  mkdir -p "$service_root" "$service_log_root"

  escaped_launcher="$(xml_escape "$launcher")"
  escaped_home="$(xml_escape "$HOME")"
  escaped_output="$(xml_escape "${service_log_root}/server.log")"
  escaped_error="$(xml_escape "${service_log_root}/server-error.log")"
  managed_sandbox_environment=""
  if [ "$SKIP_SANDBOX_RUNTIME" = "1" ]; then
    managed_sandbox_environment='    <key>AGENTOS_MANAGE_LOCAL_SANDBOX</key>
    <string>false</string>'
  fi
  service_staging_path="${service_path}.staging.$$"
  cat >"$service_staging_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${service_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${escaped_launcher}</string>
    <string>start</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>${escaped_home}</string>
    <key>USERPROFILE</key>
    <string>${escaped_home}</string>
${managed_sandbox_environment}
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
  <key>ExitTimeOut</key>
  <integer>960</integer>
  <key>StandardOutPath</key>
  <string>${escaped_output}</string>
  <key>StandardErrorPath</key>
  <string>${escaped_error}</string>
</dict>
</plist>
EOF
  chmod 644 "$service_staging_path"
  plutil -lint "$service_staging_path" >/dev/null
  mv "$service_staging_path" "$service_path"

  launchctl bootout "${service_domain}/com.agentos.sandbox-vmm" >/dev/null 2>&1 || true
  rm -f "$legacy_sandbox_service_path"
  stop_agentos_service
  service_bootstrap_error="${service_log_root}/launchctl-bootstrap.$$.log"
  service_bootstrapped=0
  service_bootstrap_attempt=0
  while [ "$service_bootstrap_attempt" -lt 100 ]; do
    if launchctl bootstrap "$service_domain" "$service_path" 2>"$service_bootstrap_error"; then
      service_bootstrapped=1
      break
    fi
    service_bootstrap_attempt=$((service_bootstrap_attempt + 1))
    sleep 0.2
  done
  if [ "$service_bootstrapped" != "1" ]; then
    cat "$service_bootstrap_error" >&2 || true
    rm -f "$service_bootstrap_error"
    fail "Could not register the AgentOS LaunchAgent at ${service_path}."
  fi
  rm -f "$service_bootstrap_error"
  launchctl enable "${service_domain}/${service_label}" >/dev/null 2>&1 || true
  if ! launchctl kickstart -k "${service_domain}/${service_label}"; then
    fail "Could not start the AgentOS LaunchAgent."
  fi
}

install_linux_user_service() {
  require_command systemctl
  require_command loginctl
  require_command id
  service_user="$(id -un)"
  linger_state="$(loginctl show-user "$service_user" --property=Linger 2>/dev/null | sed -n 's/^Linger=//p')"
  if [ "$linger_state" != "yes" ]; then
    step "Enabling persistent AgentOS service"
    linger_enabled=0
    if loginctl enable-linger "$service_user" >/dev/null 2>&1; then
      linger_enabled=1
    elif command -v sudo >/dev/null 2>&1 && sudo loginctl enable-linger "$service_user"; then
      linger_enabled=1
    fi
    if [ "$linger_enabled" != "1" ]; then
      fail "AgentOS could not enable persistent user services. Run 'sudo loginctl enable-linger ${service_user}' and retry, or install with --no-start when another service manager owns AgentOS."
    fi
    linger_state="$(loginctl show-user "$service_user" --property=Linger 2>/dev/null | sed -n 's/^Linger=//p')"
    [ "$linger_state" = "yes" ] || fail "AgentOS enabled user lingering, but systemd still reports Linger=${linger_state:-unknown} for ${service_user}."
  fi
  service_root="${HOME}/.config/systemd/user"
  service_path="${service_root}/agentos.service"
  service_log_root="${installation_root}/logs"
  mkdir -p "$service_root" "$service_log_root"
  service_staging_path="${service_path}.staging.$$"
  cat >"$service_staging_path" <<EOF
[Unit]
Description=AgentOS
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart="${launcher}" start
Restart=always
RestartSec=1
KillMode=mixed
TimeoutStopSec=960
Environment="HOME=${HOME}"
Environment="USERPROFILE=${HOME}"
Environment=AGENTOS_MANAGE_LOCAL_SANDBOX=false
StandardOutput=append:${service_log_root}/server.log
StandardError=append:${service_log_root}/server-error.log

[Install]
WantedBy=default.target
EOF
  chmod 644 "$service_staging_path"
  mv "$service_staging_path" "$service_path"
  systemctl --user daemon-reload
  systemctl --user enable agentos.service >/dev/null
  systemctl --user restart agentos.service
  detail "Service persistence: enabled for ${service_user}"
}

wait_for_agentos_health() {
  bundled_node="${installation_root}/current/node/bin/node"
  [ -x "$bundled_node" ] || fail "The installed Node.js runtime is unavailable."
  resolved_health_url="$HEALTH_URL"
  if [ -z "$resolved_health_url" ]; then
    resolved_environment_file="${ENVIRONMENT_FILE:-}"
    if [ -z "$resolved_environment_file" ] && [ -f "${installation_root}/installation.json" ]; then
      resolved_environment_file="$($bundled_node --input-type=module - "${installation_root}/installation.json" <<'EOF'
import { readFile } from "node:fs/promises";
const metadata = JSON.parse(await readFile(process.argv[2], "utf8"));
process.stdout.write(typeof metadata.environmentFile === "string" ? metadata.environmentFile : "");
EOF
)"
    fi
    resolved_health_url="$($bundled_node --input-type=module - "$resolved_environment_file" <<'EOF'
import { existsSync } from "node:fs";
import { loadEnvFile } from "node:process";

const environmentPath = process.argv[2]?.trim();
if (environmentPath && existsSync(environmentPath)) loadEnvFile(environmentPath);
const configuredHost = process.env.AGENTOS_HOST?.trim() || "127.0.0.1";
const host = configuredHost === "0.0.0.0"
  ? "127.0.0.1"
  : configuredHost === "::" || configuredHost === "[::]"
    ? "::1"
    : configuredHost;
const port = process.env.AGENTOS_PORT?.trim() || "4174";
const formattedHost = host.includes(":") && !host.startsWith("[") ? `[${host}]` : host;
process.stdout.write(`http://${formattedHost}:${port}/health`);
EOF
)"
  fi
  if "$bundled_node" - "$resolved_health_url" <<'EOF'
const healthUrl = process.argv[2];
const deadline = Date.now() + 90_000;
while (Date.now() < deadline) {
  try {
    const response = await fetch(healthUrl, { signal: AbortSignal.timeout(1_500) });
    const body = await response.json();
    if (response.ok && body?.ok === true) process.exit(0);
  } catch {}
  await new Promise((resolve) => setTimeout(resolve, 1_000));
}
process.exit(1);
EOF
  then
    return
  fi
  service_log_root="${installation_root}/logs"
  if [ -f "${service_log_root}/server-error.log" ]; then
    tail -n 30 "${service_log_root}/server-error.log" >&2 || true
  fi
  if [ -f "${service_log_root}/server.log" ]; then
    tail -n 30 "${service_log_root}/server.log" >&2 || true
  fi
  if [ "${platform:-}" = "darwin" ] && [ -n "${service_domain:-}" ]; then
    launchctl bootout "${service_domain}/${service_label}" >/dev/null 2>&1 || true
  fi
  if [ "${platform:-}" = "linux" ]; then
    systemctl --user stop agentos.service >/dev/null 2>&1 || true
  fi
  fail "AgentOS did not become healthy at ${resolved_health_url}."
}

wait_for_sandbox_health() {
  bundled_node="${installation_root}/current/node/bin/node"
  [ -x "$bundled_node" ] || fail "The installed Node.js runtime is unavailable."
  if "$bundled_node" - "$SANDBOX_HEALTH_URL" <<'EOF'
const healthUrl = process.argv[2];
const deadline = Date.now() + 90_000;
while (Date.now() < deadline) {
  try {
    const response = await fetch(healthUrl, { signal: AbortSignal.timeout(1_500) });
    const body = await response.json();
    if (response.ok && body?.available === true) process.exit(0);
  } catch {}
  await new Promise((resolve) => setTimeout(resolve, 500));
}
process.exit(1);
EOF
  then
    detail "Sandbox: ready at http://127.0.0.1:4380"
    return
  fi
  fail "AgentOS started, but the managed macOS sandbox did not become healthy at ${SANDBOX_HEALTH_URL}."
}

# The user-service name is shared across installations. A custom --prefix is
# not permission to stop or replace another installation's service.
registered_agentos_launcher() {
  registered_launcher=""
  case "${platform:-}" in
    darwin)
      registered_description="$(launchctl print "gui/$(id -u)/com.agentos.server" 2>/dev/null || true)"
      if [ -n "$registered_description" ]; then
        registered_launcher="$(printf '%s\n' "$registered_description" | sed -n 's/^[[:space:]]*program = //p')"
        [ -n "$registered_launcher" ] || registered_launcher="unknown"
      elif [ -f "${HOME}/Library/LaunchAgents/com.agentos.server.plist" ]; then
        registered_launcher="$(plutil -extract ProgramArguments.0 raw -o - "${HOME}/Library/LaunchAgents/com.agentos.server.plist" 2>/dev/null || true)"
        [ -n "$registered_launcher" ] || registered_launcher="unknown"
      fi
      ;;
    linux)
      registered_description="$(systemctl --user show --property=ExecStart --value agentos.service 2>/dev/null || true)"
      if [ -n "$registered_description" ]; then
        registered_launcher="$(printf '%s\n' "$registered_description" | sed -n 's/^{ path=\([^;]*\) ; argv\[\]=.*$/\1/p')"
        [ -n "$registered_launcher" ] || registered_launcher="unknown"
      elif [ -f "${HOME}/.config/systemd/user/agentos.service" ]; then
        registered_launcher="$(sed -n 's/^ExecStart="\(.*\)" start$/\1/p' "${HOME}/.config/systemd/user/agentos.service")"
        [ -n "$registered_launcher" ] || registered_launcher="unknown"
      fi
      ;;
  esac
  printf '%s\n' "$registered_launcher"
}

check_agentos_service_target() {
  registered_owner="$(registered_agentos_launcher)"
  if [ -n "$registered_owner" ] && [ "$registered_owner" != "$launcher" ]; then
    if [ "$NO_START" != "1" ]; then
      fail "The user service belongs to another AgentOS installation (or its owner cannot be verified). Use --core-only --no-start --no-link for an isolated installation."
    fi
    if [ "${install_sandbox_runtime:-0}" = "1" ]; then
      fail "The shared Runtime is used by another AgentOS installation. Use --core-only for an isolated installation."
    fi
  fi
}

stop_agentos_service() {
  check_agentos_service_target
  # --no-start may still upgrade files belonging to this service, so stop an
  # exact owner before replacement. Unknown/foreign ownership is never adopted.
  [ "$(registered_agentos_launcher)" = "$launcher" ] || return 0
  case "${platform:-}" in
    darwin)
      stop_domain="gui/$(id -u)"
      stop_description="$(launchctl print "${stop_domain}/com.agentos.server" 2>/dev/null || true)"
      stop_pid="$(printf '%s\n' "$stop_description" | sed -n 's/^[[:space:]]*pid = //p')"
      case "$stop_pid" in
        0|*[!0-9]*) fail "Cannot verify the old AgentOS service process; installation was not changed." ;;
      esac
      launchctl bootout "${stop_domain}/com.agentos.server" >/dev/null 2>&1 || true
      if [ -n "$stop_pid" ]; then
        # bootout removes the launchd name before the supervised Core and VMM
        # have finished saving work. Keep their installed files intact until
        # the exact old supervisor exits, within the service's shutdown budget.
        detail "Waiting for the old AgentOS service to finish saving work"
        stop_deadline=$(( $(date +%s) + 960 ))
        while kill -0 "$stop_pid" 2>/dev/null; do
          if [ "$(date +%s)" -ge "$stop_deadline" ]; then
            fail "The old AgentOS process did not exit; installation stopped before replacing files."
          fi
          sleep 0.2
        done
      fi
      ;;
    linux)
      systemctl --user stop agentos.service >/dev/null 2>&1 || true
      ;;
  esac
}

start_agentos_service() {
  check_agentos_service_target
  case "$platform" in
    darwin)
      install_macos_user_service
      ;;
    linux)
      install_linux_user_service
      ;;
  esac
  wait_for_agentos_health
}

install_sandbox_runtime_release() {
  runtime_archive_path="$1"
  runtime_package_name="$2"
  runtime_extract_root="$3"
  step "Installing AgentOS Runtime"
  tar -xzf "$runtime_archive_path" -C "$runtime_extract_root"
  runtime_package_root="${runtime_extract_root}/${runtime_package_name}"
  case "$platform" in
    darwin)
      runtime_installer="${runtime_package_root}/deploy/macos/install.sh"
      [ -x "$runtime_installer" ] || fail "The AgentOS Runtime release does not contain its macOS installer."
      "$runtime_installer" --managed
      ;;
    linux)
      runtime_installer="${runtime_package_root}/deploy/install.sh"
      [ -x "$runtime_installer" ] || fail "The AgentOS Runtime release does not contain its Linux installer."
      if [ "$(id -u)" = "0" ]; then
        "$runtime_installer"
      else
        require_command sudo
        sudo "$runtime_installer"
      fi
      ;;
  esac
}

platform="$(detect_platform)"
architecture="$(detect_core_architecture)"
runtime_architecture="$(detect_runtime_architecture)"
require_linux_glibc_baseline
if [ -z "$AGENTOS_SANDBOX_RUNTIME_DIGEST" ]; then
  case "$runtime_architecture" in
    amd64) AGENTOS_SANDBOX_RUNTIME_DIGEST="$DEFAULT_SANDBOX_RUNTIME_DIGEST_AMD64" ;;
    arm64) AGENTOS_SANDBOX_RUNTIME_DIGEST="$DEFAULT_SANDBOX_RUNTIME_DIGEST_ARM64" ;;
  esac
fi
installation_root="$(resolve_installation_root)"
download_cache_root="${installation_root}/cache/downloads"
if [ -n "$ENVIRONMENT_FILE" ]; then
  ENVIRONMENT_FILE="$(resolve_environment_file)"
fi
launcher="${installation_root}/bin/agentos"
package_name="agentos-${AGENTOS_VERSION}-${platform}-${architecture}"
archive_name="${package_name}.tar.gz"
metadata_name="${archive_name}.artifact.json"
sandbox_runtime_package_name="agentos-sandbox-runtime-${AGENTOS_SANDBOX_RUNTIME_VERSION}-${platform}-${runtime_architecture}"
sandbox_runtime_archive_name="${sandbox_runtime_package_name}.tar.gz"
sandbox_runtime_metadata_name="${sandbox_runtime_archive_name}.artifact.json"
offline_mode=0
if [ -n "$LOCAL_CORE_ARCHIVE" ] || [ -n "$LOCAL_RUNTIME_ARCHIVE" ] || [ -n "$OFFLINE_BUNDLE" ]; then
  offline_mode=1
fi

step "AgentOS ${AGENTOS_VERSION}"
detail "Target: ${platform}-${architecture}"
detail "Install: ${installation_root}"
if [ -n "$ENVIRONMENT_FILE" ]; then
  detail "Environment: ${ENVIRONMENT_FILE}"
fi
if [ "$offline_mode" = "1" ]; then
  detail "Source: offline files"
else
  detail "Release: ${AGENTOS_REPOSITORY}@${AGENTOS_TAG}"
fi
if [ "$SKIP_SANDBOX_RUNTIME" = "1" ]; then
  detail "AgentOS Runtime: skipped (--core-only)"
else
  detail "AgentOS Runtime: ${AGENTOS_SANDBOX_RUNTIME_VERSION} · local · ${platform}-${runtime_architecture}"
  if [ "$offline_mode" = "0" ]; then
    detail "Runtime source: ${AGENTOS_REPOSITORY}@${AGENTOS_SANDBOX_RUNTIME_TAG}"
  fi
  detail "Cube target: downloaded on demand after Cube configuration is saved"
fi

if [ "$DRY_RUN" = "1" ]; then
  detail "Dry run: no files were downloaded or changed"
  exit 0
fi

install_core=1
install_sandbox_runtime=0
if [ "$SKIP_SANDBOX_RUNTIME" != "1" ] && ! sandbox_runtime_is_current; then
  install_sandbox_runtime=1
fi
check_agentos_service_target

if [ -x "$launcher" ]; then
  installed_version="$("$launcher" version 2>/dev/null || true)"
  if [ "$installed_version" = "$AGENTOS_VERSION" ]; then
    install_core=0
    if [ "$install_sandbox_runtime" = "0" ] && [ "$offline_mode" = "0" ]; then
      step "AgentOS ${AGENTOS_VERSION} is already installed"
      if [ -n "$ENVIRONMENT_FILE" ]; then
        current_node="${installation_root}/current/node/bin/node"
        current_installer="${installation_root}/current/install/install.mjs"
        [ -x "$current_node" ] || fail "The installed Node.js runtime is unavailable."
        [ -f "$current_installer" ] || fail "The installed AgentOS installer is unavailable."
        step "Updating AgentOS environment selection"
        set -- --prefix "$installation_root" --agentos-env-file "$ENVIRONMENT_FILE"
        if [ "$NO_LINK" = "1" ]; then
          set -- "$@" --no-link
        fi
        "$current_node" "$current_installer" "$@"
      fi
      if [ "$SKIP_DOCTOR" != "1" ]; then
        "$launcher" doctor
      fi
      if [ "$NO_START" != "1" ]; then
        step "Starting AgentOS"
        start_agentos_service
        if [ "$SKIP_SANDBOX_RUNTIME" != "1" ]; then
          wait_for_sandbox_health
        fi
        detail "Open: ${resolved_health_url%/health}"
      else
        detail "AgentOS was not started (--no-start)"
      fi
      exit 0
    fi
    detail "Repair: installing missing or unhealthy sandbox components"
  elif [ -n "$installed_version" ]; then
    detail "Upgrade: ${installed_version} -> ${AGENTOS_VERSION}"
  fi
fi

require_command awk
require_command cat
require_command cp
require_command find
require_command grep
require_command head
require_command mktemp
require_command sed
require_command tar
require_command tr
require_command wc

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/agentos-install.XXXXXX")"
download_pid=""
download_lock_dir=""
cleanup() {
  if [ -n "${download_pid:-}" ] && kill -0 "$download_pid" 2>/dev/null; then
    kill "$download_pid" 2>/dev/null || true
    wait "$download_pid" 2>/dev/null || true
  fi
  release_download_cache_lock
  rm -rf "$temporary_root"
}
trap cleanup 0
trap 'exit 129' 1
trap 'exit 130' 2
trap 'exit 131' 3
trap 'exit 143' 15

archive_path="${temporary_root}/${archive_name}"
metadata_path="${temporary_root}/${metadata_name}"
sandbox_runtime_archive_path="${temporary_root}/${sandbox_runtime_archive_name}"
sandbox_runtime_metadata_path="${temporary_root}/${sandbox_runtime_metadata_name}"

if [ -n "$OFFLINE_BUNDLE" ]; then
  offline_bundle_path="$(resolve_local_path "$OFFLINE_BUNDLE")"
  [ -f "$offline_bundle_path" ] || fail "Offline bundle not found: ${offline_bundle_path}"
  step "Reading AgentOS offline bundle"
  validate_tar_archive_paths "$offline_bundle_path"
  offline_extract_root="${temporary_root}/offline-bundle"
  mkdir -p "$offline_extract_root"
  tar -xzf "$offline_bundle_path" -C "$offline_extract_root"
  if [ "$install_core" = "1" ]; then
    LOCAL_CORE_ARCHIVE="$(find_offline_bundle_asset "$offline_extract_root" "$archive_name")"
  fi
  if [ "$install_sandbox_runtime" = "1" ]; then
    LOCAL_RUNTIME_ARCHIVE="$(find_offline_bundle_asset "$offline_extract_root" "$sandbox_runtime_archive_name")"
  fi
fi

if [ "$install_core" = "1" ]; then
  if [ -n "$LOCAL_CORE_ARCHIVE" ]; then
    local_core_path="$(resolve_local_path "$LOCAL_CORE_ARCHIVE")"
    [ -f "$local_core_path" ] || fail "Core archive not found: ${local_core_path}"
    step "Reading local AgentOS Core"
    cp "$local_core_path" "$archive_path"
  elif [ "$offline_mode" = "1" ]; then
    fail "Offline installation requires --core ${archive_name}."
  else
    download_verified_release_asset \
      "$AGENTOS_TAG" \
      "$archive_name" "$metadata_name" "$archive_path" "$metadata_path" \
      "AgentOS core" "core" "$platform" "$architecture"
  fi
  step "Validating AgentOS Core package"
  verify_core_release_archive "$archive_path"
fi
if [ "$install_sandbox_runtime" = "1" ]; then
  if [ -n "$LOCAL_RUNTIME_ARCHIVE" ]; then
    local_runtime_path="$(resolve_local_path "$LOCAL_RUNTIME_ARCHIVE")"
    [ -f "$local_runtime_path" ] || fail "AgentOS Runtime archive not found: ${local_runtime_path}"
    step "Reading local AgentOS Runtime"
    cp "$local_runtime_path" "$sandbox_runtime_archive_path"
  elif [ "$offline_mode" = "1" ]; then
    fail "Offline installation requires --runtime ${sandbox_runtime_archive_name}, or --core-only."
  else
    download_verified_release_asset \
      "$AGENTOS_SANDBOX_RUNTIME_TAG" \
      "$sandbox_runtime_archive_name" "$sandbox_runtime_metadata_name" \
      "$sandbox_runtime_archive_path" "$sandbox_runtime_metadata_path" \
      "AgentOS Runtime" "sandbox-runtime" "$platform" "$runtime_architecture"
  fi
  step "Validating AgentOS Runtime package"
  verify_sandbox_runtime_archive "$sandbox_runtime_archive_path"
fi
if [ "$install_core" = "1" ] || [ "$install_sandbox_runtime" = "1" ]; then
  stop_agentos_service
fi

if [ "$install_sandbox_runtime" = "1" ]; then
  install_sandbox_runtime_release \
    "$sandbox_runtime_archive_path" "$sandbox_runtime_package_name" "$temporary_root"
fi

if [ "$install_core" = "1" ]; then
  step "Installing AgentOS core"
  tar -xzf "$archive_path" -C "$temporary_root"
  package_root="${temporary_root}/${package_name}"
  [ -x "${package_root}/node/bin/node" ] || fail "The release does not contain its bundled Node.js runtime."
  [ -f "${package_root}/install/install.mjs" ] || fail "The release does not contain the AgentOS installer."
  installer_log="${temporary_root}/installer.log"

  set --
  if [ -n "$AGENTOS_PREFIX" ]; then
    set -- "$@" --prefix "$AGENTOS_PREFIX"
  fi
  if [ -n "$ENVIRONMENT_FILE" ]; then
    set -- "$@" --agentos-env-file "$ENVIRONMENT_FILE"
  fi
  if [ "$NO_LINK" = "1" ]; then
    set -- "$@" --no-link
  fi
  if ! "${package_root}/node/bin/node" \
    "${package_root}/install/install.mjs" "$@" >"$installer_log" 2>&1; then
    cat "$installer_log" >&2
    fail "The bundled AgentOS installer did not complete."
  fi
fi

[ -x "$launcher" ] || fail "AgentOS launcher was not created at ${launcher}."
if [ "$SKIP_DOCTOR" != "1" ]; then
  step "Checking the installation"
  "$launcher" doctor
fi

if [ "$NO_START" != "1" ]; then
  step "Starting AgentOS"
  start_agentos_service
  if [ "$SKIP_SANDBOX_RUNTIME" != "1" ]; then
    wait_for_sandbox_health
  fi
fi

step "AgentOS ${AGENTOS_VERSION} is ready"
if [ "$NO_START" != "1" ]; then
  detail "Open: ${resolved_health_url%/health}"
  case "$platform" in
    darwin) detail "Service: ${HOME}/Library/LaunchAgents/com.agentos.server.plist" ;;
    linux) detail "Service: ${HOME}/.config/systemd/user/agentos.service" ;;
  esac
else
  detail "AgentOS was not started (--no-start)"
  detail "Start: ${launcher} start"
fi
if [ "$NO_LINK" != "1" ]; then
  case ":${PATH}:" in
    *":${HOME}/.local/bin:"*) ;;
    *) detail "PATH: add ${HOME}/.local/bin to use the short 'agentos' command" ;;
  esac
fi
