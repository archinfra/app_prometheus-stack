#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="prometheus-stack"
APP_VERSION="0.1.0"
PACKAGE_PROFILE="integrated"
WORKDIR="/tmp/${APP_NAME}-installer"
PAYLOAD_ARCHIVE="${WORKDIR}/payload.tar.gz"
CHART_DIR="${WORKDIR}/charts/kube-prometheus-stack"
IMAGE_DIR="${WORKDIR}/images"
IMAGE_INDEX="${IMAGE_DIR}/image-index.tsv"
BASE_VALUES_FILE="${WORKDIR}/values-base.yaml"
PHASE1_VALUES_FILE="${WORKDIR}/values-phase1.yaml"
PHASE2_VALUES_FILE="${WORKDIR}/values-phase2.yaml"

ACTION="help"
RELEASE_NAME="prometheus-stack"
NAMESPACE="monitoring"
WAIT_TIMEOUT="10m"
IMAGE_PULL_POLICY="IfNotPresent"
REGISTRY_REPO="sealos.hub:5000/kube4"
REGISTRY_REPO_EXPLICIT="false"
REGISTRY_USER="admin"
REGISTRY_PASS="passw0rd"
SKIP_IMAGE_PREPARE="false"
DELETE_CRDS="false"
AUTO_YES="false"

PROMETHEUS_STORAGE_CLASS="nfs"
PROMETHEUS_STORAGE_SIZE="200Gi"
PROMETHEUS_RETENTION="14d"
PROMETHEUS_RETENTION_SIZE="30GiB"
ALERTMANAGER_STORAGE_CLASS="nfs"
ALERTMANAGER_STORAGE_SIZE="10Gi"
GRAFANA_STORAGE_CLASS="nfs"
GRAFANA_STORAGE_SIZE="10Gi"
GRAFANA_ADMIN_PASSWORD="admin@passw0rd"

STACK_LABEL_KEY="monitoring.archinfra.io/stack"
STACK_LABEL_VALUE="default"

HELM_ARGS=()
PAYLOAD_OFFSET=""

