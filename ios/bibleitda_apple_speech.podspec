#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint bibleitda_apple_speech.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'bibleitda_apple_speech'
  s.version          = '0.2.0'
  s.summary          = 'Bibleitda iOS whisper.cpp speech transcription bridge.'
  s.description      = <<-DESC
Uses whisper.cpp for private, on-device Bible-writing speech recognition.
                       DESC
  s.homepage         = 'https://github.com/Newercorp/bibleitda-apple-speech'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Newer Corp' => 'dev@newer.co.kr' }
  s.source           = { :path => '.' }
  s.source_files = [
    'Classes/**/*.{h,m,mm,swift}',
    'Vendor/WhisperCppFlutterBridge/*.{h,cpp}',
    'Vendor/WhisperCppCore/src/whisper.cpp',
    'Vendor/WhisperCppCore/src/coreml/*.{h,m,mm}',
    'Vendor/WhisperCppCore/ggml/src/{ggml.c,ggml.cpp,ggml-alloc.c,ggml-backend.cpp,ggml-backend-dl.cpp,ggml-backend-meta.cpp,ggml-backend-reg.cpp,ggml-opt.cpp,ggml-quants.c,ggml-threading.cpp,gguf.cpp}',
    'Vendor/WhisperCppCore/ggml/src/ggml-cpu/{ggml-cpu.c,ggml-cpu.cpp,repack.cpp,hbm.cpp,quants.c,traits.cpp,binary-ops.cpp,unary-ops.cpp,vec.cpp,ops.cpp}',
    'Vendor/WhisperCppCore/ggml/src/ggml-cpu/amx/{amx.cpp,mmq.cpp}',
    'Vendor/WhisperCppCore/ggml/spm/*.{c,cpp}',
    'Vendor/WhisperCppCore/ggml/src/ggml-blas/ggml-blas.cpp',
    'Vendor/WhisperCppCore/ggml/src/ggml-metal/*.{m,cpp}'
  ]
  s.resources = [
    'Vendor/WhisperCppCore/ggml/Resources/ggml-metal.txt',
    'Vendor/WhisperCppCore/ggml/src/ggml-metal/ggml-metal-impl.h',
    'Vendor/WhisperCppCore/ggml/src/ggml-common.h'
  ]
  s.public_header_files = 'Vendor/WhisperCppFlutterBridge/whisper_flutter.h'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'
  s.frameworks = 'AVFoundation', 'Accelerate', 'Metal', 'MetalKit', 'Foundation', 'CoreML'
  s.libraries = 'c++'
  s.requires_arc = [
    'Classes/**/*.swift',
    'Vendor/WhisperCppCore/src/coreml/*.{m,mm}'
  ]

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'SWIFT_ENABLE_EXPLICIT_MODULES' => 'NO',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) GGML_USE_CPU GGML_USE_BLAS GGML_BLAS_USE_ACCELERATE GGML_USE_ACCELERATE GGML_USE_METAL WHISPER_USE_COREML WHISPER_COREML_ALLOW_FALLBACK ACCELERATE_NEW_LAPACK ACCELERATE_LAPACK_ILP64 WHISPER_VERSION=\"1.9.2\" GGML_VERSION=\"0.18.1\" GGML_COMMIT=\"unknown\"',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/Vendor/WhisperCppCore/include" "${PODS_TARGET_SRCROOT}/Vendor/WhisperCppCore/ggml/include" "${PODS_TARGET_SRCROOT}/Vendor/WhisperCppCore/ggml/src" "${PODS_TARGET_SRCROOT}/Vendor/WhisperCppCore/ggml/src/ggml-cpu" "${PODS_TARGET_SRCROOT}/Vendor/WhisperCppCore/ggml/src/ggml-metal"'
  }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'bibleitda_apple_speech_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
