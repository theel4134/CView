#!/usr/bin/env ruby
# Statistics 리디자인 — 기존 2 파일 제거 + 신규 10 파일 추가.
require 'xcodeproj'

project_path = File.expand_path(File.join(__dir__, '..', 'CView_v2.xcodeproj'))
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'CView_v2' }
abort "CView_v2 target not found" unless target

ref_file = project.files.find { |f| f.path == 'Sources/CViewApp/Views/HomeView.swift' }
abort "Reference file (HomeView.swift) not found" unless ref_file
group = ref_file.parent
puts "Target group: #{group.hierarchy_path} (sourceTree=#{group.source_tree})"

# 1) 기존 파일 제거
removed_paths = [
  'Sources/CViewApp/Views/StatisticsView.swift',
  'Sources/CViewApp/Views/StatisticsDetailViews.swift',
]
removed_paths.each do |rel_path|
  refs = project.files.select { |f| f.path == rel_path }
  if refs.empty?
    puts "  [skip-rm] #{rel_path} (no ref)"
    next
  end
  refs.each do |fref|
    target.source_build_phase.files.select { |bf| bf.file_ref == fref }.each(&:remove_from_project)
    fref.remove_from_project
  end
  puts "  [remove ] #{rel_path}"
end

# 2) 신규 파일 추가
files = [
  'Sources/CViewApp/Views/Statistics/StatisticsView.swift',
  'Sources/CViewApp/Views/Statistics/Components/SectionHeader.swift',
  'Sources/CViewApp/Views/Statistics/Components/EmptyStatePlaceholder.swift',
  'Sources/CViewApp/Views/Statistics/Components/KPICard.swift',
  'Sources/CViewApp/Views/Statistics/Components/StatCard.swift',
  'Sources/CViewApp/Views/Statistics/Components/GrafanaDashboardView.swift',
  'Sources/CViewApp/Views/Statistics/Tabs/SessionStatsView.swift',
  'Sources/CViewApp/Views/Statistics/Tabs/StreamingStatsView.swift',
  'Sources/CViewApp/Views/Statistics/Tabs/PerformanceStatsView.swift',
  'Sources/CViewApp/Views/Statistics/Tabs/ChatStatsView.swift',
  'Sources/CViewApp/Views/Statistics/Tabs/WatchHistoryStatsView.swift',
  'Sources/CViewApp/Views/Statistics/Tabs/ServerSyncStatsView.swift',
]

files.each do |rel_path|
  if project.files.any? { |f| f.path == rel_path }
    puts "  [skip-add] #{rel_path}"
    next
  end
  file_ref = group.new_file(rel_path)
  file_ref.source_tree = 'SOURCE_ROOT'
  target.add_file_references([file_ref])
  puts "  [add    ] #{rel_path}"
end

project.save
puts "Done."
