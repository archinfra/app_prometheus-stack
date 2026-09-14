#!/usr/bin/env bash
set -Eeuo pipefail

APP_VERSION="0.2.0"
STACK_VERSION="90.2.0"
WORKDIR="/tmp/prometheus-stack-installer"
CHART_DIR="${WORKDIR}/charts/kube-prometheus-stack"
IMAGE_DIR="${WORKDIR}/images"
IMAGE_INDEX="${IMAGE_DIR}/image-index.tsv"
VALUES="${WORKDIR}/values.yaml"
PHASE1="${WORKDIR}/phase1.yaml"

ACTION="help"; RELEASE="prometheus-stack"; NS="monitoring"; TIMEOUT="10m"; YES=false
REGISTRY="sealos.hub:5000/kube4"; REGISTRY_SET=false; REGISTRY_USER="admin"; REGISTRY_PASS="passw0rd"; REGISTRY_SECRET=""
PULL_POLICY="IfNotPresent"; SKIP_IMAGES=false; SKIP_CRD_UPGRADE=false; DELETE_CRDS=false
PROM_SC="nfs"; PROM_SIZE="200Gi"; PROM_MODE="ReadWriteOnce"; PROM_RETENTION="14d"; PROM_RETENTION_SIZE="30GiB"; PROM_REPLICAS=1; PROM_SVC="NodePort"; PROM_PORT=30091
AM_SC="nfs"; AM_SIZE="10Gi"; AM_MODE="ReadWriteOnce"; AM_REPLICAS=1; AM_CONFIG=""; ENABLE_AM=true
GRAFANA_SC="nfs"; GRAFANA_SIZE="10Gi"; GRAFANA_MODE="ReadWriteOnce"; GRAFANA_REPLICAS=1; GRAFANA_USER="admin"; GRAFANA_PASS="admin@passw0rd"; GRAFANA_SVC="NodePort"; GRAFANA_PORT=30090; ENABLE_GRAFANA=true
ENABLE_RULES=true; ENABLE_KSM=true; ENABLE_NODE=true
STACK_LABEL_KEY="monitoring.archinfra.io/stack"; STACK_LABEL_VALUE="default"
DASH_LABEL_KEY="grafana_dashboard"; DASH_LABEL_VALUE="1"; DASH_FOLDER_ANNO="grafana_folder"; DASH_NS="ALL"
EXTRA_VALUES=(); HELM_ARGS=(); PAYLOAD_OFFSET=""

CRDS=(alertmanagerconfigs.monitoring.coreos.com alertmanagers.monitoring.coreos.com podmonitors.monitoring.coreos.com probes.monitoring.coreos.com prometheusagents.monitoring.coreos.com prometheuses.monitoring.coreos.com prometheusrules.monitoring.coreos.com scrapeconfigs.monitoring.coreos.com servicemonitors.monitoring.coreos.com thanosrulers.monitoring.coreos.com)

die(){ echo "[ERROR] $*" >&2; exit 1; }
log(){ echo "[INFO] $*"; }
ok(){ echo "[OK] $*"; }
bool(){ [[ "$2" == true || "$2" == false ]] || die "$1 must be true|false"; }
posint(){ [[ "$2" =~ ^[1-9][0-9]*$ ]] || die "$1 must be a positive integer"; }
svc(){ [[ "$2" =~ ^(ClusterIP|NodePort|LoadBalancer)$ ]] || die "$1 must be ClusterIP|NodePort|LoadBalancer"; }
q(){ printf '%s' "$1" | sed "s/'/''/g"; }

