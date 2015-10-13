from python:2.7

# install ruby 2.1.5
# instructions from https://stackoverflow.com/questions/18490591/how-to-install-ruby-2-on-ubuntu-without-rvm?answertab=active#tab-top

workdir /tmp
run \
    apt-get -y update && \
    apt-get -y install wget build-essential zlib1g-dev libssl-dev libreadline6-dev libyaml-dev

# install sox and mp3 format support
run \
    apt-get -y install libsox-fmt-mp3 sox

# copy the application files to the image
#workdir /srv/tomecast-worker
#copy . /srv/tomecast-worker/
#run bundle install --path vendor/bundle

run apt-get -y install build-essential python-dev python-setuptools \
    libatlas-dev libatlas3gf-base \
    libatlas-base-dev gfortran \
    python-matplotlib libgsl0-dev
run apt-get -y install python-sklearn
run pip install numpy==1.7.2
run pip install scipy simplejson
run pip install -U matplotlib
run pip install eyeD3-pip==0.6.19
run pip install -U scikits.talkbox
run pip install 'http://tcpdiag.dl.sourceforge.net/project/mlpy/mlpy%203.5.0/mlpy-3.5.0.tar.gz'
run pip install -U scikit-learn

workdir /srv/
run git clone https://github.com/tyiannak/pyAudioAnalysis.git

run rm pyAudioAnalysis/data/diarizationExample.segments
run rm pyAudioAnalysis/data/diarizationExample2.segments

#finish up
cmd ["bundle", "exec", "sidekiq", "-r", "./worker.rb", "-c","1"]