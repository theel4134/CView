#!/usr/bin/env ruby
require 'xcodeproj'

project_path = '/Users/kimsundong/Downloads/work/CView_v2/CView_v2.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'CView_v2' }
abort "CView_v2 target not found" unless target

ref_file = project.files.find { |f| f.path == 'Sources/CViewApp/AppDependencies.swift' }
abort "Reference file not found" unless ref_file
group = ref_file.parent
puts "Target group: #{group.hierarchy_path} (sourceTree=#{group.source_tree})"

files = [
  'Sources/CViewApp/Services/WidgetSnapshotWriter.swift',
  'Sources/CViewApp/Navigation/DeepLinkRouter.swift',
  'Sources/CViewApp/AppState+Widget.swift',
]

files.each do |rel_path|
  if project.files.any? { |f| f.path == rel_path }
    puts "  [skip] #{rel_path}"
    next
  end
  file_ref = group.new_file(rel_path)
  file_ref.source_tree = 'SOURCE_ROOT'
  target.add_file_references([file_ref])
  puts "  [add ] #{rel_path}"
end

project.save
puts "Done."
