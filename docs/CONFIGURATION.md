# Configuration reference

LuCI writes allowlisted values to `/etc/config/pangolin` section `main`.
Secrets are never returned to the browser: a blank password field keeps the
stored value, and a separate checkbox explicitly clears it. The file and the
generated runtime JSON are mode `0600`.

The service renders UCI into `/var/run/pangolin/site.json` and runs:

```sh
pangolin up site --config-file /var/run/pangolin/site.json
```

## Identity and connection

| UCI option | JSON key | Default / purpose |
| --- | --- | --- |
| `enabled` | local | `0`; run the connector when set to `1` |
| `endpoint` | `endpoint` | `https://app.pangolin.net`; public Pangolin HTTPS URL |
| `auth_mode` | local | `credentials` or `provisioning` |
| `id` | `id` | Existing Pangolin Site ID |
| `secret` | `secret` | Existing site secret |
| `provisioning_key` | `provisioningKey` | One-time provisioning key |
| `name` | `name` | Site name used during provisioning |
| `log_level` | `logLevel` | `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL` |

In credentials mode, both `id` and `secret` are required. Provisioning mode
requires both `provisioning_key` and `name`. A helper copies generated
permanent credentials back to UCI and clears the one-time values.

## Tunnel and networking

| UCI option | JSON key | Default / purpose |
| --- | --- | --- |
| `dns` | `dns` | `9.9.9.9`; tunnel resolver |
| `mtu` | `mtu` | `1280`; accepted range 576–9000 |
| `port` | `port` | Optional WireGuard listen port |
| `interface` | `interface` | `pangolin`; upstream client-interface prefix/name |
| `no_cloud` | `noCloud` | Disable cloud fallback |
| `prefer_endpoint` | `preferEndpoint` | Prefer a specific endpoint |
| `local_endpoint_interfaces` | `localEndpointInterfaces` | Limit endpoint discovery to named host interfaces |
| `ping_interval` | `pingInterval` | `15s` |
| `ping_timeout` | `pingTimeout` | `7s` |
| `udp_proxy_idle_timeout` | `udpProxyIdleTimeout` | `90s` |
| `native` | `native` | Create native interfaces for client tunnels served by the site |
| `native_main` | `nativeMain` | Create a TUN for the site's main tunnel; experimental |
| `interface_main` | `interfaceMain` | `pangolin`; native-main Linux interface name |
| `manage_network` | local | Register native-main in netifd/firewall4 |

`healthFile` is fixed to `/var/run/pangolin/site-healthy` for status reporting.
The reliable upstream default is `native_main=0`, which uses Newt's userspace
netstack and creates no host interface.

With `enabled=1`, `native_main=1`, and `manage_network=1`,
`pangolin-network sync` creates `network.pangolin` and firewall zone
`pangolin`. The initial zone permits input/output and rejects forwarding so
site proxy listeners on the tunnel address remain reachable. Later syncs
preserve administrator changes to the firewall policy. It does not create
forwardings, masquerading, or remote-to-LAN access.

## Site features

| UCI option | JSON key | Purpose |
| --- | --- | --- |
| `disable_clients` | `disableClients` | Disable Pangolin client-routing features |
| `disable_ssh` | `disableSsh` | Disable SSH integration |
| `enforce_hc_cert` | `enforceHcCert` | Verify health-check certificates |
| `updown_script` | `updownScript` | Absolute target-change hook path |
| `blueprint_file` | `blueprintFile` | Blueprint applied at startup |
| `provisioning_blueprint_file` | `provisioningBlueprintFile` | Blueprint applied after provisioning |
| `docker_socket` | `dockerSocket` | Optional discovery socket; normally empty on OpenWrt |
| `docker_enforce_network_validation` | `dockerEnforceNetworkValidation` | Validate Docker networks |

## TLS and authentication daemon

| UCI option | JSON key | Purpose |
| --- | --- | --- |
| `tls_client_cert` | `tlsClientCertFile` | mTLS client certificate path |
| `tls_client_key` | `tlsClientKey` | mTLS private key path |
| `tls_client_ca` | `tlsClientCa` | List of trusted CA paths |
| `tls_private_key` | `tlsClientCert` | Legacy PKCS#12 bundle path |
| `auth_daemon_key` | `adPreSharedKey` | Auth-daemon pre-shared key |
| `auth_daemon_principals_file` | `adPrincipalsFile` | SSH principals file |
| `auth_daemon_ca_cert_path` | `adCaCertPath` | SSH CA certificate path |
| `auth_daemon_generate_random_password` | `adGenerateRandomPassword` | Generate authenticated-user passwords |

LuCI requires filesystem paths to be absolute and rejects `..` components.
Certificate/key files are not copied into the package and must be installed by
the administrator with appropriate permissions.

## Observability and process policy

| UCI option | JSON/local key | Default / purpose |
| --- | --- | --- |
| `metrics` | `metrics` | Enable Prometheus metrics |
| `admin_addr` | `metricsAdminAddr` | `127.0.0.1:2112`; metrics/admin bind address |
| `metrics_async_bytes` | `metricsAsyncBytes` | Asynchronous byte counters |
| `otlp` | `otlp` | Enable OTLP export |
| `region` | `region` | Telemetry region label |
| `pprof` | `pprof` | Go profiling endpoints on the admin listener |
| `respawn_threshold` | procd | `3600` seconds |
| `respawn_timeout` | procd | `5` seconds before restart |
| `respawn_retry` | procd | `5` rapid-failure retries |
| `stdout`, `stderr` | procd | Send both streams to logd |

Keep the admin listener on loopback unless explicit authentication and
firewall policy protect it. OTLP endpoint/credentials are deliberately not
stored by this interface; advanced deployments may provide them through a
separately managed process environment.

## Headless configuration

`/usr/libexec/configure-pangolin` accepts a root-only mode-0600 shell file:

```sh
PANGOLIN_ENDPOINT='https://pangolin.example.com'
NEWT_ID='site-id'
NEWT_SECRET='site-secret'
PANGOLIN_NATIVE_MAIN='0'
```

Or use `NEWT_PROVISIONING_KEY` and `NEWT_SITE_NAME` instead of the ID/secret
pair. The helper validates the URL and credential combination, commits UCI,
synchronizes optional network state, enables the init service, and restarts it.
