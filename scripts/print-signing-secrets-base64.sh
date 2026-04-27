#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/print-signing-secrets-base64.sh \
    --p12 /path/to/cert.p12 \
    --jks /path/to/upload-keystore.jks \
    [--mobileprovision /path/to/profile.mobileprovision] \
    [--output /path/to/.env.github-secrets] \
    [--gh-output /path/to/.gh-set-github-secrets.sh] \
    [--repo owner/repo]

Description:
  Reads local signing files, prompts for passwords and signing metadata,
  writes a shell-compatible env file, and generates gh CLI commands that can
  push those values into GitHub Actions Secrets.

Output keys:
  IOS_CERTIFICATE_P12_BASE64
  IOS_PROVISIONING_PROFILE_BASE64
  ANDROID_KEYSTORE_BASE64
  IOS_CERTIFICATE_PASSWORD
  ANDROID_KEYSTORE_PASSWORD
  ANDROID_KEY_ALIAS
  ANDROID_KEY_PASSWORD
  ANDROID_APPLICATION_ID
  IOS_BUNDLE_IDENTIFIER
  IOS_DEVELOPMENT_TEAM
  IOS_PROVISIONING_PROFILE_SPECIFIER
  IOS_CODE_SIGN_IDENTITY
  IOS_EXPORT_METHOD

Default output file:
  .env.github-secrets

Default gh command file:
  .gh-set-github-secrets.sh
EOF
}

require_file() {
  local label="$1"
  local path="$2"
  if [[ ! -f "$path" ]]; then
    echo "File not found for $label: $path" >&2
    exit 1
  fi
}

encode_file() {
  local path="$1"
  base64 < "$path" | tr -d '\n'
}

shell_quote() {
  python3 - "$1" <<'PY'
import shlex
import sys
print(shlex.quote(sys.argv[1]))
PY
}

abs_path() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
}

append_kv() {
  local key="$1"
  local value="$2"
  printf "%s=%s\n" "$key" "$(shell_quote "$value")" >> "$OUTPUT_PATH"
  SECRET_KEYS+=("$key")
}

prompt_value() {
  local var_name="$1"
  local prompt_text="$2"
  local default_value="${3:-}"
  local secret_mode="${4:-false}"
  local current_value="${!var_name:-}"
  local input=""

  if [[ -n "$current_value" ]]; then
    return
  fi

  if [[ "$secret_mode" == "true" ]]; then
    if [[ -n "$default_value" ]]; then
      read -r -s -p "$prompt_text [$default_value]: " input
    else
      read -r -s -p "$prompt_text: " input
    fi
    echo
  else
    if [[ -n "$default_value" ]]; then
      read -r -p "$prompt_text [$default_value]: " input
    else
      read -r -p "$prompt_text: " input
    fi
  fi

  if [[ -z "$input" ]]; then
    input="$default_value"
  fi

  printf -v "$var_name" "%s" "$input"
}

P12_PATH=""
MOBILEPROVISION_PATH=""
JKS_PATH=""
OUTPUT_PATH=".env.github-secrets"
GH_OUTPUT_PATH=".gh-set-github-secrets.sh"
GH_REPO=""

IOS_CERTIFICATE_PASSWORD="${IOS_CERTIFICATE_PASSWORD:-}"
ANDROID_KEYSTORE_PASSWORD="${ANDROID_KEYSTORE_PASSWORD:-}"
ANDROID_KEY_ALIAS="${ANDROID_KEY_ALIAS:-}"
ANDROID_KEY_PASSWORD="${ANDROID_KEY_PASSWORD:-}"
ANDROID_APPLICATION_ID="${ANDROID_APPLICATION_ID:-com.magechiu.contentseeker}"
IOS_BUNDLE_IDENTIFIER="${IOS_BUNDLE_IDENTIFIER:-com.magechiu.contentseeker}"
IOS_DEVELOPMENT_TEAM="${IOS_DEVELOPMENT_TEAM:-}"
IOS_PROVISIONING_PROFILE_SPECIFIER="${IOS_PROVISIONING_PROFILE_SPECIFIER:-}"
IOS_CODE_SIGN_IDENTITY="${IOS_CODE_SIGN_IDENTITY:-Apple Distribution}"
IOS_EXPORT_METHOD="${IOS_EXPORT_METHOD:-app-store}"
SECRET_KEYS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --p12)
      P12_PATH="${2:-}"
      shift 2
      ;;
    --mobileprovision)
      MOBILEPROVISION_PATH="${2:-}"
      shift 2
      ;;
    --jks)
      JKS_PATH="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    --gh-output)
      GH_OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    --repo)
      GH_REPO="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$P12_PATH" || -z "$JKS_PATH" ]]; then
  usage
  exit 1
fi

require_file "p12" "$P12_PATH"
require_file "jks" "$JKS_PATH"
if [[ -n "$MOBILEPROVISION_PATH" ]]; then
  require_file "mobileprovision" "$MOBILEPROVISION_PATH"
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
mkdir -p "$(dirname "$GH_OUTPUT_PATH")"
OUTPUT_PATH="$(abs_path "$OUTPUT_PATH")"
GH_OUTPUT_PATH="$(abs_path "$GH_OUTPUT_PATH")"

