import Foundation
import Testing
@testable import launchPadCore

struct PinyinTests {
    @Test func convertsChineseToToneLessPinyin() {
        let components = Pinyin.components(of: "微信")
        #expect(components.count == 1)
        #expect(components.first?.full == "weixin")
        #expect(components.first?.initials == "wx")
    }

    @Test func stripsToneMarks() {
        let components = Pinyin.components(of: "音乐")
        #expect(components.contains { $0.full == "yinyue" && $0.initials == "yy" })
    }

    @Test func offersAlternateReadingsForPolyphones() {
        let bank = Pinyin.components(of: "银行")
        #expect(bank.contains { $0.full == "yinhang" })
        let music = Pinyin.components(of: "音乐")
        #expect(music.contains { $0.full == "yinle" })
    }

    @Test func keepsEnglishNamesAsIs() {
        let components = Pinyin.components(of: "Safari")
        #expect(components.count == 1)
        #expect(components.first?.full == "safari")
        #expect(components.first?.initials == "s")
    }

    @Test func handlesMixedNames() {
        let components = Pinyin.components(of: "有道云笔记")
        #expect(components.count == 1)
        #expect(components.first?.full == "youdaoyunbiji")
        #expect(components.first?.initials == "ydybj")
    }
}
