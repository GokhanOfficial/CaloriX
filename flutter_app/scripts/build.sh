#!/usr/bin/env bash
#
# CaloriX — geliştirme/üretim yardımcısı (interaktif menü).
#
# Build (debug/release APK, AAB, web) + Run (flutter run — cihaz/emülatör/
# tarayıcı seçimi) + cihaza kur/çalıştır/flutter clean. Tek menüde toplar.
#
# Kullanım:
#   ./scripts/build.sh                # ana menü
#   ./scripts/build.sh debug          # menüsüz: debug APK üret
#   ./scripts/build.sh release        # menüsüz: imzalı release APK üret
#   ./scripts/build.sh aab            # menüsüz: App Bundle (Play Console)
#   ./scripts/build.sh web            # menüsüz: web release
#   ./scripts/build.sh clean          # menüsüz: flutter clean
#   ./scripts/build.sh run            # menüsüz: flutter run (cihaz seç)
#   ./scripts/build.sh --help         # yardım
#
# Release imzalaması `android/key.properties` + `android/app/calorix-upload.jks`
# varsa `build.gradle.kts` tarafından otomatik uygulanır — ek bayrak gerekmez.
# CI'da `cp .env.example .env` yapılmalı, yoksa asset-bundle derleme patlar
# ([[env-config]]). Bu script yerel .env varlığını kontrol eder.

set -euo pipefail

# --- konum ----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ ! -f "$APP_DIR/pubspec.yaml" ]]; then
  echo "HATA: pubspec.yaml bulunamadı: $APP_DIR" >&2
  echo "       Script flutter_app/scripts/ altında olmalı." >&2
  exit 1
fi

cd "$APP_DIR"

# --- renkler (TTY / NO_COLOR saygılı) -------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'; C_DIM=$'\033[2m'
else
  C_RESET=''; C_BOLD=''; C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_DIM=''
fi

