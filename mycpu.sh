#!/usr/bin/env bash
# mycpu - Smart CPU freq & governor setup
# By Edoll
# Universal: Linux, Android (rooted), WSL
# Usage: mycpu [--install]

set -euo pipefail
IFS=$'\n\t'

# ─────────────────────────────
# Helper Functions
# ─────────────────────────────
ROOT_OK() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  elif command -v su >/dev/null 2>&1; then
    su -c "$(printf '%q ' "$@")"
  else
    echo -e "\e[31m[!] Root permission required.\e[0m"
    return 2
  fi
}

msg()  { printf '\e[1;34m[INFO]\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m[WARN]\e[0m %s\n' "$*"; }
err()  { printf '\e[1;31m[ERR]\e[0m %s\n' "$*"; }
pause() { read -rp "Press Enter to continue... "; }

# ─────────────────────────────
# CPU Detection
# ─────────────────────────────
CPUDIR="/sys/devices/system/cpu"
CPU_CORES=()
for p in "$CPUDIR"/cpu[0-9]*; do
  [ -d "$p" ] && [[ "$(basename "$p")" =~ ^cpu[0-9]+$ ]] && CPU_CORES+=("$(basename "$p")")
done

[ ${#CPU_CORES[@]} -eq 0 ] && { err "No CPU cores found in $CPUDIR"; exit 1; }

msg "CPU detected: ${CPU_CORES[*]}"

COMMON_GOVS=""
COMMON_MIN=0
COMMON_MAX=0
declare -A GOVS MINF MAXF

for cpu in "${CPU_CORES[@]}"; do
  base="$CPUDIR/$cpu/cpufreq"
  [ -d "$base" ] || continue

  if [ -f "$base/scaling_available_governors" ]; then
    govs=$(tr -s ' ' <"$base/scaling_available_governors")
    GOVS[$cpu]="$govs"
    if [ -z "$COMMON_GOVS" ]; then
      COMMON_GOVS="$govs"
    else
      tmp=""
      for g in $govs; do
        if echo "$COMMON_GOVS" | grep -qw "$g"; then
          tmp="$tmp $g"
        fi
      done
      COMMON_GOVS=$(echo "$tmp" | xargs)
    fi
  fi

  if [ -f "$base/cpuinfo_min_freq" ]; then
    MINF[$cpu]=$(<"$base/cpuinfo_min_freq")
    [ $COMMON_MIN -eq 0 ] && COMMON_MIN=${MINF[$cpu]}
    (( COMMON_MIN > ${MINF[$cpu]} )) && COMMON_MIN=${MINF[$cpu]}
  fi

  if [ -f "$base/cpuinfo_max_freq" ]; then
    MAXF[$cpu]=$(<"$base/cpuinfo_max_freq")
    [ $COMMON_MAX -eq 0 ] && COMMON_MAX=${MAXF[$cpu]}
    (( COMMON_MAX < ${MAXF[$cpu]} )) && COMMON_MAX=${MAXF[$cpu]}
  fi
done

msg "Common governors: ${COMMON_GOVS:-none}"
msg "Common frequency: ${COMMON_MIN}-${COMMON_MAX} kHz"
echo

# ─────────────────────────────
# Print Current CPU Info
# ─────────────────────────────
print_current() {
  echo -e "\n\e[1;34mCurrent CPU Status:\e[0m"
  for cpu in "${CPU_CORES[@]}"; do
    base="$CPUDIR/$cpu/cpufreq"
    gov=$(cat "$base/scaling_governor" 2>/dev/null || echo "-")
    cur=$(cat "$base/scaling_cur_freq" 2>/dev/null || echo "-")
    printf " %-6s  governor=%-12s  freq=%s kHz\n" "$cpu" "$gov" "$cur"
  done
}

# ─────────────────────────────
# Apply Settings
# ─────────────────────────────
apply_gov() {
  local gov="$1"
  msg "Applying governor '$gov'..."
  for cpu in "${CPU_CORES[@]}"; do
    p="$CPUDIR/$cpu/cpufreq/scaling_governor"
    ROOT_OK sh -c "echo $gov > $p" 2>/dev/null || warn "Failed to set $cpu"
  done
  msg "Done."
}

apply_freq() {
  local minf="$1" maxf="$2"
  msg "Applying frequency $minf - $maxf kHz..."
  for cpu in "${CPU_CORES[@]}"; do
    base="$CPUDIR/$cpu/cpufreq"
    ROOT_OK sh -c "echo $minf > $base/scaling_min_freq" 2>/dev/null || warn "Failed to set min"
    ROOT_OK sh -c "echo $maxf > $base/scaling_max_freq" 2>/dev/null || warn "Failed to set max"
  done
  msg "Done."
}

# ─────────────────────────────
# Persistence Setup
# ─────────────────────────────
make_persist() {
  local gov="$1" minf="$2" maxf="$3"
  cat <<EOF
#!/system/bin/sh
# Auto-generated mycpu persist $(date)
CPUDIR="/sys/devices/system/cpu"
for p in \$CPUDIR/cpu[0-9]*; do
  [ -d "\$p/cpufreq" ] || continue
  [ -n "$gov" ] && echo "$gov" > "\$p/cpufreq/scaling_governor" 2>/dev/null || true
  [ -n "$minf" ] && echo "$minf" > "\$p/cpufreq/scaling_min_freq" 2>/dev/null || true
  [ -n "$maxf" ] && echo "$maxf" > "\$p/cpufreq/scaling_max_freq" 2>/dev/null || true
done
EOF
}

persist_install() {
  local content="$1"
  local target=""
  if command -v systemctl &>/dev/null; then
    target="/etc/systemd/system/mycpu-persist.service"
    echo "$content" | ROOT_OK tee /usr/local/bin/mycpu-persist.sh >/dev/null
    ROOT_OK chmod +x /usr/local/bin/mycpu-persist.sh
    ROOT_OK tee "$target" >/dev/null <<EOF
[Unit]
Description=MyCPU Persistent Governor/Freq

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mycpu-persist.sh

[Install]
WantedBy=multi-user.target
EOF
    ROOT_OK systemctl daemon-reload
    ROOT_OK systemctl enable mycpu-persist.service
    msg "Systemd persistence created: $target"
    return
  fi

  if [ -d /data/adb/service.d ]; then
    target="/data/adb/service.d/mycpu-persist.sh"
    echo "$content" | ROOT_OK tee "$target" >/dev/null
    ROOT_OK chmod +x "$target"
    msg "Android (Magisk) persistence created: $target"
    return
  fi

  if [ -f /etc/rc.local ]; then
    echo "$content" | ROOT_OK tee /usr/local/bin/mycpu-persist.sh >/dev/null
    ROOT_OK chmod +x /usr/local/bin/mycpu-persist.sh
    grep -q "mycpu-persist.sh" /etc/rc.local || \
      ROOT_OK sh -c "sed -i '\$i /usr/local/bin/mycpu-persist.sh &\n' /etc/rc.local"
    msg "rc.local persistence created."
    return
  fi

  warn "No automatic persistence mechanism found."
}

# ─────────────────────────────
# Main Menu
# ─────────────────────────────
main_menu() {
  clear
  echo -e "\e[1;36m=== MyCPU — Smart CPU Governor/Freq Manager ===\e[0m"
  print_current
  echo
  echo " 1) Set Governor"
  echo " 2) Set Frequency"
  echo " 3) Set Governor + Frequency"
  echo " 0) Exit"
  echo
  read -rp "Select menu [0-3]: " opt
  case "$opt" in
    1)
      echo "Available governors: $COMMON_GOVS"
      read -rp "Select governor: " gov
      apply_gov "$gov"
      read -rp "Make it permanent (persist)? (y/n): " yn
      [[ $yn =~ ^[Yy]$ ]] && persist_install "$(make_persist "$gov" "" "")"
      ;;
    2)
      read -rp "Min freq (kHz) [${COMMON_MIN}]: " minf
      read -rp "Max freq (kHz) [${COMMON_MAX}]: " maxf
      minf=${minf:-$COMMON_MIN}
      maxf=${maxf:-$COMMON_MAX}
      apply_freq "$minf" "$maxf"
      read -rp "Make it permanent (persist)? (y/n): " yn
      [[ $yn =~ ^[Yy]$ ]] && persist_install "$(make_persist "" "$minf" "$maxf")"
      ;;
    3)
      read -rp "Governor: " gov
      read -rp "Min freq (kHz) [${COMMON_MIN}]: " minf
      read -rp "Max freq (kHz) [${COMMON_MAX}]: " maxf
      apply_gov "$gov"
      apply_freq "${minf:-$COMMON_MIN}" "${maxf:-$COMMON_MAX}"
      read -rp "Make it permanent (persist)? (y/n): " yn
      [[ $yn =~ ^[Yy]$ ]] && persist_install "$(make_persist "$gov" "$minf" "$maxf")"
      ;;
    0) exit 0 ;;
    *) warn "Invalid choice" ;;
  esac
  pause
  main_menu
}

