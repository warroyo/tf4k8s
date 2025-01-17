#!/usr/bin/env bash

# Modified variant of hack script!
# @see https://github.com/cloudfoundry/cf-for-k8s/blob/master/hack/generate-values.sh

set -euo pipefail

function usage_text() {
  cat <<EOF
Usage:
  $(basename "$0")

flags:
  -d, --cf-domain
      (required) Root DNS domain name for the CF install
      (e.g. if CF API at api.inglewood.k8s-dev.relint.rocks, cf-domain = inglewood.k8s-dev.relint.rocks)

  -s, --silence-hack-warning
      (optional) Omit hack script warning message.
EOF
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage_text >&2
fi

while [[ $# -gt 0 ]]; do
  i=$1
  case $i in
  -d=* | --cf-domain=*)
    DOMAIN="${i#*=}"
    shift
    ;;
  -d | --cf-domain)
    DOMAIN="${2}"
    shift
    shift
    ;;
  -s | --silence-hack-warning)
    SILENCE_HACK_WARNING="true"
    shift
    ;;
  *)
    echo -e "Error: Unknown flag: ${i/=*/}\n" >&2
    usage_text >&2
    exit 1
    ;;
  esac
done

if [[ -z ${SILENCE_HACK_WARNING:=} ]]; then
  echo "WARNING: The hack scripts are intended for development of cf-for-k8s.
  They are not officially supported product bits.  Their interface and behavior
  may change at any time without notice." 1>&2
fi

if [[ -z ${DOMAIN:=} ]]; then
  echo "Missing required flag: -d / --cf-domain" >&2
  exit 1
fi

VARS_FILE="/tmp/${DOMAIN}/cf-vars.yaml"

# Make sure bosh binary exists
bosh --version >/dev/null

bosh interpolate --vars-store=${VARS_FILE} <(
  cat <<EOF
variables:
- name: blobstore_secret_key
  type: password
- name: db_admin_password
  type: password
- name: capi_db_password
  type: password
- name: capi_db_encryption_key
  type: password
- name: uaa_db_password
  type: password
- name: uaa_login_secret
  type: password
- name: uaa_admin_client_secret
  type: password
- name: uaa_encryption_key_passphrase
  type: password
- name: cc_username_lookup_client_secret
  type: password
- name: cf_api_backup_metadata_generator_client_secret
  type: password
- name: cf_api_controllers_client_secret
  type: password
- name: default_ca
  type: certificate
  options:
    is_ca: true
    common_name: ca
- name: uaa_jwt_policy_signing_key
  type: certificate
  options:
    ca: default_ca
    common_name: uaa_jwt_policy_signing_key
- name: uaa_login_service_provider
  type: certificate
  options:
    ca: default_ca
    common_name: uaa_login_service_provider
EOF
) >/dev/null

cat <<EOF
#@data/values
---
system_domain: "${DOMAIN}"
app_domains:
#@overlay/append
- "apps.${DOMAIN}"

blobstore:
  secret_access_key: $(bosh interpolate ${VARS_FILE} --path=/blobstore_secret_key)
cf_db:
  admin_password: $(bosh interpolate ${VARS_FILE} --path=/db_admin_password)
capi:
  cc_username_lookup_client_secret: $(bosh interpolate ${VARS_FILE} --path=/cc_username_lookup_client_secret)
  cf_api_controllers_client_secret: $(bosh interpolate ${VARS_FILE} --path=/cf_api_controllers_client_secret)
  cf_api_backup_metadata_generator_client_secret: $(bosh interpolate ${VARS_FILE} --path=/cf_api_backup_metadata_generator_client_secret)
  database:
    password: $(bosh interpolate ${VARS_FILE} --path=/capi_db_password)
    encryption_key: $(bosh interpolate ${VARS_FILE} --path=/capi_db_encryption_key)

uaa:
  database:
    password: $(bosh interpolate ${VARS_FILE} --path=/uaa_db_password)
  admin_client_secret: $(bosh interpolate ${VARS_FILE} --path=/uaa_admin_client_secret)
  jwt_policy:
    signing_key: |
$(bosh interpolate "${VARS_FILE}" --path=/uaa_jwt_policy_signing_key/private_key | grep -Ev '^$' | sed -e 's/^/      /')
  encryption_key:
    passphrase: $(bosh interpolate "${VARS_FILE}" --path=/uaa_encryption_key_passphrase)
  login:
    service_provider:
      key: |
$(bosh interpolate "${VARS_FILE}" --path=/uaa_login_service_provider/private_key | grep -Ev '^$' | sed -e 's/^/        /')
      certificate: |
$(bosh interpolate "${VARS_FILE}" --path=/uaa_login_service_provider/certificate | grep -Ev '^$' | sed -e 's/^/        /')
  login_secret: $(bosh interpolate "${VARS_FILE}" --path=/uaa_login_secret)
EOF

if [[ -n "${K8S_ENV:-}" ]] ; then
    k8s_env_path=$HOME/workspace/relint-ci-pools/k8s-dev/ready/claimed/"$K8S_ENV"
    if [[ -f "$k8s_env_path" ]] ; then
	      ip_addr=$(jq -r .lb_static_ip < "$k8s_env_path")
        echo 1>&2 "Detected \$K8S_ENV environment var; writing \"load_balancer.static_ip: $ip_addr\" entry to end of output"
        echo "
load_balancer:
  enable: true
  static_ip: $ip_addr
"
    fi
fi