info()  { printf '%sℹ%s  %s\n' "$C_CYAN"   "$C_RESET" "$*"; }
ok()    { printf '%s✓%s  %s\n' "$C_GREEN"  "$C_RESET" "$*"; }
warn()  { printf '%s⚠%s  %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()   { printf '%s✗%s  %s\n' "$C_RED"     "$C_RESET" "$*" >&2; }
hdr()   { printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
dim()   { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }

# --- yardımcılar ----------------------------------------------------------
human_size() {
  local bytes=$1
  if   (( bytes >= 1073741824 )); then awk -v b="$bytes" 'BEGIN{printf "%.1f GB", b/1073741824}'
  elif (( bytes >= 1048576     )); then awk -v b="$bytes" 'BEGIN{printf "%.1f MB", b/1048576}'
  elif (( bytes >= 1024         )); then awk -v b="$bytes" 'BEGIN{printf "%.1f KB", b/1024}'
  else printf '%d B' "$bytes"
  fi
}

flutter_cmd() {
  if command -v flutter >/dev/null 2>&1; then echo flutter
  elif [[ -x "$HOME/fvm/default/bin/flutter" ]]; then echo "$HOME/fvm/default/bin/flutter"
  else echo ""
  fi
}

ADB="${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools/adb"
[[ -x "$ADB" ]] || ADB="adb"
command -v "$ADB" >/dev/null 2>&1 || ADB=""

# --- cihaz/emülatör keşfi -------------------------------------------------
# Çıktı: "<id>\t<label>" satırları (label = cihaz/emülatör adı).
list_android_targets() {
  local flutter; flutter="$(flutter_cmd)"
  [[ -z "$flutter" ]] && return 0
  # flutter devices --machine JSON'u en güvenilir kaynak.
  "$flutter" devices --machine 2>/dev/null \
    | sed -n '/^[[:space:]]*\[/,/^[[:space:]]*]/p' \
    | python3 -c '
import sys, json
try:
    devs = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for d in devs:
    p = d.get("targetPlatform","")
    if p.startswith("android"):
        mid = d.get("id") or d.get("emulatorId") or ""
        name = d.get("name","?")
        print(f"{mid}\t{name}\tandroid")
' 2>/dev/null
}

# adb ile bağlı cihazları (boş flutter id'leri olan fiziksel cihazlar) ekle.
adb_devices() {
  [[ -n "$ADB" ]] || return 0
  "$ADB" devices -l 2>/dev/null | awk '/device$/ && $1!="*"{print $1}'
}

# --- web tarayıcı keşfi ---------------------------------------------------
find_browsers() {
  local found=()
  local desc; local exe
  # (komut, insan adı) — sıralama önemli: en çok tercih edilen önce.
  local pairs=(
    "google-chrome-stable|Chrome (stable)"
    "google-chrome|Chrome"
    "chromium|Chromium"
    "microsoft-edge-stable|Edge (stable)"
    "microsoft-edge|Edge"
    "brave-browser|Brave"
    "firefox|Firefox"
    "webkitgtk-driver|WebKit (flutter'dan açılır)"
  )
  for pair in "${pairs[@]}"; do
    exe="${pair%%|*}"; desc="${pair##*|}"
    command -v "$exe" >/dev/null 2>&1 && found+=("$exe|$desc")
  done
  printf '%s\n' "${found[@]}"
}

# --- genel select (0..N-1, 0="geri/çıkış") --------------------------------
select_choice() {
  local -n _opts=$1 _out=$2
  local i=0 item
  for item in "${_opts[@]}"; do
    printf '  %d) %s\n' "$i" "$item"; i=$((i+1))
  done
  local n
  read -rp "Seçim> " n
  if [[ "$n" =~ ^[0-9]+$ ]] && (( 0 <= n && n < ${#_opts[@]} )); then
    _out=$n; return 0
  fi
  err "Geçersiz seçim: '$n'"; _out=-1; return 1
}

# --- ön kontrol -----------------------------------------------------------
preflight() {
  hdr "${C_CYAN}CaloriX — Geliştirme/Üretim Yardımcısı${C_RESET}"
  local fl; fl="$(flutter_cmd)"
  if [[ -z "$fl" ]]; then err "flutter bulunamadı (PATH'te değil)."; exit 1; fi
  local fver; fver="$("$fl" --version 2>/dev/null | head -1)"
  printf '  %sFlutter:%s %s\n' "$C_DIM" "$C_RESET" "$fver"
  printf '  %sUygulama:%s %s\n' "$C_DIM" "$C_RESET" "$APP_DIR"
  if [[ -f "$APP_DIR/.env" ]]; then
    ok ".env asset mevcut ($(human_size "$(wc -c <"$APP_DIR/.env" | tr -d ' ')"))"
  else
    warn ".env asset YOK — release build asset-bundle'da patlayabilir."
    warn "CI ise: cp .env.example .env  | yerelse: Supabase URL+anon key içeren .env üret."
  fi
  if [[ -f "$APP_DIR/android/key.properties" && -f "$APP_DIR/android/app/calorix-upload.jks" ]]; then
    ok "Keystore + key.properties mevcut → release imzalı derlenir."
  else
    warn "Keystore/key.properties yok → release DEBUG anahtarıyla imzalanır (dağıtıma uygun değil)."
  fi
  echo
}

# --- derleme fonksiyonları ------------------------------------------------
build_apk() {
  local mode=$1  # debug | release
  hdr "flutter build apk --$mode"
  flutter build apk --"$mode"
  local out="$APP_DIR/build/app/outputs/flutter-apk/app-$mode.apk"
  [[ -f "$out" ]] || { err "APK üretilmedi: $out"; return 1; }
  report_apk "$out" "$mode"
  post_apk_menu "$out" "$mode"
}

build_aab() {
  hdr "flutter build appbundle --release"
  flutter build appbundle --release
  local out="$APP_DIR/build/app/outputs/flutter-release/app-release.aab"
  [[ -f "$out" ]] || { err "AAB üretilmedi: $out"; return 1; }
  ok "App Bundle hazır:"
  printf '  %sYol:%s    %s\n' "$C_DIM" "$C_RESET" "$out"
  printf '  %sBoyut:%s   %s\n' "$C_DIM" "$C_RESET" "$(human_size "$(wc -c <"$out" | tr -d ' ')")"
  dim "Play Console → Üretim → Bundle keşfet (.aab). bundletool ile cihaza kurulabilir."
}

build_web() {
  hdr "flutter build web --release"
  flutter build web --release
  local out="$APP_DIR/build/web"
  [[ -d "$out" ]] || { err "Web çıktısı yok: $out"; return 1; }
  ok "Web release hazır:"
  printf '  %sYol:%s %s\n' "$C_DIM" "$C_RESET" "$out"
  dim "Statik hostinge (Vercel/Netlify) yükle. Yerel önizleme: dart run dhttpd --path build/web"
}

# --- derleme sonrası rapor (APK) ------------------------------------------
report_apk() {
  local out=$1 mode=$2
  local size; size="$(wc -c <"$out" | tr -d ' ')"
  ok "APK hazır ($mode):"
  printf '  %sYol:%s    %s\n' "$C_DIM" "$C_RESET" "$out"
  printf '  %sBoyut:%s   %s\n' "$C_DIM" "$C_RESET" "$(human_size "$size")"

  if [[ "$mode" == "release" ]]; then
    local apksigner="" aapt2="" bt
    command -v apksigner >/dev/null 2>&1 && apksigner=apksigner
    [[ -z "$apksigner" ]] && { bt="$(ls -d "$HOME/Android/Sdk/build-tools/"* 2>/dev/null | sort -V | tail -1)"; [[ -n "$bt" && -x "$bt/apksigner" ]] && apksigner="$bt/apksigner"; }
    if [[ -n "$apksigner" ]]; then
      if "$apksigner" verify --print-certs "$out" >/dev/null 2>&1; then
        ok "İmza doğrulandı (apksigner: geçerli)."
      else
        warn "apksigner doğrulayamadı — imza şeması sorunlu olabilir."
      fi
    else
      dim "apksigner bulunamadı — imza doğrulaması atlandı."
    fi

    command -v aapt2 >/dev/null 2>&1 && aapt2=aapt2
    [[ -z "$aapt2" ]] && { bt="$(ls -d "$HOME/Android/Sdk/build-tools/"* 2>/dev/null | sort -V | tail -1)"; [[ -n "$bt" && -x "$bt/aapt2" ]] && aapt2="$bt/aapt2"; }
    if [[ -n "$aapt2" ]]; then
      local badging; badging="$("$aapt2" dump badging "$out" 2>/dev/null)"
      local pkg vc vn ts
      pkg="$(grep -oP "^package: name='\K[^']+" <<<"$badging" | head -1)"
      vc="$(grep  -oP "versionCode='\K[^']+"     <<<"$badging" | head -1)"
      vn="$(grep  -oP "versionName='\K[^']+"     <<<"$badging" | head -1)"
      ts="$(grep  -oP "targetSdkVersion:'\K[^']+" <<<"$badging" | head -1)"
      printf '  %sPaket:%s  %s\n' "$C_DIM" "$C_RESET" "${pkg:-?}"
      printf '  %sSürüm:%s   %s (code %s)   %sSDK:%s %s\n' \
        "$C_DIM" "$C_RESET" "${vn:-?}" "${vc:-?}" "$C_DIM" "$C_RESET" "${ts:-?}"
    fi
  fi
  echo
}

# --- APK sonrası aksiyon menüsü -------------------------------------------
post_apk_menu() {
  local out=$1 mode=$2
  while true; do
    echo "Bu APK ile ne yapalım?"
    local opts=( "Menüye dön" "Cihaza kur (adb install -r)" "Cihaza kur + çalıştır" "Dosya yöneticisinde aç" )
    select_choice opts choice || { echo; continue; }
    case "$choice" in
      0) return 0 ;;
      1) install_apk "$out" ;;
      2) install_apk "$out" && run_installed ;;
      3) open_in_filemgr "$out" ;;
    esac
  done
}

