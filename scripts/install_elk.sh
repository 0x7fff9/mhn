#!/bin/bash

set -x
set -e

DIR=`dirname "$0"`
$DIR/install_hpfeeds-logger-json.sh

# install Java
apt-get install -y python-software-properties
add-apt-repository -y ppa:webupd8team/java
apt-get update
apt-get -y install oracle-java8-installer

# Install ES
wget -qO - https://packages.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb http://packages.elastic.co/elasticsearch/2.x/debian stable main" | sudo tee -a /etc/apt/sources.list.d/elasticsearch-2.x.list
apt-get update
apt-get -y install elasticsearch
sed -i '/network.host/c\network.host\:\ localhost' /etc/elasticsearch/elasticsearch.yml
service elasticsearch restart
update-rc.d elasticsearch defaults 95 10

# Install Kibana
mkdir /tmp/kibana
cd /tmp/kibana ;
wget https://download.elasticsearch.org/kibana/kibana/kibana-4.4.0-linux-x64.tar.gz
tar xvf kibana-4.4.0-linux-x64.tar.gz
sed -i '/0.0.0.0/c\host\:\ localhost' /etc/elasticsearch/elasticsearch.yml
mkdir -p /opt/kibana
cp -R /tmp/kibana/kibana-4*/* /opt/kibana/
rm -rf /tmp/kibana/kibana-4*

cat > /etc/supervisor/conf.d/kibana.conf <<EOF
[program:kibana]
command=/opt/kibana/bin/kibana
directory=/opt/kibana/
stdout_logfile=/var/log/mhn/kibana.log
stderr_logfile=/var/log/mhn/kibana.err
autostart=true
autorestart=true
startsecs=10
EOF

# Install Logstash

echo 'deb http://packages.elastic.co/logstash/2.2/debian stable main' | sudo tee /etc/apt/sources.list.d/logstash-2.2.x.list
apt-get update
apt-get install logstash
cd /opt/logstash

cat > /opt/logstash/mhn.conf <<EOF

input {
  file {
    path => "/var/log/mhn/mhn-json.log"
    start_position => "end"
    sincedb_path => "/opt/logstash/sincedb"
  }
}

filter {
  json {
    source => "message"
  }

  geoip {
      source => "src_ip"
      target => "src_ip_geo"
      database => "/opt/GeoLiteCity.dat"
      add_field => ["[src_ip_geo][location]",[ "%{[src_ip_geo][longitude]}" , "%{[src_ip_geo][latitude]}" ] ]
  }

  geoip {
    source => "dest_ip"
    target => "dest_ip_geo"
    database => "/opt/GeoLiteCity.dat"
    add_field => ["[dest_ip_geo][location]",[ "%{[dest_ip_geo][longitude]}" , "%{[dest_ip_geo][latitude]}" ] ]
  }
}

output {
  elasticsearch {
    hosts => "127.0.0.1:9200"
    index => "mhn-%{+YYYYMMddHH00}"
    document_type => "event"
  }
}
EOF

cat > /opt/logstash/mhn-template.json <<EOF
{
    "template" : "mhn-*",
    "mappings" : {
      "event" : {
        "properties": {
            "dest_port": {"type": "long"},
            "src_port": {"type": "long"},
            "src_ip": {"type": "ip"},
            "dest_ip": {"type": "ip"},
            "src_ip_geo":{
               "properties":{
                "location":{"type":"geo_point"}
               }
            },
            "dest_ip_geo":{
               "properties":{
                "location":{"type":"geo_point"}
               }
            }
        }
      }
    }
}
EOF

cat > /etc/supervisor/conf.d/logstash.conf <<EOF
[program:logstash]
command=/opt/logstash/bin/logstash -f mhn.conf
directory=/opt/logstash/
stdout_logfile=/var/log/mhn/logstash.log
stderr_logfile=/var/log/mhn/logstash.err
autostart=true
autorestart=true
startsecs=10
EOF

supervisorctl update
