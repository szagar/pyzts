require 'yaml'

class Configuration
  attr_reader :data

  def initialize(args={})
    args = defaults.merge(args)
    @data = YAML::load_file(File.join(args[:path],
                                      args[:filename]))
    define_methods_for_environment(args[:env])
  end

  def define_methods_for_environment(env)
    data[env].each do |name,value|
      instance_eval <<-COS
        def #{name}                 # def host
          "#{value}"                #   "localhost"
        end                         # end
      COS
    end
  end

  def defaults
    {env:      'production',
     path:     File.join(ENV['ZTS_HOME'],'etc'),
     filename: 'config.yml'}
  end
end
