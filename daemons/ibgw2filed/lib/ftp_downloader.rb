class FtpDownloader
  attr_reader :config

  def initialize(config=Configuration.new(filename: 'ftp.yml'}))
    @config = config
  end

  def download_file
    temp = Tempfile.new(config.filename)
    tempname = temp.path
    temp.close
    Net::FTP.open(config.host,
                  config.login,
                  config.password) do |ftp
      ftp.getbinaryfile(File.join(config.path, config.filename), tempname)
    end
    tempname
  end
end
