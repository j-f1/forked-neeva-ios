require 'xcodeproj'
project_path = './Client.xcodeproj'
project = Xcodeproj::Project.open(project_path)
project.native_targets.each do |target|
    target.build_configurations.each do |config|
        config.build_settings["EXCLUDED_ARCHS[sdk=iphonesimulator*]"] = 'arm64'
    end
end
project.save
