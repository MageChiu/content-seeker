import 'dart:ffi';
import 'dart:io';

/// 加载 libseeker 原生库
/// 根据不同平台返回对应的动态库实例
DynamicLibrary loadSeekerLibrary() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libseeker.so');
  } else if (Platform.isIOS) {
    // iOS 静态链接，从进程中查找符号
    return DynamicLibrary.process();
  } else if (Platform.isMacOS) {
    // macOS 通过 CocoaPods framework 加载
    return DynamicLibrary.open('native_seeker.framework/native_seeker');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('seeker.dll');
  } else if (Platform.isLinux) {
    return DynamicLibrary.open('libseeker.so');
  } else {
    throw UnsupportedError('当前平台不支持 libseeker: ${Platform.operatingSystem}');
  }
}
