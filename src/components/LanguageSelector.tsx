import { useTranslation } from "react-i18next";
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from "@/components/ui/select";
import { Globe } from "lucide-react";

export function LanguageSelector() {
    const { i18n } = useTranslation();

    const handleLanguageChange = (value: string) => {
        i18n.changeLanguage(value);
    };

    return (
        <Select value={i18n.language.split('-')[0]} onValueChange={handleLanguageChange}>
            <SelectTrigger className="w-[140px] bg-background/50 backdrop-blur-sm border-muted">
                <Globe className="mr-2 h-4 w-4" />
                <SelectValue placeholder="Language" />
            </SelectTrigger>
            <SelectContent>
                <SelectItem value="en">English</SelectItem>
                <SelectItem value="tr">Türkçe</SelectItem>
                <SelectItem value="es">Español</SelectItem>
                <SelectItem value="fr">Français</SelectItem>
                <SelectItem value="de">Deutsch</SelectItem>
                <SelectItem value="pt">Português</SelectItem>
                <SelectItem value="it">Italiano</SelectItem>
                <SelectItem value="ru">Русский</SelectItem>
                <SelectItem value="ja">日本語</SelectItem>
                <SelectItem value="ko">한국어</SelectItem>
                <SelectItem value="zh">中文</SelectItem>
                <SelectItem value="ar">العربية</SelectItem>
            </SelectContent>
        </Select>
    );
}
