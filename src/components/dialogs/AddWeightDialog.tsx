import { useState } from "react";
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
import { Textarea } from "@/components/ui/textarea";
import { Loader2 } from "lucide-react";

interface AddWeightDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  currentWeight?: number;
  onSubmit: (weight: number, note?: string) => Promise<{ error: Error | null }>;
}

export function AddWeightDialog({
  open,
  onOpenChange,
  currentWeight,
  onSubmit,
}: AddWeightDialogProps) {
  const [loading, setLoading] = useState(false);
  const [weight, setWeight] = useState(currentWeight?.toString() || "");
  const [note, setNote] = useState("");

  // `parseFloat` "abc" → NaN, "" → NaN, "-3" → -3. Bunlar `weight_entries`
  // tablosuna yazılıp BMI/kilo trendini bozuyordu (Flutter tarafında aynı
  // sınıf hata `weight_card` ile düzeltildi). `Number.isFinite` + üst sınır.
  const weightNum = parseFloat(weight);
  const weightValid = Number.isFinite(weightNum) && weightNum >= 20 && weightNum <= 500;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!weightValid) return;
    setLoading(true);

    const result = await onSubmit(weightNum, note || undefined);

    setLoading(false);

    if (!result.error) {
      setWeight("");
      setNote("");
      onOpenChange(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Kilo Kaydet</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="flex flex-col flex-1 min-h-0">
          <DialogScrollArea>
            <div className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="weight">Kilo (kg)</Label>
                <Input
                  id="weight"
                  type="number"
                  step="0.1"
                  min={20}
                  max={500}
                  value={weight}
                  onChange={(e) => setWeight(e.target.value)}
                  placeholder="75.5"
                  required
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="note">Not (isteğe bağlı)</Label>
                <Textarea
                  id="note"
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  placeholder="Sabah aç karnına..."
                  rows={2}
                />
              </div>
            </div>
          </DialogScrollArea>

          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
            >
              İptal
            </Button>
            <Button type="submit" disabled={loading || !weightValid}>
              {loading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Kaydet
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
