#!/usr/bin/env ruby

# Adapted from from Nathan's dotfiles: <https://github.com/aniero/dotfiles/blob/master/install.rb>
# which was originally taken from: <http://errtheblog.com/posts/89-huba-huba>

puts
at_exit { puts }

require 'fileutils'
require 'erb'
require 'optparse'
require 'pp'

begin
  require 'colored'
  $has_color = true
rescue LoadError
  begin
    require 'rubygems'
    require 'colored'
    $has_color = true
  rescue LoadError => e
    warn "Install the 'colored' gem if you want colors: <gem install colored>"
    warn ""
    $has_color = false
  end
end

if $has_color
  String.class_eval do
    def dry_success
      bold.black
    end
    alias :unimportant :dry_success
    alias :dry_failure :dry_success
    def success
      green
    end
    def failure
      red
    end
    def filename
      bold.blue
    end
    def debugging
      cyan
    end
    def emphasis
      bold.yellow
    end
  end
else
  String.class_eval do
    %w(unimportant dry_success dry_failure success failure filename debugging emphasis).each do |method|
      define_method(method) { self }
    end
  end
end

home = File.expand_path(ENV['HOME'])

options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"
  opts.on("-n", "--noop", "--dry-run", "Don't actually copy or write any files.") do |val|
    options[:dry_run] = true
  end
  opts.on("-f", "--force-templates", "Usually dotfiles that already exist are not overwritten. This will only cause
                                     dotfile templates to be applied (regardless of whether their target files exist or not).") do |val|
    options[:force] = :templates
  end
  opts.on("-F", "--force-all", "Overwrite every target file whether it already exists or not.") do |val|
    options[:force] = :all
  end
  opts.on("--github-token TOKEN", "Specify your Github API token. It will be placed in .gitconfig.") do |val|
    options[:github_token] = val
  end
  opts.on("-V", "--verbose", "Show commands being run") do |val|
    options[:verbose] = true
  end
  opts.on_tail("-h", "--help") do |val|
    puts parser
    exit
  end
end
parser.parse!(ARGV)
if ARGV.any?
  warn "Unknown arguments: #{ARGV.inspect}"
  warn parser
  exit 1
end

SOURCE_DIR = "src"

files = []
Dir["#{SOURCE_DIR}/**/*"].each do |file|
  source_basename = file.sub("#{SOURCE_DIR}/", "")
  source = File.expand_path(file)
  next if File.directory?(source)
  short_source = source.sub(home, "~")
  target = File.join(home, "." + source_basename).sub(/\.erb$/, "")
  short_target = target.sub(home, "~")
  status = ""
  reason = 'already exists'
  if File.extname(source) == '.erb'
    template = ERB.new(File.read(source), nil, "-")  # allow <%- ... -%> tags like Rails
    content = template.result(binding).strip
    if File.exists?(target)
      existing_content = File.read(target)
      if content == existing_content
        status = options[:force] == :all ? 'overwrite' : 'skip'
      else
        status = options[:force] == :templates ? 'overwrite' : 'skip'
      end
    else
      status = 'install'
    end
    reason = 'same content'
  else
    if File.exists?(target)
      status = options[:force] == :all ? 'overwrite' : 'skip'
    else
      status = 'install'
    end
  end
  files << [
    source_basename,
    source,
    short_source,
    target,
    short_target,
    status,
    reason,
    content
  ]
end
w = files.map {|f| f[5].length }.max

if options[:dry_run]
  puts "Here's what the output will look like on a 'real' run."
  puts "Nothing is being written to the filesystem.".emphasis
  puts
end

num_skipped_files = 0
num_updated_files = 0

files.each do |file|
  source_basename, source, short_source, target, short_target, status, reason, content = file

  if status == 'skip'
    if options[:verbose]
      puts status.rjust(w).failure + " " + short_target + " (#{reason})".unimportant
    end
    num_skipped_files += 1
  else
    puts status.rjust(w).success + " " + short_target
    if File.extname(source) == ".erb"
      unless options[:dry_run]
        FileUtils.mkdir_p(File.dirname(target))
        File.open(target, "w") {|f| f.write(content) }
      end
      puts content.debugging if options[:verbose]
    else
      target = File.join(home, "." + source_basename)
      # Remove the target manually.
      # If it's a regular file, ln -f won't remove it.
      system("rm", "-rf", target)
      cmd = ["ln", "-s", source, target]
      pretty_cmd = cmd.map {|x| x =~ /[ ]/ ? x.inspect : x }.join(" ")
      puts pretty_cmd.debugging if options[:verbose]
      unless options[:dry_run]
        FileUtils.mkdir_p(File.dirname(target))
        system(*cmd)
      end
    end
    num_updated_files += 1
  end
end

if num_updated_files == 0
  puts if options[:verbose]
  puts "All files are already up to date, you're good!".success
  unless options[:verbose]
    puts "Run again with --verbose if you want to know why.".success
  end
elsif !options[:dry_run]
  puts if options[:verbose]
  puts "Dotfiles successfully updated!".success
end

if num_skipped_files > 0
  puts "Run again with --force-templates or --force-all to force-update skipped files.".success
end
