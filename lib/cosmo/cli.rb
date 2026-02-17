# frozen_string_literal: true

require "yaml"
require "optparse"

module Cosmo
  class CLI # rubocop:disable Metrics/ClassLength
    def self.run
      instance.run
    end

    def self.instance
      @instance ||= new
    end

    def run
      flags, command, options = parse
      load_config(flags[:config_file])
      puts self.class.banner
      boot_application
      require_path(flags[:require])
      Engine.run(command, options)
    end

    private

    def parse
      flags = {}
      parser = flags_parser(flags)
      parser.order!

      options = {}
      command = ARGV.shift
      parser = options_parser(command, options)
      parser&.order!

      [flags, command, options]
    end

    def load_config(path)
      raise ConfigNotFoundError, path if path && !File.exist?(path)

      unless path
        # Try default path
        default_path = File.expand_path(Config::DEFAULT_PATH)
        path = default_path if File.exist?(default_path)
      end

      Config.load(path)
    end

    def boot_application
      boot_path = File.expand_path("config/boot.rb")
      require boot_path if File.exist?(boot_path)

      environment_path = File.expand_path("config/environment.rb")
      require environment_path if File.exist?(environment_path)
    end

    def require_path(path)
      if path
        require_files(path)
        return # If a path is provided don't load default dirs.
      end

      # Load files from app/streams if they exist.
      # Streams are always eagerly loaded since they register classes to process events.
      require_files("app/streams") if File.directory?("app/streams")
    end

    def flags_parser(flags) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      OptionParser.new do |o| # rubocop:disable Metrics/BlockLength
        o.banner = "Usage: cosmo [flags] [command] [options]"
        o.separator ""
        o.separator "Command:"
        o.separator "  jobs      Run jobs"
        o.separator "  streams   Run streams"
        o.separator "  actions   Run actions"
        o.separator ""
        o.separator "Flags:"

        o.on "-c", "--concurrency INT", Integer, "Threads to use" do |arg|
          flags[:concurrency] = arg
        end

        o.on "-r", "--require PATH|DIR", "Location of files to require" do |arg|
          flags[:require] = arg
        end

        o.on "-t", "--timeout NUM", Integer, "Shutdown timeout" do |arg|
          flags[:timeout] = arg
        end

        o.on "-C", "--config PATH", "Path to config file" do |arg|
          flags[:config_file] = arg
        end

        o.on "-S", "--setup", "Load config, create streams and exit" do
          load_config(flags[:config_file])

          Config[:streams].each do |name, config|
            Client.instance.stream_info(name)
          rescue NATS::JetStream::Error::NotFound
            Client.instance.create_stream(name, config)
          end

          puts "Cosmo streams were created/updated"
          exit(0)
        end

        o.on_tail "-v", "--version", "Print version" do
          puts "Cosmo #{VERSION}"
          exit(0)
        end

        o.on_tail "-h", "--help", "Show help" do
          puts o
          exit(0)
        end
      end
    end

    def options_parser(command, options) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      case command
      when "jobs"
        OptionParser.new do |o|
          o.banner = "Usage: cosmo jobs [options]"

          o.on "--stream NAME", "Job's stream" do |arg|
            options[:stream] = arg
          end

          o.on "--subject NAME", "Job's subject" do |arg|
            options[:subject] = arg
          end
        end
      when "streams"
        OptionParser.new do |o|
          o.banner = "Usage: cosmo streams [options]"
          o.separator ""
          o.separator "  [m] many processors can be specified, in that case single options [1] are ignored"
          o.separator "  [1] options work only for a single processor"
          o.separator ""

          o.on "--processors NAMES", "[m] Specify processors names with comma" do |arg|
            options[:processors] = arg.split(",")
          end

          o.on "--stream NAME", "[1] Specify stream name" do |arg|
            options[:stream] = arg
          end

          o.on "--subject NAME", "[1] Specify subject name" do |arg|
            options[:subject] = arg
          end

          o.on "--consumer_name NAME", "[1] Specify consumer name" do |arg|
            options[:consumer_name] = arg
          end

          o.on "--batch_size NUM", Integer, "[1] Number of messages in the batch" do |arg|
            options[:batch_size] = arg
          end
        end
      when "actions"
        OptionParser.new do |o|
          o.banner = "Usage: cosmo actions [options]"

          o.on "-n", "--nop", "Do nothing and exit" do
            exit(0)
          end
        end
      end
    end

    def require_files(path)
      path = File.expand_path(path)

      if File.directory?(path)
        files = Dir["#{path}/**/*.rb"]
        files.each { |f| require f }
        return
      end

      require path
    end

    # rubocop:disable Layout/TrailingWhitespace,Lint/IneffectiveAccessModifier
    def self.banner
      <<-TEXT
                    .#%+:                                                  
                     ==-.                                       +.         
                       +:  .::::.                              :*-         
                     .=%%%%%%%%%%%%%#-                                     
                  .#%%%%%%%%##*+===+*#%%:                                  
                :##%%%%#:  :-::...::::. -%.                                
               +%%%**  :.             :+. -=.%:                         -  
              *%%%%: .-%%%#             ++ ---%.    -=                :==- 
              :%%%-  *%%%%               *- %:#+   =%%%.             .====:
          .%@%+.##.  #%%:                -+ =-=-    *%%:  .            :=  
          =*%%%=-#.                      :: =-:     *%-%%%%%#              
          .%=##* #-                         %.     :%%-+++%%%:             
           +=*+= +%.                      .*.   .=+.%%-#%%#*+:             
            ===: =*%=                   .*+  *%+%%% -%*:%%%%%:       .     
                 =***%*.            .:#*:  .%%*+%%%#.+%+. .          =     
           -%#-:        -*########+   .:   +%%%=%%%*++:                    
        .##:---.  :%%-  *: +%%%%%%%%%%%##. -#%%*= =-                       
         *#:-: :%%%%+%%= --%%#. -#%%%%+=#-   =:            .:::::::::::::: 
         :#- =%%%%%%%+++. +*%=-%%%%#-..       ..:::::::::::::..            
            +***+:=***::  ==:.      ....::..                               
         -%%%%%+%%-         ....               .     +##%%=  .#%%%%%%%#.   
        .%%%%##=%%-               :+#%%%#. *%%%%+   -%%%%%= .%%%%%%%%%%%   
         -+--         -=#%#+:   +%%%%%%%#. *%%%%%+  #%%%%%= =%%%*   %%%%.  
           .-+###.  *%%%%%%%%+ -%%%%+.     *%%%%%%:*%%%%%%+ -%%%*   %%%%.  
        .*%%%%%%%  %%%%+.=%%%# =%%%%-      *%%%%%%%%%%*%%%+ -%%%*   %%%%.  
       =%%%%%#=:. :%%%#  .%%%#  #%%%%%%%:  +%%%-*%%%%:=%%%+ -%%%*   %%%%.  
      -%%%%-      .%%%#   %%%%    .#%%%%%= +%%%- #%%= -%%%+ -%%%*  .%%%%.  
      *%%%#       .%%%#.  %%%%       +%%%* +%%%-      -%%%+  #%%%###%%%*   
      %%%%*        %%%#.  #%%%..****#####- =###-      -###+   =######*.    
      #%%%#        #%%%*+*#%%* .########:  =#*=:                           
      +%%%%-   .=+ .########=   :----.           .:::--====++++********### 
      .#%#########:  :==-:          ..:--=====---::::..                    
       .########+.         .:--=--::.                                      
          :--.       .---:.                                                
                 :.                                                        
      TEXT
    end
    # rubocop:enable Layout/TrailingWhitespace,Lint/IneffectiveAccessModifier
  end
end
