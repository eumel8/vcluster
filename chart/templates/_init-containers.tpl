{{- define "vcluster.initContainers" -}}
{{- if eq (include "vcluster.distro" .) "k3s" -}}
{{ include "vcluster.k3s.initContainers" . }}
{{- else if eq (include "vcluster.distro" .) "k8s" -}}
{{ include "vcluster.k8s.initContainers" . }}
{{- else if eq (include "vcluster.distro" .) "k0s" -}}
{{ include "vcluster.k0s.initContainers" . }}
{{- else if eq (include "vcluster.distro" .) "eks" -}}
{{ include "vcluster.eks.initContainers" . }}
{{- end -}}
{{- end -}}

{{- define "vcluster.eks.initContainers" -}}
{{- include "vcluster.oldPlugins.initContainers" . }}
{{- include "vcluster.plugins.initContainers" . }}
# this is needed because the k8s containers are distroless and thus we don't have any
# way of copying the binaries otherwise
- name: vcluster-copy
  image: {{ include "vcluster.controlPlane.image" . | quote }}
  volumeMounts:
    - mountPath: /binaries
      name: binaries
  command:
    - /bin/sh
  args:
    - -c
    - "cp /vcluster /binaries/vcluster"
  {{- if .Values.controlPlane.statefulSet.imagePullPolicy }}
  imagePullPolicy: {{ .Values.controlPlane.statefulSet.imagePullPolicy }}
  {{- end }}
  securityContext:
{{ toYaml .Values.controlPlane.distro.eks.securityContext | indent 4 }}
  resources:
{{ toYaml .Values.controlPlane.distro.eks.resources | indent 4 }}
{{- if not .Values.controlPlane.distro.eks.controllerManager.disabled }}
- name: kube-controller-manager
  image: "{{ .Values.controlPlane.advanced.defaultImageRegistry }}{{ .Values.controlPlane.distro.eks.controllerManager.image.repository }}:{{ .Values.controlPlane.distro.eks.controllerManager.image.tag }}"
  volumeMounts:
    - mountPath: /binaries
      name: binaries
  command:
    - /binaries/vcluster
  args:
    - cp
    - /usr/local/bin/kube-controller-manager
    - /binaries/kube-controller-manager
  {{- if .Values.controlPlane.distro.eks.controllerManager.imagePullPolicy }}
  imagePullPolicy: {{ .Values.controlPlane.distro.eks.controllerManager.imagePullPolicy }}
  {{- end }}
  securityContext:
{{ toYaml .Values.controlPlane.distro.eks.securityContext | indent 4 }}
  resources:
{{ toYaml .Values.controlPlane.distro.eks.resources | indent 4 }}
{{- end }}
{{- if .Values.controlPlane.advanced.virtualScheduler.enabled }}
- name: kube-scheduler-manager
  image: "{{ .Values.controlPlane.advanced.defaultImageRegistry }}{{ .Values.controlPlane.distro.eks.scheduler.image.repository }}:{{ .Values.controlPlane.distro.eks.scheduler.image.tag }}"
  volumeMounts:
    - mountPath: /binaries
      name: binaries
  command:
    - /binaries/vcluster
  args:
    - cp
    - /usr/local/bin/kube-scheduler
    - /binaries/kube-scheduler
  {{- if .Values.controlPlane.distro.eks.scheduler.imagePullPolicy }}
  imagePullPolicy: {{ .Values.controlPlane.distro.eks.scheduler.imagePullPolicy }}
  {{- end }}
  securityContext:
{{ toYaml .Values.controlPlane.distro.eks.securityContext | indent 4 }}
  resources:
{{ toYaml .Values.controlPlane.distro.eks.resources | indent 4 }}
{{- end }}
{{- if not .Values.controlPlane.distro.eks.apiServer.disabled }}
- name: kube-apiserver
  image: "{{ .Values.controlPlane.advanced.defaultImageRegistry }}{{ .Values.controlPlane.distro.eks.apiServer.image.repository }}:{{ .Values.controlPlane.distro.eks.apiServer.image.tag }}"
  volumeMounts:
    - mountPath: /binaries
      name: binaries
  command:
    - /binaries/vcluster
  args:
    - cp
    - /usr/local/bin/kube-apiserver
    - /binaries/kube-apiserver
  {{- if .Values.controlPlane.distro.eks.apiServer.imagePullPolicy }}
  imagePullPolicy: {{ .Values.controlPlane.distro.eks.apiServer.imagePullPolicy }}
  {{- end }}
  securityContext:
{{ toYaml .Values.controlPlane.distro.eks.securityContext | indent 4 }}
  resources:
{{ toYaml .Values.controlPlane.distro.eks.resources | indent 4 }}
{{- end }}
{{- end -}}

