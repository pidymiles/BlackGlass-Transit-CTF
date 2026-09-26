# Blackglass Transit

Blackglass Transit is an advanced, isolated Active Directory CTF designed for a Proxmox VE host with nested KVM enabled. The player begins with access to one web service, compromises two Linux systems, constructs two pivots, enters a Windows domain, and follows an Active Directory privilege path to domain administrator.

The deployment generates five unique flags and fresh infrastructure passwords each time the range is reset.

## Range layout

Version: 1.0.0

| Guest | Operating system | RAM | Reachable networks | Role |
| --- | --- | ---: | --- | --- |
| edge01 | Debian 12 | 1 GB | Outside, transit | Initial web target and first SSH pivot |
| jump01 | Debian 12 | 1 GB | Transit, corporate | Internal repository, Linux escalation, second SSH pivot |
| dc01 | Windows Server 2022 | 4 GB | Corporate | BLACKGLASS.LAB domain controller |
| file01 | Windows Server 2022 | 4 GB | Corporate | Domain member and restricted archive share |
| ws01 | Windows 11 | 4 GB | Corporate | Internal employee portal and password-culture clues |

The nested guests use three intentionally separated challenge networks:

| Network | CIDR | Purpose |
| --- | --- | --- |
| Outside | 172.22.10.0/24 | Only edge01 is attached |
| Transit | 10.60.10.0/24 | edge01 to jump01 |
| Corporate | 10.60.20.0/24 | jump01 to the Windows domain |

Only TCP 8080 and TCP 2222 are published from the range-controller VM. No Windows service is intentionally exposed to the physical LAN.

## Host requirements

Create one Debian 12 VM on Proxmox with:

- 8 virtual CPUs
- 24 GB RAM
- At least 180 GB of thin-provisioned storage
- CPU type set to host
- One NIC on the isolated lab/LAN bridge used by the Kali machine
- Internet access during the initial box download

Enable host CPU passthrough for the range-controller VM from the Proxmox shell:

~~~bash
qm set RANGE_VM_ID --cpu host
~~~

Inside the Debian range-controller VM, verify that nested virtualization is visible:

~~~bash
test -e /dev/kvm && grep -E -m1 '(vmx|svm)' /proc/cpuinfo
~~~

## Install

Extract this project inside the Debian range-controller VM, enter its directory, and run:

~~~bash
sudo ./scripts/bootstrap-controller.sh && sudo reboot
~~~

After the reboot:

~~~bash
./scripts/up.sh
~~~

The initial run downloads two Debian boxes and three Windows boxes. Depending on storage and Internet speed, allow approximately 45 to 120 minutes. The script starts the guests serially so the domain controller is ready before its member systems join the domain.

When provisioning finishes, expose the two intended entry ports:

~~~bash
sudo ./scripts/expose.sh
~~~

Display the range status:

~~~bash
./scripts/status.sh
~~~

From Kali, browse to:

~~~text
http://RANGE_CONTROLLER_IP:8080/
~~~

The SSH entry port is TCP 2222 on the same address. The player is not given credentials initially.

Give the player only the contents of the player directory. The provisioning source necessarily contains challenge internals and should remain on the range controller.

## Common operations

Stop the nested guests without deleting them:

~~~bash
vagrant halt
~~~

Start an already-provisioned range:

~~~bash
vagrant up --provider=libvirt --no-provision --no-parallel && sudo ./scripts/expose.sh
~~~

Run non-spoiling health checks:

~~~bash
./scripts/healthcheck.sh
~~~

Destroy the guests and generate fresh flags and passwords:

~~~bash
./scripts/reset.sh
~~~

## Isolation and safety

This project deliberately creates exploitable systems. Keep the outer range-controller VM on an isolated lab bridge or trusted private network.

- Do not bridge the inner corporate network directly to a physical interface.
- Do not publish libvirt management or Vagrant-forwarded Windows ports.
- Do not use real credentials or production data.
- Shut down the range when it is not being used.
- Treat the generated organizer secrets as sensitive challenge material.

The exposure script creates a dedicated nftables table and publishes only the web service and edge SSH service. It also blocks the high-numbered host ports that a Windows Vagrant box may create.

## Files

| Path | Purpose |
| --- | --- |
| Vagrantfile | Nested guest definitions and isolated networks |
| scripts/up.sh | Secret generation and ordered deployment |
| scripts/expose.sh | Controlled port publication on the range controller |
| scripts/healthcheck.sh | Non-spoiling service validation |
| scripts/reset.sh | Destructive range reset with confirmation |
| provision | Linux and Windows guest configuration |
| player | Spoiler-free player briefing and proxychains template |
| organizer | Organizer-only validation and solution material |
| .generated | Runtime secrets; created locally and excluded from source control |

## Base images

The project pins currently available libvirt boxes:

- debian/bookworm64 12.20260519.1
- gusztavvargadr/windows-server-2022-standard 2607.0.0
- gusztavvargadr/windows-11 2607.1.0

The public Vagrant registry is scheduled for retirement after 2026. Run the optional prefetch script while the registry remains available, and preserve the resulting local box cache if this range will be used long-term:

~~~bash
./scripts/prefetch-boxes.sh
~~~

The Vagrantfile also accepts boxes already installed through normal local Vagrant box management.
