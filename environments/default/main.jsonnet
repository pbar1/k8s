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

local defaultEnvMap = {
  TZ: 'America/Los_Angeles',
  PUID: '1000',
  PGID: '100',
};

local make_arr_app(namespace, cfg) = {
  deployment: deployment.new(
    name=cfg.name,
    containers=[
      container.new(name=cfg.name, image=cfg.image)
      + container.securityContext.withAllowPrivilegeEscalation(false)
      + container.withEnvMap(cfg.env)
      + container.withPorts([containerPort.new(cfg.port)])
      + container.withVolumeMounts([volumeMount.new(x.name, x.ctr) for x in cfg.hostPathMappings]),
    ]
  ) + deployment.spec.template.spec.withVolumes([
    volume.fromHostPath(x.name, x.host) + volume.hostPath.withType('Directory')
    for x in cfg.hostPathMappings
  ]) + deployment.metadata.withNamespace(namespace),

  service: service.new(
    cfg.name, { name: cfg.name }, [servicePort.new(cfg.port, cfg.port)]
  ) + service.spec.withType('NodePort') + service.metadata.withNamespace(namespace),
};

{
  media: {
    namespace: namespace.new('media'),

    sonarr: make_arr_app('media', {
      name: 'sonarr',
      image: 'lscr.io/linuxserver/sonarr:latest',
      env: defaultEnvMap,
      port: 8989,
      hostPathMappings: [
        { name: 'config', host: '/data/general/config/sonarr', ctr: '/config' },
        { name: 'downloads', host: '/data/torrents/transmission', ctr: '/downloads' },
        { name: 'media', host: '/data/media/tv', ctr: '/tv' },
      ],
    }),

    radarr: make_arr_app('media', {
      name: 'radarr',
      image: 'lscr.io/linuxserver/radarr:latest',
      env: defaultEnvMap,
      port: 7878,
      hostPathMappings: [
        { name: 'config', host: '/data/general/config/radarr', ctr: '/config' },
        { name: 'downloads', host: '/data/torrents/transmission', ctr: '/downloads' },
        { name: 'media', host: '/data/media/movies', ctr: '/movies' },
      ],
    }),

    readarr: make_arr_app('media', {
      name: 'readarr',
      image: 'lscr.io/linuxserver/readarr:develop',
      env: defaultEnvMap,
      port: 8787,
      hostPathMappings: [
        { name: 'config', host: '/data/general/config/readarr-audiobooks', ctr: '/config' },
        { name: 'downloads', host: '/data/torrents/transmission', ctr: '/downloads' },
        { name: 'media', host: '/data/media/audiobooks', ctr: '/audiobooks' },
      ],
    }),
  },
}