install_apk() {
  local out=$1 dev
  dev="$(pick_device "Cihaz seç (kurulum):")" || { warn "Kurulum atlandı."; return 1; }
  hdr "adb -s $dev install -r $out"
  if "$ADB" -s "$dev" install -r "$out"; then
    ok "Kuruldu: $dev"
  else
    err "Kurulum başarısız."; return 1
  fi
}

run_installed() {
  local pkg="com.calorix.app"
  hdr "adb shell am start -n $pkg/.$APP_MAIN_ACTIVITY"
  "$ADB" shell am start -n "$pkg/.$APP_MAIN_ACTIVITY" 2>/dev/null \
    || "$ADB" shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 \
    || { warn "Otomatik başlatma yapılamadı — cihazdan elle aç."; return 1; }
  ok "Uygulama başlatıldı: $pkg"
}

open_in_filemgr() {
  local d; d="$(dirname "$1")"
  command -v xdg-open >/dev/null 2>&1 && { xdg-open "$d" 2>/dev/null || true; return 0; }
  command -v explorer.exe >/dev/null 2>&1 && { explorer.exe "$(wslpath -w "$d" 2>/dev/null)" 2>/dev/null || true; return 0; }
  warn "Dosya yöneticisi açılamadı. Yol: $d"
}

APP_MAIN_ACTIVITY="MainActivity"

