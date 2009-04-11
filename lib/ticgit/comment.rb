# TicGit Library
#
# This library implements a git based ticketing system in a git repo
#
# Author::    Scott Chacon (mailto:schacon@gmail.com)
# License::   MIT License
#

module TicGit
  class Comment
    
    attr_reader :base, :user, :added, :comment
    
    def initialize(base, file_name, sha)
      @base = base
      @comment = base.git.gblob(sha).contents rescue nil
      
      # obtain type (COMMENT in this case), date and user
      type, date, user = file_name.split('_')
      
      @added = Time.at(date.to_i)
      @user = user
    end
    
  end
end