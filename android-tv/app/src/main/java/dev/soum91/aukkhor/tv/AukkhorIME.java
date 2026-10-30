package dev.soum91.aukkhor.tv;

import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.inputmethodservice.InputMethodService;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Native D-pad navigable Android TV IME. InputConnection handles all committed text. */
public final class AukkhorIME extends InputMethodService {
    private int mode=0; // English, phonetic Bangla, direct Bangla
    private boolean shifted=false, symbols=false;
    private String phoneticBuffer="", phoneticRendered="";
    private final String[] qwerty={"QWERTYUIOP","ASDFGHJKL","ZXCVBNM"};
    private final String[] nativeBangla={"ৌৈাীূবহগদজড","োে্িুপর্কতচট","ংমনলসযষশড়"};
    private LinearLayout root;
    private TextView hint;

    @Override public void onStartInput(EditorInfo info, boolean restarting) {
        super.onStartInput(info,restarting);
        phoneticBuffer="";
        phoneticRendered="";
        TVBridgeService bridge=TVBridgeService.instance();
        if(bridge!=null) bridge.editorOpened(this,info);
    }
    @Override public void onStartInputView(EditorInfo info, boolean restarting) {
        super.onStartInputView(info,restarting);
        TVBridgeService bridge=TVBridgeService.instance();
        if(bridge!=null) bridge.editorOpened(this,info);
        render();
    }
    @Override public void onFinishInput() {
        TVBridgeService bridge=TVBridgeService.instance();
        if(bridge!=null) bridge.editorClosed(this);
        super.onFinishInput();
    }
    @Override public View onCreateInputView() {
        root=new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(12,10,12,12);
        root.setBackgroundColor(Color.rgb(14,24,43));
        render();
        return root;
    }
    private static GradientDrawable keyBackground(int color) {
        GradientDrawable bg=new GradientDrawable();
        bg.setColor(color);
        bg.setCornerRadius(13);
        bg.setStroke(1,Color.rgb(67,90,126));
        return bg;
    }
    private Button key(String text,int weight,Runnable action) {
        Button b=new Button(this);
        b.setText(text);
        b.setAllCaps(false);
        b.setTextColor(Color.WHITE);
        b.setTextSize(text.length()>6?14:20);
        b.setTypeface(Typeface.DEFAULT,Typeface.BOLD);
        b.setBackground(keyBackground(Color.rgb(34,52,83)));
        b.setFocusable(true);
        b.setOnClickListener(v->action.run());
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(0,57,weight);
        lp.setMargins(3,3,3,3);
        b.setLayoutParams(lp);
        return b;
    }
    private void commit(String value) {
        InputConnection connection=getCurrentInputConnection();
        if(connection!=null)connection.commitText(value,1);
    }
    private void clearPhonetic() {
        phoneticBuffer="";
        phoneticRendered="";
    }
    private void appendPhonetic(String roman) {
        InputConnection c=getCurrentInputConnection();
        if(c==null)return;
        phoneticBuffer+=roman.toLowerCase();
        String next=PhoneticBangla.transliterate(phoneticBuffer);
        if(!phoneticRendered.isEmpty())c.deleteSurroundingText(phoneticRendered.length(),0);
        c.commitText(next,1);
        phoneticRendered=next;
    }
    private void erase() {
        if(mode==1 && !symbols && !phoneticBuffer.isEmpty()){
            InputConnection c=getCurrentInputConnection();
            if(c==null)return;
            phoneticBuffer=phoneticBuffer.substring(0,phoneticBuffer.length()-1);
            if(!phoneticRendered.isEmpty())c.deleteSurroundingText(phoneticRendered.length(),0);
            String next=PhoneticBangla.transliterate(phoneticBuffer);
            if(!next.isEmpty())c.commitText(next,1);
            phoneticRendered=next;
            return;
        }
        InputConnection connection=getCurrentInputConnection();
        if(connection!=null) connection.deleteSurroundingTextInCodePoints(1,0);
    }
    private void render() {
        if(root==null)return;
        root.removeAllViews();
        hint=new TextView(this);
        hint.setTextColor(Color.rgb(135,215,255));
        hint.setTextSize(16);
        hint.setGravity(Gravity.CENTER);
        hint.setText("Aukkhor TV   •   Select a text field   •   Type on iPhone when paired");
        root.addView(hint,new LinearLayout.LayoutParams(-1,44));
        for(int index=0;index<3;index++){
            LinearLayout row=new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setGravity(Gravity.CENTER);
            String letters = symbols ? (index==0?"1234567890":index==1?"@#$%&*-+":"?!.,:/()") :
                mode==2?nativeBangla[index]:qwerty[index];
            for(int n=0;n<letters.length();n++) {
                String letter=String.valueOf(letters.charAt(n));
                row.addView(key(shifted?letter.toUpperCase():letter,1,()->{
                    if(mode==1 && !symbols)appendPhonetic(letter);
                    else commit(shifted?letter.toUpperCase():letter.toLowerCase());
                }));
            }
            root.addView(row,new LinearLayout.LayoutParams(-1,63));
        }
        LinearLayout controls=new LinearLayout(this);
        controls.setOrientation(LinearLayout.HORIZONTAL);
        controls.addView(key(mode==0?"EN":mode==1?"বাংলা Ph":"বাংলা",2,()->{
            clearPhonetic(); mode=(mode+1)%3;render();
        }));
        controls.addView(key(symbols?"ABC":"123",2,()->{clearPhonetic();symbols=!symbols;render();}));
        controls.addView(key("⇧",1,()->{shifted=!shifted;render();}));
        controls.addView(key("Space",5,()->{clearPhonetic();commit(" ");}));
        controls.addView(key("⌫",2,this::erase));
        controls.addView(key("↵",2,()->{
            clearPhonetic();
            InputConnection c=getCurrentInputConnection();
            if(c!=null)c.performEditorAction(EditorInfo.IME_ACTION_DONE);
        }));
        root.addView(controls,new LinearLayout.LayoutParams(-1,65));
    }
}