# --- cihaz seçimi (kurulum/flutter run) -----------------------------------
# Çıktı: tek adb serial. Boşsa hata. Emülatör yoksa açma teklif eder.
pick_device() {
  local prompt=$1
  [[ -n "$ADB" ]] || { err "adb bulunamadı (ANDROID_HOME/platform-tools/adb)."; return 1; }

  local ids=() labels=()
  local id label
  while IFS=$'\t' read -r id label; do
    [[ -z "$id" ]] && continue
    ids+=("$id"); labels+=("$label")
  done < <(list_android_targets)

  # Fiziksel cihazları ekle (adb devices'tan).
  for id in $(adb_devices); do
    [[ " ${ids[*]} " == *" $id "* ]] && continue
    local model; model="$("$ADB" -s "$id" shell getprop ro.product.model 2>/dev/null | tr -d '\r' || echo "?")"
    ids+=("$id"); labels+=("$id — ${model:-cihaz}")
  done

  if (( ${#ids[@]} == 0 )); then
    # Cihaz yok → emülatör açma teklif et.
    warn "Bağlı cihaz/emülatör yok."
    if maybe_launch_emulator; then
      # Emülatör açıldıktan sonra listeyi yeniden dene.
      while IFS=$'\t' read -r id label; do
        [[ -z "$id" ]] && continue
        ids+=("$id"); labels+=("$label")
      done < <(list_android_targets)
    fi
    if (( ${#ids[@]} == 0 )); then
      err "Yine de cihaz yok — emülatör/cihaz bekleniyor."; return 1
    fi
  fi

  hdr "$prompt"
  local i=0
  for label in "${labels[@]}"; do printf '  %d) %s\n' "$i" "$label"; i=$((i+1)); done
  local n
  read -rp "Cihaz no> " n
  if [[ "$n" =~ ^[0-9]+$ ]] && (( 0 <= n && n < ${#ids[@]} )); then
    echo "${ids[$n]}"
    return 0
  fi
  err "Geçersiz seçim."; return 1
}

# Emülatör varsa açma teklif et; true dönerse bir cihaz bekleniyor.
maybe_launch_emulator() {
  local fl; fl="$(flutter_cmd)"
  [[ -z "$fl" ]] && return 1
  local emus; emus="$("$fl" emulators 2>/dev/null | sed -n '/^Id[[:space:]]/,$p' | tail -n +2)"
  [[ -z "$emus" ]] && return 1
  echo "  Mevcut emülatörler:"
  echo "$emus" | sed 's/^/    /'
  read -rp "Bir emülatör açılsın mı? [E/h] " yn
  [[ "${yn:-E}" =~ ^[Ee]$ ]] || return 1
  local first; first="$(echo "$emus" | awk '{print $1}' | head -1)"
  info "Emülatör başlatılıyor: $first (ilk açılış birkaç dakika sürebilir)..."
  "$fl" emulators --launch "$first" >/dev/null 2>&1 || true
  # Cihaz boot edene kadar bekle (en fazla ~120s).
  info "Cihaz hazır olana kadar bekleniyor..."
  local waited=0
  while (( waited < 120 )); do
    if "$ADB" shell getprop sys.boot_completed 2>/dev/null | grep -q 1; then
      sleep 2
      break
    fi
    sleep 3; waited=$((waited+3))
  done
  return 0
}

# --- flutter run (canlı çalıştırma) ---------------------------------------
run_app() {
  local fl; fl="$(flutter_cmd)"
  [[ -z "$fl" ]] && { err "flutter bulunamadı."; return 1; }
  hdr "Hedef seç"
  local opts=( "Geri" "Android cihaz/emülatör" "Web (tarayıcıda)" "Linux masaüstü" "Tüm bağlı cihazlar (d)" )
  select_choice opts choice || { echo; return 1; }
  case "$choice" in
    0) return 0 ;;
    1) run_android "$fl" ;;
    2) run_web "$fl" ;;
    3) run_desktop "$fl" linux ;;
    4) run_all "$fl" ;;
  esac
}

run_android() {
  local fl=$1
  local dev; dev="$(pick_device "Android hedefi:")" || { warn "Çalıştırma iptal."; return 1; }
  hdr "flutter run -d $dev"
  "$fl" run -d "$dev"
}

run_web() {
  local fl=$1
  # Web platformu disable olabilir → cihaz listesinde 'web' görünmez.
  # flutter config ile durumu teyit et, gerekirse enable teklif et.
  if ! "$fl" devices 2>/dev/null | grep -qiE '^[[:space:]]*(web|chrome)'; then
    warn "Web hedefi görünmüyor — Flutter web desteği kapalı olabilir."
    read -rp "flutter config --enable-web çalıştırılsın mı? [E/h] " yn
    if [[ "${yn:-E}" =~ ^[Ee]$ ]]; then
      "$fl" config --enable-web >/dev/null 2>&1 && ok "Web etkinleştirildi."
    else
      warn "Web etkinleştirilmedi — 'flutter run -d web' başarısız olabilir."
    fi
  fi
  local browsers; browsers="$(find_browsers)"
  if [[ -z "$browsers" ]]; then
    warn "Bilinen tarayıcı bulunamadı — flutter varsayılanı (Chrome/Chromium araması) kullanılacak."
    hdr "flutter run -d web"
    "$fl" run -d web
    return $?
  fi
  local exe=() desc=()
  local b
  while IFS='|' read -r e d; do exe+=("$e"); desc+=("$d"); done <<<"$browsers"
  hdr "Tarayıcı seç"
  local i=0; for d in "${desc[@]}"; do printf '  %d) %s\n' "$i" "$d"; i=$((i+1)); done
  printf '  %d) Flutter varsayılanı (otomatik Chrome araması)\n' "${#exe[@]}"
  local n
  read -rp "Tarayıcı no> " n
  if [[ "$n" =~ ^[0-9]+$ ]] && (( 0 <= n && n < ${#exe[@]} )); then
    local b="${exe[$n]}"; local exe_path; exe_path="$(command -v "$b")"
    # Flutter tool'u CHROME_EXECUTABLE env var'ını okur (flutter_tools
    # lib/src/web/chrome.dart kChromeEnvironment). Webkit/Firefox
    # farklı başlatıcılar ister; en güvenilir yol Chrome-ailesi + env.
    if [[ "$b" == firefox* || "$b" == brave-browser ]]; then
      warn "$b Chrome tabanlı değil — Flutter web yine de Chrome arar."
      warn "Onu ayrı pencerede açmak için: 'flutter run -d web-server' sonra URL'i $b ile aç."
    fi
    hdr "flutter run -d web  (CHROME_EXECUTABLE=$exe_path)"
    env "CHROME_EXECUTABLE=$exe_path" "$fl" run -d web
  elif [[ "$n" =~ ^[0-9]+$ ]] && (( n == ${#exe[@]} )); then
    hdr "flutter run -d web"
    "$fl" run -d web
  else
    warn "Geçersiz seçim — flutter varsayılanı kullanılıyor."
    hdr "flutter run -d web"
    "$fl" run -d web
  fi
}

run_desktop() {
  local fl=$1 platform=$2
  hdr "flutter run -d $platform"
  "$fl" run -d "$platform"
}

run_all() {
  local fl=$1
  hdr "flutter run -d all"
  "$fl" run -d all
}

# --- temizlik -------------------------------------------------------------
do_clean() {
  hdr "flutter clean"
  flutter clean
  ok "Temizlendi."
}

# --- ana menü -------------------------------------------------------------
main_menu() {
  while true; do
    hdr "Ne yapalım?"
    local opts=(
      "Çıkış"
      "Çalıştır (flutter run) — cihaz/tarayıcı seç"
      "Debug APK üret (hızlı, test)"
      "Release APK üret (imzalı, dağıtım)"
      "App Bundle üret (.aab, Play Console)"
      "Web (release) üret (statik dosyalar)"
      "Bağlı cihaz/emülatörleri göster"
      "Temizle (flutter clean)"
    )
    select_choice opts choice || { echo; continue; }
    case "$choice" in
      0) ok "Güle güle."; exit 0 ;;
      1) run_app ;;
      2) build_apk debug ;;
      3) build_apk release ;;
      4) build_aab ;;
      5) build_web ;;
      6) show_devices ;;
      7) do_clean ;;
    esac
    echo
  done
}

show_devices() {
  hdr "Bağlı cihazlar"
  local fl; fl="$(flutter_cmd)"
  if [[ -n "$fl" ]]; then
    "$fl" devices 2>/dev/null || true
  else
    err "flutter yok — adb'ye düşülüyor."
  fi
  if [[ -n "$ADB" ]]; then
    echo
    dim "adb devices -l:"
    "$ADB" devices -l 2>/dev/null || true
  fi
}

# --- CLI kısayolları (menüsüz) -------------------------------------------
run_direct() {
  case "$1" in
    debug)   preflight; build_apk debug ;;
    release) preflight; build_apk release ;;
    aab)     preflight; build_aab ;;
    web)     preflight; build_web ;;
    run)     preflight; run_app ;;
    clean)   preflight; do_clean ;;
    -h|--help|help) sed -n '2,20p' "${BASH_SOURCE[0]}" ;;
    *) err "Bilinmeyen komut: $1"; echo "Çalıştır: $0 --help"; exit 2 ;;
  esac
}

# --- giriş ---------------------------------------------------------------
if [[ $# -gt 0 ]]; then
  run_direct "$1"
else
  preflight
  main_menu
fi
