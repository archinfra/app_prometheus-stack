# Prometheus Stack 运维文档

这份文档主要给运维、平台管理员和后续 AI 自动化系统使用。

## 1. 默认访问方式

默认安装后：

- Grafana NodePort：`30090`
- Prometheus NodePort：`30091`

默认访问地址：

- Grafana：`http://<任一节点IP>:30090`
- Prometheus：`http://<任一节点IP>:30091`

默认账号密码：

- Grafana 用户名：`admin`
- Grafana 密码：安装参数 `--grafana-admin-password`，默认 `admin@passw0rd`

## 2. 默认安装出的核心组件

- Prometheus Operator
- Prometheus
- Alertmanager
- Grafana
- Grafana image renderer
- kube-state-metrics
- node-exporter

## 3. 默认内置监控

### 3.1 Kubernetes 监控

默认规则会覆盖：

- apiserver
- controller-manager
- scheduler
- kubelet
- kube-proxy
- kube-state-metrics
- node-exporter

### 3.2 监控资源自动发现

Prometheus 默认自动发现：

- `ServiceMonitor`
- `PodMonitor`
- `Probe`
- `PrometheusRule`

条件：

- 必须带 `monitoring.archinfra.io/stack=default`

### 3.3 Dashboard 自动发现

Grafana 默认自动发现所有 namespace 中满足条件的 ConfigMap：

- `grafana_dashboard=1`

可选目录注解：

- `grafana_folder`

## 4. 默认内置告警

默认启用 `kube-prometheus-stack` 内置规则组，主要包括：

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

## 5. 默认内置 recording rules

默认 recording rules 已经启用，主要用于：

- 提前聚合高成本查询
- 给 dashboard 直接复用
- 给告警规则降低计算成本

常见例子：

- `count:up1`
- `count:up0`
- `instance:node_cpu:rate:sum`
- `instance:node_memory_utilisation:ratio`
- `cluster:node_cpu:ratio`
- `node:node_cpu_utilization:ratio_rate5m`

## 6. 默认告警通知行为

默认 Alertmanager 配置是 `null receiver`。

意思是：

- 告警规则会触发
- Alertmanager 也会收到告警
- 但不会发送到外部通知系统

这是为了避免首次安装时误发大量测试告警。

## 7. 怎么接入真实告警

推荐准备一份 Alertmanager YAML，然后安装时传：

```bash
./prometheus-stack-installer-amd64.run install \
  --alertmanager-config-file ./examples/alertmanager-config-webhook.yaml \
  -y
```

可以接入：

- webhook
- 企业微信
- 钉钉
- 飞书
- Slack
- SMTP 邮件网关

## 8. 运维常用命令

看核心工作负载：

```bash
kubectl get pods,svc,deploy,statefulset,daemonset -n monitoring
```

看监控资源：

```bash
kubectl get servicemonitor,podmonitor,prometheusrule,prometheus,alertmanager -A
```

看 dashboard ConfigMap：

```bash
kubectl get configmap -A -l grafana_dashboard=1
```

看 NodePort：

```bash
kubectl get svc -n monitoring
```

看 Prometheus targets：

```bash
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090
```

看 Alertmanager 当前配置：

```bash
kubectl get secret -n monitoring | grep alertmanager
```

## 9. 常见排障点

### 9.1 业务组件没有被抓到

先看：

```bash
kubectl get servicemonitor,podmonitor -A --show-labels
```

重点检查：

- 是否带 `monitoring.archinfra.io/stack=default`
- namespace 是否正确
- endpoint port/path 是否正确

### 9.2 Dashboard 没自动出现

先看：

```bash
kubectl get configmap -A -l grafana_dashboard=1 --show-labels
```

重点检查：

- ConfigMap 是否存在
- 是否带 `grafana_dashboard=1`
- JSON 是否合法
- 是否需要 `grafana_folder`

### 9.3 告警规则存在但不发通知

先看：

```bash
kubectl get prometheusrule -A
kubectl logs -n monitoring deploy/prometheus-stack-kube-prom-alertmanager
```

再确认：

- 有没有传 `--alertmanager-config-file`
- Alertmanager 路由是不是 still 指向 `null`

## 10. 对后续中间件仓库的建议

为了让平台运维和 AI 自动化更顺，建议每个中间件仓库 README 都补齐：

- exporter / metrics 是什么
- 默认 `ServiceMonitor` 名字是什么
- 默认 `PrometheusRule` 名字是什么
- 默认 dashboard ConfigMap 名字是什么
- 默认有哪些内置告警
- 默认有哪些 recording rules
- 如果有 exporter SQL，SQL 文件放在哪里、会监控什么