{{- define "vcluster.k8s.initContainers" -}}
{{- include "vcluster.oldPlugins.initContainers" . }}
{{- include "vcluster.plugins.initContainers" . }}
# this is needed because the k8s containers are distroless and thus we don't have any
# way of copying the binaries otherwise
- name: vcluster-copy
  image: {{ include "vcluster.controlPlane.image" . | quote }}
  volumeMounts:
    - mountPath: /binaries
      name: binaries
  command:
    - /bin/sh
  args:
    - -c
    - "cp /vcluster /binaries/vcluster"
  {{- if .Values.controlPlane.statefulSet.imagePullPolicy }}
  imagePullPolicy: {{ .Values.controlPlane.statefulSet.imagePullPolicy }}
  {{- end }}
  securityContext:
{{ toYaml .Values.controlPlane.distro.k8s.securityContext | indent 4 }}
  resources:
{{ toYaml .Values.controlPlane.distro.k8s.resources | indent 4 }}
{{- if not .Values.controlPlane.distro.k8s.controllerManager.disabled }}
- name: kube-controller-manager
  image: "{{ .Values.controlPlane.advanced.defaultImageRegistry }}{{ .Values.controlPlane.distro.k8s.controllerManager.image.repository }}:{{ .Values.controlPlane.distro.k8s.controllerManager.image.tag }}"
  volumeMounts:
    - mountPath: /binaries
      name: binaries
  command:
    - /binaries/vcluster
  args:
    - cp
    - /usr/local/bin/kube-controller-manager
    - /binaries/kube-controller-manager
  {{- if .Values.controlPlane.distro.k8s.controllerManager.imagePullPolicy }}
  imagePullPolicy: {{ .Values.controlPlane.distro.k8s.controllerManager.imagePullPolicy }}
  {{- end }}
  securityContext:
{{ toYaml .Values.controlPlane.distro.k8s.securityContext | indent 4 }}
  resources:
{{ toYaml .Values.controlPlane.distro.k8s.resources | indent 4 }}
{{- end }}
{{- if .Values.controlPlane.advanced.virtualScheduler.enabled }}
- name: kube-scheduler-manager
  image: "{{ .Values.controlPlane.advanced.defaultImageRegistry }}{{ .Values.controlPlane.distro.k8s.scheduler.image.repository }}:{{ .Values.controlPlane.distro.k8s.scheduler.image.tag }}"
  volumeMounts:
    - mountPath: /binaries
      name: binaries
  command:
    - /binaries/vcluster
  args:
    - cp
    - /usr/local/bin/kube-scheduler
    - /binaries/kube-scheduler
  {{- if .Values.controlPlane.distro.k8s.scheduler.imagePullPolicy }}
  imagePullPolicy: {{ .Values.controlPlane.distro.k8s.scheduler.imagePullPolicy }}
  {{- end }}
  securityContext:
{{ toYaml .Values.controlPlane.distro.k8s.securityContext | indent 4 }}
  resources:
{{ toYaml .Values.controlPlane.distro.k8s.resources | indent 4 }}
{{- end }}
{{- if not .Values.controlPlane.distro.k8s.apiServer.disabled }}
- name: kube-apiserver
  image: "{{ .Values.controlPlane.advanced.defaultImageRegistry }}{{ .Values.controlPlane.distro.k8s.apiServer.image.repository }}:{{ .Values.controlPlane.distro.k8s.apiServer.image.tag }}"
  volumeMounts:
    - mountPath: /binaries
      name: binaries
  command:
    - /binaries/vcluster
  args:
    - cp
    - /usr/local/bin/kube-apiserver
    - /binaries/kube-apiserver
  {{- if .Values.controlPlane.distro.k8s.apiServer.imagePullPolicy }}
  imagePullPolicy: {{ .Values.controlPlane.distro.k8s.apiServer.imagePullPolicy }}
  {{- end }}
  securityContext:
{{ toYaml .Values.controlPlane.distro.k8s.securityContext | indent 4 }}
  resources:
{{ toYaml .Values.controlPlane.distro.k8s.resources | indent 4 }}
{{- end }}
{{- end -}}

{{- define "vcluster.k3s.initContainers" -}}
{{- include "vcluster.oldPlugins.initContainers" . }}
{{- include "vcluster.plugins.initContainers" . }}
- image: "{{ .Values.controlPlane.advanced.defaultImageRegistry }}{{ .Values.controlPlane.distro.k3s.image.repository }}:{{ .Values.controlPlane.distro.k3s.image.tag }}"
  name: vcluster
  command:
    - /bin/sh
  args:
    - -c
    - "cp /bin/k3s /binaries/k3s"
  {{- if .Values.controlPlane.distro.k3s.imagePullPolicy }}
  imagePullPolicy: {{ .Values.controlPlane.distro.k3s.imagePullPolicy }}
  {{- end }}
  securityContext:
{{ toYaml .Values.controlPlane.distro.k3s.securityContext | indent 4 }}
  volumeMounts:
    - name: binaries
      mountPath: /binaries
  resources:
{{ toYaml .Values.controlPlane.distro.k3s.resources | indent 4 }}
{{- end -}}

