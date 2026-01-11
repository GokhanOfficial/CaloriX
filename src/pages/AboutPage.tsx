import { AppLayout } from "@/components/layout/AppLayout";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { Info, Mail, Code, Heart } from "lucide-react";
import { PollinationsCredit } from "@/components/common/PollinationsCredit";

const AboutPage = () => {
  return (
    <AppLayout title="Hakkında">
      <div className="container max-w-lg space-y-4 px-4 py-4">
        {/* App Info */}
        <Card className="border-none bg-card shadow-lg">
          <CardHeader className="text-center pb-2">
            <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-2xl bg-primary/10 mb-3">
              <Info className="h-8 w-8 text-primary" />
            </div>
            <CardTitle className="text-2xl font-bold text-foreground">CaloriX</CardTitle>
            <p className="text-muted-foreground">Kalori ve Makro Takip Uygulaması</p>
          </CardHeader>
          <CardContent className="text-center">
            <div className="inline-flex items-center gap-2 rounded-full bg-primary/10 px-3 py-1 text-sm font-medium text-primary">
              Versiyon 1.0.0
            </div>
          </CardContent>
        </Card>

        {/* Features */}
        <Card className="border-none bg-card shadow-lg">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Özellikler</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="flex items-start gap-3">
              <div className="h-2 w-2 rounded-full bg-primary mt-2" />
              <p className="text-sm text-foreground">AI destekli yemek tanıma (fotoğraf ve metin)</p>
            </div>
            <div className="flex items-start gap-3">
              <div className="h-2 w-2 rounded-full bg-primary mt-2" />
              <p className="text-sm text-foreground">Barkod ile yiyecek ekleme</p>
            </div>
            <div className="flex items-start gap-3">
              <div className="h-2 w-2 rounded-full bg-primary mt-2" />
              <p className="text-sm text-foreground">Su ve kilo takibi</p>
            </div>
            <div className="flex items-start gap-3">
              <div className="h-2 w-2 rounded-full bg-primary mt-2" />
              <p className="text-sm text-foreground">Detaylı analiz ve grafikler</p>
            </div>
            <div className="flex items-start gap-3">
              <div className="h-2 w-2 rounded-full bg-primary mt-2" />
              <p className="text-sm text-foreground">Akıllı bildirim hatırlatıcıları</p>
            </div>
            <div className="flex items-start gap-3">
              <div className="h-2 w-2 rounded-full bg-primary mt-2" />
              <p className="text-sm text-foreground">Offline-first çalışma desteği</p>
            </div>
          </CardContent>
        </Card>

        {/* Developer Info */}
        <Card className="border-none bg-card shadow-lg">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Geliştirici</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-full bg-primary/10">
                <Code className="h-5 w-5 text-primary" />
              </div>
              <div>
                <p className="font-medium text-foreground">Gökhan Tekyıldırım</p>
                <p className="text-sm text-muted-foreground">Yazılım Geliştirici</p>
              </div>
            </div>

            <Separator />

            <a
              href="mailto:gokhantekyildirim@outlook.com"
              className="flex items-center gap-3 p-3 rounded-lg bg-muted/50 hover:bg-muted transition-colors"
            >
              <Mail className="h-5 w-5 text-muted-foreground" />
              <div>
                <p className="text-sm font-medium text-foreground">E-posta</p>
                <p className="text-sm text-muted-foreground">gokhantekyildirim@outlook.com</p>
              </div>
            </a>
          </CardContent>
        </Card>

        {/* Powered By */}
        <Card className="border-none bg-card shadow-lg">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Destekleyenler</CardTitle>
          </CardHeader>
          <CardContent>
            <PollinationsCredit />
          </CardContent>
        </Card>

        {/* Footer */}
        <Card className="border-none bg-card shadow-lg">
          <CardContent className="p-4 text-center">
            <div className="flex items-center justify-center gap-2 text-sm text-muted-foreground">
              <span>Made with</span>
              <Heart className="h-4 w-4 text-destructive fill-destructive" />
              <span>in Turkey</span>
            </div>
            <p className="text-xs text-muted-foreground mt-2">
              © 2025 CaloriX. Tüm hakları saklıdır.
            </p>
          </CardContent>
        </Card>
      </div>
    </AppLayout>
  );
};

export default AboutPage;
