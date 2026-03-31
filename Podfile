platform :osx, '14.0'

target 'MyFTPClient' do
  use_frameworks!
  pod 'NMSSH'

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
      config.build_settings['ARCHS'] = 'x86_64'
      config.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'
    end
  end
end
