#!/usr/bin/env ruby
# Add CViewWidgets WidgetKit Extension target to CView_v2.xcodeproj
require 'xcodeproj'

PROJECT_PATH = '/Users/kimsundong/Downloads/work/CView_v2/CView_v2.xcodeproj'
TARGET_NAME = 'CViewWidgets'
WIDGET_DIR_REL = 'CViewWidgets'  # relative to SOURCE_ROOT
BUNDLE_ID = 'com.cview.app.widgets'

project = Xcodeproj::Project.open(PROJECT_PATH)

# Idempotency: skip if target already exists
if project.targets.any? { |t| t.name == TARGET_NAME }
  puts "Target #{TARGET_NAME} already exists. Skipping."
  exit 0
end

main_target = project.targets.find { |t| t.name == 'CView_v2' }
abort "CView_v2 target not found" unless main_target

# 1) Create the new target as App Extension
target = project.new(Xcodeproj::Project::Object::PBXNativeTarget)
project.objects_by_uuid[target.uuid] = target
project.root_object.targets << target
target.name = TARGET_NAME
target.product_name = TARGET_NAME
target.product_type = 'com.apple.product-type.app-extension'
target.build_configuration_list = Xcodeproj::Project::ProjectHelper
  .configuration_list(project, :osx, '15.0', :swift, :app_extension)

# Adjust per-config build settings
target.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_NAME'                  => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER'     => BUNDLE_ID,
    'INFOPLIST_FILE'                => "#{WIDGET_DIR_REL}/Info.plist",
    'GENERATE_INFOPLIST_FILE'       => 'NO',
    'CODE_SIGN_ENTITLEMENTS'        => "#{WIDGET_DIR_REL}/CViewWidgets.entitlements",
    'CODE_SIGN_STYLE'               => 'Automatic',
    'CODE_SIGN_IDENTITY'            => '-',
    'CODE_SIGNING_REQUIRED'         => 'NO',
    'CODE_SIGNING_ALLOWED'          => 'YES',
    'MACOSX_DEPLOYMENT_TARGET'      => '15.0',
    'SDKROOT'                       => 'macosx',
    'SWIFT_VERSION'                 => '6.0',
    'SWIFT_EMIT_LOC_STRINGS'        => 'YES',
    'SKIP_INSTALL'                  => 'YES',
    'LD_RUNPATH_SEARCH_PATHS'       => '$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks',
    'ENABLE_HARDENED_RUNTIME'       => 'YES',
    'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO',
    'COMBINE_HIDPI_IMAGES'          => 'YES',
    'INFOPLIST_KEY_CFBundleDisplayName' => 'CView Widgets',
    'INFOPLIST_KEY_NSHumanReadableCopyright' => '',
  })
end

# Make a product reference (the .appex)
product_ref = project.products_group.new_reference("#{TARGET_NAME}.appex", :built_products)
product_ref.explicit_file_type = 'wrapper.app-extension'
product_ref.include_in_index = '0'
target.product_reference = product_ref

# 2) Sources build phase
sources_phase = target.new_shell_script_build_phase  # placeholder; replace below
target.build_phases.delete(sources_phase)
sources_phase = project.new(Xcodeproj::Project::Object::PBXSourcesBuildPhase)
project.objects_by_uuid[sources_phase.uuid] = sources_phase
target.build_phases << sources_phase

frameworks_phase = project.new(Xcodeproj::Project::Object::PBXFrameworksBuildPhase)
project.objects_by_uuid[frameworks_phase.uuid] = frameworks_phase
target.build_phases << frameworks_phase

resources_phase = project.new(Xcodeproj::Project::Object::PBXResourcesBuildPhase)
project.objects_by_uuid[resources_phase.uuid] = resources_phase
target.build_phases << resources_phase

# 3) Locate or create CViewWidgets group at project root
widgets_group = project.main_group.children.find { |g| g.respond_to?(:path) && g.path == WIDGET_DIR_REL }
widgets_group ||= project.main_group.new_group(WIDGET_DIR_REL, WIDGET_DIR_REL)
providers_group = widgets_group.children.find { |g| g.respond_to?(:path) && g.path == 'Providers' }
providers_group ||= widgets_group.new_group('Providers', 'Providers')
sub_widgets_group = widgets_group.children.find { |g| g.respond_to?(:path) && g.path == 'Widgets' }
sub_widgets_group ||= widgets_group.new_group('Widgets', 'Widgets')

# Files to register (path relative to widgets_group)
swift_files = {
  widgets_group => [
    'CViewWidgetsBundle.swift',
  ],
  providers_group => [
    'WidgetSnapshotLoader.swift',
    'SelectChannelIntent.swift',
    'WidgetCommon.swift',
  ],
  sub_widgets_group => [
    'FollowingLiveListWidget.swift',
    'SingleChannelWidget.swift',
    'NowWatchingWidget.swift',
    'LiveCountWidget.swift',
  ],
}

added = []
swift_files.each do |group, names|
  names.each do |name|
    file_ref = group.children.find { |c| c.respond_to?(:path) && c.path == name }
    file_ref ||= group.new_file(name)
    sources_phase.add_file_reference(file_ref)
    added << name
  end
end
puts "Added #{added.size} Swift sources to #{TARGET_NAME}: #{added.join(', ')}"

# Info.plist + entitlements (just file refs — don't add to a build phase)
['Info.plist', 'CViewWidgets.entitlements'].each do |name|
  unless widgets_group.children.any? { |c| c.respond_to?(:path) && c.path == name }
    widgets_group.new_file(name)
  end
end

# 4) Link CViewCore (SPM product). Reuse the existing XCSwiftPackageProductDependency object.
core_dep = project.root_object.package_references.first&.tap { |_| } # ensure container exists
core_product = project.objects.find do |o|
  o.is_a?(Xcodeproj::Project::Object::XCSwiftPackageProductDependency) && o.product_name == 'CViewCore'
end
if core_product
  target.package_product_dependencies << core_product
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  project.objects_by_uuid[build_file.uuid] = build_file
  build_file.product_ref = core_product
  frameworks_phase.files << build_file
  puts "Linked CViewCore (SPM)."
else
  puts "WARNING: CViewCore SPM product not found — link manually in Xcode."
end

# 5) Embed app extension into main app
copy_phase = main_target.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' || p.dst_subfolder_spec == '13' }
unless copy_phase
  copy_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  project.objects_by_uuid[copy_phase.uuid] = copy_phase
  copy_phase.name = 'Embed App Extensions'
  copy_phase.dst_subfolder_spec = '13'  # PlugIns
  copy_phase.dst_path = ''
  copy_phase.run_only_for_deployment_postprocessing = '0'
  main_target.build_phases << copy_phase
end

# Avoid duplicate embed entry
unless copy_phase.files.any? { |f| f.file_ref == product_ref }
  embed_bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  project.objects_by_uuid[embed_bf.uuid] = embed_bf
  embed_bf.file_ref = product_ref
  embed_bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  copy_phase.files << embed_bf
end

# Add target dependency from main app -> widget
unless main_target.dependencies.any? { |d| d.target == target }
  main_target.add_dependency(target)
end

project.save
puts "Saved. New target: #{TARGET_NAME} (#{BUNDLE_ID})"
