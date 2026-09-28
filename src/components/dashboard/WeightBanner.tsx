import { Scale, ChevronRight, AlertCircle } from "lucide-react";
import { CardContent } from "@/components/ui/card";
import { dayDiff } from "@/lib/dates";
import { cn } from "@/lib/utils";
import { useTranslation } from "react-i18next";

interface WeightBannerProps {
  lastWeight?: number;
  lastWeighDate?: Date;
  reminderDays?: number;
  onLogWeight?: () => void;
}

export function WeightBanner({
  lastWeight,
  lastWeighDate,
  reminderDays = 7,
  onLogWeight,
}: WeightBannerProps) {
  const { t } = useTranslation();
  /**
   * Gün farkı — **takvim günü** farkı.
   *
   * `Math.floor((Date.now() - date) / 864e5)` **duvar saati farkına**
   * duyarlıdır: gece 01:00'de tartılan bir kullanıcı için 12 saat sonra
   * fark 0 (değil 1) hesaplanıyor, yani "3 gündür tartılmadı" uyarısı
   * **bir gün geç** gösteriliyor. `lastWeighDate` ayrıca
   * `new Date("2026-03-01")` ile geliyordu → **UTC** gece yarısı; Türkiye'de
   * fark 3 saat eksik ölçülüyordu. `dayDiff` iki sorunu birden çözer
   * (yerel ayrıştırma `Index`'te, gün farkı burada).
   */
  const daysSinceWeigh = lastWeighDate ? dayDiff(lastWeighDate, new Date()) : null;

  const isOverdue = daysSinceWeigh !== null && daysSinceWeigh >= reminderDays;

  return (
    // Erişilebilirlik: `onClick` taşıyan bir `<div>` (shadcn `Card`)
    // klavyeyle **ulaşılamıyor** ve ekran okuyucu onu buton olarak
    // tanımıyordu (WCAG 2.1.1 / 4.1.2). İçindeki `Button` yalnız
    // dekoratif bir ok ikonuydu ve kendi tıklaması işlevsizdi
    // (`type` belirtilmediği için bir `<form>` içinde **submit** olurdu).
    // Kart artık bir `<button>`; içteki `Button` kaldırıldı (aynı işi iki
    // kez yapıyordu).
    <button
      type="button"
      onClick={onLogWeight}
      aria-label={t('dashboard.logWeight')}
      className={cn(
        "w-full border-none text-left shadow-lg transition-all hover:shadow-glow",
        isOverdue ? "bg-warning/10 border-warning/30" : "bg-card"
      )}
    >
      <CardContent className="flex items-center justify-between p-4">
        <div className="flex items-center gap-3">
          <div
            className={cn(
              "flex h-10 w-10 items-center justify-center rounded-full",
              isOverdue ? "bg-warning/20" : "bg-primary/10"
            )}
          >
            {isOverdue ? (
              <AlertCircle className="h-5 w-5 text-warning" />
            ) : (
              <Scale className="h-5 w-5 text-primary" />
            )}
          </div>
          <div>
            <p className="font-semibold text-foreground">
              {lastWeight ? `${lastWeight} kg` : t('dashboard.logWeight')}
            </p>
            <p className="text-sm text-muted-foreground">
              {isOverdue
                ? t('dashboard.weightOverdue', { days: daysSinceWeigh })
                : lastWeighDate
                  ? t('dashboard.lastWeight', { days: daysSinceWeigh })
                  : t('dashboard.recordWeight')}
            </p>
          </div>
        </div>
        <ChevronRight className="h-5 w-5 shrink-0 text-muted-foreground" aria-hidden="true" />
      </CardContent>
    </button>
  );
}
