local defaults = {
  local defaults = self,
  // Convention: Top-level fields related to CRDs are public, other fields are hidden
  // If there is no CRD for the component, everything is hidden in defaults.
  name:: 'power-exporter',
  namespace:: error 'must provide namespace',
  version:: error 'must provide version',
  image:: error 'must provide version',
  resources:: {
    requests: { cpu: '102m', memory: '180Mi' },
    limits: { cpu: '250m', memory: '180Mi' },
  },
  listenAddress:: '127.0.0.1',
  port:: 8000,
  commonLabels:: {
    'app.kubernetes.io/name': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'exporter',
    'app.kubernetes.io/part-of': 'kube-prometheus',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
};

function(params) {
  local pe = self,
  _config:: defaults + params,
  // Safety check
  assert std.isObject(pe._config.resources),
  _metadata:: {
    name: pe._config.name,
    namespace: pe._config.namespace,
    labels: pe._config.commonLabels,
  },

  deployment:
    local powerExporter = {
      name: pe._config.name,
      image: pe._config.image,
      ports: [{
        name: 'http',
        containerPort: pe._config.port,
      }],
      resources: pe._config.resources,
      env: [
        { name: 'DEVICE_UDP_IP', value: "127.0.0.1" },
        { name: 'DEVICE_UDP_PORT', value: "5000" },
      ],
      securityContext: {
          allowPrivilegeEscalation: false,
          readOnlyRootFilesystem: true,
          capabilities: { drop: ['ALL'], add: ['SYS_TIME'] },
      },
    };

    {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: pe._metadata,
      spec: {
        selector: {
          matchLabels: pe._config.selectorLabels,
        },
        template: {
          metadata: {
            annotations: {
              'kubectl.kubernetes.io/default-container': powerExporter.name,
            },
            labels: pe._config.commonLabels,
          },
          spec: {
            nodeSelector: { 'kubernetes.io/os': 'linux' },
            tolerations: [{
              operator: 'Exists',
            }],
            containers: [powerExporter],
            priorityClassName: 'system-cluster-critical',
            securityContext: {
              runAsUser: 65534,
              runAsNonRoot: true,
            },
            hostPID: true,
            hostNetwork: true,
          },
        },
      },
    },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: pe._metadata,
    spec: {
      ports: [{
        name: 'http',
        port: pe._config.port,
        targetPort: 'http',
      }],
      selector: pe._config.selectorLabels,
    },
  },

  serviceMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: pe._metadata,
    spec: {
      jobLabel: 'app.kubernetes.io/name',
      selector: {
        matchLabels: pe._config.selectorLabels,
      },
      endpoints: [{
        path: '/metrics',
        port: 'http',
        scheme: 'http',
        interval: '15s',
        bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
        relabelings: [
          {
            action: 'replace',
            regex: '(.*)',
            replacement: '$1',
            sourceLabels: ['__meta_kubernetes_pod_node_name'],
            targetLabel: 'instance',
          },
        ],
        tlsConfig: {
          insecureSkipVerify: true,
        },
      }],
    },
  },
}