import Carbon.HIToolbox
import Foundation

enum KeyboardLayoutKeyRenderer {
  static func name(for keyCode: UInt16) -> String? {
    guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
      let layoutDataPointer = TISGetInputSourceProperty(
        inputSource, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPointer).takeUnretainedValue()
    guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
    let keyboardLayout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
    var deadKeyState: UInt32 = 0
    var length = 0
    var characters = [UniChar](repeating: 0, count: 4)
    let status = UCKeyTranslate(
      keyboardLayout,
      keyCode,
      UInt16(kUCKeyActionDisplay),
      0,
      UInt32(LMGetKbdType()),
      OptionBits(kUCKeyTranslateNoDeadKeysBit),
      &deadKeyState,
      characters.count,
      &length,
      &characters
    )
    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: characters, count: length).uppercased()
  }
}
