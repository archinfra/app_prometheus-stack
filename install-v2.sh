#!/usr/bin/env bash
set -Eeuo pipefail

APP_VERSION="0.2.0"
STACK_VERSION="90.2.0"
WORKDIR="/tmp/prometheus-stack-installer"
CHART_DIR="${WORKDIR}/charts/kube-prometheus-stack"
CRD_DIR="${WORKDIR}/crds"
IMAGE_DIR="${WORKDIR}/images"
IMAGE_INDEX="${IMAGE_DIR}/image-index.tsv"
VALUES_FILE="${WORKDIR}/values-generated.yaml"
PHASE1_FILE="${WORKDIR}/values-phase1.yaml"

ACTION="help"
RELEASE="prometheus-stack"
NAMESPACE="monitoring"
WAIT_TIMEOUT="10m"
AUTO_YES="false"

REGISTRY="sealos.hub:5000/kube4"
REGISTRY_EXPLICIT="false"
REGISTRY_USER="admin"
REGISTRY_PASSWORD="passw0rd"
REGISTRY_SECRET=""
IMAGE_PULL_POLICY="IfNotPresent"
SKIP_IMAGE_PREPARE="false"
SKIP_CRD_UPGRADE="false"
DELETE_CRDS="false"

PROMETHEUS_STORAGE_CLASS="nfs"
PROMETHEUS_STORAGE_SIZE="200Gi"
PROMETHEUS_STORAGE_ACCESS_MODE="ReadWriteOnce"
PROMETHEUS_RETENTION="14d"
PROMETHEUS_RETENTION_SIZE="30GiB"
PROMETHEUS_REPLICAS="1"
PROMETHEUS_SERVICE_TYPE="NodePort"
PROMETHEUS_NODE_PORT="30091"

ALERTMANAGER_STORAGE_CLASS="nfs"
ALERTMANAGER_STORAGE_SIZE="10Gi"
ALERTMANAGER_STORAGE_ACCESS_MODE="ReadWriteOnce"
ALERTMANAGER_REPLICAS="1"
ALERTMANAGER_CONFIG_FILE=""
ENABLE_ALERTMANAGER="true"

GRAFANA_STORAGE_CLASS="nfs"
GRAFANA_STORAGE_SIZE="10Gi"
GRAFANA_STORAGE_ACCESS_MODE="ReadWriteOnce"
GRAFANA_REPLICAS="1"
GRAFANA_ADMIN_USER="admin"
GRAFANA_ADMIN_PASSWORD="admin@passw0rd"
GRAFANA_SERVICE_TYPE="NodePort"
GRAFANA_NODE_PORT="30090"
ENABLE_GRAFANA="true"

ENABLE_DEFAULT_RULES="true"
ENABLE_KUBE_STATE_METRICS="true"
ENABLE_NODE_EXPORTER="true"
STACK_LABEL_KEY="monitoring.archinfra.io/stack"
STACK_LABEL_VALUE="default"
DASHBOARD_LABEL_KEY="grafana_dashboard"
DASHBOARD_LABEL_VALUE="1"
DASHBOARD_FOLDER_ANNOTATION="grafana_folder"
DASHBOARD_SEARCH_NAMESPACE="ALL"

EXTRA_VALUES_FILES=()
HELM_ARGS=()
PAYLOAD_OFFSET=""

declare -A IMAGES=()

readonly CRDS=(
  alertmanagerconfigs.monitoring.coreos.com
  alertmanagers.monitoring.coreos.com
  podmonitors.monitoring.coreos.com
  probes.monitoring.coreos.com
  prometheusagents.monitoring.coreos.com
  prometheuses.monitoring.coreos.com
  prometheusrules.monitoring.coreos.com
  scrapeconfigs.monitoring.coreos.com
  servicemonitors.monitoring.coreos.com
  thanosrulers.monitoring.coreos.com
)

log() { echo "[INFO] $*"; }
ok() { echo "[OK] $*"; }
warn() { echo "[WARN] $*" >&2; }
die() { echo "[ERROR] $*" >&2; exit 1; }

program_name() { basename "$0"; }
yaml_quote() { printf '%s' "$1" | sed "s/'/''/g"; }

