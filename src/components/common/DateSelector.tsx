import { ChevronLeft, ChevronRight, Calendar } from "lucide-react";
import { Button } from "@/components/ui/button";
import { format, addDays, subDays, isToday, isTomorrow, isYesterday, type Locale } from "date-fns";
import { tr, enUS, es, fr, de, pt, it, ru, ja, ko, zhCN, ar } from "date-fns/locale";
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
  const handlePrevDay = () => onDateChange(subDays(date, 1));
  const handleNextDay = () => onDateChange(addDays(date, 1));
  const handleToday = () => onDateChange(new Date());

  const currentLocale = locales[i18n.language.split('-')[0]] || enUS;

  const getDateLabel = () => {
    if (isToday(date)) return t('common.today');
    if (isYesterday(date)) return t('common.yesterday');
    if (isTomorrow(date)) return t('common.tomorrow');
    return format(date, "d MMMM yyyy", { locale: currentLocale });
  };

  return (
    <div className="flex items-center justify-between py-3">
      <Button
        variant="ghost"
        size="icon"
        onClick={handlePrevDay}
        className="h-9 w-9 text-muted-foreground hover:text-foreground"
      >
        <ChevronLeft className="h-5 w-5" />
      </Button>

      <button
        onClick={handleToday}
        className="flex items-center gap-2 rounded-lg px-3 py-1.5 text-foreground transition-colors hover:bg-muted"
      >
        <Calendar className="h-4 w-4 text-primary" />
        <span className="font-semibold">{getDateLabel()}</span>
        {!isToday(date) && (
          <span className="text-xs text-muted-foreground">
            ({format(date, "d MMM", { locale: tr })})
          </span>
        )}
      </button>

      <Button
        variant="ghost"
        size="icon"
        onClick={handleNextDay}
        className="h-9 w-9 text-muted-foreground hover:text-foreground"
      >
        <ChevronRight className="h-5 w-5" />
      </Button>
    </div>
  );
}
