#!/usr/bin/env ruby

require 'open3'
require 'json'

NixpkgsPath = File.expand_path("/path/to/nixpkgs")
# master as of 2021-10-25
StartRev = "8e18c70837aa01ade3718cd0fd35b649b3a2cf52"

raise 'Please set NixpkgsPath' unless Dir.exist? NixpkgsPath

Change = Struct.new(:version, :drv, :date, :rev, :depth, keyword_init: true)

def find_versions(versions_to_find: 10, start_depth: 0, log: Log.new)
  @log = log
  prev_change = Change.new(depth: start_depth - 1, rev: StartRev, drv: nil, version: nil)
  versions_found = 0

  while versions_found < versions_to_find
    upper_bound = find_next_drv(prev_change)
    change = find_drv_change(prev_change, upper_bound)
    @log.add_change(change)
    if change.version != prev_change.version
      versions_found += 1
    end
    prev_change = change
  end
end

# Find upper bound of next change after arg `change`
# by probing with exponential step size
def find_next_drv(change)
  depth = 0
  step = 1
  while true
    depth += step
    version, drv = get_version(change, depth)
    break if drv != change.drv
    step *= 2
  end
  depth
end

# binary search for next change within arg `change` and
# the following `hi` (integer) commits
def find_drv_change(change, hi)
  lo = 0
  loop do
    mid = (lo + hi + 1) / 2 # round up
    version, drv = get_version(change, mid)
    if mid == hi
      return Change.new(version: version, drv: drv, date: get_date,
                        rev: get_rev, depth: change.depth + mid)
    end
    if drv == change.drv
      lo = mid
    else
      hi = mid
    end
  end
end

# get version at depth relative to change
def get_version(change, depth)
  @log.print_depth(change.depth, depth)
  checkout(change.rev, depth)
  maybe_stop
  expr = <<~EOF
    with (import "#{NixpkgsPath}" { config = {}; overlays = []; });
    {
      version = glibc.version;
      drv = glibc.drvPath;
    }
  EOF
  json = run('nix', 'eval', '--impure', '--json', '--expr', expr)
  maybe_stop
  data = JSON.load(json)
  [data['version'], data['drv']]
end

def maybe_stop
  exit if @abort
end

def get_date
  git_nixpkgs('show', '-s', '--format=%ci')
end

def get_rev
  git_nixpkgs('rev-parse', 'HEAD')
end

def checkout(rev, depth)
  git_nixpkgs('checkout', "#{rev}~#{depth}")
end

def git_nixpkgs(*args)
  run('git', '-C', NixpkgsPath, *args).strip
end

def run(*cmd)
  stdout, stderr, status = Open3.capture3(*cmd)
  if !status.success?
    raise "Command '#{cmd}' failed with output:\n#{stderr}"
  end
  stdout
end

class Log
  def initialize(dir: Dir.pwd)
    @changes = Hash.new{|h,k| h[k] = [] }
    @num_changes = 0
    @path = File.join(dir, "changes-#{StartRev[0..6]}.json")
    at_exit { write_log }
  end

  def write_log
    File.write(@path, JSON.pretty_generate(@changes) + "\n")
  end

  def add_change(change)
    puts "Found change #{change.to_h.except(:drv)}"
    @changes[change.version] << change.to_h.except(:version)
    @num_changes += 1
    write_log if @num_changes % 5 == 0
  end

  def print_depth(base, extra)
    puts "Checking depth #{base + extra} (Relative to last change: #{extra})"
  end
end

puts
puts "Press ENTER to cleanly exit this program"
puts
Thread.new do
  gets
  @abort = true
end

find_versions(versions_to_find: 10)
