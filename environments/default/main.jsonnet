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
local envFromSource = k.core.v1.envFromSource;

local defaultEnvMap = {
  TZ: 'America/Los_Angeles',
  PUID: '1000',
  PGID: '100',
};

local make_arr_app(namespace, cfg) = {
  local _volumes = [
    volume.fromHostPath(x.name, x.host) + volume.hostPath.withType('Directory')
    for x in cfg.hostPathMappings
  ],
  local _volumeMounts = [
    volumeMount.new(x.name, x.ctr)
    for x in cfg.hostPathMappings
  ],
  local _containers = [
    container.new(name=cfg.name, image=cfg.image)
    + container.securityContext.withAllowPrivilegeEscalation(false)
    + container.withEnvMap(cfg.env)
    + container.withPorts([containerPort.new(cfg.port)])
    + container.withVolumeMounts(_volumeMounts),
  ],

  deployment: deployment.new(name=cfg.name, containers=_containers)
              + deployment.spec.template.spec.withVolumes(_volumes)
              + deployment.spec.template.spec.withNodeName('tec')
              + deployment.metadata.withNamespace(namespace),

  local _podSelector = { name: cfg.name },
  local _servicePorts = [servicePort.new(cfg.port, cfg.port)],

  service: service.new(cfg.name, _podSelector, _servicePorts)
           + service.spec.withType('NodePort')
           + service.metadata.withNamespace(namespace),
};

// FIXME: Duplicate code
local make_plex(namespace, cfg) = {
  local _volumes = [
    volume.fromHostPath(x.name, x.host) + volume.hostPath.withType('Directory')
    for x in cfg.hostPathMappings
  ] + [volume.fromEmptyDir('transcode') + volume.emptyDir.withMedium('Memory')],
  local _volumeMounts = [
    volumeMount.new(x.name, x.ctr)
    for x in cfg.hostPathMappings
  ] + [volumeMount.new('transcode', '/transcode')],
  local _containers = [
    container.new(name=cfg.name, image=cfg.image)
    + container.securityContext.withAllowPrivilegeEscalation(false)
    + container.withEnvMap(cfg.env)
    + container.withVolumeMounts(_volumeMounts),
  ],

  deployment: deployment.new(name=cfg.name, containers=_containers)
              + deployment.spec.template.spec.withVolumes(_volumes)
              + deployment.spec.template.spec.withNodeName('tec')
              + deployment.spec.template.spec.withHostNetwork(true)
              + deployment.metadata.withNamespace(namespace),
};

// FIXME: Craps out when the PIA port forward TTL is reached
// FIXME: Codify the `pia-credentials` secret
// FIXME: Duplicate code
local make_transmission(namespace, cfg) = {
  local _volumes = [
    volume.fromHostPath(x.name, x.host) + volume.hostPath.withType('Directory')
    for x in cfg.hostPathMappings
  ] + [volume.fromEmptyDir('pia-shared') + volume.emptyDir.withMedium('Memory')],
  local _volumeMounts = [
    volumeMount.new(x.name, x.ctr)
    for x in cfg.hostPathMappings
  ],
  local _containers = [
    container.new(name=cfg.name, image=cfg.image)
    + container.securityContext.withAllowPrivilegeEscalation(false)
    + container.withEnvMap(cfg.env)
    + container.withPorts([containerPort.new(cfg.port)])
    + container.withVolumeMounts(_volumeMounts),
    container.new(name='pia-wireguard', image='ghcr.io/pbar1/pia-wireguard:latest')
    + container.securityContext.withPrivileged(true)
    + container.withVolumeMounts([volumeMount.new('pia-shared', '/pia-shared')])
    + container.withEnvFrom(envFromSource.secretRef.withName('pia-credentials'))
    + container.withEnvMap({
      PREFERRED_REGION: 'swiss',
      PIA_DNS: 'true',
      PIA_PF: 'true',
      PF_FILE: '/pia-shared/port.dat',
    }),
    container.new('notify-port', image='ghcr.io/pbar1/transmission-pia-port:latest')
    + container.securityContext.withAllowPrivilegeEscalation(false)
    + container.withVolumeMounts([volumeMount.new('pia-shared', '/pia-shared')]),
  ],

  deployment: deployment.new(name=cfg.name, containers=_containers)
              + deployment.spec.template.spec.withVolumes(_volumes)
              + deployment.spec.template.spec.withNodeName('tec')
              + deployment.metadata.withNamespace(namespace),

  local _podSelector = { name: cfg.name },
  local _servicePorts = [servicePort.new(cfg.port, cfg.port)],

  service: service.new(cfg.name, _podSelector, _servicePorts)
           + service.spec.withType('NodePort')
           + service.metadata.withNamespace(namespace),
};

{
  media: {
    namespace: namespace.new('media'),

    prowlarr: make_arr_app('media', {
      name: 'prowlarr',
      image: 'lscr.io/linuxserver/prowlarr:develop',
      env: defaultEnvMap,
      port: 9696,
      hostPathMappings: [
        { name: 'config', host: '/data/general/config/prowlarr', ctr: '/config' },
      ],
    }),

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

    bazarr: make_arr_app('media', {
      name: 'bazarr',
      image: 'lscr.io/linuxserver/bazarr:latest',
      env: defaultEnvMap,
      port: 6767,
      hostPathMappings: [
        { name: 'config', host: '/data/general/config/bazarr', ctr: '/config' },
        { name: 'tv', host: '/data/media/tv', ctr: '/tv' },
        { name: 'movies', host: '/data/media/movies', ctr: '/movies' },
      ],
    }),

    plex: make_plex('media', {
      name: 'plex',
      image: 'lscr.io/linuxserver/plex:latest',
      env: defaultEnvMap,
      hostPathMappings: [
        { name: 'config', host: '/data/general/config/plex', ctr: '/config' },
        { name: 'tv', host: '/data/media/tv', ctr: '/tv' },
        { name: 'movies', host: '/data/media/movies', ctr: '/movies' },
        { name: 'audiobooks', host: '/data/media/audiobooks', ctr: '/audiobooks' },
      ],
    }),

    transmission: make_transmission('media', {
      name: 'transmission',
      image: 'lscr.io/linuxserver/transmission:latest',
      env: defaultEnvMap { TRANSMISSION_WEB_HOME: '/flood-for-transmission/' },
      port: 9091,
      hostPathMappings: [
        { name: 'config', host: '/data/general/config/transmission', ctr: '/config' },
        { name: 'downloads', host: '/data/torrents/transmission', ctr: '/downloads' },
      ],
    }),
  },
}