help(){
cat <<EOF
Prometheus Stack Offline Installer v${APP_VERSION}
kube-prometheus-stack ${STACK_VERSION}

Usage:
  ./$(basename "$0") <install|uninstall|status|help> [options] [-- <helm_args>]

Core:
  -n, --namespace <ns>                     [default: ${NS}]
  --release-name <name>                    [default: ${RELEASE}]
  --wait-timeout <duration>                [default: ${TIMEOUT}]
  --values-file <path>                     extra Helm values; repeatable

Prometheus:
  --prometheus-storage-class <name>        [default: ${PROM_SC}]
  --prometheus-storage-size <size>         [default: ${PROM_SIZE}]
  --prometheus-storage-access-mode <mode>  [default: ${PROM_MODE}]
  --prometheus-retention <duration>        [default: ${PROM_RETENTION}]
  --prometheus-retention-size <size>       [default: ${PROM_RETENTION_SIZE}]
  --prometheus-replicas <n>                [default: ${PROM_REPLICAS}]
  --prometheus-service-type <type>         [default: ${PROM_SVC}]
  --prometheus-node-port <port>            [default: ${PROM_PORT}]

Alertmanager:
  --alertmanager-storage-class <name>       [default: ${AM_SC}]
  --alertmanager-storage-size <size>        [default: ${AM_SIZE}]
  --alertmanager-storage-access-mode <mode> [default: ${AM_MODE}]
  --alertmanager-replicas <n>               [default: ${AM_REPLICAS}]
  --alertmanager-config-file <path>         [default: null receiver]
  --enable-alertmanager <true|false>        [default: ${ENABLE_AM}]

Grafana:
  --grafana-storage-class <name>            [default: ${GRAFANA_SC}]
  --grafana-storage-size <size>             [default: ${GRAFANA_SIZE}]
  --grafana-storage-access-mode <mode>      [default: ${GRAFANA_MODE}]
  --grafana-replicas <n>                    [default: ${GRAFANA_REPLICAS}]
  --grafana-admin-user <user>               [default: ${GRAFANA_USER}]
  --grafana-admin-password <password>       [default: ${GRAFANA_PASS}]
  --grafana-service-type <type>             [default: ${GRAFANA_SVC}]
  --grafana-node-port <port>                [default: ${GRAFANA_PORT}]
  --enable-grafana <true|false>             [default: ${ENABLE_GRAFANA}]

Discovery / dashboards:
  --stack-label-key <key>                   [default: ${STACK_LABEL_KEY}]
  --stack-label-value <value>               [default: ${STACK_LABEL_VALUE}]
  --dashboard-label-key <key>               [default: ${DASH_LABEL_KEY}]
  --dashboard-label-value <value>           [default: ${DASH_LABEL_VALUE}]
  --dashboard-folder-annotation <key>       [default: ${DASH_FOLDER_ANNO}]
  --dashboard-search-namespace <value>      [default: ${DASH_NS}]
  --enable-default-rules <true|false>       [default: ${ENABLE_RULES}]
  --enable-kube-state-metrics <true|false>  [default: ${ENABLE_KSM}]
  --enable-node-exporter <true|false>       [default: ${ENABLE_NODE}]

Registry:
  --registry <repo-prefix>                  [default: ${REGISTRY}]
  --registry-user <user>                    [default: ${REGISTRY_USER}]
  --registry-password <password>            [default: <hidden>]
  --registry-secret <name>                  [default: <none>]
  --image-pull-policy <policy>              [default: ${PULL_POLICY}]
  --skip-image-prepare

Upgrade / cleanup:
  --skip-crd-upgrade
  --delete-crds

Other:
  -y, --yes
  -h, --help
  -- <helm_args>
EOF
}

