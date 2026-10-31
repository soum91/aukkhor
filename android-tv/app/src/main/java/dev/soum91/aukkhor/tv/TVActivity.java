package dev.soum91.aukkhor.tv;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.StateListDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.inputmethod.InputMethodManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.Enumeration;

/**
 * Remote-friendly setup UI. All controls have content-sized height in dp,
 * not fixed pixel heights (which clipped text on high-density Google TVs).
 * Displays the pairing secret only on the local TV display.
 */
public final class TVActivity extends Activity {
    private static final int BG = Color.rgb(10, 19, 33);
    private static final int PANEL = Color.rgb(19, 34, 53);
    private static final int FG = Color.rgb(237, 246, 255);
    private static final int MUTED = Color.rgb(176, 196, 212);
    private static final int ACCENT = Color.rgb(103, 220, 232);
    private static final int GOLD = Color.rgb(255, 203, 117);
    private TextView status, deviceCode, fingerprint, ipAddress, keyboardState;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable refresh = new Runnable() {
        @Override public void run() {
            update();
            handler.postDelayed(this, 2000);
        }
    };

    private int dp(float v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }

    private GradientDrawable panelBackground() {
        GradientDrawable d = new GradientDrawable();
        d.setColor(PANEL);
        d.setCornerRadius(dp(17));
        d.setStroke(dp(1), Color.rgb(42, 65, 86));
        return d;
    }

