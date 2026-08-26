{{/*
Validate required secrets when features are enabled.
*/}}
{{- define "kubeclaw.validateValues" -}}
{{- if .Values.tailscale.ssh.enabled }}
  {{- if and (not .Values.tailscale.ssh.authKey) (not .Values.tailscale.ssh.authKeySecretName) }}
    {{- fail "tailscale.ssh.enabled is true but neither tailscale.ssh.authKey nor tailscale.ssh.authKeySecretName is set" }}
  {{- end }}
{{- end }}
{{- if .Values.litellm.enabled }}
  {{- if not .Values.litellm.masterkey }}
    {{- fail "litellm.enabled is true but litellm.masterkey is not set" }}
  {{- end }}
{{- end }}
{{- if .Values.backup.enabled }}
  {{- if not (index .Values.secret.data "S3_BUCKET") }}
    {{- fail "backup.enabled is true but secret.data.S3_BUCKET is not set" }}
  {{- end }}
  {{- if not (index .Values.secret.data "S3_ACCESS_KEY_ID") }}
    {{- fail "backup.enabled is true but secret.data.S3_ACCESS_KEY_ID is not set" }}
  {{- end }}
  {{- if not (index .Values.secret.data "S3_SECRET_ACCESS_KEY") }}
    {{- fail "backup.enabled is true but secret.data.S3_SECRET_ACCESS_KEY is not set" }}
  {{- end }}
{{- end }}
{{- if .Values.gatewayAPI.enabled }}
  {{- if and (not .Values.gatewayAPI.gatewayClassName) (not .Values.gatewayAPI.controller.enabled) }}
    {{- fail "gatewayAPI.enabled is true but neither gatewayAPI.gatewayClassName nor gatewayAPI.controller.enabled is set" }}
  {{- end }}
  {{- if and .Values.gatewayAPI.crds.install .Values.gatewayAPI.controller.enabled }}
    {{- fail "gatewayAPI.crds.install and gatewayAPI.controller.enabled are mutually exclusive — the Envoy Gateway subchart bundles its own CRDs" }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Resolve the effective gatewayClassName.
When gatewayClassName is empty and controller.enabled is true, default to controller.gatewayClassName.
*/}}
{{- define "kubeclaw.gatewayClassName" -}}
{{- if .Values.gatewayAPI.gatewayClassName }}
{{- .Values.gatewayAPI.gatewayClassName }}
{{- else if .Values.gatewayAPI.controller.enabled }}
{{- .Values.gatewayAPI.controller.gatewayClassName }}
{{- end }}
{{- end }}

{{/*
Expand the name of the chart.
*/}}
{{- define "kubeclaw.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncated at 63 chars because some Kubernetes name fields are limited to this.
*/}}
{{- define "kubeclaw.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Name of the Gateway StatefulSet and its headless Service.
*/}}
{{- define "kubeclaw.gatewayName" -}}
{{- printf "%s-gateway" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Create chart label value: "<chart-name>-<chart-version>".
*/}}
{{- define "kubeclaw.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "kubeclaw.labels" -}}
helm.sh/chart: {{ include "kubeclaw.chart" . }}
{{ include "kubeclaw.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | replace "+" "_" | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels used by the StatefulSet and Service.
*/}}
{{- define "kubeclaw.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kubeclaw.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the Secret that holds gateway credentials.
Returns the existing secret name when set, otherwise the generated name.
*/}}
{{- define "kubeclaw.secretName" -}}
{{- if .Values.secret.existingSecretName }}
{{- .Values.secret.existingSecretName }}
{{- else }}
{{- include "kubeclaw.fullname" . }}
{{- end }}
{{- end }}

{{/*
Name of the desired-config ConfigMap.
*/}}
{{- define "kubeclaw.configmapName" -}}
{{- printf "%s-config" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Name of the main state PVC (used in volumeClaimTemplates metadata).
*/}}
{{- define "kubeclaw.statePvcName" -}}
{{- printf "%s-state" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Name of the workspace PVC (used in volumeClaimTemplates metadata when splitVolumes=true).
*/}}
{{- define "kubeclaw.workspacePvcName" -}}
{{- printf "%s-workspace" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "kubeclaw.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "kubeclaw.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Checksum annotation for the desired-config ConfigMap.
Including this in the StatefulSet pod template triggers a rollout when config changes.
Usage: {{ include "kubeclaw.configChecksum" . }}

`config.checksumOverride` lets the caller decide what counts as a config change.
The reason it exists: bootstrap.sh merges /config-src into the state config ONCE,
at container start, so this annotation is not belt-and-braces -- it is the only
thing that makes a config change take effect, and therefore EVERY config change
restarts the tenant's Gateway. Parts of the config do not need that. `mcp.servers`
in particular can be applied to a running Gateway with `openclaw mcp set/unset`
followed by `openclaw mcp reload`, so a caller that does so can hash the config
WITHOUT its mcp block and stop rolling the pod to add a tool server.

Left unset, behaviour is exactly as before: the whole rendered ConfigMap is
hashed. The override is opt-in because getting it wrong means a config change
that silently never reaches the Gateway, and only a caller that knows which
parts it applies out-of-band can make that call.
*/}}
{{- define "kubeclaw.configChecksum" -}}
{{- if .Values.config.desired }}
{{- with .Values.config.checksumOverride }}
checksum/config: {{ . | quote }}
{{- else }}
checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Checksum annotation for the env ConfigMap.
Triggers rollout when computed env vars change.
Usage: {{ include "kubeclaw.envConfigChecksum" . }}
*/}}
{{- define "kubeclaw.envConfigChecksum" -}}
checksum/env-config: {{ include (print $.Template.BasePath "/env-configmap.yaml") . | sha256sum }}
{{- end }}

