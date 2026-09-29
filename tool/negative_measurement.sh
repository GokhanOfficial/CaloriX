#!/usr/bin/env bash
# ==========================================================
# ⭐ NEGATİF ÖLÇÜM (A1r11) — "yeşil test ≠ etkin test" döngüsünü kapatma
# ==========================================================
# PROTOKOL: Bir testin gerçekten bir hatayı yakaladığı, ancak düzeltme
# GERİ ALINIP kırmızıya düştüğü görülerek kanıtlanır. Bu betik:
#   1. düzeltme yerindeyken testi koşturur (yeşil olduğunu doğrular),
#   2. her düzeltmeyi TEK TEK geri alır,
#   3. testin KIRMIZIya düştüğünü doğrular,
#   4. dosyayı eski hâline döndürür ve tekrar yeşil olduğunu doğrular.
#
# ⚠️ Bu döngüde 8 kez "yeşil test ≠ etkin test" vakası yakalandı; yeni testler
#    yazılmadan önce/sonra bu betik koşturulmalıdır.
#
# Kullanım: bash tool/negative_measurement.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$ROOT/supabase/functions/_shared/openai_compat.ts"
TEST_REL="functions/_shared/openai_compat_test.ts"
BACKUP="$(mktemp -d)"
LOG="$BACKUP/test-output.log"

fail=0

restore() {
  [ -f "$BACKUP/openai_compat.ts" ] && cp "$BACKUP/openai_compat.ts" "$SHARED"
  rm -rf "$BACKUP"
}
trap restore EXIT

cp "$SHARED" "$BACKUP/openai_compat.ts"

# Testi koştur, çıktıyı $LOG'a yaz (renk kodları temizlenerek).
run_test() {
  (cd "$ROOT/supabase" && deno test --frozen=true --allow-env --allow-read "$TEST_REL" 2>&1) \
    | sed 's/\x1b\[[0-9;]*m//g' > "$LOG"
  return 0
}

expect_red() {
  if grep -qE 'FAILED|error: Test failed' "$LOG"; then
    echo "  [GECERLI] $1 -> test KIRMIZI oldu (düzeltme geri alınınca gerçekten kırılıyor)"
    grep -E '^FAILED' "$LOG" | head -3 | sed 's/^/            /'
  else
    echo "  [BASARISIZ] $1 -> test YESIL kaldı! Bu test hatayı YAKALAMIYOR (etkin değil)"
    tail -3 "$LOG" | sed 's/^/            /'
    fail=1
  fi
}

expect_green() {
  if grep -qE 'ok .* [0-9]+ passed .* 0 failed' "$LOG"; then
    echo "  [GECERLI] $1 -> test YESIL"
  else
    echo "  [BASARISIZ] $1 -> test beklenmedik şekilde KIRMIZI"
    tail -5 "$LOG" | sed 's/^/            /'
    fail=1
  fi
}

# ⚠️ KALDIRMA, *SATIR* değil *BLOK* bazlı olmalıdır.
# İlk denemede yalnızca `if (...) {` satırı silindi; gövde-işaretler
# (`}`) ortada kaldı ve dosya **tip denetiminden** düştü. Bu, testin kırmızıya
# düşmesi DEĞİL, programın derlenememesi demektir — sahte bir kanıttır.
# Bu yüzden her kaldırma, `if` bloğunun tamamını (açılıştan kapanışa) siler.
remove_block() {
  local file="$1" header="$2"
  python3 - "$file" "$header" <<'PY'
import sys, re
path, header = sys.argv[1], sys.argv[2]
src = open(path, encoding="utf-8").read()
idx = src.find(header)
if idx == -1:
    sys.exit(f"KALDIRMA HATASI: baslangic bulunamadi -> {header[:70]}")
# `if (...) {` satirindan eslesen kapanis suslusune kadar (suslu sayaci).
start = src.rfind("\n", 0, idx) + 1
i = src.find("{", idx)
depth = 0
while i != -1:
    if src[i] == "{":
        depth += 1
    elif src[i] == "}":
        depth -= 1
        if depth == 0:
            break
    i += 1
if i == -1:
    sys.exit("KALDIRMA HATASI: eslesen kapanis bulunamadi")
end = i + 1
open(path, "w", encoding="utf-8").write(src[:start] + "  // [KALDIRMA TESTI] blok kaldirildi\n" + src[end:])
PY
}

# Tek satırlık (blok olmayan) ifadeyi kaldırır. Yalnızca tam satır eşleşir.
remove_line() {
  local file="$1" line="$2"
  python3 - "$file" "$line" <<'PY'
import sys
path, line = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8").read().split("\n")
if line not in lines:
    sys.exit(f"KALDIRMA HATASI: satir bulunamadi -> {line[:70]}")
idx = lines.index(line)
lines[idx] = "  // [KALDIRMA TESTI] satir kaldirildi"
open(path, "w", encoding="utf-8").write("\n".join(lines))
PY
}

