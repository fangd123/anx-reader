# Local Build Environment

This file records the local tool paths that have already been verified on this machine for building `anx-reader`.

## Flutter

- Flutter SDK: `/home/ubuntu/tooling/flutter`
- Flutter binary: `/home/ubuntu/tooling/flutter/bin/flutter`
- Dart binary: `/home/ubuntu/tooling/flutter/bin/dart`

Check version:

```bash
/home/ubuntu/tooling/flutter/bin/flutter --version
```

## Android

- Android SDK: `/home/ubuntu/android-sdk`
- Android local properties file: `/home/ubuntu/ai_projects/anx-reader/android/local.properties`

Current `android/local.properties` values:

```properties
flutter.sdk=/home/ubuntu/tooling/flutter
sdk.dir=/home/ubuntu/android-sdk
flutter.buildMode=release
flutter.versionName=1.15.0
flutter.versionCode=6324
```

## Java / JDK

System default `java` currently points to:

- `java`: `/usr/lib/jvm/java-21-openjdk-amd64/bin/java`

But that location does not provide `javac`, so it is not sufficient for Android builds by itself.

Verified full JDK paths on this machine:

- Preferred `JAVA_HOME`: `/home/ubuntu/.local/jdks/jdk-21.0.11+10`
- `javac`: `/home/ubuntu/.local/jdks/jdk-21.0.11+10/bin/javac`

Other full JDKs found:

- `/home/ubuntu/.local/opt/openjdk21/usr/lib/jvm/java-21-openjdk-amd64`
- `/home/ubuntu/tooling/local-jdk/extract/usr/lib/jvm/java-21-openjdk-amd64`
- `/home/ubuntu/tooling/local-jdk/jdk21`

Recommended build environment:

```bash
export JAVA_HOME=/home/ubuntu/.local/jdks/jdk-21.0.11+10
export PATH="$JAVA_HOME/bin:$PATH"
```

Verify:

```bash
java -version
javac -version
```

## Android Signing

- Key properties: `/home/ubuntu/ai_projects/anx-reader/android/key.properties`
- Keystore: `/home/ubuntu/ai_projects/anx-reader/android/app/keystore.jks`

`android/key.properties` currently references:

```properties
storeFile=keystore.jks
```

This path is resolved relative to `android/app/build.gradle`, so the actual keystore file in use is:

- `/home/ubuntu/ai_projects/anx-reader/android/app/keystore.jks`

## Release Build Command

Use this exact command for local APK release builds:

```bash
cd /home/ubuntu/ai_projects/anx-reader
export JAVA_HOME=/home/ubuntu/.local/jdks/jdk-21.0.11+10
export PATH="$JAVA_HOME/bin:$PATH"
/home/ubuntu/tooling/flutter/bin/flutter build apk --release
```

## Notes

- If Gradle reports that the toolchain does not provide `JAVA_COMPILER`, check whether `JAVA_HOME` is accidentally pointing at `/usr/lib/jvm/java-21-openjdk-amd64`.
- Prefer the full JDK under `/home/ubuntu/.local/jdks/jdk-21.0.11+10` for Android builds on this machine.
