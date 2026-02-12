App to sort out gallery

✅ Wo du den Code schreibst (nachdem Schritt 2 fertig ist)

Dann gilt:

App-Code: lib/main.dart

Dependencies: pubspec.yaml

Android Permissions: android/app/src/main/AndroidManifest.xml


______

7) Wo du später etwas anpassen musst (wichtig)
App-Name ändern

Android Manifest Label:

android:label="Retro Relics" ✅ (ist schon drin)

AdMob später echt schalten

In lib/main.dart unten:

static const String rewardedAndroidTest = "...";


➡️ Später ersetzen durch eure echte Ad Unit ID.

Credits Logik

In lib/main.dart:

int _credits = 15;


Und bei Reward:

setState(() => _credits = 5);


AndroidManifest: Wichtig: Die APPLICATION_ID ist hier die Google Test App ID.
Später ersetzt du die durch deine echte AdMob App ID.