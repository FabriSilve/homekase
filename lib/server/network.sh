#!/usr/bin/env bash

cmd_server_network() {
  header "Network Interfaces"
  ip -br addr show
  echo

  header "Default Gateway"
  ip route show | grep default || true
  echo

  header "DNS Nameservers"
  grep nameserver /etc/resolv.conf
  echo
}