prompt_value IOS_CERTIFICATE_PASSWORD "Enter IOS_CERTIFICATE_PASSWORD" "" true
prompt_value ANDROID_KEYSTORE_PASSWORD "Enter ANDROID_KEYSTORE_PASSWORD" "" true
prompt_value ANDROID_KEY_ALIAS "Enter ANDROID_KEY_ALIAS"
prompt_value ANDROID_KEY_PASSWORD "Enter ANDROID_KEY_PASSWORD" "" true
prompt_value ANDROID_APPLICATION_ID "Enter ANDROID_APPLICATION_ID" "$ANDROID_APPLICATION_ID"
prompt_value IOS_BUNDLE_IDENTIFIER "Enter IOS_BUNDLE_IDENTIFIER" "$IOS_BUNDLE_IDENTIFIER"
prompt_value IOS_DEVELOPMENT_TEAM "Enter IOS_DEVELOPMENT_TEAM"
if [[ -n "$MOBILEPROVISION_PATH" ]]; then
  prompt_value IOS_PROVISIONING_PROFILE_SPECIFIER "Enter IOS_PROVISIONING_PROFILE_SPECIFIER"
fi
prompt_value IOS_CODE_SIGN_IDENTITY "Enter IOS_CODE_SIGN_IDENTITY" "$IOS_CODE_SIGN_IDENTITY"
prompt_value IOS_EXPORT_METHOD "Enter IOS_EXPORT_METHOD" "$IOS_EXPORT_METHOD"

IOS_CERTIFICATE_P12_BASE64="$(encode_file "$P12_PATH")"
ANDROID_KEYSTORE_BASE64="$(encode_file "$JKS_PATH")"
IOS_PROVISIONING_PROFILE_BASE64=""
if [[ -n "$MOBILEPROVISION_PATH" ]]; then
  IOS_PROVISIONING_PROFILE_BASE64="$(encode_file "$MOBILEPROVISION_PATH")"
fi

{
  echo "# Generated by scripts/print-signing-secrets-base64.sh"
  echo "# Safe to source in a POSIX shell."
} > "$OUTPUT_PATH"

append_kv "IOS_CERTIFICATE_P12_BASE64" "$IOS_CERTIFICATE_P12_BASE64"
if [[ -n "$IOS_PROVISIONING_PROFILE_BASE64" ]]; then
  append_kv "IOS_PROVISIONING_PROFILE_BASE64" "$IOS_PROVISIONING_PROFILE_BASE64"
fi
append_kv "ANDROID_KEYSTORE_BASE64" "$ANDROID_KEYSTORE_BASE64"
append_kv "IOS_CERTIFICATE_PASSWORD" "$IOS_CERTIFICATE_PASSWORD"
append_kv "ANDROID_KEYSTORE_PASSWORD" "$ANDROID_KEYSTORE_PASSWORD"
append_kv "ANDROID_KEY_ALIAS" "$ANDROID_KEY_ALIAS"
append_kv "ANDROID_KEY_PASSWORD" "$ANDROID_KEY_PASSWORD"
append_kv "ANDROID_APPLICATION_ID" "$ANDROID_APPLICATION_ID"
append_kv "IOS_BUNDLE_IDENTIFIER" "$IOS_BUNDLE_IDENTIFIER"
append_kv "IOS_DEVELOPMENT_TEAM" "$IOS_DEVELOPMENT_TEAM"
if [[ -n "$IOS_PROVISIONING_PROFILE_SPECIFIER" ]]; then
  append_kv "IOS_PROVISIONING_PROFILE_SPECIFIER" "$IOS_PROVISIONING_PROFILE_SPECIFIER"
fi
append_kv "IOS_CODE_SIGN_IDENTITY" "$IOS_CODE_SIGN_IDENTITY"
append_kv "IOS_EXPORT_METHOD" "$IOS_EXPORT_METHOD"

{
  echo "#!/usr/bin/env bash"
  echo "set -euo pipefail"
  echo "set -a"
  echo "source $(shell_quote "$OUTPUT_PATH")"
  echo "set +a"
  echo
  for key in "${SECRET_KEYS[@]}"; do
    if [[ -n "$GH_REPO" ]]; then
      printf "gh secret set %s --repo %s < <(printf '%%s' \"\$%s\")\n" "$key" "$GH_REPO" "$key"
    else
      printf "gh secret set %s < <(printf '%%s' \"\$%s\")\n" "$key" "$key"
    fi
  done
} > "$GH_OUTPUT_PATH"

chmod +x "$GH_OUTPUT_PATH"

cat "$OUTPUT_PATH"
echo
echo "Wrote dotenv output to: $OUTPUT_PATH"
echo "Wrote gh secret commands to: $GH_OUTPUT_PATH"
