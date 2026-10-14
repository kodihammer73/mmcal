# MMCal - R8/ProGuard keep rules
#
# The release build uses R8 (code shrinking/obfuscation). Some plugins rely on
# reflection or on class names that R8 would otherwise strip/rename, which can
# cause a crash on launch in the release build even though the debug build works
# fine. These keep rules protect the plugins used by this app.

# --- google_mobile_ads (AdMob) ---
# The AdMob SDK uses reflection and must not be shrunk/obfuscated.
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# --- WorkManager + Room (used by google_mobile_ads) ---
# WorkManager uses Room internally. R8 strips/renames the Room-generated
# database implementation (WorkDatabase_Impl), which causes the launch crash:
#   "Failed to create an instance of androidx.work.impl.WorkDatabase"
# Keep all WorkManager and Room classes, plus Room-generated code.
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep @androidx.room.Entity class * { *; }
-keep @androidx.room.Dao class * { *; }
-keep @androidx.room.Database class * { *; }
-dontwarn androidx.work.**
-dontwarn androidx.room.**


# --- package_info_plus ---
# Reads package info via reflection on some platforms.
-keep class io.flutter.plugins.packageinfo.** { *; }
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }

# --- shared_preferences ---
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class com.shared_preferences.** { *; }

# --- url_launcher ---
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }

# --- Flutter engine / plugin registrant ---
# Keep the generated plugin registrant and Flutter engine classes.
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
-keep class com.mmcal.app.** { *; }

# --- General: keep line numbers for readable crash logs ---
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
