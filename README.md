## Installer Runtime Note

The installer now streams the embedded payload directly into the target work directory and no longer writes an extra `/tmp/prometheus-stack-installer/payload.tar.gz` copy during install.

During installation it is normal to see `/tmp/prometheus-stack-installer/images` grow as image archives are unpacked for `docker load`; that growth is the real payload extraction, not a duplicated archive file.

# app_prometheus-stack

面向 Kubernetes 的 Prometheus/Grafana/Alertmanager 离线交付仓库。

它的目标不是只把监控栈“装起来”，而是给整个平台提供一套稳定的监控底座，让 `MySQL`、`Redis`、`Nacos`、`MinIO`、`RabbitMQ`、`MongoDB`、`Milvus` 等中间件只要按统一契约暴露监控资源，就能被自动发现、自动出现在 Grafana、自动进入告警体系。

## 1. 这套安装器现在能做什么

- 支持 `amd64` / `arm64` 两种架构的 `.run` 离线安装包
- 安装流程默认分两阶段
  - 第一阶段只安装 `CRD + Prometheus Operator`
  - 第二阶段再安装 `Prometheus + Alertmanager + Grafana + kube-state-metrics + node-exporter`
- Prometheus 自动跨 namespace 发现这些资源：
  - `ServiceMonitor`
  - `PodMonitor`
  - `Probe`
  - `PrometheusRule`
- Grafana 自动跨 namespace 发现 Dashboard ConfigMap
- 默认开启外部访问：
  - `Grafana NodePort = 30090`
  - `Prometheus NodePort = 30091`
- 默认内置 Kubernetes 集群级监控、默认规则、默认 recording rules、默认 Grafana dashboards

## 2. 平台统一接入契约

### 2.1 Prometheus 自动发现契约

Prometheus 只会抓取带下面这个标签的监控资源：

- 键：`monitoring.archinfra.io/stack`
- 值：`default`

适用资源：

- `ServiceMonitor`
- `PodMonitor`
- `Probe`
- `PrometheusRule`

也就是说，业务组件要想被当前监控栈自动发现，至少要满足：

```yaml
metadata:
  labels:
    monitoring.archinfra.io/stack: default
```

### 2.2 Grafana 自动导入 Dashboard 契约

Grafana sidecar 默认会跨所有 namespace 搜索 Dashboard ConfigMap，契约如下：

- Dashboard 标签键：`grafana_dashboard`
- Dashboard 标签值：`1`
- 可选目录注解：`grafana_folder`

示例：

```yaml
metadata:
  labels:
    grafana_dashboard: "1"
    monitoring.archinfra.io/stack: default
  annotations:
    grafana_folder: "Middleware/MySQL"
```

只要某个中间件仓库安装时顺手创建这个 ConfigMap，Grafana 就会自动看到仪表盘，不需要再手工导入。

## 3. 默认安装结果

默认动作：

- release 名：`prometheus-stack`
- namespace：`monitoring`
- Grafana 管理员账号：`admin`
- Grafana 管理员密码：`admin@passw0rd`
- Grafana 暴露方式：`NodePort`
- Grafana 端口：`30090`
- Prometheus 暴露方式：`NodePort`
- Prometheus 端口：`30091`
- Prometheus 存储类：`nfs`
- Prometheus 存储大小：`200Gi`
- Prometheus retention：`14d`
- Alertmanager 存储类：`nfs`
- Alertmanager 存储大小：`10Gi`
- Grafana 存储类：`nfs`
- Grafana 存储大小：`10Gi`

安装完成后，常用访问地址为：

- Grafana：`http://<任一节点IP>:30090`
- Prometheus：`http://<任一节点IP>:30091`
- Prometheus 集群内地址：`http://prometheus-stack-kube-prom-prometheus.monitoring.svc:9090`
- Alertmanager 集群内地址：`http://alertmanager-operated.monitoring.svc:9093`

说明：

- `Grafana` 和 `Prometheus` 默认直接开放为 NodePort，方便平台运维和 AI 自动巡检
- `Alertmanager` 默认只保留集群内访问；如果需要真实通知，请传 `--alertmanager-config-file`

## 4. 快速开始

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

如果目标仓库已经有镜像，跳过导入：

```bash
./prometheus-stack-installer-amd64.run install \
  --registry sealos.hub:5000/kube4 \
  --skip-image-prepare \
  -y
```

自定义 NodePort：

```bash
./prometheus-stack-installer-amd64.run install \
  --grafana-node-port 30090 \
  --prometheus-node-port 30091 \
  -y
```

接入真实告警通知：

