import { useState } from "react";
import { Droplets } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

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
  const [amount, setAmount] = useState("");

  const handleSubmit = () => {
    const value = parseInt(amount, 10);
    if (value > 0) {
      onSubmit(value);
      setAmount("");
      onOpenChange(false);
    }
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
            Özel Miktar Ekle
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-4 py-4">
          <div className="space-y-2">
            <Label htmlFor="waterAmount">Miktar (ml)</Label>
            <Input
              id="waterAmount"
              type="number"
              placeholder="Örn: 330"
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

        <DialogFooter>
          <Button variant="outline" onClick={() => handleOpenChange(false)}>
            İptal
          </Button>
          <Button 
            onClick={handleSubmit} 
            disabled={!amount || parseInt(amount, 10) <= 0}
          >
            Ekle
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
