import pollinationsLogo from "@/assets/pollinations-logo.svg";

interface PollinationsCreditProps {
  className?: string;
}

export function PollinationsCredit({ className }: PollinationsCreditProps) {
  return (
    <div className={className}>
      <p className="text-xs text-muted-foreground text-center mb-1">
        AI destekçisi
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