need(){ [[ $# -ge 2 ]] || die "missing value for $1"; }
parse(){
  [[ $# -gt 0 ]] || return 0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      install|uninstall|status|help) ACTION="$1"; shift;;
      -n|--namespace) need "$@"; NS="$2"; shift 2;;
      --release-name) need "$@"; RELEASE="$2"; shift 2;;
      --wait-timeout) need "$@"; TIMEOUT="$2"; shift 2;;
      --values-file) need "$@"; EXTRA_VALUES+=("$2"); shift 2;;
      --prometheus-storage-class) need "$@"; PROM_SC="$2"; shift 2;;
      --prometheus-storage-size) need "$@"; PROM_SIZE="$2"; shift 2;;
      --prometheus-storage-access-mode) need "$@"; PROM_MODE="$2"; shift 2;;
      --prometheus-retention) need "$@"; PROM_RETENTION="$2"; shift 2;;
      --prometheus-retention-size) need "$@"; PROM_RETENTION_SIZE="$2"; shift 2;;
      --prometheus-replicas) need "$@"; PROM_REPLICAS="$2"; shift 2;;
      --prometheus-service-type) need "$@"; PROM_SVC="$2"; shift 2;;
      --prometheus-node-port) need "$@"; PROM_PORT="$2"; shift 2;;
      --alertmanager-storage-class) need "$@"; AM_SC="$2"; shift 2;;
      --alertmanager-storage-size) need "$@"; AM_SIZE="$2"; shift 2;;
      --alertmanager-storage-access-mode) need "$@"; AM_MODE="$2"; shift 2;;
      --alertmanager-replicas) need "$@"; AM_REPLICAS="$2"; shift 2;;
      --alertmanager-config-file) need "$@"; AM_CONFIG="$2"; shift 2;;
      --enable-alertmanager) need "$@"; ENABLE_AM="$2"; shift 2;;
      --grafana-storage-class) need "$@"; GRAFANA_SC="$2"; shift 2;;
      --grafana-storage-size) need "$@"; GRAFANA_SIZE="$2"; shift 2;;
      --grafana-storage-access-mode) need "$@"; GRAFANA_MODE="$2"; shift 2;;
      --grafana-replicas) need "$@"; GRAFANA_REPLICAS="$2"; shift 2;;
      --grafana-admin-user) need "$@"; GRAFANA_USER="$2"; shift 2;;
      --grafana-admin-password) need "$@"; GRAFANA_PASS="$2"; shift 2;;
      --grafana-service-type) need "$@"; GRAFANA_SVC="$2"; shift 2;;
      --grafana-node-port) need "$@"; GRAFANA_PORT="$2"; shift 2;;
      --enable-grafana) need "$@"; ENABLE_GRAFANA="$2"; shift 2;;
      --stack-label-key) need "$@"; STACK_LABEL_KEY="$2"; shift 2;;
      --stack-label-value) need "$@"; STACK_LABEL_VALUE="$2"; shift 2;;
      --dashboard-label-key) need "$@"; DASH_LABEL_KEY="$2"; shift 2;;
      --dashboard-label-value) need "$@"; DASH_LABEL_VALUE="$2"; shift 2;;
      --dashboard-folder-annotation) need "$@"; DASH_FOLDER_ANNO="$2"; shift 2;;
      --dashboard-search-namespace) need "$@"; DASH_NS="$2"; shift 2;;
      --enable-default-rules) need "$@"; ENABLE_RULES="$2"; shift 2;;
      --enable-kube-state-metrics) need "$@"; ENABLE_KSM="$2"; shift 2;;
      --enable-node-exporter) need "$@"; ENABLE_NODE="$2"; shift 2;;
      --registry) need "$@"; REGISTRY="$2"; REGISTRY_SET=true; shift 2;;
      --registry-user) need "$@"; REGISTRY_USER="$2"; shift 2;;
      --registry-password) need "$@"; REGISTRY_PASS="$2"; shift 2;;
      --registry-secret) need "$@"; REGISTRY_SECRET="$2"; shift 2;;
      --image-pull-policy) need "$@"; PULL_POLICY="$2"; shift 2;;
      --skip-image-prepare) SKIP_IMAGES=true; shift;;
      --skip-crd-upgrade) SKIP_CRD_UPGRADE=true; shift;;
      --delete-crds) DELETE_CRDS=true; shift;;
      -y|--yes) YES=true; shift;;
      -h|--help) ACTION=help; shift;;
      --) shift; while [[ $# -gt 0 ]]; do HELM_ARGS+=("$1"); shift; done;;
      *) die "unknown argument: $1";;
    esac
  done
}

validate(){
  [[ "$PULL_POLICY" =~ ^(Always|IfNotPresent|Never)$ ]] || die "invalid image pull policy"
  svc --prometheus-service-type "$PROM_SVC"; svc --grafana-service-type "$GRAFANA_SVC"
  bool --enable-alertmanager "$ENABLE_AM"; bool --enable-grafana "$ENABLE_GRAFANA"; bool --enable-default-rules "$ENABLE_RULES"; bool --enable-kube-state-metrics "$ENABLE_KSM"; bool --enable-node-exporter "$ENABLE_NODE"
  posint --prometheus-replicas "$PROM_REPLICAS"; posint --alertmanager-replicas "$AM_REPLICAS"; posint --grafana-replicas "$GRAFANA_REPLICAS"
  [[ "$PROM_SVC" != NodePort || "$PROM_PORT" =~ ^3[0-2][0-9]{3}$ ]] || die "invalid prometheus nodePort"
  [[ "$GRAFANA_SVC" != NodePort || "$GRAFANA_PORT" =~ ^3[0-2][0-9]{3}$ ]] || die "invalid grafana nodePort"
  local f; for f in "${EXTRA_VALUES[@]}"; do [[ -f "$f" ]] || die "values file not found: $f"; done
  [[ -z "$AM_CONFIG" || -f "$AM_CONFIG" ]] || die "alertmanager config not found: $AM_CONFIG"
}

deps(){
  command -v helm >/dev/null || die "helm required"
  command -v kubectl >/dev/null || die "kubectl required"
  [[ "$ACTION" != install || "$SKIP_IMAGES" == true ]] || command -v docker >/dev/null || die "docker required unless --skip-image-prepare"
}

