# ProGuard / R8 keep rules — CaloriX Flutter (Faz 5)
#
# Release build'de minifyEnabled + shrinkResources açık. Aşağıdaki
# kurallar, yansıma (reflection) veya manuel JSON eşlemesi ile çalışan
# sınıfların R8 tarafından daraltılıp kaldırılmasını engeller.

# --- Flutter / Dart ---
# Flutter engine ve Dart AOT derlemesi zaten kendi kendini korur;
# bu satır önlem amaçlı bırakılmıştır.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# --- Supabase (gson/jackson-style reflection, PostgREST DTO) ---
# supabase_flutter kendi keep kurallarını consumer rules ile getirir;
# yine de DTO ve model sınıflarını açıkça koruyoruz.
-keep class com.supabase.** { *; }
-keep class io.supabase.** { *; }
-keep class com.calorix.** { *; }
-keep class com.calorix.app.** { *; }

# Model sınıfları: @JsonSerializable kodu üretse de, bazı eşlemeler
# (Map<String,dynamic> manuel parse, fromJson factory) R8 tarafından
# kullanılmış sayılmayıp kaldırılabilir. Tüm data model sınıflarını
# ve ürettikleri .g.dart kodunu koru.
-keep class com.calorix.app.data.models.** { *; }
-keep class com.calorix.app.data.models.**$* { *; }
# json_serializable ürettiği `$*JsonConverter` ve yardımcı sınıflar.
-keepclassmembers class com.calorix.app.data.models.** {
  public *;
  <fields>;
}

# --- Riverpod ---
# Provider'lar yansıma ile değil compile-time ile çözülür, ancak
# riverpod'un dahili annotation işleyicisi için önlem:
-keep class riverpod.** { *; }

# --- easy_localization (asset tabanlı JSON, runtime reflection yok) ---
# Çeviri JSON'ları asset olarak gömülü; R8 dokunmaz. Yine de
# EasyLocalization sınıf hiyerarşisini koru.
-keep class com.github.easylocalization.** { *; }

# --- mobile_scanner / camera / image_picker (native plugin) ---
# Plugin'ler MethodChannel ile konuşur; plugin proxy sınıfları
# R8 tarafından küçültülmemeli. Flutter plugin consumer rules genelde
# bunu otomatik yapar, burada yedek olarak.
-keep class com.google.zxing.** { *; }
-keep class me.leon.** { *; }

# --- Genel: enum ve serialVersionUID ---
-keepclassmembers enum * {
  public static **[] values();
  public static ** valueOf(java.lang.String);
}
-keepclassmembers class * implements java.io.Serializable {
  static final long serialVersionUID;
  private static final java.io.ObjectStreamField[] serialPersistentFields;
  private void writeObject(java.io.ObjectOutputStream);
  private void readObject(java.io.ObjectInputStream);
  java.lang.Object writeReplace();
  java.lang.Object readResolve();
}

# --- Play Core (Play Store deferred components) ---
# Uygulama Play Core / ertelenmiş bileşen kullanmıyor, ancak Flutter
# engine'in PlayStoreDeferredComponentManager'ı bu sınıflara referans
# verir. Bunlar classpath'te olmadığından R8 missing-class hatası verir.
# Sınıfları derlemeye zorlamadan uyarıyı bastır (R8 önerisi).
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# --- Yığınlama (stack traces) okunabilir kalsın ---
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,InnerClasses,EnclosingMethod
-renamesourcefileattribute SourceFile
