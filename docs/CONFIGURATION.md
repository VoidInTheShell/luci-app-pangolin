# Configuration reference

LuCI writes an allowlisted UCI model to `/etc/config/newt`. At service start,
the init script renders Newt's native JSON schema to a root-only runtime file.
The table below makes that translation explicit.

| LuCI area | UCI option | Newt JSON key | Purpose |
| --- | --- | --- | --- |
| General | `endpoint` | `endpoint` | Public Pangolin HTTPS URL, with optional non-default port |
| General | `id` | `id` | Existing Newt identifier |
| General | `secret` | `secret` | Existing Newt secret |
| General | `provisioning_key` | `provisioningKey` | One-time site provisioning key |
| General | `name` | `name` | Site name used during provisioning |
| General | `log_level` | `logLevel` | `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL` |
| Network | `dns` | `dns` | DNS resolver used by the tunnel |
| Network | `mtu` | `mtu` | Tunnel MTU, 576–9000 |
| Network | `port` | `port` | Optional WireGuard listen port |
| Network | `interface` | `interface` | Client tunnel interface name |
| Network | `native` | `native` | Use native client interfaces |
| Network | `native_main` | `nativeMain` | Use a native main WireGuard interface |
| Network | `interface_main` | `interfaceMain` | Native main-interface name |
| Network | `no_cloud` | `noCloud` | Disable cloud-relay fallback |
| Network | `prefer_endpoint` | `preferEndpoint` | Override server endpoint selection |
| Network | `local_endpoint_interfaces` | `localEndpointInterfaces` | Interfaces used for local endpoint discovery |
| Network | `ping_interval` | `pingInterval` | Tunnel keepalive interval |
| Network | `ping_timeout` | `pingTimeout` | Keepalive timeout |
| Network | `udp_proxy_idle_timeout` | `udpProxyIdleTimeout` | Idle lifetime for UDP proxy sessions |
| Features | `disable_clients` | `disableClients` | Disable Pangolin client routing |
| Features | `disable_ssh` | `disableSsh` | Disable SSH integration |
| Features | `enforce_hc_cert` | `enforceHcCert` | Verify TLS certificates for health checks |
| Features | `updown_script` | `updownScript` | Target add/remove hook |
| Features | `blueprint_file` | `blueprintFile` | Blueprint applied at startup |
| Features | `provisioning_blueprint_file` | `provisioningBlueprintFile` | Blueprint applied after provisioning |
| Features | `docker_socket` | `dockerSocket` | Optional container discovery socket |
| Features | `docker_enforce_network_validation` | `dockerEnforceNetworkValidation` | Validate discovered container networks |
| Features | `auth_daemon_key` | `adPreSharedKey` | SSH auth-daemon shared key |
| Features | `auth_daemon_principals_file` | `adPrincipalsFile` | SSH principals output path |
| Features | `auth_daemon_ca_cert_path` | `adCaCertPath` | SSH CA certificate path |
| Features | `auth_daemon_generate_random_password` | `adGenerateRandomPassword` | Generate authenticated-user passwords |
| TLS | `tls_client_cert` | `tlsClientCertFile` | Client certificate path |
| TLS | `tls_client_key` | `tlsClientKey` | Client key path |
| TLS | `tls_client_ca` | `tlsClientCa` | Additional CA certificate paths |
| TLS | `tls_private_key` | `tlsClientCert` | Legacy PKCS#12 bundle path |
| Observability | `metrics` | `metrics` | Enable Prometheus metrics |
| Observability | `otlp` | `otlp` | Enable OTLP export |
| Observability | `admin_addr` | `metricsAdminAddr` | Metrics and diagnostics listen address |
| Observability | `region` | `region` | Telemetry region label |
| Observability | `metrics_async_bytes` | `metricsAsyncBytes` | Asynchronous byte counters |
| Observability | `pprof` | `pprof` | Enable Go profiling endpoints |

`healthFile` is deliberately fixed at `/var/run/newt/healthy`, rather than
user configurable, because LuCI uses it as its connected-state signal.

The remaining UCI settings are OpenWrt integration controls and are not passed
to Newt: `enabled`, `auth_mode`, `respawn_threshold`, `respawn_timeout`,
`respawn_retry`, `stdout`, and `stderr`.

## Reference implementation

No official OPNsense Newt plug-in was published in the sources available when
this package was implemented. The option set was therefore derived from the
Newt 1.18.1 `fileSettings` schema and cross-checked against Fossorial's router
web integration. The LuCI interface exposes every setting in that upstream
JSON schema while keeping Pangolin resources and access policy out of scope.

Provisioning-key enrollment is supported and converted to persistent Newt
credentials automatically. Newt 1.18.1 does not expose a device-approval-only
authentication mode in that schema.
