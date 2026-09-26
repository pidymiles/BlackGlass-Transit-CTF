#!/usr/bin/env python3
import argparse
import ipaddress
import socket
import sys

sys.path.insert(0, "/opt/blackglass/netaudit/plugins")
from formatter import format_report


def main():
    parser = argparse.ArgumentParser(description="Blackglass route audit")
    parser.add_argument("--target", required=True)
    args = parser.parse_args()

    target = str(ipaddress.ip_address(args.target))
    status = "closed"

    try:
        with socket.create_connection((target, 445), timeout=2):
            status = "reachable"
    except OSError:
        status = "unreachable"

    print(format_report(target, status))


if __name__ == "__main__":
    main()

