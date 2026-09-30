#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint pip_kit.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'pip_kit'
  s.version          = '1.0.2'
  s.summary          = 'System Picture in Picture for any Flutter content.'
  s.description      = <<-DESC
System Picture in Picture for any Flutter widget, video or self-contained route flow.
                       DESC
  s.homepage         = 'https://github.com/Mohiuddin655-PUB/pip_kit'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Mohiuddin' => 'https://github.com/Mohiuddin655-PUB' }
  s.source           = { :path => '.' }
  s.source_files = 'pip_kit/Sources/pip_kit/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'pip_kit_privacy' => ['pip_kit/Sources/pip_kit/PrivacyInfo.xcprivacy']}
end
