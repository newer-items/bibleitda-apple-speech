#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint bibleitda_apple_speech.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'bibleitda_apple_speech'
  s.version          = '0.0.1'
  s.summary          = 'Bibleitda iOS 26 speech transcription bridge.'
  s.description      = <<-DESC
Uses Apple SpeechAnalyzer for Bible-writing speech recognition on iOS 26.
                       DESC
  s.homepage         = 'https://github.com/Newercorp/bibleitda-apple-speech'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Newer Corp' => 'dev@newer.co.kr' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'bibleitda_apple_speech_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