confirm(){
  [[ "$YES" == true ]] && return
  echo "Action=${ACTION} Release=${RELEASE} Namespace=${NS} Stack=${STACK_VERSION}"
  read -r -p "Continue? [y/N] " a
  [[ "$a" =~ ^[Yy]$ ]] || exit 1
}

payload_offset(){
  [[ -n "$PAYLOAD_OFFSET" ]] && return
  local n; n="$(awk '/^__PAYLOAD_BELOW__$/{print NR;exit}' "$0")"; [[ -n "$n" ]] || die "payload marker missing"
  PAYLOAD_OFFSET="$(( $(head -n "$n" "$0" | wc -c) + 1 ))"
  while [[ "$(dd if="$0" bs=1 skip="$((PAYLOAD_OFFSET-1))" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" =~ ^(0a|0d)$ ]]; do PAYLOAD_OFFSET=$((PAYLOAD_OFFSET+1)); done
}
stream(){ payload_offset; tail -c +"$PAYLOAD_OFFSET" "$0"; }
extract(){
  rm -rf "$WORKDIR"; mkdir -p "$WORKDIR"
  if [[ "$SKIP_IMAGES" == true ]]; then stream | tar -xzf - -C "$WORKDIR" ./charts ./images/image-index.tsv >/dev/null
  else stream | tar -xzf - -C "$WORKDIR" >/dev/null; fi
  [[ -d "$CHART_DIR" && -f "$IMAGE_INDEX" ]] || die "invalid embedded payload"
}

declare -A IMG=()
load_meta(){
  local tar load target
  while IFS=$'\t' read -r tar load target; do
    [[ -n "$tar" ]] || continue
    if [[ "$REGISTRY_SET" == true ]]; then target="${REGISTRY}/${target##*/}"; fi
    IMG["${target##*/}"]="$target"
  done < "$IMAGE_INDEX"
}
find_img(){
  local name="$1" k
  for k in "${!IMG[@]}"; do [[ "${k%%:*}" == "$name" ]] && { echo "${IMG[$k]}"; return; }; done
  die "image not found: $name"
}
ireg(){ echo "${1%%/*}"; }
irepo(){ local x="${1#*/}"; echo "${x%:*}"; }
itag(){ echo "${1##*:}"; }

prepare_images(){
  [[ "$SKIP_IMAGES" == true ]] && return
  echo "$REGISTRY_PASS" | docker login "${REGISTRY%%/*}" -u "$REGISTRY_USER" --password-stdin >/dev/null || true
  local tar load target
  while IFS=$'\t' read -r tar load target; do
    [[ -n "$tar" ]] || continue
    [[ "$REGISTRY_SET" == true ]] && target="${REGISTRY}/${target##*/}"
    docker load -i "${IMAGE_DIR}/${tar}" >/dev/null
    [[ "$load" == "$target" ]] || docker tag "$load" "$target"
    docker push "$target" >/dev/null
  done < "$IMAGE_INDEX"
}

