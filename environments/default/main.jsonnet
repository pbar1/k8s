local k = import 'k.libsonnet';

// https://jsonnet-libs.github.io/k8s-libsonnet/
local namespace = k.core.v1.namespace;
local deployment = k.apps.v1.deployment;
local container = k.core.v1.container;
local containerPort = k.core.v1.containerPort;
local volume = k.core.v1.volume;
local volumeMount = k.core.v1.volumeMount;
local service = k.core.v1.service;
local servicePort = k.core.v1.servicePort;

local make_arr_app(namespace, cfg) = {
  deployment: deployment.new(
    name='sonarr',
    containers=[
      container.new(name='sonarr', image='lscr.io/linuxserver/sonarr:latest')
      + container.withEnvMap({
        TZ: 'America/Los_Angeles',
        PUID: '1000',
        PGID: '100',
      })
      + container.withPorts(ports=[containerPort.new(8989)])
      + container.securityContext.withAllowPrivilegeEscalation(false)
      + container.withVolumeMounts([
        volumeMount.new('config', '/config'),
        volumeMount.new('downloads', '/downloads'),
        volumeMount.new('tv', '/tv'),
      ]),
    ]
  ) + deployment.spec.template.spec.withVolumes([
    volume.fromHostPath('config', '/data/general/config/sonarr') + volume.hostPath.withType('Directory'),
    volume.fromHostPath('downloads', '/data/torrents/transmission') + volume.hostPath.withType('Directory'),
    volume.fromHostPath('tv', '/data/media/tv') + volume.hostPath.withType('Directory'),
  ]) + deployment.metadata.withNamespace('media'),

  service: service.new(
    'sonarr', { name: 'sonarr' }, [servicePort.new(8989, 8989)]
  ) + service.spec.withType('NodePort') + service.metadata.withNamespace('media'),
};

{
  media: {
    namespace: namespace.new('media'),
    sonarr: make_arr_app('media', {
      name: 'sonarr',
      image: 'lscr.io/linuxserver/sonarr:latest',
      hostPathMappings: [
        { name: 'config', host: '/data/general/config/sonarr', ctr: '/config' },
        { name: 'downloads', host: '/data/torrents/transmission', ctr: '/downloads' },
        { name: 'media', host: '/data/media/tv', ctr: '/tv' },
      ],
      port: 8989,
    }),
  },
}