readonly CRDS=(
  "alertmanagerconfigs.monitoring.coreos.com"
  "alertmanagers.monitoring.coreos.com"
  "podmonitors.monitoring.coreos.com"
  "probes.monitoring.coreos.com"
  "prometheusagents.monitoring.coreos.com"
  "prometheuses.monitoring.coreos.com"
  "prometheusrules.monitoring.coreos.com"
  "scrapeconfigs.monitoring.coreos.com"
  "servicemonitors.monitoring.coreos.com"
  "thanosrulers.monitoring.coreos.com"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() {
  echo -e "${CYAN}[INFO]${NC} $*"
}

success() {
  echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

die() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
  exit 1
}

section() {
  echo
  echo -e "${BLUE}${BOLD}============================================================${NC}"
  echo -e "${BLUE}${BOLD}$*${NC}"
  echo -e "${BLUE}${BOLD}============================================================${NC}"
}

program_name() {
  basename "$0"
}

banner() {
  echo
  echo -e "${GREEN}${BOLD}Prometheus Stack 离线安装器${NC}"
  echo -e "${CYAN}版本: ${APP_VERSION}${NC}"
  echo -e "${CYAN}产物包: ${PACKAGE_PROFILE}${NC}"
}

usage() {
  local cmd="./$(program_name)"
  cat <<EOF
Usage:
  ${cmd} <install|uninstall|status|help> [options] [-- <helm_args>]
  ${cmd} -h|--help

Actions:
  install       Install the Prometheus Stack in two phases: CRDs/operator first, full stack second
  uninstall     Uninstall the release and optionally delete CRDs
  status        Show CRD, Helm release and workload status
  help          Show this message

Core options:
  -n, --namespace <ns>                       Namespace, default: ${NAMESPACE}
  --release-name <name>                     Helm release name, default: ${RELEASE_NAME}
  --wait-timeout <duration>                 Wait timeout, default: ${WAIT_TIMEOUT}

Storage and runtime:
  --prometheus-storage-class <name>         Default: ${PROMETHEUS_STORAGE_CLASS}
  --prometheus-storage-size <size>          Default: ${PROMETHEUS_STORAGE_SIZE}
  --prometheus-retention <duration>         Default: ${PROMETHEUS_RETENTION}
  --prometheus-retention-size <size>        Default: ${PROMETHEUS_RETENTION_SIZE}
  --alertmanager-storage-class <name>       Default: ${ALERTMANAGER_STORAGE_CLASS}
  --alertmanager-storage-size <size>        Default: ${ALERTMANAGER_STORAGE_SIZE}
  --grafana-storage-class <name>            Default: ${GRAFANA_STORAGE_CLASS}
  --grafana-storage-size <size>             Default: ${GRAFANA_STORAGE_SIZE}
  --grafana-admin-password <password>       Default: ${GRAFANA_ADMIN_PASSWORD}

Image and registry:
  --registry <repo-prefix>                  Target image repo prefix, default: ${REGISTRY_REPO}
  --registry-user <user>                    Registry username, default: ${REGISTRY_USER}
  --registry-password <password>            Registry password, default: <hidden>
  --image-pull-policy <policy>              Always|IfNotPresent|Never, default: ${IMAGE_PULL_POLICY}
  --skip-image-prepare                      Reuse images already present in the target registry

Cleanup:
  --delete-crds                             With uninstall, also delete monitoring CRDs

Other:
  -y, --yes                                 Skip confirmation
  -h, --help                                Show help

Examples:
  ${cmd} install -n monitoring --grafana-admin-password 'Admin@123' -y
  ${cmd} install --registry harbor.example.com/kube4 --skip-image-prepare -y
  ${cmd} status -n monitoring
  ${cmd} uninstall -n monitoring --delete-crds -y
EOF
}

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

parse_args() {
  if [[ $# -eq 0 ]]; then
    ACTION="help"
    return
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      install|uninstall|status|help)
        ACTION="$1"
        shift
        ;;
      -n|--namespace)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        NAMESPACE="$2"
        shift 2
        ;;
      --release-name)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        RELEASE_NAME="$2"
        shift 2
        ;;
      --prometheus-storage-class)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        PROMETHEUS_STORAGE_CLASS="$2"
        shift 2
        ;;
      --prometheus-storage-size)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        PROMETHEUS_STORAGE_SIZE="$2"
        shift 2
        ;;
      --prometheus-retention)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        PROMETHEUS_RETENTION="$2"
        shift 2
        ;;
      --prometheus-retention-size)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        PROMETHEUS_RETENTION_SIZE="$2"
        shift 2
        ;;
      --alertmanager-storage-class)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        ALERTMANAGER_STORAGE_CLASS="$2"
        shift 2
        ;;
      --alertmanager-storage-size)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        ALERTMANAGER_STORAGE_SIZE="$2"
        shift 2
        ;;
      --grafana-storage-class)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        GRAFANA_STORAGE_CLASS="$2"
        shift 2
        ;;
      --grafana-storage-size)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        GRAFANA_STORAGE_SIZE="$2"
        shift 2
        ;;
      --grafana-admin-password)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        GRAFANA_ADMIN_PASSWORD="$2"
        shift 2
        ;;
      --registry)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        REGISTRY_REPO="$2"
        REGISTRY_REPO_EXPLICIT="true"
        shift 2
        ;;
      --registry-user)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        REGISTRY_USER="$2"
        shift 2
        ;;
      --registry-password)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        REGISTRY_PASS="$2"
        shift 2
        ;;
      --image-pull-policy)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        IMAGE_PULL_POLICY="$2"
        shift 2
        ;;
      --skip-image-prepare)
        SKIP_IMAGE_PREPARE="true"
        shift
        ;;
      --wait-timeout)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        WAIT_TIMEOUT="$2"
        shift 2
        ;;
      --delete-crds)
        DELETE_CRDS="true"
        shift
        ;;
      -y|--yes)
        AUTO_YES="true"
        shift
        ;;
      -h|--help)
        ACTION="help"
        shift
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          HELM_ARGS+=("$1")
          shift
        done
        break
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

