import pollinationsLogo from "@/assets/pollinations-logo.svg";
import { useTranslation } from "react-i18next";

interface PollinationsCreditProps {
  className?: string;
}

export function PollinationsCredit({ className }: PollinationsCreditProps) {
  const { t } = useTranslation();
  return (
    <div className={className}>
      <p className="text-xs text-muted-foreground text-center mb-1">
        {t('common.aiPoweredBy')}
      </p>
      <a
        href="https://pollinations.ai/"
        target="_blank"
        rel="noopener noreferrer"
        className="flex items-center justify-center hover:opacity-80 transition-opacity"
      >
        <img
          src={pollinationsLogo}
          alt="Pollinations.ai"
          className="h-5 invert dark:invert-0 opacity-70 hover:opacity-100 transition-opacity"
        />
      </a>
    </div>
  );
}
