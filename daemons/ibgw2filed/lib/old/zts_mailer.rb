class ZtsMailer
end

__END__
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  address:              'smtp.gmail.com',
  port:                 587,
  domain:               'example.com',
  user_name:            '<username>',
  password:             '<password>',
  authentication:       'plain',
  enable_starttls_auto: true 
}



mail = Mail.new do
       to 'mikel@test.lindsaar.net'
     from 'ada@test.lindsaar.net'
  subject 'testing sendmail'
     body 'testing sendmail'
end

mail.deliver

end
