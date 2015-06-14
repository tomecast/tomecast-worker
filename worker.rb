require 'open-uri'
require 'open3'
require 'fileutils'

#retrieve podcast metadata from queue.
podcast_filename = 'ColbertPodcast.mp3'
title = 'ColbertPodcast'

#clear up temp folders
FileUtils.rm_rf Dir.glob("transcript/*")
FileUtils.rm_rf Dir.glob("segments/*")
FileUtils.rm_rf Dir.glob("podcast/*")


### Compile SpeechSDK Transcriber
command = "mcs /reference:System.ServiceModel.dll /reference:System.Runtime.Serialization /reference:System.Web -r:SpeechSDK/x64/SpeechClient.dll Program.cs"

Open3.popen3(command,:chdir=>'transcribe') do |stdin, out, err, external|
  # Create a thread to read from each stream
  { :stdout => out, :stderr => err }.each do |key, stream|
    puts "redirecting #{key.to_s}"
    Thread.new do
      until (line = stream.gets).nil? do
        puts "#{key} --> #{line}"
      end
    end
  end

  # Don't exit until the external process is done
  external.join
  if external.value.success?
    puts 'successfully compiled transcriber'
  else
    puts 'compile failed.'
  end

end

#### Download the podcast

# File.open("podcasts/", "wb") do |saved_file|
#   # the following "open" is provided by open-uri
#   open("http://somedomain.net/flv/sample/sample.flv", "rb") do |read_file|
#     saved_file.write(read_file.read)
#   end
# end


#### Split the podcast into multiple segments
# spliting the podcast into single channel audio with 8000 rate
command = "sox podcast/#{podcast_filename} -c 1 -r 8000 segments/segment.wav trim 0 10 : newfile : restart "


Open3.popen3(command) do |stdin, out, err, external|
  # Create a thread to read from each stream
  { :stdout => out, :stderr => err }.each do |key, stream|
    puts "redirecting #{key.to_s}"
    Thread.new do
      until (line = stream.gets).nil? do
        puts "#{key} --> #{line}"
      end
    end
  end

  # Don't exit until the external process is done
  external.join
  if external.value.success?
    puts 'successfully split files'
  else
    puts 'splitting files caused an error.'
  end

end


## Send each segment to the Transcriber
# "3db0f094a68741b6b7c26d46313d1cd6"

responses = []
Dir['segments/*'].sort().each do |file_name|
  next if File.directory? file_name

  p file_name
  index = File.basename(file_name,File.extname(file_name))[7..-1].to_i
  index = index -1;

  command = "mono transcribe/Program.exe 'https://speech.platform.bing.com/recognize' '#{file_name}' '3db0f094a68741b6b7c26d46313d1cd6'"
  Open3.popen3(command) do |stdin, out, err, external|
    # Create a thread to read from each stream
    { :stdout => out, :stderr => err }.each do |key, stream|
      puts "redirecting #{key.to_s}"
      Thread.new do
        until (line = stream.gets).nil? do
          puts "#{key} --> #{line}"

          if(key == :stdout)
            responses.insert(index, line)
          end
        end
      end
    end
    # Don't exit until the external process is done
    external.join
    if external.value.success?
      puts 'successfully transcribed file'
    else
      puts 'an error occured while transcribing file'
    end
  end
end

responses = responses.compact
## merge the response segments into a coherent transcript
segments = {}
require 'json'
responses.each_with_index do |response, index|
  next unless response
  segment = JSON.parse(response)
  next unless segment
  next if segment['header']['status'] == 'error'
  segments[index*10] = {
      'requestid' => segment['header']['properties']['requestid'],
      'confidence' => segment['results'][0]['confidence'],
      'timestamp' => index*10,
      'content' => segment['results'][0]['name']
  }
end

#add header information
transcript = {
    'episode_name' => title,
    'episode_no' => 1,
    'date' => 'rfc3339',
    'episode_url' => 'http://www.google.com',
    'podcast_url' => 'http://www.google.com',
    'segments' => segments,
}

#write the file in github.
File.open('transcript/colbert.json', 'w') { |file| file.write(JSON.pretty_generate(transcript)) }