# ─────────────────────────────
# Install to PATH
# ─────────────────────────────
if [ "${1:-}" = "--install" ]; then
  target="/usr/local/bin/mycpu"
  ROOT_OK cp "$0" "$target"
  ROOT_OK chmod +x "$target"
  msg "Installed at $target — run with 'mycpu'"
  exit 0
fi

# ─────────────────────────────
# Start Interactive
# ─────────────────────────────
main_menu  [ -d "$p" ] && [[ "$(basename "$p")" =~ ^cpu[0-9]+$ ]] && CPU_CORES+=("$(basename "$p")")
done

[ ${#CPU_CORES[@]} -eq 0 ] && { err "Tidak menemukan CPU cores di $CPUDIR"; exit 1; }

msg "CPU terdeteksi: ${CPU_CORES[*]}"

COMMON_GOVS=""
COMMON_MIN=0
COMMON_MAX=0
declare -A GOVS MINF MAXF

for cpu in "${CPU_CORES[@]}"; do
  base="$CPUDIR/$cpu/cpufreq"
  [ -d "$base" ] || continue

  if [ -f "$base/scaling_available_governors" ]; then
    govs=$(tr -s ' ' <"$base/scaling_available_governors")
    GOVS[$cpu]="$govs"
    if [ -z "$COMMON_GOVS" ]; then
      COMMON_GOVS="$govs"
    else
      tmp=""
      for g in $govs; do
        if echo "$COMMON_GOVS" | grep -qw "$g"; then
          tmp="$tmp $g"
        fi
      done
      COMMON_GOVS=$(echo "$tmp" | xargs)
    fi
  fi

  if [ -f "$base/cpuinfo_min_freq" ]; then
    MINF[$cpu]=$(<"$base/cpuinfo_min_freq")
    [ $COMMON_MIN -eq 0 ] && COMMON_MIN=${MINF[$cpu]}
    (( COMMON_MIN > ${MINF[$cpu]} )) && COMMON_MIN=${MINF[$cpu]}
  fi

  if [ -f "$base/cpuinfo_max_freq" ]; then
    MAXF[$cpu]=$(<"$base/cpuinfo_max_freq")
    [ $COMMON_MAX -eq 0 ] && COMMON_MAX=${MAXF[$cpu]}
    (( COMMON_MAX < ${MAXF[$cpu]} )) && COMMON_MAX=${MAXF[$cpu]}
  fi
done

msg "Governor umum: ${COMMON_GOVS:-tidak ada}"
msg "Frekuensi umum: ${COMMON_MIN}-${COMMON_MAX} kHz"
echo

# ─────────────────────────────
# Print Current CPU Info
# ─────────────────────────────
print_current() {
  echo -e "\n\e[1;34mStatus CPU Saat Ini:\e[0m"
  for cpu in "${CPU_CORES[@]}"; do
    base="$CPUDIR/$cpu/cpufreq"
    gov=$(cat "$base/scaling_governor" 2>/dev/null || echo "-")
    cur=$(cat "$base/scaling_cur_freq" 2>/dev/null || echo "-")
    printf " %-6s  governor=%-12s  freq=%s kHz\n" "$cpu" "$gov" "$cur"
  done
}

# ─────────────────────────────
# Apply Settings
# ─────────────────────────────
apply_gov() {
  local gov="$1"
  msg "Menerapkan governor '$gov'..."
  for cpu in "${CPU_CORES[@]}"; do
    p="$CPUDIR/$cpu/cpufreq/scaling_governor"
    ROOT_OK sh -c "echo $gov > $p" 2>/dev/null || warn "Gagal set $cpu"
  done
  msg "Selesai."
}

apply_freq() {
  local minf="$1" maxf="$2"
  msg "Menerapkan frekuensi $minf - $maxf kHz..."
  for cpu in "${CPU_CORES[@]}"; do
    base="$CPUDIR/$cpu/cpufreq"
    ROOT_OK sh -c "echo $minf > $base/scaling_min_freq" 2>/dev/null || warn "Gagal set min"
    ROOT_OK sh -c "echo $maxf > $base/scaling_max_freq" 2>/dev/null || warn "Gagal set max"
  done
  msg "Selesai."
}

# ─────────────────────────────
# Persistence Setup
# ─────────────────────────────
make_persist() {
  local gov="$1" minf="$2" maxf="$3"
  cat <<EOF
#!/system/bin/sh
# Auto-generated mycpu persist $(date)
CPUDIR="/sys/devices/system/cpu"
for p in \$CPUDIR/cpu[0-9]*; do
  [ -d "\$p/cpufreq" ] || continue
  [ -n "$gov" ] && echo "$gov" > "\$p/cpufreq/scaling_governor" 2>/dev/null || true
  [ -n "$minf" ] && echo "$minf" > "\$p/cpufreq/scaling_min_freq" 2>/dev/null || true
  [ -n "$maxf" ] && echo "$maxf" > "\$p/cpufreq/scaling_max_freq" 2>/dev/null || true
done
EOF
}

persist_install() {
  local content="$1"
  local target=""
  if command -v systemctl &>/dev/null; then
    target="/etc/systemd/system/mycpu-persist.service"
    echo "$content" | ROOT_OK tee /usr/local/bin/mycpu-persist.sh >/dev/null
    ROOT_OK chmod +x /usr/local/bin/mycpu-persist.sh
    ROOT_OK tee "$target" >/dev/null <<EOF
[Unit]
Description=MyCPU Persistent Governor/Freq

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mycpu-persist.sh

[Install]
WantedBy=multi-user.target
EOF
    ROOT_OK systemctl daemon-reload
    ROOT_OK systemctl enable mycpu-persist.service
    msg "Persisten systemd dibuat: $target"
    return
  fi

  if [ -d /data/adb/service.d ]; then
    target="/data/adb/service.d/mycpu-persist.sh"
    echo "$content" | ROOT_OK tee "$target" >/dev/null
    ROOT_OK chmod +x "$target"
    msg "Persisten Android (Magisk) dibuat: $target"
    return
  fi

  if [ -f /etc/rc.local ]; then
    echo "$content" | ROOT_OK tee /usr/local/bin/mycpu-persist.sh >/dev/null
    ROOT_OK chmod +x /usr/local/bin/mycpu-persist.sh
    grep -q "mycpu-persist.sh" /etc/rc.local || \
      ROOT_OK sh -c "sed -i '\$i /usr/local/bin/mycpu-persist.sh &\n' /etc/rc.local"
    msg "Persisten rc.local dibuat."
    return
  fi

  warn "Tidak menemukan mekanisme persistensi otomatis."
}

# ─────────────────────────────
# Main Menu
# ─────────────────────────────
main_menu() {
  clear
  echo -e "\e[1;36m=== MyCPU — Smart CPU Governor/Freq Manager ===\e[0m"
  print_current
  echo
  echo " 1) Set Governor"
  echo " 2) Set Frequency"
  echo " 3) Set Governor + Frequency"
  echo " 0) Keluar"
  echo
  read -rp "Pilih menu [0-3]: " opt
  case "$opt" in
    1)
      echo "Governors tersedia: $COMMON_GOVS"
      read -rp "Pilih governor: " gov
      apply_gov "$gov"
      read -rp "Jadikan permanen (persist)? (y/n): " yn
      [[ $yn =~ ^[Yy]$ ]] && persist_install "$(make_persist "$gov" "" "")"
      ;;
    2)
      read -rp "Min freq (kHz) [${COMMON_MIN}]: " minf
      read -rp "Max freq (kHz) [${COMMON_MAX}]: " maxf
      minf=${minf:-$COMMON_MIN}
      maxf=${maxf:-$COMMON_MAX}
      apply_freq "$minf" "$maxf"
      read -rp "Jadikan permanen (persist)? (y/n): " yn
      [[ $yn =~ ^[Yy]$ ]] && persist_install "$(make_persist "" "$minf" "$maxf")"
      ;;
    3)
      read -rp "Governor: " gov
      read -rp "Min freq (kHz) [${COMMON_MIN}]: " minf
      read -rp "Max freq (kHz) [${COMMON_MAX}]: " maxf
      apply_gov "$gov"
      apply_freq "${minf:-$COMMON_MIN}" "${maxf:-$COMMON_MAX}"
      read -rp "Jadikan permanen (persist)? (y/n): " yn
      [[ $yn =~ ^[Yy]$ ]] && persist_install "$(make_persist "$gov" "$minf" "$maxf")"
      ;;
    0) exit 0 ;;
    *) warn "Pilihan tidak valid" ;;
  esac
  pause
  main_menu
}