normalize_flags() {
  case "${IMAGE_PULL_POLICY}" in
    Always|IfNotPresent|Never) ;;
    *)
      die "Unsupported image pull policy: ${IMAGE_PULL_POLICY}"
      ;;
  esac
}

check_deps() {
  command -v helm >/dev/null 2>&1 || die "helm is required"
  command -v kubectl >/dev/null 2>&1 || die "kubectl is required"
  if [[ "${ACTION}" == "install" && "${SKIP_IMAGE_PREPARE}" != "true" ]]; then
    command -v docker >/dev/null 2>&1 || die "docker is required unless --skip-image-prepare is used"
  fi
}

confirm() {
  [[ "${AUTO_YES}" == "true" ]] && return 0

  section "部署配置确认"
  echo "Action                    : ${ACTION}"
  echo "Release                   : ${RELEASE_NAME}"
  echo "Namespace                 : ${NAMESPACE}"
  if [[ "${ACTION}" == "install" ]]; then
    echo "Prometheus storageClass   : ${PROMETHEUS_STORAGE_CLASS}"
    echo "Prometheus storage        : ${PROMETHEUS_STORAGE_SIZE}"
    echo "Prometheus retention      : ${PROMETHEUS_RETENTION}"
    echo "Prometheus retention size : ${PROMETHEUS_RETENTION_SIZE}"
    echo "Alertmanager storageClass : ${ALERTMANAGER_STORAGE_CLASS}"
    echo "Alertmanager storage      : ${ALERTMANAGER_STORAGE_SIZE}"
    echo "Grafana storageClass      : ${GRAFANA_STORAGE_CLASS}"
    echo "Grafana storage           : ${GRAFANA_STORAGE_SIZE}"
    echo "Registry repo             : ${REGISTRY_REPO}"
    echo "Skip image prepare        : ${SKIP_IMAGE_PREPARE}"
    echo "Wait timeout              : ${WAIT_TIMEOUT}"
  fi
  if [[ "${ACTION}" == "uninstall" ]]; then
    echo "Delete CRDs               : ${DELETE_CRDS}"
  fi
  if [[ ${#HELM_ARGS[@]} -gt 0 ]]; then
    echo "Helm extra args           : ${HELM_ARGS[*]}"
  fi
  echo
  read -r -p "Continue? [y/N] " answer
  [[ "${answer}" =~ ^[Yy]$ ]] || die "Cancelled"
}

init_payload_offset() {
  [[ -n "${PAYLOAD_OFFSET}" ]] && return 0

  local marker_line payload_offset skip_bytes byte_hex
  marker_line="$(awk '/^__PAYLOAD_BELOW__$/ { print NR; exit }' "$0")"
  [[ -n "${marker_line}" ]] || die "Unable to locate embedded payload"

  payload_offset="$(( $(head -n "${marker_line}" "$0" | wc -c | tr -d ' ') + 1 ))"
  skip_bytes=0
  while :; do
    byte_hex="$(dd if="$0" bs=1 skip="$((payload_offset + skip_bytes - 1))" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    case "${byte_hex}" in
      0a|0d)
        skip_bytes=$((skip_bytes + 1))
        ;;
      "")
        die "Invalid payload boundary"
        ;;
      *)
        break
        ;;
    esac
  done

  PAYLOAD_OFFSET="$((payload_offset + skip_bytes))"
}

payload_stream() {
  init_payload_offset
  dd if="$0" bs=1 skip="$((PAYLOAD_OFFSET - 1))" 2>/dev/null
}

extract_payload() {
  log "Extracting embedded payload to ${WORKDIR}"
  rm -rf "${WORKDIR}"
  mkdir -p "${WORKDIR}"

  payload_stream | tee "${PAYLOAD_ARCHIVE}" | tar -xzf - -C "${WORKDIR}" >/dev/null

  [[ -d "${CHART_DIR}" ]] || die "Missing chart payload"
  [[ -f "${IMAGE_INDEX}" ]] || die "Missing image metadata payload"
}