{{/*
Image string helper.
*/}}
{{- define "kubeclaw.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s:%s@%s" .Values.image.repository .Values.image.tag .Values.image.digest }}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- end -}}
{{- end }}

{{/*
Name of the Secret holding the Tailscale auth key.
Returns authKeySecretName if set, otherwise "<fullname>-tailscale-authkey".
*/}}
{{- define "kubeclaw.tailscaleAuthKeySecretName" -}}
{{- if .Values.tailscale.ssh.authKeySecretName }}
{{- .Values.tailscale.ssh.authKeySecretName }}
{{- else }}
{{- printf "%s-tailscale-authkey" (include "kubeclaw.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Key within the Tailscale auth key Secret.
*/}}
{{- define "kubeclaw.tailscaleAuthKeySecretKey" -}}
{{- default "TS_AUTHKEY" .Values.tailscale.ssh.authKeySecretKey }}
{{- end }}

{{/*
Tailscale sidecar hostname. Falls back to kubeclaw.fullname.
*/}}
{{- define "kubeclaw.tailscaleHostname" -}}
{{- default (include "kubeclaw.fullname" .) .Values.tailscale.ssh.hostname }}
{{- end }}

{{/*
LiteLLM proxy base URL.
Returns the in-cluster URL of the LiteLLM proxy service on port 4000.
The alias "litellm" in Chart.yaml causes the subchart Service to be named
"<release>-litellm", matching the standard Helm subchart naming convention.
*/}}
{{- define "kubeclaw.litellmBaseUrl" -}}
{{- printf "http://%s-litellm:4000/v1" .Release.Name }}
{{- end }}

{{/*
Name of the egress-filter Deployment and Service.
*/}}
{{- define "kubeclaw.egressFilterName" -}}
{{- printf "%s-egress-filter" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Selector labels for the egress-filter Deployment.
*/}}
{{- define "kubeclaw.egressFilterSelectorLabels" -}}
app.kubernetes.io/name: {{ include "kubeclaw.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: egress-filter
{{- end }}

{{/*
Name of the Chromium Deployment and Service.
*/}}
{{- define "kubeclaw.chromiumName" -}}
{{- printf "%s-chromium" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Selector labels for the Chromium Deployment.
*/}}
{{- define "kubeclaw.chromiumSelectorLabels" -}}
app.kubernetes.io/name: {{ include "kubeclaw.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: chromium
{{- end }}

{{/*
Checksum annotation for the Blocky ConfigMap.
Triggers rollout of the egress-filter Deployment when config changes.
*/}}
{{- define "kubeclaw.blockyConfigChecksum" -}}
{{- if .Values.egressFilter.enabled }}
checksum/blocky-config: {{ include (print $.Template.BasePath "/egress-filter-configmap.yaml") . | sha256sum }}
{{- end }}
{{- end }}

{{/*
Name of the OTel Node Collector DaemonSet.
*/}}
{{- define "kubeclaw.nodeCollectorName" -}}
{{- printf "%s-otel-node" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Selector labels for the OTel Node Collector DaemonSet.
*/}}
{{- define "kubeclaw.nodeCollectorSelectorLabels" -}}
app.kubernetes.io/component: otel-node-collector
{{- end }}

{{/*
Name of the OTel Cluster Collector Deployment.
*/}}
{{- define "kubeclaw.clusterCollectorName" -}}
{{- printf "%s-otel-cluster" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Selector labels for the OTel Cluster Collector Deployment.
*/}}
{{- define "kubeclaw.clusterCollectorSelectorLabels" -}}
app.kubernetes.io/component: otel-cluster-collector
{{- end }}

{{/*
OTel Collector gateway endpoint (ClickStack subchart).
The ClickStack subchart deploys an OTel Collector with a Service named
"<release>-clickstack-otel-collector". OTLP HTTP is on port 4318.
*/}}
{{- define "kubeclaw.otelGatewayEndpoint" -}}
{{- printf "http://%s-clickstack-otel-collector:4318" .Release.Name }}
{{- end }}

{{/*
OTel Collector gateway gRPC endpoint (ClickStack subchart).
OTLP gRPC is on port 4317.
*/}}
{{- define "kubeclaw.otelGatewayGrpcEndpoint" -}}
{{- printf "%s-clickstack-otel-collector:4317" .Release.Name }}
{{- end }}

{{/*
Checksum annotation for the OTel Node Collector ConfigMap.
*/}}
{{- define "kubeclaw.nodeCollectorConfigChecksum" -}}
checksum/otel-node-config: {{ include (print $.Template.BasePath "/otel-node-configmap.yaml") . | sha256sum }}
{{- end }}

{{/*
Checksum annotation for the OTel Cluster Collector ConfigMap.
*/}}
{{- define "kubeclaw.clusterCollectorConfigChecksum" -}}
checksum/otel-cluster-config: {{ include (print $.Template.BasePath "/otel-cluster-configmap.yaml") . | sha256sum }}
{{- end }}

{{/*
Name of the Obsidian vault PVC (used in volumeClaimTemplates metadata).
*/}}
{{- define "kubeclaw.obsidianPvcName" -}}
{{- printf "%s-obsidian" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Name of the Gateway API Gateway resource.
*/}}
{{- define "kubeclaw.gatewayAPIName" -}}
{{- printf "%s-gateway-api" (include "kubeclaw.fullname" .) }}
{{- end }}

{{/*
Fixed SELinux MCS level for every pod that mounts the state PVC. Without a fixed
level the kubelet assigns each pod random MCS categories and relabels the shared
ReadWriteOnce volume to whichever mounted last, locking the others out on
enforcing-SELinux nodes (Bottlerocket / EKS Auto Mode) — surfaces as EACCES
despite correct ownership. Empty .Values.seLinuxLevel disables (e.g. Docker Desktop).
*/}}
{{- define "kubeclaw.seLinuxOptions" -}}
{{- if .Values.seLinuxLevel }}
seLinuxOptions:
  level: {{ .Values.seLinuxLevel | quote }}
{{- end }}
{{- end -}}

{{/*
Co-locates a pod with the Gateway pod. Required for every pod that mounts the
Gateway's ReadWriteOnce state PVC.

An EBS volume attaches to exactly one node, but the bound PV's node affinity
only constrains the availability zone — not the node. With more than one node
in the zone the scheduler is free to place these pods away from the Gateway,
and the attach can then never succeed. Volume attachment does not crash and
retry, it waits: the pod sits in Init:0/N with zero restarts and (on EKS Auto
Mode) no FailedAttachVolume event, indefinitely. Combined with
concurrencyPolicy: Forbid that wedges every later run of the CronJob too, so a
single mis-scheduled pod silently stops the schedule until a human intervenes.

Pinning to the Gateway pod rather than a fixed node keeps this correct when the
Gateway is rescheduled (e.g. Spot reclaim). If the Gateway is mid-move the job
goes Pending instead of wedging, and activeDeadlineSeconds bounds that wait.
*/}}
{{- define "kubeclaw.gatewayColocation" -}}
podAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          {{- include "kubeclaw.selectorLabels" . | nindent 10 }}
          app.kubernetes.io/component: gateway
      topologyKey: kubernetes.io/hostname
{{- end -}}

{{/*
Node placement (nodeSelector + tolerations) shared by EVERY pod this chart
creates, not just the Gateway.

Why this exists: `pod.nodeSelector` and `pod.tolerations` were originally read
only by the StatefulSet. That is a trap once the values point at a TAINTED pool,
which is exactly what the operator does when isolating tenants onto dedicated
capacity.

The failure is silent and total. The five Jobs/CronJobs (qmd-update, qmd-embed,
diagnostics, backup, backup-on-delete) are pinned by `kubeclaw.gatewayColocation`
to the Gateway's own node, because they mount its ReadWriteOnce volume. If you
add another, `grep -l gatewayColocation templates/` is the authoritative list;
counting from memory is how `backup` was missed the first time. Move the
Gateway onto a tainted node while the Jobs tolerate nothing, and their one legal
node becomes the one node they may not enter. They do not fail; they go Pending
forever, and `concurrencyPolicy: Forbid` means the schedule never recovers.
Chromium and the egress-filter have the same problem without the affinity: they
would simply drift onto whatever untainted node exists, away from the tenant
pool they were meant to be isolated with.

So placement belongs to every pod in the release. Emit unindented; callers
supply nindent for their nesting depth (6 for Deployments, 10 for CronJobs).
*/}}
{{- define "kubeclaw.podPlacement" -}}
{{- with .Values.pod.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.pod.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Tenant account id, used to attribute telemetry to a customer.

Nothing in the cluster carries the account id as a label today. It exists only
inside the namespace name (openclaw-<uuid>), so grouping logs, metrics or spans
by tenant meant string-parsing kube_namespace at every call site. Deriving it
once here and stamping it on every pod makes tenant a first-class tag.

The namespace is the source of truth because the provisioner already names it
from the account id; datadog.accountId is an escape hatch for installs that do
not follow that convention (local dev, self-hosted).
*/}}
{{- define "kubeclaw.accountId" -}}
{{- if .Values.datadog.accountId }}
{{- .Values.datadog.accountId }}
{{- else if hasPrefix "openclaw-" .Release.Namespace }}
{{- trimPrefix "openclaw-" .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Datadog unified service tags plus tenant attribution, for pod templates.

WHY THIS EXISTS. With no explicit tags.datadoghq.com/service label the Datadog
agent derives `service` from the pod name. For CronJob pods that name embeds the
schedule counter, so every single run minted a brand new service:
openclaw-kubeclaw-qmd-update-29764270, -29765115, -29763675 and so on. One
namespace accumulated 1,778 distinct services in seven days. Service-level
dashboards, monitors and the service catalog were all unusable for tenant
workloads, and APM service sprawl made trace search useless.

The service name is fullname + component, which deliberately REPRODUCES the
names the two long-lived workloads already resolved to
(openclaw-kubeclaw-gateway, openclaw-kubeclaw-egress-filter). Existing
dashboards and monitors on those two keep working. Only the broken names change.

Usage:
  {{- include "kubeclaw.datadogPodLabels" (dict "ctx" . "component" "gateway") | nindent 8 }}
*/}}
{{- define "kubeclaw.datadogPodLabels" -}}
{{- $ctx := .ctx -}}
tags.datadoghq.com/service: {{ printf "%s-%s" (include "kubeclaw.fullname" $ctx) .component | trunc 63 | trimSuffix "-" }}
{{- /*
    DELIBERATELY NO tags.datadoghq.com/version.

    Datadog already derives `version` from the container image tag, and it is
    correct today: gateway spans carry version 2026.6.10 from image tag
    2026.6.10-cc.slack1. Chart.AppVersion is NOT maintained against the image
    (it reads 2026.5.22 while 2026.6.10-cc.slack1 is deployed), so setting the
    label from it would replace a correct live value with a stale one and break
    version grouping and deployment tracking in APM.

    If you ever want an explicit version label, source it from .Values.image.tag,
    never from Chart.AppVersion.
*/ -}}
{{- with $ctx.Values.datadog.env }}
tags.datadoghq.com/env: {{ . | quote }}
{{- end }}
{{- with (include "kubeclaw.accountId" $ctx) }}
tenfold.io/account-id: {{ . | quote }}
{{- end }}
{{- end }}