usage() {
  local cmd="./$(program_name)"
  cat <<EOF
Prometheus Stack Offline Installer v${APP_VERSION}
kube-prometheus-stack ${STACK_VERSION}

Usage:
  ${cmd} <install|uninstall|status|help> [options] [-- <helm_args>]
  ${cmd} -h|--help

Actions:
  install       Install a new stack or upgrade an existing release
  uninstall     Uninstall the Helm release; CRDs are preserved by default
  status        Show Helm release, CRD and workload status
  help          Show this help

Core:
  -n, --namespace <ns>                       [default: ${NAMESPACE}]
  --release-name <name>                      [default: ${RELEASE}]
  --wait-timeout <duration>                  [default: ${WAIT_TIMEOUT}]
  --values-file <path>                       Extra Helm values file; repeatable [default: none]

Prometheus:
  --prometheus-storage-class <name>          [default: ${PROMETHEUS_STORAGE_CLASS}]
  --prometheus-storage-size <size>           [default: ${PROMETHEUS_STORAGE_SIZE}]
  --prometheus-storage-access-mode <mode>    [default: ${PROMETHEUS_STORAGE_ACCESS_MODE}]
  --prometheus-retention <duration>          [default: ${PROMETHEUS_RETENTION}]
  --prometheus-retention-size <size>         [default: ${PROMETHEUS_RETENTION_SIZE}]
  --prometheus-replicas <n>                  [default: ${PROMETHEUS_REPLICAS}]
  --prometheus-service-type <type>           ClusterIP|NodePort|LoadBalancer [default: ${PROMETHEUS_SERVICE_TYPE}]
  --prometheus-node-port <port>              [default: ${PROMETHEUS_NODE_PORT}]

Alertmanager:
  --alertmanager-storage-class <name>         [default: ${ALERTMANAGER_STORAGE_CLASS}]
  --alertmanager-storage-size <size>          [default: ${ALERTMANAGER_STORAGE_SIZE}]
  --alertmanager-storage-access-mode <mode>  [default: ${ALERTMANAGER_STORAGE_ACCESS_MODE}]
  --alertmanager-replicas <n>                [default: ${ALERTMANAGER_REPLICAS}]
  --alertmanager-config-file <path>           [default: null receiver]
  --enable-alertmanager <true|false>          [default: ${ENABLE_ALERTMANAGER}]

Grafana:
  --grafana-storage-class <name>              [default: ${GRAFANA_STORAGE_CLASS}]
  --grafana-storage-size <size>               [default: ${GRAFANA_STORAGE_SIZE}]
  --grafana-storage-access-mode <mode>        [default: ${GRAFANA_STORAGE_ACCESS_MODE}]
  --grafana-replicas <n>                      [default: ${GRAFANA_REPLICAS}]
  --grafana-admin-user <user>                 [default: ${GRAFANA_ADMIN_USER}]
  --grafana-admin-password <password>         [default: ${GRAFANA_ADMIN_PASSWORD}]
  --grafana-service-type <type>               ClusterIP|NodePort|LoadBalancer [default: ${GRAFANA_SERVICE_TYPE}]
  --grafana-node-port <port>                  [default: ${GRAFANA_NODE_PORT}]
  --enable-grafana <true|false>               [default: ${ENABLE_GRAFANA}]

Discovery / dashboards:
  --stack-label-key <key>                     [default: ${STACK_LABEL_KEY}]
  --stack-label-value <value>                 [default: ${STACK_LABEL_VALUE}]
  --dashboard-label-key <key>                 [default: ${DASHBOARD_LABEL_KEY}]
  --dashboard-label-value <value>             [default: ${DASHBOARD_LABEL_VALUE}]
  --dashboard-folder-annotation <key>         [default: ${DASHBOARD_FOLDER_ANNOTATION}]
  --dashboard-search-namespace <value>        [default: ${DASHBOARD_SEARCH_NAMESPACE}]
  --enable-default-rules <true|false>         [default: ${ENABLE_DEFAULT_RULES}]
  --enable-kube-state-metrics <true|false>    [default: ${ENABLE_KUBE_STATE_METRICS}]
  --enable-node-exporter <true|false>         [default: ${ENABLE_NODE_EXPORTER}]

Registry / images:
  --registry <repo-prefix>                    [default: ${REGISTRY}]
  --registry-user <user>                      [default: ${REGISTRY_USER}]
  --registry-password <password>              [default: <hidden>]
  --registry-secret <name>                    Kubernetes imagePullSecret [default: none]
  --image-pull-policy <policy>                Always|IfNotPresent|Never [default: ${IMAGE_PULL_POLICY}]
  --skip-image-prepare                        Reuse images already present in registry [default: false]

Upgrade / cleanup:
  --skip-crd-upgrade                          Do not apply bundled CRDs before upgrade [default: false]
  --delete-crds                               Delete monitoring CRDs during uninstall [default: false]

Other:
  -y, --yes                                   Skip confirmation [default: false]
  -h, --help                                  Show help
  -- <helm_args>                              Pass remaining arguments directly to Helm

Examples:
  ${cmd} install -n monitoring --grafana-admin-password 'Admin@123' -y
  ${cmd} install --prometheus-retention 30d --prometheus-retention-size 160GiB -y
  ${cmd} install --registry harbor.example.com/monitoring --registry-secret harbor-pull -y
  ${cmd} install --values-file ./site-values.yaml -y
  ${cmd} status -n monitoring
EOF
}

