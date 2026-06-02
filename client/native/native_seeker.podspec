Pod::Spec.new do |s|
  s.name             = 'native_seeker'
  s.version          = '0.2.0'
  s.summary          = 'Content Seeker native media core library'
  s.homepage         = 'https://github.com/magechiu/content-seeker'
  s.license          = { :type => 'MIT' }
  s.author           = { 'magechiu' => 'magechiu@example.com' }
  s.source           = { :path => '.' }

  s.source_files     = 'include/**/*.h', 'src/**/*.{h,cpp,mm}',
                       'third_party/quickjs/quickjs.c',
                       'third_party/quickjs/quickjs.h',
                       'third_party/quickjs/quickjs-atom.h',
                       'third_party/quickjs/quickjs-opcode.h',
                       'third_party/quickjs/libregexp.c',
                       'third_party/quickjs/libregexp.h',
                       'third_party/quickjs/libregexp-opcode.h',
                       'third_party/quickjs/libunicode.c',
                       'third_party/quickjs/libunicode.h',
                       'third_party/quickjs/libunicode-table.h',
                       'third_party/quickjs/cutils.c',
                       'third_party/quickjs/cutils.h',
                       'third_party/quickjs/libbf.c',
                       'third_party/quickjs/libbf.h',
                       'third_party/quickjs/list.h'
  s.public_header_files = 'include/**/*.h'

  s.osx.deployment_target = '10.15'
  s.ios.deployment_target = '13.0'

  s.frameworks = 'Foundation', 'AVFoundation', 'CoreMedia'

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) SEEKER_BUILDING_DLL=1 CONFIG_VERSION=\"2024-01-13\" CONFIG_BIGNUM=1',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/include" "${PODS_TARGET_SRCROOT}/src" "${PODS_TARGET_SRCROOT}/third_party" "${PODS_TARGET_SRCROOT}/third_party/quickjs"',
    'CLANG_ENABLE_OBJC_ARC' => 'YES',
  }

  # 排除非 Apple 平台的桩文件（Apple 平台用 muxer_apple.mm，
  # muxer_fmp4.cpp 始终编译作为 fallback）
  s.exclude_files = 'src/utils/http_client_stub.cpp', 'src/utils/muxer_default.cpp'

  s.libraries = 'c++'
end