image_name_from_ref() {
  local ref="$1"
  local name_tag="${ref##*/}"
  echo "${name_tag%%:*}"
}

image_name_tag_from_ref() {
  local ref="$1"
  echo "${ref##*/}"
}

resolve_target_ref() {
  local default_ref="$1"
  if [[ "${REGISTRY_REPO_EXPLICIT}" == "true" ]]; then
    echo "${REGISTRY_REPO}/$(image_name_tag_from_ref "${default_ref}")"
  else
    echo "${default_ref}"
  fi
}

image_registry_from_ref() {
  local ref="$1"
  echo "${ref%%/*}"
}

image_repository_from_ref() {
  local ref="$1"
  local remainder="${ref#*/}"
  echo "${remainder%:*}"
}

image_tag_from_ref() {
  local ref="$1"
  echo "${ref##*:}"
}

yaml_single_quote() {
  printf '%s' "$1" | sed "s/'/''/g"
}

declare -A IMAGE_DEFAULT_TARGETS=()
declare -A IMAGE_EFFECTIVE_TARGETS=()
declare -A IMAGE_LOAD_REFS=()

load_image_metadata() {
  while IFS=$'\t' read -r tar_name load_ref default_target_ref; do
    [[ -n "${tar_name}" ]] || continue
    IMAGE_LOAD_REFS["${tar_name}"]="${load_ref}"
    IMAGE_DEFAULT_TARGETS["${tar_name}"]="${default_target_ref}"
    IMAGE_EFFECTIVE_TARGETS["${tar_name}"]="$(resolve_target_ref "${default_target_ref}")"
  done < "${IMAGE_INDEX}"
}

find_image_ref_by_name() {
  local wanted_name="$1"
  local tar_name
  for tar_name in "${!IMAGE_EFFECTIVE_TARGETS[@]}"; do
    if [[ "$(image_name_from_ref "${IMAGE_EFFECTIVE_TARGETS[${tar_name}]}")" == "${wanted_name}" ]]; then
      echo "${IMAGE_EFFECTIVE_TARGETS[${tar_name}]}"
      return 0
    fi
  done
  return 1
}

docker_login() {
  local registry_host="${REGISTRY_REPO%%/*}"
  log "Logging into registry ${registry_host}"
  if ! echo "${REGISTRY_PASS}" | docker login "${registry_host}" -u "${REGISTRY_USER}" --password-stdin >/dev/null 2>&1; then
    warn "docker login failed for ${registry_host}; continuing and letting push decide"
  fi
}

prepare_images() {
  [[ "${SKIP_IMAGE_PREPARE}" == "true" ]] && {
    log "Skipping image prepare because --skip-image-prepare was requested"
    return 0
  }

  docker_login

  local tar_name load_ref target_ref tar_path
  while IFS=$'\t' read -r tar_name load_ref _; do
    [[ -n "${tar_name}" ]] || continue
    tar_path="${IMAGE_DIR}/${tar_name}"
    [[ -f "${tar_path}" ]] || die "Missing image tar: ${tar_path}"

    target_ref="${IMAGE_EFFECTIVE_TARGETS[${tar_name}]}"

    log "Loading ${tar_name}"
    docker load -i "${tar_path}" >/dev/null

    if [[ "${load_ref}" != "${target_ref}" ]]; then
      log "Tagging ${load_ref} -> ${target_ref}"
      docker tag "${load_ref}" "${target_ref}"
    fi

    log "Pushing ${target_ref}"
    docker push "${target_ref}" >/dev/null
  done < "${IMAGE_INDEX}"

  success "Image prepare completed"
}

ensure_namespace() {
  if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    log "Creating namespace ${NAMESPACE}"
    kubectl create namespace "${NAMESPACE}" >/dev/null
  fi
}