require_value() { [[ $# -ge 2 ]] || die "Missing value for $1"; }

parse_args() {
  [[ $# -gt 0 ]] || return 0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      install|uninstall|status|help) ACTION="$1"; shift ;;
      -n|--namespace) require_value "$@"; NAMESPACE="$2"; shift 2 ;;
      --release-name) require_value "$@"; RELEASE="$2"; shift 2 ;;
      --wait-timeout) require_value "$@"; WAIT_TIMEOUT="$2"; shift 2 ;;
      --values-file) require_value "$@"; EXTRA_VALUES_FILES+=("$2"); shift 2 ;;
      --prometheus-storage-class) require_value "$@"; PROMETHEUS_STORAGE_CLASS="$2"; shift 2 ;;
      --prometheus-storage-size) require_value "$@"; PROMETHEUS_STORAGE_SIZE="$2"; shift 2 ;;
      --prometheus-storage-access-mode) require_value "$@"; PROMETHEUS_STORAGE_ACCESS_MODE="$2"; shift 2 ;;
      --prometheus-retention) require_value "$@"; PROMETHEUS_RETENTION="$2"; shift 2 ;;
      --prometheus-retention-size) require_value "$@"; PROMETHEUS_RETENTION_SIZE="$2"; shift 2 ;;
      --prometheus-replicas) require_value "$@"; PROMETHEUS_REPLICAS="$2"; shift 2 ;;
      --prometheus-service-type) require_value "$@"; PROMETHEUS_SERVICE_TYPE="$2"; shift 2 ;;
      --prometheus-node-port) require_value "$@"; PROMETHEUS_NODE_PORT="$2"; shift 2 ;;
      --alertmanager-storage-class) require_value "$@"; ALERTMANAGER_STORAGE_CLASS="$2"; shift 2 ;;
      --alertmanager-storage-size) require_value "$@"; ALERTMANAGER_STORAGE_SIZE="$2"; shift 2 ;;
      --alertmanager-storage-access-mode) require_value "$@"; ALERTMANAGER_STORAGE_ACCESS_MODE="$2"; shift 2 ;;
      --alertmanager-replicas) require_value "$@"; ALERTMANAGER_REPLICAS="$2"; shift 2 ;;
      --alertmanager-config-file) require_value "$@"; ALERTMANAGER_CONFIG_FILE="$2"; shift 2 ;;
      --enable-alertmanager) require_value "$@"; ENABLE_ALERTMANAGER="$2"; shift 2 ;;
      --grafana-storage-class) require_value "$@"; GRAFANA_STORAGE_CLASS="$2"; shift 2 ;;
      --grafana-storage-size) require_value "$@"; GRAFANA_STORAGE_SIZE="$2"; shift 2 ;;
      --grafana-storage-access-mode) require_value "$@"; GRAFANA_STORAGE_ACCESS_MODE="$2"; shift 2 ;;
      --grafana-replicas) require_value "$@"; GRAFANA_REPLICAS="$2"; shift 2 ;;
      --grafana-admin-user) require_value "$@"; GRAFANA_ADMIN_USER="$2"; shift 2 ;;
      --grafana-admin-password) require_value "$@"; GRAFANA_ADMIN_PASSWORD="$2"; shift 2 ;;
      --grafana-service-type) require_value "$@"; GRAFANA_SERVICE_TYPE="$2"; shift 2 ;;
      --grafana-node-port) require_value "$@"; GRAFANA_NODE_PORT="$2"; shift 2 ;;
      --enable-grafana) require_value "$@"; ENABLE_GRAFANA="$2"; shift 2 ;;
      --stack-label-key) require_value "$@"; STACK_LABEL_KEY="$2"; shift 2 ;;
      --stack-label-value) require_value "$@"; STACK_LABEL_VALUE="$2"; shift 2 ;;
      --dashboard-label-key) require_value "$@"; DASHBOARD_LABEL_KEY="$2"; shift 2 ;;
      --dashboard-label-value) require_value "$@"; DASHBOARD_LABEL_VALUE="$2"; shift 2 ;;
      --dashboard-folder-annotation) require_value "$@"; DASHBOARD_FOLDER_ANNOTATION="$2"; shift 2 ;;
      --dashboard-search-namespace) require_value "$@"; DASHBOARD_SEARCH_NAMESPACE="$2"; shift 2 ;;
      --enable-default-rules) require_value "$@"; ENABLE_DEFAULT_RULES="$2"; shift 2 ;;
      --enable-kube-state-metrics) require_value "$@"; ENABLE_KUBE_STATE_METRICS="$2"; shift 2 ;;
      --enable-node-exporter) require_value "$@"; ENABLE_NODE_EXPORTER="$2"; shift 2 ;;
      --registry) require_value "$@"; REGISTRY="$2"; REGISTRY_EXPLICIT="true"; shift 2 ;;
      --registry-user) require_value "$@"; REGISTRY_USER="$2"; shift 2 ;;
      --registry-password) require_value "$@"; REGISTRY_PASSWORD="$2"; shift 2 ;;
      --registry-secret) require_value "$@"; REGISTRY_SECRET="$2"; shift 2 ;;
      --image-pull-policy) require_value "$@"; IMAGE_PULL_POLICY="$2"; shift 2 ;;
      --skip-image-prepare) SKIP_IMAGE_PREPARE="true"; shift ;;
      --skip-crd-upgrade) SKIP_CRD_UPGRADE="true"; shift ;;
      --delete-crds) DELETE_CRDS="true"; shift ;;
      -y|--yes) AUTO_YES="true"; shift ;;
      -h|--help) ACTION="help"; shift ;;
      --) shift; while [[ $# -gt 0 ]]; do HELM_ARGS+=("$1"); shift; done; break ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
}

validate_bool() { [[ "$2" == "true" || "$2" == "false" ]] || die "$1 must be true|false"; }
validate_positive_int() { [[ "$2" =~ ^[1-9][0-9]*$ ]] || die "$1 must be a positive integer"; }
validate_service_type() { [[ "$2" =~ ^(ClusterIP|NodePort|LoadBalancer)$ ]] || die "$1 must be ClusterIP|NodePort|LoadBalancer"; }
validate_node_port() {
  local name="$1" value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || die "$name must be numeric"
  (( value >= 30000 && value <= 32767 )) || die "$name must be within 30000-32767"
}

validate_args() {
  [[ "$IMAGE_PULL_POLICY" =~ ^(Always|IfNotPresent|Never)$ ]] || die "Unsupported image pull policy: ${IMAGE_PULL_POLICY}"
  validate_service_type --prometheus-service-type "$PROMETHEUS_SERVICE_TYPE"
  validate_service_type --grafana-service-type "$GRAFANA_SERVICE_TYPE"
  validate_bool --enable-alertmanager "$ENABLE_ALERTMANAGER"
  validate_bool --enable-grafana "$ENABLE_GRAFANA"
  validate_bool --enable-default-rules "$ENABLE_DEFAULT_RULES"
  validate_bool --enable-kube-state-metrics "$ENABLE_KUBE_STATE_METRICS"
  validate_bool --enable-node-exporter "$ENABLE_NODE_EXPORTER"
  validate_positive_int --prometheus-replicas "$PROMETHEUS_REPLICAS"
  validate_positive_int --alertmanager-replicas "$ALERTMANAGER_REPLICAS"
  validate_positive_int --grafana-replicas "$GRAFANA_REPLICAS"
  [[ "$PROMETHEUS_SERVICE_TYPE" != "NodePort" ]] || validate_node_port --prometheus-node-port "$PROMETHEUS_NODE_PORT"
  [[ "$GRAFANA_SERVICE_TYPE" != "NodePort" ]] || validate_node_port --grafana-node-port "$GRAFANA_NODE_PORT"

  local file
  for file in "${EXTRA_VALUES_FILES[@]}"; do
    [[ -f "$file" ]] || die "Values file not found: $file"
  done
  [[ -z "$ALERTMANAGER_CONFIG_FILE" || -f "$ALERTMANAGER_CONFIG_FILE" ]] || die "Alertmanager config file not found: ${ALERTMANAGER_CONFIG_FILE}"
}

check_deps() {
  command -v helm >/dev/null 2>&1 || die "helm is required"
  command -v kubectl >/dev/null 2>&1 || die "kubectl is required"
  if [[ "$ACTION" == "install" && "$SKIP_IMAGE_PREPARE" != "true" ]]; then
    command -v docker >/dev/null 2>&1 || die "docker is required unless --skip-image-prepare is used"
  fi
}

confirm() {
  [[ "$AUTO_YES" == "true" ]] && return 0
  echo "Action                    : ${ACTION}"
  echo "Release                   : ${RELEASE}"
  echo "Namespace                 : ${NAMESPACE}"
  echo "kube-prometheus-stack     : ${STACK_VERSION}"
  if [[ "$ACTION" == "install" ]]; then
    echo "Prometheus storage        : ${PROMETHEUS_STORAGE_CLASS}/${PROMETHEUS_STORAGE_SIZE}/${PROMETHEUS_STORAGE_ACCESS_MODE}"
    echo "Prometheus retention      : ${PROMETHEUS_RETENTION}/${PROMETHEUS_RETENTION_SIZE}"
    echo "Prometheus replicas       : ${PROMETHEUS_REPLICAS}"
    echo "Grafana replicas          : ${GRAFANA_REPLICAS}"
    echo "Alertmanager replicas     : ${ALERTMANAGER_REPLICAS}"
    echo "Registry                  : ${REGISTRY}"
    echo "Registry pull secret      : ${REGISTRY_SECRET:-<none>}"
    echo "Extra values files        : ${EXTRA_VALUES_FILES[*]:-<none>}"
  fi
  echo
  read -r -p "Continue? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || die "Cancelled"
}

init_payload_offset() {
  [[ -n "$PAYLOAD_OFFSET" ]] && return 0
  local marker_line offset byte_hex
  marker_line="$(awk '/^__PAYLOAD_BELOW__$/ {print NR; exit}' "$0")"
  [[ -n "$marker_line" ]] || die "Unable to locate embedded payload"
  offset="$(( $(head -n "$marker_line" "$0" | wc -c | tr -d ' ') + 1 ))"
  while :; do
    byte_hex="$(dd if="$0" bs=1 skip="$((offset - 1))" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    case "$byte_hex" in
      0a|0d) offset=$((offset + 1)) ;;
      "") die "Invalid payload boundary" ;;
      *) break ;;
    esac
  done
  PAYLOAD_OFFSET="$offset"
}

