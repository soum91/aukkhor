package dev.soum91.aukkhor.tv;

import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.StateListDrawable;
import android.inputmethodservice.InputMethodService;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/** Android TV input method, operable with only a directional remote and OK. */
public final class AukkhorIME extends InputMethodService {
    private static final int BACKGROUND = Color.rgb(14, 24, 43);
    private static final int KEY_COLOR = Color.rgb(34, 52, 83);
    private static final int FOCUS_COLOR = Color.rgb(29, 103, 149);
    private static final int ACCENT = Color.rgb(135, 215, 255);
    private static final String[][] ENGLISH = {
        {"q", "w", "e", "r", "t", "y", "u", "i", "o", "p"},
        {"a", "s", "d", "f", "g", "h", "j", "k", "l"},
        {"z", "x", "c", "v", "b", "n", "m"}
    };
    private static final String[][] CONSONANTS = {
        {"ক", "খ", "গ", "ঘ", "ঙ", "চ", "ছ", "জ", "ঝ", "ঞ"},
        {"ট", "ঠ", "ড", "ঢ", "ণ", "ত", "থ", "দ", "ধ", "ন"},
        {"প", "ফ", "ব", "ভ", "ম", "য", "র", "ল", "শ", "স", "ষ", "হ"}
    };
    private static final String[][] VOWELS = {
        {"অ", "আ", "ই", "ঈ", "উ", "ঊ", "ঋ", "এ", "ঐ", "ও", "ঔ"},
        {"া", "ি", "ী", "ু", "ূ", "ৃ", "ে", "ৈ", "ো", "ৌ", "্"},
        {"ং", "ঃ", "ঁ", "ৎ", "ড়", "ঢ়", "য়", "০", "১", "২"}
    };
    private static final String[][] SYMBOLS = {
        {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0"},
        {"@", "#", "$", "%", "&", "-", "+", "(", ")", "/"},
        {"*", "\"", ":", ";", "!", "?", "'", ",", ".", "_"}
    };

    private int mode; // 0 English; 1 phonetic Bangla; 2 direct Bangla
    private boolean shifted;
    private boolean symbols;
    private boolean vowels;
    private String phoneticBuffer = "";
    private String phoneticRendered = "";
    private LinearLayout root;
    private EditorInfo currentEditor;
    private final List<List<Button>> focusRows = new ArrayList<>();
    private int focusRow = 0;
    private int focusColumn = 0;
    private final Handler repeatHandler = new Handler(Looper.getMainLooper());
    private boolean deletingHeld;
    private final Runnable repeatDelete = new Runnable() {
        @Override public void run() {
            if (!deletingHeld) return;
            erase();
            repeatHandler.postDelayed(this, 50);
        }
    };

    private int dp(float value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    @Override public boolean onEvaluateFullscreenMode() {
        // Landscape TV text fields must stay visible above the keyboard.
        return false;
    }

    @Override public void onStartInput(EditorInfo info, boolean restarting) {
        super.onStartInput(info, restarting);
        currentEditor = info;
        clearBuffer();
        int kind = info.inputType & InputType.TYPE_MASK_CLASS;
        symbols = kind == InputType.TYPE_CLASS_NUMBER || kind == InputType.TYPE_CLASS_PHONE;
        TVBridgeService bridge = TVBridgeService.instance();
        if (bridge != null) bridge.editorOpened(this, info);
    }

    @Override public void onStartInputView(EditorInfo info, boolean restarting) {
        super.onStartInputView(info, restarting);
        currentEditor = info;
        TVBridgeService bridge = TVBridgeService.instance();
        if (bridge != null) bridge.editorOpened(this, info);
        render();
    }

    @Override public void onFinishInput() {
        stopDelete();
        clearBuffer();
        currentEditor = null;
        TVBridgeService bridge = TVBridgeService.instance();
        if (bridge != null) bridge.editorClosed(this);
        super.onFinishInput();
    }

    @Override public void onDestroy() {
        stopDelete();
        super.onDestroy();
    }

    @Override public void onConfigurationChanged(Configuration configuration) {
        super.onConfigurationChanged(configuration);
        render();
    }

    @Override public View onCreateInputView() {
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(12), dp(8), dp(12), dp(12));
        root.setBackgroundColor(BACKGROUND);
        render();
        return root;
    }

    private static GradientDrawable background(int color, int border) {
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(color);
        shape.setCornerRadius(13);
        shape.setStroke(2, border);
        return shape;
    }

    private StateListDrawable keyBackground() {
        StateListDrawable states = new StateListDrawable();
        states.addState(new int[]{android.R.attr.state_focused}, background(FOCUS_COLOR, ACCENT));
        states.addState(new int[]{android.R.attr.state_pressed}, background(FOCUS_COLOR, ACCENT));
        states.addState(new int[]{}, background(KEY_COLOR, Color.rgb(67, 90, 126)));
        return states;
    }

    private Button key(String label, float weight, int row, int col, Runnable action) {
        Button button = new Button(this);
        button.setId(View.generateViewId());
        button.setText(label);
        button.setAllCaps(false);
        button.setTextColor(Color.WHITE);
        button.setTextSize(label.length() > 6 ? 14 : 20);
        button.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        button.setBackground(keyBackground());
        button.setFocusable(true);
        button.setMinHeight(0);
        button.setMinimumHeight(0);
        button.setPadding(dp(2), 0, dp(2), 0);
        button.setOnClickListener(v -> {
            focusRow = row;
            focusColumn = col;
            action.run();
        });
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, dp(54), weight);
        params.setMargins(dp(3), dp(3), dp(3), dp(3));
        button.setLayoutParams(params);
        return button;
    }

