import QtQuick
import QtQuick.Layouts

PageFrame {
    id: p
    icon: "icons/keyboard.svg"
    title: "Select Your Keyboard"
    subtitle: "Choose the layout that matches the keys on your keyboard."
    canContinue: Inst.keymap !== ""
    firstFocus: list.searchField

    property var guessFor: ({ "en_US": "us", "en_GB": "gb", "en_IE": "ie", "en_CA": "us", "en_AU": "us", "de_DE": "de", "de_AT": "at", "de_CH": "ch",
                              "fr_FR": "fr", "fr_BE": "be", "fr_CA": "ca", "fr_CH": "ch", "es_ES": "es", "es_MX": "latam", "es_AR": "latam",
                              "it_IT": "it", "pt_PT": "pt", "pt_BR": "br", "nl_NL": "us", "nl_BE": "be", "da_DK": "dk", "nb_NO": "no", "nn_NO": "no",
                              "sv_SE": "se", "fi_FI": "fi", "pl_PL": "pl", "cs_CZ": "cz", "sk_SK": "sk", "hu_HU": "hu", "ro_RO": "ro", "ru_RU": "ru",
                              "uk_UA": "ua", "tr_TR": "tr", "el_GR": "gr", "ja_JP": "jp", "ko_KR": "kr", "is_IS": "is", "et_EE": "ee", "lt_LT": "lt",
                              "lv_LV": "lv", "sl_SI": "si", "hr_HR": "hr", "bg_BG": "bg", "he_IL": "il" })

    Component.onCompleted: {
        if (!Inst.keymapTouched) {
            var g = guessFor[Inst.locale.split(".")[0]]
            if (g && Inst.keymaps.indexOf(g) >= 0 && g !== Inst.keymap) {
                Inst.keymap = g
                Inst.applyKeymap()
            }
        }
    }

    SearchList {
        id: list
        Layout.fillWidth: true
        listHeight: Math.max(160, Math.min(320, p.height - 385))
        placeholder: "Search keyboard layouts"
        current: Inst.keymap
        items: Inst.keymaps.map(function (k) { return { id: k, title: Inst.keymapName(k), trailing: k } })
        onPicked: (id) => {
            Inst.keymap = id
            Inst.keymapTouched = true
            applyTimer.restart()
        }
        onActivated: Inst.navNext()
        KeyNavigation.tab: test
    }

    Timer {
        id: applyTimer
        interval: 250
        onTriggered: Inst.applyKeymap()
    }

    KField {
        id: test
        Layout.fillWidth: true
        Layout.topMargin: 6
        placeholder: "Type here to test your keyboard"
    }
}
