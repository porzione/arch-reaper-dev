#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'ostruct'
require 'date'
require 'erb'
require 'open-uri'
require 'fileutils'
require 'digest'

OS = 'linux'

opt = OpenStruct.new
OptionParser.new do |opts|
  opts.on('-D', 'Debug') { opt.debug = true }
  opts.on('-r', '--release', 'Release') { opt.rel = true }
  opts.on('-v', '--version VERSION', 'Dev version') do |v|
    opt.ver = v
  end
  opts.on('-b', '--basever BASE', 'Base version, ex 6.25') do |b|
    opt.bver = b
  end
  opts.on('-d', '--destdir DIR',  'Destination dir') do |d|
    opt.ddir = d
  end
  opts.on('-a', '--arch arch',    'Arhitecture') do |a|
    opt.arch = a
  end
end.parse!

abort 'Need base version' unless opt.bver

pkgver = if opt.ver
           opt.ver =~ /rc\d/ ? "#{opt.bver}#{opt.ver}" : "#{opt.bver}+dev#{opt.ver}"
         elsif opt.rel
           opt.bver
         else
           "#{opt.bver}+dev#{DateTime.now.strftime('%m%d')}"
         end
puts "ver: #{pkgver}" if opt.debug

arch = opt.arch || RUBY_PLATFORM.match('^(\w+)-\w+$').captures.first
puts "target: #{arch}-#{OS}" if opt.debug

file = "reaper#{pkgver.tr('.', '')}_#{OS}_#{arch}.tar.xz"
dv = opt.bver.sub(/\d\d$/, 'x')
url = opt.rel ? "https://www.reaper.fm/files/#{dv}/#{file}" : "https://www.landoleet.org/#{file}"
puts "url: #{url}" if opt.debug

btotal = nil
unless File.exist?("#{__dir__}/#{file}")
  URI.parse(url).open('rb',
                      content_length_proc: lambda { |clen|
                                             btotal = clen
                                           },
                      progress_proc: lambda { |btrans|
                                       if btotal
                                         print("\r#{btrans}/#{btotal}")
                                       else
                                         print("\r#{btrans} (total size unknown)")
                                       end
                                     }) do |page|
    puts
    File.open("#{__dir__}/#{file}", 'wb') do |f|
      while (chunk = page.read(8192))
        f.write(chunk)
      end
    end
  end
end

digest = opt.rel ? Digest::SHA256.file("#{__dir__}/#{file}") : 'SKIP'
puts "sha256: #{digest}" if opt.debug
pkgbuild = "#{__dir__}/PKGBUILD"
tpl = ERB.new(File.read("#{__dir__}/PKGBUILD.erb"))
pkg = tpl.result_with_hash(
  pkgver:       pkgver,
  provides_ver: opt.bver,
  sha256sums:   digest,
  arch:         arch,
  os:           OS
)
File.write(pkgbuild, pkg, mode: 'w')

Dir.chdir(__dir__) { system 'makepkg -si' }

if opt.ddir
  src = "/var/cache/pacman/pkg/reaper-bin-dev-#{pkgver}-1-#{arch}.pkg.tar.zst"
  FileUtils.cp(src, opt.ddir)
end
