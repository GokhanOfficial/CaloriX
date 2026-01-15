import { ScanBarcode, Sparkles, Search, History, Star } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useOnlineStatus } from "@/hooks/useOnlineStatus";
import { cn } from "@/lib/utils";
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
  const isOnline = useOnlineStatus();
  const { t } = useTranslation();

  const actions = [
    {
      icon: ScanBarcode,
      label: t('dashboard.quick.barcode'),
      description: t('dashboard.quick.scan'),
      onClick: onBarcodeScan,
      requiresOnline: false,
    },
    {
      icon: Search,
      label: t('dashboard.quick.search'),
      description: t('dashboard.quick.findFood'),
      onClick: onTextAdd,
      requiresOnline: false,
    },
    {
      icon: Sparkles,
      label: t('dashboard.quick.ai'),
      description: t('dashboard.quick.photoText'),
      onClick: onPhotoAdd,
      requiresOnline: true,
    },
    {
      icon: History,
      label: t('dashboard.quick.recent'),
      description: t('dashboard.quick.history'),
      onClick: onRecent,
      requiresOnline: false,
    },
    {
      icon: Star,
      label: t('dashboard.quick.favorites'),
      description: t('dashboard.quick.saved'),
      onClick: onFavorites,
      requiresOnline: false,
    },
  ];

  return (
    <Card className="border-none bg-card shadow-lg">
      <CardHeader className="pb-2">
        <CardTitle className="text-lg font-semibold">{t('dashboard.quickAdd')}</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-3 gap-3 sm:grid-cols-5">
          {actions.map(({ icon: Icon, label, description, onClick, requiresOnline }) => {
            const isDisabled = requiresOnline && !isOnline;
            return (
              <button
                key={label}
                onClick={onClick}
                disabled={isDisabled}
                className={cn(
                  "flex flex-col items-center gap-2 rounded-xl p-3 transition-all",
                  isDisabled
                    ? "cursor-not-allowed opacity-50"
                    : "hover:bg-primary/5 hover:shadow-md active:scale-95"
                )}
              >
                <div
                  className={cn(
                    "flex h-12 w-12 items-center justify-center rounded-xl transition-colors",
                    isDisabled ? "bg-muted" : "bg-primary/10"
                  )}
                >
                  <Icon
                    className={cn(
                      "h-6 w-6",
                      isDisabled ? "text-muted-foreground" : "text-primary"
                    )}
                  />
                </div>
                <div className="text-center">
                  <p className="text-xs font-medium text-foreground">{label}</p>
                  <p className="text-[10px] text-muted-foreground">{description}</p>
                </div>
              </button>
            );
          })}
        </div>
        {!isOnline && (
          <p className="mt-3 text-center text-xs text-warning">
            {t('dashboard.quick.offline')}
          </p>
        )}
      </CardContent>
    </Card>
  );
}
