# Google OAuth Setup Guide

## 1. Extracting SHA Keys
You need the SHA-1 and SHA-256 fingerprints to register the Android app with Google.
Run the following commands in the terminal:
```bash
cd android
./gradlew signingReport
```
Copy the `SHA1` and `SHA-256` from the output under the `AndroidDebugKey` alias.
For your current debug keystore, the values are:
- **SHA-1**: `05:2E:DA:A5:BC:2D:C1:B9:FF:F4:D6:35:9B:77:68:6C:7F:A8:B6:F8`
- **SHA-256**: `EE:61:7D:E8:56:EE:7E:79:CE:7C:2C:59:FD:D6:6B:00:3D:69:BB:94:5E:E9:47:C2:F5:18:49:B1:E8:97:0D:DE`

## 2. Firebase Console Configuration
1. Go to the [Firebase Console](https://console.firebase.google.com/).
2. Select your project.
3. Go to **Project Settings** (the gear icon) > **General** tab.
4. Scroll down to your Android app (`com.basra.storemanager`).
5. Click **Add fingerprint** and paste the `SHA-1` and `SHA-256` extracted above.
6. Make sure to download the updated `google-services.json` and replace the existing one in `android/app/google-services.json` (This ensures the `oauth_client` array is properly populated).

## 3. Google Cloud Console Configuration
1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Select the project associated with your Firebase project.
3. Go to **APIs & Services** > **Credentials**.
4. You will see Web client and Android client IDs under "OAuth 2.0 Client IDs" that Firebase automatically created.
5. We need the **Web client ID** and its **Client secret** to configure Supabase.

## 4. Supabase Dashboard Configuration
1. Go to the [Supabase Dashboard](https://supabase.com/dashboard).
2. Open your project > **Authentication** > **Providers** > **Google**.
3. Enable Google sign-in.
4. Enter the **Web Client ID** and **Web Client Secret** obtained from the Google Cloud Console.
5. Copy the Supabase Redirect URL: `https://rkofqwcuvbzrnmelvxhz.supabase.co/auth/v1/callback`
6. Go back to Google Cloud Console > **Credentials** > Edit the **Web client**, and add this Redirect URL under "Authorized redirect URIs".

## 5. Mobile App Deep Link Verification
The deep link callback is `io.supabase.naboo://login-callback`.
- **Android**: Verified in `android/app/src/main/AndroidManifest.xml` (using `<data android:scheme="io.supabase.naboo" android:host="login-callback"/>`).
- **iOS**: Verified in `ios/Runner/Info.plist`.
- **Package Name**: Verified as `com.basra.storemanager` in `android/app/build.gradle.kts`.
