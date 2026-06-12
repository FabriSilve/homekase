#!/usr/bin/env bash

cmd_server_network() {
  header "Network Interfaces"
  ip -br addr show
  echo

  header "Default Gateway"
  ip route | grep default
  echo

  header "DNS Nameservers"
  grep nameserver /etc/resolv.conf
  echo
}
