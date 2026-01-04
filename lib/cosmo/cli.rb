# frozen_string_literal: true

require "yaml"
require "optparse"

module Cosmo
  class CLI
    def self.run(...)
      new.run(...)
    end

    def run(argv)
      options = parse(argv)
      load_config(options[:config_file])
      puts self.class.banner
      require_files(options[:require])
      create_streams
      Engine.run
    end

    private

    def parse(argv)
      options = {}
      parser = option_parser(options)
      parser.parse!(argv)
      options
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

    def create_streams
      Config[:streams].each do |name, config|
        Client.instance.maybe_create_stream(name, config)
      end
    end

    def require_files(path)
      return unless path

      if File.directory?(path)
        files = Dir[File.expand_path("#{path}/*.rb")]
        files.each { |f| require f }
      else
        require File.expand_path(path)
      end
    end

    def option_parser(options)
      parser = OptionParser.new do |o|
        o.on "-c", "--concurrency INT", "Threads to use" do |arg|
          options[:concurrency] = Integer(arg)
        end

        o.on "-r", "--require [PATH|DIR]", "Location of files to require" do |arg|
          options[:require] = arg
        end

        o.on "-t", "--timeout NUM", "Shutdown timeout" do |arg|
          options[:timeout] = Integer(arg)
        end

        o.on "-C", "--config PATH", "Path to config file" do |arg|
          options[:config_file] = arg
        end

        o.on "-s", "--setup", "Load config, create streams and exit" do
          load_config(options[:config_file])
          create_streams
          puts "Cosmo streams were created/updated"
          exit(0)
        end

        o.on "-v", "--version", "Print version and exit" do
          puts "Cosmo #{VERSION}"
          exit(0)
        end
      end

      parser.banner = "cosmo [options]"
      parser.on_tail "-h", "--help", "Show help" do
        puts parser
        exit(1)
      end

      parser
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
