import { ChevronLeft, ChevronRight, Calendar } from "lucide-react";
import { Button } from "@/components/ui/button";
import { format, isToday, isTomorrow, isYesterday, type Locale } from "date-fns";
import { tr, enUS, es, fr, de, pt, it, ru, ja, ko, zhCN, ar } from "date-fns/locale";
import { addLocalDays, startOfLocalDay } from "@/lib/dates";
import { useTranslation } from "react-i18next";

const locales: Record<string, Locale> = {
  tr, en: enUS, es, fr, de, pt, it, ru, ja, ko, zh: zhCN, ar
};

interface DateSelectorProps {
  date: Date;
  onDateChange: (date: Date) => void;
}

export function DateSelector({ date, onDateChange }: DateSelectorProps) {
  const { t, i18n } = useTranslation();
  // `addDays/subDays` (date-fns) `setDate` tabanlı **takvim günü** işlemidir
  // ve doğrudur; ancak "bugün" düğmesi `new Date()` ile gece yarısını
  // aşmış bir an verebiliyordu (seçili gün 00:05 iken "bugün" 05 dk sonrasına
  // kayıyordu, dolayısıyla `useDailyData` başka bir günü sorguluyordu).
  // `startOfLocalDay` bunu kapatıyor. `addLocalDays` de DST'de gün
  // kaçırmıyor (bkz. `lib/dates.ts`).
  const handlePrevDay = () => onDateChange(addLocalDays(date, -1));
  const handleNextDay = () => onDateChange(addLocalDays(date, 1));
  const handleToday = () => onDateChange(startOfLocalDay(new Date()));

  const currentLocale = locales[i18n.language.split('-')[0]] || enUS;

  const getDateLabel = () => {
    if (isToday(date)) return t('common.today');
    if (isYesterday(date)) return t('common.yesterday');
    if (isTomorrow(date)) return t('common.tomorrow');
    return format(date, "d MMMM yyyy", { locale: currentLocale });
  };

  return (
    <div className="flex items-center justify-between py-3">
      {/* Erişilebilirlik: ikon-only butonlarda erişilebilir ad yoktu —
          ekran okuyucu "buton" diyordu, ne yaptığını söylemiyordu
          (WCAG 4.1.2). `aria-label` + `title` eklendi. `type="button"`
          da şart: bu bileşen bir `<form>` içinde kullanılırsa buton
          **submit** olur ve formu gönderirdi. */}
      <Button
        type="button"
        variant="ghost"
        size="icon"
        onClick={handlePrevDay}
        aria-label={t('common.previousDay')}
        title={t('common.previousDay')}
        className="h-9 w-9 text-muted-foreground hover:text-foreground"
      >
        <ChevronLeft className="h-5 w-5" aria-hidden="true" />
      </Button>

      <button
        type="button"
        onClick={handleToday}
        className="flex items-center gap-2 rounded-lg px-3 py-1.5 text-foreground transition-colors hover:bg-muted"
      >
        <Calendar className="h-4 w-4 text-primary" aria-hidden="true" />
        <span className="font-semibold">{getDateLabel()}</span>
        {!isToday(date) && (
          <span className="text-xs text-muted-foreground">
            ({format(date, "d MMM", { locale: tr })})
          </span>
        )}
      </button>

      <Button
        type="button"
        variant="ghost"
        size="icon"
        onClick={handleNextDay}
        aria-label={t('common.nextDay')}
        title={t('common.nextDay')}
        className="h-9 w-9 text-muted-foreground hover:text-foreground"
      >
        <ChevronRight className="h-5 w-5" aria-hidden="true" />
      </Button>
    </div>
  );
}
