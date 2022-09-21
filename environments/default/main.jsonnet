local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';

// https://jsonnet-libs.github.io/k8s-libsonnet
local namespace = k.core.v1.namespace;
local deployment = k.apps.v1.deployment;
local container = k.core.v1.container;
local containerPort = k.core.v1.containerPort;
local volume = k.core.v1.volume;
local volumeMount = k.core.v1.volumeMount;
local service = k.core.v1.service;
local servicePort = k.core.v1.servicePort;
local envFromSource = k.core.v1.envFromSource;
local ingress = k.networking.v1.ingress;
local ingressTLS = k.networking.v1.ingressTLS;
local ingressRule = k.networking.v1.ingressRule;
local httpIngressPath = k.networking.v1.httpIngressPath;

// https://tanka.dev/helm
local helm = tanka.helm.new(std.thisFile);

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
    + container.withTerminationMessagePolicy('FallbackToLogsOnError')
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
local make_doplarr(namespace, cfg) = {
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
    + container.withTerminationMessagePolicy('FallbackToLogsOnError')
    + container.withEnvMap(cfg.env)
    + container.withEnvFrom(envFromSource.secretRef.withName('doplarr-env'))
    + container.withVolumeMounts(_volumeMounts),
  ],

  deployment: deployment.new(name=cfg.name, containers=_containers)
              + deployment.spec.template.spec.withVolumes(_volumes)
              + deployment.spec.template.spec.withNodeName('tec')
              + deployment.metadata.withNamespace(namespace),
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
    + container.withTerminationMessagePolicy('FallbackToLogsOnError')
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
    + container.withTerminationMessagePolicy('FallbackToLogsOnError')
    + container.withEnvMap(cfg.env)
    + container.withPorts([containerPort.new(cfg.port)])
    + container.withVolumeMounts(_volumeMounts),
    container.new(name='pia-wireguard', image='ghcr.io/pbar1/pia-wireguard:latest')
    + container.securityContext.withPrivileged(true)
    + container.withTerminationMessagePolicy('FallbackToLogsOnError')
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
    + container.withTerminationMessagePolicy('FallbackToLogsOnError')
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

  /*
  ingress: ingress.new(cfg.name)
           + ingress.metadata.withAnnotations({
             'cert-manager.io/cluster-issuer': 'letsencrypt-production',
             'traefik.ingress.kubernetes.io/router.entrypoints': 'websecure',
           })
           + ingress.spec.withRules(
             ingressRule.withHost(cfg.name + '.xnauts.net')
             + ingressRule.http.withPaths(
               httpIngressPath.withPath('/')
               + httpIngressPath.withPathType('Prefix')
               + httpIngressPath.backend.service.withName(cfg.name)
               + httpIngressPath.backend.service.port.withNumber(cfg.port)
             )
           )
           + ingress.spec.withTls(ingressTLS.withHosts(cfg.name + '.xnauts.net') + ingressTLS.withSecretName(cfg.name + '-tls'))
           + ingress.metadata.withNamespace(namespace),
           */
};

// FIXME: Duplicate code
local make_unifi(namespace, cfg) = {
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
    + container.withTerminationMessagePolicy('FallbackToLogsOnError')
    + container.withEnvMap(cfg.env)
    + container.withVolumeMounts(_volumeMounts),
  ],

  deployment: deployment.new(name=cfg.name, containers=_containers)
              + deployment.spec.template.spec.withVolumes(_volumes)
              + deployment.spec.template.spec.withNodeName('tec')
              + deployment.spec.template.spec.withHostNetwork(true)
              + deployment.metadata.withNamespace(namespace),
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

    doplarr: make_doplarr('media', {
      name: 'doplarr',
      image: 'lscr.io/linuxserver/doplarr:latest',
      env: defaultEnvMap {
        SONARR__URL: 'http://sonarr:8989',
        RADARR__URL: 'http://radarr:7878',
      },
      hostPathMappings: [
        { name: 'config', host: '/data/general/config/doplarr', ctr: '/config' },
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

  certManager: {
    namespace: namespace.new('cert-manager'),

    certManager: helm.template('cert-manager', '../../charts/cert-manager', {
      namespace: 'cert-manager',
      values: {
        installCRDs: true,
        extraArgs: [
          '--dns01-recursive-nameservers-only',
          '--dns01-recursive-nameservers=1.1.1.1:53,1.0.0.1:53',
        ],
      },
    }),

    // TODO: Abstract this and make `letsencrypt-staging`
    letsEncryptProduction: {
      apiVersion: 'cert-manager.io/v1',
      kind: 'ClusterIssuer',
      metadata: { name: 'letsencrypt-production', namespace: 'cert-manager' },
      spec: { acme: {
        server: 'https://acme-v02.api.letsencrypt.org/directory',
        email: 'piercebartine@gmail.com',
        privateKeySecretRef: { name: 'letsencrypt-production' },
        solvers: [{
          dns01: { cloudflare: {
            email: 'piercebartine@gmail.com',
            apiKeySecretRef: { name: 'cloudflare-api-key', key: 'api-key' },
          } },
          selector: { dnsZones: ['xnauts.net'] },
        }],
      } },
    },
  },

  externalDns: {
    namespace: namespace.new('external-dns'),
    externalDns: helm.template('external-dns', '../../charts/external-dns', {
      namespace: 'external-dns',
      values: {
        logLevel: 'debug',
        triggerOnEventLoop: true,
        policy: 'sync',
        domainFilters: ['xnauts.net'],
        provider: 'cloudflare',
        // extraArgs: ['--cloudflare-proxied'],
        env: [
          { name: 'CF_API_EMAIL', value: 'piercebartine@gmail.com' },
          { name: 'CF_API_KEY', valueFrom: { secretKeyRef: { name: 'cloudflare', key: 'CF_API_KEY' } } },
        ],
      },
    }),
  },


  // descheduler: {
  //   descheduler: helm.template('descheduler', '../../charts/descheduler', {
  //     namespace: 'kube-system',
  //     values: { schedule: '*/2 * * * *' },
  //   }),
  // },

  /*
  monitoring: {
    namespace: namespace.new('monitoring'),

    prometheus: helm.template('prometheus', '../../charts/kube-prometheus-stack', {
      namespace: 'monitoring',
      values: {
        alertmanager: { enabled: false },
        grafana: {
          defaultDashboardsTimezone: 'browser',
          adminPassword: 'grafana',
        },
        persistence: { enabled: false },
      },
      prometheus: {
        prometheusSpec: { retention: '30d' },
      },
    }),
  },
  */

}
