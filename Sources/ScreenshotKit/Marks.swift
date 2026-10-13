/// The marks that the user draws in the box.
///
/// Empty for now. Subissue 3 (YAZ-2767) adds `Tool`, `MarkStyle`, `Mark`, and `add`, `undo`, `redo`.
/// The type exists already so that `CaptureInteraction` and `composeFinalImage` keep their shape.
public struct MarkList: Equatable {
    public init() {}
}
