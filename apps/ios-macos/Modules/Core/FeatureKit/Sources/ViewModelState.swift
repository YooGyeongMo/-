import Observation
import SwiftUI

/// 화면 모델을 **뷰 수명 동안 한 번만** 만든다(`@State` 초기화 함정 막기).
///
/// `_model = State(initialValue: ViewModel(...))`는 부모가 다시 그릴 때마다(토스트·키보드·탭 바 인셋 등)
/// 새 `ViewModel`을 만들고 버린다. SwiftUI는 처음 것만 쓰지만 `init` 비용·부수 효과는 매번 든다.
/// 이 래퍼는 만드는 식을 `@autoclosure`로 받아 **처음 읽을 때 한 번만** 실행한다.
///
///     @ViewModelState private var model: HomeViewModel
///     init(repository: any TranslationRepository) {
///         _model = ViewModelState(wrappedValue: HomeViewModel(repository: repository))
///     }
///     TextEditor(text: $model.text) // projectedValue = Bindable
///
/// 상자(`Box`)는 매번 만들어지지만 비어 있는 작은 참조라 싸다. `@State`가 처음 상자만 붙잡는다.
/// 상자 안 값을 바꾸는 것은 SwiftUI 상태 변경이 아니라서 "뷰 갱신 중 상태 변경" 경고가 나지 않는다.
/// 화면 갱신은 모델이 `@Observable`이라 모델의 프로퍼티를 읽은 곳만 다시 그린다.
@propertyWrapper
public struct ViewModelState<Model: AnyObject & Observable>: DynamicProperty {
    @State private var box = Box()
    private let make: () -> Model

    public init(wrappedValue make: @autoclosure @escaping () -> Model) {
        self.make = make
    }

    public var wrappedValue: Model {
        if let model = box.model {
            return model
        }
        let model = make()
        box.model = model
        return model
    }

    public var projectedValue: Bindable<Model> {
        Bindable(wrappedValue)
    }

    private final class Box {
        var model: Model?
    }
}
