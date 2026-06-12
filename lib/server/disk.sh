#!/usr/bin/env bash

cmd_server_disk() {
  header "Block Devices"
  lsblk -f
  echo

  header "Disk Usage"
  df -h
  echo

  local volumes=(/data /storage /backup)
  for vol in "${volumes[@]}"; do
    if mountpoint -q "${vol}" 2>/dev/null || [[ -d "${vol}" ]]; then
      header "Top 5 subdirs in ${vol}"
      du -sh "${vol}"/* 2>/dev/null | sort -rh | head -5 || true
      echo
    fi
  done
}