# ─────────────────────────────
# Install to PATH
# ─────────────────────────────
if [ "${1:-}" = "--install" ]; then
  target="/usr/local/bin/mycpu"
  ROOT_OK cp "$0" "$target"
  ROOT_OK chmod +x "$target"
  msg "Terinstall di $target — jalankan dengan 'mycpu'"
  exit 0
fi

# ─────────────────────────────
# Start Interactive
# ─────────────────────────────
main_menu    if [ -z "$COMMON_GOVS" ]; then
      COMMON_GOVS="$govs"
    else
      tmp=""
      for g in $govs; do
        if echo "$COMMON_GOVS" | grep -qw "$g"; then
          tmp="$tmp $g"
        fi
      done
      COMMON_GOVS=$(echo "$tmp" | xargs)
    fi
  fi

  if [ -f "$base/cpuinfo_min_freq" ]; then
    MINF[$cpu]=$(<"$base/cpuinfo_min_freq")
    [ $COMMON_MIN -eq 0 ] && COMMON_MIN=${MINF[$cpu]}
    (( COMMON_MIN > ${MINF[$cpu]} )) && COMMON_MIN=${MINF[$cpu]}
  fi

  if [ -f "$base/cpuinfo_max_freq" ]; then
    MAXF[$cpu]=$(<"$base/cpuinfo_max_freq")
    [ $COMMON_MAX -eq 0 ] && COMMON_MAX=${MAXF[$cpu]}
    (( COMMON_MAX < ${MAXF[$cpu]} )) && COMMON_MAX=${MAXF[$cpu]}
  fi