write_values(){
  local op reload webhook cert am prom grafana curl busy sidecar renderer rbac ksm node thanos
  op="$(find_img prometheus-operator)"; reload="$(find_img prometheus-config-reloader)"; webhook="$(find_img admission-webhook)"; cert="$(find_img kube-webhook-certgen)"
  am="$(find_img alertmanager)"; prom="$(find_img prometheus)"; grafana="$(find_img grafana)"; curl="$(find_img curl)"; busy="$(find_img busybox)"
  sidecar="$(find_img k8s-sidecar)"; renderer="$(find_img grafana-image-renderer)"; rbac="$(find_img kube-rbac-proxy)"; ksm="$(find_img kube-state-metrics)"; node="$(find_img node-exporter)"; thanos="$(find_img thanos)"

  cat > "$VALUES" <<EOF
commonLabels:
  "${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"
global:
  imagePullSecrets: $( [[ -n "$REGISTRY_SECRET" ]] && printf '[{"name":"%s"}]' "$REGISTRY_SECRET" || printf '[]' )
windowsMonitoring: {enabled: false}
defaultRules: {create: ${ENABLE_RULES}}
prometheusOperator:
  enabled: true
  image: {registry: "$(ireg "$op")", repository: "$(irepo "$op")", tag: "$(itag "$op")", sha: "", pullPolicy: "${PULL_POLICY}"}
  prometheusConfigReloader:
    image: {registry: "$(ireg "$reload")", repository: "$(irepo "$reload")", tag: "$(itag "$reload")", sha: ""}
  thanosImage: {registry: "$(ireg "$thanos")", repository: "$(irepo "$thanos")", tag: "$(itag "$thanos")", sha: ""}
  serviceMonitor:
    additionalLabels: {"${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"}
  admissionWebhooks:
    deployment:
      enabled: true
      image: {registry: "$(ireg "$webhook")", repository: "$(irepo "$webhook")", tag: "$(itag "$webhook")", sha: "", pullPolicy: "${PULL_POLICY}"}
    patch:
      enabled: true
      image: {registry: "$(ireg "$cert")", repository: "$(irepo "$cert")", tag: "$(itag "$cert")", sha: "", pullPolicy: "${PULL_POLICY}"}
alertmanager:
  enabled: ${ENABLE_AM}
  alertmanagerSpec:
    replicas: ${AM_REPLICAS}
    image: {registry: "$(ireg "$am")", repository: "$(irepo "$am")", tag: "$(itag "$am")", sha: ""}
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: "${AM_SC}"
          accessModes: ["${AM_MODE}"]
          resources: {requests: {storage: "${AM_SIZE}"}}
  serviceMonitor:
    additionalLabels: {"${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"}
$(if [[ -n "$AM_CONFIG" ]]; then printf '  tplConfig: false\n  stringConfig: |-\n'; sed 's/^/    /' "$AM_CONFIG"; fi)
prometheus:
  enabled: true
  service: {type: "${PROM_SVC}", nodePort: ${PROM_PORT}}
  prometheusSpec:
    replicas: ${PROM_REPLICAS}
    image: {registry: "$(ireg "$prom")", repository: "$(irepo "$prom")", tag: "$(itag "$prom")", sha: ""}
    retention: "${PROM_RETENTION}"
    retentionSize: "${PROM_RETENTION_SIZE}"
    serviceMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelector: {matchLabels: {"${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"}}
    serviceMonitorNamespaceSelector: {}
    podMonitorSelectorNilUsesHelmValues: false
    podMonitorSelector: {matchLabels: {"${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"}}
    podMonitorNamespaceSelector: {}
    probeSelectorNilUsesHelmValues: false
    probeSelector: {matchLabels: {"${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"}}
    probeNamespaceSelector: {}
    ruleSelectorNilUsesHelmValues: false
    ruleSelector: {matchLabels: {"${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"}}
    ruleNamespaceSelector: {}
    scrapeConfigSelectorNilUsesHelmValues: false
    scrapeConfigSelector: {matchLabels: {"${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"}}
    scrapeConfigNamespaceSelector: {}
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: "${PROM_SC}"
          accessModes: ["${PROM_MODE}"]
          resources: {requests: {storage: "${PROM_SIZE}"}}
grafana:
  enabled: ${ENABLE_GRAFANA}
  replicas: ${GRAFANA_REPLICAS}
  forceDeployDashboards: true
  adminUser: '$(q "$GRAFANA_USER")'
  adminPassword: '$(q "$GRAFANA_PASS")'
  image: {registry: "$(ireg "$grafana")", repository: "$(irepo "$grafana")", tag: "$(itag "$grafana")", sha: "", pullPolicy: "${PULL_POLICY}"}
  downloadDashboardsImage: {registry: "$(ireg "$curl")", repository: "$(irepo "$curl")", tag: "$(itag "$curl")", sha: "", pullPolicy: "${PULL_POLICY}"}
  initChownData:
    image: {registry: "$(ireg "$busy")", repository: "$(irepo "$busy")", tag: "$(itag "$busy")", sha: "", pullPolicy: "${PULL_POLICY}"}
  sidecar:
    image: {registry: "$(ireg "$sidecar")", repository: "$(irepo "$sidecar")", tag: "$(itag "$sidecar")", sha: ""}
    dashboards:
      enabled: true
      label: "${DASH_LABEL_KEY}"
      labelValue: "${DASH_LABEL_VALUE}"
      searchNamespace: "${DASH_NS}"
      folderAnnotation: "${DASH_FOLDER_ANNO}"
    datasources: {enabled: true, defaultDatasourceEnabled: true, isDefaultDatasource: true}
  imageRenderer:
    image: {registry: "$(ireg "$renderer")", repository: "$(irepo "$renderer")", tag: "$(itag "$renderer")", sha: "", pullPolicy: "${PULL_POLICY}"}
  persistence: {enabled: true, type: pvc, size: "${GRAFANA_SIZE}", storageClassName: "${GRAFANA_SC}", accessModes: ["${GRAFANA_MODE}"]}
  service: {type: "${GRAFANA_SVC}", nodePort: ${GRAFANA_PORT}}
  serviceMonitor: {enabled: true, labels: {"${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"}}
kubeStateMetrics:
  enabled: ${ENABLE_KSM}
  image: {registry: "$(ireg "$ksm")", repository: "$(irepo "$ksm")", tag: "$(itag "$ksm")", sha: ""}
  kubeRBACProxy:
    image: {registry: "$(ireg "$rbac")", repository: "$(irepo "$rbac")", tag: "$(itag "$rbac")", sha: ""}
  prometheus:
    monitor:
      additionalLabels: {"${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"}
nodeExporter:
  enabled: ${ENABLE_NODE}
  image: {registry: "$(ireg "$node")", repository: "$(irepo "$node")", tag: "$(itag "$node")", sha: ""}
  kubeRBACProxy:
    image: {registry: "$(ireg "$rbac")", repository: "$(irepo "$rbac")", tag: "$(itag "$rbac")", sha: ""}
  prometheus:
    monitor:
      additionalLabels: {"${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"}
    podMonitor:
      additionalLabels: {"${STACK_LABEL_KEY}": "${STACK_LABEL_VALUE}"}
EOF
  cat > "$PHASE1" <<EOF
crds: {enabled: true}
defaultRules: {create: false}
prometheusOperator: {enabled: true}
prometheus: {enabled: false}
alertmanager: {enabled: false}
grafana: {enabled: false}
kubeStateMetrics: {enabled: false}
nodeExporter: {enabled: false}
thanosRuler: {enabled: false}
EOF
}

