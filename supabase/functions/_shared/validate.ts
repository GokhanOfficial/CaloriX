/**
 * Ortak input doğrulama yardımcıları.
 *
 * Amaç: gövde alanlarının tip/uzunluk/aralık kontrolünü tek yerde toplamak ve
 * kullanıcı girdisini (prompt injection yüzeyi) modele aktarırken sınırlandırmak.
 */

export class ValidationError extends Error {
  readonly status: number;
  constructor(message: string, status = 400) {
    super(message);
    this.name = "ValidationError";
    this.status = status;
  }
}

/** Zorunlu, boş olmayan metin; uzunluk sınırı uygulanır. */
export function requireString(value: unknown, field: string, maxLength = 500): string {
  if (typeof value !== "string") throw new ValidationError(`${field} metin olmalı`);
  const trimmed = value.trim();
  if (!trimmed) throw new ValidationError(`${field} boş olamaz`);
  if (trimmed.length > maxLength) throw new ValidationError(`${field} en fazla ${maxLength} karakter olabilir`);
  return trimmed;
}

/** İsteğe bağlı metin; verilmezse `null`, fazla uzunsa hata. */
export function optionalString(value: unknown, field: string, maxLength = 500): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") throw new ValidationError(`${field} metin olmalı`);
  const trimmed = value.trim();
  if (!trimmed) return null;
  if (trimmed.length > maxLength) throw new ValidationError(`${field} en fazla ${maxLength} karakter olabilir`);
  return trimmed;
}

/** UUID formatı doğrulaması (BOLA önlemi: tahmin edilebilir ID ile erişim). */
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function requireUuid(value: unknown, field: string): string {
  const text = requireString(value, field, 64);
  if (!UUID_RE.test(text)) throw new ValidationError(`${field} geçersiz`);
  return text.toLowerCase();
}

/** Sınırlı sayısal değer. */
export function requireNumber(value: unknown, field: string, min = 0, max = Number.MAX_SAFE_INTEGER): number {
  const number = typeof value === "number" ? value : typeof value === "string" ? Number(value) : NaN;
  if (!Number.isFinite(number)) throw new ValidationError(`${field} sayı olmalı`);
  if (number < min || number > max) {
    throw new ValidationError(`${field} ${min}-${max} aralığında olmalı`);
  }
  return number;
}

/** Bir eleman listeden seçilmiş olmalı (allow-list ile prompt injection azaltma). */
export function requireEnum<T extends string>(value: unknown, field: string, allowed: readonly T[]): T {
  if (typeof value !== "string" || !allowed.includes(value as T)) {
    throw new ValidationError(`${field} geçersiz değer`);
  }
  return value as T;
}

/** YYYY-MM-DD formatı. */
export function requireDateOnly(value: unknown, field: string): string {
  const text = requireString(value, field, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) throw new ValidationError(`${field} YYYY-AA-GG olmalı`);
  return text;
}

/** data URL / base64 görsel doğrulaması (boyut sınırı ile). */
export function requireImageBase64(value: unknown, field = "image_base64", maxChars = 8_000_000): string {
  const text = requireString(value, field, maxChars);
  if (!/^data:image\/(jpeg|jpg|png|webp|gif);base64,[A-Za-z0-9+/=\s]+$/.test(text) && !/^[A-Za-z0-9+/=\s]+$/.test(text)) {
    throw new ValidationError("Görsel formatı geçersiz (data URL veya base64 bekleniyor)");
  }
  return text;
}