payload_stream() { init_payload_offset; tail -c +"${PAYLOAD_OFFSET}" "$0"; }

extract_payload() {
  rm -rf "$WORKDIR"
  mkdir -p "$WORKDIR"
  if [[ "$SKIP_IMAGE_PREPARE" == "true" ]]; then
    payload_stream | tar -xzf - -C "$WORKDIR" ./charts ./crds ./images/image-index.tsv >/dev/null
  else
    payload_stream | tar -xzf - -C "$WORKDIR" >/dev/null
  fi
  [[ -d "$CHART_DIR" ]] || die "Missing chart payload"
  [[ -d "$CRD_DIR" ]] || die "Missing CRD payload"
  [[ -f "$IMAGE_INDEX" ]] || die "Missing image metadata payload"
}

resolve_target_ref() {
  local default_ref="$1"
  if [[ "$REGISTRY_EXPLICIT" == "true" ]]; then
    echo "${REGISTRY}/${default_ref##*/}"
  else
    echo "$default_ref"
  fi
}

load_image_metadata() {
  local tar_name load_ref target_ref
  while IFS=$'\t' read -r tar_name load_ref target_ref; do
    [[ -n "$tar_name" ]] || continue
    target_ref="$(resolve_target_ref "$target_ref")"
    IMAGES["${target_ref##*/}"]="$target_ref"
  done < "$IMAGE_INDEX"
}

