# frozen_string_literal: true

VAGRANTFILE_API_VERSION = "2"
ROOT = File.expand_path(__dir__)
GENERATED = File.join(ROOT, ".generated")

required_secret_files = %w[edge.env jump.env dc.env file.env ws.env]
missing_secret_files = required_secret_files.reject do |name|
  File.file?(File.join(GENERATED, name))
end

unless missing_secret_files.empty?
  abort "Missing generated challenge state. Run ./scripts/up.sh first."
end

def isolated_network(machine, address, network_name)
  machine.vm.network "private_network",
                     ip: address,
                     libvirt__network_name: network_name,
                     libvirt__forward_mode: "none"
end

def read_env_file(path)
  File.readlines(path, chomp: true).each_with_object({}) do |line, values|
    next if line.empty? || line.start_with?("#")

    key, value = line.split("=", 2)
    values[key] = value
  end
end

def libvirt_profile(machine, memory_mb, cpus, management_name, management_cidr)
  machine.vm.provider :libvirt do |provider|
    provider.memory = memory_mb
    provider.cpus = cpus
    provider.cpu_mode = "host-passthrough"
    provider.management_network_name = management_name
    provider.management_network_address = management_cidr
    provider.management_network_mode = "none"
    provider.management_network_autostart = true
  end
end

def linux_guest(machine, hostname, management_name, management_cidr, memory_mb = 1024)
  machine.vm.box = "debian/bookworm64"
  machine.vm.box_version = "12.20260519.1"
  machine.vm.hostname = hostname
  machine.vm.boot_timeout = 900
  machine.ssh.keep_alive = true
  libvirt_profile(machine, memory_mb, 1, management_name, management_cidr)
end

def windows_guest(machine, hostname, box_name, box_version, management_name, management_cidr, memory_mb)
  machine.vm.box = box_name
  machine.vm.box_version = box_version
  machine.vm.hostname = hostname
  machine.vm.guest = :windows
  machine.vm.communicator = "winrm"
  machine.vm.boot_timeout = 1800
  machine.winrm.timeout = 1800
  machine.winrm.max_tries = 180
  machine.winrm.retry_delay = 5
  libvirt_profile(machine, memory_mb, 2, management_name, management_cidr)