echo "=== 0) TEMEL: düzeltme yerinde test yeşil mi? ==="
run_test
expect_green "temel koşu"
if [ "$fail" -ne 0 ]; then
  echo "  [HATA] Temel koşu zaten kırmızı; negatif ölçüm yapılamaz."
  exit 1
fi

# ------------------------------------------------------------------
# KALDIRMA 1: kod bloğu + ön/son metin temizleme
# Ölçüme dayanak: MODEL-UYUMLULUK-RAPORU.md — Gemini/Gemma/GLM JSON'u
# ```json bloğü içinde döndürüyor; temizleme olmadan JSON.parse hep patlar.
# ------------------------------------------------------------------
echo
echo "=== 1) parseJsonLoose: kod bloğu + ön/son metin temizleme KALDIRILDI ==="
remove_block "$SHARED" '  if (fenced?.[1]) {' \
  && { run_test; expect_red "kod bloğu temizleme"; } || { echo "  [HATA] kaldırma yapılamadı"; fail=1; }
cp "$BACKUP/openai_compat.ts" "$SHARED"

# ------------------------------------------------------------------
# KALDIRMA 2: kesilmiş yanıt reddi
# Ölçüme dayanak: gemini-3.7-flash max_tokens:500 ile finish_reason=length
# döndü; kesilmiş JSON'dan makro hedefi üretmek sessiz başarısızlıktır.
# ------------------------------------------------------------------
echo
echo "=== 2) finish_reason=length reddi KALDIRILDI (sessiz başarısızlık riski) ==="
remove_block "$SHARED" '  if (isTruncated(finishReason)) {' \
  && { run_test; expect_red "length reddi"; } || { echo "  [HATA] kaldırma yapılamadı"; fail=1; }
cp "$BACKUP/openai_compat.ts" "$SHARED"

# ------------------------------------------------------------------
# KALDIRMA 3: content-parts (dizi) desteği
# Ölçüme dayanak: sağlayıcılar içeriği content DİZİSİ olarak da döndürebiliyor;
# eski kod `if (!content)` geçip JSON.parse'ı diziye çalıştırıyordu.
# ------------------------------------------------------------------
echo
echo "=== 3) extractText: content-parts (dizi) desteği KALDIRILDI ==="
remove_block "$SHARED" '  if (Array.isArray(content)) {' \
  && { run_test; expect_red "content-parts"; } || { echo "  [HATA] kaldırma yapılamadı"; fail=1; }
cp "$BACKUP/openai_compat.ts" "$SHARED"

# ------------------------------------------------------------------
# KALDIRMA 4: message.text yedeği
# Ölçüme dayanak: bazı proxy'ler içeriği message.content yerine message.text
# alanına koyuyor; eski kod null görüp 502 veriyordu.
# ------------------------------------------------------------------
echo
echo "=== 4) extractText: message.text yedeği KALDIRILDI ==="
remove_block "$SHARED" '  for (const key of ["text", "output_text"] as const) {' \
  && { run_test; expect_red "message.text"; } || { echo "  [HATA] kaldırma yapılamadı"; fail=1; }
cp "$BACKUP/openai_compat.ts" "$SHARED"

# ------------------------------------------------------------------
# KALDIRMA 5: dizi/nesne kök seçimi (sessiz veri kaybı)
# Bulgu: `Sonuçlar: [{"a":1}]` metninde dizi içindeki nesne seçilip dizi kökü
# sessizce kayboluyordu; ilk-blok sıralaması bunu engelliyor.
# ------------------------------------------------------------------
echo
echo "=== 5) parseJsonLoose: kök seçimi (dizi/nesne sırası) KALDIRILDI ==="
remove_line "$SHARED" '  candidates.sort((a, b) => a.start - b.start);' \
  && { run_test; expect_red "dizi kökü sırası"; } || { echo "  [HATA] kaldırma yapılamadı"; fail=1; }
cp "$BACKUP/openai_compat.ts" "$SHARED"

# ------------------------------------------------------------------
echo
echo "=== 6) GERİ YÜKLEME: dosya eski hâline döndü, test tekrar yeşil mi? ==="
run_test
expect_green "geri yükleme sonrası"

echo
if [ "$fail" -eq 0 ]; then
  echo "NEGATIF OLCUM: BASARILI — 5/5 kaldırma testi gerçekten kırmızıya düştü"
else
  echo "NEGATIF OLCUM: BASARISIZ — en az bir test hatayı yakalamıyor"
fi
exit "$fail"