find_image() {
  local name="$1" key
  for key in "${!IMAGES[@]}"; do
    if [[ "${key%%:*}" == "$name" ]]; then
      echo "${IMAGES[$key]}"
      return 0
    fi
  done
  die "Unable to resolve image: ${name}"
}

image_registry() { echo "${1%%/*}"; }
image_repository() { local rest="${1#*/}"; echo "${rest%:*}"; }
image_tag() { echo "${1##*:}"; }

prepare_images() {
  [[ "$SKIP_IMAGE_PREPARE" == "true" ]] && { log "Skipping image prepare"; return 0; }

  local registry_host="${REGISTRY%%/*}"
  if ! echo "$REGISTRY_PASSWORD" | docker login "$registry_host" -u "$REGISTRY_USER" --password-stdin >/dev/null 2>&1; then
    warn "docker login failed for ${registry_host}; push will determine whether anonymous access is allowed"
  fi

  local tar_name load_ref default_ref target_ref tar_path
  while IFS=$'\t' read -r tar_name load_ref default_ref; do
    [[ -n "$tar_name" ]] || continue
    tar_path="${IMAGE_DIR}/${tar_name}"
    [[ -f "$tar_path" ]] || die "Missing image tar: ${tar_path}"
    target_ref="$(resolve_target_ref "$default_ref")"
    log "Loading ${tar_name}"
    docker load -i "$tar_path" >/dev/null
    [[ "$load_ref" == "$target_ref" ]] || docker tag "$load_ref" "$target_ref"
    log "Pushing ${target_ref}"
    docker push "$target_ref" >/dev/null
    if [[ "${tar_name}" == *node-exporter* ]]; then
      local dist="${target_ref}-distroless"
      log "Pushing node-exporter -distroless tag ${dist}"
      docker tag "${target_ref}" "${dist}" >/dev/null 2>&1 || true
      docker push "${dist}" >/dev/null 2>&1 || true
    fi
  done < "$IMAGE_INDEX"
}

