local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';

local namespace = k.core.v1.namespace;
local helm = tanka.helm.new(std.thisFile);

{
  namespace: namespace.new('unifi'),

  unifiController: helm.template('unifi-controller', '../../charts/unifi', {
    namespace: 'unifi',
    values: {
      env: { TZ: 'America/Los_Angeles', UNIFI_GID: '100', UNIFI_UID: '1000' },
      hostNetwork: true,
      persistence: { data: {
        enabled: true,
        type: 'hostPath',
        hostPath: '/data/general/unifi',
        mountPath: '/unifi',
      } },
    },
  }),
}
