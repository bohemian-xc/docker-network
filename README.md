# Macvlan network setup for Raspberry Pi (three-step guide)

This guide walks through the updated process for creating VLANs on a Raspberry Pi, running the Docker Compose file to create macvlan networks, and installing a small systemd "shim" service that brings up a host-side macvlan interface so the host can reach the macvlan subnet.

IMPORTANT: The repository does not include any VLAN-creation scripts. All commands are manual examples you run on the Pi.

## Prerequisites
- A Linux host (Raspberry Pi OS / Debian-like) running Docker and Docker Compose (v2 recommended).
- Root or sudo access on the Pi to create VLAN interfaces and install systemd units.
- A managed switch or network capable of the VLANs you plan to use.

Files in this folder:
- [docker-compose-network.yml](docker-compose-network.yml) — Compose file that defines the networks and an example container.
- [.env.example](.env.example) — Environment variables for network names, parents, and subnets.
- [macvlan-shim.service](macvlan-shim.service) — Example systemd unit to create a host macvlan interface at boot.

---

## Section 1 — Create VLANs on the Raspberry Pi (manual)

1. Install VLAN support (if not present):

```bash
sudo apt update
sudo apt install -y vlan
```

2. Create virtual NICs

Create the file `/etc/network/interfaces.d/vlans` and add a stanza for each VLAN. Example for VLAN 10:

```
auto eth0.10
iface eth0.10 inet manual
	vlan-raw-device eth0
```

By convention the virtual NIC is named `<physicalNIC>.<PVID>` (for example, `eth0.10`). Add additional blocks for more VLANs.

3. Configure addressing (static example)

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

4. Apply changes

Restart networking or reboot:

```bash
sudo systemctl restart networking
# or
sudo reboot
```

5. Verify

Confirm both addresses are present:

```bash
hostname -I
# expected output example: 10.0.20.125 10.0.10.125
```

---

## Section 2 — Run the Docker Compose file to create macvlan networks

1. Copy the example environment file and edit values:

```bash
cp .env.example .env
# Edit .env to match your interface names, subnets and gateway values
```

Notes for `.env`:
- `VLAN*_PARENT` should match the Pi's VLAN sub-interface (for example `eth0.10`).
- `VLAN*_SUBNET` and `VLAN*_GATEWAY` define the macvlan subnet.
- `VLAN*_IPRANGE` (optional) can limit the range Docker will allocate for dynamic IPs.

2. The compose file mounts a local `vol` directory for persistent data. Create it if needed:

```bash
mkdir -p ./vol
```

3. Start the stack (this creates the macvlan networks declared in the compose file):

```bash
docker compose -f docker-compose-network.yml up -d
```

4. Verify networks exist and inspect them:

```bash
docker network ls
docker network inspect <network-name>
```

Important macvlan behaviour:
- Containers attached to a macvlan network are by default isolated from the Docker host. They behave like separate hosts on the physical network.
- To allow host ↔ container communication you can create a host-side macvlan interface (see Section 3) or use other bridging techniques.

---

## Section 3 — Install and configure `macvlan-shim.service` (systemd)

This repository includes an example `macvlan-shim.service` that creates a host-side macvlan interface so the Pi (host) can route to the macvlan subnet. The example file contains placeholder/static addresses — you MUST update these values to match your network.

1. Inspect the provided service file: [macvlan-shim.service](macvlan-shim.service)

2. Edit the unit to use the correct parent interface and addresses. Example entries you will typically adapt:

```ini
ExecStart=/sbin/ip link add macvlan-shim link eth0 type macvlan mode bridge
ExecStart=/sbin/ip addr add 192.168.1.62/24 dev macvlan-shim
ExecStart=/sbin/ip link set macvlan-shim up
ExecStart=/sbin/ip route add 192.168.1.64/26 dev macvlan-shim
```

- Change `eth0` to the physical interface on your Pi if different.
- Change `192.168.1.62/24` and the route `192.168.1.64/26` to static addresses and routes appropriate for your macvlan subnet.

3. Install the service on the Pi (example):

```bash
sudo cp macvlan-shim.service /etc/systemd/system/macvlan-shim.service
sudo systemctl daemon-reload
sudo systemctl enable --now macvlan-shim.service
sudo systemctl status macvlan-shim.service
```

4. Confirm host can reach the macvlan subnet and containers:

```bash
ip addr show macvlan-shim
ip route show
ping <container-ip>
```

Reminder: update static IP addresses
- The `macvlan-shim.service` file and any static IPs assigned to containers must be within the IP range/subnet defined for the corresponding macvlan network. Assigning addresses outside the subnet will cause routing failures and reachability issues.

---

## Cleanup

To remove the example container and the networks created by Compose:

```bash
docker compose -f docker-compose-network.yml down
```

To remove the host shim:

```bash
sudo systemctl disable --now macvlan-shim.service
sudo rm /etc/systemd/system/macvlan-shim.service
sudo systemctl daemon-reload
```

## Troubleshooting
- If the compose step fails to create a macvlan network, confirm the `parent` interface exists on the Pi (`ip link`) and that the VLAN is allowed/trunked on the switch.
- If the host cannot reach containers, double-check the `macvlan-shim.service` addresses and ensure they fall inside the macvlan subnet.

