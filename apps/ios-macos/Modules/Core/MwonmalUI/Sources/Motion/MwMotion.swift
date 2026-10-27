import SwiftUI

/// 애니메이션 프리셋(ADR-0012). 화면은 곡선 리터럴 대신 이것만 쓴다. 동작 줄이기 설정이면 바로 바뀐다.
public enum MwMotion {
    /// 아래 안내(토스트)가 나타나고 사라질 때.
    public static func toast(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.28)
    }
}
