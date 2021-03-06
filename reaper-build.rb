#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'ostruct'
require 'date'
require 'tempfile'
require 'open-uri'
require 'fileutils'
require 'digest'

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
  opts.on('-d', '--destdir DIR', 'Destination dir') do |d|
    opt.ddir = d
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

file = "reaper#{pkgver.tr('.', '')}_linux_x86_64.tar.xz"
url = "https://www.landoleet.org/#{file}"
puts url if opt.debug

btotal = nil
unless File.exist?(file)
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
    File.open("#{__dir__}/#{file}", 'wb') do |f|
      while (chunk = page.read(8192))
        f.write(chunk)
      end
    end
  end
end

digest = Digest::SHA256.file(file)
puts digest if opt.debug
pkgbuild = "#{__dir__}/PKGBUILD"
tmp = Tempfile.new
tmp.write(
  File.read(pkgbuild)
  .sub(/(?<=^pkgver=).+/, pkgver)
  .sub(/(?<=^sha256sums=).+/, "('#{digest}')")
  .sub(/(?<=^provides=\('reaper-bin=)[^']+/, opt.bver)
)
tmp.close

FileUtils.mv(tmp.path, "#{__dir__}/PKGBUILD")

Dir.chdir(__dir__) { system 'makepkg -si' }

if opt.ddir
  FileUtils.cp(
    "/var/cache/pacman/pkg/reaper-bin-dev-#{pkgver}-1-x86_64.pkg.tar.zst",
    opt.ddir
  )
end
