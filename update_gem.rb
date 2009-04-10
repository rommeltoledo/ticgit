#!/usr/bin/env ruby -wKU
  # This file is used to locally build and install the gem for quick
  # debugging
  puts "Build the Gem"
 `gem build ticgit.gemspec` 
 puts "Install the Gem"
 `sudo gem install ticgit-0.3.6.gem`