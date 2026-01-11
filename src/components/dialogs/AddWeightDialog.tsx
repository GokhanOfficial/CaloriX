import { useState } from "react";
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

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    const result = await onSubmit(parseFloat(weight), note || undefined);

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
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="weight">Kilo (kg)</Label>
            <Input
              id="weight"
              type="number"
              step="0.1"
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

          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
            >
              İptal
            </Button>
            <Button type="submit" disabled={loading || !weight}>
              {loading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Kaydet
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