write_pull_secret_values() {
  if [[ -n "$REGISTRY_SECRET" ]]; then
    cat <<EOF
  imagePullSecrets:
    - name: "${REGISTRY_SECRET}"
EOF
  else
    echo "  imagePullSecrets: []"
  fi
}

write_values() {
  local operator reloader webhook certgen alertmanager prometheus thanos grafana curl busybox sidecar renderer rbac ksm node
  operator="$(find_image prometheus-operator)"
  reloader="$(find_image prometheus-config-reloader)"
  webhook="$(find_image admission-webhook)"
  certgen="$(find_image kube-webhook-certgen)"
  alertmanager="$(find_image alertmanager)"
  prometheus="$(find_image prometheus)"
  thanos="$(find_image thanos)"
  grafana="$(find_image grafana)"
  curl="$(find_image curl)"
  busybox="$(find_image busybox)"
  sidecar="$(find_image k8s-sidecar)"
  renderer="$(find_image grafana-image-renderer)"
  rbac="$(find_image kube-rbac-proxy)"
  ksm="$(find_image kube-state-metrics)"
  node="$(find_image node-exporter)"

  cat > "$VALUES_FILE" <<EOF
commonLabels:
  "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
global:
$(write_pull_secret_values)
windowsMonitoring:
  enabled: false
defaultRules:
  create: ${ENABLE_DEFAULT_RULES}

prometheusOperator:
  enabled: true
  image:
    registry: "$(image_registry "$operator")"
    repository: "$(image_repository "$operator")"
    tag: "$(image_tag "$operator")"
    sha: ""
    pullPolicy: "${IMAGE_PULL_POLICY}"
  prometheusConfigReloader:
    image:
      registry: "$(image_registry "$reloader")"
      repository: "$(image_repository "$reloader")"
      tag: "$(image_tag "$reloader")"
      sha: ""
  thanosImage:
    registry: "$(image_registry "$thanos")"
    repository: "$(image_repository "$thanos")"
    tag: "$(image_tag "$thanos")"
    sha: ""
  serviceMonitor:
    additionalLabels:
      "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
  admissionWebhooks:
    deployment:
      enabled: true
      image:
        registry: "$(image_registry "$webhook")"
        repository: "$(image_repository "$webhook")"
        tag: "$(image_tag "$webhook")"
        sha: ""
        pullPolicy: "${IMAGE_PULL_POLICY}"
    patch:
      enabled: true
      image:
        registry: "$(image_registry "$certgen")"
        repository: "$(image_repository "$certgen")"
        tag: "$(image_tag "$certgen")"
        sha: ""
        pullPolicy: "${IMAGE_PULL_POLICY}"

alertmanager:
  enabled: ${ENABLE_ALERTMANAGER}
  alertmanagerSpec:
    replicas: ${ALERTMANAGER_REPLICAS}
    image:
      registry: "$(image_registry "$alertmanager")"
      repository: "$(image_repository "$alertmanager")"
      tag: "$(image_tag "$alertmanager")"
      sha: ""
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: "${ALERTMANAGER_STORAGE_CLASS}"
          accessModes:
            - "${ALERTMANAGER_STORAGE_ACCESS_MODE}"
          resources:
            requests:
              storage: "${ALERTMANAGER_STORAGE_SIZE}"
  serviceMonitor:
    additionalLabels:
      "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
$(if [[ -n "$ALERTMANAGER_CONFIG_FILE" ]]; then
  printf '  tplConfig: false\n'
  printf '  stringConfig: |-\n'
  sed 's/^/    /' "$ALERTMANAGER_CONFIG_FILE"
fi)

prometheus:
  enabled: true
  service:
    type: "${PROMETHEUS_SERVICE_TYPE}"
    nodePort: ${PROMETHEUS_NODE_PORT}
  serviceMonitor:
    additionalLabels:
      "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
  thanosServiceMonitor:
    additionalLabels:
      "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
  prometheusSpec:
    replicas: ${PROMETHEUS_REPLICAS}
    image:
      registry: "$(image_registry "$prometheus")"
      repository: "$(image_repository "$prometheus")"
      tag: "$(image_tag "$prometheus")"
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
            - "${PROMETHEUS_STORAGE_ACCESS_MODE}"
          resources:
            requests:
              storage: "${PROMETHEUS_STORAGE_SIZE}"

grafana:
  enabled: ${ENABLE_GRAFANA}
  replicas: ${GRAFANA_REPLICAS}
  forceDeployDashboards: true
  adminUser: '$(yaml_quote "$GRAFANA_ADMIN_USER")'
  adminPassword: '$(yaml_quote "$GRAFANA_ADMIN_PASSWORD")'
  extraLabels:
    "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
  image:
    registry: "$(image_registry "$grafana")"
    repository: "$(image_repository "$grafana")"
    tag: "$(image_tag "$grafana")"
    sha: ""
    pullPolicy: "${IMAGE_PULL_POLICY}"
  downloadDashboardsImage:
    registry: "$(image_registry "$curl")"
    repository: "$(image_repository "$curl")"
    tag: "$(image_tag "$curl")"
    sha: ""
    pullPolicy: "${IMAGE_PULL_POLICY}"
  initChownData:
    image:
      registry: "$(image_registry "$busybox")"
      repository: "$(image_repository "$busybox")"
      tag: "$(image_tag "$busybox")"
      sha: ""
      pullPolicy: "${IMAGE_PULL_POLICY}"
  sidecar:
    image:
      registry: "$(image_registry "$sidecar")"
      repository: "$(image_repository "$sidecar")"
      tag: "$(image_tag "$sidecar")"
      sha: ""
    dashboards:
      enabled: true
      label: "${DASHBOARD_LABEL_KEY}"
      labelValue: "${DASHBOARD_LABEL_VALUE}"
      searchNamespace: "${DASHBOARD_SEARCH_NAMESPACE}"
      folderAnnotation: "${DASHBOARD_FOLDER_ANNOTATION}"
      provider:
        allowUiUpdates: false
    datasources:
      enabled: true
      defaultDatasourceEnabled: true
      isDefaultDatasource: true
      alertmanager:
        enabled: true
  imageRenderer:
    image:
      registry: "$(image_registry "$renderer")"
      repository: "$(image_repository "$renderer")"
      tag: "$(image_tag "$renderer")"
      sha: ""
      pullPolicy: "${IMAGE_PULL_POLICY}"
  persistence:
    enabled: true
    type: pvc
    size: "${GRAFANA_STORAGE_SIZE}"
    storageClassName: "${GRAFANA_STORAGE_CLASS}"
    accessModes:
      - "${GRAFANA_STORAGE_ACCESS_MODE}"
  service:
    type: "${GRAFANA_SERVICE_TYPE}"
    nodePort: ${GRAFANA_NODE_PORT}
    labels:
      "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
  serviceMonitor:
    enabled: true
    labels:
      "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"

kubeStateMetrics:
  enabled: ${ENABLE_KUBE_STATE_METRICS}
kube-state-metrics:
  image:
    registry: "$(image_registry "$ksm")"
    repository: "$(image_repository "$ksm")"
    tag: "$(image_tag "$ksm")"
    sha: ""
    pullPolicy: "${IMAGE_PULL_POLICY}"
  kubeRBACProxy:
    image:
      registry: "$(image_registry "$rbac")"
      repository: "$(image_repository "$rbac")"
      tag: "$(image_tag "$rbac")"
      sha: ""
      pullPolicy: "${IMAGE_PULL_POLICY}"
  prometheus:
    monitor:
      additionalLabels:
        "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"

nodeExporter:
  enabled: ${ENABLE_NODE_EXPORTER}
prometheus-node-exporter:
  image:
    registry: "$(image_registry "$node")"
    repository: "$(image_repository "$node")"
    tag: "$(image_tag "$node")"
    pullPolicy: "${IMAGE_PULL_POLICY}"
  kubeRBACProxy:
    image:
      registry: "$(image_registry "$rbac")"
      repository: "$(image_repository "$rbac")"
      tag: "$(image_tag "$rbac")"
      sha: ""
      pullPolicy: "${IMAGE_PULL_POLICY}"
  prometheus:
    monitor:
      additionalLabels:
        "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
    podMonitor:
      additionalLabels:
        "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
EOF

  cat > "$PHASE1_FILE" <<EOF
crds:
  enabled: true
defaultRules:
  create: false
prometheusOperator:
  enabled: true
prometheus:
  enabled: true
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
}