done

msg "Common governors: ${COMMON_GOVS:-none}"
msg "Common frequency: ${COMMON_MIN}-${COMMON_MAX} kHz"
echo

# ─────────────────────────────
# Print Current CPU Info
# ─────────────────────────────
print_current() {
  echo -e "\n\e[1;34mCurrent CPU Status:\e[0m"
  for cpu in "${CPU_CORES[@]}"; do
    base="$CPUDIR/$cpu/cpufreq"
    gov=$(cat "$base/scaling_governor" 2>/dev/null || echo "-")
    cur=$(cat "$base/scaling_cur_freq" 2>/dev/null || echo "-")
    printf " %-6s  governor=%-12s  freq=%s kHz\n" "$cpu" "$gov" "$cur"
  done
}

# ─────────────────────────────
# Apply Settings
# ─────────────────────────────
apply_gov() {
  local gov="$1"
  msg "Applying governor '$gov'..."
  for cpu in "${CPU_CORES[@]}"; do
    p="$CPUDIR/$cpu/cpufreq/scaling_governor"
    ROOT_OK sh -c "echo $gov > $p" 2>/dev/null || warn "Failed to set $cpu"
  done
  msg "Done."
}

apply_freq() {
  local minf="$1" maxf="$2"
  msg "Applying frequency $minf - $maxf kHz..."
  for cpu in "${CPU_CORES[@]}"; do
    base="$CPUDIR/$cpu/cpufreq"
    ROOT_OK sh -c "echo $minf > $base/scaling_min_freq" 2>/dev/null || warn "Failed to set min"
    ROOT_OK sh -c "echo $maxf > $base/scaling_max_freq" 2>/dev/null || warn "Failed to set max"
  done
  msg "Done."
}

