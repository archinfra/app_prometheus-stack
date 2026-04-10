# Prometheus Stack 集成文档

这份文档专门说明业务中间件如何自动接入当前监控栈，包括：

- 怎么接 `ServiceMonitor`
- 怎么接 `PrometheusRule`
- 怎么接 Grafana dashboard
- 标签应该怎么打
- 运维应该检查什么

## 1. 统一标签契约

### 1.1 Prometheus 发现标签

所有希望被当前 Prometheus 自动发现的监控资源，都需要带：

```yaml
metadata:
  labels:
    monitoring.archinfra.io/stack: default
```

适用资源：

- `ServiceMonitor`
- `PodMonitor`
- `Probe`
- `PrometheusRule`

### 1.2 Grafana dashboard 标签

所有希望被当前 Grafana 自动导入的 dashboard ConfigMap，都需要带：

```yaml
metadata:
  labels:
    grafana_dashboard: "1"
    monitoring.archinfra.io/stack: default
```

可选：

```yaml
metadata:
  annotations:
    grafana_folder: "Middleware/MySQL"
```

这样 Grafana 会把它放到指定目录。

## 2. ServiceMonitor 接入

最小示例见 [servicemonitor-app.yaml](C:/Users/yuanyp8/Desktop/archinfra/app_prometheus/examples/servicemonitor-app.yaml)。

关键点：

- `metadata.labels` 必须带 `monitoring.archinfra.io/stack=default`
- endpoint 要指向 exporter 的 metrics 端口
- namespace 可以不是 `monitoring`

示例要点：

```yaml
kind: ServiceMonitor
metadata:
  labels:
    monitoring.archinfra.io/stack: default
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: mysql-exporter
```

## 3. PodMonitor 接入

当组件没有稳定 Service，或者更适合直接抓 Pod 时，可以使用 `PodMonitor`。

场景示例：

- `etcd`
- 某些 sidecar exporter
- 某些 DaemonSet 型 exporter

要求与 `ServiceMonitor` 一样：

- 一样要带 `monitoring.archinfra.io/stack=default`

## 4. PrometheusRule 接入

最小示例见 [prometheusrule-app-alerts.yaml](C:/Users/yuanyp8/Desktop/archinfra/app_prometheus/examples/prometheusrule-app-alerts.yaml)。

关键点：

- `PrometheusRule` 也必须带 `monitoring.archinfra.io/stack=default`
- 推荐同时包含：
  - 应用级告警规则
  - 应用级 recording rules

建议每个中间件都至少提供：

- Availability 规则
- Saturation 规则
- Error 规则
- 核心容量规则

## 5. Grafana dashboard 接入

最小示例见 [grafana-dashboard-configmap.yaml](C:/Users/yuanyp8/Desktop/archinfra/app_prometheus/examples/grafana-dashboard-configmap.yaml)。

要求：

- `grafana_dashboard: "1"`
- `monitoring.archinfra.io/stack: default`
- dashboard JSON 放进 ConfigMap 的 data 字段

推荐：

- 一个组件至少一个总览 dashboard
- 有条件的话再拆：
  - runtime dashboard
  - storage dashboard
  - replication / cluster dashboard
  - slow query / queue / cache dashboard

## 6. 各中间件建议最少提供的内容

### 6.1 MySQL

- `ServiceMonitor`
- `PrometheusRule`
- `grafana dashboard`
- 关键指标：
  - connections
  - slow queries
  - qps/tps
  - buffer pool
  - replication lag

### 6.2 Redis

- `ServiceMonitor`
- `PrometheusRule`
- `grafana dashboard`
- 关键指标：
  - used memory
  - hit ratio
  - ops/sec
  - evicted keys
  - replication offset / lag

### 6.3 MinIO

- `ServiceMonitor`
- `PrometheusRule`
- `grafana dashboard`
- 关键指标：
  - request rate
  - error rate
  - bucket/object growth
  - disk usage

### 6.4 RabbitMQ

- `ServiceMonitor`
- `PrometheusRule`
- `grafana dashboard`
- 关键指标：
  - queue depth
  - unacked messages
  - consumers
  - connections
  - disk alarm

### 6.5 MongoDB

- `ServiceMonitor`
- `PrometheusRule`
- `grafana dashboard`
- 关键指标：
  - opcounters
  - cache usage
  - replication lag
  - connections
  - locks

### 6.6 Milvus

- `ServiceMonitor` / `PodMonitor`
- `PrometheusRule`
- `grafana dashboard`
- 关键指标：
  - proxy
  - querynode
  - datanode
  - etcd
  - minio

## 7. 运维校验命令

看自动发现：

```bash
kubectl get servicemonitor,podmonitor,prometheusrule -A \
  -l monitoring.archinfra.io/stack=default
```

看 dashboard ConfigMap：

```bash
kubectl get configmap -A -l grafana_dashboard=1
```

看 Prometheus targets：

```bash
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090
```

看 Grafana dashboards：

```bash
kubectl get configmap -A -l grafana_dashboard=1 --show-labels
```

## 8. 对 AI 的建议

如果后续要让 AI 自动部署中间件，建议它每装一个组件后都执行：

1. 检查 exporter 或 metrics endpoint 是否存在
2. 检查 `ServiceMonitor` / `PodMonitor` 是否存在
3. 检查 `PrometheusRule` 是否存在
4. 检查 dashboard ConfigMap 是否存在
5. 检查 Grafana 中是否已经出现对应目录或 dashboard