release_exists() { helm status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; }

apply_bundled_crds() {
  [[ "$SKIP_CRD_UPGRADE" == "true" ]] && { log "Skipping bundled CRD apply"; return 0; }
  log "Applying bundled Prometheus Operator CRDs"
  kubectl apply --server-side --force-conflicts -f "$CRD_DIR" >/dev/null
}

wait_for_crds() {
  local crd
  for crd in "${CRDS[@]}"; do
    kubectl wait --for=condition=Established --timeout="$WAIT_TIMEOUT" "crd/${crd}" >/dev/null
  done
}

helm_run() {
  local phase="$1"
  local -a cmd=(
    helm upgrade --install "$RELEASE" "$CHART_DIR"
    -n "$NAMESPACE"
    --create-namespace
    --wait
    --wait-for-jobs
    --timeout "$WAIT_TIMEOUT"
    -f "$VALUES_FILE"
  )

  [[ "$phase" == "first" ]] && cmd+=(-f "$PHASE1_FILE")

  local file
  for file in "${EXTRA_VALUES_FILES[@]}"; do
    cmd+=(-f "$file")
  done
  cmd+=("${HELM_ARGS[@]}")

  printf '[INFO] Helm: '
  printf '%q ' "${cmd[@]}"
  echo
  "${cmd[@]}"
}