resolve_required_images() {
  ALERTMANAGER_IMAGE="$(find_image_ref_by_name "alertmanager")" || die "Unable to resolve alertmanager image"
  ADMISSION_WEBHOOK_IMAGE="$(find_image_ref_by_name "admission-webhook")" || die "Unable to resolve admission-webhook image"
  OPERATOR_IMAGE="$(find_image_ref_by_name "prometheus-operator")" || die "Unable to resolve prometheus-operator image"
  CONFIG_RELOADER_IMAGE="$(find_image_ref_by_name "prometheus-config-reloader")" || die "Unable to resolve prometheus-config-reloader image"
  THANOS_IMAGE="$(find_image_ref_by_name "thanos")" || die "Unable to resolve thanos image"
  PROMETHEUS_IMAGE="$(find_image_ref_by_name "prometheus")" || die "Unable to resolve prometheus image"
  GRAFANA_IMAGE="$(find_image_ref_by_name "grafana")" || die "Unable to resolve grafana image"
  BUSYBOX_IMAGE="$(find_image_ref_by_name "busybox")" || die "Unable to resolve busybox image"
  CURL_IMAGE="$(find_image_ref_by_name "curl")" || die "Unable to resolve curl image"
  K8S_SIDECAR_IMAGE="$(find_image_ref_by_name "k8s-sidecar")" || die "Unable to resolve k8s-sidecar image"
  GRAFANA_RENDERER_IMAGE="$(find_image_ref_by_name "grafana-image-renderer")" || die "Unable to resolve grafana-image-renderer image"
  KUBE_RBAC_PROXY_IMAGE="$(find_image_ref_by_name "kube-rbac-proxy")" || die "Unable to resolve kube-rbac-proxy image"
  KUBE_STATE_METRICS_IMAGE="$(find_image_ref_by_name "kube-state-metrics")" || die "Unable to resolve kube-state-metrics image"
  NODE_EXPORTER_IMAGE="$(find_image_ref_by_name "node-exporter")" || die "Unable to resolve node-exporter image"
  WEBHOOK_CERTGEN_IMAGE="$(find_image_ref_by_name "kube-webhook-certgen")" || die "Unable to resolve kube-webhook-certgen image"
}

