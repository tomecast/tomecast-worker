require 'open-uri'
require 'open3'
require 'fileutils'
require 'uri'
require 'logger'
require_relative 'lib/helpers/tomecast_logger'
require_relative 'lib/microsoft_project_oxford/transcribe'

class Processor
  include TomecastLogger

  def initialize(episode_local_path, metadata)
    @episode_local_path = episode_local_path
    @metadata = metadata
    @segments = []
  end


  def start()
    logger.info '## convert the podcast to a mono wav file (so that we can do speaker diarization on it'
    convert_to_wav

    logger.info '## run speaker diarization on the wav file to calculate the speech segments'
    calculate_segments

    logger.info '## parse speech segments from the podcast.seg file'
    parse_segments

    logger.info '## split audio file into segments and store in the segments folder'
    split_audio_into_segments

    logger.info '## transcribe segments using microsoft project oxford api'
    transcribe_segments

    logger.info '## coalesce transcription by merging all the segments into a json blob'
    coalesce_transcription

  end

  def convert_to_wav(wav_file='podcast/podcast.wav')
    command = "sox #{@episode_local_path} -r 16000 -b 16 -e signed-integer -c 1 #{wav_file}"

      Open3.popen3(command) do |stdin, out, err, external|
        # Create a thread to read from each stream
        { :stdout => out, :stderr => err }.each do |key, stream|
          logger.info "redirecting #{key.to_s}"
          Thread.new do
            until (line = stream.gets).nil? do
              logger.debug "#{key} --> #{line}"
            end
          end
        end

        # Don't exit until the external process is done
        external.join
        if external.value.success?
          logger.info 'successfully converted podcast to wav file'
        else
          raise 'converting to wav caused an error.'
        end

      end
  end

  def calculate_segments(wav_file='podcast/podcast.wav', seg_file='podcast/podcast.seg')
    command = "java -Xmx2024m -jar ./lib/lium/lium_spkdiarization-8.4.1.jar --fInputMask=./#{wav_file} --sOutputFormat=seg --sOutputMask=./#{seg_file} --doCEClustering podcast"

    Open3.popen3(command) do |stdin, out, err, external|
      # Create a thread to read from each stream
      { :stdout => out, :stderr => err }.each do |key, stream|
        logger.info "redirecting #{key.to_s}"
        Thread.new do
          until (line = stream.gets).nil? do
            logger.debug "#{key} --> #{line}"
          end
        end
      end

      # Don't exit until the external process is done
      external.join
      if external.value.success?
        logger.info 'successfully calculated speaker segments using diarization'
      else
        raise 'calculating segments caused an error.'
      end

    end
  end

  def parse_segments(seg_file='podcast/podcast.seg', warn_length=19, warn_gap=2)
    #hellointernet 766765 768117 hellointernet-7667.65-7681.17-F0-M-S1000
    #20071218_1900_1920_inter 1 0    322   M S U S0

    File.open(seg_file, 'r') do |f|
      f.each_line do |line|
        if(line.empty? || line.start_with?(';;'))
          next
        end

        #data = line.split(' ').last
        #name, start_segment, end_segment, ignore, gender, speaker = data.split('-')
        name, channel, start_segment, length_segment, gender, type, env, speaker = line.split(' ')
        @segments.push({
             :start_segment => (start_segment.to_f/100).round(2),
             :length_segment => (length_segment.to_f/100).round(2),
             :speaker => speaker
         })
      end
    end

    @segments = @segments.sort_by { |k| k[:start_segment] }

    #print warnings
    long_segments = []
    segment_gaps = []
    @segments.each_with_index {|segment, index|

      # - when the segment is more than 15s
      if(segment[:length_segment] >warn_length)
        long_segments.push(segment)
      end

      # - when there is a gap between segments of more than 5 seconds
      if(index > 0 && (segment[:start_segment] - (@segments[index-1][:start_segment] + @segments[index-1][:length_segment])) > warn_gap )

        segment_gaps.push({
          :segment_gap => (segment[:start_segment] - (@segments[index-1][:start_segment] + @segments[index-1][:length_segment])).round(2),
          :current_segment_start => segment[:start_segment],
          :prev_segment_end => @segments[index-1][:start_segment] + @segments[index-1][:length_segment]
        })
      end
    }

    if(!long_segments.empty?)
      long_segments = long_segments.sort_by { |k| k[:length_segment] }.reverse

      logger.warn "Found long segments:"
      long_segments.each {|segment|
        logger.warn("segment: #{segment[:start_segment]}, length: #{segment[:length_segment]}s")
      }
    else
      logger.info "No long segments found"
    end

    if(!segment_gaps.empty?)
      segment_gaps = segment_gaps.sort_by { |k| k[:segment_gap] }.reverse

      logger.warn "Found significant gap between segments:"
      segment_gaps.each {|segment|
        logger.warn("current segment: #{segment[:current_segment_start]}, previous segment end: #{segment[:prev_segment_end]}, length: #{segment[:segment_gap]}")
      }
    else
      logger.info "No significant gaps found between segments"
    end

  end

  def split_audio_into_segments(wav_file='podcast/podcast.wav')

    @segments.each do |segment_info|

      command = "sox #{wav_file} segments/segment-#{segment_info[:start_segment]}-#{segment_info[:length_segment]}.wav trim #{segment_info[:start_segment]} #{segment_info[:length_segment]}"

      Open3.popen3(command) do |stdin, out, err, external|
        # Create a thread to read from each stream
        { :stdout => out, :stderr => err }.each do |key, stream|
          logger.info "redirecting #{key.to_s}"
          Thread.new do
            until (line = stream.gets).nil? do
              logger.debug "#{key} --> #{line}"
            end
          end
        end

        # Don't exit until the external process is done
        external.join
        if external.value.success?
          logger.info "successfully extracted audio segment(#{segment_info[:start_segment]}s - #{segment_info[:start_segment] + segment_info[:length_segment]}s) from podcast"
        else
          raise 'extracting segment caused an error.'
        end
      end

    end

  end

  def transcribe_segments
    transcription_engine = Transcribe.new
    transcription_engine.start()
  end

  def coalesce_transcription


    begin
      metadata_pubdate = DateTime.rfc3339(@metadata[:pubdate]).strftime('%F')
    rescue ArgumentError
      # handle invalid date
      metadata_pubdate = DateTime.now().strftime('%F')
    end

    transcript_payload = {
        'title' => @metadata[:episode_title],
        'date' => metadata_pubdate,
        'description' => @metadata[:description],
        'episode_url' => @metadata[:episode_url],
        'slug' => cleaned_string(@metadata[:episode_title],'-')
    }

    transcript = {}
    @segments.each do |segment_info|
      begin
        transcript_segment_file = "transcript/segment-#{segment_info[:start_segment]}-#{segment_info[:length_segment]}.json"
        file_content_json = File.read(transcript_segment_file)
        transcript_info = JSON.parse(file_content_json)

        if transcript_info['header']['status'] == 'error'
          transcript[segment_info[:start_segment].to_s] = {
              'requestid' => transcript_info['header']['properties']['requestid'],
              'timestamp' => segment_info[:start_segment],
              'content' => ''
          }
        else
          transcript[segment_info[:start_segment].to_s] = {
              'requestid' => transcript_info['header']['properties']['requestid'],
              'confidence' => transcript_info['results'][0]['confidence'],
              'timestamp' => segment_info[:start_segment],
              'content' => transcript_info['results'][0]['name'],
              'speaker' => segment_info[:speaker]
          }
        end
      rescue
        #an error occured parsing the transcript, or the transcript doesnt exist.
        # create a nil tombstone.
        transcript[segment_info[:start_segment].to_s] = {
            'timestamp' => segment_info[:start_segment],
            'content' => '',
        }
      end
    end

    transcript_payload['segments'] = transcript
    return transcript_payload

  end




  #################################################################################################
  # Utilities
  def cleaned_string(raw, delim='_')
    raw.gsub(/^.*(\\|\/)/, '').gsub(/[^0-9A-Za-z.\-]/, ' ').strip().gsub(/\s+/, delim)
  end

end

# processor = Processor.new('podcast/48.mp3',{})
# # processor.parse_segments('podcast/podcast.seg', 20, 2)
# # processor.split_audio_into_segments
# #processor.start()
#
# processor.transcribe_segments