install_stack() {
  extract_payload
  load_image_metadata
  prepare_images
  write_values

  kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE" >/dev/null

  if release_exists; then
    log "Existing release detected: CRD apply + single-stage Helm upgrade"
    apply_bundled_crds
    wait_for_crds
    helm_run upgrade
  else
    log "First install: applying bundled CRDs"
    apply_bundled_crds
    wait_for_crds
    log "First install phase 1: Prometheus Operator"
    helm_run first
    log "First install phase 2: full monitoring stack"
    helm_run full
  fi

  kubectl get pods,svc,deploy,statefulset,daemonset -n "$NAMESPACE" -l "app.kubernetes.io/instance=${RELEASE}" || true
  ok "Prometheus Stack ${STACK_VERSION} install/upgrade completed"
}

uninstall_stack() {
  if release_exists; then
    helm uninstall "$RELEASE" -n "$NAMESPACE"
  else
    warn "Helm release ${RELEASE} not found in namespace ${NAMESPACE}"
  fi

  if [[ "$DELETE_CRDS" == "true" ]]; then
    warn "Deleting CRDs also deletes cluster-wide monitoring custom resources"
    local crd
    for crd in "${CRDS[@]}"; do
      kubectl delete crd "$crd" --ignore-not-found >/dev/null || true
    done
  fi
}

show_status() {
  echo "Installer version          : ${APP_VERSION}"
  echo "kube-prometheus-stack     : ${STACK_VERSION}"
  helm status "$RELEASE" -n "$NAMESPACE" || true
  echo
  kubectl get pods,svc,deploy,statefulset,daemonset -n "$NAMESPACE" -l "app.kubernetes.io/instance=${RELEASE}" || true
  echo
  local crd
  for crd in "${CRDS[@]}"; do
    kubectl get crd "$crd" >/dev/null 2>&1 && echo "[OK] ${crd}" || echo "[--] ${crd}"
  done
}

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

main() {
  parse_args "$@"
  validate_args

  case "$ACTION" in
    help) usage ;;
    install) check_deps; confirm; install_stack ;;
    uninstall) check_deps; confirm; uninstall_stack ;;
    status) check_deps; show_status ;;
    *) die "Unsupported action: ${ACTION}" ;;
  esac
}

main "$@"
exit 0

__PAYLOAD_BELOW__
