{% set proxy = salt['pillar.get']('virl:proxy', salt['grains.get']('proxy', False)) %}
{% set http_proxy = salt['pillar.get']('virl:http_proxy', salt['grains.get']('http_proxy', 'https://proxy.esl.cisco.com:80/')) %}
{% set crypt = salt['pillar.get']('restrictedusers:consul:crypt', salt['grains.get']('consul_crypt', '*')) %}

/usr/local/bin/consul:
  file.managed:
    - name: /tmp/consul.zip
    - source: https://dl.bintray.com/mitchellh/consul/0.5.2_linux_amd64.zip
    - source_hash: md5=37000419d608fd34f0f2d97806cf7399
  module.run:
    - name: archive.unzip
    - zip_file: /tmp/consul.zip
    - dest: /usr/local/bin
    - require:
      - file: /usr/local/bin/consul

consul group:
  group.present:
    - name: consul

consul user:
  user.present:
    - require:
      - group: consul group
    - fullname: Consul user
    - shell: /bin/bash
    - home: /home/consul
    - groups:
      - consul
    - password: {{ crypt }}

{% for consuldir in ['/etc/consul.d/bootstrap','/etc/consul.d/server','/etc/consul.d/client','/var/consul'] %}
{{consuldir}}:
  file.directory:
    - require:
      - user: consul user
    - user: consul
    - group: consul
    - makedirs: True

{% endfor %}

python-consul for salt-consul:
  pip.installed:
    - name: python-consul
    {% if proxy == true %}
    - proxy: {{ http_proxy }}
    {% endif %}

/srv/salt/_modules/consul_mod.py:
  file.managed:
    - source: salt://common/consul/files/consul_mod.py

/srv/salt/_states/consul_check.py:
  file.managed:
    - source: salt://common/consul/files/consul_check.py

/srv/salt/_states/consul_key.py:
  file.managed:
    - source: salt://common/consul/files/consul_key.py

/srv/salt/_states/consul_service.py:
  file.managed:
    - source: salt://common/consul/files/consul_service.py

