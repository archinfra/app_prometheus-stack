# Prometheus Stack Version BOM

Release target: `app_prometheus-stack v0.2.0`

| Component | Version |
|---|---:|
| kube-prometheus-stack | 90.2.0 |
| Prometheus Operator | 0.93.1 |
| Prometheus | 3.14.0-distroless |
| Alertmanager | 0.34.0 |
| Grafana Helm chart | 13.2.4 |
| Grafana | 13.2.1-distroless |
| kube-state-metrics Helm chart | 8.4.2 |
| kube-state-metrics | 2.20.0 |
| prometheus-node-exporter Helm chart | 4.57.0 |
| node-exporter | 1.12.1 |
| Thanos | 0.42.4 |
| k8s-sidecar | 2.11.2 |
| kube-rbac-proxy | 0.22.1 |
| kube-webhook-certgen | 1.8.8 |
| Grafana image renderer | 5.10.3 |

## Build model

The release artifact no longer depends on the vendored chart directory being manually kept in sync.
`build.sh` pulls the exact `kube-prometheus-stack` OCI chart version declared in `versions.env`,
embeds it into the `.run` package, and verifies the chart version before packaging.

## Upgrade behavior

- First install: phase 1 installs CRDs/operator, phase 2 installs the complete stack.
- Existing Helm release: bundled CRDs are applied with server-side apply, then a single full-stack Helm upgrade is executed.
- `--skip-crd-upgrade` is available for controlled exception cases.

## Parameter model

Top-level platform defaults are exposed through `-h/--help` and can be overridden by CLI.
For settings not modeled directly by the installer, `--values-file` can be repeated to add site-specific Helm values.
