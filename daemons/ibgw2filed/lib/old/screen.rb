module Screen
  def self.clear
    if $stdout.isatty then  
      print "\e[2J\e[f" 
    end
  end
end