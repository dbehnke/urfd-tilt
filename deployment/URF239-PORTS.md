# URF239 Port Usage on `whocares`

Observed from `/home/dbehnke/urf239` on host `whocares`.

## Runtime layout

- Compose project: `urf239`
- Compose file: `/home/dbehnke/urf239/docker-compose.yml`
- Running services: `urfd`, `tcd`, `dashboard`
- `urfd` and `tcd` use `network_mode: host`
- `dashboard` uses bridge networking with `8080/tcp` published to the host

## Dashboard

| Purpose | Address / port | Source |
| --- | --- | --- |
| HTTP dashboard | `0.0.0.0:8080/tcp` and `[::]:8080/tcp` | Docker publish + `config/dashboard/config.yaml` `server.addr: ":8080"` |
| Dashboard state NNG | `tcp://host.docker.internal:5555` | `config/dashboard/config.yaml` `server.nng_url` |
| Voice reflector NNG | `tcp://host.docker.internal:5556` | `config/dashboard/config.yaml` `voice.reflector_addr` |
| Voice control NNG | `tcp://host.docker.internal:6556` | `config/dashboard/config.yaml` `voice.control_addr` |

## URFD

| Purpose / protocol | Address / port | Source |
| --- | --- | --- |
| Dashboard NNG | `tcp://0.0.0.0:5555` | `config/production/urfd.ini` `[Dashboard] NNGAddr` |
| Dashboard/control NNG | `tcp://0.0.0.0:6001` | `config/production/urfd.ini` `[Dashboard] ControlNNGAddr`; comment says this was moved off `6556` to avoid conflict |
| Voice NNG audio | `tcp://0.0.0.0:5556` | `config/production/urfd.ini` `[Voice] NngAddr` |
| Voice NNG PTT/control | `tcp://0.0.0.0:6556` | Observed owned by the `urfd` container at runtime; dashboard `voice.control_addr` targets this port |
| Transcoder | `0.0.0.0:10101/tcp` | `config/production/urfd.ini` `[Transcoder] Port` and `BindingAddress` |
| DCS | `30052/udp` | `config/production/urfd.ini` `[DCS] Port` |
| DExtra | `30002/udp` | `config/production/urfd.ini` `[DExtra] Port` |
| DPlus | `20002/udp` | `config/production/urfd.ini` `[DPlus] Port` |
| DMRPlus | `8881/udp` | `config/production/urfd.ini` `[DMRPlus] Port` |
| M17 | `17001/udp` | `config/production/urfd.ini` `[M17] Port` |
| MMDVM | `62031/udp` | `config/production/urfd.ini` `[MMDVM] Port` |
| NXDN | `41401/udp` | `config/production/urfd.ini` `[NXDN] Port` |
| P25 | `41001/udp` | `config/production/urfd.ini` `[P25] Port` |
| URF | `10018/udp` | `config/production/urfd.ini` `[URF] Port` |
| USRP RX | `0.0.0.0:34001/udp` | `config/production/urfd.ini` `[USRP] RxPort` |
| USRP TX | `127.0.0.1:32001/udp` | `config/production/urfd.ini` `[USRP] TxPort` |
| YSF | `42001/udp` | `config/production/urfd.ini` `[YSF] Port` |

Configured but disabled in `urfd.ini`:

| Protocol | Port |
| --- | --- |
| Brandmeister | `10003/udp` |
| IMRS | `21111/udp` |

## TCD

| Purpose | Address / port | Source |
| --- | --- | --- |
| URFD transcoder connection | `127.0.0.1:10101` | `config/production/tcd.ini` `ServerAddress` + `Port` |

TCD uses host networking but does not publish Docker ports. Its configured relationship is to connect to URFD's transcoder listener on `127.0.0.1:10101`.

## Verification notes

Host socket checks showed listeners for `8080/tcp`, `5555/tcp`, `5556/tcp`, `6001/tcp`, `6556/tcp`, and `10101/tcp`, plus the URFD UDP protocol ports listed above.

The apparent `6001` vs `6556` mismatch is two different control surfaces, not a competing setting for one port:

- `6001/tcp` is the configured `[Dashboard] ControlNNGAddr` in URF239's `urfd.ini`. The inline comment says it was moved off `6556` to avoid conflict, likely for dashboard/control or AllStar-Nexus registration traffic.
- `6556/tcp` is still opened by the running `urfd` process. The `urfd` container owns the socket inode for `6556`, and the dashboard's `voice.control_addr` points to `tcp://host.docker.internal:6556`. This is the voice PTT/control endpoint paired with voice audio on `5556`.

Operationally: document both ports. Do not change dashboard voice control from `6556` to `6001` unless validating voice TX/PTT against URFD, because the dashboard voice client is explicitly configured for the `5556` audio / `6556` control pair.