release_exists(){ helm status "$RELEASE" -n "$NS" >/dev/null 2>&1; }
crd_upgrade(){
  [[ "$SKIP_CRD_UPGRADE" == true ]] && return
  local d="${CHART_DIR}/charts/crds/crds"; [[ -d "$d" ]] || die "CRD dir missing"
  kubectl apply --server-side --force-conflicts -f "$d" >/dev/null
}
wait_crds(){ local c; for c in "${CRDS[@]}"; do kubectl wait --for=condition=Established --timeout="$TIMEOUT" "crd/$c" >/dev/null; done; }

helm_run(){
  local phase="$1"; shift
  local args=(helm upgrade --install "$RELEASE" "$CHART_DIR" -n "$NS" --create-namespace --wait --wait-for-jobs --timeout "$TIMEOUT" -f "$VALUES")
  [[ "$phase" == first ]] && args+=(-f "$PHASE1")
  local f; for f in "${EXTRA_VALUES[@]}"; do args+=(-f "$f"); done
  args+=("${HELM_ARGS[@]}")
  printf '[INFO] '; printf '%q ' "${args[@]}"; echo
  "${args[@]}"
}

install(){
  extract; load_meta; prepare_images; write_values
  kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS" >/dev/null
  if release_exists; then
    log "existing release detected: CRD apply + single-stage upgrade"
    crd_upgrade; wait_crds; helm_run upgrade
  else
    log "first install: phase 1 CRDs/operator"
    helm_run first; wait_crds
    log "first install: phase 2 full stack"
    helm_run full
  fi
  kubectl get pods,svc,deploy,statefulset,daemonset -n "$NS" -l "app.kubernetes.io/instance=${RELEASE}" || true
  ok "Prometheus Stack ${STACK_VERSION} installed/upgraded"
}

uninstall(){
  release_exists && helm uninstall "$RELEASE" -n "$NS" || true
  if [[ "$DELETE_CRDS" == true ]]; then
    echo "[WARN] deleting CRDs deletes cluster-wide monitoring custom resources"
    local c; for c in "${CRDS[@]}"; do kubectl delete crd "$c" --ignore-not-found >/dev/null || true; done
  fi
}

status(){
  helm status "$RELEASE" -n "$NS" || true
  kubectl get pods,svc,deploy,statefulset,daemonset -n "$NS" -l "app.kubernetes.io/instance=${RELEASE}" || true
}

main(){
  parse "$@"; validate
  case "$ACTION" in
    help) help;;
    install) deps; confirm; install;;
    uninstall) deps; confirm; uninstall;;
    status) deps; status;;
    *) die "unsupported action: $ACTION";;
  esac
}
trap 'rm -rf "$WORKDIR"' EXIT
main "$@"
exit 0

__PAYLOAD_BELOW__
