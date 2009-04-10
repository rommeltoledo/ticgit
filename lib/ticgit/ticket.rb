# TicGit Library
#
# This library implements a git based ticketing system in a git repo
#
# Authors::    Scott Chacon (mailto:schacon@gmail.com), PaulBone (http://github.com/paulboone)
# License::   MIT License
#

module TicGit
  class Ticket
  
    attr_reader :base, :opts
    attr_accessor :ticket_id, :ticket_name
    attr_accessor :title, :state, :milestone, :assigned, :opened
    attr_accessor :comments, :tags, :attachments # arrays
    
    def initialize(base, options = {})
      # read the user name and email from the git config
      options[:user_name] ||= base.git.config('user.name') 
      options[:user_email] ||= base.git.config('user.email')      
      
      
      @base = base
      # if not options are given initialize the has empty
      @opts = options || {}
      
      @state = 'open' # by default
      
      # note that comments, tags and attachments are arrays
      @comments = []
      @tags = []
      @attachments = []
    end
  
    def self.create(base, title, options = {})
      t = Ticket.new(base, options)
      t.title = title
      # create_ticket_name creates a ticket name of the type:
      # time_title_randomNumber
      t.ticket_name = self.create_ticket_name(title)
      # add the ticket to the ticgit repository and return it
      t.save_new
      t
    end
    
    def self.open(base, ticket_name, ticket_hash, options = {})
      tid = nil
      
      # create a new ticket and assign the name
      t = Ticket.new(base, options)
      t.ticket_name = ticket_name
      
      # get the title and date based on the ticket name
      title, date = self.parse_ticket_name(ticket_name)
      
      # assign it
      t.title = title
      t.opened = date
      
      # parse the values of each of the "files" in the ticket hash
      # and assign the values accordingly
      ticket_hash['files'].each do |fname, value|
        if fname == 'TICKET_ID'
          tid = value
        else
          # matching
          data = fname.split('_')
          if data[0] == 'ASSIGNED'
            t.assigned = data[1]
          end
          if data[0] == 'ATTACHMENT'
            t.attachments << TicGit::Attachment.new(base,fname,value)
          end
          if data[0] == 'COMMENT'
            t.comments << TicGit::Comment.new(base, fname, value)
          end
          if data[0] == 'TAG'
            t.tags << data[1]
          end
          if data[0] == 'STATE'
            t.state = data[1]
          end          
        end
      end
      
      t.ticket_id = tid
      t
    end
    
    
    def self.parse_ticket_name(name)
      # separate the ticket name components
      epoch, title, rand = name.split('_')
      # remove the dashes and replace them with spaces
      title = title.gsub('-', ' ')
      # return title and date
      return [title, Time.at(epoch.to_i)]
    end
    
    # write this ticket to the git database
    def save_new
      # in_branch changes to the ticgit branch and yields the branch path
      # in the form of a Git::WorkingBranch
      base.in_branch do |wd|
        base.logger.info "saving #{ticket_name}"
        
        # each ticket has its own directory
        Dir.mkdir(ticket_name)
        Dir.chdir(ticket_name) do
          # note that values in the ticket are actual file names
          # AND its contents, except for TICKET_ID
          base.new_file('TICKET_ID', ticket_name)
          base.new_file('ASSIGNED_' + email, email)
          base.new_file('STATE_' + state, state)
          
          # add initial comment
          #COMMENT_080315060503045__schacon_at_gmail
          base.new_file(comment_name(email), opts[:comment]) if opts[:comment]

          # add initial tags
          #  note that there can be an infinite ammount of TAG_tag 
          # files. One for each tag (fileName == content)
          if opts[:tags] && opts[:tags].size > 0
            opts[:tags] = opts[:tags].map { |t| t.strip }.compact
            opts[:tags].each do |tag|
              if tag.size > 0
                tag_filename = 'TAG_' + Ticket.clean_string(tag)
                if !File.exists?(tag_filename)
                  base.new_file(tag_filename, tag_filename)
                end
              end
            end
          end            
        end
	      
        # add all the contents of the directory
        base.git.add
        # commit the changes
        base.git.commit("added ticket #{ticket_name}")
      end
      # ticket_id
    end
    
    def self.clean_string(string)
      # change everything to lowercase and replace anything that is not
      # in the regexpr for dashes
      string.downcase.gsub(/[^a-z0-9]+/i, '-')
    end
    
    def add_comment(comment)
      # exit if not comment is given
      return false if !comment
      # in_branch changes to the ticgit branch and yields the branch path
      # in the form of a Git::WorkingBranch
      base.in_branch do |wd|
        # change to the ticket name directory
        Dir.chdir(ticket_name) do
          # add the comment file
          base.new_file(comment_name(email), comment) 
        end
        # add the file
        base.git.add
        # commit the changes
        base.git.commit("added comment to ticket #{ticket_name}")
      end
    end
    
    def add_attachment(file) 
      # in_branch changes to the ticgit branch and yields the branch path
      # in the form of a Git::WorkingBranch 
      base.in_branch do |wd|
        # change the directory to the current ticket name
        Dir.chdir(ticket_name) do
          # copy the file to the ticgit branch
          FileUtils.copy(file,attachment_name(email,File.basename(file)))
        end
        # add it and commit it with the message
        # TODO: Include the filename in the commit message
        base.git.add
        base.git.commit("added attachment to ticket #{ticket_name}")
      end
    end

    def change_state(new_state)
      # exit if no state is given or the given state is the same as the current
      return false if !new_state
      return false if new_state == state

      # in_branch changes to the ticgit branch and yields the branch path
      # in the form of a Git::WorkingBranch
      base.in_branch do |wd|
        # change the directory
        Dir.chdir(ticket_name) do
          # create the state file
          base.new_file('STATE_' + new_state, new_state)
        end
        # remove the old state file
        base.git.remove(File.join(ticket_name,'STATE_' + state))
        # add the new file to the repository
        base.git.add
        # commit the changes
        base.git.commit("added state (#{new_state}) to ticket #{ticket_name}")
        # TODO: Note that state is not changed to new_state
      end
    end

    def change_assigned(new_assigned)
      # if new_assigned is nil, assign it from email
      new_assigned ||= email
      # if no change the exit
      return false if new_assigned == assigned

      # in_branch changes to the ticgit branch and yields the branch path
      # in the form of a Git::WorkingBranch
      base.in_branch do |wd|
        # change the current directory
        Dir.chdir(ticket_name) do
          # create the assigned file
          base.new_file('ASSIGNED_' + new_assigned, new_assigned)
        end
        # remove the old assigned file
        base.git.remove(File.join(ticket_name,'ASSIGNED_' + assigned))
        # add it to the repository
        base.git.add
        # and commit the changes
        base.git.commit("assigned #{new_assigned} to ticket #{ticket_name}")
        # TODO: Again, assigned is not changed to new_assigned
      end
    end
    
    def add_tag(tag)
      # exit if no tag is given
      return false if !tag
      # the added flag determines if a git add/commit is necessary
      added = false
      # split the tags and remove leading and trainling spaces
      tags = tag.split(',').map { |t| t.strip }
      
      # in_branch changes to the ticgit branch and yields the branch path
      # in the form of a Git::WorkingBranch
      base.in_branch do |wd|
        # change the current directory to the ticket's directory
        Dir.chdir(ticket_name) do
          # for each tag
          tags.each do |add_tag|
            if add_tag.size > 0
              # create the filename
              tag_filename = 'TAG_' + Ticket.clean_string(add_tag)
              # if the file does not exist
              if !File.exists?(tag_filename)
                # create the file
                base.new_file(tag_filename, tag_filename)
                # flag that new tag was added
                added = true
              end
            end
          end
        end
        # if a new tag was added
        if added
          # add it to the git repository and  commit it with a message
          base.git.add
          base.git.commit("added tags (#{tag}) to ticket #{ticket_name}")
        end
      end
    end
    
    def remove_tag(tag)
      # exit if no tag is given
      return false if !tag
      # removed determines whether a tag was eliminated or not
      removed = false
      
      # split and remove the trainling spaces from the tags
      tags = tag.split(',').map { |t| t.strip }
      
      # in_branch changes to the ticgit branch and yields the branch path
      # in the form of a Git::WorkingBranch
      base.in_branch do |wd|
        # with each tag
        tags.each do |add_tag|
          # form the name it would have been added with
          tag_filename = File.join(ticket_name, 'TAG_' + Ticket.clean_string(add_tag))
          # if the file exists delete it
          if File.exists?(tag_filename)
            base.git.remove(tag_filename)
            removed = true
          end
        end
        # if files were removed, commit the repository with a message
        if removed
          base.git.commit("removed tags (#{tag}) from ticket #{ticket_name}")
        end
      end
    end
    
    def path
      # retunr state/ticket_name
      File.join(state, ticket_name)
    end
    
    
    def attachment_name(email,filename)
      'ATTACHMENT_' + Time.now.to_i.to_s + '_' + email + "@@" + filename
    end
    def comment_name(email)
      # returns the string of form: 
      # COMMENT_1206565689_schacon@gmail.com
      'COMMENT_' + Time.now.to_i.to_s + '_' + email
    end
    
    
    def email
      # if the email does not exist in the options has return "anon"
      opts[:user_email] || 'anon'
    end
    
    def assigned_name
      # return login from an email if non exists, return ''
      assigned.split('@').first rescue ''
    end
    
    def self.create_ticket_name(title)
      # creates a ticket name of the form:
      # 1206565689_find-the-git-directory-properly-_425
      [Time.now.to_i.to_s, Ticket.clean_string(title), rand(999).to_i.to_s].join('_')
    end

    
  end
end
