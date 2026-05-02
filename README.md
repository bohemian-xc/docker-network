**Overview**
- **Purpose**: Lightweight repository to create and share Docker network objects (bridge and macvlan) for other projects.
- **Scope**: Provides a reusable `docker-compose-network.yml` and an example `.env` to define macvlan/bridge networks and a data volume.

**Prerequisites**
- Docker Engine and Docker Compose (Compose V2) installed.
- For `macvlan` networks: host network interface(s) configured and available (e.g., `eth0`, `eth0.10`).
- On Linux hosts you may need to create VLAN sub-interfaces (example uses `eth0.10`).

## 1. Setting up VLAN on Raspberry Pi

This section follows the steps from the Engineer's Workshop guide to create VLAN virtual NICs and configure IP addressing.

Prerequisites:

- A managed switch port configured as a trunk/hybrid with the VLANs you need
- Physical NIC name on the Pi (e.g., `eth0`)

1) Install the VLAN package

```bash
sudo apt update
sudo apt install -y vlan
```

2) Create virtual NICs

Create the file `/etc/network/interfaces.d/vlans` and add a stanza for each VLAN. Example for VLAN 10:

```
auto eth0.10
iface eth0.10 inet manual
	vlan-raw-device eth0
```

By convention the virtual NIC is named `<physicalNIC>.<PVID>` (for example, `eth0.10`). Add additional blocks for more VLANs.

3) Configure addressing (static example)

Edit `/etc/dhcpcd.conf` and add IP configuration for each interface you want to set statically. Example:

```
# example static IP configuration

interface eth0
	static ip_address=10.0.20.125/24

interface eth0.10
	static ip_address=10.0.10.125/24
	static routers=10.0.10.1
	static domain_name_servers=1.1.1.1
```

If you use DHCP for a VLAN virtual NIC, you can skip the static block for that interface.

4) Apply changes

Restart networking or reboot:

```bash
sudo systemctl restart networking
# or
sudo reboot
```

5) Verify

Confirm both addresses are present:

```bash
hostname -I
# expected output example: 10.0.20.125 10.0.10.125
```

If you need to enable the `8021q` kernel module explicitly, add it to `/etc/modules` so it loads at boot:

```bash
echo 8021q | sudo tee -a /etc/modules
sudo modprobe 8021q
```

Notes:

- Replace `eth0`, VLAN IDs and IP addresses with values for your network.
- If your Pi uses a different init/system (or a GUI network manager), adapt these steps accordingly.


## 2. Running docker compose to setup macvlan networks

**Quick Start**
- Copy the example env and edit values:

  - Copy `.env.example` to `.env` and update network and healthcheck settings.

  - Minimal edit example (in `.env`):

    HEALTHCHECK_CMD="nc -z -w 3 192.168.1.1 80 || exit 1"
    HEALTHCHECK_INT=30s
    HEALTHCHECK_TOT=10s
    HEALTHCHECK_RTS=3
    HEALTHCHECK_STP=30s

    VLAN10_PARENT=eth0.10
    VLAN10_SUBNET=192.168.10.0/24
    VLAN10_GATEWAY=192.168.10.1
    VLAN10_NAME=macvlan_vlan10

    VLAN100_PARENT=eth0.100
    VLAN100_SUBNET=192.168.100.0/24
    VLAN100_GATEWAY=192.168.100.1
    VLAN100_NAME=macvlan_vlan100

    VLAN200_PARENT=eth0.200
    VLAN200_SUBNET=192.168.200.0/24
    VLAN200_GATEWAY=192.168.200.1
    VLAN200_NAME=macvlan_vlan200

- Create VLAN sub-interfaces on the host (example for Linux):

```bash
sudo ip link add link eth0 name eth0.10 type vlan id 10
sudo ip link set eth0.10 up
```

- Start the compose stack (this will create networks and a container named `network_container`):

```bash
docker compose up -d
```

**Notes & Important Gotchas**
- Network key names in `docker-compose-network.yml`:
  - `shared_bridge` — a normal bridge network used by the example service.
  - `vlan10_net`, `vlan100_net`, `vlan200_net` — macvlan networks created using `parent` from `.env`.

- Ensure the `parent` interface exists on the host where Compose runs. If the parent is a VLAN sub-interface (e.g., `eth0.10`) create it beforehand.

- `macvlan` network constraints:
  - Containers on a macvlan network are isolated from the Docker host by default. To allow host-to-container access, additional macvlan configuration or a bridge on the host is needed.
  - Using macvlan on Windows or macOS hosts (Docker Desktop) is typically unsupported — run macvlan on Linux hosts (Raspberry Pi, servers, WSL2 with proper network setup).

- Healthcheck: The `HEALTHCHECK_CMD` variable is used as a `CMD-SHELL` argument. Keep the full command in `.env` and include quotes if it contains spaces.

**Files**
- `docker-compose-network.yml` — compose file that defines example service, bridge and macvlan networks, and a local volume `data_volume`.
- `.env.example` — example variables to copy to `.env`.

**Advanced / Manual steps**
- Create macvlan networks manually (if you prefer explicit control):

```bash
docker network create -d macvlan \
  --subnet=192.168.10.0/24 --gateway=192.168.10.1 \
  -o parent=eth0.10 macvlan_vlan10
```

- Remove the example container and networks:

```bash
docker compose down
# or
docker rm -f network_container && docker network rm macvlan_vlan10 macvlan_vlan100 macvlan_vlan200
```

**Troubleshooting**
- If Compose fails to create a macvlan network, check the parent interface name and run `ip link` on the host.
- If `HEALTHCHECK_CMD` fails, test it directly on the host shell to confirm connectivity and command syntax.

