# require 'net/http'
# require 'uri'
# require 'rest-client'
# require 'json'
# require 'securerandom'
# class Transcribe
# #curl -X POST --data-binary @recording.wav \
# #  --header 'Content-Type: audio/x-wav; rate=16000;' \
# #     'https://www.google.com/speech-api/v2/recognize?lang=en-gb'
# end
#

contents = File.readlines('keys.yaml').each {|l| l.chomp!}.uniq!

File.open('keys_unique.yaml', 'w') { |file|
  contents.each {|key|
    file.write(key + "\n")
  }
}