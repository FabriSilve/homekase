#!/usr/bin/env bash
# shellcheck disable=SC2154  # GREEN/RED/RESET set by common.sh

# ---------------------------------------------------------------------------
# _status_collect_system
# Sets globals: _hn, _uptime, _load1, _load5, _load15, _ram_used_mb, _ram_total_mb
# ---------------------------------------------------------------------------
_status_collect_system() {
  _hn="$(hostname)"

  local up_sec
  up_sec="$(awk '{print int($1)}' /proc/uptime)"
  local days hours mins
  days=$(( up_sec / 86400 ))
  hours=$(( (up_sec % 86400) / 3600 ))
  mins=$(( (up_sec % 3600) / 60 ))
  if (( days > 0 )); then
    local ds hs
    ds="day$([[ "${days}" -ne 1 ]] && echo s || true)"
    hs="hour$([[ "${hours}" -ne 1 ]] && echo s || true)"
    _uptime="${days} ${ds}, ${hours} ${hs}"
  elif (( hours > 0 )); then
    local hs ms
    hs="hour$([[ "${hours}" -ne 1 ]] && echo s || true)"
    ms="min$([[ "${mins}" -ne 1 ]] && echo s || true)"
    _uptime="${hours} ${hs}, ${mins} ${ms}"
  else
    local ms
    ms="min$([[ "${mins}" -ne 1 ]] && echo s || true)"
    _uptime="${mins} ${ms}"
  fi

  read -r _load1 _load5 _load15 _ _ < /proc/loadavg

  local mem_line
  mem_line="$(free -m | awk 'NR==2 {print $2, $3}' || true)"
  _ram_total_mb="${mem_line%% *}"
  _ram_used_mb="${mem_line##* }"
}

# ---------------------------------------------------------------------------
# _status_collect_disk
# Populates parallel arrays: _disk_mount[] _disk_used[] _disk_total[] _disk_pct[]
# ---------------------------------------------------------------------------
_status_collect_disk() {
  _disk_mount=()
  _disk_used=()
  _disk_total=()
  _disk_pct=()

  local mounts=(/data /storage /backup)
  local m
  for m in "${mounts[@]}"; do
    [[ -d "${m}" ]] || continue
    local line
    line="$(df -h --output=size,used,pcent,target "${m}" 2>/dev/null | awk 'NR>1 {print $1, $2, $3, $4}' || true)"
    [[ -z "${line}" ]] && continue
    local total used pct target
    read -r total used pct target <<< "${line}"
    _disk_mount+=("${target}")
    _disk_used+=("${used}")
    _disk_total+=("${total}")
    _disk_pct+=("${pct}")
  done
}

# ---------------------------------------------------------------------------
# _status_collect_services
# Populates parallel arrays: _svc_name[] _svc_port[] _svc_running[] _svc_url[]
# ---------------------------------------------------------------------------
_status_collect_services() {
  _svc_name=()
  _svc_port=()
  _svc_running=()
  _svc_url=()

  local ts_hostname
  ts_hostname="$(config_get 'tailscale.hostname' 2>/dev/null || true)"

  local containers
  containers="$(docker ps -a \
    --filter "label=com.homekase.service" \
    --format '{{.Names}}' 2>/dev/null || true)"

  [[ -z "${containers}" ]] && return 0

  local cname
  while IFS= read -r cname; do
    [[ -z "${cname}" ]] && continue

    local svc port ts_flag running url
    svc="$(docker inspect "${cname}" --format '{{index .Config.Labels "com.homekase.service"}}' 2>/dev/null || true)"
    port="$(docker inspect "${cname}" --format '{{index .Config.Labels "com.homekase.port"}}' 2>/dev/null || true)"
    ts_flag="$(docker inspect "${cname}" --format '{{index .Config.Labels "com.homekase.tailscale"}}' 2>/dev/null || true)"
    running="$(docker inspect "${cname}" --format '{{.State.Running}}' 2>/dev/null || true)"

    url="null"
    if [[ "${ts_flag}" == "true" && -n "${ts_hostname}" && "${ts_hostname}" != "null" && -n "${port}" ]]; then
      url="https://${ts_hostname}:${port}"
    fi

    _svc_name+=("${svc}")
    _svc_port+=("${port}")
    _svc_running+=("${running}")
    _svc_url+=("${url}")
  done <<< "${containers}"
}