    private void appendRow(String[][] layout, int index) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER);
        List<Button> items = new ArrayList<>();
        int rowIndex = focusRows.size();
        for (String symbol : layout[index]) {
            final int column = items.size();
            String display = mode == 0 && !symbols && shifted
                ? symbol.toUpperCase(Locale.ROOT) : symbol;
            Button button = key(display, 1, rowIndex, column, () -> typeSymbol(symbol));
            row.addView(button);
            items.add(button);
        }
        root.addView(row);
        focusRows.add(items);
    }

    private void addControl(LinearLayout row, List<Button> items, String label,
                            float weight, Runnable action) {
        int rowIndex = focusRows.size();
        Button button = key(label, weight, rowIndex, items.size(), action);
        row.addView(button);
        items.add(button);
        if ("⌫".equals(label)) installDeleteRepeat(button);
    }

    private static int nearest(int index, int sourceCount, int targetCount) {
        if (sourceCount <= 1 || targetCount <= 1) return 0;
        return Math.min(targetCount - 1,
            Math.round(index * (targetCount - 1f) / (sourceCount - 1f)));
    }

    private void connectDirectionalFocus() {
        for (int r = 0; r < focusRows.size(); r++) {
            List<Button> row = focusRows.get(r);
            for (int c = 0; c < row.size(); c++) {
                Button button = row.get(c);
                button.setNextFocusLeftId(row.get(Math.max(0, c - 1)).getId());
                button.setNextFocusRightId(row.get(Math.min(row.size() - 1, c + 1)).getId());
                int up = Math.max(0, r - 1);
                int down = Math.min(focusRows.size() - 1, r + 1);
                button.setNextFocusUpId(focusRows.get(up).get(
                    nearest(c, row.size(), focusRows.get(up).size())).getId());
                button.setNextFocusDownId(focusRows.get(down).get(
                    nearest(c, row.size(), focusRows.get(down).size())).getId());
            }
        }
    }

    private void render() {
        if (root == null) return;
        stopDelete();
        root.removeAllViews();
        focusRows.clear();
        TextView hint = new TextView(this);
        hint.setTextColor(ACCENT);
        hint.setTextSize(15);
        hint.setGravity(Gravity.CENTER);
        hint.setText("Aukkhor TV    •    D-pad to navigate, OK to type    •    Pair iPhone in the app");
        root.addView(hint, new LinearLayout.LayoutParams(-1, dp(38)));

        if (getSharedPreferences("aukkhor_tv_ui", Context.MODE_PRIVATE)
                .getBoolean("number_row", false) && !symbols) {
            appendRow(SYMBOLS, 0);
        }
        String[][] layout = symbols ? SYMBOLS
            : mode == 2 ? (vowels ? VOWELS : CONSONANTS) : ENGLISH;
        for (int row = 0; row < layout.length; row++) appendRow(layout, row);

        LinearLayout controls = new LinearLayout(this);
        controls.setOrientation(LinearLayout.HORIZONTAL);
        List<Button> items = new ArrayList<>();
        addControl(controls, items, mode == 0 ? "EN" : mode == 1 ? "বাংলা Ph" : "বাংলা",
            2, () -> { finishPhonetic(); mode = (mode + 1) % 3; shifted = false; render(); });
        addControl(controls, items, symbols ? "ABC" : "123", 2,
            () -> { finishPhonetic(); symbols = !symbols; render(); });
        addControl(controls, items, mode == 2 && !symbols ? (vowels ? "ব্যঞ্জন" : "স্বর") : "⇧",
            2, () -> {
                finishPhonetic();
                if (mode == 2 && !symbols) vowels = !vowels;
                else shifted = !shifted;
                render();
            });
        addControl(controls, items, "Space", 5, () -> { finishPhonetic(); commit(" "); });
        addControl(controls, items, "⌫", 2, this::erase);
        int action = currentEditor == null ? EditorInfo.IME_ACTION_UNSPECIFIED
            : currentEditor.imeOptions & EditorInfo.IME_MASK_ACTION;
        String enterLabel = action == EditorInfo.IME_ACTION_SEARCH ? "Search"
            : action == EditorInfo.IME_ACTION_NEXT ? "Next"
            : action == EditorInfo.IME_ACTION_GO ? "Go" : "↵";
        addControl(controls, items, enterLabel, 2, this::enter);
        root.addView(controls);
        focusRows.add(items);

        connectDirectionalFocus();
        if (!focusRows.isEmpty()) {
            int requestedRow = Math.min(focusRow, focusRows.size() - 1);
            List<Button> requested = focusRows.get(requestedRow);
            Button focused = requested.get(Math.min(focusColumn, requested.size() - 1));
            root.post(focused::requestFocus);
        }
    }

    private void typeSymbol(String symbol) {
        if (mode == 1 && !symbols) {
            appendPhonetic(symbol);
        } else {
            finishPhonetic();
            commit(mode == 0 && !symbols && shifted ? symbol.toUpperCase(Locale.ROOT) : symbol);
        }
        if (shifted && mode == 0 && !symbols) {
            shifted = false;
            render();
        }
    }

    private void commit(String value) {
        InputConnection connection = getCurrentInputConnection();
        if (connection != null) connection.commitText(value, 1);
    }

    /** Text from the authenticated iPhone bridge must not join phonetic composition. */
    boolean commitRemoteText(String text) {
        finishPhonetic();
        InputConnection connection = getCurrentInputConnection();
        return connection != null && connection.commitText(text, 1);
    }

    private void clearBuffer() {
        phoneticBuffer = "";
        phoneticRendered = "";
    }

    private void finishPhonetic() {
        if (!phoneticBuffer.isEmpty()) {
            InputConnection connection = getCurrentInputConnection();
            if (connection != null) connection.finishComposingText();
        }
        clearBuffer();
    }

    private void renderPhonetic() {
        InputConnection connection = getCurrentInputConnection();
        if (connection == null) return;
        String next = PhoneticBangla.transliterate(phoneticBuffer);
        if (!connection.setComposingText(next, 1)) {
            if (!phoneticRendered.isEmpty())
                connection.deleteSurroundingText(phoneticRendered.length(), 0);
            if (!next.isEmpty()) connection.commitText(next, 1);
        }
        phoneticRendered = next;
        if (phoneticBuffer.isEmpty()) connection.finishComposingText();
    }

    private void appendPhonetic(String roman) {
        phoneticBuffer += roman.toLowerCase(Locale.ROOT);
        renderPhonetic();
    }

    private void erase() {
        if (mode == 1 && !symbols && !phoneticBuffer.isEmpty()) {
            phoneticBuffer = phoneticBuffer.substring(0, phoneticBuffer.length() - 1);
            renderPhonetic();
            return;
        }
        InputConnection connection = getCurrentInputConnection();
        if (connection == null) return;
        if (!connection.deleteSurroundingTextInCodePoints(1, 0))
            connection.deleteSurroundingText(1, 0);
    }

    private void enter() {
        finishPhonetic();
        InputConnection connection = getCurrentInputConnection();
        if (connection == null) return;
        int action = currentEditor == null ? EditorInfo.IME_ACTION_UNSPECIFIED
            : currentEditor.imeOptions & EditorInfo.IME_MASK_ACTION;
        boolean multiline = currentEditor != null &&
            (currentEditor.inputType & InputType.TYPE_TEXT_FLAG_MULTI_LINE) != 0;
        boolean noEnterAction = currentEditor != null &&
            (currentEditor.imeOptions & EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0;
        if (!multiline && !noEnterAction && action != EditorInfo.IME_ACTION_NONE &&
                action != EditorInfo.IME_ACTION_UNSPECIFIED) {
            if (connection.performEditorAction(action)) return;
        }
        connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER));
        connection.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER));
    }

    private void startDelete() {
        if (deletingHeld) return;
        deletingHeld = true;
        erase();
        repeatHandler.postDelayed(repeatDelete, 330);
    }

    private void stopDelete() {
        deletingHeld = false;
        repeatHandler.removeCallbacks(repeatDelete);
    }

    private void installDeleteRepeat(Button button) {
        button.setOnKeyListener((view, keyCode, event) -> {
            if (keyCode != KeyEvent.KEYCODE_DPAD_CENTER && keyCode != KeyEvent.KEYCODE_ENTER &&
                    keyCode != KeyEvent.KEYCODE_NUMPAD_ENTER) return false;
            if (event.getAction() == KeyEvent.ACTION_DOWN) startDelete();
            if (event.getAction() == KeyEvent.ACTION_UP) stopDelete();
            return true;
        });
        button.setOnTouchListener((view, event) -> {
            if (event.getActionMasked() == MotionEvent.ACTION_DOWN) startDelete();
            if (event.getActionMasked() == MotionEvent.ACTION_UP ||
                    event.getActionMasked() == MotionEvent.ACTION_CANCEL) stopDelete();
            return true;
        });
        button.setOnFocusChangeListener((view, hasFocus) -> {
            if (!hasFocus) stopDelete();
        });
    }

    @Override public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_DEL) {
            erase();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }
}