```bash
./prometheus-stack-installer-amd64.run install \
  --alertmanager-config-file ./examples/alertmanager-config-webhook.yaml \
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

卸载并删除 CRD：

```bash
./prometheus-stack-installer-amd64.run uninstall -n monitoring --delete-crds -y
```

## 5. 自动发现、自动 dashboard、自动告警是怎么串起来的

### 5.1 业务组件接入监控

以 MySQL、Redis、MinIO、RabbitMQ、MongoDB、Milvus 为例，业务仓库需要做三类资源：

1. `ServiceMonitor` 或 `PodMonitor`
2. `PrometheusRule`
3. Dashboard `ConfigMap`

接入后的效果：

- Prometheus 自动抓 exporter / metrics endpoint
- Prometheus 自动加载应用规则
- Grafana 自动看到对应 dashboard

### 5.2 推荐的每个业务仓库最少内置内容

- 一个 metrics endpoint
- 一个 `ServiceMonitor`
- 一组应用级 `PrometheusRule`
- 一组 Grafana dashboard ConfigMap

### 5.3 对已有中间件仓库的建议

这套仓库现在已经把自动发现机制打通了，后续建议各中间件仓库补齐各自的：

- MySQL：
  - exporter dashboard
  - 复制/连接数/慢查询/缓存命中率告警
- Redis：
  - 内存/连接数/主从延迟/evicted keys dashboard 和告警
- MinIO：
  - bucket/object/API/error dashboard 和告警
- RabbitMQ：
  - queue depth、unacked、connections、disk free 告警
- MongoDB：
  - opcounters、replica lag、cache pressure dashboard 和告警
- Milvus：
  - proxy/querynode/datanode/minio/etcd 组合 dashboard 和告警

## 6. 这套监控栈内置了什么

### 6.1 内置监控目标

默认启用：

- `prometheus-operator`
- `prometheus`
- `alertmanager`
- `grafana`
- `grafana-image-renderer`
- `kube-state-metrics`
- `node-exporter`
- Kubernetes 默认规则覆盖的 apiserver / controller-manager / scheduler / kubelet 等

### 6.2 内置告警

来自 `kube-prometheus-stack` 默认规则组，主要包括：

- `alertmanager`
- `etcd`
- `configReloaders`
- `general`
- `kubeApiserverAvailability`
- `kubeApiserverBurnrate`
- `kubeApiserverSlos`
- `kubeControllerManager`
- `kubelet`
- `kubeProxy`
- `kubePrometheusGeneral`
- `kubernetesApps`
- `kubernetesResources`
- `kubernetesStorage`
- `kubernetesSystem`
- `kubeSchedulerAlerting`
- `kubeStateMetrics`
- `network`
- `node`
- `nodeExporterAlerting`
- `prometheus`
- `prometheusOperator`

说明：

- 这些告警规则默认已存在
- 但默认 `Alertmanager` receiver 是 `null`
- 也就是默认“规则会触发，但不会发到外部通知系统”

如果你希望真正发通知，需要给 `Alertmanager` 提供配置文件。

### 6.3 内置 recording rules

内置 recording rules 也已经开启，常见包括：

- `count:up1`
- `count:up0`
- `instance:node_cpu:rate:sum`
- `instance:node_memory_utilisation:ratio`
- `cluster:node_cpu:ratio`
- `node:node_cpu_utilization:ratio_rate5m`
- 各类 apiserver burn-rate / availability / histogram 聚合指标

这些 recording rules 的意义是：

- 提前把高成本 PromQL 计算好
- 降低 dashboard 查询开销
- 方便告警规则直接复用

## 7. 告警应该怎么接

推荐方式是准备一份独立 Alertmanager 配置文件，然后通过安装参数传入：

```bash
./prometheus-stack-installer-amd64.run install \
  --alertmanager-config-file ./examples/alertmanager-config-webhook.yaml \
  -y
```

你可以把它对接到：

- webhook
- 企业微信
- 钉钉
- 飞书
- Slack
- 邮件网关

默认不建议把这些通知地址硬编码进安装器。

## 8. 与中间件项目的关系

这套监控栈是“平台底座”，不直接负责安装业务中间件。

推荐的安装顺序：

1. `metrics-server`
2. `prometheus-stack`
3. `mysql`
4. `redis`
5. `nacos`
6. `minio`
7. `rabbitmq`
8. `mongodb`
9. `milvus`

依赖关系：

- 这些业务组件不依赖 Prometheus 才能运行
- 但它们要想自动纳入统一监控、统一 dashboard、统一告警，就依赖当前 Prometheus/Grafana 契约

## 9. 给新接手运维或 AI 的执行建议

如果是普通运维同事或 AI 自动部署，请遵循下面的步骤：

1. 先安装 Prometheus Stack。
2. 确认 `Grafana` 和 `Prometheus` NodePort 可访问。
3. 再安装业务组件。
4. 每安装一个业务组件，都检查：
   - `ServiceMonitor` / `PodMonitor` 是否存在
   - `PrometheusRule` 是否存在
   - dashboard ConfigMap 是否存在
5. 用 Grafana 和 Prometheus Targets 双重验证是否自动接入成功。

## 10. 详细文档

- [详细集成文档](C:/Users/yuanyp8/Desktop/archinfra/app_prometheus/docs/INTEGRATION.zh-CN.md)
- [告警与 Dashboard 运维文档](C:/Users/yuanyp8/Desktop/archinfra/app_prometheus/docs/OPERATIONS.zh-CN.md)
- [手工测试方案](C:/Users/yuanyp8/Desktop/archinfra/app_prometheus/docs/TESTING.zh-CN.md)

## 11. 示例清单

- [Alertmanager webhook 配置示例](C:/Users/yuanyp8/Desktop/archinfra/app_prometheus/examples/alertmanager-config-webhook.yaml)
- [ServiceMonitor 示例](C:/Users/yuanyp8/Desktop/archinfra/app_prometheus/examples/servicemonitor-app.yaml)
- [PrometheusRule 示例](C:/Users/yuanyp8/Desktop/archinfra/app_prometheus/examples/prometheusrule-app-alerts.yaml)
- [Grafana dashboard ConfigMap 示例](C:/Users/yuanyp8/Desktop/archinfra/app_prometheus/examples/grafana-dashboard-configmap.yaml)
