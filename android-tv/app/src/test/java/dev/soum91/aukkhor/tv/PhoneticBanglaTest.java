package dev.soum91.aukkhor.tv;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

/** Runs on the build server without an emulator or device. */
public final class PhoneticBanglaTest {
    @Test public void commonWordsUseBanglaSpellings() {
        assertEquals("আমি", PhoneticBangla.transliterate("ami"));
        assertEquals("তুমি", PhoneticBangla.transliterate("tumi"));
        assertEquals("বাংলা", PhoneticBangla.transliterate("bangla"));
        assertEquals("ধন্যবাদ", PhoneticBangla.transliterate("dhonnobad"));
    }

    @Test public void romanInputIsCaseIndependent() {
        assertEquals("অক্ষর", PhoneticBangla.transliterate("AUKKHOR"));
        assertEquals("খ", PhoneticBangla.transliterate("kh"));
        assertEquals("ক", PhoneticBangla.transliterate("k"));
    }

    @Test public void removingRomanLettersRestoresEarlierTransliteration() {
        assertEquals("খ", PhoneticBangla.transliterate("kh"));
        assertEquals("ক", PhoneticBangla.transliterate("k"));
        assertEquals("", PhoneticBangla.transliterate(""));
    }
}
