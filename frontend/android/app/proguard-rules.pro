# Release builds shrink and optimise the Java side with R8 (Flutter's Gradle
# plugin adds this file to that step). Google's Navigation SDK builds its own
# internal classes by reflection, so R8 must leave them whole: without these
# rules the driver app crashed the moment in-app guidance started
# ("IllegalAccessException ... navigation.internal ... is not accessible"),
# in release builds only - debug builds are not shrunk.
-keep class com.google.android.libraries.navigation.** { *; }
-keep interface com.google.android.libraries.navigation.** { *; }
-dontwarn com.google.android.libraries.navigation.**

# The Navigation SDK ships its own copy of the Maps classes under this name.
-keep class com.google.android.libraries.geo.** { *; }
-dontwarn com.google.android.libraries.geo.**