{{- define "vcluster.k0s.initContainers" -}}
{{- include "vcluster.oldPlugins.initContainers" . }}
{{- include "vcluster.plugins.initContainers" . }}
- image: {{ .Values.controlPlane.advanced.defaultImageRegistry }}{{ .Values.controlPlane.distro.k0s.image.repository }}:{{ .Values.controlPlane.distro.k0s.image.tag }}
  name: vcluster
  command:
    - /bin/sh
  args:
    - -c
    - "cp /usr/local/bin/k0s /binaries/k0s"
  {{- if .Values.controlPlane.distro.k0s.imagePullPolicy }}
  imagePullPolicy: {{ .Values.controlPlane.distro.k0s.imagePullPolicy }}
  {{- end }}
  securityContext:
{{ toYaml .Values.controlPlane.distro.k0s.securityContext | indent 4 }}
  volumeMounts:
    - name: binaries
      mountPath: /binaries
  resources:
{{ toYaml .Values.controlPlane.distro.k0s.resources | indent 4 }}
{{- end -}}

{{/*
  Plugin init container definition
*/}}
{{- define "vcluster.plugins.initContainers" -}}
{{- range $key, $container := .Values.plugins }}
{{- if not $container.image }}
{{- continue }}
{{- end }}
- image: {{ $.Values.controlPlane.advanced.defaultImageRegistry }}{{ $container.image }}
  {{- if $container.name }}
  name: {{ $container.name | quote }}
  {{- else }}
  name: {{ $key | quote }}
  {{- end }}
  {{- if $container.imagePullPolicy }}
  imagePullPolicy: {{ $container.imagePullPolicy }}
  {{- end }}
  {{- if or $container.command $container.args }}
  {{- if $container.command }}
  command:
    {{- range $commandIndex, $command := $container.command }}
    - {{ $command | quote }}
    {{- end }}
  {{- end }}
  {{- if $container.args }}
  args:
    {{- range $argIndex, $arg := $container.args }}
    - {{ $arg | quote }}
    {{- end }}
  {{- end }}
  {{- else }}
  command: ["sh"]
  args: ["-c", "cp -r /plugin /plugins/{{ $key }}"]
  {{- end }}
  {{- if $container.securityContext }}
  securityContext:
{{ toYaml $container.securityContext | indent 4 }}
  {{- end }}
  {{- if $container.volumeMounts }}
  volumeMounts:
{{ toYaml $container.volumeMounts | indent 4 }}
  {{- else }}
  volumeMounts:
    - mountPath: /plugins
      name: plugins
  {{- end }}
  {{- if $container.resources }}
  resources:
{{ toYaml $container.resources | indent 4 }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
  Old Plugin init container definition
*/}}
{{- define "vcluster.oldPlugins.initContainers" -}}
{{- range $key, $container := .Values.plugin }}
{{- if or (ne $container.version "v2") (not $container.image) -}}
{{- continue -}}
{{- end -}}
- image: {{ $.Values.controlPlane.advanced.defaultImageRegistry }}{{ $container.image }}
  {{- if $container.name }}
  name: {{ $container.name | quote }}
  {{- else }}
  name: {{ $key | quote }}
  {{- end }}
  {{- if $container.imagePullPolicy }}
  imagePullPolicy: {{ $container.imagePullPolicy }}
  {{- end }}
  {{- if or $container.command $container.args }}
  {{- if $container.command }}
  command:
    {{- range $commandIndex, $command := $container.command }}
    - {{ $command | quote }}
    {{- end }}
  {{- end }}
  {{- if $container.args }}
  args:
    {{- range $argIndex, $arg := $container.args }}
    - {{ $arg | quote }}
    {{- end }}
  {{- end }}
  {{- else }}
  command: ["sh"]
  args: ["-c", "cp -r /plugin /plugins/{{ $key }}"]
  {{- end }}
  securityContext:
{{ toYaml $container.securityContext | indent 4 }}
  {{- if $container.volumeMounts }}
  volumeMounts:
{{ toYaml $container.volumeMounts | indent 4 }}
  {{- else }}
  volumeMounts:
    - mountPath: /plugins
      name: plugins
  {{- end }}
  {{- if $container.resources }}
  resources:
{{ toYaml $container.resources | indent 4 }}
  {{- end }}
{{- end }}
{{- end -}}