# ---------------------------------------------------------------------------
# cmd_status [--json]
# ---------------------------------------------------------------------------
cmd_status() {
  local json_mode=false
  local arg
  for arg in "$@"; do
    [[ "${arg}" == "--json" ]] && json_mode=true
  done

  _status_collect_system
  _status_collect_disk
  _status_collect_services

  if ${json_mode}; then
    local disk_json="[]"
    local i
    for i in "${!_disk_mount[@]}"; do
      disk_json="$(jq -n \
        --argjson arr   "${disk_json}" \
        --arg mount     "${_disk_mount[${i}]}" \
        --arg used      "${_disk_used[${i}]}" \
        --arg total     "${_disk_total[${i}]}" \
        --arg pct       "${_disk_pct[${i}]}" \
        '$arr + [{"mount":$mount,"used":$used,"total":$total,"percent":$pct}]')"
    done

    local svc_json="[]"
    for i in "${!_svc_name[@]}"; do
      local url_val running_bool port_int
      if [[ "${_svc_url[${i}]}" == "null" ]]; then
        url_val="null"
      else
        url_val="\"${_svc_url[${i}]}\""
      fi
      running_bool="false"
      [[ "${_svc_running[${i}]}" == "true" ]] && running_bool="true"
      port_int="${_svc_port[${i}]:-0}"
      svc_json="$(jq -n \
        --argjson arr    "${svc_json}" \
        --arg  name      "${_svc_name[${i}]}" \
        --argjson port   "${port_int:-0}" \
        --argjson run    "${running_bool}" \
        --argjson url    "${url_val}" \
        '$arr + [{"name":$name,"port":$port,"running":$run,"url":$url}]')"
    done

    jq -n \
      --arg  hostname    "${_hn}" \
      --arg  uptime      "${_uptime}" \
      --arg  load1       "${_load1}" \
      --arg  load5       "${_load5}" \
      --arg  load15      "${_load15}" \
      --argjson ram_used  "${_ram_used_mb:-0}" \
      --argjson ram_total "${_ram_total_mb:-0}" \
      --argjson disk      "${disk_json}" \
      --argjson services  "${svc_json}" \
      '{
        system: {
          hostname:  $hostname,
          uptime:    $uptime,
          load:      {"1m": $load1, "5m": $load5, "15m": $load15},
          ram:       {"used_mb": $ram_used, "total_mb": $ram_total}
        },
        disk:     $disk,
        services: $services
      }'
    return 0
  fi

  header "System"
  printf "  %-12s %s\n" "Hostname:"  "${_hn}"
  printf "  %-12s %s\n" "Uptime:"    "${_uptime}"
  printf "  %-12s %s / %s / %s\n" "Load:" "${_load1}" "${_load5}" "${_load15}"
  local ram_used_disp ram_total_disp
  if (( _ram_total_mb >= 1024 )); then
    ram_used_disp="$(awk "BEGIN{printf \"%.1fG\", ${_ram_used_mb}/1024}")"
    ram_total_disp="$(awk "BEGIN{printf \"%.1fG\", ${_ram_total_mb}/1024}")"
  else
    ram_used_disp="${_ram_used_mb}M"
    ram_total_disp="${_ram_total_mb}M"
  fi
  printf "  %-12s %s / %s used\n" "RAM:" "${ram_used_disp}" "${ram_total_disp}"

  if (( ${#_disk_mount[@]} > 0 )); then
    header "Disk"
    local i
    for i in "${!_disk_mount[@]}"; do
      printf "  %-12s %s used of %s (%s)\n" \
        "${_disk_mount[${i}]}" "${_disk_used[${i}]}" "${_disk_total[${i}]}" "${_disk_pct[${i}]}"
    done
  fi

  header "Services"
  if (( ${#_svc_name[@]} == 0 )); then
    printf "  (no homekase services running)\n"
  else
    local i
    for i in "${!_svc_name[@]}"; do
      local sym status_word url_part
      if [[ "${_svc_running[${i}]}" == "true" ]]; then
        sym="${GREEN}●${RESET}"
        status_word="running"
      else
        sym="${RED}○${RESET}"
        status_word="stopped"
      fi
      url_part=""
      [[ "${_svc_url[${i}]}" != "null" && -n "${_svc_url[${i}]}" ]] && url_part="   ${_svc_url[${i}]}"
      printf "  %-14s %b %-10s :%s%s\n" \
        "${_svc_name[${i}]}" "${sym}" "${status_word}" "${_svc_port[${i}]}" "${url_part}"
    done
  fi
  echo
}
