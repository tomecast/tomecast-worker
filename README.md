# Spout-Worker
The spout worker is an automatic transcriber for podcasts
It will listen to a redis queue for messages
Once a message is recieved it will process it, and try to generate a transcript of the podcast.

The worker requires the following software to be installed

- ruby 2.x
- sox mp3 support - `sudo apt-get install libsox-fmt-mp3`
- sox - `sudo apt-get install sox`
- mono - http://www.mono-project.com/docs/getting-started/install/linux/


# Getting Started

`bundle install --path vendor/bundle`

The worker can be started by running the following command:

`REDIS_SERVER_URL="redis://ABC123" SPEECH_API_KEY=ABC123 GITHUB_API_KEY=ABC123 bundle exec sidekiq -r ./worker.rb -d -L logs/sidekiq.log`

Where `ABC123` is replaced by your redis url and api keys.

To test that the worker is working properly, you can modify the add-to-queue.rb file and then, in a seperate console window, you can run

`REDIS_SERVER_URL='redis://ABC123' bundle exec ruby ./add-to-queue.rb`

Which will add podcasts to the queue.


# Helpful commands/urls

- http://stefaanlippens.net/audio_conversion_cheat_sheet
- `sox test/serial-s01-e01.mp3 -c 1 -r 8000 out.wav trim 0 10`
- `mcs /reference:System.ServiceModel.dll /reference:System.Runtime.Serialization /reference:System.Web -r:SDK/Microsoft-IntelligentServices-Speech-Windows-1.0.3954923/SpeechSDK/x64/SpeechClient.dll Program.cs`

#TODO:
- generate a standard timing format (or compatible json version)
    - TTML - http://www.w3.org/TR/ttaf1-dfxp/
    - WebVTT - https://en.wikipedia.org/wiki/WebVTT