# ─────────────────────────────
# Persistence Setup
# ─────────────────────────────
make_persist() {
  local gov="$1" minf="$2" maxf="$3"
  cat <<EOF
#!/system/bin/sh
# Auto-generated mycpu persist $(date)
CPUDIR="/sys/devices/system/cpu"
for p in \$CPUDIR/cpu[0-9]*; do
  [ -d "\$p/cpufreq" ] || continue
  [ -n "$gov" ] && echo "$gov" > "\$p/cpufreq/scaling_governor" 2>/dev/null || true
  [ -n "$minf" ] && echo "$minf" > "\$p/cpufreq/scaling_min_freq" 2>/dev/null || true
  [ -n "$maxf" ] && echo "$maxf" > "\$p/cpufreq/scaling_max_freq" 2>/dev/null || true
done
EOF
}

persist_install() {
  local content="$1"
  local target=""
  if command -v systemctl &>/dev/null; then
    target="/etc/systemd/system/mycpu-persist.service"
    echo "$content" | ROOT_OK tee /usr/local/bin/mycpu-persist.sh >/dev/null
    ROOT_OK chmod +x /usr/local/bin/mycpu-persist.sh
    ROOT_OK tee "$target" >/dev/null <<EOF
[Unit]
Description=MyCPU Persistent Governor/Freq

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mycpu-persist.sh

[Install]
WantedBy=multi-user.target
EOF
    ROOT_OK systemctl daemon-reload
    ROOT_OK systemctl enable mycpu-persist.service
    msg "Systemd persistence created: $target"
    return
  fi

  if [ -d /data/adb/service.d ]; then
    target="/data/adb/service.d/mycpu-persist.sh"
    echo "$content" | ROOT_OK tee "$target" >/dev/null
    ROOT_OK chmod +x "$target"
    msg "Android (Magisk) persistence created: $target"
    return
  fi

  if [ -f /etc/rc.local ]; then
    echo "$content" | ROOT_OK tee /usr/local/bin/mycpu-persist.sh >/dev/null
    ROOT_OK chmod +x /usr/local/bin/mycpu-persist.sh
    grep -q "mycpu-persist.sh" /etc/rc.local || \
      ROOT_OK sh -c "sed -i '\$i /usr/local/bin/mycpu-persist.sh &\n' /etc/rc.local"
    msg "rc.local persistence created."
    return
  fi

  warn "No automatic persistence mechanism found."
}

