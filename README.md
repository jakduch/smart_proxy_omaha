# Smart Proxy - Omaha

This plug-in adds support for the Omaha Procotol to Foreman's Smart Proxy. It is used when updating CoreOS clusters.
The Smart Proxy Omaha plugin acts as a mirror for Omaha releases and sends reports to Foreman about the update activity of the managed hosts. It needs the [Foreman Omaha plugin](https://github.com/theforeman/foreman_omaha) installed to work properly.

## How it works

The operatingsystem packages install a cronjob, that runs the binary `smart-proxy-omaha-sync` nightly to sync omaha content from the upstream mirror servers.
Your CoreOS hosts can then be configured to update against the smart proxy. The proxy then uploads facts and reports to Foreman.
Omaha content is served directly from the proxy.

## Compatibility

| Foreman Proxy Version | Plugin Version |
| --------------------- | -------------- |
| >= 1.12               | any            |

## Installation

To be able to use Foreman for your Omaha updates, you need to install the [Foreman Omaha plugin](https://github.com/theforeman/foreman_omaha), install this smart-proxy plugin and configure your CoreOS hosts.

For the Smart Proxy plugin, follow the [smart-proxy plugin installation instructions](http://projects.theforeman.org/projects/foreman/wiki/How_to_Install_a_Smart-Proxy_Plugin). You usually just need to install the `rubygem-smart_proxy_omaha` package and restart the `foreman-proxy` service.

For the initial sync of releases you need to run the binary `smart-proxy-omaha-sync` as `foreman-proxy` user.

Do not forget to register the smart proxy in Foreman via the user interface.

## Host Configuration

You need to configure your CoreOS hosts to connect to the Omaha smart-proxy for updates. You can either configure your servers manually or use cloud-config.
If your smart-proxy uses a self-signed ssl certificate, you have to add the CA certificate to the CoreOS truststore. By default, the smart-proxys uses a PuppetCA certificate. To print the PuppetCA certificate, issue `cat $(puppet config print localcacert)` on any puppet enabled node.

### Using Config File

To add a custom CA certificate to CoreOS's truststore:

```bash
vim /etc/ssl/certs/customCA_root.pem
sudo /usr/sbin/update-ca-certificates
```

To configure CoreOS to connect to the Omaha smart-proxy for updates, edit `/etc/coreos/update.conf`,
to configure Flatcar to connect to the Omaha smart-proxy for updates, edit `/etc/flatcar/update.conf`:

```
GROUP=stable
SERVER=https://omahaproxy.example.com:8443/omaha/v1/update
```

Restart update engine:

```bash
sudo systemctl restart update-engine
```

### Using Cloud-Config

Configure CoreOS to connect to the Omaha smart-proxy for updates:

```yaml
#cloud-config
coreos:
  update:
    group: "stable"
    server: "https://omahaproxy.example.com:8443/omaha/v1/update"
```

Add a custom CA certificate to CoreOS's truststore:
```yaml
#cloud-config
write-files:
  - path: /etc/ssl/certs/customCA_root.pem
    permissions: 0644
    content: |
      -----BEGIN CERTIFICATE-----
      YOUR-BASE64-ENCODED-CERTIFICATE
      -----END CERTIFICATE-----
units:
  - name: update-ca-certificates.service
    command: start
    content: |
      [Unit]
      Description=Force Update CA bundle at /etc/ssl/certs/ca-certificates.crt
      # Since other services depend on the certificate store run this early
      DefaultDependencies=no
      Wants=systemd-tmpfiles-setup.service clean-ca-certificates.service
      After=systemd-tmpfiles-setup.service clean-ca-certificates.service
      Before=sysinit.target
      ConditionPathIsReadWrite=/etc/ssl/certs

      [Service]
      Type=oneshot
      ExecStart=/usr/sbin/update-ca-certificates
```


### Release channels

All three default release channels (alpha, beta, stable) are supported. You cannot define custom channels right now.

### Testing

To test if a client can successfully check for updates, these commands may help:

```bash
$ update_engine_client -check_for_update
$ journalctl -u update-engine.service
```

## Foreman delivery queue

Facts and reports are persisted in `queuepath` before they are delivered to Foreman.
Delivery happens in the background and is retried every `queue_retry_interval` seconds,
so an unavailable Foreman instance does not interrupt Omaha requests.

## Proxy Support

In the settings file you can specify a http proxy that is used to download Omaha content.
You need to allow https access to these servers:

For CoreOS:
* alpha.release.core-os.net
* beta.release.core-os.net
* stable.release.core-os.net
* update.release.core-os.net

For Flatcar:
* www.flatcar-linux.org
* alpha.release.flatcar-linux.net
* beta.release.flatcar-linux.net
* stable.release.flatcar-linux.net
* update.release.flatcar-linux.net

## Make it High Available

In order to make the Omaha Smart Proxy high available or add additional capacity, just scale out and put a loadbalancer in front of the proxies.

## Copyright

Copyright (c) 2016 The Foreman developers

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
