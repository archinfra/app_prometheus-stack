# app_prometheus-stack

面向 Kubernetes 的 Prometheus Stack 离线交付仓库，目标是把监控底座做成和 `apps_mysql`、`apps_redis` 一致的交付体验：

- 支持 `amd64` / `arm64` 多架构离线安装包
- 通过 `GitHub Actions` 自动构建 `.run` 包与 release
- 安装流程默认分两阶段执行
- 最终 `helm upgrade --install` 显式写入内网镜像地址
- Prometheus 通过统一标签跨 namespace 自动发现 `ServiceMonitor` / `PodMonitor` / `Probe` / `PrometheusRule`

## 1. 自动发现契约

平台统一使用如下标签契约：

- 键：`monitoring.archinfra.io/stack`
- 值：`default`

Prometheus 只会选择带这个标签的监控资源，因此：

- `apps_mysql` 的内置 `ServiceMonitor` 和 addon `ServiceMonitor`
- `apps_redis` 的 `metrics.serviceMonitor`

只要带上同样标签，就会自动被当前监控栈发现，不会误抓第三方资源。

## 2. 两阶段安装逻辑

对外动作只有一个 `install`，内部自动拆成：

1. 先安装 `CRD + Prometheus Operator`
2. 等 CRD Established、Operator Ready
3. 再安装完整监控栈

这样可以避免“CRD 还没起来就申请 ServiceMonitor/Prometheus/Alertmanager 资源”的竞态问题，重复执行也保持幂等。

## 3. 目录说明

- `build.sh`
  构建多架构 `.run` 离线安装包
- `install.sh`
  自解压安装器模板
- `images/image.json`
  多架构镜像定义，构建期会生成 `image-index.tsv`
- `charts/kube-prometheus-stack`
  vendored Helm Chart
- `.github/workflows/build-offline-installer.yml`
  GitHub Actions 构建与 release
- `docs/TESTING.zh-CN.md`
  手工验证方案

## 4. 本地构建

依赖：

- `bash`
- `docker`
- `jq`

示例：

```bash
./build.sh --arch amd64
./build.sh --arch arm64
./build.sh --arch all
```

构建产物位于 `dist/`：

- `prometheus-stack-installer-amd64.run`
- `prometheus-stack-installer-amd64.run.sha256`
- `prometheus-stack-installer-arm64.run`
- `prometheus-stack-installer-arm64.run.sha256`

## 5. 安装器使用

查看帮助：

```bash
./prometheus-stack-installer-amd64.run --help
./prometheus-stack-installer-amd64.run help
```

基础安装：

```bash
./prometheus-stack-installer-amd64.run install \
  --namespace monitoring \
  --grafana-admin-password 'Admin@123' \
  -y
```

如果目标仓库中已经有镜像，可跳过导入和推送：

```bash
./prometheus-stack-installer-amd64.run install \
  --registry sealos.hub:5000/kube4 \
  --skip-image-prepare \
  -y
```

查看状态：

```bash
./prometheus-stack-installer-amd64.run status -n monitoring
```

卸载：

```bash
./prometheus-stack-installer-amd64.run uninstall -n monitoring -y
```

卸载并同时删除 Prometheus Operator CRD：

```bash
./prometheus-stack-installer-amd64.run uninstall -n monitoring --delete-crds -y
```

## 6. 镜像策略

运行镜像统一落到内网仓库风格：

- `sealos.hub:5000/kube4/alertmanager:v0.30.1`
- `sealos.hub:5000/kube4/prometheus-operator:v0.88.1`
- `sealos.hub:5000/kube4/prometheus:v3.9.1`
- `sealos.hub:5000/kube4/grafana:12.3.1`

构建期优先拉取官方上游多架构镜像，再重新打包到离线安装器中。安装时如果没有显式传 `--registry`，会直接推送到这些默认内网地址；如果传了 `--registry harbor.example.com/kube4`，则会把同名镜像重定向到新前缀。

## 7. GitHub Actions 发布

推送到 `main` / `master` 后：

- 自动构建 `amd64` / `arm64`
- 自动上传 Actions artifacts

推送 `v*` tag 后：

- 自动把两种架构的 `.run` 和 `.sha256` 发布到 GitHub Release

推荐流程：

```bash
git push origin main
git tag v0.1.0
git push origin v0.1.0
```
