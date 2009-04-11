require 'logger'
require 'fileutils'
require 'yaml'

# TicGit Library
#
# This library implements a git based ticketing system in a git repo
#
# Author::    Scott Chacon (mailto:schacon@gmail.com)
# License::   MIT License
#

module TicGit
  # error class for no repository found
  class NoRepoFound < StandardError;end
  
  
  class Base

    attr_reader :git, :logger
    attr_reader :tic_working, :tic_index
    attr_reader :tickets, :last_tickets, :current_ticket  # (schacon's note)saved in state
    attr_reader :config
    attr_reader :state, :config_file
    
    # Called from Ticgit when initialized
    def initialize(git_dir, opts = {})
      # Open the git repositiry and create the git object
      @git = Git.open(find_repo(git_dir))
      # If a logger was passed assign it to the instance variable,
      # if not, then create a new to log to STDOUT
      @logger = opts[:logger] || Logger.new(STDOUT)
      
      # extract the git path and change / by - to create a folder 
      # so the folder name is like home-documents-projects-ticgit
      
      proj = Ticket.clean_string(@git.dir.path)
      
      # if the :tic_dir key pair exsts assign it to the instance variable, otherwise
      # use the home directory
      # TODO: This might be where to fix the "Non-consistent tickets" problem
      @tic_dir = opts[:tic_dir] || '~/.ticgit'
      
      # is the :working_directoy key pair exists use it, if not
      # create a directory tic_dir/proj/working
      @tic_working = opts[:working_directory] || File.expand_path(File.join(@tic_dir, proj, 'working'))
      puts tic_working
      
      # load the index file
      @tic_index = opts[:index_file] || File.expand_path(File.join(@tic_dir, proj, 'index'))
      
      # load config file which as far as I can tell it only contains the saved list options
      @config_file = File.expand_path(File.join(@tic_dir, proj, 'config.yml'))
      if File.exists?(config_file)
        @config = YAML.load(File.read(config_file))
      else
        @config = {}
      end
      
      # Load the state file
      @state = File.expand_path(File.join(@tic_dir, proj, 'state'))
      
      
      if File.exists?(@state)
        load_state
        # reset_ticgit
      else
        reset_ticgit
      end
    end
    
    def find_repo(dir)
      full = File.expand_path(dir)
      # ENV is the has containing the key-pairs of your environment such as
      # MANPATH, TERM_PROGRAM, DISPLAY.
      # This either gets the GIT_WORKING_DIR key-pair OR goes into a loop 
      # to find the .git repository in dir
      ENV["GIT_WORKING_DIR"] || loop do
        return full if File.directory?(File.join(full, ".git"))
        # if none is found then raise the exception
        raise NoRepoFound if full == full=File.dirname(full)
      end
    end
    
    def save_state
      # marshal dump the internals to the local directory
      # TODO: Maybe the state should be inside the ticgit repository so it travels with it?
      #       or not because then different users could not save their current state
      #       but, what should be is some sort of flag to rebuild the state when fetching
      #       updates from a repository and at the same time preserve the state, specially
      #       current tickets
      File.open(@state, 'w') { |f| Marshal.dump([@tickets, @last_tickets, @current_ticket], f) } rescue nil
      # save config file. 
      # Note that it is using the accessor method for config instead of the instance variable
      # is there a particular reason for that?
      File.open(@config_file, 'w') { |f| f.write(config.to_yaml) }
    end
    
    def load_state
      # read in the internals
      if(File.exists?(@state))
        @tickets, @last_tickets, @current_ticket = File.open(@state) { |f| Marshal.load(f) } rescue nil
      end      
    end
    
    # returns new Ticket
    def ticket_new(title, options = {})
      #  Create a new ticket 
      t = TicGit::Ticket.create(self, title, options)
      #  reset ticgit
      reset_ticgit
      # open the ticket just created
      TicGit::Ticket.open(self, t.ticket_name, @tickets[t.ticket_name])
    end

    def reset_ticgit
      load_tickets
      save_state
    end
    
    def ticket_comment(comment, ticket_id = nil)
      #  if the reverse parsing finds the ticket
      if t = ticket_revparse(ticket_id)        
        #  open the ticket
        ticket = TicGit::Ticket.open(self, t, @tickets[t])
        #  add the comment
        ticket.add_comment(comment)
        #  and reset ticgit
        reset_ticgit
      end
    end
    
    # returns array of Tickets 
    def ticket_list(options = {})
      #  create local empty array
      ts = []
      #  clear the last tickets instance variable
      @last_tickets = []
      # if the config instance variable hash has the 'list_options' key-pair, use it
      #  if not create an empty hash
      @config['list_options'] ||= {}
      
      # add each ticket to the local ts array
      @tickets.to_a.each do |name, t|
        ts << TicGit::Ticket.open(self, name, t)
      end

      # assign to the variable the key-pair :saved in the options hash
      # if it exists, name will not be nil and execution will go into the if 
      # statement
      if name = options[:saved]
        # if the name is valid it will be assigned to c, which will contain a key pair
        # with the options for that name, i.e. :tag=>"features"
         if c = config['list_options'][name]
           # add the options for that saved name to the options hash
           options = c.merge(options)
         end
      end   
      
      # if the options hash contains the :list key-pair means that the end
      # user wants to see a list of saved lists
      if options[:list]
        # TODO : this is a hack and i need to fix it (schacon's note)
        # create string with the saved parameters for each named list
        config['list_options'].each do |name, opts|
          puts name + "\t" + opts.inspect
        end
        # exit you are done with the listing
        return false
      end   
       
      
      # if the :order key-pair exists, then the list needs to be sorted
      # the order is typically given by field.type, i.e. date.desc
      # by default it is ascending
      if field = options[:order]
        # split the type from field
        field, type = field.split('.')
        # act based on the field, sort ascending by default
        case field
        when 'assigned'
          ts = ts.sort { |a, b| a.assigned <=> b.assigned }
        when 'state'
          ts = ts.sort { |a, b| a.state <=> b.state }
        when 'date'
          ts = ts.sort { |a, b| a.opened <=> b.opened }
        end    
        
        # if the type was given as descending then reverse the array
        ts = ts.reverse if type == 'desc'
      else
        # default list. If no ordering was given, order by ascending date
        ts = ts.sort { |a, b| a.opened <=> b.opened }
      end

      # if no options were given, add the state key-pair with open as value
      if options.size == 0
        # default list
        options[:state] = 'open'
      end
      
      # :tag it selects the elements in the array ts if the tags include the 
      # option given in the key-pair :tag
      if t = options[:tag]
        ts = ts.select { |tag| tag.tags.include?(t) }
      end
      
      # :state it selects based on the state
      if s = options[:state]
        ts = ts.select { |tag| tag.state =~ /#{s}/ }
      end
      
      # it selects based on the assigned
      if a = options[:assigned]
        ts = ts.select { |tag| tag.assigned =~ /#{a}/ }
      end
      
      # if the options contain the :save key-pair, it means that that particular search will
      # be saved in the config file. Note that the :save key-pair is removed before saving 
      # to avoid saving the same option every time the list name is invoked
      if save = options[:save]
        options.delete(:save)
        @config['list_options'][save] = options
      end
      
      # populates the last tickets instance by scrolling each element in ts
      # note that this happens after all the options have been parsed
      @last_tickets = ts.map { |t| t.ticket_name }
      
      # save the state. Particularly relevant if an option to save was given. Useless otherwise
      # TODO: move save state inside the if of :save ?
      save_state
      
      # return the recently populated local array with the tickets
      ts
    end
    
    # returns single Ticket
    def ticket_show(ticket_id = nil)      
      # (schacon's note)ticket_id can be index of last_tickets, partial sha or nil => last ticket
      # if reverse parse returns a valid ticket (i.e. not null)
      if t = ticket_revparse(ticket_id)
        # open and show the ticket
        return TicGit::Ticket.open(self, t, @tickets[t])
      end
    end
    
    # (schacon's note)returns recent ticgit activity
    # (schacon's note)uses the git logs for this
    def ticket_recent(ticket_id = nil)  
      # if a ticket_id was given
      if ticket_id
        # reverse parse it
        t = ticket_revparse(ticket_id) 
        # returnt its git history from the ticgit branch
        return git.log.object('ticgit').path(t)
      else 
        # return the whole history
        # TODO: this might be kind of crazy for a long running repository. Trim to results within
        #       a given amount of days/weeks. Afterall, it is RECENT
        return git.log.object('ticgit')
      end
    end
    
    
    def ticket_revparse(ticket_id)
      # if a ticket id was given
      if ticket_id
        # the ticket id matches the regular expresson which is looking for a number 
        # or multiple occurances of a number, than it is likely you are selecting from a
        # listing (i.e. 1,2,3... etch)
        if /^[0-9]*$/ =~ ticket_id
          # if it matches then just extract it from the array and return that ticket
          if t = @last_tickets[ticket_id.to_i - 1]
            return t
          end
        else
          # if it did not match
          # (schacon's note) partial or full sha
          if ch = @tickets.select { |name, t| t['files'].assoc('TICKET_ID')[1] =~ /^#{ticket_id}/ }
            return ch.first[0]
          end
        end
      # if no ticket id was given but there is a current ticket then return the current ticket
      elsif(@current_ticket)
        return @current_ticket
      end
    end    

    
    def ticket_tag(tag, ticket_id = nil, options = {})
      # if a valid ticket_id is found
      if t = ticket_revparse(ticket_id)
        # open the ticket
        ticket = TicGit::Ticket.open(self, t, @tickets[t])
        # add or remove the tag according to the options
        if options[:remove]
          ticket.remove_tag(tag)
        else
          ticket.add_tag(tag)
        end
        # reset the ticgit repository
        reset_ticgit
      end
    end
        
    def ticket_change(new_state, ticket_id = nil)
      # if a valid ticket_id is found
      if t = ticket_revparse(ticket_id)
        # if the new_state is a valid state
        # TODO: Why is tic_states a method? is this a ruby design pattern?
        if tic_states.include?(new_state)
          # get the ticket
          ticket = TicGit::Ticket.open(self, t, @tickets[t])
          # assign the new state
          ticket.change_state(new_state)
          # reset the ticgit repository
          reset_ticgit
        end
      end
    end

    def ticket_assign(new_assigned = nil, ticket_id = nil)
      if t = ticket_revparse(ticket_id)
        ticket = TicGit::Ticket.open(self, t, @tickets[t])
        ticket.change_assigned(new_assigned)
        reset_ticgit
      end
    end
    
    def ticket_checkout(ticket_id)
      if t = ticket_revparse(ticket_id)
        ticket = TicGit::Ticket.open(self, t, @tickets[t])
        # assign the found ticket to the current_ticket instance var
        @current_ticket = ticket.ticket_name
        # save that in the config file
        save_state
      end
    end
    
    def comment_add(ticket_id, comment, options = {})
    end

    def comment_list(ticket_id)
    end
     
    # Why is this a method instead of a hash or a variable?
    def tic_states
      ['open', 'resolved', 'invalid', 'hold']
    end
        

    def load_tickets
      # create the empty hash
      @tickets = {}
      # get the current repository branches. Branches are returned in arrays
      # as ["branch_name", is_current?]
      bs = git.lib.branches_all.map { |b| b[0] }
      
      # if ticgit is not in the branches the working directory does not exist
      # initialize the ticgit branch
      init_ticgit_branch(bs.include?('ticgit')) if !(bs.include?('ticgit') && File.directory?(@tic_working))
      
      # tree is an array witch contains mode, type, sha, file/folder for each
      # object in the branch ticgit
      # each element in the array looks like:
      #  "100644 blob 3074cf018984581d1015ed2fc08b9155b5447ff4\t1206206148_add-attachment-to-ticket_138/COMMENT_1206206148_schacon@gmail.com"
      tree = git.lib.full_tree('ticgit')
      
      tree.each do |t|
        # split the data accordingly
        data, file = t.split("\t")
        mode, type, sha = data.split(" ")
        tic = file.split('/')
        # if tic is a directory
        if tic.size == 2  # (schacon's note) directory depth
          ticket, info = tic
          # the key looks like "1206206148_add-attachment-to-ticket_138"
          @tickets[ticket] ||= { 'files' => [] }
          # append info and sha
          @tickets[ticket]['files'] << [info, sha]
        end
      end
    end
    
    def init_ticgit_branch(ticgit_branch = false)
      @logger.info 'creating ticgit repo branch'
      
      # if switching to the ticgit_branch succeeds
      # in branch yields a Git::WorkingDirectory
      in_branch(ticgit_branch) do          
       # create the hold file
        new_file('.hold', 'hold')
        # if ticgit_branch did not exist
        if !ticgit_branch
          #  add
          git.add
          #  create tjhe initial commit
          git.commit('creating the ticgit branch')
        end
      end
    end
    
    # temporarlily switches to ticgit branch for tic work
    def in_branch(branch_exists = true)
      needs_checkout = false
      # if the tic_working directory does not exist
      if !File.directory?(@tic_working)
        # create it
        FileUtils.mkdir_p(@tic_working)
        # mark for checkout
        needs_checkout = true
      end
      
      # if the hold file does not exist
      if !File.exists?('.hold')
        # mark for checkout
        needs_checkout = true
      end
      
      # capture the current branch
      old_current = git.lib.branch_current
      
      # Start protected block using Ensure
      #  Not really sure what this block does. I would think that a simple
      # git checkout would be sufficient but apparently not. Need to look
      # further into this.
      begin
        # switch the HEAD ref-link to point to branch ticgit
        git.lib.change_head_branch('ticgit')
        
        # @tic_index is a string pointing to the tic index file
        # i.e. /Users/malifeMb/.ticgit/-users-malifemb-documents-mariano-development-ror-ticgit/index
        git.with_index(@tic_index) do          
          git.with_working(@tic_working) do |wd|
            # checkout ticgit
            git.lib.checkout('ticgit') if needs_checkout && branch_exists
            yield wd  # wd is Git::WorkingDirectory which is a string 
          end
        end
      ensure
        # if something fails make sure you return to the branch you were
        # in
        git.lib.change_head_branch(old_current)
      end
    end
          
    def new_file(name, contents)
      # Create  file
      File.open(name, 'w') do |f|
        f.puts contents
      end
    end
   
  end
end