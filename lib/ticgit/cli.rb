require 'ticgit'
require 'optparse'

#  To build the gem locally 
#  gem build ticgit.gemspec 
#  to install it
#  sudo gem install ticgit-0.3.6.gem

# used Cap as a model for this - thanks Jamis

module TicGit
  class CLI
    # The array of (unparsed) command-line options
    attr_reader :action, :options, :args, :tic

    def self.execute
      # Call self.parse in cli.rb
      # then parse returns a cli object which 
      # in turn calls execute!
      parse(ARGV).execute!
    end
    
    def self.parse(args)
      # call initialize in cli.rb passing the arguments to it
      cli = new(args)
      # call parse_options! in cli.rb and verify that there are 
      # options, if there are, the first one is the action 
      cli.parse_options!
      # return cli
      cli
    end

    def initialize(args)
      # create a shallow copy of the arguments
      @args = args.dup
      # call open method in ticgit.rb, this in turn creates a new
      # base from base.rb
      @tic = TicGit.open('.', :keep_state => true)
      # no idea what this does
      $stdout.sync = true # so that Net::SSH prompts show up
    # this is exception handling in case NoRepoFound
    # NoRepoFound is a class tha inherits from StandardError
    rescue NoRepoFound
      # print message and exit
      puts "No repo found"
      exit
    end    
    
    # when the code reaches this point action has already been 
    # filled (by parse_options!). Handle the action accordingly
    def execute!
      case action
      when 'list':
        handle_ticket_list
      when 'state'
        handle_ticket_state
      when 'assign'
        handle_ticket_assign
      when 'show'
        handle_ticket_show
      when 'new'
        handle_ticket_new
      when 'checkout', 'co'
        handle_ticket_checkout
      when 'comment'
        handle_ticket_comment
      when 'tag'
        handle_ticket_tag
      when 'recent'
        handle_ticket_recent
      when 'milestone'
        # there is a bug here, 
        # TODO: Create a handle_ticket_milestone method
        handle_ticket_milestone
      else
        puts 'not a command'
      end
    end

    # ======================================================
    #                 Action Handling
    # ======================================================
    
    # List
    # ====

    def handle_ticket_list
      #  Parse the command line options and modify the 
      #  options instance variable
      parse_ticket_list

      
      #  If ARGV[1] has a value it means I requested a previously saved
      #  list, assign the name of the saved list to options[:saved]
      options[:saved] = ARGV[1] if ARGV[1]
      

      
      #  tic.ticket_list returns an array of tickets
      if tickets = tic.ticket_list(options)
        counter = 0
      
        puts
        # print the list header
        puts [' ', just('#', 4, 'r'), 
              just('TicId', 6),
              just('Title', 25), 
              just('State', 5),
              just('Date', 5),
              just('Assgn', 8),
              just('Tags', 20) ].join(" ")
            
        # print the horizontal bar
        a = []
        80.times { a << '-'}
        puts a.join('')

        # For each ticket in the array
        tickets.each do |t|
          # increase the counter for ticket display
          counter += 1
          # if the ticket is equals to the checked out ticket
          # add an asteriks
          tic.current_ticket == t.ticket_name ? add = '*' : add = ' '
          #display the ticket information
          puts [add, just(counter, 4, 'r'), 
                t.ticket_id[0,6], 
                just(t.title, 25), 
                just(t.state, 5),
                t.opened.strftime("%m/%d"), 
                just(t.assigned_name, 8),
                just(t.tags.join(','), 20) ].join(" ")
        end
        puts
      end
    end

    def parse_ticket_list
      # create an empty hash
      @options = {}
      
      # start the option parser
      OptionParser.new do |opts|
        # add the banner
        opts.banner = "Usage: ti list [options]"
        
        # add all the options to the command line
        opts.on("-o ORDER", "--order ORDER", "Field to order by - one of : assigned,state,date") do |v|
          @options[:order] = v
        end
        
        opts.on("-t TAG", "--tag TAG", "List only tickets with specific tag") do |v|
          @options[:tag] = v
        end
        
        opts.on("-s STATE", "--state STATE", "List only tickets in a specific state") do |v|
          @options[:state] = v
        end
        
        opts.on("-a ASSIGNED", "--assigned ASSIGNED", "List only tickets assigned to someone") do |v|
          @options[:assigned] = v
        end
        
        opts.on("-S SAVENAME", "--saveas SAVENAME", "Save this list as a saved name") do |v|
          @options[:save] = v
        end
        
        opts.on("-l", "--list", "Show the saved queries") do |v|
          @options[:list] = true
        end
      end.parse!
    end
    
    # State
    # =====

    # Parses the ticket and ticket state, verifies that the new
    # state is valid and if so changes the state
    def handle_ticket_state
      # if there are two arguments
      if ARGV.size > 2
        
        #  first argunment is the ticket
        tid = ARGV[1].chomp
        # second argument is the state
        new_state = ARGV[2].chomp
        
        # check that the new state is valid from the pool of valid
        # states; if it is, change the state
        if valid_state(new_state)
          tic.ticket_change(new_state, tid)
        else
          puts 'Invalid State - please choose from : ' + tic.tic_states.join(", ")
        end
      # if just one argument then assume working with current ticket
      elsif ARGV.size > 1
        # new state is applied to the current ticket
        # TODO: Check that there is a current ticket selected
        new_state = ARGV[1].chomp
        if valid_state(new_state)
          tic.ticket_change(new_state)
        else
          puts 'Invalid State - please choose from : ' + tic.tic_states.join(", ")
        end
      else  
        puts 'You need to at least specify a new state for the current ticket'
      end
    end
    
    # verifies that the state is a valid ticket state
    # note that this does not follow the Ruby convention of ending
    # the boolean return functions with a "?" check the book
    # to see if when parameters are passed the ? is not used
    def valid_state(state)
      tic.tic_states.include?(state)
    end
    
    # Assign
    # ======

    # Assigns a ticket to someone
    #
    # Usage:
    # ti assign             (assign checked out ticket to current user)
    # ti assign {1}         (assign ticket to current user)
    # ti assign -c {1}      (assign ticket to current user and checkout the ticket)
    # ti assign -u {name}   (assign ticket to specified user)
    def handle_ticket_assign
      parse_ticket_assign
      
      # if a checkout option was given, then check it out
      tic.ticket_checkout(options[:checkout]) if options[:checkout]
      
      # if a ticket id was given
      tic_id = ARGV.size > 1 ? ARGV[1].chomp : nil
      # assing the ticket to the specified user
      # TODO: No user pool exists, ideally there should be one.
      # TODO: Add a user catalog and verify before assing the ticket that the user is valid
      tic.ticket_assign(options[:user], tic_id)
    end

    
    def parse_ticket_assign
      # create an empty hash
      @options = {}
      # start the options parser
      OptionParser.new do |opts|
        # add the banner
        opts.banner = "Usage: ti assign [options] [ticket_id]"
        
        # Select user
        opts.on("-u USER", "--user USER", "Assign the ticket to this user") do |v|
          @options[:user] = v
        end
        
        # select ticket
        opts.on("-c TICKET", "--checkout TICKET", "Checkout this ticket") do |v|
          @options[:checkout] = v
        end
      end.parse!
    end

    # Show
    # ====
    
    def handle_ticket_show
      # if the given argument is a valid ticket progressive ID or sha 
      if t = @tic.ticket_show(ARGV[1])
        ticket_show(t)
      end
    end
    
    def ticket_show(t)
      #  Display the ticket header
      days_ago = ((Time.now - t.opened) / (60 * 60 * 24)).round.to_s
      puts
      puts just('Title', 10) + ': ' + t.title
      puts just('TicId', 10) + ': ' + t.ticket_id
      puts
      puts just('Assigned', 10) + ': ' + t.assigned.to_s 
      puts just('Opened', 10) + ': ' + t.opened.to_s + ' (' + days_ago + ' days)'
      puts just('State', 10) + ': ' + t.state.upcase
      
      # display the ticket tags
      if !t.tags.empty?
        puts just('Tags', 10) + ': ' + t.tags.join(', ')
      end
      puts
      
      # display the ticket comments
      if !t.comments.empty?
        
        # put the comments header
        puts 'Comments (' + t.comments.size.to_s + '):'
        # add them in reverse order
        t.comments.reverse.each do |c|
          # include when the comment was added
          puts '  * Added ' + c.added.strftime("%m/%d %H:%M") + ' by ' + c.user
          
          # wrap the comment to 80 columns
          wrapped = c.comment.split("\n").collect do |line|
            line.length > 80 ? line.gsub(/(.{1,80})(\s+|$)/, "\\1\n").strip : line
          end * "\n"
          
          wrapped = wrapped.split("\n").map { |line| "\t" + line }
          if wrapped.size > 6
            puts wrapped[0, 6].join("\n")
            puts "\t** more... **"
          else
            puts wrapped.join("\n")
          end
          puts
        end
      end
    end
    
    # New
    # ===
    
    def parse_ticket_new
      # empty hash
      @options = {}
      # just one command line option, the ticket title
      # TODO: Ideally the title should be limited to a certain number of characters
      OptionParser.new do |opts|
        opts.banner = "Usage: ti new [options]"
        opts.on("-t TITLE", "--title TITLE", "Title to use for the name of the new ticket") do |v|
          @options[:title] = v
        end
      end.parse!
    end
    
    def handle_ticket_new
      # parse the command line options
      parse_ticket_new
      
      # if the hash options contains the key-pair :title
      if(t = options[:title])
        # then create the ticket and then show it
        ticket_show(@tic.ticket_new(t, options))
      else
        # if no title was given then the addition is interactive
        # create a TempFile
        message_file = Tempfile.new('ticgit_message').path
        # open it
        File.open(message_file, 'w') do |f|
          # add a header with instructions
          f.puts "\n# ---"
          f.puts "tags:"
          f.puts "# first line will be the title of the tic, the rest will be the first comment"
          f.puts "# if you would like to add initial tags, put them on the 'tags:' line, comma delim"
        end
        # if message is valid
        if message = get_editor_message(message_file)
          # get the title
          title = message.shift
          #  if the trimmed title is larger than 0
          if title && title.chomp.length > 0
            # read the title
            title = title.chomp
            # get the tags
            if message.last[0, 5] == 'tags:'
              tags = message.pop
              tags = tags.gsub('tags:', '')
              tags = tags.split(',').map { |t| t.strip }
            end
            # get the comment
            if message.size > 0
              comment = message.join("")
            end
            # display the ticket
            ticket_show(@tic.ticket_new(title, :comment => comment, :tags => tags))
          else
            puts "You need to at least enter a title"
          end
        else
          puts "It seems you wrote nothing"
        end
      end
    end
    
    
    def get_editor_message(message_file = nil)
      # if the message file is nil, create a new message
      message_file = Tempfile.new('ticgit_message').path if !message_file
      
      # if the environment editor has been defined, use it, if not use vi
      editor = ENV["EDITOR"] || 'vim'
      
      # open the file in the editor
      system("#{editor} #{message_file}");
      
      # read the file
      message = File.readlines(message_file)
      # remove the comments
      message = message.select { |line| line[0, 1] != '#' } 
      # if no message is left return false
      if message.empty?
        return false
      else
        # otherwise return the actual message
        return message
      end   
    end

    # Checkout
    # ========
    
    def handle_ticket_checkout
      # get the first argument
      tid = ARGV[1].chomp
      # assign the tecket as checked out
      tic.ticket_checkout(tid)
    end
    
    # Comment
    # =======
    
    def parse_ticket_comment
      # empty hash
      @options = {}
      # start the options parser
      OptionParser.new do |opts|
        # configure the banner
        opts.banner = "Usage: ti comment [tic_id] [options]"
        
        # command line options
        opts.on("-m MESSAGE", "--message MESSAGE", "Message you would like to add as a comment") do |v|
          @options[:message] = v
        end
        
        # option to add a file that contains the comments
        opts.on("-f FILE", "--file FILE", "A file that contains the comment you would like to add") do |v|
          raise ArgumentError, "Only 1 of -f/--file and -m/--message can be specified" if @options[:message]
          raise ArgumentError, "File #{v} doesn't exist" unless File.file?(v) 
          raise ArgumentError, "File #{v} must be <= 2048 bytes" unless File.size(v) <= 2048
          @options[:file] = v
        end
      end.parse!
    end

    def handle_ticket_comment
      # parse the command line options
      parse_ticket_comment
      
      # get a valid ticket id
      tid = nil
      tid = ARGV[1].chomp if ARGV[1]
      
      # if the options hash contains a :mesasge key-pair
      if(m = options[:message])
        # add the comment to the ticket
        tic.ticket_comment(m, tid)
      elsif(f = options[:file])
        # elseif the options has a :file key-pair
        # get the comment directly from the file
        tic.ticket_comment(File.read(options[:file]), tid)
      else
        # finally if no message is given then get it from an editor
        if message = get_editor_message
          #  Add the comment
          # TODO: verify tha the message actually contains text
          tic.ticket_comment(message.join(''), tid)
        end
      end
    end

    # Tag
    # ===
    def parse_ticket_tag
      # empty hash
      @options = {}
      # start the command line parser
      OptionParser.new do |opts|
        # set the banner
        opts.banner = "Usage: ti tag [tic_id] [options] [tag_name] "
        
        # option to remove the banner
        opts.on("-d", "Remove this tag from the ticket") do |v|
          @options[:remove] = v
        end
      end.parse!
    end
    
    def handle_ticket_tag
      parse_ticket_tag
      
      # if the options contains the :remove key-pair
      if options[:remove]
        puts 'remove'
      end
      
      
      tid = nil
      # if ticket number was given
      if ARGV.size > 2
        # get the id
        tid = ARGV[1].chomp
        # and tag it (or remove it based on the options)
        tic.ticket_tag(ARGV[2].chomp, tid, options)
      elsif ARGV.size > 1
        # if no ticket was given the it is assumed to be the checked out
        tic.ticket_tag(ARGV[1], nil, options)
      else  
        puts 'You need to at least specify one tag to add'
      end
    end
    
    #  Recent
    #  ======
    
    def handle_ticket_recent
      # prints recent activity of the tickets
      
      # if a valid ticket id is given then only the activity of that ticket is listed
      # note that this is based on the git commit history of the ticgit branch on the repository
      tic.ticket_recent(ARGV[1]).each do |commit|
        puts commit.sha[0, 7] + "  " + commit.date.strftime("%m/%d %H:%M") + "\t" + commit.message
      end
    end
    
    # Milestone
    # ==========

    # tic milestone
    # tic milestone migration1 (list tickets)
    # tic milestone -n migration1 3/4/08 (new milestone)
    # tic milestone -a {1} (add ticket to milestone)
    # tic milestone -d migration1 (delete)
    
    # TODO: Milestone is broken. Need to implement habndle_ticket_milestone
    def parse_ticket_milestone
      @options = {}
      OptionParser.new do |opts|
        opts.banner = "Usage: ti milestone [milestone_name] [options] [date]"
        opts.on("-n MILESTONE", "--new MILESTONE", "Add a new milestone to this project") do |v|
          @options[:new] = v
        end
        opts.on("-a TICKET", "--new TICKET", "Add a ticket to this milestone") do |v|
          @options[:add] = v
        end
        opts.on("-d MILESTONE", "--delete MILESTONE", "Remove a milestone") do |v|
          @options[:remove] = v
        end
      end.parse!
    end

    def parse_options! #:nodoc:     
      # validate that the arguments are not empty 
      if args.empty?
        warn "Please specify at least one action to execute."
        puts " list state show new checkout comment tag assign recent"
        exit
      end
      # if they are not then action is always the first argument
      @action = args.first
    end
    
    
    def just(value, size, side = 'l')
      value = value.to_s
      if value.size > size
        value = value[0, size]
      end
      if side == 'r'
        return value.rjust(size)
      else
        return value.ljust(size)
      end
    end
    
  end
end