write_base_values_file() {
  cat > "${BASE_VALUES_FILE}" <<EOF
commonLabels:
  "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"

windowsMonitoring:
  enabled: false

defaultRules:
  create: true

prometheusOperator:
  enabled: true
  image:
    registry: $(image_registry_from_ref "${OPERATOR_IMAGE}")
    repository: $(image_repository_from_ref "${OPERATOR_IMAGE}")
    tag: "$(image_tag_from_ref "${OPERATOR_IMAGE}")"
    sha: ""
  prometheusConfigReloader:
    image:
      registry: $(image_registry_from_ref "${CONFIG_RELOADER_IMAGE}")
      repository: $(image_repository_from_ref "${CONFIG_RELOADER_IMAGE}")
      tag: "$(image_tag_from_ref "${CONFIG_RELOADER_IMAGE}")"
      sha: ""
  thanosImage:
    registry: $(image_registry_from_ref "${THANOS_IMAGE}")
    repository: $(image_repository_from_ref "${THANOS_IMAGE}")
    tag: "$(image_tag_from_ref "${THANOS_IMAGE}")"
    sha: ""
  serviceMonitor:
    additionalLabels:
      "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
  admissionWebhooks:
    deployment:
      enabled: true
      image:
        registry: $(image_registry_from_ref "${ADMISSION_WEBHOOK_IMAGE}")
        repository: $(image_repository_from_ref "${ADMISSION_WEBHOOK_IMAGE}")
        tag: "$(image_tag_from_ref "${ADMISSION_WEBHOOK_IMAGE}")"
        sha: ""
        pullPolicy: ${IMAGE_PULL_POLICY}
    patch:
      enabled: true
      image:
        registry: $(image_registry_from_ref "${WEBHOOK_CERTGEN_IMAGE}")
        repository: $(image_repository_from_ref "${WEBHOOK_CERTGEN_IMAGE}")
        tag: "$(image_tag_from_ref "${WEBHOOK_CERTGEN_IMAGE}")"
        sha: ""
        pullPolicy: ${IMAGE_PULL_POLICY}

alertmanager:
  enabled: true
  alertmanagerSpec:
    image:
      registry: $(image_registry_from_ref "${ALERTMANAGER_IMAGE}")
      repository: $(image_repository_from_ref "${ALERTMANAGER_IMAGE}")
      tag: "$(image_tag_from_ref "${ALERTMANAGER_IMAGE}")"
      sha: ""
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: "${ALERTMANAGER_STORAGE_CLASS}"
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: "${ALERTMANAGER_STORAGE_SIZE}"
  serviceMonitor:
    additionalLabels:
      "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"

prometheus:
  enabled: true
  serviceMonitor:
    additionalLabels:
      "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
  thanosServiceMonitor:
    additionalLabels:
      "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
  prometheusSpec:
    image:
      registry: $(image_registry_from_ref "${PROMETHEUS_IMAGE}")
      repository: $(image_repository_from_ref "${PROMETHEUS_IMAGE}")
      tag: "$(image_tag_from_ref "${PROMETHEUS_IMAGE}")"
      sha: ""
    retention: "${PROMETHEUS_RETENTION}"
    retentionSize: "${PROMETHEUS_RETENTION_SIZE}"
    serviceMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelector:
      matchLabels:
        "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
    serviceMonitorNamespaceSelector: {}
    podMonitorSelectorNilUsesHelmValues: false
    podMonitorSelector:
      matchLabels:
        "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
    podMonitorNamespaceSelector: {}
    probeSelectorNilUsesHelmValues: false
    probeSelector:
      matchLabels:
        "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
    probeNamespaceSelector: {}
    ruleSelectorNilUsesHelmValues: false
    ruleSelector:
      matchLabels:
        "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
    ruleNamespaceSelector: {}
    scrapeConfigSelectorNilUsesHelmValues: false
    scrapeConfigSelector:
      matchLabels:
        "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
    scrapeConfigNamespaceSelector: {}
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: "${PROMETHEUS_STORAGE_CLASS}"
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: "${PROMETHEUS_STORAGE_SIZE}"

grafana:
  enabled: true
  adminPassword: '$(yaml_single_quote "${GRAFANA_ADMIN_PASSWORD}")'
  extraLabels:
    "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
  image:
    registry: $(image_registry_from_ref "${GRAFANA_IMAGE}")
    repository: $(image_repository_from_ref "${GRAFANA_IMAGE}")
    tag: "$(image_tag_from_ref "${GRAFANA_IMAGE}")"
    sha: ""
  downloadDashboardsImage:
    registry: $(image_registry_from_ref "${CURL_IMAGE}")
    repository: $(image_repository_from_ref "${CURL_IMAGE}")
    tag: "$(image_tag_from_ref "${CURL_IMAGE}")"
    sha: ""
    pullPolicy: ${IMAGE_PULL_POLICY}
  initChownData:
    image:
      registry: $(image_registry_from_ref "${BUSYBOX_IMAGE}")
      repository: $(image_repository_from_ref "${BUSYBOX_IMAGE}")
      tag: "$(image_tag_from_ref "${BUSYBOX_IMAGE}")"
      sha: ""
      pullPolicy: ${IMAGE_PULL_POLICY}
  sidecar:
    image:
      registry: $(image_registry_from_ref "${K8S_SIDECAR_IMAGE}")
      repository: $(image_repository_from_ref "${K8S_SIDECAR_IMAGE}")
      tag: "$(image_tag_from_ref "${K8S_SIDECAR_IMAGE}")"
      sha: ""
  imageRenderer:
    image:
      registry: $(image_registry_from_ref "${GRAFANA_RENDERER_IMAGE}")
      repository: $(image_repository_from_ref "${GRAFANA_RENDERER_IMAGE}")
      tag: "$(image_tag_from_ref "${GRAFANA_RENDERER_IMAGE}")"
      sha: ""
      pullPolicy: ${IMAGE_PULL_POLICY}
    serviceMonitor:
      labels:
        "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
  persistence:
    enabled: true
    type: pvc
    size: "${GRAFANA_STORAGE_SIZE}"
    storageClassName: "${GRAFANA_STORAGE_CLASS}"
  serviceMonitor:
    labels:
      "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"

kubeStateMetrics:
  enabled: true
  image:
    registry: $(image_registry_from_ref "${KUBE_STATE_METRICS_IMAGE}")
    repository: $(image_repository_from_ref "${KUBE_STATE_METRICS_IMAGE}")
    tag: "$(image_tag_from_ref "${KUBE_STATE_METRICS_IMAGE}")"
    sha: ""
  kubeRBACProxy:
    image:
      registry: $(image_registry_from_ref "${KUBE_RBAC_PROXY_IMAGE}")
      repository: $(image_repository_from_ref "${KUBE_RBAC_PROXY_IMAGE}")
      tag: "$(image_tag_from_ref "${KUBE_RBAC_PROXY_IMAGE}")"
      sha: ""
  prometheus:
    monitor:
      additionalLabels:
        "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"

nodeExporter:
  enabled: true
  commonLabels:
    "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
  image:
    registry: $(image_registry_from_ref "${NODE_EXPORTER_IMAGE}")
    repository: $(image_repository_from_ref "${NODE_EXPORTER_IMAGE}")
    tag: "$(image_tag_from_ref "${NODE_EXPORTER_IMAGE}")"
    sha: ""
  kubeRBACProxy:
    image:
      registry: $(image_registry_from_ref "${KUBE_RBAC_PROXY_IMAGE}")
      repository: $(image_repository_from_ref "${KUBE_RBAC_PROXY_IMAGE}")
      tag: "$(image_tag_from_ref "${KUBE_RBAC_PROXY_IMAGE}")"
      sha: ""
  prometheus:
    monitor:
      additionalLabels:
        "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
    podMonitor:
      additionalLabels:
        "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
EOF
}

