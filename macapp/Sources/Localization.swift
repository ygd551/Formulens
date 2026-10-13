import Foundation

/// 界面文字本地化：代码中统一写英文，翻译放在 Resources/<语言>.lproj/Localizable.strings。
/// 默认跟随系统语言，也可以在应用内（菜单栏 ∑ → 语言）手动选择。
/// 新增界面文字后，运行 macapp/tools/check_l10n.sh 检查是否都有中文翻译。
enum AppLanguage: String, CaseIterable {
    case system, en, zhHans = "zh-Hans"

    /// 语言名称用各自的语言显示，方便在看不懂当前界面语言时也能找到
    var title: String {
        switch self {
        case .system: return L("Follow System")
        case .en: return "English"
        case .zhHans: return "简体中文"
        }
    }
}

enum Localizer {
    private static let key = "language"

    static var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    /// 当前使用的翻译：跟随系统时交给 macOS 选择，否则使用指定语言的 .lproj
    private(set) static var bundle: Bundle = bundle(for: language)

    static func set(_ lang: AppLanguage) {
        UserDefaults.standard.set(lang.rawValue, forKey: key)
        bundle = bundle(for: lang)
    }

    private static func bundle(for lang: AppLanguage) -> Bundle {
        guard lang != .system,
              let path = Bundle.main.path(forResource: lang.rawValue, ofType: "lproj"),
              let b = Bundle(path: path)
        else { return .main }
        return b
    }
}

func L(_ key: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: Localizer.bundle, value: key, comment: "")
}

/// 带参数的文字，参数统一用 %@ 占位
func L(_ key: String, _ args: String...) -> String {
    String(format: L(key), arguments: args)
}
