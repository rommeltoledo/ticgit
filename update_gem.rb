#!/usr/bin/env ruby -wKU
  puts "Build the Gem"
 `gem build ticgit.gemspec` 
 puts "Install the Gem"
 `sudo gem install ticgit-0.3.6.gem`