write_phase_values_files() {
  write_base_values_file

  cat > "${PHASE1_VALUES_FILE}" <<EOF
crds:
  enabled: true

defaultRules:
  create: false

prometheusOperator:
  enabled: true

prometheus:
  enabled: false

alertmanager:
  enabled: false

grafana:
  enabled: false

kubeStateMetrics:
  enabled: false

nodeExporter:
  enabled: false

thanosRuler:
  enabled: false
EOF

  cat > "${PHASE2_VALUES_FILE}" <<EOF
crds:
  enabled: true

defaultRules:
  create: true

prometheusOperator:
  enabled: true

prometheus:
  enabled: true

alertmanager:
  enabled: true

grafana:
  enabled: true

kubeStateMetrics:
  enabled: true

nodeExporter:
  enabled: true

thanosRuler:
  enabled: false
EOF
}

preview_command() {
  local rendered=()
  local arg
  for arg in "$@"; do
    rendered+=("$(printf '%q' "${arg}")")
  done
  printf '%s ' "${rendered[@]}"
  echo
}

helm_release_args() {
  local values_file="$1"
  local -a cmd=(
    helm upgrade --install "${RELEASE_NAME}" "${CHART_DIR}"
    -n "${NAMESPACE}"
    --create-namespace
    --wait
    --wait-for-jobs
    --timeout "${WAIT_TIMEOUT}"
    -f "${BASE_VALUES_FILE}"
    -f "${values_file}"
  )

  if [[ ${#HELM_ARGS[@]} -gt 0 ]]; then
    cmd+=("${HELM_ARGS[@]}")
  fi

  printf '%s\n' "${cmd[@]}"
}

run_helm_phase() {
  local phase_name="$1"
  local values_file="$2"
  local -a helm_cmd=()

  mapfile -t helm_cmd < <(helm_release_args "${values_file}")
  section "Helm 命令预览 (${phase_name})"
  preview_command "${helm_cmd[@]}"
  "${helm_cmd[@]}"
}

wait_for_crds_established() {
  section "等待 CRD 就绪"
  local crd
  for crd in "${CRDS[@]}"; do
    log "Waiting for CRD ${crd}"
    kubectl wait --for=condition=Established --timeout="${WAIT_TIMEOUT}" "crd/${crd}" >/dev/null
  done
  success "CRDs are established"
}

wait_for_release_workloads() {
  local kind resource
  local -a resources=()

  for kind in deployment statefulset daemonset; do
    mapfile -t resources < <(kubectl get "${kind}" -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" -o name 2>/dev/null || true)
    for resource in "${resources[@]}"; do
      [[ -n "${resource}" ]] || continue
      log "Waiting for ${resource}"
      kubectl rollout status -n "${NAMESPACE}" "${resource}" --timeout="${WAIT_TIMEOUT}"
    done
  done
}

wait_for_operator_managed_statefulset() {
  local resource_kind="$1"
  local sts_prefix="$2"
  local resource_name statefulset_name

  resource_name="$(kubectl get "${resource_kind}" -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [[ -n "${resource_name}" ]] || return 0

  statefulset_name="${sts_prefix}-${resource_name}"
  if kubectl get "statefulset/${statefulset_name}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    log "Waiting for statefulset/${statefulset_name}"
    kubectl rollout status -n "${NAMESPACE}" "statefulset/${statefulset_name}" --timeout="${WAIT_TIMEOUT}"
  fi
}

install_release() {
  ensure_namespace
  resolve_required_images
  write_phase_values_files

  section "阶段一: 安装 CRD 与 Prometheus Operator"
  run_helm_phase "phase-1" "${PHASE1_VALUES_FILE}"
  wait_for_crds_established
  wait_for_release_workloads

  section "阶段二: 安装完整监控栈"
  run_helm_phase "phase-2" "${PHASE2_VALUES_FILE}"
  wait_for_release_workloads
  wait_for_operator_managed_statefulset "prometheus" "prometheus"
  wait_for_operator_managed_statefulset "alertmanager" "alertmanager"

  success "Prometheus Stack install or upgrade completed"
}

show_post_install_info() {
  section "部署结果"
  kubectl get pods,svc,deploy,statefulset,daemonset -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true

  if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    echo
    kubectl get servicemonitor,podmonitor,prometheusrule,prometheus,alertmanager -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true
  fi
}

delete_crds_if_requested() {
  [[ "${DELETE_CRDS}" == "true" ]] || return 0

  section "删除监控 CRD"
  local crd
  for crd in "${CRDS[@]}"; do
    kubectl delete crd "${crd}" --ignore-not-found >/dev/null || true
  done
  success "CRD cleanup requested"
}

uninstall_release() {
  if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    helm uninstall "${RELEASE_NAME}" -n "${NAMESPACE}"
    success "Release ${RELEASE_NAME} uninstalled"
  else
    warn "Helm release ${RELEASE_NAME} not found in namespace ${NAMESPACE}"
  fi

  delete_crds_if_requested
}

show_crd_status() {
  section "CRD 状态"
  local crd
  for crd in "${CRDS[@]}"; do
    if kubectl get crd "${crd}" >/dev/null 2>&1; then
      echo "[OK] ${crd}"
    else
      echo "[--] ${crd}"
    fi
  done
}

show_status() {
  show_crd_status

  section "Helm 状态"
  helm status "${RELEASE_NAME}" -n "${NAMESPACE}" || warn "Release ${RELEASE_NAME} not found"

  section "工作负载状态"
  kubectl get pods,svc,deploy,statefulset,daemonset -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true

  if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    echo
    kubectl get servicemonitor,podmonitor,prometheusrule,prometheus,alertmanager -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true
  fi
}

main() {
  parse_args "$@"
  normalize_flags
  banner

  case "${ACTION}" in
    help)
      usage
      ;;
    install)
      check_deps
      confirm
      extract_payload
      load_image_metadata
      prepare_images
      install_release
      show_post_install_info
      ;;
    uninstall)
      check_deps
      confirm
      uninstall_release
      ;;
    status)
      check_deps
      show_status
      ;;
    *)
      die "Unsupported action: ${ACTION}"
      ;;
  esac
}

main "$@"
exit 0

__PAYLOAD_BELOW__
