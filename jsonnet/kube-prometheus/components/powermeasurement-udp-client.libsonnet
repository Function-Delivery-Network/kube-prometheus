local defaults = {
  local defaults = self,
  // Convention: Top-level fields related to CRDs are public, other fields are hidden
  // If there is no CRD for the component, everything is hidden in defaults.
  name:: 'powermeasurement-udp-client',
  namespace:: error 'must provide namespace',
  version:: error 'must provide version',
  image:: error 'must provide version',
  resources:: {
    requests: { cpu: '102m', memory: '180Mi' },
    limits: { cpu: '250m', memory: '180Mi' },
  },
  listenAddress:: '127.0.0.1',
  port:: 5000,
  commonLabels:: {
    'app.kubernetes.io/name': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'powermeasurement-client',
    'app.kubernetes.io/part-of': 'kube-prometheus',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
};

function(params) {
  local client = self,
  _config:: defaults + params,
  // Safety check
  assert std.isObject(client._config.resources),
  _metadata:: {
    name: client._config.name,
    namespace: client._config.namespace,
    labels: client._config.commonLabels,
  },

  deployment:
    local powerMeasurementClient = {
      name: client._config.name,
      image: client._config.image,
      resources: client._config.resources,
      env: [
        { name: 'POWERMETER_SERVER_IP', value: "127.0.0.1" },
        { name: 'POWERMETER_SERVER_PORT', value: "5000" },
        { name: 'INA3221_CHANNEL', value: "3" },
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
      metadata: client._metadata,
      spec: {
        selector: {
          matchLabels: client._config.selectorLabels,
        },
        template: {
          metadata: {
            annotations: {
              'kubectl.kubernetes.io/default-container': powerMeasurementClient.name,
            },
            labels: client._config.commonLabels,
          },
          spec: {
            nodeSelector: { 'kubernetes.io/os': 'linux' },
            tolerations: [{
              operator: 'Exists',
            }],
            containers: [powerMeasurementClient],
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
}