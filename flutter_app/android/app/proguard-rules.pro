# R8 rules — deliberately MINIMAL.
#
# Play Console "R8 optimisation" warning (release 42) was caused by three
# blanket rules that used to live here:
#   -keep class io.flutter.** { *; }
#   -keep class com.google.firebase.** { *; }
#   -keep class com.google.android.gms.** { *; }
# Blanket { *; } keeps disable shrinking/optimisation for the entire Flutter
# engine + all of Firebase + all of Play Services — R8 then ships them
# un-optimised (higher memory, bigger APK). None of them are needed:
# Flutter's Gradle tooling injects its own engine keep rules, and Firebase /
# Play Services / Play Billing / ML Kit all ship consumer ProGuard rules
# inside their AARs.

-keepattributes Signature
-keepattributes *Annotation*

# flutter_local_notifications deserialises scheduled notifications with Gson
# reflection — keep its models so scheduled reminders survive minification.
-keep class com.dexterous.** { *; }

-dontwarn io.flutter.**
-dontwarn com.google.**
