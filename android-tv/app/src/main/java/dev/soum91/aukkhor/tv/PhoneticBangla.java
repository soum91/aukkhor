package dev.soum91.aukkhor.tv;

import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

/** Lightweight transliteration with first-pass Bengali conjunct rules. */
final class PhoneticBangla {
    private static final Map<String,String> WORDS=new LinkedHashMap<>();
    private static final String[][] CONSONANTS={
        {"kksh","ক্ষ"},{"chh","ছ"},{"kkh","ক্ষ"},{"ksh","ক্ষ"},
        {"ng","ং"},{"kh","খ"},{"gh","ঘ"},{"ch","চ"},{"jh","ঝ"},
        {"th","থ"},{"dh","ধ"},{"ph","ফ"},{"bh","ভ"},{"sh","শ"},
        {"ss","ষ"},{"rr","ড়"},{"ny","ঞ"},{"tt","ট"},{"dd","ড"},
        {"k","ক"},{"g","গ"},{"c","ক"},{"j","জ"},{"t","ত"},{"d","দ"},
        {"n","ন"},{"p","প"},{"f","ফ"},{"b","ব"},{"m","ম"},
        {"r","র"},{"l","ল"},{"s","স"},{"h","হ"},{"y","য"},
        {"w","ও"},{"v","ভ"},{"z","জ"}
    };
    private static final String[][] VOWELS={
        {"aa","আ","া"},{"ee","ঈ","ী"},{"ii","ঈ","ী"},{"uu","ঊ","ূ"},
        {"oo","উ","ু"},{"oi","ঐ","ৈ"},{"ou","ঔ","ৌ"},
        {"a","আ","া"},{"i","ই","ি"},{"u","উ","ু"},
        {"e","এ","ে"},{"o","অ","ো"}
    };
    static {
        WORDS.put("ami","আমি");WORDS.put("tumi","তুমি");
        WORDS.put("bangla","বাংলা");WORDS.put("bhalo","ভালো");
        WORDS.put("shubho","শুভ");WORDS.put("shokal","সকাল");
        WORDS.put("dhonnobad","ধন্যবাদ");
        WORDS.put("okkhor","অক্ষর");WORDS.put("akkhor","অক্ষর");
        WORDS.put("aukkhor","অক্ষর");WORDS.put("akshor","অক্ষর");
    }
    private PhoneticBangla(){}
    static String transliterate(String text) {
        String input=text.toLowerCase(Locale.ROOT);
        String exact=WORDS.get(input);
        if(exact!=null)return exact;
        StringBuilder out=new StringBuilder();
        boolean prevConsonant=false;
        for(int i=0;i<input.length();){
            boolean matched=false;
            for(String[] vowel:VOWELS)if(input.startsWith(vowel[0],i)){
                out.append(prevConsonant?vowel[2]:vowel[1]);
                prevConsonant=false;
                i+=vowel[0].length();
                matched=true;break;
            }
            if(matched)continue;
            for(String[] consonant:CONSONANTS)if(input.startsWith(consonant[0],i)){
                if(prevConsonant && !consonant[1].equals("ং"))out.append("্");
                out.append(consonant[1]);
                prevConsonant=!consonant[1].equals("ং");
                i+=consonant[0].length();
                matched=true;break;
            }
            if(matched)continue;
            out.append(input.charAt(i++));
            prevConsonant=false;
        }
        return out.toString();
    }
}
