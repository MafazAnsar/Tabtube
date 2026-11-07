#!/usr/bin/env bash
# Generates the TabTube Android project and builds the APK.
set -e
rm -rf proj && mkdir proj && cd proj
J=app/src/main/java/com/tabtube/player
mkdir -p $J app/src/main/res/drawable

cat > settings.gradle <<'EOF'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = 'TabTube'
include ':app'
EOF
cat > build.gradle <<'EOF'
plugins { id 'com.android.application' version '8.5.2' apply false }
EOF
cat > gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx2g
android.nonTransitiveRClass=true
EOF
cat > app/build.gradle <<'EOF'
plugins { id 'com.android.application' }
android {
    namespace 'com.tabtube.player'
    compileSdk 34
    defaultConfig {
        applicationId 'com.tabtube.player'
        minSdk 21
        targetSdk 34
        versionCode 1
        versionName '1.0'
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
    lint { abortOnError false }
}
EOF
cat > app/src/main/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <application
        android:label="TabTube"
        android:icon="@drawable/ic_launcher"
        android:hardwareAccelerated="true"
        android:usesCleartextTraffic="false"
        android:theme="@android:style/Theme.DeviceDefault">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTask"
            android:configChanges="orientation|screenSize|keyboardHidden|smallestScreenSize|screenLayout|uiMode">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="https"/>
                <data android:scheme="http"/>
                <data android:host="youtube.com"/>
                <data android:host="www.youtube.com"/>
                <data android:host="m.youtube.com"/>
                <data android:host="youtu.be"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF
cat > app/src/main/res/drawable/ic_launcher.xml <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="96dp" android:height="96dp" android:viewportWidth="96" android:viewportHeight="96">
    <path android:fillColor="#E62117" android:pathData="M12,28 H84 A8,8 0 0 1 92,36 V60 A8,8 0 0 1 84,68 H12 A8,8 0 0 1 4,60 V36 A8,8 0 0 1 12,28 Z"/>
    <path android:fillColor="#FFFFFF" android:pathData="M40,38 L62,48 L40,58 Z"/>
</vector>
EOF

cat > $J/MainActivity.java <<'EOF'
package com.tabtube.player;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ActivityInfo;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Bundle;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.view.WindowManager;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.Toast;

public class MainActivity extends Activity {
    static final String HOME = "https://m.youtube.com/";
    static final String[] TRUSTED = {"youtube.com", "youtu.be", "google.com", "gstatic.com",
            "ytimg.com", "googlevideo.com", "googleusercontent.com", "ggpht.com", "youtube-nocookie.com"};

    WebView web;
    FrameLayout root;
    View customView;
    WebChromeClient.CustomViewCallback customCb;
    SharedPreferences prefs;
    String mobileUA, desktopUA, lastUrl = HOME;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        prefs = getSharedPreferences("tt", MODE_PRIVATE);
        root = new FrameLayout(this);
        setContentView(root);
        web = new WebView(this);
        root.addView(web, new FrameLayout.LayoutParams(-1, -1));

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setSupportZoom(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
        String ua = s.getUserAgentString();
        mobileUA = ua.replace("; wv", "").replaceAll("Version/\\d+\\.\\d+ ", "");
        String chrome = "100.0.0.0";
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("Chrome/(\\S+)").matcher(ua);
        if (m.find()) chrome = m.group(1);
        desktopUA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/" + chrome + " Safari/537.36";
        applyUA();

        CookieManager cm = CookieManager.getInstance();
        cm.setAcceptCookie(true);
        cm.setAcceptThirdPartyCookies(web, true);

        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                return handle(r.getUrl());
            }

            @Override
            @SuppressWarnings("deprecation")
            public boolean shouldOverrideUrlLoading(WebView v, String url) {
                return handle(Uri.parse(url));
            }

            @Override
            public void onPageStarted(WebView v, String url, Bitmap f) {
                if (url != null && url.startsWith("http")) lastUrl = url;
            }

            @Override
            @SuppressWarnings("deprecation")
            public void onReceivedError(WebView v, int code, String desc, String url) {
                v.loadData("<html><body style='background:#111;color:#eee;font:22px sans-serif;padding:48px'>"
                        + "<h2>Can't load YouTube</h2><p>Check Wi-Fi, then open the menu and tap Reload.</p></body></html>",
                        "text/html", "utf-8");
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onShowCustomView(View v, CustomViewCallback cb) {
                if (customView != null) { cb.onCustomViewHidden(); return; }
                customView = v;
                customCb = cb;
                root.addView(v, new FrameLayout.LayoutParams(-1, -1));
                web.setVisibility(View.GONE);
                if (getActionBar() != null) getActionBar().hide();
                immersive(true);
                setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
            }

            @Override
            public void onHideCustomView() { exitFull(); }

            @Override
            public Bitmap getDefaultVideoPoster() {
                return Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888);
            }
        });

        if (b != null) web.restoreState(b);
        else web.loadUrl(target(getIntent()));
    }

    String target(Intent i) {
        Uri d = i == null ? null : i.getData();
        if (d == null || d.getHost() == null) return HOME;
        String host = d.getHost();
        if (host.equals("youtu.be")) {
            String id = d.getLastPathSegment();
            return id == null ? HOME : "https://m.youtube.com/watch?v=" + id;
        }
        return d.toString();
    }

    boolean handle(Uri u) {
        String scheme = u.getScheme(), host = u.getHost();
        if (scheme != null && (scheme.equals("http") || scheme.equals("https")) && host != null) {
            for (String t : TRUSTED) if (host.equals(t) || host.endsWith("." + t)) return false;
        }
        try { startActivity(new Intent(Intent.ACTION_VIEW, u)); } catch (ActivityNotFoundException e) { }
        return true;
    }

    boolean desktop() { return prefs.getBoolean("desktop", false); }

    void applyUA() {
        WebSettings s = web.getSettings();
        s.setUserAgentString(desktop() ? desktopUA : mobileUA);
        s.setUseWideViewPort(desktop());
        s.setLoadWithOverviewMode(desktop());
    }

    @SuppressWarnings("deprecation")
    void immersive(boolean on) {
        getWindow().getDecorView().setSystemUiVisibility(on
                ? View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                : View.SYSTEM_UI_FLAG_VISIBLE);
    }

    void exitFull() {
        if (customView == null) return;
        root.removeView(customView);
        customView = null;
        web.setVisibility(View.VISIBLE);
        if (customCb != null) customCb.onCustomViewHidden();
        if (getActionBar() != null) getActionBar().show();
        immersive(false);
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        menu.add(0, 1, 0, "Home").setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM);
        menu.add(0, 2, 1, "Reload").setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM);
        menu.add(0, 3, 2, "Desktop site").setCheckable(true).setChecked(desktop());
        menu.add(0, 4, 3, "Copy link");
        menu.add(0, 5, 4, "Open in browser");
        menu.add(0, 6, 5, "Clear data & cookies");
        menu.add(0, 7, 6, "Quit");
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem it) {
        switch (it.getItemId()) {
            case 1: web.loadUrl(desktop() ? "https://www.youtube.com/" : HOME); return true;
            case 2: web.loadUrl(lastUrl); return true;
            case 3:
                prefs.edit().putBoolean("desktop", !desktop()).apply();
                it.setChecked(desktop());
                applyUA();
                String u = lastUrl;
                u = desktop() ? u.replace("//m.youtube.com", "//www.youtube.com") : u.replace("//www.youtube.com", "//m.youtube.com");
                web.loadUrl(u);
                return true;
            case 4:
                ((ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("link", lastUrl));
                Toast.makeText(this, "Link copied", Toast.LENGTH_SHORT).show();
                return true;
            case 5:
                try { startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(lastUrl))); } catch (ActivityNotFoundException e) { }
                return true;
            case 6:
                CookieManager.getInstance().removeAllCookies(null);
                web.clearCache(true);
                web.clearHistory();
                Toast.makeText(this, "Cleared", Toast.LENGTH_SHORT).show();
                web.loadUrl(HOME);
                return true;
            case 7: finish(); return true;
        }
        return super.onOptionsItemSelected(it);
    }

    @Override
    protected void onNewIntent(Intent i) {
        super.onNewIntent(i);
        setIntent(i);
        web.loadUrl(target(i));
    }

    @Override
    protected void onSaveInstanceState(Bundle b) {
        super.onSaveInstanceState(b);
        web.saveState(b);
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        if (customView != null) exitFull();
        else if (web.canGoBack()) web.goBack();
        else super.onBackPressed();
    }

    @Override
    protected void onDestroy() {
        if (web != null) { root.removeAllViews(); web.destroy(); }
        super.onDestroy();
    }
}
EOF

gradle assembleDebug --no-daemon --console=plain
