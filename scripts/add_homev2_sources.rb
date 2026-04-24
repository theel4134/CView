#!/usr/bin/env ruby
require 'xcodeproj'

project_path = '/Users/kimsundong/Downloads/work/CView_v2/CView_v2.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'CView_v2' }
abort "CView_v2 target not found" unless target

ref_file = project.files.find { |f| f.path == 'Sources/CViewApp/Views/HomeView.swift' }
abort "Reference file (HomeView.swift) not found" unless ref_file
group = ref_file.parent
puts "Target group: #{group.hierarchy_path} (sourceTree=#{group.source_tree})"

files = [
  'Sources/CViewApp/Views/HomeV2/HomeRecommendationEngine.swift',
  'Sources/CViewApp/Views/HomeV2/HomeV2Components.swift',
  'Sources/CViewApp/Views/HomeV2/HomeView_v2.swift',
  'Sources/CViewApp/Views/HomeV2/HomeMonitorPanel.swift',
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
