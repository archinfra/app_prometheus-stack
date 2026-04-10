# app_prometheus-stack 手工测试方案

## 1. 目标

验证以下能力真实可用：

- `amd64` / `arm64` 双架构离线包
- `.run` 安装器支持 `install|uninstall|status|help`
- 默认两阶段安装
- 默认 NodePort
  - Grafana `30090`
  - Prometheus `30091`
- 自动发现 `ServiceMonitor` / `PodMonitor` / `PrometheusRule`
- 自动发现 Grafana dashboard ConfigMap
- 可选外接 Alertmanager 配置

## 2. 静态校验

在仓库根目录执行：

```bash
bash -n build.sh install.sh
python - <<'PY'
import json, pathlib
data = json.loads(pathlib.Path("images/image.json").read_text(encoding="utf-8"))
assert any(item["arch"] == "amd64" for item in data)
assert any(item["arch"] == "arm64" for item in data)
print("image.json ok")
PY
./install.sh --help
```

确认帮助里有这些参数：

- `--grafana-service-type`
- `--grafana-node-port`
- `--prometheus-service-type`
- `--prometheus-node-port`
- `--alertmanager-config-file`

## 3. GitHub Actions 校验

### 3.1 main 分支

确认：

- `amd64` 构建成功
- `arm64` 构建成功

### 3.2 tag release

确认 release 页面包含：

- `prometheus-stack-installer-amd64.run`
- `prometheus-stack-installer-amd64.run.sha256`
- `prometheus-stack-installer-arm64.run`
- `prometheus-stack-installer-arm64.run.sha256`

## 4. 基础安装验证

```bash
./prometheus-stack-installer-amd64.run install \
  --namespace monitoring \
  --grafana-admin-password 'Admin@123' \
  -y
```

确认点：

1. 日志先出现第一阶段 CRD/operator 安装
2. 再出现 CRD Established 等待
3. 再出现第二阶段完整监控栈安装
4. 最终所有核心工作负载 Ready

检查命令：

```bash
kubectl get crd | grep monitoring.coreos.com
kubectl get pods,svc,deploy,statefulset,daemonset -n monitoring
kubectl get prometheus,alertmanager,servicemonitor,podmonitor,prometheusrule -n monitoring
```

## 5. NodePort 验证

```bash
kubectl get svc -n monitoring
```

确认：

- Grafana 对应 Service 为 `NodePort`
- Prometheus 对应 Service 为 `NodePort`
- 端口分别是 `30090` 和 `30091`

再从浏览器或 curl 验证：

```bash
curl -I http://<node-ip>:30090
curl -I http://<node-ip>:30091
```

## 6. ServiceMonitor 自动发现验证

准备一个带平台标签的测试 `ServiceMonitor`，可直接用：

- [servicemonitor-app.yaml](C:/Users/yuanyp8/Desktop/archinfra/app_prometheus/examples/servicemonitor-app.yaml)

确认：

```bash
kubectl get servicemonitor -A -l monitoring.archinfra.io/stack=default
```

再到 Prometheus Targets 页面确认 target 已被发现。

## 7. PrometheusRule 自动发现验证

准备测试规则：

- [prometheusrule-app-alerts.yaml](C:/Users/yuanyp8/Desktop/archinfra/app_prometheus/examples/prometheusrule-app-alerts.yaml)

确认：

```bash
kubectl get prometheusrule -A -l monitoring.archinfra.io/stack=default
```

如果表达式可触发，再确认 Alertmanager 能接收到告警。

## 8. Grafana Dashboard 自动导入验证

准备测试 dashboard：

- [grafana-dashboard-configmap.yaml](C:/Users/yuanyp8/Desktop/archinfra/app_prometheus/examples/grafana-dashboard-configmap.yaml)

确认：

```bash
kubectl get configmap -A -l grafana_dashboard=1
```

然后登录 Grafana，看是否自动出现：

- 目录：由 `grafana_folder` 决定
- Dashboard：由 ConfigMap 中 JSON 决定

## 9. Alertmanager 外接通知验证

使用示例配置安装：

```bash
./prometheus-stack-installer-amd64.run install \
  --namespace monitoring \
  --alertmanager-config-file ./examples/alertmanager-config-webhook.yaml \
  -y
```

确认：

- 告警规则存在
- Alertmanager 配置不再是默认 null receiver
- 测试告警可以投递到你的 webhook

## 10. 幂等验证

再执行一次相同安装命令，确认：

- 不因 CRD 已存在失败
- 不因 Helm release 已存在失败
- NodePort 配置保持不变
- 核心工作负载继续 Ready

## 11. 卸载验证

默认卸载：

```bash
./prometheus-stack-installer-amd64.run uninstall -n monitoring -y
```

确认 release 被删掉，但 CRD 保留。

删除 CRD：

```bash
./prometheus-stack-installer-amd64.run uninstall -n monitoring --delete-crds -y
```

确认监控 CRD 被删除。
