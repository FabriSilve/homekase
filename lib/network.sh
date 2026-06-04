#!/bin/bash

get_preferred_interface() {
  local net_dir="${SYS_NET_DIR:-/sys/class/net}"

  # Prefer ethernet with cable connected
  for iface in "$net_dir"/e*; do
    [ -d "$iface" ] || continue
    [ "$(cat "$iface/carrier" 2>/dev/null)" = "1" ] || continue
    basename "$iface"
    return
  done

  # Fallback: WiFi that is up
  for iface in "$net_dir"/w*; do
    [ -d "$iface" ] || continue
    [ "$(cat "$iface/operstate" 2>/dev/null)" = "up" ] || continue
    basename "$iface"
    return
  done

  # Last resort: first non-loopback interface
  for iface in "$net_dir"/*; do
    local name
    name=$(basename "$iface")
    [ "$name" = "lo" ] && continue
    [ -d "$iface" ] || continue
    echo "$name"
    return
  done
}

show_router_instructions() {
  local interface="$1"
  local server_ip="$2"
  local gateway="$3"
  local mac="$4"
  local ip_only="${server_ip%%/*}"

  section "Router Configuration" \
"Configure your router admin panel with these settings to complete the network setup."

  echo -e "  ${BOLD}Router admin UI:${NC}   http://${gateway}"
  echo ""
  echo -e "  ${BOLD}1. DHCP Reservation${NC} (prevents IP conflicts if router restarts)"
  echo -e "     MAC address:   ${mac}"
  echo -e "     Assign IP:     ${ip_only}"
  echo ""
  echo -e "  ${BOLD}2. DNS Servers${NC} (for network-wide ad blocking via AdGuard)"
  echo -e "     Primary DNS:   ${ip_only}"
  echo -e "     Secondary DNS: 8.8.8.8  <- fallback if server is off"
  echo ""
  echo -e "  ${YELLOW}Note:${NC} secondary DNS bypasses AdGuard when server is unreachable."
  echo -e "  ${YELLOW}Note:${NC} all LAN devices must reconnect or renew DHCP to use new DNS."
}

setup_static_ip() {
  local netplan_file="${NETPLAN_FILE:-/etc/netplan/99-homekase-static.yaml}"
  local net_dir="${SYS_NET_DIR:-/sys/class/net}"

  local interface
  interface=$(get_preferred_interface)

  if [ -z "$interface" ]; then
    warn "No network interface detected — skipping static IP setup."
    return 0
  fi

  # Detect and report interface type
  if [ -d "$net_dir/$interface/wireless" ]; then
    warn "No ethernet with cable detected — using WiFi ($interface). Connect a cable for better stability."
  elif [ "$(cat "$net_dir/$interface/carrier" 2>/dev/null)" = "1" ]; then
    info "Ethernet interface detected: $interface (cable connected)"
  fi

  local current_ip gateway mac
  current_ip=$(ip -4 addr show "$interface" | awk '/inet /{print $2}')
  gateway=$(ip route | awk '/default/{print $3; exit}')
  mac=$(ip link show "$interface" | awk '/ether/{print $2}')

  # If Ethernet has no IP but WiFi does, keep the Ethernet interface but hint at the subnet
  local subnet_hint=""
  if [ -z "$current_ip" ]; then
    local gw_iface gw_ip
    gw_iface=$(ip route | awk '/default/{print $5; exit}')
    gw_ip=$(ip -4 addr show "$gw_iface" 2>/dev/null | awk '/inet /{print $2}')
    if [ -n "$gw_ip" ] && [ "$gw_iface" != "$interface" ]; then
      subnet_hint=$(echo "$gw_ip" | sed 's/\.[0-9]*\/\(.*\)/.X\/\1/')
    fi
  fi

  if [ -f "$netplan_file" ]; then
    info "Static IP already configured ($netplan_file)"
    show_router_instructions "$interface" "$current_ip" "$gateway" "$mac"
    return 0
  fi

  section "Static IP Configuration" \
"A static IP ensures your server always has the same address on your network.
Without it, the IP may change on router restart, breaking DNS and all services."

  info "Interface:   $interface"
  info "Current IP:  ${current_ip:-not assigned}"
  info "Gateway:     $gateway"
  info "MAC address: $mac"

  if [ -z "$current_ip" ]; then
    warn "Ethernet ($interface) has no IP yet — you're likely connected via WiFi."
    info "Your gateway is $gateway — use an IP in that subnet."
    local default_hint="${subnet_hint:-192.168.1.100/24}"
    local manual_ip
    manual_ip=$(prompt_input "Enter the static IP for $interface" "$default_hint")
    if [ -z "$manual_ip" ]; then
      warn "No IP provided — static IP skipped"
      show_router_instructions "$interface" "$current_ip" "$gateway" "$mac"
      return 0
    fi
    current_ip="$manual_ip"
  fi

  if ! prompt_yes_no "Configure static IP ${current_ip%%/*} on $interface?"; then
    warn "Static IP skipped — server IP may change and break services."
    show_router_instructions "$interface" "$current_ip" "$gateway" "$mac"
    return 0
  fi

  mkdir -p "$(dirname "$netplan_file")"
  cat > "$netplan_file" << NETPLAN
network:
  version: 2
  ethernets:
    ${interface}:
      dhcp4: no
      addresses:
        - ${current_ip}
      routes:
        - to: default
          via: ${gateway}
      nameservers:
        addresses:
          - 127.0.0.1
          - 8.8.8.8
NETPLAN

  chmod 600 "$netplan_file"
  netplan apply
  ok "Static IP ${current_ip%%/*} configured on $interface"
  show_router_instructions "$interface" "$current_ip" "$gateway" "$mac"
}
