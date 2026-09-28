import { useState } from "react";
import { Droplets } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogScrollArea,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useTranslation } from "react-i18next";

interface CustomWaterDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSubmit: (amount: number) => void;
}

export function CustomWaterDialog({
  open,
  onOpenChange,
  onSubmit,
}: CustomWaterDialogProps) {
  const { t } = useTranslation();
  const [amount, setAmount] = useState("");

  // `parseInt("500.9")` → 500 (ondalık **sessizce** kesilir), `parseInt("abc")`
  // → NaN, `parseInt("-1")` → -1. Alt sınır zaten vardı ama üst sınır
  // yoktu: "999999" ml tek kayıtla günlük hedefi (varsayılan 2500 ml)
  // binlerce katına çıkarıyor ve aylar boyunca istatistikleri bozuyordu.
  // Flutter tarafındaki karşılığı `water_tracker`'ın 5000 ml üst sınırıdır.
  const amountNum = Number(amount);
  const amountValid =
    Number.isInteger(amountNum) && amountNum >= 50 && amountNum <= 5000;

  const handleSubmit = () => {
    if (!amountValid) return;
    onSubmit(amountNum);
    setAmount("");
    onOpenChange(false);
  };

  const handleOpenChange = (newOpen: boolean) => {
    if (!newOpen) {
      setAmount("");
    }
    onOpenChange(newOpen);
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Droplets className="h-5 w-5 text-info" />
            {t('dialogs.customAmount')}
          </DialogTitle>
        </DialogHeader>

        <DialogScrollArea>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="waterAmount">{t('dashboard.water')} (ml)</Label>
              <Input
                id="waterAmount"
                type="number"
                min={50}
                max={5000}
                step={50}
                placeholder={`${t('dialogs.example')} 330`}
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && handleSubmit()}
                autoFocus
              />
            </div>

            {/* Quick presets */}
            <div className="flex gap-2 flex-wrap">
              {[150, 200, 330, 400, 600].map((preset) => (
                <Button
                  key={preset}
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => setAmount(String(preset))}
                  className="text-xs"
                >
                  {preset} ml
                </Button>
              ))}
            </div>
          </div>
        </DialogScrollArea>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => handleOpenChange(false)}>
            {t('common.cancel')}
          </Button>
          <Button
            type="button"
            onClick={handleSubmit}
            disabled={!amountValid}
          >
            {t('dialogs.add')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
