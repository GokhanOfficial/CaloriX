#!/usr/bin/env bash
# CaloriX Android sürüm yayınlama scripti.
#
# APK + latest.json dosyalarını GitHub Releases'a yükler; Flutter uygulaması
# açılışta https://github.com/GokhanOfficial/CaloriX/releases/latest/download/latest.json
# adresinden kontrol eder.
#
# Kullanım:
#   tool/release_android.sh [--min-code N] [--notes-tr "..."] [--notes-en "..."]
#
# Örnekler:
#   # Normal sürüm — eski sürümler OPSİYONEL güncelleme görür:
#   tool/release_android.sh
#
#   # DB migration'ı geldi (ör. şema değişti) — build 4'ten eskiler ÇALIŞMAZ:
#   tool/release_android.sh --min-code 4
#
# Ön koşullar: flutter, gh (girişli), python3, curl.
set -euo pipefail

REPO="GokhanOfficial/CaloriX"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_DIR="$ROOT/flutter_app"
PUBSPEC="$FLUTTER_DIR/pubspec.yaml"
ASSET_NAME="calorix.apk"

MIN_CODE=""
NOTES_TR=""
NOTES_EN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --min-code)
      [[ $# -ge 2 ]] || { echo "HATA: --min-code bir değer gerektirir." >&2; exit 1; }
      MIN_CODE="$2"; shift 2 ;;
    --notes-tr)
      [[ $# -ge 2 ]] || { echo "HATA: --notes-tr bir değer gerektirir." >&2; exit 1; }
      NOTES_TR="$2"; shift 2 ;;
    --notes-en)
      [[ $# -ge 2 ]] || { echo "HATA: --notes-en bir değer gerektirir." >&2; exit 1; }
      NOTES_EN="$2"; shift 2 ;;
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Bilinmeyen argüman: $1" >&2; exit 1 ;;
  esac
done

# Ön koşullar — hepsi kullanılıyor, eksikse sessizce bozuk manifest
# üretmektense baştan dur.
for cmd in flutter gh python3 curl sha256sum; do
  command -v "$cmd" >/dev/null \
    || { echo "HATA: '$cmd' bulunamadı." >&2; exit 1; }
done

# --- 1) Sürüm bilgisi pubspec'ten ---
VERSION_LINE="$(grep -m1 '^version:' "$PUBSPEC")"
VERSION="$( cut -d'+' -f1 <<<"${VERSION_LINE#version: }" )"
BUILD="$(  cut -d'+' -f2 <<<"${VERSION_LINE#version: }" )"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "HATA: pubspec version biçimi: $VERSION_LINE" >&2; exit 1; }
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "HATA: pubspec build numarası yok (örn. version: 1.2.0+3): $VERSION_LINE" >&2; exit 1; }

# min-code yoksa: cutoff = 1 → eskilere opsiyonel güncelleme (zorunluluk
# yalnızca DB migration'ı gibi kırıcı değişiklikte --min-code ile gelir).
MIN_CODE="${MIN_CODE:-1}"
[[ "$MIN_CODE" =~ ^[0-9]+$ ]] || { echo "HATA: --min-code sayısal olmalı." >&2; exit 1; }
if (( MIN_CODE > BUILD )); then
  echo "HATA: --min-code ($MIN_CODE) yayınlanan build'den ($BUILD) büyük olamaz." >&2; exit 1
fi

TAG="android-v${VERSION}+${BUILD}"
echo "» Sürüm: $VERSION (build $BUILD) | min desteklenen build: $MIN_CODE | tag: $TAG"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "HATA: $TAG tag'i zaten var. pubspec'te sürümü/build'i yükselt." >&2; exit 1
fi

# --- 2) Release APK derle ---
echo "» flutter build apk --release ..."
( cd "$FLUTTER_DIR" && flutter build apk --release )
APK="$FLUTTER_DIR/build/app/outputs/flutter-apk/app-release.apk"
[[ -f "$APK" ]] || { echo "HATA: APK bulunamadı: $APK" >&2; exit 1; }

SHA256="$(sha256sum "$APK" | cut -d' ' -f1)"
APK_SIZE_MB="$(( $(stat -c%s "$APK") / 1024 / 1024 ))"
echo "» APK hazır: ${APK_SIZE_MB} MB, sha256=$SHA256"

# --- 3) latest.json üret ---
# Not: tag'deki '+' URL'de %2B olmalı; GitHub asset URL'si tag'ı olduğu gibi
# kullanır, APK asset adını sabit tutuyoruz (calorix.apk) ki URL basit kalsın.
APK_URL="https://github.com/${REPO}/releases/download/${TAG//+/%2B}/${ASSET_NAME}"
GENERATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Not: `latest.json` geçici dosya olarak repo köküne yazılır (release'a
# yüklenmek için) ve **her** çıkış yolunda silinir. Daha önce yalnızca
# başarıda `rm -f` vardı; `gh release create` hata verdiğinde yayınlanmamış
# bir manifest çalışma ağacında kalıyor ve bir sonraki run'da yanlışlıkla
# yüklenebiliyordu.
LATEST_JSON="$ROOT/latest.json"
trap 'rm -f "$NOTES_FILE" "$LATEST_JSON"; rm -rf "$STAGE_DIR"' EXIT
NOTES_FILE=""
STAGE_DIR=""

python3 - "$APK_URL" "$SHA256" "$GENERATED_AT" "$VERSION" "$BUILD" "$MIN_CODE" "$NOTES_TR" "$NOTES_EN" <<'PYEOF' > "$LATEST_JSON"
import json, sys
apk_url, sha256, released_at, version, code, min_code, notes_tr, notes_en = sys.argv[1:9]
notes = {k: v for k, v in (("tr", notes_tr), ("en", notes_en)) if v}
print(json.dumps({
    "versionName": version,
    "versionCode": int(code),
    "minSupportedVersionCode": int(min_code),
    "apkUrl": apk_url,
    "sha256": sha256,
    "notes": notes,
    "releasedAt": released_at,
}, indent=2, ensure_ascii=False))
PYEOF
echo "» latest.json üretildi:"
cat "$LATEST_JSON"

# --- 4) Release oluştur ---
NOTES_FILE="$(mktemp)"
{
  echo "CaloriX Android $VERSION (build $BUILD)"
  echo
  echo "- APK: \`$ASSET_NAME\` (${APK_SIZE_MB} MB, sha256: \`${SHA256:0:16}…\`)"
  echo "- Minimum desteklenen build: **$MIN_CODE**$( (( MIN_CODE <= 1 )) && echo " — tüm eski sürümler opsiyonel güncelleme görür" || echo " — daha eskiler zorunlu güncelleme görür")"
  [[ -n "$NOTES_TR" ]] && { echo; echo "## Notlar"; echo "$NOTES_TR"; }
} > "$NOTES_FILE"

echo "» gh release create $TAG ..."
# gh'nin "dosya#ad" sözdizimi asset'i yeniden adlandırmıyor; APK'yı
# kararlı "calorix.apk" adına kopyalayıp öyle yüklüyoruz (manifest URL'si
# sürümden bağımsız sabit kalır).
STAGE_DIR="$(mktemp -d)"
STAGED_APK="$STAGE_DIR/$ASSET_NAME"
cp "$APK" "$STAGED_APK"

gh release create "$TAG" \
  --repo "$REPO" \
  --title "CaloriX Android $VERSION" \
  --notes-file "$NOTES_FILE" \
  "$STAGED_APK" \
  "$LATEST_JSON"

# --- 5) Kararlı URL'yi doğrula ---
MANIFEST_URL="https://github.com/${REPO}/releases/latest/download/latest.json"
sleep 3
STATUS="$(curl -sIL -o /dev/null -w '%{http_code}' "$MANIFEST_URL")"
if [[ "$STATUS" == "200" ]]; then
  echo "✓ Yayınlandı ve doğrulandı: $MANIFEST_URL"
  curl -sL "$MANIFEST_URL" | python3 -c 'import json,sys; m=json.load(sys.stdin); print("  manifest: v" + m["versionName"] + " build " + str(m["versionCode"]) + ", min build " + str(m["minSupportedVersionCode"]))'
else
  echo "⚠ UYARI: manifest URL'si HTTP $STATUS döndü (yayınlanması birkaç saniye sürebilir): $MANIFEST_URL" >&2
fi
