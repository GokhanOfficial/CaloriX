import { ScanBarcode, Sparkles, Search, History, Star } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useTranslation } from "react-i18next";

interface QuickAddMenuProps {
  onBarcodeScan?: () => void;
  onPhotoAdd?: () => void;
  onTextAdd?: () => void;
  onRecent?: () => void;
  onFavorites?: () => void;
}

export function QuickAddMenu({
  onBarcodeScan,
  onPhotoAdd,
  onTextAdd,
  onRecent,
  onFavorites,
}: QuickAddMenuProps) {
  const { t } = useTranslation();

  const actions = [
    {
      icon: ScanBarcode,
      label: t('dashboard.quick.barcode'),
      description: t('dashboard.quick.scan'),
      onClick: onBarcodeScan,
    },
    {
      icon: Search,
      label: t('dashboard.quick.search'),
      description: t('dashboard.quick.findFood'),
      onClick: onTextAdd,
    },
    {
      icon: Sparkles,
      label: t('dashboard.quick.ai'),
      description: t('dashboard.quick.photoText'),
      onClick: onPhotoAdd,
    },
    {
      icon: History,
      label: t('dashboard.quick.recent'),
      description: t('dashboard.quick.history'),
      onClick: onRecent,
    },
    {
      icon: Star,
      label: t('dashboard.quick.favorites'),
      description: t('dashboard.quick.saved'),
      onClick: onFavorites,
    },
  ];

  return (
    <Card className="border-none bg-card shadow-lg">
      <CardHeader className="pb-2">
        <CardTitle className="text-lg font-semibold">{t('dashboard.quickAdd')}</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-3 gap-3 sm:grid-cols-5">
          {actions.map(({ icon: Icon, label, description, onClick }) => (
            <button
              key={label}
              onClick={onClick}
              className="flex flex-col items-center gap-2 rounded-xl p-3 transition-all hover:bg-primary/5 hover:shadow-md active:scale-95"
            >
              <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-primary/10 transition-colors">
                <Icon className="h-6 w-6 text-primary" />
              </div>
              <div className="text-center">
                <p className="text-xs font-medium text-foreground">{label}</p>
                <p className="text-[10px] text-muted-foreground">{description}</p>
              </div>
            </button>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
