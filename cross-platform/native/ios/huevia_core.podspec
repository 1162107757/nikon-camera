Pod::Spec.new do |s|
  s.name = 'huevia_core'
  s.version = '0.1.0'
  s.summary = 'Shared Huevia image and camera core.'
  s.description = 'Original Java algorithms translated ahead of time, with native Apple image and storage adapters.'
  s.homepage = 'https://github.com/1162107757/nikon-camera'
  s.license = { :type => 'Proprietary' }
  s.author = { 'Huevia' => 'Huevia' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.{h,m,mm,cpp}', 'Generated/**/*.{h,m}'
  s.exclude_files = 'Generated/**/*Test.{h,m}', 'Generated/**/CoreParity.{h,m}', 'Generated/**/CoreBoundary.{h,m}', 'Generated/**/NcpCompatibilityFixtures.{h,m}'
  s.public_header_files = 'Classes/HueviaCorePlugin.h'
  s.vendored_frameworks = 'Frameworks/JRE.xcframework', 'Frameworks/LibRaw.xcframework'
  s.resource_bundles = { 'HueviaNativeAssets' => ['Assets/**/*', 'Notices/*'] }
  s.frameworks = 'Foundation', 'UIKit', 'ImageIO', 'CoreGraphics', 'CoreText', 'Security', 'Photos', 'UniformTypeIdentifiers'
  s.libraries = 'z', 'iconv', 'c++'
  s.dependency 'Flutter'
  s.platform = :ios, '16.0'
  s.requires_arc = true
  s.compiler_flags = '-ffp-contract=off'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Generated" "$(PODS_TARGET_SRCROOT)/RuntimeHeaders"',
    'CLANG_ENABLE_OBJC_ARC' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) J2OBJC_USE_ARC=1',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17'
  }
end