# ─────────────────────────────
# Main Menu
# ─────────────────────────────
main_menu() {
  clear
  echo -e "\e[1;36m=== MyCPU — Smart CPU Governor/Freq Manager ===\e[0m"
  print_current
  echo
  echo " 1) Set Governor"
  echo " 2) Set Frequency"
  echo " 3) Set Governor + Frequency"
  echo " 0) Exit"
  echo
  read -rp "Select menu [0-3]: " opt
  case "$opt" in
    1)
      echo "Available governors: $COMMON_GOVS"
      read -rp "Select governor: " gov
      apply_gov "$gov"
      read -rp "Make it permanent (persist)? (y/n): " yn
      [[ $yn =~ ^[Yy]$ ]] && persist_install "$(make_persist "$gov" "" "")"
      ;;
    2)
      read -rp "Min freq (kHz) [${COMMON_MIN}]: " minf
      read -rp "Max freq (kHz) [${COMMON_MAX}]: " maxf
      minf=${minf:-$COMMON_MIN}
      maxf=${maxf:-$COMMON_MAX}
      apply_freq "$minf" "$maxf"
      read -rp "Make it permanent (persist)? (y/n): " yn
      [[ $yn =~ ^[Yy]$ ]] && persist_install "$(make_persist "" "$minf" "$maxf")"
      ;;
    3)
      read -rp "Governor: " gov
      read -rp "Min freq (kHz) [${COMMON_MIN}]: " minf
      read -rp "Max freq (kHz) [${COMMON_MAX}]: " maxf
      apply_gov "$gov"
      apply_freq "${minf:-$COMMON_MIN}" "${maxf:-$COMMON_MAX}"
      read -rp "Make it permanent (persist)? (y/n): " yn
      [[ $yn =~ ^[Yy]$ ]] && persist_install "$(make_persist "$gov" "$minf" "$maxf")"
      ;;
    0) exit 0 ;;
    *) warn "Invalid choice" ;;
  esac
  pause
  main_menu
}

# ─────────────────────────────
# Install to PATH
# ─────────────────────────────
if [ "${1:-}" = "--install" ]; then
  target="/usr/local/bin/mycpu"
  ROOT_OK cp "$0" "$target"
  ROOT_OK chmod +x "$target"
  msg "Installed at $target — run with 'mycpu'"
  exit 0
fi

# ─────────────────────────────
# Start Interactive
# ─────────────────────────────
main_menu
