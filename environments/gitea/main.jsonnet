local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';

local namespace = k.core.v1.namespace;
local helm = tanka.helm.new(std.thisFile);

{
  namespace: namespace.new('gitea'),

  release: helm.template('gitea', '../../charts/gitea', {
    namespace: 'gitea',
    values: {
      gitea: { config: { server: { SSH_DOMAIN: 'ssh.gitea.xnauts.net', SSH_PORT: 32222 } } },
      image: { rootless: true, pullPolicy: 'IfNotPresent' },
      service: { ssh: {
        type: 'LoadBalancer',
        externalTrafficPolicy: 'Local',
        annotations: { 'external-dns.alpha.kubernetes.io/hostname': 'ssh.gitea.xnauts.net' },
      } },
      ingress: {
        enabled: true,
        annotations: {
          'cert-manager.io/cluster-issuer': 'letsencrypt-production',
          'traefik.ingress.kubernetes.io/router.entrypoints': 'websecure',
        },
        hosts: [{ host: 'gitea.xnauts.net', paths: [{ path: '/', pathType: 'Prefix' }] }],
        tls: [{ hosts: ['gitea.xnauts.net'], secretName: 'gitea-tls' }],
        apiVersion: 'networking.k8s.io/v1',
      },
    },
  }),
}
