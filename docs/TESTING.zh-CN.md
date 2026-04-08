# app_prometheus-stack 手工测试方案

## 1. 目标

验证当前仓库已经真实具备这些能力：

- `amd64` / `arm64` 双架构离线构建
- `.run` 安装器可执行 `install|uninstall|status|help`
- 安装流程按“两阶段”执行
- CRD 与 Operator 先就绪，再申请完整监控资源
- Prometheus 只发现带 `monitoring.archinfra.io/stack=default` 标签的监控资源
- MySQL / Redis 的 `ServiceMonitor` 可自动接入

## 2. 静态校验

在仓库根目录执行：

```bash
bash -n build.sh install.sh
python - <<'PY'
import json, pathlib
path = pathlib.Path("images/image.json")
data = json.loads(path.read_text(encoding="utf-8"))
assert any(item["arch"] == "amd64" for item in data)
assert any(item["arch"] == "arm64" for item in data)
print("image.json ok")
PY
./install.sh --help
./install.sh help
```

重点确认：

- 帮助里有 `install|uninstall|status|help`
- 帮助里有 `--skip-image-prepare`
- 帮助里有 `--delete-crds`
- 帮助里有存储和 Grafana 管理员密码参数

## 3. GitHub Actions 校验

### 3.1 `main` 分支构建

确认 `build-offline-installer.yml` 在 `main` 推送后触发：

- `amd64` job 成功
- `arm64` job 成功

产物应包含：

- `prometheus-stack-installer-amd64.run`
- `prometheus-stack-installer-amd64.run.sha256`
- `prometheus-stack-installer-arm64.run`
- `prometheus-stack-installer-arm64.run.sha256`

### 3.2 `v*` tag release

打 tag 后确认 release 页面包含四个文件：

- `prometheus-stack-installer-amd64.run`
- `prometheus-stack-installer-amd64.run.sha256`
- `prometheus-stack-installer-arm64.run`
- `prometheus-stack-installer-arm64.run.sha256`

## 4. 安装链路验证

### 4.1 首次安装

```bash
./prometheus-stack-installer-amd64.run install \
  --namespace monitoring \
  --grafana-admin-password 'Admin@123' \
  -y
```

确认点：

1. 安装日志先出现“阶段一: 安装 CRD 与 Prometheus Operator”
2. 随后出现“等待 CRD 就绪”
3. 再出现“阶段二: 安装完整监控栈”
4. 最终 `kubectl get` 能看到 operator、Prometheus、Alertmanager、Grafana、kube-state-metrics、node-exporter

检查命令：

```bash
kubectl get crd | grep monitoring.coreos.com
kubectl get deploy,statefulset,daemonset -n monitoring
kubectl get prometheus,alertmanager,servicemonitor,podmonitor,prometheusrule -n monitoring
```

### 4.2 幂等安装

再次执行同一条安装命令：

```bash
./prometheus-stack-installer-amd64.run install \
  --namespace monitoring \
  --grafana-admin-password 'Admin@123' \
  -y
```

确认点：

- 不应因为 CRD 已存在而失败
- 不应因为 release 已存在而失败
- 资源状态仍保持 Ready

### 4.3 状态查看

```bash
./prometheus-stack-installer-amd64.run status -n monitoring
```

确认点：

- 能展示 CRD 状态
- 能展示 Helm 状态
- 能展示部署后的工作负载

## 5. 自动发现验证

### 5.1 MySQL ServiceMonitor

安装或补装 MySQL 监控后，确认其 `ServiceMonitor` 带有：

```yaml
monitoring.archinfra.io/stack: default
```

检查：

```bash
kubectl get servicemonitor -A --show-labels | grep mysql
```

随后进入 Prometheus UI 或查询 targets，确认该 MySQL target 被抓取。

### 5.2 Redis ServiceMonitor

安装 Redis 并启用监控：

```bash
./redis-cluster-installer-amd64.run install \
  --namespace redis-system \
  --storage-class nfs \
  --enable-metrics \
  --enable-servicemonitor \
  -y
```

检查：

```bash
kubectl get servicemonitor -A --show-labels | grep redis
```

确认 Redis target 在 Prometheus 中可见。

### 5.3 负例验证

创建一个没有 `monitoring.archinfra.io/stack=default` 标签的测试 `ServiceMonitor`，确认它不会被当前 Prometheus 选中。

### 5.4 跨 namespace 验证

至少让一个 MySQL 或 Redis 部署在非 `monitoring` 命名空间下，确认同样可以被发现。

## 6. 卸载验证

### 6.1 默认卸载

```bash
./prometheus-stack-installer-amd64.run uninstall -n monitoring -y
```

确认点：

- release 卸载成功
- CRD 仍然保留

### 6.2 删除 CRD

```bash
./prometheus-stack-installer-amd64.run uninstall -n monitoring --delete-crds -y
```

确认点：

- 监控 CRD 被删除
- 后续若要重新安装，需要再次跑 install

## 7. 多架构验证

### 7.1 `amd64`

在 x86 集群验证：

- `.run` 可执行
- 镜像地址不带 `-amd64`
- 所有组件 Ready

### 7.2 `arm64`

在 arm 集群验证：

- `prometheus-stack-installer-arm64.run` 可执行
- 镜像推送成功
- Prometheus / Grafana / kube-state-metrics / node-exporter 正常启动

## 8. 排障重点

如果安装失败，优先看：

```bash
kubectl get events -n monitoring --sort-by=.lastTimestamp | tail -n 50
kubectl logs -n monitoring deploy/prometheus-stack-operator
helm status prometheus-stack -n monitoring
```

如果是镜像问题，重点确认：

- `.run` 包版本和目标架构是否匹配
- `--registry` 是否指向正确内网仓库
- `--skip-image-prepare` 是否误用于目标仓库还没有镜像的场景
