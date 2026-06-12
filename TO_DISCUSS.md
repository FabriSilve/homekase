# TO_DISCUSS

---

## Plan 2 — Server Commands

**1. UFW ports** ✅ DECIDED
SSH + tailscale0 only on initial setup. `homekase add <service>` will detect if UFW is running and open the ports it needs. 80/443 not opened by default.
NEW: top-level `homekase open <service>` / `homekase close <service>` commands — expose/hide a service's port on the LAN for testing.

**2. Static IP — DNS** ✅ DECIDED
8.8.8.8.

**3. `homekase server docker` standalone** ✅ DECIDED
Runs before `init`. All subcommands idempotent.

---

## Plan 3 — Init Command

**4. gum bootstrap** ✅ DECIDED
Install gum silently first, then show interactive list. Already implemented.

**5. nvim symlink scope** ✅ DECIDED
Invoking user + root only.

---

## Plan 4 — Services

**6. Port conflict detection** ✅ DECIDED
`next_available_port` checks `homekase.yml` + `ss -tlnp`. Already implemented.

**7. Tailscale Serve** ✅ DECIDED
Direct Tailscale IP:port per service. No path-based routing.

**8. AI model thresholds** ✅ DECIDED
≥12G → qwen2.5:14b, ≥7G → qwen2.5:7b, ≥4G → qwen2.5:3b.

---

## Plan 5 — Status + Backup

**9. `homekase status` permissions** ✅ DECIDED
No root required. User must be in docker group.

**10. Backup path** ✅ DECIDED
`/backup`.

**11. Postgres services** ✅ DECIDED
Only Immich uses postgres. Vikunja uses sqlite. Already in backup labels.

---

## New — Pending Implementation

**12. `homekase open <service>` / `homekase close <service>`**
Top-level commands. Read `com.homekase.port` Docker label for the named service, then call `ufw allow/deny <port>/tcp` if UFW is active.
Complement to `homekase server firewall open <port>` (raw port). This one takes a service name.
