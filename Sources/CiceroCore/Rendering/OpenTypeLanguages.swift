import Foundation

/// The names of OpenType's language system tags, like Bulgarian for BGR, those fonts give localized forms for; a tag
/// the list doesn't have is shown as it is.
public enum OpenTypeLanguages {
    public static func name(of tag: String) -> String {
        names[tag.trimmingCharacters(in: .whitespaces)] ?? tag
    }

    /// "Serbian and Macedonian".
    public static func names(of tags: [String]) -> String {
        tags.map(name(of:)).listed()
    }

    private static let names = [
        "ABK": "Abkhazian", "AFK": "Afrikaans", "AMH": "Amharic", "APPH": "Americanist Phonetic", "ARA": "Arabic",
        "ASM": "Assamese", "AZE": "Azerbaijani", "BEL": "Belarusian", "BEN": "Bengali", "BGR": "Bulgarian", "BOS": "Bosnian",
        "BRE": "Breton", "BSH": "Bashkir", "CAT": "Catalan", "CHU": "Chuvash", "CRT": "Crimean Tatar", "CSY": "Czech",
        "DAN": "Danish", "DEU": "German", "ELL": "Greek", "ENG": "English", "ESP": "Spanish", "ETI": "Estonian",
        "EUQ": "Basque", "FAR": "Persian", "FIN": "Finnish", "FOS": "Faroese", "FRA": "French", "GAE": "Scottish Gaelic",
        "GAG": "Gagauz", "GUA": "Guarani", "GUJ": "Gujarati", "HAU": "Hausa", "HIN": "Hindi", "HRV": "Croatian",
        "HUN": "Hungarian", "HYE": "Armenian", "IBO": "Igbo", "IND": "Indonesian", "IPPH": "IPA", "IRI": "Irish",
        "IRT": "Irish Traditional", "ISL": "Icelandic", "ISM": "Inari Sami", "ITA": "Italian", "IWR": "Hebrew",
        "JAN": "Japanese", "KAN": "Kannada", "KAT": "Georgian", "KAZ": "Kazakh", "KGZ": "Kyrgyz", "KHM": "Khmer",
        "KOK": "Konkani", "KOR": "Korean", "KRK": "Karakalpak", "KSH": "Kashmiri", "KUR": "Kurdish", "LAO": "Lao",
        "LSM": "Lule Sami", "LTH": "Lithuanian", "LVI": "Latvian", "MAH": "Marathi", "MAL": "Malayalam", "MKD": "Macedonian",
        "MLR": "Malayalam", "MLY": "Malay", "MNG": "Mongolian", "MOL": "Moldavian", "MTS": "Maltese", "NAV": "Navajo",
        "NEP": "Nepali", "NLD": "Dutch", "NOR": "Norwegian", "NSM": "Northern Sami", "ORI": "Odia", "OSS": "Ossetian",
        "PAN": "Punjabi", "PAS": "Pashto", "PLK": "Polish", "PTG": "Portuguese", "ROM": "Romanian", "RUS": "Russian",
        "SAN": "Sanskrit", "SKS": "Skolt Sami", "SKY": "Slovak", "SLV": "Slovenian", "SND": "Sindhi", "SNH": "Sinhala",
        "SQI": "Albanian", "SRB": "Serbian", "SSM": "Southern Sami", "SVE": "Swedish", "SWK": "Swahili", "TAM": "Tamil",
        "TAT": "Tatar", "TEL": "Telugu", "TGK": "Tajik", "TGL": "Tagalog", "THA": "Thai", "TIB": "Tibetan", "TKM": "Turkmen",
        "TRK": "Turkish", "UKR": "Ukrainian", "URD": "Urdu", "UZB": "Uzbek", "VIT": "Vietnamese", "WEL": "Welsh",
        "YAK": "Sakha", "YBA": "Yoruba", "YID": "Yiddish", "ZHH": "Chinese (Hong Kong)", "ZHS": "Chinese (Simplified)",
        "ZHT": "Chinese (Traditional)", "ZHTM": "Chinese (Macao)",
    ]
}
