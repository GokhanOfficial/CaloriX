import { ChevronLeft, ChevronRight, Calendar } from "lucide-react";
import { Button } from "@/components/ui/button";
import { format, addDays, subDays, isToday, isTomorrow, isYesterday } from "date-fns";
import { tr } from "date-fns/locale";

interface DateSelectorProps {
  date: Date;
  onDateChange: (date: Date) => void;
}

export function DateSelector({ date, onDateChange }: DateSelectorProps) {
  const handlePrevDay = () => onDateChange(subDays(date, 1));
  const handleNextDay = () => onDateChange(addDays(date, 1));
  const handleToday = () => onDateChange(new Date());

  const getDateLabel = () => {
    if (isToday(date)) return "Bugün";
    if (isYesterday(date)) return "Dün";
    if (isTomorrow(date)) return "Yarın";
    return format(date, "d MMMM yyyy", { locale: tr });
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
