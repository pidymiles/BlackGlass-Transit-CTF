# Blackglass Transit — Player Briefing

Blackglass Systems has isolated a suspected compromise inside its segmented corporate environment. An exposed artifact relay is the only service reachable from your assessment network.

Your objective is to recover five flags and obtain administrative control of the BLACKGLASS.LAB domain.

## Starting point

The organizer will provide one IP address:

~~~text
http://TARGET:8080/
~~~

TCP 2222 is also in scope, but no username or credential is supplied.

## Rules

- Only the supplied range-controller IP and systems reached through the challenge are in scope.
- Do not attack the Proxmox host, libvirt management networks, or other LAN systems.
- Denial of service, destructive domain changes, and persistence outside the challenge are unnecessary.
- Flags use the format flag{...}.
- The intended path can be completed from Kali using standard web, SSH, Linux, Impacket, Samba, Kerberos, and BloodHound-compatible tooling.
- TCP connect scans are more reliable through SOCKS than SYN scans.

## Objectives

1. Establish a foothold on the exposed relay.
2. Discover and traverse the transit network.
3. Escalate on the internal Linux node.
4. Enter and enumerate the BLACKGLASS.LAB domain.
5. Follow the delegated-control path to domain administrator.

Expect to use more than one SSH tunnel or proxychains configuration. Record credentials, routes, hostnames, and object relationships as you progress.