    private GradientDrawable buttonBackground(int color, int stroke) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(dp(11));
        d.setStroke(dp(2), stroke);
        return d;
    }

    private StateListDrawable buttonStates() {
        StateListDrawable states = new StateListDrawable();
        states.addState(new int[] { android.R.attr.state_focused },
            buttonBackground(Color.rgb(27, 111, 170), ACCENT));
        states.addState(new int[] { android.R.attr.state_pressed },
            buttonBackground(Color.rgb(25, 97, 145), ACCENT));
        states.addState(new int[] {},
            buttonBackground(Color.rgb(31, 55, 82), Color.rgb(63, 89, 118)));
        return states;
    }

    private TextView text(LinearLayout into, String value, int sp, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextColor(color);
        view.setTextSize(sp);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        view.setIncludeFontPadding(true);
        view.setGravity(Gravity.START | Gravity.CENTER_VERTICAL);
        view.setLineSpacing(dp(2), 1.08f);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(9);
        into.addView(view, lp);
        return view;
    }

    private void action(LinearLayout into, String label, Runnable callback) {
        Button b = new Button(this);
        b.setAllCaps(false);
        b.setText(label);
        b.setTextSize(16);
        b.setTextColor(Color.WHITE);
        b.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        b.setGravity(Gravity.CENTER_VERTICAL | Gravity.START);
        b.setBackground(buttonStates());
        b.setMinHeight(dp(54));
        b.setMinimumHeight(dp(54));
        b.setPadding(dp(17), dp(13), dp(17), dp(13));
        b.setSingleLine(false);
        b.setFocusable(true);
        b.setOnClickListener(v -> callback.run());
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(11);
        into.addView(b, lp);
    }

    private LinearLayout panel() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(23), dp(21), dp(23), dp(18));
        box.setBackground(panelBackground());
        return box;
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);

        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(BG);
        scroll.setFillViewport(true);
        scroll.setClipToPadding(false);

        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(dp(30), dp(22), dp(30), dp(25));
        scroll.addView(page);
        setContentView(scroll);

        text(page, "Aukkhor  ·  অক্ষর", 32, ACCENT, true);
        text(page, "Use your iPhone keyboard to type on Google TV", 17, MUTED, false);

        LinearLayout cards = new LinearLayout(this);
        int widthDp = (int)(getResources().getDisplayMetrics().widthPixels /
                            getResources().getDisplayMetrics().density);
        boolean twoColumns = widthDp >= 720;
        cards.setOrientation(twoColumns ? LinearLayout.HORIZONTAL : LinearLayout.VERTICAL);
        LinearLayout.LayoutParams row = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        row.topMargin = dp(12);
        page.addView(cards, row);

        LinearLayout setup = panel();
        LinearLayout pairing = panel();
        if (twoColumns) {
            LinearLayout.LayoutParams left = new LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 0.85f);
            left.rightMargin = dp(17);
            cards.addView(setup, left);
            cards.addView(pairing, new LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.15f));
        } else {
            LinearLayout.LayoutParams top = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            top.bottomMargin = dp(15);
            cards.addView(setup, top);
            cards.addView(pairing, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        }

        text(setup, "1  Set up TV keyboard", 21, FG, true);
        status = text(setup, "Starting receiver…", 15, GOLD, false);
        keyboardState = text(setup, "Checking keyboard selection…", 15, MUTED, false);
        action(setup, "Start receiver", this::startReceiver);
        action(setup, "Enable keyboard in TV Settings", () -> {
            startActivity(new Intent(Settings.ACTION_INPUT_METHOD_SETTINGS));
        });
        action(setup, "Select Aukkhor TV keyboard", () -> {
            InputMethodManager imm =
                (InputMethodManager)getSystemService(INPUT_METHOD_SERVICE);
            if (imm != null) imm.showInputMethodPicker();
        });
        text(setup, "Select Aukkhor as the TV input method. You can also type with the TV remote.",
            14, MUTED, false);

        text(pairing, "2  Pair your iPhone directly", 21, FG, true);
        text(pairing, "Windows is NOT needed. Connect both devices to the same reachable local network.",
            15, MUTED, false);
        text(pairing, "TV IP ADDRESS", 13, ACCENT, true);
        ipAddress = text(pairing, "Checking network…", 21, FG, true);
        text(pairing, "SIX-DIGIT PAIRING CODE", 13, ACCENT, true);
        deviceCode = text(pairing, "…", 29, FG, true);
        text(pairing, "CERTIFICATE FINGERPRINT (SHA-256)", 13, ACCENT, true);
        fingerprint = text(pairing, "Starting secure receiver…", 13, FG, false);
        fingerprint.setTypeface(Typeface.MONOSPACE);
        fingerprint.setTextIsSelectable(false);
        action(pairing, "Generate new pairing code", () -> {
            TVBridgeService s = TVBridgeService.instance();
            if (s != null && s.bridge() != null) {
                s.bridge().resetPairing();
                update();
            }
        });
        text(pairing,
            "On iPhone: Open Aukkhor → Android TV. Enter the IP address, full fingerprint and code shown here, then tap Pair Android TV.",
            14, MUTED, false);

        LinearLayout hint = panel();
        LinearLayout.LayoutParams hintLp = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        hintLp.topMargin = dp(17);
        page.addView(hint, hintLp);
        text(hint, "How typing works", 17, ACCENT, true);
        text(hint,
            "Open a regular text field on the TV. Keep the Aukkhor app open on your iPhone to receive its typing prompt. Password fields are not remotely typed. iOS cannot reliably wake a suspended app from local Wi-Fi alone.",
            15, MUTED, false);

        startReceiver();
    }

    private void startReceiver() {
        if (TVBridgeService.instance() == null) {
            Intent service = new Intent(this, TVBridgeService.class);
            try {
                startForegroundService(service);
                status.setText("Starting receiver…");
            } catch (RuntimeException e) {
                status.setText("Could not start receiver: " + e.getMessage());
            }
        }
        handler.postDelayed(this::update, 500);
    }

    private String localAddress() {
        try {
            Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
            while (interfaces.hasMoreElements()) {
                NetworkInterface nic = interfaces.nextElement();
                if (!nic.isUp() || nic.isLoopback()) continue;
                Enumeration<InetAddress> addresses = nic.getInetAddresses();
                while (addresses.hasMoreElements()) {
                    InetAddress address = addresses.nextElement();
                    if (address instanceof Inet4Address && address.isSiteLocalAddress())
                        return address.getHostAddress();
                }
            }
        } catch (Exception ignored) { }
        return "No private IPv4 address found";
    }

    private String compactFingerprint(String raw) {
        if (raw == null) return "";
        String value = raw.replace(":", "").trim();
        if (value.length() != 64) return raw;
        return value.substring(0, 32) + "\n" + value.substring(32);
    }

    private void update() {
        if (isFinishing() || isDestroyed()) return;
        TVBridgeService service = TVBridgeService.instance();
        TVBridgeServer bridge = service == null ? null : service.bridge();
        ipAddress.setText(localAddress() + "  (port " + TVBridgeServer.PORT + ")");
        String currentIME = Settings.Secure.getString(getContentResolver(),
            Settings.Secure.DEFAULT_INPUT_METHOD);
        boolean selected = currentIME != null &&
            currentIME.startsWith(getPackageName() + "/");
        keyboardState.setText(selected
            ? "✓ Aukkhor TV keyboard selected"
            : "Keyboard not selected. Use the buttons below.");
        keyboardState.setTextColor(selected ? ACCENT : GOLD);
        if (bridge == null) {
            status.setText("Receiver unavailable" +
                (service == null ? "" : ": " + service.error()));
            deviceCode.setText("Start receiver first");
            fingerprint.setText("");
            return;
        }
        status.setText("✓ Receiver running");
        deviceCode.setText(bridge.pairingCode());
        try {
            fingerprint.setText(compactFingerprint(bridge.fingerprint()));
        } catch (Exception e) {
            fingerprint.setText("Certificate unavailable: " + e.getMessage());
        }
    }

    @Override public void onResume() {
        super.onResume();
        handler.removeCallbacks(refresh);
        handler.post(refresh);
    }
    @Override public void onPause() {
        handler.removeCallbacks(refresh);
        super.onPause();
    }
}