end

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box_check_update = false
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.ssh.insert_key = false

  config.vm.define "edge01", primary: true do |edge|
    linux_guest(edge, "edge01", "bg-mgmt-edge", "192.168.121.0/29")
    isolated_network(edge, "172.22.10.10", "bg-outside")
    isolated_network(edge, "10.60.10.10", "bg-transit")
    if File.file?(File.join(GENERATED, "edge.ready"))
      edge.ssh.username = "vagrant"
      edge.ssh.private_key_path = File.join(GENERATED, "mgmt_ed25519")
    end
    edge.vm.provision "file",
                      source: ".generated/edge.env",
                      destination: "/tmp/bg-edge.env"
    edge.vm.provision "file",
                      source: ".generated/mgmt_ed25519.pub",
                      destination: "/tmp/bg-mgmt.pub"
    edge.vm.provision "file",
                      source: "provision/linux/edge_app.py",
                      destination: "/tmp/edge_app.py"
    edge.vm.provision "shell",
                      path: "provision/linux/edge.sh",
                      args: "/tmp/bg-edge.env",
                      privileged: true,
                      sensitive: true
  end

  config.vm.define "jump01" do |jump|
    linux_guest(jump, "jump01", "bg-mgmt-jump", "192.168.121.8/29")
    isolated_network(jump, "10.60.10.20", "bg-transit")
    isolated_network(jump, "10.60.20.20", "bg-corporate")
    if File.file?(File.join(GENERATED, "jump.ready"))
      jump.ssh.username = "vagrant"
      jump.ssh.private_key_path = File.join(GENERATED, "mgmt_ed25519")
    end
    jump.vm.provision "file",
                      source: ".generated/jump.env",
                      destination: "/tmp/bg-jump.env"
    jump.vm.provision "file",
                      source: ".generated/mgmt_ed25519.pub",
                      destination: "/tmp/bg-mgmt.pub"
    jump.vm.provision "file",
                      source: "provision/linux/net-audit.py",
                      destination: "/tmp/net-audit.py"
    jump.vm.provision "file",
                      source: "provision/linux/formatter.py",
                      destination: "/tmp/formatter.py"
    jump.vm.provision "shell",
                      path: "provision/linux/jump.sh",
                      args: "/tmp/bg-jump.env",
                      privileged: true,
                      sensitive: true
  end

  config.vm.define "dc01" do |dc|
    windows_guest(
      dc,
      "dc01",
      "gusztavvargadr/windows-server-2022-standard",
      "2607.0.0",
      "bg-mgmt-dc",
      "192.168.121.16/29",
      4096
    )
    isolated_network(dc, "10.60.20.10", "bg-corporate")
    if File.file?(File.join(GENERATED, "dc.ready"))
      dc_secrets = read_env_file(File.join(GENERATED, "dc.env"))
      dc.winrm.username = "BLACKGLASS\\vagrant"
      dc.winrm.password = dc_secrets.fetch("MGMT_PASSWORD")
    end
    dc.vm.provision "file",
                    source: ".generated/dc.env",
                    destination: "C:/Windows/Temp/bg-dc.env"
    dc.vm.provision "shell",
                    name: "dc-promote",
                    path: "provision/windows/dc-promote.ps1",
                    sensitive: true
    dc.vm.provision "shell",
                    name: "dc-reboot",
                    reboot: true
    dc.vm.provision "shell",
                    name: "dc-configure",
                    path: "provision/windows/dc-configure.ps1",
                    sensitive: true
  end

  config.vm.define "file01" do |file_server|
    windows_guest(
      file_server,
      "file01",
      "gusztavvargadr/windows-server-2022-standard",
      "2607.0.0",
      "bg-mgmt-file",
      "192.168.121.24/29",
      4096
    )
    isolated_network(file_server, "10.60.20.30", "bg-corporate")
    if File.file?(File.join(GENERATED, "file.ready"))
      file_secrets = read_env_file(File.join(GENERATED, "file.env"))
      file_server.winrm.username = ".\\vagrant"
      file_server.winrm.password = file_secrets.fetch("MGMT_PASSWORD")
    end
    file_server.vm.provision "file",
                             source: ".generated/file.env",
                             destination: "C:/Windows/Temp/bg-member.env"
    file_server.vm.provision "shell",
                             name: "domain-join",
                             path: "provision/windows/member-join.ps1",
                             args: "-ExpectedAddress 10.60.20.30",
                             sensitive: true
    file_server.vm.provision "shell",
                             name: "member-reboot",
                             reboot: true
    file_server.vm.provision "shell",
                             name: "file-configure",
                             path: "provision/windows/file-configure.ps1",
                             sensitive: true
  end

  config.vm.define "ws01" do |workstation|
    windows_guest(
      workstation,
      "ws01",
      "gusztavvargadr/windows-11",
      "2607.1.0",
      "bg-mgmt-ws",
      "192.168.121.32/29",
      4096
    )
    isolated_network(workstation, "10.60.20.40", "bg-corporate")
    if File.file?(File.join(GENERATED, "ws.ready"))
      ws_secrets = read_env_file(File.join(GENERATED, "ws.env"))
      workstation.winrm.username = ".\\vagrant"
      workstation.winrm.password = ws_secrets.fetch("MGMT_PASSWORD")
    end
    workstation.vm.provision "file",
                            source: ".generated/ws.env",
                            destination: "C:/Windows/Temp/bg-member.env"
    workstation.vm.provision "shell",
                            name: "domain-join",
                            path: "provision/windows/member-join.ps1",
                            args: "-ExpectedAddress 10.60.20.40",
                            sensitive: true
    workstation.vm.provision "shell",
                            name: "member-reboot",
                            reboot: true
    workstation.vm.provision "shell",
                            name: "workstation-configure",
                            path: "provision/windows/ws-configure.ps1",
                            sensitive: true
  end

  config.vm.post_up_message = <<~MESSAGE
    Blackglass Transit guests are running.
    Run sudo ./scripts/expose.sh and then ./scripts/healthcheck.sh.
    Give players only player/BRIEFING.md and the proxychains templates.
  MESSAGE
end
